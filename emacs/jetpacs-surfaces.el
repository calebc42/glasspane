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
           (prior (gethash key jetpacs--registrations)))
      (when (and prior (not (equal prior jetpacs-current-owner)))
        (if jetpacs-strict-namespaces
            (error "jetpacs: %s %S already owned by %S (claiming as %S)"
                   kind name prior jetpacs-current-owner)
          (display-warning
           'jetpacs
           (format "%s %S re-registered by %S (was %S)"
                   kind name jetpacs-current-owner prior)
           :warning)))
      (puthash key jetpacs-current-owner jetpacs--registrations)))
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
  (remhash (cons kind name) jetpacs--registrations))

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

(defun jetpacs-connected-p ()
  "Non-nil when the attached client is past the SPEC 10.3 barrier."
  (and jetpacs--client (eq (ebp-client-state jetpacs--client) 'ready)))

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
`jetpacs-on-state-change') and `:before-replay-function' (the SPEC 10.3
step-3 required-root push, when `jetpacs-shell' is loaded); a caller
value for either is shadowed.  Everything else passes through."
  (let ((client (apply #'ebp-connect host port
                       :state-changed-function #'jetpacs--on-state-changed
                       :before-replay-function
                       (lambda (c)
                         (when (fboundp 'jetpacs-shell--before-replay)
                           (jetpacs-shell--before-replay c)))
                       config)))
    (jetpacs-attach client)))

;;;; Actions (the SPEC 14 shim over `ebp-client-register-action')

(eval-and-compile
  (defconst jetpacs--blocking-readers
    '(read-key-sequence read-key-sequence-vector read-key map-y-or-n-p
      recursive-edit)
    "Input readers that IGNORE `inhibit-interaction' and must be stubbed.
Verified empirically on Emacs 30.1: with `inhibit-interaction' bound to
t, every minibuffer reader (`read-string', `completing-read',
`read-passwd', `read-file-name', `read-buffer', `read-answer',
`read-number', `read-char-from-minibuffer'), both yes/no prompts, and
the raw `read-char'/`read-event'/`read-char-exclusive' all signal
`inhibited-interaction' — but these five BLOCK FOREVER instead.  Each is
a C subr, and `cl-letf' on a subr's `symbol-function' works, so they are
replaced wholesale for the extent."))

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
  `(let ((inhibit-interaction t))
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

(defun jetpacs--dispatch (client params fn)
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
        ;; Pin prompt redirection back to the built-ins: ivy/consult
        ;; reroute prompts to a keyboard UI the phone cannot drive.  A
        ;; conforming handler never prompts inside the dispatch extent
        ;; (decision D2), but a ported body that slips must fail locally,
        ;; not wedge the filter behind a completion framework.
        (completing-read-function #'completing-read-default)
        (read-file-name-function #'read-file-name-default)
        (read-buffer-function nil)
        (disabled-command-function nil))
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

(defun jetpacs-defaction (name fn)
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
future client."
  (unless (and (stringp name) (string-search "." name)
               (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" name)
               (<= (string-bytes name) 128))
    (error "jetpacs: action name %S must be a dotted SPEC 4.4 identifier"
           name))
  (unless (functionp fn)
    (error "jetpacs: action %s handler must be a function" name))
  (jetpacs--claim "action" name)
  (puthash name fn jetpacs-action-handlers)
  (when jetpacs--client
    (ebp-client-register-action jetpacs--client name
                                (jetpacs--action-shim name)))
  name)

(defun jetpacs-undefaction (name)
  "Remove the action NAME from the staging table and any live client."
  (remhash name jetpacs-action-handlers)
  (when jetpacs--client
    (remhash name (ebp-client-actions jetpacs--client)))
  (jetpacs--unclaim "action" name))

(defvar jetpacs--applied-revisions (make-hash-table :test #'equal)
  "Map of SURFACE -> the newest revision the Companion CONFIRMED applied.
`ebp-client-revisions' cannot serve: it claims `floor + 1' at SEND time
so a second in-flight push is newer, and never rolls back when a push
fails — one refused update would otherwise leave every later tap looking
stale forever.  `jetpacs-shell' records confirmations here.")

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
  (if-let* ((client (jetpacs-client))
            (profile (plist-get (ebp-client-profiles client) (or target :app))))
      (and (member type (append (plist-get profile :node_types) nil)) t)
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
  (if-let* ((client (jetpacs-client))
            (profile (plist-get (ebp-client-profiles client) (or target :app))))
      (and (member feature (append (plist-get profile :features) nil)) t)
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
        (funcall fn value)
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

(defun jetpacs-test-reset-state ()
  "Reset floor state for tests and teardown."
  (clrhash jetpacs--state-handlers)
  (when (fboundp 'jetpacs-async-reset)
    (jetpacs-async-reset))
  (when (boundp 'jetpacs-shell--snackbar)
    (setq jetpacs-shell--snackbar nil)))

(provide 'jetpacs-surfaces)
;;; jetpacs-surfaces.el ends here
