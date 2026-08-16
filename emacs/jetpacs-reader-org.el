;;; jetpacs-reader-org.el --- Org adapter for the Jetpacs reader -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Orgro-shaped Org reader, implemented by renting built-in Org:
;; `org-cycle-overview'/`org-cycle-content' for visibility cycling,
;; `org-occur' for text and regexp sparse views,
;; `org-match-sparse-tree' for tags/properties/TODO filtering,
;; Org fontification and pretty entities for reader mode, org-crypt for
;; symmetric encrypted entries, and `jetpacs-org-render' for the wire
;; representation.  Tables, images, LaTeX, links, citations,
;; attachments, footnotes, checkbox/timestamp actions, drawers, and
;; blocks already flow through that renderer and Org's own keymaps.
;;
;; Transclusion is intentionally absent: it is not built into Org and
;; therefore does not belong in this built-in-backed adapter.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-fold)
(require 'org-crypt)
(require 'ebp-org)
(require 'jetpacs-reader)
(require 'jetpacs-org-render)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)

(defcustom jetpacs-reader-org-max-query-chars 500
  "Maximum search or sparse-tree query accepted from a reader."
  :type 'integer :group 'jetpacs-org)

(defvar jetpacs-reader-org--registered nil
  "Non-nil while the Org reader adapter and actions are registered.")

(defun jetpacs-reader-org-path-p (path)
  "Whether PATH names an Org document."
  (and (stringp path) (string-suffix-p ".org" path t)))

(defun jetpacs-reader-org--buffer (path)
  "Visit PATH and return its Org buffer."
  (let ((buf (find-file-noselect path t)))
    (with-current-buffer buf
      (unless (derived-mode-p 'org-mode) (org-mode)))
    buf))

(defun jetpacs-reader-org--reader-mode-p (path)
  "Whether PATH has Orgro-style reader typography enabled."
  (jetpacs-reader-state-get path :org-reader-mode t))

(defun jetpacs-reader-org--visibility (path)
  "PATH's global visibility state."
  (jetpacs-reader-state-get path :org-visibility 'overview))

(defun jetpacs-reader-org--apply-reader-mode (path buffer)
  "Apply PATH's reader typography to BUFFER through Org variables."
  (let ((enabled (jetpacs-reader-org--reader-mode-p path)))
    (with-current-buffer buffer
      (unless (and (eq org-hide-emphasis-markers enabled)
                   (eq org-pretty-entities enabled)
                   (eq org-hide-leading-stars enabled))
        (setq-local org-hide-emphasis-markers enabled)
        (setq-local org-pretty-entities enabled)
        (setq-local org-hide-leading-stars enabled)
        (font-lock-flush (point-min) (point-max)))
      (font-lock-ensure (point-min) (point-max)))))

(defun jetpacs-reader-org--apply-visibility (path buffer)
  "Apply PATH's selected global visibility state in BUFFER."
  (with-current-buffer buffer
    (pcase (jetpacs-reader-org--visibility path)
      ('overview (org-cycle-overview))
      ('contents (org-cycle-content))
      ('all (org-fold-show-all)))))

(defun jetpacs-reader-org--ensure-initial-visibility (path buffer)
  "Give PATH Orgro's overview first paint exactly once."
  (unless (jetpacs-reader-state-get path :org-initialized nil)
    (jetpacs-reader-org--apply-visibility path buffer)
    (jetpacs-reader-state-set path :org-initialized t)))

(defun jetpacs-reader-org--search-mode (path)
  "Return PATH's search mode: `plain', `regexp', or `sparse'."
  (jetpacs-reader-state-get path :org-search-mode 'plain))

(defun jetpacs-reader-org--clear-search-in-buffer (path buffer)
  "Remove search overlays in BUFFER and restore PATH visibility."
  (with-current-buffer buffer
    (org-remove-occur-highlights)
    (org-fold-show-all))
  (jetpacs-reader-org--apply-visibility path buffer)
  (jetpacs-reader-state-set path :org-query "")
  (jetpacs-reader-state-set path :org-hits nil))

(defun jetpacs-reader-org--apply-search (path query)
  "Apply PATH search QUERY and return its match count, or `sparse'.
