;;; jetpacs-project.el --- Project dashboard (core stock satellite) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; A home base for the current project: almost pure glue over substrates
;; the foundation already ships.  `project.el' is usable on the phone
;; today only through the command palette; this gives it a first-class
;; screen.  Each entry runs a built-in project command and lands the
;; result on its mode's substrate through `jetpacs-navigate-buffer'
;; (xref results, compilation, comint, tablist).
;;
;; Prompting commands (the grep regexp, the compile command) run inside
;; a flow continuation — the same seam jetpacs-files uses — where the
;; dialog bridge is allowed to turn their prompts into phone dialogs;
;; a handler itself never prompts (decision D2).
;;
;; (Behavior reference: POC 1's jetpacs-project.el.  Changed: the VC
;; entry is built-in `project-vc-dir' only — magit is not shipped with
;; Emacs, so it is not named here; magit users reach theirs through the
;; palette, landing on the same substrates.  POC 1's multi-view shell
;; becomes one owned root surface with a screen-state variable, like
;; the Customize browser.)

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'xref)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-navigate)
(require 'jetpacs-files)
(require 'jetpacs-shell)

(defconst jetpacs-project-surface "jetpacs.project"
  "The project dashboard's root surface (owner and surface name).")

(defcustom jetpacs-project-find-max 200
  "Maximum project files listed at once in the Find file screen.
Large trees are capped with a trailing note; the filter narrows instead
of paging."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-project--current nil
  "The selected project root (a directory string), or nil for none.")

(defvar jetpacs-project--screen 'dashboard
  "Which screen the surface shows: `dashboard', `find', or `switch'.")

(defvar jetpacs-project--find-filter ""
  "Current substring filter for the Find file screen.")

(defun jetpacs-project--root ()
  "The selected project root, defaulting to the ambient project's root."
  (or jetpacs-project--current
      (when-let* ((proj (ignore-errors (project-current))))
        (setq jetpacs-project--current (project-root proj)))))

(defun jetpacs-project--name (root)
  "A friendly display name for the project rooted at ROOT."
  (or (let ((default-directory root))
        (when-let* ((proj (ignore-errors (project-current))))
          (ignore-errors (project-name proj))))
      (file-name-nondirectory (directory-file-name root))))

(defun jetpacs-project--same-root-p (a b)
  (and a b (string= (directory-file-name (expand-file-name a))
                    (directory-file-name (expand-file-name b)))))

(defun jetpacs-project--widen-roots (root)
  "Admit ROOT into `jetpacs-files-roots' so Find file can open its files.
Keeps a single \"Project\" entry, replaced on each switch, so the guard
stays as tight as the current project."
  (when (stringp root)
    (setq jetpacs-files-roots
          (cons (cons "Project" (file-name-as-directory root))
                (assoc-delete-all "Project" jetpacs-files-roots)))))

;;;; Running project commands

(defun jetpacs-project--refresh ()
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-project-surface)))))

(defun jetpacs-project--view-buffer-of (fn)
  "Run FN at the project root in a continuation; navigate to its buffer.
FN returns a buffer or buffer name.  It may prompt (the dialog bridge
is active in the continuation) and may signal — a signal or a quit
costs the navigation, never the session.  `last-input-event' is cleared
around the interactive drives so no stale event hijacks a prompt."
  (let ((root (jetpacs-project--root)))
    (if (null root)
        (jetpacs-shell-notify "No project selected")
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (let* ((default-directory root)
                    (last-input-event nil)
                    (target (funcall fn)))
               (when target (jetpacs-navigate-buffer target)))
           (quit nil)
           (error (jetpacs-shell-notify
                   (format "Project command failed: %s"
                           (error-message-string err))))))))))

;;;; Cards and screens

(defun jetpacs-project--entry (icon title caption action)
  "A hub row: leading ICON, TITLE/CAPTION, a chevron; tap runs ACTION."
  (jetpacs-card
   (jetpacs-row
    (jetpacs-icon icon)
    (jetpacs-with-attrs
     (jetpacs-column (jetpacs-text title :style "label")
                     (jetpacs-text caption :style "caption"))
     :weight 1)
    (jetpacs-icon "chevron_right"))
   :on-tap action))

(defun jetpacs-project--header (root)
  (if root
      (jetpacs-card
       (jetpacs-column
        (jetpacs-text (jetpacs-project--name root) :style "title")
        (jetpacs-text (abbreviate-file-name (directory-file-name root))
                      :style "caption")))
    (jetpacs-empty-state
     :icon "folder_off" :title "No project here"
     :caption
     "Open a file inside a project, or switch to a known one below.")))

(defun jetpacs-project--dashboard-nodes ()
  (let ((root (jetpacs-project--root)))
    (list
     (jetpacs-project--header root)
     (jetpacs-project--entry "search" "Find file"
                             "Open a file from this project"
                             (jetpacs-action "project.find-file"
                                             :when-offline "drop"))
     (jetpacs-project--entry "travel_explore" "Grep"
                             "Search the project for a regexp"
                             (jetpacs-action "project.grep"
                                             :when-offline "drop"))
     (jetpacs-project--entry "build" "Compile"
                             "Run a compile command at the root"
                             (jetpacs-action "project.compile"
                                             :when-offline "drop"))
     (jetpacs-project--entry "terminal" "Shell"
                             "A shell rooted in the project"
                             (jetpacs-action "project.shell"
                                             :when-offline "drop"))
     (jetpacs-project--entry "view_list" "Buffers"
                             "Buffers belonging to this project"
                             (jetpacs-action "project.buffers"
                                             :when-offline "drop"))
     (jetpacs-project--entry "account_tree" "Version control"
                             "The built-in VC directory"
                             (jetpacs-action "project.vc"
                                             :when-offline "drop"))
     (jetpacs-project--entry "swap_horiz" "Switch project"
                             "Pick another known project"
                             (jetpacs-action "project.switch-screen"
                                             :when-offline "drop"))
     (jetpacs-project--entry "storage" "Databases"
                             "SQL connections and schema"
                             (jetpacs-action "sql.show"
                                             :when-offline "drop")))))

(defun jetpacs-project--file-card (root file)
  (let ((rel (file-relative-name file root)))
    (jetpacs-card
     (jetpacs-row
      (jetpacs-icon "description")
      (jetpacs-with-attrs (jetpacs-text rel :style "body" :max-lines 2)
                          :weight 1))
     :on-tap (jetpacs-action "project.open-file"
                             :args `(:file ,file) :when-offline "drop"))))

