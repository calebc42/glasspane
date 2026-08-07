;;; jetpacs-devtools.el --- Push-loop profiler + failure flight recorder -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The measurement layer, ported from poc-v1 `jetpacs-devtools.el' and
;; grown a flight recorder.  Two halves, separately switched:
;;
;; PROFILER (`jetpacs-devtools-profile', on by default) — per-surface
;; builder wall clock, outbound push counts and serialized sizes, and
;; the push-storm tripwire for the builder-that-retriggers-itself
;; class of bug.  Timings, counts, and sizes are metadata, so SPEC
;; 23.3 does not constrain them — but sizing is not free: each push is
;; serialized once more to measure it (the GATE 5 measure), single-
;; digit milliseconds at typical spec sizes and tens of milliseconds
;; near the frame budget.  Disable the profile if that matters.
;;
;; FLIGHT RECORDER (`jetpacs-devtools-recording', OFF by default) —
;; the home the scrubbed error path never had.  SPEC 23.3 makes every
;; loud channel print only the error SYMBOL (`jetpacs-error-label'):
;; the app card, *Messages*, the wire.  The morning this module was
;; born, that policy reduced a device-only home failure to the string
;; "error" with nowhere to look.  The recorder listens on the shell's
;; `jetpacs-shell-builder-error-functions' seam, which fires from
;; HANDLER-BIND context — the stack is still standing — so it can keep
;; what the label drops: the full condition, a real backtrace, and the
;; failing screen's identity, as inspectable Lisp data.  The last spec
;; each surface built rides the same setting: a spec EMBEDS payload
;; (the clip view renders the kill ring, buffer drills render buffer
;; text), so retaining one is payload capture, not metadata — it is
;; kept only while the recorder is on, and dropped with the records
;; when it turns off.
;;
;; The recorder is §23.3's "explicit developer setting" made literal:
;; detailed payload capture is legal ONLY behind such a setting, and
;; what is kept "MUST be bounded in size and lifetime" — hence off by
;; default, a hard entry cap (`jetpacs-devtools-record-limit'), and a
;; TTL (`jetpacs-devtools-record-ttl').  Nothing recorded here ever
;; crosses the wire or reaches a log; the report renders into a local
;; buffer on demand.  Enabling the recorder while a privacy-sensitive
;; trigger source (SPEC 21.4) is live is the developer's own call —
;; the setting exists so that call is explicit.
;;
;; INSPECTOR (`jetpacs-devtools-inspect', no setting at all) — the
;; third half, and the only one that answers "what is this screen
;; MADE of".  A Jetpacs screen is a Lisp datum: the builder returns a
;; spec, the spec is a plist of plists and vectors, and the device is
;; a rendering of it.  The inspector closes that loop for a human —
;; build the spec fresh, pretty-print it into a buffer, and show the
;; buffer through the Tier-0 renderer so the data is readable ON THE
;; PHONE, then hand it straight back with `jetpacs-shell-push'
;; `:spec'.  Inspect, edit the sexp, push it: the whole round trip and
;; not one line of new machinery on the return leg.
;;
;; It is CAPTURE ON DEMAND, and that is a deliberate refusal of the
;; retention above.  `jetpacs-devtools--specs' already holds a spec
;; per surface — but only while the recorder is on, which is a
;; developer setting that is OFF by default and may be off right now,
;; and what it holds is the spec of some PAST build.  Reading it would
;; make the inspector answer "nothing" on a healthy session and answer
;; STALE on a recording one.  So the inspector builds; the retention
;; is the flight recorder's business and stays that way.
;;
;; Zero wire cost for the first two: this module observes one seam and
;; two advised functions and never sends anything itself.  The
;; inspector sends exactly what any drill-in sends — a buffer.

;;; Code:

(require 'cl-lib)
(require 'backtrace)
(require 'pp)
(require 'jetpacs-shell)
(require 'jetpacs-navigate)

(defgroup jetpacs-devtools nil
  "Instrumentation for the Jetpacs push loop."
  :group 'jetpacs)

(defcustom jetpacs-devtools-profile t
  "When non-nil, record builder timings, push counts, and push sizes.
Metadata only — no payload, so SPEC 23.3 leaves it unconstrained.
Sizing serializes each pushed spec once more (see the Commentary for
the real cost); disable if a profiler fingers the recorder itself."
  :type 'boolean :group 'jetpacs-devtools)

(defcustom jetpacs-devtools-recording nil
  "When non-nil, keep full detail for builder and gate failures.
This is the SPEC 23.3 \"explicit developer setting\": while enabled,
the flight recorder retains each failure's condition object,
`error-message-string' (which may embed the offending datum), a
backtrace, the failing surface/screen, and each surface's last built
spec — locally, in bounded storage, never on the wire and never in a
log.  OFF by default, as 23.3 requires.  Turning it off — by any
path: `jetpacs-devtools-toggle-recording', the device Settings
screen, or `setopt' — clears everything it retained; the :set below
is what makes the Settings path keep that promise."
  :type 'boolean :group 'jetpacs-devtools
  :set (lambda (sym val)
         (set-default sym val)
         (unless val
           (when (boundp 'jetpacs-devtools--records)
             (setq jetpacs-devtools--records nil))
           (when (boundp 'jetpacs-devtools--specs)
             (clrhash jetpacs-devtools--specs)))))

(defcustom jetpacs-devtools-record-limit 32
  "Most failure records kept; older entries fall off (SPEC 23.3 size bound)."
  :type 'natnum :group 'jetpacs-devtools)

(defcustom jetpacs-devtools-record-ttl 3600
  "Seconds a failure record survives (SPEC 23.3 lifetime bound).
Old entries are dropped whenever a record lands or the report renders."
  :type 'natnum :group 'jetpacs-devtools)

(defcustom jetpacs-devtools-storm-threshold 8
  "`surface.update' pushes within `jetpacs-devtools-storm-window' seconds
that trigger the push-storm warning.  A settled app pushes on user
action and data change; a builder that re-triggers every build pushes
continuously — the storm warning is the tripwire for that class of
bug.  The push history sizes itself to this threshold, so any value
can trip."
  :type 'natnum :group 'jetpacs-devtools)

(defcustom jetpacs-devtools-storm-window 10
  "Seconds of history the push-storm check considers."
  :type 'natnum :group 'jetpacs-devtools)

(defconst jetpacs-devtools--backtrace-max 12000
  "Octets of backtrace kept per record — part of the 23.3 size bound.")

(defconst jetpacs-devtools-inspect-max 65536
  "Octets of pretty-printed spec `jetpacs-devtools-inspect-buffer' shows.
A DEFENSIVE cap, not a wire bound — nothing here crosses the wire; the
Tier-0 renderer pages the buffer onto the device like any other, and
budgets it there.  What this bounds is the local buffer: a spec is
whatever a builder returned, a builder is user code, and an unbounded
`pp' of a pathological one is a wedged Emacs on a phone.  A cut is
ANNOUNCED in the buffer, never silent, and the full datum is always one
`jetpacs-devtools-capture-spec' call away in the REPL.")

;; --- State ------------------------------------------------------------------

(defvar jetpacs-devtools--builds (make-hash-table :test 'equal)
  "Surface -> plist (:last-ms N :max-ms N :count N :at TIME).")

(defvar jetpacs-devtools--specs (make-hash-table :test 'equal)
  "Surface -> the spec its builder last produced (a reference, not a copy).
Payload, not metadata: filled only while `jetpacs-devtools-recording'
is on, cleared when it turns off.")

(defvar jetpacs-devtools--pushes (make-hash-table :test 'equal)
  "Surface -> plist (:last-bytes N-or-nil :count N :at TIME).")

(defvar jetpacs-devtools--push-times nil
  "Recent push times (floats), newest first.
Capped at (max 64 `jetpacs-devtools-storm-threshold') entries, so the
storm check always has enough history to reach its threshold.")

(defvar jetpacs-devtools--storm-warned-at 0
  "Last storm warning time, rate-limiting to one per window.")

(defvar jetpacs-devtools--records nil
  "Failure records, newest first, bounded by limit and TTL.
Each is a plist (:at FLOAT :surface S :screen ID-or-nil :phase SYM
:symbol SYM :message STR :backtrace STR).")

;; --- The flight recorder (the `jetpacs-shell-builder-error-functions' seam) --

(defun jetpacs-devtools--prune-records (&optional now)
  "Enforce the 23.3 bounds: entry cap and TTL, as of NOW."
  (let ((cutoff (- (or now (float-time)) jetpacs-devtools-record-ttl)))
    (setq jetpacs-devtools--records
          (seq-take (seq-filter (lambda (r) (> (plist-get r :at) cutoff))
                                jetpacs-devtools--records)
                    jetpacs-devtools-record-limit))))

(defun jetpacs-devtools--record-failure (context err)
  "Keep ERR's full story for CONTEXT while the stack still stands.
Installed on `jetpacs-shell-builder-error-functions', so this runs
from HANDLER-BIND context — `backtrace-get-frames' here sees the
signal path, not the catch site.  A nil `jetpacs-devtools-recording'
makes this one variable test (the seam is always installed, the
developer setting gates the retention)."
  (when jetpacs-devtools-recording
    (push (list :at (float-time)
                :surface (plist-get context :surface)
                :screen (plist-get context :screen)
                :phase (or (plist-get context :phase) 'build)
                :symbol (if (consp err) (car err) err)
                :message (if (consp err) (error-message-string err)
                           (format "%s" err))
                :backtrace
                ;; A bare-symbol ERR is a synthesized failure (chrome's
                ;; non-node check): no signal happened, so the frames
                ;; here would be the CATCH SITE's loop, not the builder
                ;; — a misleading trace is worse than none.
                (if (not (consp err)) ""
                  (let ((bt (ignore-errors
                              (backtrace-to-string
                               (backtrace-get-frames
                                'jetpacs-devtools--record-failure)))))
                    (if (and bt (> (length bt)
                                   jetpacs-devtools--backtrace-max))
                        (substring bt 0 jetpacs-devtools--backtrace-max)
                      (or bt "")))))
          jetpacs-devtools--records)
    (jetpacs-devtools--prune-records)))

(defun jetpacs-devtools-toggle-recording ()
  "Flip the failure recorder; dropping to off clears everything it kept.
The clear rides the defcustom's :set — the same path the device
Settings toggle takes — so disabling the developer setting ends the
retention it authorized no matter which door it goes through."
  (interactive)
  (customize-set-variable 'jetpacs-devtools-recording
                          (not jetpacs-devtools-recording))
  (message "jetpacs-devtools: failure recording %s"
           (if jetpacs-devtools-recording "ON" "off")))

;; --- The profiler (advice, zero footprint elsewhere) ------------------------

(defun jetpacs-devtools--time-build (orig surface plist)
  "Around `jetpacs-shell--build': wall clock, keyed by SURFACE.
The timing is metadata and rides `jetpacs-devtools-profile'; the
built spec is PAYLOAD, so its retention (for
`jetpacs-devtools-last-spec' + `pp') rides the recorder's developer
setting instead.  Measurement never alters the build: it is
condition-cased away from the value path."
  (let ((t0 (float-time))
        (spec (funcall orig surface plist)))
    (ignore-errors
      (when jetpacs-devtools-profile
        (let ((ms (* 1000 (- (float-time) t0)))
              (rec (gethash surface jetpacs-devtools--builds)))
          (puthash surface (list :last-ms ms
                                 :max-ms (max ms (or (plist-get rec :max-ms)
                                                     0.0))
                                 :count (1+ (or (plist-get rec :count) 0))
                                 :at (current-time))
                   jetpacs-devtools--builds)))
      (when jetpacs-devtools-recording
        (puthash surface spec jetpacs-devtools--specs)))
    spec))

(defun jetpacs-devtools--storm-p (times now threshold window)
  "Non-nil when THRESHOLD of TIMES fall within WINDOW seconds before NOW.
Pure, for tests."
  (>= (cl-count-if (lambda (tm) (<= (- now tm) window)) times)
      threshold))

(defun jetpacs-devtools--note-push (surface spec)
  "Tally one outbound push of SPEC to SURFACE; watch for storms.
Size is the GATE 5 measure (`string-bytes' of the canonical JSON) —
POC 3 rents jsonrpc.el for framing, so exact encoded frame sizes never
surface; the spec's serialized size is the comparable number the size
gate itself budgets against."
  (when jetpacs-devtools-profile
    (ignore-errors
      (let ((rec (gethash surface jetpacs-devtools--pushes))
            (bytes (ignore-errors
                     (string-bytes (jetpacs-node->canonical-json spec))))
            (now (float-time)))
        (puthash surface (list :last-bytes bytes
                               :count (1+ (or (plist-get rec :count) 0))
                               :at (current-time))
                 jetpacs-devtools--pushes)
        (push now jetpacs-devtools--push-times)
        (let ((tail (nthcdr (max 63 (1- jetpacs-devtools-storm-threshold))
                            jetpacs-devtools--push-times)))
          (when tail (setcdr tail nil)))
        (when (and (jetpacs-devtools--storm-p
                    jetpacs-devtools--push-times now
                    jetpacs-devtools-storm-threshold
                    jetpacs-devtools-storm-window)
                   (> (- now jetpacs-devtools--storm-warned-at)
                      jetpacs-devtools-storm-window))
          (setq jetpacs-devtools--storm-warned-at now)
          (display-warning
           'jetpacs
           (format (concat "push storm: %d surface updates in %ds — a "
                           "builder may re-trigger every push; see "
                           "M-x jetpacs-devtools-report")
                   jetpacs-devtools-storm-threshold
                   jetpacs-devtools-storm-window)
           :warning))))))

(defun jetpacs-devtools--observe-push (orig client surface spec &rest keys)
  "Around `ebp-client-surface-update': note the push, then send unchanged."
  (jetpacs-devtools--note-push surface spec)
  (apply orig client surface spec keys))

;; --- Public surface ---------------------------------------------------------

(defun jetpacs-devtools-last-spec (surface)
  "The spec SURFACE's builder last produced, or nil.
The raw material for \"what did the Companion actually receive\"
questions; pretty-print it with `pp'.  Retained only while
`jetpacs-devtools-recording' is on — a spec embeds payload, so it
lives under the same developer setting as the failure records."
  (gethash surface jetpacs-devtools--specs))

(defun jetpacs-devtools-reset ()
  "Drop all instrumentation, records included."
  (interactive)
  (clrhash jetpacs-devtools--builds)
  (clrhash jetpacs-devtools--specs)
  (clrhash jetpacs-devtools--pushes)
  (setq jetpacs-devtools--push-times nil
        jetpacs-devtools--storm-warned-at 0
        jetpacs-devtools--records nil))

(defun jetpacs-devtools-report-buffer ()
  "Render the report into *jetpacs-devtools* and return the buffer.
Recorded strings are inserted inert — never through a format control —
per SPEC 23.2."
  (jetpacs-devtools--prune-records)
  (let ((buf (get-buffer-create "*jetpacs-devtools*"))
        (now (float-time)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Jetpacs devtools — %s\n" (format-time-string "%F %T"))
                (format "profile: %s   failure recording: %s\n\n"
                        (if jetpacs-devtools-profile "on" "OFF")
                        (if jetpacs-devtools-recording "ON" "off")))
        (insert (format "Pushes in last %ds: %d\n\n"
                        jetpacs-devtools-storm-window
                        (cl-count-if (lambda (tm)
                                       (<= (- now tm)
                                           jetpacs-devtools-storm-window))
                                     jetpacs-devtools--push-times)))
        (insert (format "Failures recorded: %d%s\n"
                        (length jetpacs-devtools--records)
                        (if jetpacs-devtools-recording ""
                          "  (recording is off — M-x \
jetpacs-devtools-toggle-recording)")))
        (dolist (r jetpacs-devtools--records)
          (insert (format "\n— %s  %s%s  [%s]\n"
                          (format-time-string "%T" (plist-get r :at))
                          (plist-get r :surface)
                          (if (plist-get r :screen)
                              (concat " / " (plist-get r :screen)) "")
                          (plist-get r :phase))
                  "  ")
          (insert (plist-get r :message))
          (insert "\n")
          (let ((bt (plist-get r :backtrace)))
            (unless (string-empty-p bt)
              (insert "  backtrace:\n")
              (dolist (line (split-string bt "\n" t))
                (insert "    ") (insert line) (insert "\n")))))
        (insert "\nSurfaces (last push):\n")
        (let (rows)
          (maphash (lambda (s rec) (push (cons s rec) rows))
                   jetpacs-devtools--pushes)
          (if (null rows)
              (insert "  (none observed)\n")
            (dolist (row (cl-sort rows #'> :key (lambda (r)
                                                  (or (plist-get (cdr r)
                                                                 :last-bytes)
                                                      0))))
              (insert (format "  %-28s %8s bytes  x%-4d %s\n"
                              (car row)
                              (or (plist-get (cdr row) :last-bytes) "?")
                              (plist-get (cdr row) :count)
                              (format-time-string
                               "%T" (plist-get (cdr row) :at)))))))
        (insert "\nBuilders (wall clock):\n")
        (let (rows)
          (maphash (lambda (s rec) (push (cons s rec) rows))
                   jetpacs-devtools--builds)
          (if (null rows)
              (insert "  (none observed)\n")
            (dolist (row (cl-sort rows #'> :key (lambda (r)
                                                  (plist-get (cdr r)
                                                             :last-ms))))
              (insert (format "  %-28s last %7.1f ms  max %7.1f ms  x%d\n"
                              (car row)
                              (plist-get (cdr row) :last-ms)
                              (plist-get (cdr row) :max-ms)
                              (plist-get (cdr row) :count))))))
        (insert "\nLast spec per surface (retained while recording is on): \
(pp (jetpacs-devtools-last-spec SURFACE))\n"))
      (special-mode))
    buf))

(defun jetpacs-devtools-report ()
  "Render and display the devtools report."
  (interactive)
  (display-buffer (jetpacs-devtools-report-buffer)))

;; --- The inspector: the spec is data, and the data is yours ------------------

(defun jetpacs-devtools--resolve-root (surface)
  "The live root id SURFACE names, or nil when nothing registers one.
`jetpacs-shell-roots' is the PUBLIC read of the registry — the same one
the launcher builds its app list from, so \"a surface you can inspect\"
and \"a surface you can switch to\" are the same set by construction.
An exact id wins; a bare owner falls back to its D1 `app:<owner>'
spelling, so a REPL caller may type `\"hub\"'."
  (and (stringp surface)
       (let ((roots (jetpacs-shell-roots)))
         (cond ((assoc surface roots) surface)
               ((assoc (concat "app:" surface) roots) (concat "app:" surface))))))

(defun jetpacs-devtools-capture-spec (surface)
  "Build SURFACE's registered root FRESH, right now, and return the spec.
Nil when nothing registers SURFACE.

CAPTURE ON DEMAND.  This deliberately does NOT read
`jetpacs-devtools--specs' (nor its accessor `jetpacs-devtools-last-spec'):
that retention is RECORDING-GATED and the recorder is off by default —
so it may hold nothing at all, and when it holds something it holds the
spec of a PAST build.  \"What does this screen look like as data, now\"
is a question a build answers and a cache does not.

The capture route is `jetpacs-shell--build' called with the registry's
own entry plist — literally the two lines `jetpacs-shell-push' runs
before it reaches the gates.  That is the LEAST new seam available:
zero new code in the shell, and the spec you read here is the spec the
device would be sent, degrade included (a crashing builder yields its
error view rather than signalling out of an inspection).  Calling the
root's `:builder' directly would have to re-create by hand the three
things that build wraps it in — the registered owner binding, the ONE
per-document id-claim table, and the degrade — which is more new code
for a spec that is no longer the one the phone gets.  Devtools is
already the module that reaches into this function; it advises it.

The measurement is left ALONE: the profiler and the recorder are bound
off across the build, so an inspection does not land in the wall-clock
tally, does not count toward the push-storm history, and — the part
that matters under SPEC 23.3 — creates no payload retention of its own.
Inspecting is reading, not recording."
  (when-let* ((id (jetpacs-devtools--resolve-root surface))
              (entry (alist-get id jetpacs-shell--roots nil nil #'equal)))
    (let ((jetpacs-devtools-profile nil)
          (jetpacs-devtools-recording nil))
      (jetpacs-shell--build id entry))))

(defun jetpacs-devtools-inspect-buffer (surface)
  "Pretty-print SURFACE's freshly built spec into a buffer; return it.
Nil when nothing registers SURFACE.  The buffer is
\"*jetpacs-inspect: SURFACE*\" and it OPENS WITH THE DATUM: point-min is
the spec's own open paren, so `C-M-f', `C-x C-e', and a plain kill of
the whole form all work without stepping over a preamble.  The prose —
provenance, the push-back recipe, any truncation notice — trails below
as Lisp comments.

The loop the prose describes needs no code on its return leg:

    ;; on the phone, or here
    (jetpacs-devtools-inspect \"app:hub\")
    ;; edit the sexp — retitle the top bar, drop a node, add a button
    (jetpacs-shell-push \"app:hub\" :spec EDITED)

`jetpacs-shell-push' has taken a `:spec' override since the first cut,
so the edited datum goes back exactly the way the builder's would have.
Homoiconic all the way down: the screen is a value, and a value can be
read, changed, and returned."
  (when-let* ((id (jetpacs-devtools--resolve-root surface)))
    (let* ((spec (jetpacs-devtools-capture-spec id))
           (text (pp-to-string spec))
           (full (string-bytes text))
           (cut (> full jetpacs-devtools-inspect-max))
           (buf (get-buffer-create (format "*jetpacs-inspect: %s*" id))))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          ;; Chars never outnumber octets, so a char-count substring is
          ;; always inside the octet cap.
          (insert (if cut (substring text 0 jetpacs-devtools-inspect-max) text))
          (unless (bolp) (insert "\n"))
          (when cut
            (insert (format "\n;; TRUNCATED at %d of %d octets \
(jetpacs-devtools-inspect-max).\n\
;; The form above is INCOMPLETE — read the whole datum with\n\
;;   (pp (jetpacs-devtools-capture-spec %S))\n"
                            jetpacs-devtools-inspect-max full id)))
          (insert (format "\n;; %s — built %s, fresh (never a cached spec).\n\
;; The spec is DATA and the data is yours: edit the form above, then\n\
;;   (jetpacs-shell-push %S :spec EDITED)\n\
;; and the phone renders what you wrote.\n"
                          id (format-time-string "%F %T") id)))
        ;; Data, not a program: `lisp-data-mode' fontifies and indents it
        ;; without pretending the plist is a call form.  Left WRITABLE on
        ;; purpose — editing this buffer is half the point.
        (lisp-data-mode)
        (goto-char (point-min)))
      buf)))

(defun jetpacs-devtools-inspect (surface &optional target)
  "Show SURFACE's freshly built spec as Lisp, on the device and here.
Builds through `jetpacs-devtools-capture-spec', renders through
`jetpacs-devtools-inspect-buffer', and presents the result with
`jetpacs-navigate-buffer' — so the Tier-0 buffer renderer makes the
data phone-visible for free, exactly the way the Tools drawer's
*Messages* row already reads the Emacs log.  TARGET is the surface to
drill onto; nil takes the device flow's own (the surface the user
tapped from).

Returns the buffer, or nil when nothing registers SURFACE.  Never
signals: this is reachable from an action handler's continuation.

Interactively, completion is over the live root registry — on the
device that prompt is the Companion's own picker, because the dialog
bridge answers `completing-read' there."
  (interactive
   (list (completing-read "Inspect surface: "
                          (sort (mapcar #'car (jetpacs-shell-roots)) #'string<)
                          nil t)))
  (let ((buf (jetpacs-devtools-inspect-buffer surface)))
    (cond
     (buf (jetpacs-navigate-buffer buf target) buf)
     (t (jetpacs-shell-notify (format "No live surface named %s"
                                      (jetpacs-scalar-text (format "%s" surface)))
                              target)
        nil))))

(defun jetpacs-devtools--action-inspect (args params)
  "Handler for `jetpacs.devtools.inspect': ARGS `:surface', built now.
Resolution happens INSIDE the extent so an unknown name answers a
clean `rejected' — SPEC 14.4's permanent no — rather than deferring
work that has nothing to do.  The build and the drill are D2
continuation work: a builder is user code and may take as long as it
likes."
  (let ((surface (plist-get args :surface))
        (target (plist-get params :surface)))
    (if (not (jetpacs-devtools--resolve-root surface))
        'rejected
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (jetpacs-devtools-inspect surface target)
           (error (message "jetpacs-devtools: inspect failed: %s"
                           (jetpacs-error-label err))))))
      'accepted)))

(defun jetpacs-devtools--action-inspect-pick (_args params)
  "Handler for `jetpacs.devtools.inspect-pick': choose, then inspect.
The affordance's half of the pair — the Tools drawer row carries no
surface, because the interesting surface is whichever one is live when
you tap it.  The picker is a BRIDGED `completing-read' over the root
registry, raised from a `jetpacs-flow-continue' continuation for the
reason D2 exists: inside the dispatch extent prompting is banned, and
outside it the flow identity the continuation carries is what tells the
dialog floor to render the picker on the phone instead of a minibuffer
nobody is looking at."
  (let ((target (plist-get params :surface)))
    (jetpacs-flow-continue
     (lambda ()
       (let ((names (sort (mapcar #'car (jetpacs-shell-roots)) #'string<)))
         (if (null names)
             (jetpacs-shell-notify "No live surfaces to inspect" target)
           (let ((choice (condition-case nil
                             (completing-read "Inspect surface: " names nil t)
                           (quit ""))))
             (unless (string-empty-p choice)
               (condition-case err
                   (jetpacs-devtools-inspect choice target)
                 (error (message "jetpacs-devtools: inspect failed: %s"
                                 (jetpacs-error-label err))))))))))
    'accepted))

;; GLOBAL VERBS.  Devtools owns the actions and ZERO surfaces — the
;; affordance is a row in the hub's drawer, and an inspection is
;; legitimate from any screen — so the D1 scope exemption is declared
;; explicitly, the way `jetpacs.theme.modus-toggle' declares it.  The
;; :args/:doc schema is dogfooded here rather than described: the
;; inspector is the self-hosting program's own tool, and an action
;; editor reading `jetpacs-action-schema' can lay out this form.
(with-jetpacs-owner "jetpacs.devtools"
  (jetpacs-defaction "jetpacs.devtools.inspect"
                     #'jetpacs-devtools--action-inspect
                     :any-surface t
                     :args '((:name surface :type "text" :required t))
                     :doc "Show a live surface's spec, built fresh, as Lisp.")
  (jetpacs-defaction "jetpacs.devtools.inspect-pick"
                     #'jetpacs-devtools--action-inspect-pick
                     :any-surface t
                     :doc "Pick a live surface, then inspect its spec."))

;; The seam member is always installed; `jetpacs-devtools-recording'
;; gates the retention, so a live session pays one nil test per failure
;; until the developer setting turns the recorder on.
(add-hook 'jetpacs-shell-builder-error-functions
          #'jetpacs-devtools--record-failure)

;; The floor's reset seam: instrumentation is per-session state like any
;; other, so a fixture that resets the floor drops the records too.
(add-hook 'jetpacs-reset-functions #'jetpacs-devtools-reset)

(unless (advice-member-p #'jetpacs-devtools--time-build 'jetpacs-shell--build)
  (advice-add 'jetpacs-shell--build :around #'jetpacs-devtools--time-build))
(unless (advice-member-p #'jetpacs-devtools--observe-push
                         'ebp-client-surface-update)
  (advice-add 'ebp-client-surface-update :around
              #'jetpacs-devtools--observe-push))

(provide 'jetpacs-devtools)
;;; jetpacs-devtools.el ends here
