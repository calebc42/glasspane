;;; jetpacs-reader.el --- Reusable document reader host -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; A mode-neutral reader extension point for the Files edit screen.
;; Adapters recognize paths and provide a rendered body plus optional
;; top-bar actions.  The host owns only document identity, the
;; rendered/plain choice, action freshness, and composition with Files;
;; parsing, visibility, search, and structured actions remain in the
;; mode adapter.  `jetpacs-reader-org' is the first consumer, while an
;; Elisp reader can reuse this host without importing Org policy.
;;
;; Reader state is keyed by canonical path and never rides in an action
;; as authority.  Every device toggle is checked against
;; `jetpacs-files-current-edit-path' before it changes state, so a stale
;; screen cannot select a different document merely by replaying args.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-files)

(cl-defstruct (jetpacs-reader-adapter
               (:constructor jetpacs-reader-adapter-create))
  "A mode-specific reader adapter.
PREDICATE receives a path.  RENDER returns one root node.  ACTIONS,
when non-nil, returns a list of top-bar action nodes.  TRANSITION, when
non-nil, receives (PATH PRESENTATION) immediately before a validated
reader/editor switch."
  id predicate render actions transition)

(defvar jetpacs-reader--adapters nil
  "Ordered list of registered `jetpacs-reader-adapter' objects.")

