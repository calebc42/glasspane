;;; glasspane-fab.el --- The floating action button: state-aware, per screen -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Glasspane's FAB is the Material extended FAB (`material3.fab') with a
;; small toggle stacked above it that fans out the screen's Org actions.
;;
;; The labelled primary is state-aware: "Capture" normally, "Clock in" on a
;; heading page, and "Clock out · TASK" on every screen while a clock runs,
;; so the most time-sensitive action is always one tap away.  It folds to
;; its icon while the body is scrolled.
;;
;; The menu is the screen's:
;;
;; - lists (Agenda, Projects, an Area page): a quick new task filed for the
;;   shown day, the Projects Area filter or the Area; a task under the
;;   clocked heading; and each Org capture template, skipping the picker;
;; - a heading page: add child or sibling, move, promote and demote; a
;;   countdown from the heading's Effort, set Effort, cancel the clock;
;;   clone with time shift, run the subtree's code, toggle ARCHIVE, sort
;;   the children and update their [/] cookies;
;; - a file's outline (hosted by Files): a new heading or TODO, run all
;;   code blocks, tangle, update dynamic blocks, and the clocked totals.
;;
;; A countdown is a device reminder at its end, carried by a reminder
;; projection, so the phone notifies even when Emacs is idle.  Without a
;; Companion that draws `material3.fab', the menu degrades to the FAB menu
;; and then to the plain capture button.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-clock)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-material3)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-dialog-slot)
(require 'jetpacs-dates)
(require 'jetpacs-reminders)
(require 'jetpacs-org-structure)
(require 'jetpacs-org-capture)
(require 'jetpacs-reader)
(require 'jetpacs-files)
(require 'org-duration)
(require 'glasspane-org)
(require 'glasspane-ui)

(defgroup glasspane-fab nil
  "Glasspane's floating action button."
  :group 'jetpacs)

(defcustom glasspane-fab-inbox nil
  "The file quick tasks are filed into, relative to `org-directory'.
Nil means `org-default-notes-file' when it lies inside `org-directory',
else \"inbox.org\" there."
  :type '(choice (const :tag "Default notes file" nil) file)
  :group 'glasspane-fab)

(defcustom glasspane-fab-template-items 4
  "How many Org capture templates the list FAB offers as their own items."
  :type 'natnum :group 'glasspane-fab)

(defconst glasspane-fab--owner "glasspane"
  "The owner whose verbs, dialog slot and reminders the FAB uses.")

;;;; Building the FAB

(defun glasspane-fab-item (label icon action)
  "One FAB menu item: LABEL beside ICON, running ACTION."
  (jetpacs-material3-fab-menu-item label icon action))

(defun glasspane-fab--truncate (text n)
  "TEXT cut to N characters with an ellipsis."
  (if (> (length text) n) (concat (substring text 0 (1- n)) "…") text))

(defun glasspane-fab--clocking-p ()
  "Whether Org has a running clock."
  (and (fboundp 'org-clocking-p) (org-clocking-p)))

(defun glasspane-fab--clock-out-primary ()
  "The primary while a clock runs: (ICON LABEL ACTION COLOR)."
  (list "timer_off"
        (concat "Clock out · "
                (glasspane-fab--truncate (or (org-no-properties
                                              (or org-clock-current-task ""))
                                             "")
                                         22))
        (jetpacs-action "org.clock.out")
        "tertiary"))

(defun glasspane-fab-node (primary items)
  "The FAB for PRIMARY, (ICON LABEL ACTION [COLOR]), with menu ITEMS.
On a Companion without `material3.fab' the primary leads a FAB menu, or,
older still, stands alone as an icon button."
  (pcase-let ((`(,icon ,label ,action ,color) primary))
    (cond
     ((jetpacs-node-advertised-p "material3.fab")
      (jetpacs-material3-fab icon action
                             :label label :collapse-on-scroll t :color color
                             :menu items :menu-icon "more_vert"))
     ((and items (jetpacs-node-advertised-p "material3.fab_menu"))
      (jetpacs-material3-fab-menu
       (cons (glasspane-fab-item label icon action) items)))
     (t (jetpacs-icon-button icon action :content-description label
                             :variant "filled" :size "large")))))

(defun glasspane-fab--capture-primary ()
  "The ordinary primary: Capture."
  (list "note_add" "Capture" (jetpacs-action "org.capture.show")))

(defun glasspane-fab--template-items ()
  "Each Org capture template as its own item, opening its form directly."
  (cl-loop for template in (ignore-errors (jetpacs-org-capture-templates))
           repeat glasspane-fab-template-items
           collect (glasspane-fab-item
                    (or (plist-get template :description)
                        (plist-get template :key))
                    "edit_note"
                    (jetpacs-action "org.capture.show"
                                    :args (list :template
                                                (plist-get template :key))))))

;;;; Screen FABs

