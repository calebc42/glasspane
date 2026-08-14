;;; jetpacs-editor.el --- Reusable mode-aware editor host -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Composes mode-specific editor behavior into the Files editor without
;; teaching Files about Org, Elisp, or any future language app.  An
;; adapter may prepare a visiting buffer, replace the plain editor body
;; for a mode-specific coordinate space, contribute a toolbar and
;; actions, provide one FAB, and react after a durable save.  The
;; adapter may also apply a correctness-critical pre-write transform
;; to a synchronized buffer; an error there aborts Files' write.  The
;; dynamic `jetpacs-files-editor-context' tells an adapter whether the
;; current editor is synchronized, allowing command operations only
;; where SPEC 17.7 permits them.
;;
;; This file intentionally does not redefine the `jetpacs-editor'
;; widget constructor from `jetpacs-widgets'; it hosts that constructor
;; through `jetpacs-editor-register' and the Files seams.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-files)

(cl-defstruct (jetpacs-editor-adapter
               (:constructor jetpacs-editor-adapter-create))
  "A mode-specific editor adapter.
PREDICATE receives a path.  SETUP, BODY, TOOLBAR, ACTIONS, FAB, and
AFTER-SAVE are optional functions of that path.  BEFORE-SAVE receives
the path and synchronized buffer."
  id predicate setup body toolbar actions fab before-save after-save)

(defvar jetpacs-editor--adapters nil
  "Ordered list of registered `jetpacs-editor-adapter' objects.")

(defvar jetpacs-editor--installed nil
  "Non-nil while the editor host is attached to Files.")

