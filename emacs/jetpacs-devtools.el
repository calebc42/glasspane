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
;; Zero wire cost either way: this module observes one seam and two
;; advised functions and never sends anything itself.

;;; Code:

(require 'cl-lib)
(require 'backtrace)
(require 'jetpacs-shell)

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