(cl-defun glasspane-fab-list (&key date area label)
  "The FAB for a list screen.
DATE, an ISO day, files the quick task as scheduled that day (Agenda);
AREA tags it (Projects filter, an Area page).  LABEL names the quick task
item, defaulting to \"New task\"."
  (glasspane-fab-node
   (if (glasspane-fab--clocking-p)
       (glasspane-fab--clock-out-primary)
     (glasspane-fab--capture-primary))
   (append
    (list (glasspane-fab-item
           (or label "New task") "add_task"
           (jetpacs-action "glasspane.fab.quick-task"
                           :args (append (and date (list :date date))
                                         (and area (list :area area))))))
    (when (glasspane-fab--clocking-p)
      (list (glasspane-fab-item "Under clocked task" "subdirectory_arrow_right"
                                (jetpacs-action "glasspane.fab.under-clock"))))
    (when (glasspane-fab--clocking-p)
      (list (glasspane-fab-item "Capture" "note_add"
                                (jetpacs-action "org.capture.show"))))
    (glasspane-fab--template-items))))

(defun glasspane-fab-app (&optional _surface)
  "The app-default FAB on Glasspane's other screens: capture and templates."
  (glasspane-fab-list))

(defun glasspane-fab--heading-groups (token)
  "The heading actions grouped for the sheets: alist of GROUP -> items.
Each item is (LABEL ICON ACTION)."
  (let* ((args (list :token token))
         (act (lambda (verb &rest more)
                (jetpacs-action verb :args (append args more)))))
    `(("structure"
       ("Add sub-heading" "subdirectory_arrow_right"
        ,(funcall act "glasspane.fab.add" :relation "child"))
       ("Add sibling task" "add_task"
        ,(funcall act "glasspane.fab.add" :relation "after" :todo t))
       ("Move up" "arrow_upward" ,(funcall act "glasspane.fab.move" :how "up"))
       ("Move down" "arrow_downward" ,(funcall act "glasspane.fab.move" :how "down"))
       ("Promote" "format_indent_decrease" ,(funcall act "glasspane.fab.move" :how "promote"))
       ("Demote" "format_indent_increase" ,(funcall act "glasspane.fab.move" :how "demote")))
      ("more"
       ("Clone with time shift…" "event_repeat" ,(funcall act "glasspane.fab.clone"))
       ("Run code blocks" "play_arrow"
        ,(jetpacs-action "glasspane.fab.babel-subtree" :args args
                         :confirm "Run every code block in this subtree?"))
       ("Sort children…" "sort" ,(funcall act "glasspane.fab.sort"))
       ("Update [/] cookies" "checklist" ,(funcall act "glasspane.fab.cookies"))
       ("Toggle ARCHIVE tag" "inventory_2" ,(funcall act "glasspane.fab.archive-tag"))))))

(defun glasspane-fab-heading (token &optional info)
  "The FAB for a heading page whose heading TOKEN names; INFO is its meta.
A running clock makes the primary Clock out; otherwise Clock in.  The menu
keeps the frequent actions; Structure… and More… open grouped sheets, so
the fan stays within Material's handful of items."
  (when (stringp token)
    (let* ((args (list :token token))
           (act (lambda (verb &rest more)
                  (jetpacs-action verb :args (append args more))))
           (clocking (glasspane-fab--clocking-p))
           (effort (plist-get info :effort)))
      (glasspane-fab-node
       (if clocking
           (glasspane-fab--clock-out-primary)
         (list "timer" "Clock in" (funcall act "heading.clock-in")))
       (delq nil
             (list
              (glasspane-fab-item "Add sub-task" "add_task"
                                  (funcall act "glasspane.fab.add" :relation "child" :todo t))
              (if (glasspane-fab-countdown-active-p)
                  (glasspane-fab-item "Stop countdown" "timer_off"
                                      (jetpacs-action "glasspane.fab.countdown-stop"))
                (glasspane-fab-item (if effort (format "Countdown %s" effort)
                                      "Countdown…")
                                    "hourglass_top"
                                    (funcall act "glasspane.fab.countdown")))
              (glasspane-fab-item "Set effort…" "schedule"
                                  (funcall act "glasspane.fab.effort"))
              (when clocking
                (glasspane-fab-item "Cancel clock" "cancel"
                                    (jetpacs-action "glasspane.fab.clock-cancel"
                                                    :confirm "Discard the running clock?")))
              (glasspane-fab-item "Structure…" "account_tree"
                                  (funcall act "glasspane.fab.group" :group "structure"))
              (glasspane-fab-item "More…" "more_horiz"
                                  (funcall act "glasspane.fab.group" :group "more"))))))))

(defun glasspane-fab--on-group (args params)
  "Show ARGS' `:group' of heading actions as a sheet."
  (let ((group (assoc (plist-get args :group)
                      (glasspane-fab--heading-groups (plist-get args :token)))))
    (cond
     ((null group) 'rejected)
     ((null (glasspane-fab--ref args)) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (with-jetpacs-owner glasspane-fab--owner
           (jetpacs-dialog-slot-show
            (concat "gp-fab-group-" (car group))
            (apply #'jetpacs-column
                   (append
                    (list (jetpacs-text (if (equal (car group) "structure")
                                            "Structure" "More")
                                        :style "title"))
                    (mapcar (lambda (item)
                              (jetpacs-with-attrs
                               (jetpacs-button (nth 0 item) (nth 2 item)
                                               :icon (nth 1 item) :variant "text")
                               :fill_fraction 1))
                            (cdr group))
                    (list :spacing 2)))
            :params params :style "sheet"))))
      'accepted))))

(defun glasspane-fab-outline (path)
  "The FAB for Org file PATH's outline in the Files document host."
  (let ((act (lambda (verb &rest more)
               (jetpacs-action verb :args (append (list :path path) more)))))
    (glasspane-fab-node
     (if (glasspane-fab--clocking-p)
         (glasspane-fab--clock-out-primary)
       (glasspane-fab--capture-primary))
     (list
      (glasspane-fab-item "New TODO" "add_task"
                          (funcall act "glasspane.fab.file-heading" :todo t))
      (glasspane-fab-item "New heading" "post_add"
                          (funcall act "glasspane.fab.file-heading"))
      (glasspane-fab-item "Run all code blocks" "play_arrow"
                          (jetpacs-action "glasspane.fab.file-babel"
                                          :args (list :path path)
                                          :confirm "Run every code block in this file?"))
      (glasspane-fab-item "Tangle" "account_tree"
                          (jetpacs-action "glasspane.fab.file-tangle"
                                          :args (list :path path)
                                          :confirm "Tangle this file's code blocks to their files?"))
      (glasspane-fab-item "Update clock tables" "table_chart"
                          (funcall act "glasspane.fab.file-dblocks"))
      (glasspane-fab-item "Time totals" "timelapse"
                          (funcall act "glasspane.fab.file-times"))))))

(defun glasspane-fab--outline-fab (path)
  "The Files document host's FAB for PATH when Glasspane's reader draws it."
  (when (and (stringp path) (ebp-org-path-p path)
             (jetpacs-reader-current-path-p path))
    (glasspane-fab-outline path)))

;;;; Dialogs

(defun glasspane-fab--surface (params)
  "PARAMS' surface, else Glasspane's."
  (or (plist-get params :surface) (jetpacs-shell-surface-for "glasspane")))

(defun glasspane-fab--prompt (id title body fields on-submit &optional ok)
  "Show dialog ID titled TITLE over BODY nodes; OK submits capturing FIELDS.
ON-SUBMIT receives the captured fields plist after the dialog closes."
  (with-jetpacs-owner glasspane-fab--owner
    (jetpacs-dialog-slot-show
     id
     (apply #'jetpacs-column
            (append
             (list (jetpacs-text title :style "title"))
             body
             (list (jetpacs-row
                    (jetpacs-spacer :weight 1)
                    (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
                    (jetpacs-button (or ok "OK")
                                    (jetpacs-dialog-submit :value "ok"
                                                           :capture-fields fields)
                                    :variant "filled")
                    :align "center" :spacing 8 :fill t)
                   :spacing 12)))
     :on-submit on-submit)))

(defun glasspane-fab--field (fields id)
  "The trimmed string field ID from FIELDS, or nil when empty."
  (let ((v (plist-get fields (intern (concat ":" id)))))
    (and (stringp v) (not (string-blank-p v)) (string-trim v))))

(defun glasspane-fab--title-input (id &optional hint)
  "A single-line title field ID with HINT."
  (jetpacs-text-input id :label "Title" :hint hint :single-line t :autofocus t))

(defun glasspane-fab--notify (text params)
  "Show TEXT as a snackbar on PARAMS' surface and refresh it.
A tap from a sheet carries no surface: Glasspane's own refreshes."
  (jetpacs-shell-notify text (glasspane-fab--surface params))
  (jetpacs-app-defer-refresh (list :surface (glasspane-fab--surface params))))

(defun glasspane-fab--close-sheet ()
  "Retire a grouped sheet whose button ran an immediate action."
  (when (jetpacs-dialog-slot-live-p glasspane-fab--owner)
    (jetpacs-dialog-slot-close glasspane-fab--owner)))

;;;; Heading verbs

(defun glasspane-fab--ref (args)
  "ARGS' heading ref in Glasspane's token scope, or nil."
  (let ((token (plist-get args :token)))
    (and (stringp token) (ebp-org-token-ref token :owner glasspane-fab--owner))))

(defun glasspane-fab--on-add (args params)
  "Ask a title, then add it at ARGS' `:relation' to the heading.
`:todo' makes it a TODO heading."
  (let* ((ref (glasspane-fab--ref args))
         (relation (pcase (plist-get args :relation)
                     ("child" 'child) ("after" 'after) ("before" 'before)))
         (todo (plist-get args :todo)))
    (cond
     ((null relation) 'rejected)
     ((null ref) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (glasspane-fab--prompt
          "gp-fab-add"
          (pcase relation ('child (if todo "New sub-task" "New sub-heading"))
                 (_ (if todo "New sibling task" "New sibling")))
          (list (jetpacs-text (or (plist-get ref :headline) "") :style "caption"
                              :color "outline")
                (glasspane-fab--title-input "gp-fab-title"))
          '("gp-fab-title")
          (lambda (fields)
            (when-let* ((title (glasspane-fab--field fields "gp-fab-title")))
              (condition-case err
                  (progn
                    (jetpacs-org-structure-insert
                     glasspane-fab--owner ref 'glasspane relation
                     (if todo (concat (or (car org-todo-keywords-1) "TODO") " " title)
                       title))
                    (glasspane-fab--notify (format "Added “%s”" title) params))
                (error (glasspane-fab--notify
                        (format "Couldn't add: %s" (error-message-string err))
                        params)))))
          "Add")))
      'accepted))))

(defun glasspane-fab--on-move (args params)
  "Move, promote or demote the heading per ARGS' `:how'."
  (let ((ref (glasspane-fab--ref args))
        (how (plist-get args :how)))
    (cond
     ((not (member how '("up" "down" "promote" "demote"))) 'rejected)
     ((null ref) 'stale)
     (t
      (glasspane-fab--close-sheet)
      (condition-case err
          (progn
            (pcase how
              ("up" (jetpacs-org-structure-move glasspane-fab--owner ref 'glasspane 'up))
              ("down" (jetpacs-org-structure-move glasspane-fab--owner ref 'glasspane 'down))
              ("promote" (jetpacs-org-structure-promote glasspane-fab--owner ref 'glasspane))
              ("demote" (jetpacs-org-structure-demote glasspane-fab--owner ref 'glasspane)))
            (jetpacs-app-defer-refresh (list :surface (glasspane-fab--surface params)))
            'accepted)
        (ebp-org-unresolved 'stale)
        (error (glasspane-fab--notify (error-message-string err) params)
               'rejected))))))

(defun glasspane-fab--at (args params fn &optional message)
  "Run FN at ARGS' heading, saving; notify MESSAGE and refresh on success."
  (glasspane-fab--close-sheet)
  (let ((status (glasspane-ui-at-ref args fn t)))
    (when (and (eq status 'accepted) message)
      (jetpacs-shell-notify message (glasspane-fab--surface params)))
    (when (eq status 'accepted)
      (jetpacs-app-defer-refresh (list :surface (glasspane-fab--surface params))))
    status))

(defun glasspane-fab--on-cookies (args params)
  "Update the [/] and [%] cookies of the heading's subtree."
  (glasspane-fab--at args params
                     (lambda () (org-update-statistics-cookies nil))
                     "Cookies updated"))

(defun glasspane-fab--on-archive-tag (args params)
  "Toggle the heading's ARCHIVE tag."
  (glasspane-fab--at args params
                     (lambda () (org-toggle-archive-tag))
                     "ARCHIVE tag toggled"))

(defconst glasspane-fab--sort-methods
  '(("a" "Alphabetically") ("p" "By priority") ("o" "By TODO state")
    ("s" "By scheduled date") ("d" "By deadline") ("t" "By time"))
  "`org-sort-entries' method letters and their labels.")

(defun glasspane-fab--on-sort (args params)
  "Ask how, then sort the heading's children."
  (let ((ref (glasspane-fab--ref args)))
    (cond
     ((null ref) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (glasspane-fab--prompt
          "gp-fab-sort" "Sort children"
          (list (jetpacs-enum-list
                 "gp-fab-sort-method"
                 (mapcar (lambda (m) (jetpacs-enum-option (cadr m) (car m)))
                         glasspane-fab--sort-methods)
                 :value "a")
                (jetpacs-switch "gp-fab-sort-reverse" :label "Reverse order"
                                :checked :json-false))
          '("gp-fab-sort-method" "gp-fab-sort-reverse")
          (lambda (fields)
            (let ((method (plist-get fields :gp-fab-sort-method))
                  (reverse (eq (plist-get fields :gp-fab-sort-reverse) t)))
              (when (assoc method glasspane-fab--sort-methods)
                (glasspane-fab--at
                 args params
                 (lambda ()
                   (org-sort-entries
                    nil (string-to-char (if reverse (upcase method) method))))
                 "Children sorted"))))
          "Sort")))
      'accepted))))

(defun glasspane-fab--on-effort (args params)
  "Ask for an Effort, offering the allowed values when Org declares them."
  (let ((ref (glasspane-fab--ref args)))
    (cond
     ((null ref) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (let* ((allowed nil) (current nil))
        (glasspane-ui-at-ref
         args (lambda ()
                (setq current (org-entry-get nil "Effort")
                      allowed (ignore-errors
                                (org-property-get-allowed-values nil "Effort" t)))))
        (jetpacs-flow-continue
         (lambda ()
           (glasspane-fab--prompt
            "gp-fab-effort" "Effort"
            (list (if allowed
                      (jetpacs-enum-list
                       "gp-fab-effort"
                       (mapcar (lambda (v) (jetpacs-enum-option v v)) allowed)
                       :value (or current (car allowed)))
                    (jetpacs-text-input "gp-fab-effort" :label "Effort"
                                        :hint "0:30, 1:00, 2d" :value current
                                        :single-line t))
                  (jetpacs-text "Empty removes it." :style "caption"
                                :color "outline"))
            '("gp-fab-effort")
            (lambda (fields)
              (let ((value (or (glasspane-fab--field fields "gp-fab-effort") "")))
                (glasspane-fab--at
                 args params
                 (lambda ()
                   (if (string-empty-p value)
                       (org-entry-delete nil "Effort")
                     (org-entry-put nil "Effort" value)))
                 (if (string-empty-p value) "Effort removed"
                   (format "Effort %s" value)))))
            "Set"))))
      'accepted))))

(defun glasspane-fab--on-clone (args params)
  "Ask how many clones and the shift, then clone the subtree."
  (let ((ref (glasspane-fab--ref args)))
    (cond
     ((null ref) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (glasspane-fab--prompt
          "gp-fab-clone" "Clone with time shift"
          (list (jetpacs-text-input "gp-fab-clone-n" :label "Clones" :value "1"
                                    :keyboard "number" :single-line t)
                (jetpacs-text-input "gp-fab-clone-shift" :label "Shift each by"
                                    :hint "+1d, +1w, +1m" :value "+1w"
                                    :single-line t))
          '("gp-fab-clone-n" "gp-fab-clone-shift")
          (lambda (fields)
            (let ((n (string-to-number (or (glasspane-fab--field fields "gp-fab-clone-n") "0")))
                  (shift (glasspane-fab--field fields "gp-fab-clone-shift")))
              (if (not (and (<= 1 n 50) shift
                            (string-match-p "\\`[-+]?[0-9]+[hdwmy]\\'" shift)))
                  (glasspane-fab--notify "Clones must be 1–50 and the shift like +1w"
                                         params)
                (glasspane-fab--at
                 args params
                 (lambda () (org-clone-subtree-with-time-shift n shift))
                 (format "%d clone%s added" n (if (= n 1) "" "s"))))))
          "Clone")))
      'accepted))))

(defun glasspane-fab--on-babel-subtree (args params)
  "Run every code block in the heading's subtree."
  (if (null (glasspane-fab--ref args))
      'stale
    (jetpacs-flow-continue
     (lambda ()
       (glasspane-fab--at args params
                          (lambda () (org-babel-execute-subtree))
                          "Code blocks ran")))
    'accepted))

(defun glasspane-fab--on-clock-cancel (_args params)
  "Discard the running clock."
  (if (not (glasspane-fab--clocking-p))
      'stale
    (let ((buffer (marker-buffer org-clock-marker)))
      (org-clock-cancel)
      ;; The cancel deletes the CLOCK line (and an emptied drawer) in the
      ;; clocked buffer; save it like every other heading mutation.
      (when (buffer-live-p buffer)
        (glasspane-org-save-and-invalidate buffer)))
    (glasspane-fab--notify "Clock cancelled" params)
    'accepted))

;;;; Countdown: a device reminder at its end

(defvar glasspane-fab--countdown nil
  "The running countdown, or nil: (:end TIME :title S).")

(defun glasspane-fab-countdown-active-p ()
  "Whether a countdown is running and not yet due."
  (and glasspane-fab--countdown
       (time-less-p nil (plist-get glasspane-fab--countdown :end))))

(defun glasspane-fab--reminders ()
  "The countdown's reminder set for the projection."
  (when (glasspane-fab-countdown-active-p)
    (list (list :id "glasspane-countdown"
                :at_ms (truncate (* 1000 (float-time
                                          (plist-get glasspane-fab--countdown :end))))
                :title "Countdown done"
                :body (plist-get glasspane-fab--countdown :title)))))

(defun glasspane-fab--minutes (effort)
  "EFFORT (an Org duration such as 0:30 or 2h) in whole minutes, or nil."
  (when (and (stringp effort) (not (string-blank-p effort)))
    (let ((m (ignore-errors (org-duration-to-minutes effort))))
      (and (numberp m) (> m 0) (round m)))))

(defun glasspane-fab--start-countdown (minutes title params)
  "Start a MINUTES countdown for TITLE and tell PARAMS' surface."
  (setq glasspane-fab--countdown
        (list :end (time-add nil (* 60 minutes)) :title title))
  (jetpacs-reminders-schedule-sync glasspane-fab--owner)
  (glasspane-fab--notify
   (format "Countdown %s for %s" (org-duration-from-minutes minutes)
           (glasspane-fab--truncate title 30))
   params))

(defun glasspane-fab--on-countdown (args params)
  "Count down the heading's Effort, or ask for minutes when it has none."
  (let ((ref (glasspane-fab--ref args)))
    (cond
     ((null ref) 'stale)
     (t
      (let (effort title)
        (glasspane-ui-at-ref args (lambda ()
                                    (setq effort (org-entry-get nil "Effort")
                                          title (org-get-heading t t t t))))
        (if-let* ((minutes (glasspane-fab--minutes effort)))
            (glasspane-fab--start-countdown minutes title params)
          (when (jetpacs-client)
            (jetpacs-flow-continue
             (lambda ()
               (glasspane-fab--prompt
                "gp-fab-countdown" "Countdown"
                (list (jetpacs-text (or title "") :style "caption" :color "outline")
                      (jetpacs-text-input "gp-fab-minutes" :label "Minutes" :value "25"
                                          :keyboard "number" :single-line t))
                '("gp-fab-minutes")
                (lambda (fields)
                  (let ((m (string-to-number
                            (or (glasspane-fab--field fields "gp-fab-minutes") "0"))))
                    (if (<= 1 m 1440)
                        (glasspane-fab--start-countdown m title params)
                      (glasspane-fab--notify "Minutes must be 1–1440" params))))
                "Start"))))))
      'accepted))))

(defun glasspane-fab--on-countdown-stop (_args params)
  "Stop the running countdown and clear its reminder."
  (setq glasspane-fab--countdown nil)
  (jetpacs-reminders-schedule-sync glasspane-fab--owner)
  (glasspane-fab--notify "Countdown stopped" params)
  'accepted)

;;;; List verbs: quick tasks

(defun glasspane-fab-inbox-file ()
  "The absolute file quick tasks are filed into."
  (let* ((dir (file-name-as-directory (expand-file-name (or org-directory "~/org"))))
         (default (and (stringp org-default-notes-file)
                       (expand-file-name org-default-notes-file dir)))
         (file (cond (glasspane-fab-inbox (expand-file-name glasspane-fab-inbox dir))
                     ((and default (string-prefix-p dir default)) default)
                     (t (expand-file-name "inbox.org" dir)))))
    file))

(defun glasspane-fab-append-heading (file text)
  "Append heading TEXT (complete, with stars) to FILE and save it."
  (with-current-buffer (find-file-noselect file)
    (unless (derived-mode-p 'org-mode) (org-mode))
    (org-with-wide-buffer
     (goto-char (point-max))
     (unless (bolp) (insert "\n"))
     (insert text)
     (unless (string-suffix-p "\n" text) (insert "\n")))
    (glasspane-org-save-and-invalidate (current-buffer))))

(defun glasspane-fab-task-text (title &optional date area)
  "A level-1 TODO heading for TITLE, scheduled DATE, tagged AREA."
  (concat "* " (or (car org-todo-keywords-1) "TODO") " " title
          (when (and (stringp area) (string-match-p "\\`[[:alnum:]_@#%]+\\'" area))
            (concat " :" area ":"))
          "\n"
          (when (jetpacs-dates-valid-p date)
            (format "SCHEDULED: <%s %s>\n" date (jetpacs-dates-weekday date t)))))

(defun glasspane-fab--date-options (date)
  "Date choices for the quick-task dialog, with DATE first when given."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (tomorrow (jetpacs-dates-shift today 1 'day))
         (opts (list (cons "none" "No date") (cons today "Today")
                     (cons tomorrow "Tomorrow"))))
    (if (and date (not (member date (list today tomorrow))))
        (cons (cons date (glasspane-ui-day-words date today)) opts)
      opts)))

(defun glasspane-fab--on-quick-task (args params)
  "Ask a title (and day), then file a TODO in the inbox.
ARGS' `:date' preselects the day; `:area' tags the task."
  (let ((date (plist-get args :date))
        (area (plist-get args :area)))
    (cond
     ((and date (not (jetpacs-dates-valid-p date))) 'rejected)
     ((and area (not (and (stringp area) (string-match-p "\\`[[:alnum:]_@#%]+\\'" area))))
      'rejected)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (glasspane-fab--prompt
          "gp-fab-task" (if area (format "New task in %s" area) "New task")
          (list (glasspane-fab--title-input "gp-fab-title")
                (jetpacs-enum-list
                 "gp-fab-when"
                 (mapcar (lambda (o) (jetpacs-enum-option (cdr o) (car o)))
                         (glasspane-fab--date-options date))
                 :value (or date "none"))
                (jetpacs-text (format "Filed in %s"
                                      (file-name-nondirectory (glasspane-fab-inbox-file)))
                              :style "caption" :color "outline"))
          '("gp-fab-title" "gp-fab-when")
          (lambda (fields)
            (when-let* ((title (glasspane-fab--field fields "gp-fab-title")))
              (let ((when (plist-get fields :gp-fab-when)))
                (condition-case err
                    (progn
                      (glasspane-fab-append-heading
                       (glasspane-fab-inbox-file)
                       (glasspane-fab-task-text
                        title (and (jetpacs-dates-valid-p when) when) area))
                      (glasspane-fab--notify (format "Added “%s”" title) params))
                  (error (glasspane-fab--notify
                          (format "Couldn't add: %s" (error-message-string err))
                          params))))))
          "Add")))
      'accepted))))

(defun glasspane-fab--on-under-clock (_args params)
  "Ask a title, then add it as a TODO under the clocked heading."
  (cond
   ((not (and (glasspane-fab--clocking-p) (markerp org-clock-hd-marker)
              (marker-buffer org-clock-hd-marker)))
    'stale)
   ((null (jetpacs-client)) 'rejected)
   (t
    (let ((ref (with-current-buffer (marker-buffer org-clock-hd-marker)
                 (org-with-wide-buffer
                  (goto-char org-clock-hd-marker)
                  (org-back-to-heading t)
                  (ebp-org-ref-at-point)))))
      (jetpacs-flow-continue
       (lambda ()
         (glasspane-fab--prompt
          "gp-fab-under-clock" "Under the clocked task"
          (list (jetpacs-text (or org-clock-current-task "") :style "caption"
                              :color "outline")
                (glasspane-fab--title-input "gp-fab-title"))
          '("gp-fab-title")
          (lambda (fields)
            (when-let* ((title (glasspane-fab--field fields "gp-fab-title")))
              (condition-case err
                  (progn
                    (jetpacs-org-structure-insert
                     glasspane-fab--owner ref 'glasspane 'child
                     (concat (or (car org-todo-keywords-1) "TODO") " " title))
                    (glasspane-fab--notify (format "Added “%s”" title) params))
                (error (glasspane-fab--notify
                        (format "Couldn't add: %s" (error-message-string err))
                        params)))))
          "Add"))))
    'accepted)))

;;;; Outline verbs (the Files document host; any surface)

(defun glasspane-fab--path (args params)
  "ARGS' current Org document path, or a status symbol."
  (let ((path (plist-get args :path)))
    (cond
     ((not (and (stringp path) (ebp-org-path-p path))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-reader-current-path-p path)) 'stale)
     (t path))))

(defmacro glasspane-fab--in-file (path &rest body)
  "Run BODY in PATH's Org buffer, widened."
  (declare (indent 1))
  `(with-current-buffer (find-file-noselect ,path)
     (org-with-wide-buffer ,@body)))

(defun glasspane-fab--on-file-heading (args params)
  "Ask a title, then append a top-level heading (or TODO) to the file."
  (let ((path (glasspane-fab--path args params))
        (todo (plist-get args :todo)))
    (cond
     ((symbolp path) path)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (glasspane-fab--prompt
          "gp-fab-file-heading" (if todo "New TODO" "New heading")
          (list (jetpacs-text (file-name-nondirectory path) :style "caption"
                              :color "outline")
                (glasspane-fab--title-input "gp-fab-title"))
          '("gp-fab-title")
          (lambda (fields)
            (when-let* ((title (glasspane-fab--field fields "gp-fab-title")))
              (glasspane-fab-append-heading
               path (concat "* " (if todo (concat (or (car org-todo-keywords-1) "TODO")
                                                   " ")
                                   "")
                            title "\n"))
              (glasspane-fab--notify (format "Added “%s”" title) params)))
          "Add")))
      'accepted))))

(defun glasspane-fab--file-command (args params fn message)
  "Run FN in ARGS' file buffer from a continuation; save; notify MESSAGE."
  (let ((path (glasspane-fab--path args params)))
    (if (symbolp path)
        path
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (progn
               (glasspane-fab--in-file path (funcall fn))
               (with-current-buffer (find-file-noselect path)
                 (when (buffer-modified-p)
                   (glasspane-org-save-and-invalidate (current-buffer))))
               (glasspane-fab--notify message params))
           (error (glasspane-fab--notify
                   (format "That did not work: %s" (error-message-string err))
                   params)))))
      'accepted)))

(defun glasspane-fab--on-file-babel (args params)
  "Run every code block in the file."
  (glasspane-fab--file-command args params #'org-babel-execute-buffer
                               "Code blocks ran"))

(defvar glasspane-fab--last-tangle 0
  "How many files the last tangle wrote.")

(defun glasspane-fab--on-file-tangle (args params)
  "Tangle the file's code blocks."
  (glasspane-fab--file-command
   args params
   (lambda ()
     (let ((files (org-babel-tangle)))
       (setq glasspane-fab--last-tangle (length files))))
   "Tangled"))

(defun glasspane-fab--on-file-dblocks (args params)
  "Update every dynamic block (clock tables included) in the file."
  (glasspane-fab--file-command args params #'org-update-all-dblocks
                               "Dynamic blocks updated"))

(defun glasspane-fab-file-times (path)
  "PATH's top-level headings with their clocked minutes, longest first.
A list of (TITLE . MINUTES), nonzero only."
  (glasspane-fab--in-file path
    (org-clock-sum)
    (let (rows)
      (goto-char (point-min))
      (while (re-search-forward "^\\* " nil t)
        (let ((m (get-text-property (line-beginning-position) :org-clock-minutes)))
          (when (and (numberp m) (> m 0))
            (push (cons (org-get-heading t t t t) m) rows))))
      (sort rows (lambda (a b) (> (cdr a) (cdr b)))))))

(defun glasspane-fab--on-file-times (args params)
  "Show the file's clocked totals per top-level heading."
  (let ((path (glasspane-fab--path args params)))
    (cond
     ((symbolp path) path)
     ((null (jetpacs-client)) 'rejected)
     (t
      (let* ((rows (glasspane-fab-file-times path))
             (total (apply #'+ (mapcar #'cdr rows))))
        (jetpacs-flow-continue
         (lambda ()
           (with-jetpacs-owner glasspane-fab--owner
             (jetpacs-dialog-slot-show
              "gp-fab-times"
              (apply #'jetpacs-column
                     (append
                      (list (jetpacs-text "Time totals" :style "title")
                            (jetpacs-text (format "%s in %s"
                                                  (org-duration-from-minutes total)
                                                  (file-name-nondirectory path))
                                          :style "caption" :color "outline"))
                      (or (mapcar (lambda (row)
                                    (jetpacs-row
                                     (jetpacs-with-attrs
                                      (jetpacs-text (car row) :max-lines 1) :weight 1)
                                     (jetpacs-text (org-duration-from-minutes (cdr row))
                                                   :style "label")
                                     :fill t :spacing 12))
                                  (seq-take rows 30))
                          (list (jetpacs-text "Nothing clocked yet." :style "caption")))
                      (list (jetpacs-row
                             (jetpacs-spacer :weight 1)
                             (jetpacs-button "Close" (jetpacs-dialog-dismiss)
                                             :variant "text")
                             :fill t)
                            :spacing 8)))))))
        'accepted)))))

;;;; Lifecycle

(defconst glasspane-fab--verbs
  '("glasspane.fab.add" "glasspane.fab.move" "glasspane.fab.group"
    "glasspane.fab.cookies"
    "glasspane.fab.archive-tag" "glasspane.fab.sort" "glasspane.fab.effort"
    "glasspane.fab.clone" "glasspane.fab.babel-subtree"
    "glasspane.fab.clock-cancel" "glasspane.fab.countdown"
    "glasspane.fab.countdown-stop" "glasspane.fab.quick-task"
    "glasspane.fab.under-clock" "glasspane.fab.file-heading"
    "glasspane.fab.file-babel" "glasspane.fab.file-tangle"
    "glasspane.fab.file-dblocks" "glasspane.fab.file-times")
  "The FAB's verbs.")

(defun glasspane-fab-register ()
  "Register the FAB's verbs, the outline FAB hook and the countdown projection."
  (with-jetpacs-owner glasspane-fab--owner
    (let ((token '((:name token :type "text" :required t))))
      (jetpacs-defaction "glasspane.fab.add" #'glasspane-fab--on-add
                         :doc "Add a child or sibling heading" :strict t
                         :args (append token '((:name relation :type "text" :required t)
                                               (:name todo :type "bool"))))
      (jetpacs-defaction "glasspane.fab.group" #'glasspane-fab--on-group
                         :doc "Show a group of heading actions as a sheet" :strict t
                         :args (append token '((:name group :type "text" :required t))))
      (jetpacs-defaction "glasspane.fab.move" #'glasspane-fab--on-move
                         :doc "Move, promote or demote a subtree" :strict t
                         :args (append token '((:name how :type "text" :required t))))
      (jetpacs-defaction "glasspane.fab.cookies" #'glasspane-fab--on-cookies
                         :doc "Update a subtree's statistics cookies" :strict t :args token)
      (jetpacs-defaction "glasspane.fab.archive-tag" #'glasspane-fab--on-archive-tag
                         :doc "Toggle a heading's ARCHIVE tag" :strict t :args token)
      (jetpacs-defaction "glasspane.fab.sort" #'glasspane-fab--on-sort
                         :doc "Sort a heading's children" :strict t :args token)
      (jetpacs-defaction "glasspane.fab.effort" #'glasspane-fab--on-effort
                         :doc "Set or remove a heading's Effort" :strict t :args token)
      (jetpacs-defaction "glasspane.fab.clone" #'glasspane-fab--on-clone
                         :doc "Clone a subtree with a time shift" :strict t :args token)
      (jetpacs-defaction "glasspane.fab.babel-subtree" #'glasspane-fab--on-babel-subtree
                         :doc "Run every code block in a subtree" :strict t :args token)
      (jetpacs-defaction "glasspane.fab.countdown" #'glasspane-fab--on-countdown
                         :doc "Count down a heading's Effort with a device reminder" :strict t :args token))
    (jetpacs-defaction "glasspane.fab.clock-cancel" #'glasspane-fab--on-clock-cancel
                       :doc "Discard the running clock" :any-surface t)
    (jetpacs-defaction "glasspane.fab.countdown-stop" #'glasspane-fab--on-countdown-stop
                       :doc "Stop the running countdown")
    (jetpacs-defaction "glasspane.fab.quick-task" #'glasspane-fab--on-quick-task
                       :doc "File a quick TODO in the inbox" :strict t
                       :args '((:name date :type "text") (:name area :type "text")))
    (jetpacs-defaction "glasspane.fab.under-clock" #'glasspane-fab--on-under-clock
                       :doc "Add a TODO under the clocked heading")
    (let ((path '((:name path :type "text" :required t))))
      (jetpacs-defaction "glasspane.fab.file-heading" #'glasspane-fab--on-file-heading
                         :doc "Append a top-level heading to the open file"
                         :any-surface t :strict t
                         :args (append path '((:name todo :type "bool"))))
      (jetpacs-defaction "glasspane.fab.file-babel" #'glasspane-fab--on-file-babel
                         :doc "Run every code block in the open file" :any-surface t :strict t :args path)
      (jetpacs-defaction "glasspane.fab.file-tangle" #'glasspane-fab--on-file-tangle
                         :doc "Tangle the open file" :any-surface t :strict t :args path)
      (jetpacs-defaction "glasspane.fab.file-dblocks" #'glasspane-fab--on-file-dblocks
                         :doc "Update the open file's dynamic blocks" :any-surface t :strict t :args path)
      (jetpacs-defaction "glasspane.fab.file-times" #'glasspane-fab--on-file-times
                         :doc "Show the open file's clocked totals" :any-surface t :strict t :args path))
    ;; Before the stock Org editor's add-heading FAB: Glasspane's reader
    ;; owns the outline it draws.
    (jetpacs-add-hook 'jetpacs-files-editor-fab-functions
                      #'glasspane-fab--outline-fab -50))
  (jetpacs-reminders-define-projection glasspane-fab--owner
                                       #'glasspane-fab--reminders))

(defun glasspane-fab-unregister ()
  "Drop the FAB's verbs, hook and countdown."
  (dolist (name glasspane-fab--verbs)
    (jetpacs-undefaction name))
  (jetpacs-remove-hook 'jetpacs-files-editor-fab-functions
                       #'glasspane-fab--outline-fab)
  (jetpacs-reminders-remove-projection glasspane-fab--owner)
  (setq glasspane-fab--countdown nil))

(provide 'glasspane-fab)
;;; glasspane-fab.el ends here
