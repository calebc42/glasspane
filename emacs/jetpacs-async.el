;;; jetpacs-async.el --- Declarative async loading for Jetpacs views -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; A keyed loader state machine, so a view stops hand-rolling the three
;; display states of every fetch -- kick a request off in a handler, stash
;; the result in a defvar, re-push, branch on pending/ready/error by hand.
;;
;; `jetpacs-async' is called from *inside* a view builder (like React's
;; use-async): it returns the current (STATUS . PAYLOAD) for a KEY, starting
;; the loader once on first sight and caching the result.  The builder stays
;; a pure function of the cache; the one controlled impurity is the
;; idempotent first-call start.  A loader's completion schedules a single
;; coalesced re-push, so the view re-renders and reads the ready value on
;; the next build.
;;
;; Eviction rides the push cycle.  Each build stamps every KEY it asks for
;; with the current generation; `jetpacs-shell-after-push-hook' then sweeps
;; entries no build asked for this generation (running any cancel thunk the
;; loader registered) and advances the generation -- the precise mirror of a
;; component unmount, so a view that stops asking for data stops paying for
;; it.  App teardown additionally drops every entry scoped to that owner.
;;
;; Rung JC-0 of docs/PLAN-jetpacs-consumers.md (spec: docs/SPEC-JC-0-floor.md),
;; ported near-verbatim from poc-v1 `jetpacs-async.el'.  It adds nothing to
;; the wire vocabulary and never touches the endpoint: the only outward edge
;; is the re-push seam below.
;;
;; PER-OWNER PUSH (spec decision D1).  Each owner owns the surface
;; `app:<owner>', so a completion must re-push *the owner that asked*, not a
;; single global surface.  poc-v1 called `(jetpacs-shell-push)' with no
;; arguments, which is unambiguous only when one surface exists.  Every entry
;; already records its `owner', so a settle records that owner as pending and
;; the debounced flush re-pushes each one.  This keeps the module
;; shell-agnostic: it passes owners through and never learns a surface id.
;;
;; This file is required by `jetpacs-shell', so it must not require it back;
;; the shell registers the sweep on its own hook when it loads.

;;; Code:

(require 'cl-lib)

;; Resolved at runtime from `jetpacs-surfaces'/`jetpacs-shell'; forward-declared
;; so this file byte-compiles clean and can load before them.
(defvar jetpacs-current-owner)                 ; jetpacs-surfaces.el
(declare-function jetpacs-shell-push "jetpacs-shell" (&optional owner))
(declare-function jetpacs-error-label "jetpacs-surfaces" (err))

(cl-defstruct (jetpacs-async--entry (:constructor jetpacs-async--entry-make)
                                    (:copier nil))
  "One cached async load.
STATUS is `pending', `ready', or `error'; VALUE is the resolved value or
the error message string; GEN is the push-generation stamp driving the
sweep; OWNER scopes the entry to an app for teardown and names the surface
its completion re-pushes; CANCEL is an optional thunk the loader registered
to abort itself (kill a process, cancel a timer)."
  status value gen owner cancel)

