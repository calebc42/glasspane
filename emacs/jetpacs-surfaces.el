;;; jetpacs-surfaces.el --- Ownership, actions, and state over ebp.el -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The application-framework floor's registry half (rung JC-0 of
;; docs/PLAN-jetpacs-consumers.md; build spec docs/SPEC-JC-0-floor.md).
;; Rebuild-lite of poc-v1 `jetpacs-surfaces.el': the ownership registry
;; and action/state seams port; every transport seam re-wires onto
;; `ebp-client-*'.  ebp.el owns each SPEC 24.2 endpoint duty; this file
;; owns the registries the application layers share.
;;
;; Decisions (spec section 0):
;; - D1: per-owner surfaces `app:<owner>' — owner strings are wire
;;   identifiers, validated at claim time, stable across sessions.
;; - D2: an action handler MUST NOT block.  It runs inside jsonrpc.el's
;;   dispatch extent; its return value IS the protocol reply.  Prompts
;;   run from a `run-at-time' 0 continuation.
;; - Q1: single client.  `jetpacs-attach' errors on a second live client.
;; - Q3: a non-status handler return answers `rejected' with a loud
;;   warning — never a durable blanket-accept, never a bare -32603.
;; - Q4: `jetpacs-event-stale-p' is a helper a handler opts into; lag
;;   alone is not semantic staleness.
;; - Q5: state subscriptions key by bare widget id (app ids are already
;;   namespaced).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'ebp)

(defgroup jetpacs nil
  "The Jetpacs application layer over the EBP endpoint."
  :group 'ebp
  :prefix "jetpacs-")

;;;; Ownership

(defvar jetpacs-current-owner nil
  "The app/module id currently registering, or nil for anonymous core.
Bind with `with-jetpacs-owner'.  Under decision D1 an owner names the
surface `app:<owner>', so it is a wire identifier: ASCII letters,
digits, `.', `_', `-', at most 124 octets.")

(defcustom jetpacs-strict-namespaces nil
  "Non-nil makes a cross-owner registration clash an error.
Nil (the default) reports it with `display-warning' and lets the newer
registration win — the live-coding default."
  :type 'boolean
  :group 'jetpacs)

(defvar jetpacs--registrations (make-hash-table :test #'equal)
  "Map of (KIND . NAME) -> owner id, the attribution registry.")

(defvar jetpacs--claim-sites (make-hash-table :test #'equal)
  "Map of (KIND . NAME) -> the file that last claimed it.
Same-owner re-registration must stay SILENT for live coding (Caleb
re-evaluates a module constantly) while a second PACKAGE claiming the
same name must be loud.  The owner alone cannot tell those apart — two
authors who both pick a plausible owner collide silently and load order
decides the winner — so the defining file is the discriminator.")

(defconst jetpacs-reserved-owner-prefix "jetpacs."
  "Owner-name prefix RESERVED for base Jetpacs (audit R1, 2026-07-26).
Base owns `jetpacs.clip', `jetpacs.theme' and any future base surface;
a Tier-1 app MUST choose its own namespace.  Unqualified names are left
free precisely because a package author will reach for one, and under
D1 an owner is a permanent wire identifier — SPEC 13.5 keys the
device's persisted snapshot by surface id, so a collision is not a
local shadowing but two packages fighting over one device surface.")

(defun jetpacs--valid-owner-p (owner)
  "Non-nil when OWNER can name the surface `app:<owner>' (decision D1).
A SPEC 4.4 name component without `:' or `/' (so an owner is never
mistaken for a full surface id), short enough that the prefixed id fits
the 128-octet identifier cap."
  (and (stringp owner)
       (<= 1 (string-bytes owner) 124)
       (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._-]*\\'" owner)))

(defmacro with-jetpacs-owner (id &rest body)
  "Evaluate BODY with `jetpacs-current-owner' bound to ID.
ID is validated as a D1 owner (a wire identifier) at entry, so an
illegal owner fails at registration time, never as a push-time 1201."
  (declare (indent 1) (debug (form body)))
  `(let ((jetpacs-current-owner ,id))
     (unless (jetpacs--valid-owner-p jetpacs-current-owner)
       (error "jetpacs: invalid owner %S (want a SPEC 4.4 name, no `:'/`/')"
              jetpacs-current-owner))
     ,@body))

(defvar jetpacs--in-action-handler)     ; the dispatch marker, defined below

(defun jetpacs--claim (kind name)
  "Attribute KIND:NAME to `jetpacs-current-owner'; returns NAME.
A different-owner clash warns, or errors under
`jetpacs-strict-namespaces'.  Same-owner re-registration is silent.
No-op (no record) when no owner is bound."
  (when jetpacs-current-owner
    (unless (jetpacs--valid-owner-p jetpacs-current-owner)
      (error "jetpacs: invalid owner %S (want a SPEC 4.4 name, no `:'/`/')"
             jetpacs-current-owner))
    (let* ((key (cons kind name))
           (prior (gethash key jetpacs--registrations))
           (prior-site (gethash key jetpacs--claim-sites))
           ;; `buffer-file-name' follows `current-buffer', so a claim made
           ;; from inside a handler running `with-current-buffer' on a
           ;; file would record THAT file as the defining site and warn
           ;; spuriously on the next legitimate reload.  A dispatch has no
           ;; meaningful defining file; record none.
           (site (unless jetpacs--in-action-handler
                   (or load-file-name buffer-file-name))))
      (cond
       ;; A different owner: the pre-existing clash.
       ((and prior (not (equal prior jetpacs-current-owner)))
        (if jetpacs-strict-namespaces
            (error "jetpacs: %s %S already owned by %S (claiming as %S)"
                   kind name prior jetpacs-current-owner)
          (display-warning
           'jetpacs
           (format "%s %S re-registered by %S (was %S)"
                   kind name jetpacs-current-owner prior)
           :warning)))
       ;; SAME owner, DIFFERENT file: two packages picked one name.  This
       ;; was silent, and silence is the wrong default — the loser simply
       ;; stops working and load order decides which.  Re-evaluating the
       ;; SAME file stays silent, which is the live-coding case that
       ;; motivated the original silence.
       ((and prior site prior-site (not (equal site prior-site)))
        (if jetpacs-strict-namespaces
            (error "jetpacs: %s %S claimed as %S by %s, already claimed by %s"
                   kind name jetpacs-current-owner site prior-site)
          (display-warning
           'jetpacs
           (format "%s %S claimed as owner %S by %s — already claimed by %s; one of them will silently stop working (owner names are permanent wire identifiers; `%s' is reserved for base)"
                   kind name jetpacs-current-owner site prior-site
                   jetpacs-reserved-owner-prefix)
           :warning))))
      (puthash key jetpacs-current-owner jetpacs--registrations)
      (when site (puthash key site jetpacs--claim-sites))))
  name)

(defun jetpacs--owner-of (kind name)
  "The owner id recorded for KIND:NAME, or nil."
  (gethash (cons kind name) jetpacs--registrations))

(defun jetpacs--owned-names (kind owner)
  "Every NAME of KIND attributed to OWNER — the teardown enumerator."
  (let (names)
    (maphash (lambda (key own)
               (when (and (equal (car key) kind) (equal own owner))
                 (push (cdr key) names)))
             jetpacs--registrations)
    names))

(defun jetpacs--unclaim (kind name)
  "Drop the attribution record for KIND:NAME."
  (remhash (cons kind name) jetpacs--registrations)
  (remhash (cons kind name) jetpacs--claim-sites))

;;;; The client handle (single-client floor, decision Q1)