(cl-defun jetpacs-editor-register
    (id &key predicate setup body toolbar actions fab before-save after-save)
  "Register or replace editor adapter ID.
PREDICATE is required.  BEFORE-SAVE receives (PATH BUFFER); each other
non-nil extension function receives the edited PATH."
  (unless (symbolp id)
    (error "jetpacs-editor-register: ID must be a symbol"))
  (unless (functionp predicate)
    (error "jetpacs-editor-register: PREDICATE must be a function"))
  (dolist (entry `((setup . ,setup) (body . ,body) (toolbar . ,toolbar)
                   (actions . ,actions) (fab . ,fab)
                   (before-save . ,before-save)
                   (after-save . ,after-save)))
    (when (and (cdr entry) (not (functionp (cdr entry))))
      (error "jetpacs-editor-register: %s must be a function or nil"
             (car entry))))
  (let ((adapter (jetpacs-editor-adapter-create
                  :id id :predicate predicate :setup setup
                  :body body :toolbar toolbar :actions actions :fab fab
                  :before-save before-save
                  :after-save after-save))
        (cell (cl-find id jetpacs-editor--adapters
                       :key #'jetpacs-editor-adapter-id)))
    (if cell
        (setf (car (memq cell jetpacs-editor--adapters)) adapter)
      (setq jetpacs-editor--adapters
            (append jetpacs-editor--adapters (list adapter))))
    id))

(defun jetpacs-editor-unregister (id)
  "Remove editor adapter ID."
  (setq jetpacs-editor--adapters
        (cl-delete id jetpacs-editor--adapters
                   :key #'jetpacs-editor-adapter-id))
  id)

(defun jetpacs-editor-adapters-for (path)
  "Return adapters accepting PATH, isolating bad predicates."
  (cl-remove-if-not
   (lambda (adapter)
     (condition-case err
         (funcall (jetpacs-editor-adapter-predicate adapter) path)
       (error
        (message "jetpacs-editor: adapter %s predicate failed: %s"
                 (jetpacs-editor-adapter-id adapter)
                 (error-message-string err))
        nil)))
   jetpacs-editor--adapters))

(defun jetpacs-editor--call (adapter accessor path)
  "Call ADAPTER's ACCESSOR function with PATH, isolating failures."
  (when-let* ((fn (funcall accessor adapter)))
    (condition-case err
        (funcall fn path)
      (error
       (message "jetpacs-editor: adapter %s extension failed: %s"
                (jetpacs-editor-adapter-id adapter)
                (error-message-string err))
       nil))))

(defun jetpacs-editor--files-setup (path)
  "Run adapter setup and return the first mode-specific editor body."
  (let ((adapters (jetpacs-editor-adapters-for path)))
    (dolist (adapter adapters)
      (jetpacs-editor--call adapter #'jetpacs-editor-adapter-setup path))
    (cl-loop for adapter in adapters
             thereis (jetpacs-editor--call
                      adapter #'jetpacs-editor-adapter-body path))))

(defun jetpacs-editor--files-toolbar (path)
  "Return the first mode toolbar for PATH."
  (cl-loop for adapter in (jetpacs-editor-adapters-for path)
           thereis (jetpacs-editor--call
                    adapter #'jetpacs-editor-adapter-toolbar path)))

(defun jetpacs-editor--files-actions (path)
  "Return all mode-specific top-bar actions for PATH."
  (cl-loop for adapter in (jetpacs-editor-adapters-for path)
           append (or (jetpacs-editor--call
                       adapter #'jetpacs-editor-adapter-actions path)
                      nil)))

(defun jetpacs-editor--files-fab (path)
  "Return the first mode-specific FAB for PATH."
  (cl-loop for adapter in (jetpacs-editor-adapters-for path)
           thereis (jetpacs-editor--call
                    adapter #'jetpacs-editor-adapter-fab path)))

(defun jetpacs-editor--files-after-save (path)
  "Notify every matching adapter that PATH was durably saved."
  (dolist (adapter (jetpacs-editor-adapters-for path))
    (jetpacs-editor--call adapter
                          #'jetpacs-editor-adapter-after-save path)))

(defun jetpacs-editor--files-before-save (path buffer)
  "Run every matching adapter's required pre-write step on BUFFER.
Errors deliberately propagate into Files' save gate: swallowing an Org
Crypt failure would permit cleartext persistence."
  (dolist (adapter (jetpacs-editor-adapters-for path))
    (when-let ((fn (jetpacs-editor-adapter-before-save adapter)))
      (funcall fn path buffer))))

(defun jetpacs-editor-install ()
  "Install the generic editor host into Files, idempotently."
  (unless jetpacs-editor--installed
    (setq jetpacs-editor--installed t)
    (add-hook 'jetpacs-files-editor-body-functions
              #'jetpacs-editor--files-setup)
    (add-hook 'jetpacs-files-editor-actions-functions
              #'jetpacs-editor--files-actions)
    (add-hook 'jetpacs-files-editor-toolbar-functions
              #'jetpacs-editor--files-toolbar)
    (add-hook 'jetpacs-files-editor-fab-functions
              #'jetpacs-editor--files-fab)
    (add-hook 'jetpacs-files-before-buffer-save-hook
              #'jetpacs-editor--files-before-save)
    (add-hook 'jetpacs-files-after-save-hook
              #'jetpacs-editor--files-after-save))
  t)

(defun jetpacs-editor-uninstall ()
  "Detach the generic editor host from Files."
  (when jetpacs-editor--installed
    (setq jetpacs-editor--installed nil)
    (remove-hook 'jetpacs-files-editor-body-functions
                 #'jetpacs-editor--files-setup)
    (remove-hook 'jetpacs-files-editor-actions-functions
                 #'jetpacs-editor--files-actions)
    (remove-hook 'jetpacs-files-editor-toolbar-functions
                 #'jetpacs-editor--files-toolbar)
    (remove-hook 'jetpacs-files-editor-fab-functions
                 #'jetpacs-editor--files-fab)
    (remove-hook 'jetpacs-files-before-buffer-save-hook
                 #'jetpacs-editor--files-before-save)
    (remove-hook 'jetpacs-files-after-save-hook
                 #'jetpacs-editor--files-after-save))
  t)

(defun jetpacs-editor-unload-function ()
  "Unload hygiene for the editor host."
  (jetpacs-editor-uninstall)
  (setq jetpacs-editor--adapters nil)
  nil)

(provide 'jetpacs-editor)
;;; jetpacs-editor.el ends here