(defun jetpacs-project--find-nodes ()
  (let ((root (jetpacs-project--root)))
    (if (null root)
        (list (jetpacs-empty-state :icon "folder_off"
                                   :title "No project selected"
                                   :caption "Switch to a project first."))
      (let* ((default-directory root)
             (proj (ignore-errors (project-current nil root)))
             (files (and proj (ignore-errors (project-files proj))))
             (filter (downcase (string-trim jetpacs-project--find-filter)))
             (matches (if (string-empty-p filter)
                          files
                        (cl-remove-if-not
                         (lambda (f)
                           (string-search
                            filter (downcase (file-relative-name f root))))
                         files)))
             (total (length matches))
             (shown (cl-subseq matches
                               0 (min total jetpacs-project-find-max))))
        (append
         (list (jetpacs-text-input
                "project/find" :value jetpacs-project--find-filter
                :label "Filter files" :single-line t
                :hint "type a path fragment"
                :on-submit (jetpacs-action "project.find-file"))
               (jetpacs-text
                (format "%d file%s%s" total (if (= total 1) "" "s")
                        (if (> total jetpacs-project-find-max)
                            (format ", showing %d" jetpacs-project-find-max)
                          ""))
                :style "caption"))
         (if (null shown)
             (list (jetpacs-empty-state :icon "search"
                                        :title "No matching files"))
           (mapcar (lambda (f) (jetpacs-project--file-card root f))
                   shown)))))))

(defun jetpacs-project--known-roots ()
  (condition-case nil (project-known-project-roots) (error nil)))

