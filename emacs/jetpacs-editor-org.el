;;; jetpacs-editor-org.el --- Org adapter for the Jetpacs editor -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Supplies the Org editing half of the Org Mode app: Orgro-compatible
;; formatting and insertion snippets on every editor rung, built-in Org
;; structural commands on synchronized editors, the add-heading FAB,
;; Org Crypt re-encryption before a real buffer save, and cache
;; invalidation after a durable Files save.
;;
;; Commands use the existing SPEC 17.7 `edit.command' path.  They run in
;; the attached Org buffer at the device caret and pass through
;; `jetpacs-emacs-ui-command-predicate'; a plain editor receives only
;; local snippet and line operations, so it remains valid offline.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-crypt)
(require 'ebp-org)
(require 'jetpacs-editor)
(require 'jetpacs-reader-org)
(require 'jetpacs-org-toolbar)
(require 'jetpacs-org-dialogs)
(require 'jetpacs-widgets)

(defvar jetpacs-editor-org--registered nil
  "Non-nil while the Org editor adapter is registered.")

(defun jetpacs-editor-org--synced-p ()
  "Whether the Files builder is authoring a synchronized editor."
  (and (plist-get jetpacs-files-editor-context :document) t))

(defun jetpacs-editor-org--format-items ()
  "Additional Orgro formatting and insertion toolbar items."
  (list
   (jetpacs-toolbar-item :icon "format_underlined" :label "U"
                         :snippet "_${selection}_")
   (jetpacs-toolbar-item :icon "code" :label "="
                         :snippet "=${selection}=")
   (jetpacs-toolbar-item :icon "subscript" :label "x₂"
                         :snippet "_{${selection}}")
   (jetpacs-toolbar-item :icon "superscript" :label "x²"
                         :snippet "^{${selection}}")
   (jetpacs-toolbar-item :icon "horizontal_rule" :label "Rule"
                         :snippet "-----" :placement "block")
   (jetpacs-toolbar-item
    :icon "format_quote" :label "Block"
    :menu
    (mapcar
     (lambda (kind)
       (jetpacs-toolbar-item
        :label kind
        :snippet (format "#+begin_%s\n${selection}${cursor}\n#+end_%s"
                         (downcase kind) (downcase kind))
        :placement "block"))
     '("Quote" "Example" "Verse" "Center" "Comment")))
   (jetpacs-toolbar-item :icon "format_list_bulleted" :label "Table"
                         :snippet "| ${cursor} |  |\n|---+---|\n|   |  |"
                         :placement "block")
   (jetpacs-toolbar-item :icon "format_quote" :label "Footnote"
                         :snippet "[fn:${input:Name}]")
   (jetpacs-toolbar-item :icon "library_books" :label "Cite"
                         :snippet "[cite:@${input:Key}]")
   (jetpacs-toolbar-item :icon "attachment" :label "Attach"
                         :snippet "[[attachment:${input:File}]]")))

(defun jetpacs-editor-org--command-items ()
  "Built-in Org command menu for a synchronized editor."
  (when (jetpacs-editor-org--synced-p)
    (list
     (jetpacs-toolbar-item
      :icon "more_vert" :label "Org"
      :menu
      (list
       (jetpacs-toolbar-item :label "Insert heading"
                             :command "org-insert-heading-respect-content")
       (jetpacs-toolbar-item :label "Cycle TODO" :command "org-todo")
       (jetpacs-toolbar-item :label "Schedule" :command "org-schedule")
       (jetpacs-toolbar-item :label "Deadline" :command "org-deadline")
       (jetpacs-toolbar-item :label "Refile" :command "org-refile")
       (jetpacs-toolbar-item
        :label "Encrypt section"
        :command "jetpacs-editor-org-encrypt-entry"))))))

(defun jetpacs-editor-org--toolbar (_path)
  "Return the complete Org toolbar for the current editor rung."
  (append (jetpacs-org-toolbar)
          (jetpacs-editor-org--format-items)
          (jetpacs-editor-org--command-items)))

(defun jetpacs-editor-org--body (path)
  "Return a plain section editor when PATH's Org buffer is narrowed.
SPEC 19 positions are whole-document offsets, so a narrowed document
must not pretend to be synchronized.  The reader transition has
already downgraded Files; this body presents exactly the accessible
subtree and records its Emacs-owned splice identity for the save gate."
  (when-let ((buffer (get-file-buffer path)))
    (with-current-buffer buffer
      (when (and (not (jetpacs-reader-active-p path))
                 (buffer-narrowed-p))
        (let* ((beg (point-min))
               (end (point-max))
               (value (buffer-substring-no-properties beg end))
               (identity (format "%s:%d:%d" path beg end))
               (context (copy-sequence jetpacs-files-editor-context)))
          (jetpacs-reader-state-set path :org-narrow-edit-beg beg)
          (jetpacs-reader-state-set path :org-narrow-edit-end end)
          (jetpacs-reader-state-set path :org-narrow-edit-tick
                                    (buffer-chars-modified-tick))
          ;; Commands cannot use whole-document sync coordinates in this
          ;; local section editor, even if a stale context still carried
          ;; the old session during a hand-built test.
          (cl-remf context :document)
          (cl-remf context :editor-id)
          (cl-remf context :buffer)
          (let ((jetpacs-files-editor-context context))
            (jetpacs-editor
             (jetpacs-claim-node-id (jetpacs-wire-id "orgnedit" identity))
             :value value
             :syntax "org"
             :toolbar (jetpacs-editor-org--toolbar path)
             :on-save
             (jetpacs-action
              "jetpacs.editor.org.save-narrowed"
              :args (list :path path
                          :mtime (plist-get
                                  jetpacs-files-editor-context :mtime))))))))))

(defun jetpacs-editor-org--setup (path)
  "Prepare PATH's live Org buffer for encrypted-entry save safety."
  (when-let* ((buffer (get-file-buffer path)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'org-mode) (org-mode))
      (add-hook 'before-save-hook #'org-encrypt-entries nil t)))
  nil)

(defun jetpacs-editor-org--fab (path)
  "Return the Org add-heading FAB for PATH."
  (jetpacs-icon-button
   "post_add"
   (jetpacs-org-add-heading-descriptor
    (buffer-name (find-file-noselect path t)))
   :content-description "Add heading"))

(defun jetpacs-editor-org--before-save (_path buffer)
  "Re-encrypt decrypted Org Crypt entries in BUFFER before Files writes."
  (with-current-buffer buffer
    (when (derived-mode-p 'org-mode)
      (org-encrypt-entries))))

(defun jetpacs-editor-org--commit-narrowed
    (true path value record buffer)
  "Splice VALUE into BUFFER's restriction and write all of TRUE.
RECORD is the current Files edit record.  Any failure before the disk
write restores the buffer byte-for-byte and then signals."
  (with-current-buffer buffer
    (let* ((original-beg (point-min))
           (original-end (point-max))
           (original-point (point))
           (original-modified (buffer-modified-p))
           (original-full
            (save-restriction
              (widen)
              (buffer-substring-no-properties (point-min) (point-max))))
           (changed nil)
           (durable nil))
      (unwind-protect
          (progn
            ;; Pre-write transforms must see the submitted section.  The
            ;; cleanup restores this speculative buffer mutation if one
            ;; of them (notably Org Crypt) cannot complete.
            (let ((inhibit-read-only t))
              (widen)
              (delete-region original-beg original-end)
              (goto-char original-beg)
              (insert value)
              (narrow-to-region original-beg (point)))
            (setq changed t)
            (jetpacs-editor--files-before-save true buffer)
            (let ((full
                   (save-restriction
                     (widen)
                     (buffer-substring-no-properties
                      (point-min) (point-max)))))
              (when (> (string-bytes full) jetpacs-files-max-bytes)
                (user-error "Edited file exceeds the save limit"))
              (let ((coding-system-for-write (plist-get record :coding)))
                (write-region full nil true nil 'silent))
              (setq durable t)
              (set-buffer-modified-p nil)
              (set-visited-file-modtime)
              (setq jetpacs-files--edit
                    (plist-put
                     (plist-put (copy-sequence record) :seed full)
                     :mtime (jetpacs-files--mtime-stamp true)))
              (jetpacs-reader-state-set
               path :org-narrow-edit-beg (point-min))
              (jetpacs-reader-state-set
               path :org-narrow-edit-end (point-max))
              (jetpacs-reader-state-set
               path :org-narrow-edit-tick (buffer-chars-modified-tick))
              full))
        (when (and changed (not durable))
          (let ((inhibit-read-only t))
            (widen)
            (delete-region (point-min) (point-max))
            (insert original-full)
            (narrow-to-region original-beg original-end)
            (goto-char (min (max original-point (point-min)) (point-max)))
            (set-buffer-modified-p original-modified))
          (jetpacs-reader-state-set path :org-narrow-edit-beg (point-min))
          (jetpacs-reader-state-set path :org-narrow-edit-end (point-max))
          (jetpacs-reader-state-set
           path :org-narrow-edit-tick (buffer-chars-modified-tick)))))))

(defun jetpacs-editor-org--save-narrowed (args params)
  "Validate, splice, and durably save one narrowed Org section."
  (let ((path (jetpacs-reader-org--action-path args params))
        (value (plist-get args :value))
        (stamp (plist-get args :mtime))
        (surface (plist-get params :surface)))
    (cond
     ((symbolp path) path)
     ((or (jetpacs-reader-active-p path) (not (stringp value))) 'rejected)
     ((> (string-bytes value) jetpacs-files-max-bytes)
      (jetpacs-shell-notify "Section is too large to save" surface)
      'rejected)
     (t
      (condition-case err
          (let* ((true (jetpacs-files--check path nil))
                 (record jetpacs-files--edit)
                 (buffer (get-file-buffer true))
                 (beg (jetpacs-reader-state-get
                       path :org-narrow-edit-beg nil))
                 (end (jetpacs-reader-state-get
                       path :org-narrow-edit-end nil))
                 (tick (jetpacs-reader-state-get
                        path :org-narrow-edit-tick nil)))
            (cond
             ((not (and (buffer-live-p buffer)
                        (equal (plist-get record :path) true)))
              'stale)
             ((not (equal stamp (jetpacs-files--mtime-stamp true)))
              (jetpacs-shell-notify "File changed on disk — not saved"
                                    surface)
              'stale)
             ((not (file-writable-p true))
              (jetpacs-shell-notify "File is not writable" surface)
              'rejected)
             ((not (with-current-buffer buffer
                     (and (buffer-narrowed-p)
                          (= (point-min) beg) (= (point-max) end)
                          (= (buffer-chars-modified-tick) tick))))
              (jetpacs-shell-notify
               "Section changed in Emacs — not saved" surface)
              'stale)
             (t
              (jetpacs-editor-org--commit-narrowed
               true path value record buffer)
              ;; Everything below is post-durability and cannot flip the
              ;; permanent action receipt to rejected.
              (jetpacs-run-isolated 'jetpacs-files-after-save-hook true)
              (condition-case post-error
                  (progn
                    (jetpacs-shell-notify
                     (format "Saved %s"
                             (jetpacs-scalar-text
                              (file-name-nondirectory true)))
                     surface)
                    (jetpacs-reader-refresh params))
                (error
                 (message "jetpacs-editor-org: post-save refresh failed: %s"
                          (jetpacs-error-label post-error))))
              'accepted)))
        (error
         (message "jetpacs-editor-org: narrowed save failed: %s"
                  (jetpacs-error-label err))
         (jetpacs-shell-notify "Section was not saved" surface)
         'rejected))))))

(defun jetpacs-editor-org--after-save (_path)
  "Invalidate memoized Org projections after a durable Files save."
  (ebp-org-cache-invalidate))

;;;###autoload
(defun jetpacs-editor-org-encrypt-entry ()
  "Tag and symmetrically encrypt the Org entry at point.
This interactive wrapper is safe for the synchronized editor command
allowlist and makes the built-in before-save scan retain the entry."
  (interactive)
  (org-back-to-heading t)
  (org-toggle-tag "crypt" 'on)
  (org-encrypt-entry))

(defun jetpacs-editor-org-register ()
  "Register the Org editor adapter, idempotently."
  (unless jetpacs-editor-org--registered
    (setq jetpacs-editor-org--registered t)
    (jetpacs-editor-register
     'org :predicate #'jetpacs-reader-org-path-p
     :setup #'jetpacs-editor-org--setup
     :body #'jetpacs-editor-org--body
     :toolbar #'jetpacs-editor-org--toolbar
     :fab #'jetpacs-editor-org--fab
     :before-save #'jetpacs-editor-org--before-save
     :after-save #'jetpacs-editor-org--after-save)
    (jetpacs-defaction "jetpacs.editor.org.save-narrowed"
                       #'jetpacs-editor-org--save-narrowed))
  t)

(defun jetpacs-editor-org-unregister ()
  "Unregister the Org editor adapter."
  (when jetpacs-editor-org--registered
    (setq jetpacs-editor-org--registered nil)
    (jetpacs-editor-unregister 'org)
    (jetpacs-undefaction "jetpacs.editor.org.save-narrowed"))
  t)

(defun jetpacs-editor-org-unload-function ()
  "Unload hygiene for the Org editor adapter."
  (jetpacs-editor-org-unregister)
  nil)

(provide 'jetpacs-editor-org)
;;; jetpacs-editor-org.el ends here