(defvar jetpacs-reader--state (make-hash-table :test #'equal)
  "Canonical path to adapter-owned state plist.")

(defvar jetpacs-reader--installed nil
  "Non-nil while the Files seams and generic action are installed.")

(defun jetpacs-reader--key (path)
  "Return a stable local state key for PATH."
  (when (stringp path)
    (condition-case nil
        (file-truename path)
      (error (expand-file-name path)))))

(cl-defun jetpacs-reader-register (id &key predicate render actions transition)
  "Register or replace reader adapter ID.
PREDICATE and RENDER are required functions; ACTIONS is optional.
Registration order is stable when replacing an existing ID."
  (unless (symbolp id)
    (error "jetpacs-reader-register: ID must be a symbol"))
  (unless (functionp predicate)
    (error "jetpacs-reader-register: PREDICATE must be a function"))
  (unless (functionp render)
    (error "jetpacs-reader-register: RENDER must be a function"))
  (when (and actions (not (functionp actions)))
    (error "jetpacs-reader-register: ACTIONS must be a function or nil"))
  (when (and transition (not (functionp transition)))
    (error "jetpacs-reader-register: TRANSITION must be a function or nil"))
  (let ((adapter (jetpacs-reader-adapter-create
                  :id id :predicate predicate :render render
                  :actions actions :transition transition))
        (cell (cl-find id jetpacs-reader--adapters
                       :key #'jetpacs-reader-adapter-id)))
    (if cell
        (setf (car (memq cell jetpacs-reader--adapters)) adapter)
      (setq jetpacs-reader--adapters
            (append jetpacs-reader--adapters (list adapter))))
    id))

(defun jetpacs-reader-unregister (id)
  "Remove reader adapter ID."
  (setq jetpacs-reader--adapters
        (cl-delete id jetpacs-reader--adapters
                   :key #'jetpacs-reader-adapter-id))
  id)

(defun jetpacs-reader-adapter-for (path)
  "Return the first adapter accepting PATH, isolating bad predicates."
  (cl-find-if
   (lambda (adapter)
     (condition-case err
         (funcall (jetpacs-reader-adapter-predicate adapter) path)
       (error
        (message "jetpacs-reader: adapter %s predicate failed: %s"
                 (jetpacs-reader-adapter-id adapter)
                 (error-message-string err))
        nil)))
   jetpacs-reader--adapters))

(defun jetpacs-reader-state-get (path property &optional default)
  "Return PATH state PROPERTY, or DEFAULT when it is absent."
  (let ((state (gethash (jetpacs-reader--key path) jetpacs-reader--state)))
    (if (plist-member state property)
        (plist-get state property)
      default)))

(defun jetpacs-reader-state-set (path property value)
  "Set PATH state PROPERTY to VALUE and return VALUE."
  (let* ((key (jetpacs-reader--key path))
         (state (copy-sequence (gethash key jetpacs-reader--state))))
    (when key
      (puthash key (plist-put state property value) jetpacs-reader--state))
    value))

(defun jetpacs-reader-active-p (path)
  "Whether PATH currently uses its registered rendered reader."
  (and (jetpacs-reader-adapter-for path)
       (not (eq (jetpacs-reader-state-get path :presentation 'reader)
                'editor))))

(defun jetpacs-reader-current-path-p (path)
  "Whether PATH is the document on the live Files edit screen."
  (let ((current (jetpacs-files-current-edit-path)))
    (and (stringp path) (stringp current)
         (equal (jetpacs-reader--key path)
                (jetpacs-reader--key current)))))

(defun jetpacs-reader-refresh (params)
  "Schedule a refresh of PARAMS' source surface."
  (jetpacs-buffer-defer-refresh (plist-get params :surface)))

(defun jetpacs-reader--files-body (path)
  "Files body seam: render PATH when its reader is active."
  (when-let* ((adapter (and (jetpacs-reader-active-p path)
                            (jetpacs-reader-adapter-for path))))
    (condition-case err
        (funcall (jetpacs-reader-adapter-render adapter) path)
      (error
       (message "jetpacs-reader: adapter %s render failed: %s"
                (jetpacs-reader-adapter-id adapter)
                (error-message-string err))
       (jetpacs-empty-state
        :icon "error" :title "Reader failed"
        :caption "Switch to text editing to recover this document.")))))

(defun jetpacs-reader--files-actions (path)
  "Files actions seam: generic presentation toggle plus adapter actions."
  (when-let* ((adapter (jetpacs-reader-adapter-for path)))
    (let ((active (jetpacs-reader-active-p path)))
      (cons
       (jetpacs-icon-button
        (if active "edit" "preview")
        (jetpacs-action "jetpacs.reader.toggle" :args (list :path path))
        :content-description (if active "Edit as text" "Show reader"))
       (when-let* ((builder (jetpacs-reader-adapter-actions adapter)))
         (condition-case err
             (funcall builder path)
           (error
            (message "jetpacs-reader: adapter %s actions failed: %s"
                     (jetpacs-reader-adapter-id adapter)
                     (error-message-string err))
            nil)))))))

(defun jetpacs-reader--toggle (args params)
  "Handle the generic reader/editor presentation toggle."
  (let ((path (plist-get args :path)))
    (cond
     ((not (and (stringp path) (jetpacs-reader-adapter-for path)))
      'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-reader-current-path-p path)) 'stale)
     (t
      (let* ((adapter (jetpacs-reader-adapter-for path))
             (presentation
              (if (jetpacs-reader-active-p path) 'editor 'reader)))
        (condition-case err
            (progn
              (when-let ((transition
                          (jetpacs-reader-adapter-transition adapter)))
                (funcall transition path presentation))
              (jetpacs-reader-state-set path :presentation presentation)
              (jetpacs-reader-refresh params)
              'accepted)
          (error
           (message "jetpacs-reader: adapter %s transition failed: %s"
                    (jetpacs-reader-adapter-id adapter)
                    (error-message-string err))
           'rejected)))))))

(defun jetpacs-reader-reset ()
  "Forget every document's ephemeral reader presentation state."
  (clrhash jetpacs-reader--state))

(defun jetpacs-reader-install ()
  "Install the generic reader into Files, idempotently."
  (unless jetpacs-reader--installed
    (setq jetpacs-reader--installed t)
    (add-hook 'jetpacs-files-editor-body-functions
              #'jetpacs-reader--files-body)
    (add-hook 'jetpacs-files-editor-actions-functions
              #'jetpacs-reader--files-actions)
    (add-hook 'jetpacs-reset-functions #'jetpacs-reader-reset)
    (jetpacs-defaction "jetpacs.reader.toggle" #'jetpacs-reader--toggle))
  t)

(defun jetpacs-reader-uninstall ()
  "Detach the generic reader host from Files."
  (when jetpacs-reader--installed
    (setq jetpacs-reader--installed nil)
    (remove-hook 'jetpacs-files-editor-body-functions
                 #'jetpacs-reader--files-body)
    (remove-hook 'jetpacs-files-editor-actions-functions
                 #'jetpacs-reader--files-actions)
    (remove-hook 'jetpacs-reset-functions #'jetpacs-reader-reset)
    (jetpacs-undefaction "jetpacs.reader.toggle"))
  t)

(defun jetpacs-reader-unload-function ()
  "Unload hygiene for the reader host."
  (jetpacs-reader-uninstall)
  (setq jetpacs-reader--adapters nil)
  (jetpacs-reader-reset)
  nil)

(provide 'jetpacs-reader)
;;; jetpacs-reader.el ends here