(defvar jetpacs-async--cache (make-hash-table :test 'equal)
  "Map of KEY -> `jetpacs-async--entry'.  KEY is compared `equal'.")

(defvar jetpacs-async--generation 0
  "Advanced after each shell push.
Each live entry is stamped with the generation of the build that last asked
for it; entries left behind an older generation belong to views that stopped
asking, and are swept (see `jetpacs-async--after-push').")

(defvar jetpacs-async--push-timer nil
  "Debounce timer coalescing the completion pushes of one tick into one.")

(defvar jetpacs-async--pending-owners nil
  "Owners whose entries settled since the last flush.
The debounced flush re-pushes each one exactly once (spec decision D1).
Accumulated by `jetpacs-async--settle', drained by
`jetpacs-async--flush-push'.")

;; --- Completion push (debounced, per owner) --------------------------------

(defun jetpacs-async--schedule-push ()
  "Schedule one shell push after a completion, coalescing a burst.
Deferred through a zero-delay timer, not called inline: a loader that
resolves synchronously does so *while a build is running*, and pushing from
within a build would recurse."
  (unless (timerp jetpacs-async--push-timer)
    (setq jetpacs-async--push-timer
          (run-at-time 0 nil #'jetpacs-async--flush-push))))

(defun jetpacs-async--flush-push ()
  "Run the pending coalesced pushes now (the debounce timer's target).
Re-pushes each owner recorded in `jetpacs-async--pending-owners'.  An entry
created outside any `with-jetpacs-owner' has no owner and therefore no
surface to re-render, which is a programming error in the caller, so it is
reported rather than silently dropped."
  (when (timerp jetpacs-async--push-timer)
    (cancel-timer jetpacs-async--push-timer))
  (setq jetpacs-async--push-timer nil)
  (let ((owners (nreverse jetpacs-async--pending-owners)))
    (setq jetpacs-async--pending-owners nil)
    (when (fboundp 'jetpacs-shell-push)
      (dolist (owner owners)
        (if (null owner)
            (display-warning
             'jetpacs-async
             "completion outside `with-jetpacs-owner': no surface to re-render"
             :warning)
          ;; The shell no-ops for an owner with no live root.  Isolated
          ;; per owner (the drain-discipline of `jetpacs-shell--on-ready'):
          ;; one owner's gate failure must not starve the rest.
          (condition-case err
              (jetpacs-shell-push owner)
            (error (message "jetpacs-async: repush of %s failed: %s"
                            owner (jetpacs-error-label err)))))))))

;; --- The loader ------------------------------------------------------------

(defun jetpacs-async--message (err)
  "Normalize ERR (a message string or an error object) to a message string."
  (cond ((stringp err) err)
        ((and (consp err) (symbolp (car err))) (error-message-string err))
        (t (format "%s" err))))

(defun jetpacs-async--settle (key entry status value)
  "Set ENTRY to STATUS with VALUE and schedule the coalesced re-render.
No-op unless ENTRY is still the live cache entry for KEY *and* still
pending: a completion for a swept entry must not push -- on a
full-tree-resend wire each ghost push costs a complete rebuild,
reserialize, and radio wake -- and only the first of competing
resolve/reject calls wins."
  (when (and (eq entry (gethash key jetpacs-async--cache))
             (eq (jetpacs-async--entry-status entry) 'pending))
    (setf (jetpacs-async--entry-status entry) status
          (jetpacs-async--entry-value entry) value)
    (cl-pushnew (jetpacs-async--entry-owner entry)
                jetpacs-async--pending-owners :test #'equal)
    (jetpacs-async--schedule-push)))

(defun jetpacs-async--start (key entry loader)
  "Start LOADER for KEY's ENTRY, catching a synchronous throw.
LOADER is (lambda (resolve reject) ...): it calls RESOLVE with the value or
REJECT with an error string, and may return a cleanup thunk stored as the
entry's cancel."
  (let ((resolve (lambda (value) (jetpacs-async--settle key entry 'ready value)))
        (reject  (lambda (err)
                   (jetpacs-async--settle key entry 'error
                                          (jetpacs-async--message err)))))
    (condition-case err
        (let ((cleanup (funcall loader resolve reject)))
          (when (functionp cleanup)
            (setf (jetpacs-async--entry-cancel entry) cleanup)))
      (error (jetpacs-async--settle key entry 'error
                                    (error-message-string err))))))

(defun jetpacs-async--read (entry)
  "The (STATUS . PAYLOAD) pair a caller reads from ENTRY."
  (pcase (jetpacs-async--entry-status entry)
    ('ready (cons 'ready (jetpacs-async--entry-value entry)))
    ('error (cons 'error (jetpacs-async--entry-value entry)))
    (_      '(pending))))

(cl-defun jetpacs-async (key loader &key owner)
  "Return the async state for KEY as (STATUS . PAYLOAD).
STATUS is `pending', `ready', or `error'.

Call this from inside a view builder.  On the first call for a fresh KEY
\(compared `equal') start LOADER once and return `(pending)'.  LOADER is a
function (lambda (RESOLVE REJECT) ...): call RESOLVE with the value or
REJECT with an error string; either stores the result and schedules a
single coalesced re-push of the owning surface, so the view re-renders and
a later call returns `(ready . VALUE)' / `(error . MESSAGE)' from cache.  A
LOADER that throws synchronously is caught and becomes `(error . MESSAGE)'
-- it never takes down the push.  LOADER may return a cleanup thunk (a
function), run when the entry is swept, to abort itself (kill a process,
cancel a timer).

The first call always reports `(pending)', even for a loader that resolves
synchronously: the value it produced surfaces on the next build (via the
push its completion scheduled), keeping one code path for sync and async
sources alike.

Eviction: a KEY not asked for in a given push is swept after that push, so
a view that stops asking for data stops paying for it.  A completion that
arrives after its entry was swept is a no-op -- no cache write, no push --
as is a second resolve/reject after the first.

OWNER scopes the entry to an app for teardown and names the surface its
completion re-pushes, defaulting to the current `with-jetpacs-owner'.  It is
captured once, at first sight of KEY, and never revised: a KEY first
requested under app A and later shared by app B stays owned by A.  Calling
this outside any owner leaves the entry unowned -- it still caches, but no
re-render can be scheduled for it.

Usage:

  (pcase (jetpacs-async (list \\='stock product-id)
                        (lambda (resolve reject)
                          (grocy--fetch-stock product-id resolve reject)))
    (`(pending . ,_) (jetpacs-progress))
    (`(error   . ,e) (jetpacs-empty-state :title \"Couldn't load\" :caption e))
    (`(ready   . ,d) (stock-card d)))"
  (let ((entry (gethash key jetpacs-async--cache)))
    (if entry
        ;; Seen before: mark it live for this generation, read the cache.
        (progn
          (setf (jetpacs-async--entry-gen entry) jetpacs-async--generation)
          (jetpacs-async--read entry))
      ;; Fresh: register a pending entry, start the loader once, report pending.
      (setq entry (jetpacs-async--entry-make
                   :status 'pending
                   :gen jetpacs-async--generation
                   :owner (or owner (bound-and-true-p jetpacs-current-owner))))
      (puthash key entry jetpacs-async--cache)
      (jetpacs-async--start key entry loader)
      '(pending))))

;; --- Eviction --------------------------------------------------------------

(defun jetpacs-async--run-cancel (entry)
  "Run ENTRY's registered cancel thunk once, swallowing its errors."
  (let ((cancel (jetpacs-async--entry-cancel entry)))
    (when cancel
      (setf (jetpacs-async--entry-cancel entry) nil)
      (condition-case err
          (funcall cancel)
        (error (message "jetpacs-async: cancel failed: %s"
                        (error-message-string err)))))))

(defun jetpacs-async--after-push ()
  "Sweep entries no build asked for this generation, then advance it.
An entry stamped with the current generation was read by the build that
just pushed and survives; one stamped earlier belongs to a view that
stopped asking, so its cancel runs and the entry is dropped.  Registered on
`jetpacs-shell-after-push-hook' by `jetpacs-shell'."
  (let ((gen jetpacs-async--generation))
    (maphash (lambda (key entry)
               (when (< (jetpacs-async--entry-gen entry) gen)
                 (jetpacs-async--run-cancel entry)
                 (remhash key jetpacs-async--cache)))
             jetpacs-async--cache))
  (cl-incf jetpacs-async--generation))

(defun jetpacs-async-clear-owner (owner)
  "Drop every async entry scoped to OWNER (an app id), running its cancels.
Called on app teardown, so a torn-down app leaks no loads."
  (maphash (lambda (key entry)
             (when (equal (jetpacs-async--entry-owner entry) owner)
               (jetpacs-async--run-cancel entry)
               (remhash key jetpacs-async--cache)))
           jetpacs-async--cache)
  (setq jetpacs-async--pending-owners
        (delete owner jetpacs-async--pending-owners)))

(defun jetpacs-async-reset ()
  "Drop all async state, running every cancel thunk.  For teardown and tests."
  (maphash (lambda (_key entry) (jetpacs-async--run-cancel entry))
           jetpacs-async--cache)
  (clrhash jetpacs-async--cache)
  (setq jetpacs-async--generation 0)
  (setq jetpacs-async--pending-owners nil)
  (when (timerp jetpacs-async--push-timer)
    (cancel-timer jetpacs-async--push-timer))
  (setq jetpacs-async--push-timer nil))

;; The floor's reset seam.  Registered here rather than named by
;; `jetpacs-test-reset-state', so this module's reset survives a rename;
;; `add-hook' on a not-yet-defined hook is deliberate — this file loads
;; BEFORE `jetpacs-surfaces' (see the forward declarations above) and the
;; `defvar' there leaves an already-populated value alone.
(add-hook 'jetpacs-reset-functions #'jetpacs-async-reset)

(provide 'jetpacs-async)
;;; jetpacs-async.el ends here