Signals `user-error' for invalid or excessive input."
  (when (> (length query) jetpacs-reader-org-max-query-chars)
    (user-error "Query is too long"))
  (when (string-empty-p (string-trim query))
    (user-error "Query cannot be empty"))
  (let ((buffer (jetpacs-reader-org--buffer path)))
    (with-current-buffer buffer
      (org-remove-occur-highlights)
      (org-fold-show-all)
      (pcase (jetpacs-reader-org--search-mode path)
        ('plain (org-occur (regexp-quote query)))
        ('regexp
         (condition-case nil
             (progn (string-match-p query "") (org-occur query))
           (invalid-regexp (user-error "Invalid regular expression"))))
        ('sparse
         (condition-case nil
             (progn (org-match-sparse-tree nil query) 'sparse)
           (error (user-error "Invalid sparse-tree query"))))))))

(defun jetpacs-reader-org--search-controls (path)
  "Return the expanded search controls for PATH, or nil."
  (when (jetpacs-reader-state-get path :org-search-open nil)
    (let* ((mode (jetpacs-reader-org--search-mode path))
           (query (jetpacs-reader-state-get path :org-query ""))
           (hits (jetpacs-reader-state-get path :org-hits nil))
           (mode-label (pcase mode
                         ('plain "Plain") ('regexp "Regexp")
                         ('sparse "Sparse tree"))))
      (jetpacs-column
       (jetpacs-text-input
        (jetpacs-wire-id "org-find" path)
        :value query
        :hint (pcase mode
                ('plain "Find text")
                ('regexp "Find regular expression")
                ('sparse "Tags, properties, TODO query"))
        :single-line t :autofocus t
        :on-submit (jetpacs-action "jetpacs.reader.org.search"
                                   :args (list :path path)))
       (jetpacs-row
        (jetpacs-button
         mode-label
         (jetpacs-action "jetpacs.reader.org.search-mode"
                         :args (list :path path))
         :variant "tonal")
        (jetpacs-button
         "Clear"
         (jetpacs-action "jetpacs.reader.org.search-clear"
                         :args (list :path path))
         :variant "text")
        :spacing 8)
       (when hits
         (jetpacs-text
          (if (eq hits 'sparse)
              "Sparse-tree filter applied"
            (format "%d match%s" hits (if (= hits 1) "" "es")))
          :style "caption"))
       :spacing 8))))

(defun jetpacs-reader-org--render (path)
  "Render Org PATH through the shared Org rendering engine."
  (let ((buffer (jetpacs-reader-org--buffer path)))
    (jetpacs-reader-org--ensure-initial-visibility path buffer)
    (jetpacs-reader-org--apply-reader-mode path buffer)
    (let ((jetpacs-org-render-proportional-prose
           (jetpacs-reader-org--reader-mode-p path))
          (jetpacs-org-render-reader-typography t))
      (apply #'jetpacs-lazy-column
             (delq nil
                   (append
                    (list (jetpacs-reader-org--search-controls path))
                    (jetpacs-org-render buffer)))))))

(defun jetpacs-reader-org--encrypted-p (path)
  "Whether PATH visibly contains an Org Crypt entry."
  (with-current-buffer (jetpacs-reader-org--buffer path)
    (save-excursion
      (goto-char (point-min))
      (re-search-forward "-----BEGIN PGP MESSAGE-----" nil t))))

(defun jetpacs-reader-org--actions (path)
  "Reader-only Org actions for PATH."
  (when (jetpacs-reader-active-p path)
    (delq
     nil
     (list
      (jetpacs-icon-button
       "chrome_reader_mode"
       (jetpacs-action "jetpacs.reader.org.reader-mode"
                       :args (list :path path))
       :content-description
       (if (jetpacs-reader-org--reader-mode-p path)
           "Show Org markup" "Enable reader mode"))
      (jetpacs-icon-button
       "unfold_more"
       (jetpacs-action "jetpacs.reader.org.visibility"
                       :args (list :path path))
       :content-description
       (format "Visibility: %s" (jetpacs-reader-org--visibility path)))
      (jetpacs-icon-button
       "search"
       (jetpacs-action "jetpacs.reader.org.search-toggle"
                       :args (list :path path))
       :content-description "Search and sparse tree")
      (when (jetpacs-reader-org--encrypted-p path)
        (jetpacs-icon-button
         "lock_open"
         (jetpacs-action "jetpacs.reader.org.decrypt"
                         :args (list :path path))
         :content-description "Decrypt Org Crypt entries"))))))

(defun jetpacs-reader-org--transition (path presentation)
  "Prepare PATH for PRESENTATION without changing Org's restriction.
A narrowed subtree cannot use SPEC 19's whole-document coordinates, so
its editor is deliberately plain and section-scoped."
  (when (eq presentation 'editor)
    (let ((buffer (jetpacs-reader-org--buffer path)))
      (when (with-current-buffer buffer (buffer-narrowed-p))
        (unless (jetpacs-files-downgrade-current-editor path)
          (error "The current Files edit session changed"))))))

(defun jetpacs-reader-org--action-path (args params)
  "Validated Org path from ARGS and PARAMS, or a status symbol."
  (let ((path (plist-get args :path)))
    (cond
     ((not (and (jetpacs-reader-org-path-p path)
                (jetpacs-reader-adapter-for path)))
      'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-reader-current-path-p path)) 'stale)
     (t path))))

(defun jetpacs-reader-org--reader-mode-action (args params)
  "Toggle Orgro-style reader typography."
  (let ((path (jetpacs-reader-org--action-path args params)))
    (if (symbolp path) path
      (jetpacs-reader-state-set
       path :org-reader-mode
       (not (jetpacs-reader-org--reader-mode-p path)))
      (jetpacs-reader-org--apply-reader-mode
       path (jetpacs-reader-org--buffer path))
      (jetpacs-reader-refresh params)
      'accepted)))

(defun jetpacs-reader-org--visibility-action (args params)
  "Cycle overview, contents, and show-all visibility."
  (let ((path (jetpacs-reader-org--action-path args params)))
    (if (symbolp path) path
      (jetpacs-reader-state-set
       path :org-visibility
       (pcase (jetpacs-reader-org--visibility path)
         ('overview 'contents) ('contents 'all) (_ 'overview)))
      (jetpacs-reader-org--clear-search-in-buffer
       path (jetpacs-reader-org--buffer path))
      (jetpacs-reader-refresh params)
      'accepted)))

(defun jetpacs-reader-org--search-toggle-action (args params)
  "Show or hide PATH's search controls."
  (let ((path (jetpacs-reader-org--action-path args params)))
    (if (symbolp path) path
      (jetpacs-reader-state-set
       path :org-search-open
       (not (jetpacs-reader-state-get path :org-search-open nil)))
      (jetpacs-reader-refresh params)
      'accepted)))

(defun jetpacs-reader-org--search-mode-action (args params)
  "Cycle plain, regexp, and sparse-tree search modes."
  (let ((path (jetpacs-reader-org--action-path args params)))
    (if (symbolp path) path
      (jetpacs-reader-state-set
       path :org-search-mode
       (pcase (jetpacs-reader-org--search-mode path)
         ('plain 'regexp) ('regexp 'sparse) (_ 'plain)))
      (jetpacs-reader-org--clear-search-in-buffer
       path (jetpacs-reader-org--buffer path))
      (jetpacs-reader-refresh params)
      'accepted)))

(defun jetpacs-reader-org--search-action (args params)
  "Apply a submitted text, regexp, or sparse-tree query."
  (let ((path (jetpacs-reader-org--action-path args params))
        (query (plist-get args :value)))
    (cond
     ((symbolp path) path)
     ((not (stringp query)) 'rejected)
     (t
      (condition-case err
          (let ((hits (jetpacs-reader-org--apply-search path query)))
            (jetpacs-reader-state-set path :org-query query)
            (jetpacs-reader-state-set path :org-hits hits)
            (jetpacs-reader-refresh params)
            'accepted)
        (user-error
         (jetpacs-shell-notify (error-message-string err)
                               (plist-get params :surface))
         'rejected))))))

(defun jetpacs-reader-org--search-clear-action (args params)
  "Clear PATH's active search/filter and highlights."
  (let ((path (jetpacs-reader-org--action-path args params)))
    (if (symbolp path) path
      (jetpacs-reader-org--clear-search-in-buffer
       path (jetpacs-reader-org--buffer path))
      (jetpacs-reader-refresh params)
      'accepted)))

(defun jetpacs-reader-org--decrypt-action (args params)
  "Decrypt PATH's Org Crypt entries through the prompt bridge."
  (let ((path (jetpacs-reader-org--action-path args params)))
    (if (symbolp path) path
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (with-current-buffer (jetpacs-reader-org--buffer path)
               (org-decrypt-entries)
               (ebp-org-cache-invalidate)
               (jetpacs-reader-refresh params))
           (error
            (jetpacs-shell-notify
             (format "Decrypt failed: %s" (error-message-string err))
             (plist-get params :surface))))))
      'accepted)))

(defun jetpacs-reader-org-register ()
  "Register the Org reader adapter and its actions, idempotently."
  (unless jetpacs-reader-org--registered
    (setq jetpacs-reader-org--registered t)
    (jetpacs-reader-register
     'org :predicate #'jetpacs-reader-org-path-p
     :render #'jetpacs-reader-org--render
     :actions #'jetpacs-reader-org--actions
     :transition #'jetpacs-reader-org--transition)
    (jetpacs-defaction "jetpacs.reader.org.reader-mode"
                       #'jetpacs-reader-org--reader-mode-action)
    (jetpacs-defaction "jetpacs.reader.org.visibility"
                       #'jetpacs-reader-org--visibility-action)
    (jetpacs-defaction "jetpacs.reader.org.search-toggle"
                       #'jetpacs-reader-org--search-toggle-action)
    (jetpacs-defaction "jetpacs.reader.org.search-mode"
                       #'jetpacs-reader-org--search-mode-action)
    (jetpacs-defaction "jetpacs.reader.org.search"
                       #'jetpacs-reader-org--search-action)
    (jetpacs-defaction "jetpacs.reader.org.search-clear"
                       #'jetpacs-reader-org--search-clear-action)
    (jetpacs-defaction "jetpacs.reader.org.decrypt"
                       #'jetpacs-reader-org--decrypt-action))
  t)

(defun jetpacs-reader-org-unregister ()
  "Unregister the Org reader adapter and its actions."
  (when jetpacs-reader-org--registered
    (setq jetpacs-reader-org--registered nil)
    (jetpacs-reader-unregister 'org)
    (dolist (action '("jetpacs.reader.org.reader-mode"
                      "jetpacs.reader.org.visibility"
                      "jetpacs.reader.org.search-toggle"
                      "jetpacs.reader.org.search-mode"
                      "jetpacs.reader.org.search"
                      "jetpacs.reader.org.search-clear"
                      "jetpacs.reader.org.decrypt"))
      (jetpacs-undefaction action)))
  t)

(defun jetpacs-reader-org-unload-function ()
  "Unload hygiene for the Org reader adapter."
  (jetpacs-reader-org-unregister)
  nil)

(provide 'jetpacs-reader-org)
;;; jetpacs-reader-org.el ends here