(defvar jetpacs-action-handlers (make-hash-table :test #'equal)
  "Global action name -> (ARGS PARAMS) handler, the load-time staging
table.  `jetpacs-attach' replays it into each new client's allowlist;
`jetpacs--action-shim' reads it at dispatch time, so a live-coded
re-`jetpacs-defaction' takes effect without re-registering.")

(defvar jetpacs--state-handlers (make-hash-table :test #'equal)
  "Map of widget id -> callback run with each reconciled new value.")

(defvar jetpacs--client nil
  "The single live `ebp-client', or nil.")

(defun jetpacs-client ()
  "The live client, or nil."
  jetpacs--client)

(defun jetpacs-client-or-error ()
  "The live client, or signal."
  (or jetpacs--client (error "jetpacs: no client attached")))

(defun jetpacs-window ()
  "The client's SPEC 20.1.1 window plist, or nil before any report.
Keys: :width_dp :height_dp :width_class :height_class — from the
welcome mirror and every `window.changed' since."
  (and (jetpacs-connected-p)
       (ebp-client-window (jetpacs-client))))

(defun jetpacs-window-class (axis)
  "The SPEC 20.1.1 size class for AXIS (:width or :height), a string.
compact/medium/expanded at the Material breakpoints.  Falls back to
compact width / medium height before any report — the phone-shaped
guess, honest for a first paint that may arrive before the welcome
mirror on an old Companion.  Hoisted from the M3 catalog: branching a
layout on the size class is platform behavior, not sample machinery."
  (or (plist-get (jetpacs-window)
                 (if (eq axis :width) :width_class :height_class))
      (if (eq axis :width) "compact" "medium")))

(defun jetpacs-connected-p ()
  "Non-nil when the attached client is past the SPEC 10.3 barrier."
  (and jetpacs--client (eq (ebp-client-state jetpacs--client) 'ready)))

(defun jetpacs-granted-p (capability &optional client)
  "Non-nil when the session granted CAPABILITY (a SPEC 22.1 name string).
CLIENT defaults to the attached client; with none the answer is nil —
fail closed.  The granted set is the welcome's raw decoded VECTOR
\(ebp.el keeps it unconverted), so `member' always misses; this is the
one place that membership test is spelled (B1: shell, dialog and
sections each hand-rolled it before).  A grant does not imply READY —
callers gate sends on `jetpacs-connected-p' separately, and in that
order: `granted' survives on a closed client struct and would lie."
  (when-let* ((client (or client (jetpacs-client))))
    (and (seq-contains-p (ebp-client-granted client) capability) t)))

(defun jetpacs-max-event-bytes (&optional client)
  "The session's declared `max_event_bytes', or nil with no client.
B11: the largest `event.action' the Companion will CREATE — anything
bigger dies device-side with only a local diagnostic, and Emacs never
learns.  The welcome limit was previously read NOWHERE, so a seed that
must round-trip as one event (an editor's `on_save', a submitted
value) had no bound to size itself against; `jetpacs-buffer-budgets'
is the PUSH bound and does not cover this.  SPEC 4.5 floors the value
at 262144 on any conforming Companion."
  (when-let* ((client (or client (jetpacs-client))))
    (plist-get (ebp-client-limits client) :max_event_bytes)))

(defun jetpacs-scalar-text (s)
  "S with every non-scalar char replaced by U+FFFD (SPEC 4.1).
Emacs stores an undecodable octet as a raw-byte char in
#x3FFF80..#x3FFFFF, and a lone surrogate as #xD800..#xDFFF; neither is a
Unicode scalar value, and `json-serialize' signals `wrong-type-argument'
on both.  Any user text that is not valid UTF-8 — a latin-1 kill, a
binary buffer slice, a mid-stream broken sequence — would otherwise
take down the whole push.  Promoted from the buffer renderer (JA-1) so
non-renderer emitters (clip, toast) need no jetpacs-buffer edge."
  (if (string-match-p "[\x3FFF80-\x3FFFFF\xD800-\xDFFF]" s)
      (replace-regexp-in-string "[\x3FFF80-\x3FFFFF\xD800-\xDFFF]" "�"
                                s t t)
    s))

;;;; The path sandbox (floor: every rung that opens a user file shares it)

(define-error 'jetpacs-path-refused "jetpacs: path refused by policy")

(defun jetpacs-local-paths (paths)
  "PATHS with every remote name dropped, tested on the RAW strings.
The filter runs BEFORE any caller stats, truenames, or opens a member,
because for a remote name the stat IS the connection: `file-truename',
`file-directory-p' or `file-readable-p' on /ssh:host:… dials the host,
inside whatever extent the caller occupies.  `tramp-connection-timeout'
is 60 seconds and a dispatch extent has no business waiting on one.

Callers deriving a root or file set from user configuration MUST route
it through here first (JA-4 audit P1-7: the guard below inspected the
ref's own name correctly and then handed unfiltered configuration to
`file-directory-p', so one remote agenda entry dialled TRAMP on every
single resolve)."
  (delq nil (mapcar (lambda (p)
                      (and (stringp p) (not (string-empty-p p))
                           (not (file-remote-p p)) p))
                    paths)))

(cl-defun jetpacs-check-path (file roots &key (require 'readable))
  "FILE validated against ROOTS, returned as a truename, or signal.
Signals `jetpacs-path-refused' with a one-symbol data list — `not-absolute',
`remote', `no-roots', `outside-roots', `unreadable', `not-a-directory' or
`exists'.  The symbol travels alone ON PURPOSE: an error raised here is
answered toward the device, and a path in its data is a §23.1 leak
\(`jetpacs--error-label' prints symbols).

REQUIRE selects the existence test applied AFTER containment, which is
the only part that differs between callers:
  `readable'  (default) an existing readable file or directory;
  `directory' an accessible directory — the browse case;
  `absent'    a path that does NOT exist — a rename/create TARGET, whose
              parent must still be inside a root, which containment
              already established because `file-truename' resolves the
              existing prefix and keeps the new tail literal;
  nil         containment only.
Containment never varies: widening the sandbox is not something a caller
should be able to ask for by passing a flag.

Guard order is load-bearing and is the whole point of this function:

  1. absolute-string shape, on the raw argument;
  2. `file-remote-p' on the RAW name — first, see `jetpacs-local-paths';
  3. truename BOTH sides, so a symlink cannot straddle the boundary;
  4. containment by `file-in-directory-p', which compares path COMPONENTS
     — /home/u/org-evil does not sit under /home/u/org, which a string
     prefix test would admit;
  5. readability last, since it is the only stat that must touch the file.

ROOTS is the caller's allowlist; an EMPTY root set refuses everything and
says so distinctly (`no-roots'), because \"unconfigured\" and \"out of
policy\" are different conditions and only the second is the caller's
fault.  ROOTS is filtered and truenamed here — callers pass raw
configuration.

Promoted to the floor at JA-6: `jetpacs-org' had the only copy, and the
files rung was about to grow a second one.  A guard that exists twice is
a guard that is correct once."
  (unless (and (stringp file) (not (string-empty-p file))
               (file-name-absolute-p file))
    (signal 'jetpacs-path-refused (list 'not-absolute)))
  (when (file-remote-p file)
    (signal 'jetpacs-path-refused (list 'remote)))
  (let ((true (file-truename file))
        (dirs (delq nil (mapcar (lambda (d)
                                  (and (file-directory-p d) (file-truename d)))
                                (jetpacs-local-paths roots)))))
    (unless dirs
      (signal 'jetpacs-path-refused (list 'no-roots)))
    (unless (cl-some (lambda (root) (file-in-directory-p true root)) dirs)
      (signal 'jetpacs-path-refused (list 'outside-roots)))
    (pcase require
      ('readable (unless (file-readable-p true)
                   (signal 'jetpacs-path-refused (list 'unreadable))))
      ('directory (unless (file-accessible-directory-p true)
                    (signal 'jetpacs-path-refused (list 'not-a-directory))))
      ('absent (when (file-exists-p true)
                 (signal 'jetpacs-path-refused (list 'exists))))
      ('nil nil)
      (_ (error "jetpacs-check-path: unknown :require %S" require)))
    true))

(defcustom jetpacs-toast-max-chars 300
  "Character ceiling for `jetpacs-toast' TEXT (SPEC 18.2).
A toast is transient presentation with no scroll and no action, so a
long string is unreadable on the device however it is delivered.  The
wire imposes no `toast.show' limit of its own — `text' is the one
uncapped text path in this layer, and every sibling emitter caps — so
the bound is ours: it keeps a stray `buffer-string' or a backtrace out
of a frame that only `max_frame_bytes' would otherwise refuse, taking
the whole send with it."
  :type 'natnum :group 'jetpacs)

(defun jetpacs-truncate-text (s max-chars)
  "S truncated to MAX-CHARS characters, an ellipsis marking the cut.
The ellipsis replaces the tail rather than being appended past the
bound, so the result never exceeds MAX-CHARS (the `jetpacs-buffer-cap-spans'
rule).  A nil or non-positive MAX-CHARS means no bound."
  (if (or (not (natnump max-chars)) (zerop max-chars)
          (<= (length s) max-chars))
      s
    (if (< max-chars 2)
        (substring s 0 max-chars)
      (concat (substring s 0 (1- max-chars)) "…"))))

(cl-defun jetpacs-toast (text &key duration-s)
  "Best-effort device toast (SPEC 18.2); returns t when sent, nil when not.
Gated on READY — `toast.show' is legal ONLY in R — and on the
`presentation.toast' grant; gated off it is a silent no-op (B7: a toast
is never load-bearing, and SPEC 18.2 makes it MUST-NOT-be the sole
report of a durable failure).  Validation is unconditional even when
gated off: a bad DURATION-S is a programmer error and must be loud.
A notification on the wire, so the W10 sender ceiling never refuses it."
  (unless (stringp text)
    (error "jetpacs-toast: TEXT must be a string, got %S" text))
  (when duration-s
    (unless (and (integerp duration-s) (<= 1 duration-s 10))
      (error "jetpacs-toast: :duration-s must be an integer 1..10 (SPEC 18.2)")))
  (when (and (jetpacs-connected-p)
             (jetpacs-granted-p "presentation.toast"))
    (ebp-client-toast (jetpacs-client)
                      (jetpacs-truncate-text
                       (jetpacs-scalar-text (substring-no-properties text))
                       jetpacs-toast-max-chars)
                      :duration-s duration-s)
    t))

(defun jetpacs-refused-p (error)
  "Non-nil when ERROR is the local W10 sender-ceiling refusal (B8).
In this implementation pair, a 1401 {kind overloaded} callback error
means ebp concluded the callback LOCALLY and SYNCHRONOUSLY — the
request never reached the wire, and the condition is transient (the
hold clears as in-flight requests conclude).  For a shell push with a
registered root, refused IS will-retry (the push callback requeues);
for the other request wrappers the caller owns the retry, and this
predicate in the callback is the uniform detection — the wrappers' nil
return is redundant with it, never double-handle."
  (and (eql (plist-get error :code) 1401)
       (equal (plist-get (plist-get error :data) :kind) "overloaded")
       ;; The tag is the discriminator: 1401 is a MANDATORY response
       ;; code (a Companion MUST answer it when max_dialogs would be
       ;; exceeded), and a peer's arrives byte-identical to ebp's
       ;; synthetic plist.  Treating a peer refusal as will-retry made
       ;; an unbounded repush loop against a loaded Companion.
       (plist-get error :ebp-local)
       t))

;; ---- Durable admission (B9): the ratified handler convention ----
;;
;; `accepted' names a DURABLE COMMITMENT (SPEC 14.4): ebp commits the
;; EventId receipt before the reply leaves, and the Companion deletes
;; its durable record on receiving it.  Therefore:
;;   1. CHEAP EFFECT -> run it synchronously in the handler, return
;;      `accepted'.  The crash window between effect and receipt means
;;      redelivery reruns the effect: handlers SHOULD be idempotent.
;;   2. DURABLE WORK ITEM -> when the effect's own home is durable (a
;;      file, a sqlite row), commit it synchronously — file writes with
;;      `write-region-inhibit-fsync' bound nil, mirroring ebp's receipt
;;      path; Emacs 30 defaults it t and an un-fsynced record is not a
;;      14.4 commitment — then `accepted'.
;;   3. NOT NOW (expensive, locked, needs network) ->
;;      (jetpacs-retry-later SECONDS): 1500 event-retry, the Companion's
;;      durable queue stays the owner.  NEVER `accepted' + run-at-time —
;;      that deletes the record and loses the work on any crash; 14.4
;;      names the volatile-callback pattern non-conforming.
;;   4. INTERACTION continuations are NOT durable effects: `accepted' +
;;      `jetpacs-flow-continue' stays correct when the deferred thing is
;;      UI whose loss the user can re-tap; a dialog answer that produces
;;      a durable effect is admitted by the dialog's OWN event, rules 1-3.
;;   5. `stale'/`rejected' are PERMANENT (the record is deleted) — never
;;      use them for "not now".
;;   6. The deferred refresh stays the D2 norm, carrying the event's
;;      surface (D1).
;; For a drop-policy event, 1500 MAY simply lose the occurrence (14.4:
;; in-session retry is only MAY) — drop actions must be cheap or
;; loss-tolerant.

(defun jetpacs-retry-later (&optional seconds)
  "Conclude the in-flight action with `1500 event-retry' (B9 rule 3).
DOES NOT RETURN — signals through the dispatch so the Companion keeps
its durable record and redelivers; the SPEC 15.3 replay that unpauses
its pump is scheduled here, after SECONDS when given.  Only meaningful
inside an action handler; elsewhere it signals a plain error.  Takes no
message on purpose: free text in app hands is a SPEC 23.3 footgun."
  (unless (jetpacs-in-action-p)
    (error "jetpacs-retry-later: only meaningful inside an action handler"))
  (ebp-client-event-retry (jetpacs-client-or-error) seconds))

(defun jetpacs-attach (client)
  "Adopt CLIENT as the single live client; returns CLIENT.
Replays every `jetpacs-defaction' registration into CLIENT's SPEC 14
allowlist — the registrations are top-level forms evaluated long before
any client exists, while ebp's allowlist is per-client.  Errors when a
different live client is already attached (decision Q1); re-attaching
the same client is idempotent, and a closed client is replaced."
  (when (and jetpacs--client
             (not (eq jetpacs--client client))
             (not (eq (ebp-client-state jetpacs--client) 'closed)))
    (error "jetpacs: a live client is already attached (single-client floor)"))
  (setq jetpacs--client client)
  (maphash (lambda (name _fn)
             (ebp-client-register-action client name
                                         (jetpacs--action-shim name)))
           jetpacs-action-handlers)
  client)

(defun jetpacs-detach (&optional client)
  "Release the client handle and per-session registries.
With CLIENT, a no-op unless it is the attached one.  Clears the async
cache (its loads belong to sessions' views) and the state subscriptions;
the action staging table survives — it is load-time state that
`jetpacs-attach' replays into the next client."
  (when (or (null client) (eq client jetpacs--client))
    (setq jetpacs--client nil)
    (when (fboundp 'jetpacs-async-reset)
      (jetpacs-async-reset))
    (clrhash jetpacs--state-handlers)))

(defun jetpacs-connect (host port &rest config)
  "Dial the Companion, attach the client, and return it.
CONFIG is `ebp-client-create' config; this wrapper owns
`:state-changed-function' (the jetpacs state fan-out — subscribe with
`jetpacs-on-state-change') and `:before-replay-function'
\(`jetpacs--before-replay': the applied-revision seed, then the SPEC
10.3 step-3 required-root push when `jetpacs-shell' is loaded); a
caller value for either is shadowed.  Everything else passes through.
When `jetpacs-shell' is loaded, a ready hook drains the pushes SYNCING
refused (`jetpacs-shell--on-ready').  Pushed after create, it runs
AHEAD of the caller's :ready-function — the drained effects predate
READY, so they belong before whatever the application does there.
Adding it post-connect is safe: READY needs round trips that cannot
complete before this function returns.

When `jetpacs-complete' is loaded and CONFIG carries no
`:edit-complete-function', the JC-5 buffer harvester
`jetpacs-complete-edit-complete' becomes the client-wide completion
answer.  An explicit caller value wins, and `jetpacs-dialog''s picker
borrows the slot per prompt either way (it restores whatever it found)."
  (when (fboundp 'jetpacs-complete-edit-complete)
    (unless (plist-member config :edit-complete-function)
      (setq config (append config (list :edit-complete-function
                                        #'jetpacs-complete-edit-complete)))))
  (let ((client (apply #'ebp-connect host port
                       :state-changed-function #'jetpacs--on-state-changed
                       :before-replay-function #'jetpacs--before-replay
                       config)))
    (jetpacs--install-ready-hooks client)
    (jetpacs-attach client)))

(defun jetpacs--install-ready-hooks (client)
  "Install the per-client READY hooks the loaded modules provide.
Named (rather than inline in `jetpacs-connect') so a suite can pin the
wiring — the audit found both theme wirings deletable with every test
green.  ready-functions run in list order = reverse push order, so
theme pushed after shell runs BEFORE the shell drain: chrome is painted
before content arrives — and `jetpacs-theme--on-ready' sends its first
frame synchronously, which is what makes that ordering true."
  (when (fboundp 'jetpacs-shell--on-ready)
    (push #'jetpacs-shell--on-ready (ebp-client-ready-functions client)))
  (when (fboundp 'jetpacs-theme--on-ready)
    (push #'jetpacs-theme--on-ready (ebp-client-ready-functions client)))
  (when (fboundp 'jetpacs-m3--on-ready)
    (push #'jetpacs-m3--on-ready (ebp-client-ready-functions client)))
  (when (fboundp 'jetpacs-chrome--on-ready)
    (push #'jetpacs-chrome--on-ready (ebp-client-ready-functions client))))

;;;; Actions (the SPEC 14 shim over `ebp-client-register-action')

(eval-and-compile
  (defconst jetpacs--blocking-readers
    '(read-key-sequence read-key-sequence-vector read-key map-y-or-n-p
      recursive-edit read-multiple-choice x-popup-dialog)
    "Input readers that `inhibit-interaction' does not stop.

`inhibit-interaction' has only FOUR guard sites in the whole 30.1 C
source (`read-char', `read-event', `read-char-exclusive', and
`read-from-minibuffer' — src/minibuf.c:1286); every other minibuffer
reader is covered only because it funnels through the last one.  So the
coverage is wide but the edges are sharp, and each name here was
verified to escape it:

- `read-key-sequence', `read-key-sequence-vector', `read-key' and
  `recursive-edit' read the keyboard without touching either guarded
  path, and BLOCK FOREVER.
- `map-y-or-n-p' reads with `read-event' but signals `quit', not an
  `error'.  `jetpacs--dispatch' happens to catch `quit' too, but relying
  on that would be luck.
- `read-multiple-choice' is the worst: rmc.el wraps its `read-event' in
  `(condition-case nil ... (error nil))' inside a `while' (rmc.el:218),
  so it SWALLOWS the signal and retries forever — a 100% CPU spin that
  `with-timeout' cannot break, because the timer's own signal is eaten
  by the same handler.
- `x-popup-dialog' is reachable from the C body of `yes-or-no-p'
  (src/fns.c:3546) whenever `use-dialog-box' is on and the last event
  was a mouse event, bypassing the minibuffer entirely.  Verified: that
  configuration RETURNS nil instead of signalling, so a handler would
  silently receive \"no\" rather than a refusal — a wrong answer, which
  is worse than a hang.  `use-dialog-box' is also bound nil below, so
  this stub is the second lock on that door.

Native compilation makes `subrp' useless for deciding what can be
intercepted (a native-compiled Lisp function is a subr too, so
`subr-primitive-p' is the real predicate) — but `cl-letf' on
`symbol-function' works for both, which is why this list needs no such
distinction.

THE RULE when adding to this list: stub the TOP-LEVEL entry point, never
trust the inner read to signal.  `read-multiple-choice' is why — a
caller that catches errors around its own read and retries turns a
refusal into an infinite loop, and stubbing `read-event' underneath it
would have made things WORSE, not better.  A sweep of Emacs 30.1 found
rmc.el to be the only instance of that shape in the standard library,
but a third-party package is free to write the same loop."))

(defmacro jetpacs-with-no-prompts (&rest body)
  "Run BODY with every way of blocking on the local user turned into a signal.

The single worst failure mode in this bridge: an action handler runs
INSIDE the jsonrpc dispatch extent, and its return value IS the reply.
Anything that waits for local input there never returns — the Companion
waits forever for an answer, and on a headless daemon there is no user
and no terminal to answer with.  Decision D2 bans it, but D2 is a rule
about code being WRITTEN correctly; this macro makes it structural.

Two mechanisms, because neither alone suffices:

- `inhibit-interaction' (Emacs 27+) is the built-in answer and covers
  the whole minibuffer family plus `read-char'/`read-event', signalling
  `inhibited-interaction' — an `error' subtype, so `jetpacs--dispatch'
  catches it and answers `rejected'.
- `jetpacs--blocking-readers' names the five that ignore it and hang;
  they are stubbed to signal the same condition.

It also holds THROUGH TIMERS, which is what makes it worth having.
Verified on the live runtime: a body that calls `accept-process-output'
runs pending timers inside this extent, and those callbacks still see
the binding.  That is the exact shape of comint's password prompt — a
process filter defers `read-passwd' into `run-at-time' 0, and the
echo-wait loop's `accept-process-output' then pulls it in — so the
deferral cannot be used to escape the ban.

What it does NOT do: stop a handler from taking a long time.  D2 bans
blocking on the USER, not bounded local work (magit's washer runs `git
diff'; `Info-toc' reads files).  Those stay the caller's judgement."
  (declare (indent 0) (debug t))
  `(let ((inhibit-interaction t)
         ;; Forces the yes/no prompts down their MINIBUFFER path, which
         ;; is guarded; the GUI-dialog path is not (see the stub list).
         (use-dialog-box nil))
     (cl-letf ,(mapcar
                (lambda (sym)
                  `((symbol-function ',sym)
                    (lambda (&rest _)
                      (signal 'inhibited-interaction (list ,(symbol-name sym))))))
                jetpacs--blocking-readers)
       ,@body)))

(defun jetpacs--error-label (err)
  "A loggable label for ERR that cannot carry payload data.
SPEC 23.3 (amendment #74) forbids SMS bodies and senders, call numbers,
calendar titles, clipboard contents, and captured trigger fire data from
reaching normal logs — and `error-message-string' embeds the offending
DATUM, which for a `wrong-type-argument' or a handler failure is exactly
that value.  Only the error symbol is safe to print."
  (if (consp err) (symbol-name (car err)) (format "%s" err)))

(defvar jetpacs--in-action-handler nil
  "Non-nil in an action handler's dynamic extent.")

(defun jetpacs-in-action-p ()
  "Non-nil inside an action handler (nil in an async continuation)."
  jetpacs--in-action-handler)

(defvar jetpacs--dispatch-params nil
  "The current `event.action' params, bound for the dispatch extent.
Lets floor seams (`jetpacs-flow-continue') capture the event's context
without every handler hand-threading it — the JC-2 lesson generalized:
anything a continuation needs from the event must be CAPTURED at
dispatch time, because the dynamic extent is gone when the timer fires.")

(defvar jetpacs--device-flow nil
  "Non-nil inside a device-originated continuation (decision D2/JC-4).
Carries a plist (:surface S) captured from the originating event.  An
action handler itself is NOT a device-flow extent for prompting — the
no-prompts regime governs there; this marker exists precisely because
D2 moves user interaction into `run-at-time' continuations, where
`jetpacs-in-action-p' is nil and nothing else says the work was started
from the device.")

(defun jetpacs-device-flow-p ()
  "Non-nil inside a device-originated continuation.
This is the gate prompt bridging keys on: nil on desktop-initiated
code paths, so advised prompts fall through to the real minibuffer."
  (and jetpacs--device-flow t))

(defun jetpacs-flow-surface ()
  "The originating surface of the current device flow, or nil.
Inside an action handler, the event's surface; inside a
`jetpacs-flow-continue' continuation, the surface captured when the
flow began.  Dialog and global events have none (SPEC 14.4)."
  (or (plist-get jetpacs--device-flow :surface)
      (and jetpacs--in-action-handler
           (plist-get jetpacs--dispatch-params :surface))))

(defun jetpacs-flow-continue (fn)
  "Run FN soon, outside any dispatch extent, keeping the flow identity.
THE way an action handler schedules its D2 effect: called inside a
handler it captures the event's device-flow identity (surface included)
so the continuation still knows it is device-originated — which is what
lets a prompt raised there bridge to a Companion dialog instead of a
minibuffer nobody is looking at.  Called inside an existing flow
continuation it inherits that identity, so chains keep it.  Called
anywhere else FN runs unmarked: a plain deferral.

The continuation runs from a timer, therefore OUTSIDE
`jetpacs-with-no-prompts' — that regime binds dynamically and ends with
the handler (its through-timers guarantee covers only timers pumped
INSIDE the extent).  That boundary is the design, not a leak: D2 bans
blocking the DISPATCH, and the continuation is where interaction is
allowed to resume."
  (let ((flow (or jetpacs--device-flow
                  (and jetpacs--in-action-handler
                       (list :surface
                             (plist-get jetpacs--dispatch-params :surface)
                             :owner jetpacs-current-owner)))))
    (run-at-time 0 nil
                 (lambda ()
                   (let ((jetpacs--device-flow flow)
                         ;; The OWNER rides the flow too, or D1 dies at the
                         ;; timer boundary: the dispatch binding ends with
                         ;; the extent, and the D2 deferred re-push — the
                         ;; whole point of this seam — would resolve to the
                         ;; shell default.  That is the reachable case, not
                         ;; a corner: a SPEC 14.4 surfaceless event
                         ;; (reminder/trigger/shortcut/pie) has no
                         ;; `:surface' to fall back on either.
                         (jetpacs-current-owner (plist-get flow :owner)))
                     (funcall fn))))))

;;;; Flow entry (JA-2/B3): ESTABLISHING a device flow, not inheriting one

(defun jetpacs--flow-resolve-surface (surface)
  "Resolve SURFACE to a full surface id, or signal (shape-only, D1).
nil is the current owner's default; an ownerless string is a D1 owner
name resolving to app:<owner>; a colon form must name one of the four
SPEC 13.1 namespaces with a non-empty name and fit the 4.4 grammar.
Deliberately NO liveness/grant check: a flow legitimately starts before
its surface's first push and while disconnected — the dialog bridge
gates on `jetpacs-connected-p' separately, so an offline flow simply
does not bridge."
  (cond
   ((null surface) (jetpacs--default-surface))
   ((not (stringp surface))
    (error "jetpacs: invalid flow surface %S (SPEC 13.1)" surface))
   ((not (string-search ":" surface))
    (unless (jetpacs--valid-owner-p surface)
      (error "jetpacs: invalid flow owner %S (D1)" surface))
    (concat "app:" surface))
   ((and (string-match-p "\\`\\(app\\|notification\\|widget\\|tile\\):." surface)
         (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" surface)
         (<= (string-bytes surface) 128))
    surface)
   (t (error "jetpacs: invalid flow surface %S (SPEC 13.1)" surface))))

(defun jetpacs--call-with-flow (surface thunk)
  "Run THUNK inside a fresh device flow for SURFACE (see `with-jetpacs-flow').
Re-entrancy follows the dialog pump's single-flight precedent: wrapping
the SAME resolved surface is idempotent; a DIFFERENT surface refuses —
a silent override would re-route a chain's D1 re-pushes mid-flight.
The dynamic let is the entire unwind story: error, quit, and throw all
restore the prior marker; nothing to clear, nothing to leak."
  (let ((resolved (jetpacs--flow-resolve-surface surface)))
    (when (and jetpacs--device-flow
               (not (equal (plist-get jetpacs--device-flow :surface)
                           resolved)))
      (error "jetpacs: a device flow for %S is already established; refusing nested flow for %S"
             (plist-get jetpacs--device-flow :surface) resolved))
    (let* ((flow (list :surface resolved :owner jetpacs-current-owner))
           (jetpacs--device-flow flow))
      (funcall thunk))))

(defmacro with-jetpacs-flow (surface &rest body)
  "Run BODY inside a fresh device flow for SURFACE; return BODY's value.
Inside BODY, `jetpacs-device-flow-p' is true and prompts bridge to the
device per `jetpacs-dialog--bridge-p'.  Two constraints: (a) this does
NOT override the dispatch no-prompts regime — inside a handler the
in-action and inhibit-interaction tests still win, so a flow begun
there cannot unlock prompts in the extent (use `jetpacs-flow-continue'
for the event's own identity); (b) SYNCHRONOUS, so only for a clean
stack (a bare timer, a user command) — from process filters/sentinels
or ebp callbacks use `jetpacs-flow-begin', because a bridged prompt
pumps `accept-process-output' and would re-enter the jsonrpc filter."
  (declare (indent 1) (debug (form body)))
  `(jetpacs--call-with-flow ,surface (lambda () ,@body)))

(defun jetpacs-flow-begin (surface fn)
  "Run FN soon from a bare timer inside a FRESH device flow for SURFACE.
The establishing sibling of `jetpacs-flow-continue' (which only
inherits): with-editor buffers, transient callbacks, and anything else
arriving on a process callback's stack has no dispatch to inherit from
— this is how such code gets a device flow at all.  Validation is
EAGER (a bad surface signals on the caller's stack, not as a swallowed
timer message); FN runs outside any dispatch extent, exactly where the
dialog bridge is allowed to engage.  No nesting check: FN runs later
on a fresh stack, so a call from inside an existing flow deliberately
starts a NEW chain.  Keep flows serial — while one bridged prompt
pumps, a second flow's prompt falls through to the real minibuffer.
Returns the timer."
  (unless (functionp fn)
    (error "jetpacs-flow-begin: FN must be a function, got %S" fn))
  (let ((resolved (jetpacs--flow-resolve-surface surface))
        (owner jetpacs-current-owner))
    (run-at-time 0 nil
                 (lambda ()
                   (let ((jetpacs--device-flow
                          (list :surface resolved :owner owner))
                         (jetpacs-current-owner owner))
                     (funcall fn))))))

(defvar jetpacs--any-surface-actions)   ; the global-verb table, defined below

(cl-defun jetpacs--dispatch (client params fn)
  "Run FN for one `event.action' and derive its SPEC 14.4 status.
FN is called with (ARGS PARAMS) and MUST return `accepted', `stale', or
`rejected'; any other return answers `rejected' with a loud warning
\(decision Q3) — a blanket accept would durably commit a receipt for an
event that failed.  A signalled `error' or `quit' also answers
`rejected': escaping would become a bare -32603 with no `data.kind'
\(SPEC 8).  There is NO confirm gate here — the Companion presented
`confirm' before creating the event (SPEC 14.1) — and PARAMS is never
logged: amendment #74 puts sensitive trigger data in `args'."
  (ignore client)
  (let ((args (plist-get params :args))
        (jetpacs--in-action-handler t)
        ;; D1: the handler runs under the owner that REGISTERED it.  A
        ;; plain `let', not `with-jetpacs-owner': that macro errors on
        ;; nil, and nil is the common case (most base actions register
        ;; ownerless), and an error here would be caught below and
        ;; answered a PERMANENT `rejected' — a registry oddity turned
        ;; into event loss.  Unconditional, never `or'-inherited: a
        ;; re-entrant dispatch (the dialog pump, an async loader inside
        ;; a builder) would otherwise run this handler under whatever
        ;; owner happened to be on the stack.
        (jetpacs-current-owner
         (jetpacs--owner-of "action" (plist-get params :action)))
        ;; Event context for floor seams (`jetpacs-flow-continue');
        ;; never logged — amendment #74 puts sensitive data in `args'.
        (jetpacs--dispatch-params params)
        ;; Pin prompt redirection back to the built-ins: ivy/consult
        ;; reroute prompts to a keyboard UI the phone cannot drive.  A
        ;; conforming handler never prompts inside the dispatch extent
        ;; (decision D2), but a ported body that slips must fail locally,
        ;; not wedge the filter behind a completion framework.
        (completing-read-function #'completing-read-default)
        (read-file-name-function #'read-file-name-default)
        (read-buffer-function nil)
        (disabled-command-function nil))
    ;; D1 surface-context validation (SPEC 14.4: "Emacs MUST validate
    ;; the ... surface context ... before invoking application
    ;; behavior").  Scope: OWNED actions only — an owned action acts on
    ;; its owner's surfaces unless it declared :any-surface.  Ownerless
    ;; actions are deliberately not gated here: their handlers thread the
    ;; wire surface into paths that already degrade (a rootless push
    ;; no-ops), and a rooted-surface bound would reject REPLAYED durable
    ;; events for non-required roots at the barrier, which is worse than
    ;; the ghost it prevents.
    (let ((event-surface (plist-get params :surface)))
      (when (and jetpacs-current-owner
                 (stringp event-surface)
                 (not (gethash (plist-get params :action)
                               jetpacs--any-surface-actions))
                 (not (jetpacs-owned-surface-p event-surface
                                               jetpacs-current-owner)))
        (display-warning
         'jetpacs
         (format "action %s (owner %S) refused for foreign surface %S \
(SPEC 14.4 / D1)"
                 (plist-get params :action) jetpacs-current-owner
                 event-surface)
         :warning)
        (cl-return-from jetpacs--dispatch 'rejected)))
    (condition-case err
        (pcase (jetpacs-with-no-prompts (funcall fn args params))
          ((and status (or 'accepted 'stale 'rejected)) status)
          (other
           (display-warning
            'jetpacs
            (format "action %s returned %S, not accepted/stale/rejected \
(SPEC 14.4); answering rejected"
                    (plist-get params :action) other)
            :error)
           'rejected))
      (quit 'rejected)
      ;; A handler that deliberately signals a typed EBP error (notably
      ;; `1500 event-retry', the only way to say "not now, redeliver")
      ;; must reach the endpoint: `jsonrpc-error' derives from `error',
      ;; so the clause below would otherwise swallow it and answer
      ;; `rejected' — which SPEC 14.4 makes PERMANENT, deleting the
      ;; Companion's durable record.
      (jsonrpc-error (signal (car err) (cdr err)))
      ;; A handler that tried to block on the local user.  Louder than a
      ;; generic failure on purpose: the answer is still `rejected' (the
      ;; phone gets a real reply instead of waiting forever, which is the
      ;; whole point), but this is a CODE bug in the handler — decision
      ;; D2 — and it must not read as an ordinary runtime error.
      (inhibited-interaction
       (display-warning
        'jetpacs
        (format "action %s tried to prompt the local user (%s) inside the \
dispatch extent; answering rejected.  Handlers MUST NOT block (decision D2) \
— route the question to the phone with a dialog instead"
                (plist-get params :action)
                ;; Emacs's own `inhibit-interaction' signal carries no
                ;; datum; only the stubs in `jetpacs--blocking-readers'
                ;; name themselves.
                (or (car (cdr err)) "a minibuffer prompt"))
        :error)
       'rejected)
      (error
       ;; Action name and error SYMBOL only: amendment #74 keeps the datum
       ;; (a trigger's fire data reaches handlers through `args') out of logs.
       (message "jetpacs: action %s failed: %s"
                (plist-get params :action) (jetpacs--error-label err))
       'rejected))))

(defun jetpacs--action-shim (name)
  "The per-action closure registered with ebp for NAME.
Looks the handler up at dispatch time so live-coded redefinitions win."
  (lambda (client params)
    (let ((fn (gethash name jetpacs-action-handlers)))
      (if fn
          (jetpacs--dispatch client params fn)
        'rejected))))

(defvar jetpacs--any-surface-actions (make-hash-table :test #'equal)
  "Action names registered with :any-surface — D1 GLOBAL VERBS.
An owned action is otherwise scoped to its owner's surfaces at
dispatch; a global verb (base's `jetpacs.theme.modus-toggle': owned,
owns ZERO surfaces, any surface may render its button) declares the
exception EXPLICITLY rather than having the gate infer it.")

(defun jetpacs-owned-surface-p (surface owner)
  "Non-nil when SURFACE is OWNER's D1 primary or claimed under it."
  (and (stringp surface) (stringp owner)
       (or (equal surface (concat "app:" owner))
           (and (member surface (jetpacs--owned-names "surface" owner)) t))))

(cl-defun jetpacs-defaction (name fn &key any-surface)
  "Register FN as the handler for the remote action NAME; returns NAME.
A function, not a macro: FN is a value, `(lambda (args params) ...)'.
ARGS is the event's `:args' plist (jsonrpc decode: nested keyword
plists, vectors for arrays, `:json-false' for false, nil for null);
PARAMS is the full `event.action' params plist (`:event_id' `:surface'
`:revision_seen' `:dialog_id' `:fields' ...).  FN MUST return
`accepted', `stale', or `rejected' (never `duplicate' — ebp synthesizes
it from the receipt store), MUST NOT block (decision D2: it runs inside
the jsonrpc dispatch extent and its return value is the reply), and
MUST return `accepted' only once the effect is durable.

Registers into the global staging table and, when a client is attached,
into its live allowlist; `jetpacs-attach' replays the table into every
future client.

When registered under `with-jetpacs-owner', the dispatch REJECTS an
event whose wire surface is not the owner's (SPEC 14.4 validates the
surface context BEFORE invoking behavior).  ANY-SURFACE non-nil
declares a GLOBAL VERB exempt from that scope — for an owner-attributed
action whose button any surface may legitimately render."
  (unless (and (stringp name) (string-search "." name)
               (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" name)
               (<= (string-bytes name) 128))
    (error "jetpacs: action name %S must be a dotted SPEC 4.4 identifier"
           name))
  (unless (functionp fn)
    (error "jetpacs: action %s handler must be a function" name))
  (jetpacs--claim "action" name)
  (puthash name fn jetpacs-action-handlers)
  (if any-surface
      (puthash name t jetpacs--any-surface-actions)
    (remhash name jetpacs--any-surface-actions))
  (when jetpacs--client
    (ebp-client-register-action jetpacs--client name
                                (jetpacs--action-shim name)))
  name)

(defun jetpacs-undefaction (name)
  "Remove the action NAME from the staging table and any live client."
  (remhash name jetpacs-action-handlers)
  (remhash name jetpacs--any-surface-actions)
  (when jetpacs--client
    (remhash name (ebp-client-actions jetpacs--client)))
  (jetpacs--unclaim "action" name))

(defvar jetpacs--applied-revisions (make-hash-table :test #'equal)
  "Map of SURFACE -> the newest revision the Companion CONFIRMED applied.
`ebp-client-revisions' cannot serve: it claims `floor + 1' at SEND time
so a second in-flight push is newer, and never rolls back when a push
fails — one refused update would otherwise leave every later tap looking
stale forever.  `jetpacs-shell' records confirmations here, and
`jetpacs--seed-applied-revisions' seeds it from every welcome.")

(defun jetpacs--seed-applied-revisions (client)
  "Adopt CLIENT's welcome-reported floors as confirmed-applied revisions.
A welcome floor IS a confirmed apply: SPEC 13.1 lets the Companion
report a revision only after durably committing the snapshot or
tombstone it belongs to.  Without this seed the table starts empty
after a process restart, `jetpacs-event-stale-p' answers \"not stale\"
for a surface it has no entry for, and every event replayed from the
durable queue — queued against a snapshot revisions old — dispatches
as fresh, so handlers index into the wrong rows
(docs/RESEARCH-A8-2026-07-25.md section 5.2).

REPLACES the table rather than folding `max' over it: the Companion is
the authority on what it has applied, and after a pairing wipe or
reinstall its floors legitimately FALL — a surviving in-memory entry
above the reported floor would mark every replayed event stale against
a snapshot history that no longer exists.  Tombstone floors
(`:present' nil) seed too: an event queued before a removal was
outrun by it just as surely as by a later snapshot."
  (clrhash jetpacs--applied-revisions)
  (cl-loop for (key entry) on (ebp-client-surfaces client) by #'cddr
           for revision = (plist-get entry :revision)
           when (integerp revision)
           do (puthash (substring (symbol-name key) 1) revision
                       jetpacs--applied-revisions)))

(defun jetpacs--before-replay (client)
  "The SPEC 10.3 step-3 barrier work `jetpacs-connect' installs.
Ordering is the point: `queue.replay' (step 4) delivers retained
`event.action' requests while the session is still SYNCING, so
everything a replayed handler consults must be in place before this
function returns — the applied-revision seed first, then the shell's
tombstone flush and required-root pushes when `jetpacs-shell' is
loaded."
  (jetpacs--seed-applied-revisions client)
  (when (fboundp 'jetpacs-shell--before-replay)
    (jetpacs-shell--before-replay client)))

(defun jetpacs-event-stale-p (params)
  "Non-nil when PARAMS' event was created against an outdated snapshot.
Nil for a dialog or global event: SPEC 14.4 gives those no surface or
revision context, so `stale' is not derivable for them.  A helper a
handler opts into (decision Q4) — the revision floor rises on every
push, so lag alone is not semantic staleness; use this where the action
indexes into the snapshot it was tapped against.

Compares against the newest CONFIRMED-applied revision, not the claimed
floor, so a failed push cannot make a surface permanently stale."
  (let* ((surface (plist-get params :surface))
         (seen (plist-get params :revision_seen))
         (client (jetpacs-client))
         (applied (and surface
                       (gethash surface jetpacs--applied-revisions))))
    (and client surface (integerp seen) (integerp applied)
         (< seen applied))))

;;;; State (the SPEC 14.6 fan-out; ebp owns the store and reconciliation)

(defun jetpacs-node-advertised-p (type &optional target)
  "Non-nil when the live welcome advertises node TYPE for TARGET (SPEC 16.2).
TARGET defaults to `:app'.  Only the Core Node Set — `text', `row',
`column', `box', `spacer', `divider', `button', `text_input' — is
guaranteed; everything else is OPTIONAL and a sender MUST NOT emit an
unadvertised type, so a renderer that wants an optional node must ask
first and degrade when the answer is no.  With no client attached
\(offline renders, tests) assume the richer form."
  (if-let* ((client (jetpacs-client)))
      (if-let* ((profile (plist-get (ebp-client-profiles client)
                                    (or target :app))))
          (and (member type (append (plist-get profile :node_types) nil)) t)
        ;; No profile for this target on a LIVE client.  For a
        ;; CAPABILITY-GATED target that absence is the answer: SPEC 10.2
        ;; carries a dialog/notification/widget/tile profile precisely
        ;; when its capability was granted, so failing open would be
        ;; guaranteed wrong in exactly the case the gate exists for.
        ;; `app' is NOT negotiated (10.2: core session and app:* surfaces
        ;; are not capabilities), so its absence means a malformed
        ;; welcome, not a refusal — keep the richer-form tolerance there.
        (null (jetpacs--capability-gated-target-p target)))
    ;; No client at all — offline render or test: assume the richer form.
    t))

(defun jetpacs-feature-advertised-p (feature &optional target)
  "Non-nil when the live welcome advertises FEATURE for TARGET (SPEC 22.4).
The feature twin of `jetpacs-node-advertised-p'.  SPEC 22.4 registers the
constraining names; the two a renderer must ask about are `image.https'
and `image.data' (17.2), since an image URI form the client did not
advertise is a sender MUST violation — `jetpacs-shell--check-features'
SIGNALS on one, refusing the whole surface, so a builder has to ask HERE
and degrade to a caption instead of emitting and hoping.

With no client attached the gate does not run either (it needs a live
profile), so offline renders and tests assume the richer form."
  (if-let* ((client (jetpacs-client)))
      (if-let* ((profile (plist-get (ebp-client-profiles client)
                                    (or target :app))))
          (and (member feature (append (plist-get profile :features) nil)) t)
        ;; No profile for this target on a LIVE client.  For a
        ;; CAPABILITY-GATED target that absence is the answer: SPEC 10.2
        ;; carries a dialog/notification/widget/tile profile precisely
        ;; when its capability was granted, so failing open would be
        ;; guaranteed wrong in exactly the case the gate exists for.
        ;; `app' is NOT negotiated (10.2: core session and app:* surfaces
        ;; are not capabilities), so its absence means a malformed
        ;; welcome, not a refusal — keep the richer-form tolerance there.
        (null (jetpacs--capability-gated-target-p target)))
    ;; No client at all — offline render or test: assume the richer form.
    t))

(defun jetpacs--capability-gated-target-p (target)
  "Non-nil when TARGET's profile appears only under a granted capability.
SPEC 10.2/22.1: `dialog', `notification', `widget' and `tile' each ride
a capability, so an absent profile for one of them is a NO.  `app' (and
a nil TARGET, which means app) is core and always present in a
conforming welcome."
  (memq target '(:dialog :notification :widget :tile)))

(defun jetpacs--gate-descriptor-policy (descriptor &optional client)
  "Signal when DESCRIPTOR authors an offline policy this session lacks.
SPEC 14.1 (amendment #85): a sender MUST NOT author `wake' without the
`offline.wake' grant.  EVERY descriptor emitter must call this, not
just the one that pushes documents: reminders, dialogs, triggers and
notifications each reach the wire by their own path, and 14.1 binds the
SENDER — the reference Companion checks only the policy vocabulary and
`ttl_s', so an ungranted wake target is accepted, armed and signalled,
which is precisely the outcome 14.1 forbids.  Nothing downstream saves
us; this is the only gate."
  (when (and descriptor
             (equal (plist-get descriptor :when_offline) "wake")
             (not (jetpacs-granted-p "offline.wake" client)))
    (error "jetpacs: `wake' descriptor without the offline.wake grant \
(SPEC 14.1, amendment #85)")))

(defun jetpacs-builtin-advertised-p (builtin &optional target)
  "Non-nil when the live welcome advertises BUILTIN for TARGET (SPEC 14.2).
TARGET defaults to `:app'.  The builtin third of the advertised-p
triple (B13): GATE 1b (`jetpacs-shell--check-builtins') SIGNALS on an
unadvertised builtin and takes down the WHOLE push, so a builder that
wants an optional builtin — `clipboard.copy', `share.send',
`trigger.fire' — must ask here and degrade per-node instead of emitting
and hoping.  With no client attached (offline renders, tests) assume
the richer form, like the siblings."
  (if-let* ((client (jetpacs-client)))
      (if-let* ((profile (plist-get (ebp-client-profiles client)
                                    (or target :app))))
          (and (member builtin (append (plist-get profile :builtins) nil)) t)
        ;; No profile for this target on a LIVE client.  For a
        ;; CAPABILITY-GATED target that absence is the answer: SPEC 10.2
        ;; carries a dialog/notification/widget/tile profile precisely
        ;; when its capability was granted, so failing open would be
        ;; guaranteed wrong in exactly the case the gate exists for.
        ;; `app' is NOT negotiated (10.2: core session and app:* surfaces
        ;; are not capabilities), so its absence means a malformed
        ;; welcome, not a refusal — keep the richer-form tolerance there.
        (null (jetpacs--capability-gated-target-p target)))
    ;; No client at all — offline render or test: assume the richer form.
    t))

(defun jetpacs--default-surface ()
  "The current owner's surface (decision D1), or the shell default."
  (if jetpacs-current-owner
      (concat "app:" jetpacs-current-owner)
    (or (bound-and-true-p jetpacs-shell-surface-id) "app:main")))

(defun jetpacs-on-state-change (id fn &optional surface)
  "Call FN with the new value whenever stateful node ID publishes.
Keyed by (SURFACE . ID), matching SPEC 14.6, which scopes input state to
a surface AND an id — and matching ebp's own `input-values' store.
SURFACE defaults to the current owner's surface (decision D1).

\(This revises the JC-0 spec's open question Q5, which chose bare-id
keying on the rationale that app ids are already namespaced.  That
rationale predates decision D1: now that every owner gets its own
surface, two apps each using a widget id like \"title\" are distinct
\(surface, id) pairs, and bare-id keying would silently let the second
subscriber clobber the first and then fire on the wrong app's edits.)

ebp has already stored the value and applied the 14.6 reset
reconciliation before FN runs; read the store with `jetpacs-ui-state'."
  (puthash (cons (or surface (jetpacs--default-surface)) id)
           fn jetpacs--state-handlers))

(defun jetpacs-on-state-change-clear (prefix &optional surface)
  "Drop every state subscription whose id starts with PREFIX.
Restricted to SURFACE when given, otherwise across every surface."
  (let (dead)
    (maphash (lambda (key _fn)
               (when (and (string-prefix-p prefix (cdr key))
                          (or (null surface) (equal (car key) surface)))
                 (push key dead)))
             jetpacs--state-handlers)
    (dolist (key dead) (remhash key jetpacs--state-handlers))))

(defun jetpacs--on-state-changed (_client surface _revision id value)
  "The `:state-changed-function' hook body: fan out to subscribers.
One broken callback must not break the connection — this runs inside
the jsonrpc dispatch extent."
  (when-let* ((fn (gethash (cons surface id) jetpacs--state-handlers)))
    (condition-case err
        ;; D1, symmetric with `jetpacs--dispatch': this is the OTHER
        ;; device-event entry point into application code, in the same
        ;; jsonrpc extent.  Without this an app gets its owner on a tap
        ;; and loses it on a text edit — worse than a uniform nil,
        ;; because handlers written against the repaired action path
        ;; would silently misroute here.
        (let ((jetpacs-current-owner (jetpacs--owner-of "surface" surface)))
          (funcall fn value))
      ;; The datum here is the user's input value — never log it (23.3).
      (error (message "jetpacs: state handler for %s failed: %s"
                      id (jetpacs--error-label err))))))

(defun jetpacs-ui-state (id &optional surface)
  "The latest reconciled value for stateful node ID — read-through only.
ebp owns the store (`ebp-client-input-values') and its SPEC 14.6
reconciliation; no jetpacs writer exists by design.  SURFACE defaults
per decision D1 to the current owner's surface."
  (ebp-client-input-value (jetpacs-client-or-error)
                          (or surface (jetpacs--default-surface))
                          id))

(defun jetpacs-ui-state-list (id &optional surface)
  "`jetpacs-ui-state' coerced to a list of strings.
Accepts a vector (the jsonrpc decode of a JSON array), a list, a JSON
array string, or a single string; anything else is discarded."
  (let ((value (jetpacs-ui-state id surface)))
    (cond
     ((vectorp value) (seq-filter #'stringp (append value nil)))
     ((and (consp value) (not (keywordp (car value))))
      (seq-filter #'stringp value))
     ((and (stringp value) (string-prefix-p "[" value))
      (condition-case nil
          (seq-filter #'stringp
                      (append (json-parse-string value :array-type 'array)
                              nil))
        (error nil)))
     ((stringp value) (list value))
     (t nil))))

(defvar jetpacs-teardown-functions nil
  "Abnormal hook run with (OWNER) at the end of `jetpacs-teardown-owner'.
The attachment point for module-private per-owner state (reminders
bookkeeping, chrome stacks, future registries) — the rewrite's answer
to the poc's fboundp ladder.  Runs after every core registry is swept,
so a hook observing the owner's claims sees them already gone.  The
surfaces it swept are in `jetpacs-teardown-surfaces'; a per-surface
subscriber MUST read that, never recompute.  Each fn runs isolated: one
failure logs its error SYMBOL and the rest still run.  Lives on the
floor (not the shell) so subscribers need no shell edge.")

(defvar jetpacs-teardown-surfaces nil
  "The surfaces the in-progress `jetpacs-teardown-owner' is sweeping.
Bound around the WHOLE sweep — the registry pass and
`jetpacs-teardown-functions' alike — to the list computed ONCE, BEFORE
anything is unclaimed.  A hook cannot recompute this: by the time the
hooks run the owner's surface claims are gone, so
`jetpacs-shell--owner-surfaces' then answers only the D1 primary and a
per-surface subscriber silently leaks every secondary surface (the
JA-2 chrome stale-stack bug).  Read it synchronously inside the hook;
a deferred read sees nil.  Context rides a dynamic variable rather
than a second hook argument because (OWNER) is the hook's PUBLIC
arity: a two-argument call signals `wrong-number-of-arguments' in
every existing subscriber, and the hook loop isolates errors — so the
break would be SILENT and would stop every module's sweep, not just
the one being fixed.")

(defun jetpacs--owners ()
  "Every owner id with a live registration (interactive completion)."
  (let (owners)
    (maphash (lambda (_k owner)
               (cl-pushnew owner owners :test #'equal))
             jetpacs--registrations)
    owners))

(defun jetpacs-test-reset-state ()
  "Reset floor state for tests and teardown."
  (clrhash jetpacs--state-handlers)
  (clrhash jetpacs--applied-revisions)
  (when (fboundp 'jetpacs-async-reset)
    (jetpacs-async-reset))
  (when (fboundp 'jetpacs-device-reset)
    (jetpacs-device-reset))
  (when (fboundp 'jetpacs-org-reset)
    (jetpacs-org-reset))
  (when (fboundp 'jetpacs-org-render-reset)
    (jetpacs-org-render-reset))
  (when (fboundp 'jetpacs-org-dialogs-reset)
    (jetpacs-org-dialogs-reset))
  (when (fboundp 'jetpacs-org-habits-reset)
    (jetpacs-org-habits-reset))
  (when (boundp 'jetpacs-shell--snackbars)
    (clrhash jetpacs-shell--snackbars))
  (when (boundp 'jetpacs-shell--refusal-counts)
    (clrhash jetpacs-shell--refusal-counts))
  (when (boundp 'jetpacs-shell--tombstoned)
    (clrhash jetpacs-shell--tombstoned))
  ;; Shell tables (boundp-guarded: surfaces loads without shell).  Never
  ;; clear `jetpacs-action-handlers'/`jetpacs--registrations' wholesale —
  ;; the ownerless core registration \"view.switched\" must survive.
  (when (boundp 'jetpacs-shell--roots)
    (setq jetpacs-shell--roots nil))
  (when (boundp 'jetpacs-shell--repush-pending)
    (setq jetpacs-shell--repush-pending nil))
  (when (boundp 'jetpacs-shell--pending-removals)
    (setq jetpacs-shell--pending-removals nil))
  (when (and (boundp 'jetpacs-shell--repush-timer)
             (timerp jetpacs-shell--repush-timer))
    (cancel-timer jetpacs-shell--repush-timer)
    (setq jetpacs-shell--repush-timer nil))
  (when (boundp 'jetpacs-shell--current-view)
    (clrhash jetpacs-shell--current-view))
  (when (boundp 'jetpacs-shell--unasserted-view)
    (clrhash jetpacs-shell--unasserted-view)))

(provide 'jetpacs-surfaces)
;;; jetpacs-surfaces.el ends here
