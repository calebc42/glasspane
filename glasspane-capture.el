;;; glasspane-capture.el --- Glasspane org capture: share intake + the sheet chain -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The legacy capture surface retained only for GR-4 rollback: the template
;; picker and field-form sheets, and the share-sheet intake that feeds
;; them.  Native capture now lives in `jetpacs-org-capture'; this copy stays
;; entirely downstream and is inert unless `glasspane-capture-enabled'.
;; The v1 select→form→submit VERB chain collapsed into the S3
;; dialog shape: a picker button concludes its sheet with the template
;; key, the conclusion callback carries the form sheet, the form's
;; Capture gathers its fields (`jetpacs-dialog-submit'
;; :capture-fields), and the capture runs from that conclusion —
;; org.capture.select/.cancel/.submit have no wire existence anymore
;; (Cancel is the `dialog.dismiss' builtin).
;;
;; Retired against v1 (the plan's retirement list + G5 section):
;;
;; - The widget:agenda and tile:custom1 pushes (v1 capture:6-53):
;;   no widget/tile node vocabulary and no Companion renderer
;;   (FOUNDATION-GAPS #1, STOP).  Their queued header actions die with
;;   them — which is why neither of T4's capture ttl sites (:32,:50)
;;   survives to audit.
;; - `jetpacs-dialog-style' (v1:55-59): no global style variable in
;;   v3; the bottom-sheet opinion is per-dialog (S3), carried by
;;   `glasspane-capture--show-dialog'.
;; - `jetpacs-apps-set-default-fab' (v1:61-67): FOUNDATION-GAPS #2 —
;;   the capture FAB is reimplemented per-screen via chrome `:fab' on
;;   the screens that want it (G5's daily surfaces); this file owns
;;   only the verbs and the sheets.
;; - The `jetpacs-form' registry (v1:109-124 and every -reset/-seed/
;;   -field-id/-value site): S2/S3 — seeding is the field's `:value',
;;   values ride the dialog conclusion, and nothing persists
;;   device-side past the sheet, so the id-rotation trick has nothing
;;   left to defend against.
;;
;; share.text / org.capture.share stay registered: cheap offline-replay
;; entry points.  Companion-side emission is unverified until the G9
;; device gate (FOUNDATION-GAPS #3).

;;; Code:

(require 'cl-lib)
(require 'ebp)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-org-capture)
(require 'glasspane-ui)

(defvar glasspane-capture-enabled nil
  "Non-nil to register the legacy capture engine during rollback only.
The native Org capture module is the default owner after GR-4.  This flag and
file remain through the soak window so the cutover can be reversed without a
code rollback.")

;;;; Shared-in content (the share sheet's pending payload)

(defvar glasspane-capture--shared-text nil
  "Body text shared from another app, pending the next capture submit.")

(defvar glasspane-capture--shared-subject nil
  "Subject shared from another app; seeds the capture Headline field.")

(defun glasspane-capture--clear-shared ()
  "Forget the shared-in payload (a submit consumed it, or the user bailed)."
  (setq glasspane-capture--shared-text nil
        glasspane-capture--shared-subject nil))

;;;; The one live sheet (S3)

(defvar glasspane-capture--dialog nil
  "The live capture sheet, (:request-id ID), or nil.
One slot on purpose: the flow shows one sheet at a time, and a new
entry (a share arriving over an open picker) must retire the old
sheet, never stack a second.")

(defun glasspane-capture-dialog-close ()
  "Retire the live capture sheet (the S3 handler-side dismissal).
`ebp-client-abandon' sends rpc.cancel; the Companion concludes the
dialog with error 1301, which the show callback ignores because the
slot no longer points at that sheet."
  (let ((sheet glasspane-capture--dialog))
    (setq glasspane-capture--dialog nil)
    (when-let* ((client (jetpacs-client))
                (request-id (plist-get sheet :request-id)))
      (ignore-errors (ebp-client-abandon client request-id)))))

(defun glasspane-capture--show-dialog (id spec on-submit)
  "Show SPEC as bottom sheet ID; ON-SUBMIT receives the conclusion RESULT.
`:style \"sheet\"' is v1's app-wide `jetpacs-dialog-style' opinion made
per-dialog (S3 — no global variable exists to set).  Any live capture
sheet is abandoned first.  A dismissal drops the shared-in payload —
but only when THIS sheet is still the live one: the abandon's 1301
lands asynchronously, after a successor may already have stashed a
new share it must not clobber."
  (when-let* ((client (jetpacs-client)))
    (glasspane-capture-dialog-close)
    (let* ((self (list :request-id nil))
           (request-id
            (ebp-client-dialog-show
             client id spec
             :style "sheet"
             :callback
             (lambda (status result _error)
               (when (eq glasspane-capture--dialog self)
                 (setq glasspane-capture--dialog nil)
                 (if (equal status "submitted")
                     (funcall on-submit result)
                   (glasspane-capture--clear-shared)))))))
      (when request-id
        (plist-put self :request-id request-id)
        (setq glasspane-capture--dialog self)))))

;;;; Sheet bodies (pure builders — the gate serializes these)

(defun glasspane-capture--picker-body (templates)
  "The template-picker sheet body over TEMPLATES
\(`ebp-org-capture-templates' plists).  Each template button concludes
the dialog with its key — the v1 org.capture.select verb died with
the chain; the shared-in preview shows what this capture will carry."
  (apply #'jetpacs-column
         (append
          (list (jetpacs-text "Quick Capture" :style "title")
                (jetpacs-text "Select a template:" :style "caption"))
          (when glasspane-capture--shared-text
            (list (jetpacs-card
                   (jetpacs-text
                    (truncate-string-to-width
                     glasspane-capture--shared-text 200 nil nil "…")
                    :style "caption"))))
          (mapcar (lambda (tmpl)
                    (jetpacs-button
                     (jetpacs-scalar-text
                      (or (plist-get tmpl :description)
                          (plist-get tmpl :key)))
                     (jetpacs-dialog-submit :value (plist-get tmpl :key))
                     :variant "outlined"))
                  templates)
          (list (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)
                                :variant "text")
                :spacing 8))))

(defun glasspane-capture--field-pairs (tmpl)
  "((PROMPT . FIELD-ID) …) for TMPL, in template order.
Prompts are human text (\"Headline\" today, spaces tomorrow) riding
into §4.4 field ids, so each id mints through `jetpacs-wire-id' —
deterministic, so the conclusion re-derives exactly the mapping the
builder used."
  (mapcar (lambda (p) (cons p (jetpacs-wire-id "capf" p)))
          (append (plist-get tmpl :prompts) nil)))

(defun glasspane-capture--form-body (tmpl)
  "The field-form sheet body for template TMPL.
A shared-in subject seeds the Headline field via `:value' (S2: the
conclusion echoes the fields back, no state round trip).  Capture is
the `dialog.submit' builtin gathering every field id; the v1 form
registry and its state.changed bookkeeping have no successor."
  (let ((pairs (glasspane-capture--field-pairs tmpl)))
    (apply #'jetpacs-column
           (append
            (list (jetpacs-text
                   (format "Capture: %s"
                           (jetpacs-scalar-text
                            (or (plist-get tmpl :description)
                                (plist-get tmpl :key))))
                   :style "title"))
            (mapcar (lambda (cell)
                      (jetpacs-text-input
                       (cdr cell)
                       :label (car cell)
                       :value (and (equal (car cell) "Headline")
                                   glasspane-capture--shared-subject)))
                    pairs)
            (list (jetpacs-row
                   (jetpacs-spacer :weight 1)
                   (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)
                                   :variant "text")
                   (jetpacs-spacer :width 8)
                   (jetpacs-button
                    "Capture"
                    (jetpacs-dialog-submit
                     :capture-fields (mapcar #'cdr pairs))))
                  :spacing 8)))))

;;;; The chain (picker → form → run)

(defun glasspane-capture--template (key)
  "The current template plist for KEY, or nil when it vanished."
  (cl-find-if (lambda (tmpl) (equal (plist-get tmpl :key) key))
              (ebp-org-capture-templates)))

(defun glasspane-capture--show-picker (params)
  "Show the template picker; its conclusion carries the form sheet.
Templates are read at show time and AGAIN at the conclusion (SPEC
23.2): the sheet may outlive the list it was rendered from, so the
submitted key revalidates against fresh templates."
  (glasspane-capture--show-dialog
   "glasspane-capture-picker"
   (glasspane-capture--picker-body (ebp-org-capture-templates))
   (lambda (result)
     (let ((tmpl (glasspane-capture--template (plist-get result :value))))
       (if (null tmpl)
           (progn
             (jetpacs-toast "That template no longer exists")
             (glasspane-capture--clear-shared))
         (glasspane-capture--show-form tmpl params))))))

(defun glasspane-capture--show-form (tmpl params)
  "Show TMPL's field form; its conclusion runs the capture."
  (let ((key (plist-get tmpl :key))
        (pairs (glasspane-capture--field-pairs tmpl)))
    (glasspane-capture--show-dialog
     "glasspane-capture-form"
     (glasspane-capture--form-body tmpl)
     (lambda (result)
       (glasspane-capture--submit key pairs
                                  (plist-get result :fields) params)))))

(defun glasspane-capture--submit (key pairs fields params)
  "Run capture KEY from the concluded form's FIELDS plist; non-nil on success.
PAIRS maps prompts to the field ids the form minted; a missing or
non-string field lands as \"\" (`ebp-org-capture-fill' then honours
the template's own default).  The success report — snackbar, cache
drop, refresh — fires only after `ebp-org-capture-run' has RETURNED:
durable first, celebration second (the rung's rule; a swallowed error
that still celebrates is the G7 defect class)."
  (let ((values (mapcar (lambda (cell)
                          (let ((v (plist-get
                                    fields
                                    (intern (concat ":" (cdr cell))))))
                            (cons (car cell) (if (stringp v) v ""))))
                        pairs)))
    (condition-case err
        (progn
          (ebp-org-capture-run key values glasspane-capture--shared-text)
          (glasspane-capture--clear-shared)
          (ebp-org-cache-invalidate 'glasspane)
          (jetpacs-shell-notify "Captured ✓")
          (glasspane-ui--defer-refresh params)
          t)
      (error
       ;; The raw error stays in *Messages*; the wire carries the
       ;; SPEC 23.3 label at most.
       (message "glasspane: capture failed: %s" (jetpacs-error-label err))
       (glasspane-capture--clear-shared)
       (jetpacs-toast "Capture failed")
       nil))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-capture--on-show (_args params)
  "Open the template picker sheet."
  (if (null (jetpacs-client))
      'rejected
    (jetpacs-flow-continue
     (lambda () (glasspane-capture--show-picker params)))
    'accepted))

(defun glasspane-capture--on-share (args params)
  "Android share sheet → capture: stash text/subject, open the picker.
The stash is written BEFORE the client guard on purpose — a share is
its payload, and the next picker consumes whatever the last share
left.  Blank-trimmed members stash as nil; a share with only a
subject still captures (it doubles as the body — the v1 contract)."
  (let ((text (plist-get args :text))
        (subject (plist-get args :subject)))
    (setq glasspane-capture--shared-text
          (and (stringp text)
               (not (string-empty-p (string-trim text)))
               (string-trim text))
          glasspane-capture--shared-subject
          (and (stringp subject)
               (not (string-empty-p (string-trim subject)))
               (string-trim subject)))
    (unless glasspane-capture--shared-text
      (setq glasspane-capture--shared-text
            glasspane-capture--shared-subject)))
  (if (null (jetpacs-client))
      'rejected
    (jetpacs-flow-continue
     (lambda () (glasspane-capture--show-picker params)))
    'accepted))

;;;; Registration

(defconst glasspane-capture--verbs
  '("org.capture.show" "share.text" "org.capture.share")
  "The verbs the capture module owns, for the register/unregister sweep.
`share.text' is the Companion's app-agnostic share verb;
`org.capture.share' is the pre-rename id, kept so shares queued by an
older Companion still replay — both route to the same handler.")

(defun glasspane-capture--undef-if-handler (name handler)
  "Undefine NAME only when HANDLER is still the legacy implementation."
  (when (eq (gethash name jetpacs-action-handlers) handler)
    (jetpacs-undefaction name)))

(defun glasspane-capture-register ()
  "Register the legacy capture verbs when their rollback flag is enabled.
Called from `glasspane-register', never at this file's load (the G0
gate contract).  Idempotent: re-registration replaces the handlers in
place."
  (if glasspane-capture-enabled
      (with-jetpacs-owner "glasspane"
        (jetpacs-defaction "org.capture.show" #'glasspane-capture--on-show
                           :doc "Open the org capture template picker")
        ;; The two share verbs are GLOBAL (the `jetpacs.launcher.open'
        ;; precedent, jetpacs-launcher.el:148-162): a share is attributed
        ;; by the COMPANION, not by one of this app's surfaces, so its wire
        ;; surface may legitimately be a string glasspane does not own.
        (jetpacs-defaction "share.text" #'glasspane-capture--on-share
                           :any-surface t)
        (jetpacs-defaction "org.capture.share" #'glasspane-capture--on-share
                           :any-surface t))
    ;; A live flag flip retires legacy handlers and volatile state.  The
    ;; canonical upstream handlers already occupying these names are untouched
    ;; because each removal is guarded by handler identity.
    (glasspane-capture--undef-if-handler
     "org.capture.show" #'glasspane-capture--on-show)
    (dolist (name '("share.text" "org.capture.share"))
      (glasspane-capture--undef-if-handler
       name #'glasspane-capture--on-share))
    (glasspane-capture-dialog-close)
    (glasspane-capture--clear-shared)))

(defun glasspane-capture-unregister ()
  "Drop the capture verbs, retire any live sheet, forget shared state."
  (glasspane-capture--undef-if-handler
   "org.capture.show" #'glasspane-capture--on-show)
  (dolist (name '("share.text" "org.capture.share"))
    (glasspane-capture--undef-if-handler name #'glasspane-capture--on-share))
  (glasspane-capture-dialog-close)
  (glasspane-capture--clear-shared))

(provide 'glasspane-capture)
;;; glasspane-capture.el ends here