(defun jetpacs-project--switch-card (root current)
  (let ((activep (jetpacs-project--same-root-p root current)))
    (jetpacs-card
     (jetpacs-row
      (jetpacs-icon "folder")
      (jetpacs-with-attrs
       (jetpacs-column
        (jetpacs-text (file-name-nondirectory (directory-file-name root))
                      :style "label")
        (jetpacs-text (abbreviate-file-name (directory-file-name root))
                      :style "caption"))
       :weight 1)
      (if activep
          (jetpacs-icon "check_circle" :color "primary")
        (jetpacs-icon "chevron_right")))
     :on-tap (unless activep
               (jetpacs-action "project.switch"
                               :args `(:root ,root)
                               :when-offline "drop")))))

(defun jetpacs-project--switch-nodes ()
  (let ((roots (jetpacs-project--known-roots))
        (current (jetpacs-project--root)))
    (if (null roots)
        (list (jetpacs-empty-state
               :icon "folder_open" :title "No known projects"
               :caption "Projects you visit are remembered here."))
      (mapcar (lambda (root) (jetpacs-project--switch-card root current))
              roots))))

(defun jetpacs-project--view ()
  ;; A scaffold so chrome docks the view switcher.
  (jetpacs-scaffold
   :body
   (apply #'jetpacs-lazy-column
          (cons
          (jetpacs-row
           (unless (eq jetpacs-project--screen 'dashboard)
             (jetpacs-icon-button "arrow_back"
                                  (jetpacs-action "project.show"
                                                  :when-offline "drop")
                                  :content-description "Back to the dashboard"))
           (jetpacs-text (pcase jetpacs-project--screen
                           ('find "Find file")
                           ('switch "Switch project")
                           (_ "Project"))
                         :style "title"))
           (pcase jetpacs-project--screen
             ('find (jetpacs-project--find-nodes))
             ('switch (jetpacs-project--switch-nodes))
             (_ (jetpacs-project--dashboard-nodes)))))))

;;;; Actions

(defun jetpacs-project--action-show (_args _params)
  (jetpacs-project--widen-roots (jetpacs-project--root))
  (setq jetpacs-project--screen 'dashboard)
  (jetpacs-project--refresh)
  'accepted)

(defun jetpacs-project--action-find-file (args _params)
  "Open (or refilter) the Find file screen; a filter submit carries :value."
  (jetpacs-project--widen-roots (jetpacs-project--root))
  (let ((value (plist-get args :value)))
    (setq jetpacs-project--find-filter (if (stringp value) value "")))
  (setq jetpacs-project--screen 'find)
  (jetpacs-project--refresh)
  'accepted)

(defun jetpacs-project--action-open-file (args _params)
  "Widen the sandbox, then delegate to the files editor.
The editor re-checks the root guard; eligibility, the read, and any
changed-on-disk prompt live in the continuation (the files module's own
open follows the same shape)."
  (let ((file (plist-get args :file))
        (root (jetpacs-project--root)))
    (if (not (and (stringp file) root))
        'rejected
      (jetpacs-project--widen-roots root)
      (condition-case nil
          (let ((true (jetpacs-files--check file)))
            (jetpacs-flow-continue
             (lambda () (jetpacs-files--edit-open true nil)))
            'accepted)
        (jetpacs-path-refused 'rejected)))))

(defun jetpacs-project--action-grep (_args _params)
  (jetpacs-project--view-buffer-of
   (lambda ()
     (let ((regexp (string-trim (read-string "Grep project for (regexp): "))))
       (unless (string-empty-p regexp)
         (project-find-regexp regexp)
         xref-buffer-name))))
  'accepted)

(defun jetpacs-project--action-compile (_args _params)
  (jetpacs-project--view-buffer-of
   (lambda ()
     ;; `project-compile' is interactive-only (it reads the compile
     ;; command when prefixed); drive it interactively so the prompt
     ;; bridges.
     (call-interactively #'project-compile)
     "*compilation*"))
  'accepted)

(defun jetpacs-project--action-shell (_args _params)
  (jetpacs-project--view-buffer-of #'project-shell)
  'accepted)

(defun jetpacs-project--action-buffers (_args _params)
  (jetpacs-project--view-buffer-of
   (lambda () (project-list-buffers) "*Buffer List*"))
  'accepted)

(defun jetpacs-project--action-vc (_args _params)
  (jetpacs-project--view-buffer-of
   (lambda () (project-vc-dir) "*vc-dir*"))
  'accepted)

(defun jetpacs-project--action-switch-screen (_args _params)
  (setq jetpacs-project--screen 'switch)
  (jetpacs-project--refresh)
  'accepted)

(defun jetpacs-project--action-switch (args _params)
  (let ((root (plist-get args :root)))
    (if (not (and (stringp root) (file-directory-p root)))
        'rejected
      (setq jetpacs-project--current (file-name-as-directory root)
            jetpacs-project--find-filter ""
            jetpacs-project--screen 'dashboard)
      (jetpacs-project--widen-roots jetpacs-project--current)
      (jetpacs-project--refresh)
      'accepted)))

(with-jetpacs-owner "jetpacs.project"
  (jetpacs-shell-define-root jetpacs-project-surface
                             #'jetpacs-project--view))
(jetpacs-defaction "project.show" #'jetpacs-project--action-show)
(jetpacs-defaction "project.find-file" #'jetpacs-project--action-find-file)
(jetpacs-defaction "project.open-file" #'jetpacs-project--action-open-file)
(jetpacs-defaction "project.grep" #'jetpacs-project--action-grep)
(jetpacs-defaction "project.compile" #'jetpacs-project--action-compile)
(jetpacs-defaction "project.shell" #'jetpacs-project--action-shell)
(jetpacs-defaction "project.buffers" #'jetpacs-project--action-buffers)
(jetpacs-defaction "project.vc" #'jetpacs-project--action-vc)
(jetpacs-defaction "project.switch-screen"
                   #'jetpacs-project--action-switch-screen)
(jetpacs-defaction "project.switch" #'jetpacs-project--action-switch)

;; Entry: a card on the settings screen (order 30, after Customize).
(with-eval-after-load 'jetpacs-settings
  (jetpacs-settings-add-link
   30 (lambda ()
        (jetpacs-project--entry "dashboard" "Project"
                                "The current project's home base"
                                (jetpacs-action "project.show"
                                                :when-offline "drop")))))
(declare-function jetpacs-settings-add-link "jetpacs-settings" (order builder))

(provide 'jetpacs-project)
;;; jetpacs-project.el ends here