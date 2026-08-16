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
;; becomes one owned root surface; Find file and Switch project are
;; PUSHED chrome screens — back is the companion-local `view.switch'.)

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'xref)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-navigate)
(require 'jetpacs-files)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)

(defconst jetpacs-project-surface "jetpacs.project"
  "The project dashboard's root surface (owner and surface name).")

(defcustom jetpacs-project-find-max 200
  "Maximum project files listed at once in the Find file screen.
Large trees are capped with a trailing note; the filter narrows instead
of paging."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-project--current nil
  "The selected project root (a directory string), or nil for none.")

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
  "A hub-grade row: leading ICON, TITLE/CAPTION, a chevron; ACTION on tap."
  (jetpacs-chrome-row title :subtitle caption :icon icon
                      :trailing (jetpacs-icon "chevron_right")
                      :on-tap action
                      :key (jetpacs-wire-id "pj" title)))

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
  (jetpacs-chrome-row (file-relative-name file root)
                      :icon "description"
                      :on-tap (jetpacs-action "project.open-file"
                                              :args `(:file ,file)
                                              :when-offline "drop")
                      :key (jetpacs-wire-id "pf" file)))

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
    (jetpacs-chrome-row
     (file-name-nondirectory (directory-file-name root))
     :subtitle (abbreviate-file-name (directory-file-name root))
     :icon "folder"
     :trailing (if activep
                   (jetpacs-icon "check_circle" :color "primary")
                 (jetpacs-icon "chevron_right"))
     :on-tap (unless activep
               (jetpacs-action "project.switch"
                               :args `(:root ,root)
                               :when-offline "drop"))
     :key (jetpacs-wire-id "pr" root))))

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
  "The dashboard root.  Find file and Switch project are PUSHED
screens now (the conformance sweep): their back arrows are the
stack's companion-local `view.switch', where the hand-rolled
`project.show' back verb died with the socket down."
  (jetpacs-chrome-screen
   "Project"
   (apply #'jetpacs-lazy-column (jetpacs-project--dashboard-nodes))))

(defun jetpacs-project--find-screen (back)
  "Builder for the pushed Find file screen; reads the filter state."
  (jetpacs-chrome-screen
   "Find file"
   (apply #'jetpacs-lazy-column (jetpacs-project--find-nodes))
   :back back))

(defun jetpacs-project--switch-screen (back)
  "Builder for the pushed Switch project screen."
  (jetpacs-chrome-screen
   "Switch project"
   (apply #'jetpacs-lazy-column (jetpacs-project--switch-nodes))
   :back back))

(defun jetpacs-project--push (id builder)
  "Push a sub-screen, deferred and caught (the push-screen rule)."
  (jetpacs-flow-continue
   (lambda ()
     (condition-case err
         (jetpacs-chrome-push-screen jetpacs-project-surface id builder)
       (error (message "jetpacs-project: %s push failed: %s"
                       id (jetpacs-error-label err)))))))

;;;; Actions

(defun jetpacs-project--action-show (_args _params)
  "Land on the dashboard from anywhere (settings link, M-x parity).
A stack RESET, deferred: the reset's push rebuilds the dashboard
\(project-current under the selected root — real work, possibly
remote), and a handler never pushes inside the dispatch extent (D2)."
  (jetpacs-project--widen-roots (jetpacs-project--root))
  (jetpacs-flow-continue
   (lambda () (jetpacs-chrome-reset-screens jetpacs-project-surface)))
  'accepted)

(defun jetpacs-project--action-find-file (args _params)
  "Open (or refilter) the Find file screen; a filter submit carries :value.
A re-submit pushes the SAME id — the stack's truncate-and-replace
gives refilter-in-place for free."
  (jetpacs-project--widen-roots (jetpacs-project--root))
  (let ((value (plist-get args :value)))
    (setq jetpacs-project--find-filter (if (stringp value) value "")))
  (jetpacs-project--push "find" #'jetpacs-project--find-screen)
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
        (ebp-path-refused 'rejected)))))

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
  (jetpacs-project--push "switch" #'jetpacs-project--switch-screen)
  'accepted)

(defun jetpacs-project--action-switch (args _params)
  "Adopt ROOT and land back on its dashboard — a stack reset, since
the pick came from the pushed Switch screen and the drill is over."
  (let ((root (plist-get args :root)))
    (if (not (and (stringp root) (file-directory-p root)))
        'rejected
      (setq jetpacs-project--current (file-name-as-directory root)
            jetpacs-project--find-filter "")
      (jetpacs-project--widen-roots jetpacs-project--current)
      ;; Deferred like project.show: the reset's push is real builder
      ;; work and never runs inside the dispatch extent (D2).
      (jetpacs-flow-continue
       (lambda () (jetpacs-chrome-reset-screens jetpacs-project-surface)))
      'accepted)))

(with-jetpacs-owner "jetpacs.project"
  (jetpacs-chrome-define-root jetpacs-project-surface "home"
                              (lambda (_back) (jetpacs-project--view))))
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

(defvar jetpacs-launcher-row-icons)
(with-eval-after-load 'jetpacs-launcher
  (setf (alist-get (concat "app:" jetpacs-project-surface)
                   jetpacs-launcher-row-icons nil nil #'equal)
        "dashboard"))

(provide 'jetpacs-project)
;;; jetpacs-project.el ends here