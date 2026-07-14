;;; glasspane-journal.el --- Daily-note landing surface -*- lexical-binding: t; -*-

;; The Logseq bootstrapping habit, org-native (PKM plan Task 5): open
;; the app → today's page, ready to type.  A `journal' tab renders one
;; datetree day at a time — capture row on top, the day's content
;; through the foldable reader, and (on today) a "Carried over" section
;; of unfinished TODOs scheduled before today with one-tap reschedule.
;;
;; Engine decision: plain `org-datetree' (builtin, standard, importable
;; — the file layout every journal tool understands).  vulpea-journal
;; gets evaluated when the vulpea spike runs on device (PKM Task 1);
;; the seam is `glasspane-journal--append' / `--day-pos', one code path
;; either way.
;;
;; The journal file defaults to journal.org in `org-directory' — no new
;; layout invented, nothing seeded until the first capture creates the
;; datetree.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-datetree)
(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
(require 'glasspane-org)
(require 'glasspane-org-reader)
(require 'glasspane-ui)                ; date helpers + the glasspane defapp

(defcustom glasspane-journal-file nil
  "The journal file holding the datetree.
nil means journal.org inside `org-directory'."
  :type '(choice (const :tag "journal.org in org-directory" nil) file)
  :group 'jetpacs)

(defcustom glasspane-journal-landing nil
  "When non-nil the app opens on the Journal view instead of Agenda."
  :type 'boolean :group 'jetpacs)

(defvar glasspane-journal--date nil
  "The day being viewed (\"YYYY-MM-DD\"), or nil for today.")

(defun glasspane-journal--capture-form ()
  "The capture row's field registry (`jetpacs-form').
Reset after each append: rotating the field id is the server-driven
way to clear the input field."
  (jetpacs-form "journal" "glasspane"))

(defun glasspane-journal--file ()
  "The journal file path."
  (or glasspane-journal-file
      (expand-file-name "journal.org" org-directory)))

(defun glasspane-journal--today ()
  (format-time-string "%Y-%m-%d"))

(defun glasspane-journal--current ()
  "The date the view shows."
  (or glasspane-journal--date (glasspane-journal--today)))

;; ─── The datetree seam ───────────────────────────────────────────────────────

(defun glasspane-journal--day-pos (date)
  "Position of DATE's day heading in the journal file, or nil.
Datetree day headings read \"*** 2026-07-05 Saturday\"; the full
Y-m-d makes the match unambiguous against month/year levels."
  (let ((file (glasspane-journal--file)))
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (when (re-search-forward
                (format "^\\*+[ \t]+%s\\(?:[ \t]\\|$\\)" (regexp-quote date))
                nil t)
           (line-beginning-position)))))))

(defvar glasspane-org--inhibit-save-refresh)

(defun glasspane-journal--append (text &optional date)
  "Append TEXT as a plain list item under DATE's (default today) day.
Creates the datetree levels (and the file) on first use."
  (let ((date (or date (glasspane-journal--today)))
        (file (glasspane-journal--file)))
    (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number
                                     (split-string date "-"))))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-datetree-find-date-create (list m d y))
         (org-back-to-heading t)
         (org-end-of-subtree t t)
         (unless (bolp) (insert "\n"))
         (insert "- " text "\n"))
        (let ((glasspane-org--inhibit-save-refresh t)
              (save-silently t))
          (save-buffer))))
    (jetpacs-org-cache-invalidate 'glasspane)))

(defun glasspane-journal--carried-over ()
  "Unfinished TODOs scheduled before today — the carry-over list."
  (glasspane-org--query '(and (todo) (scheduled :to -1))))

;; ─── The view ────────────────────────────────────────────────────────────────

(defun glasspane-journal--nav-row (date today-p)
  "‹ yesterday | the day (a native date picker) | tomorrow › chrome."
  (apply #'jetpacs-row
         (delq nil
               (list
                (jetpacs-icon-button
                 "chevron_left"
                 (jetpacs-action "journal.nav" :args '((delta . -1))
                              :when-offline "drop")
                 :content-description "Previous day")
                (jetpacs-box
                 (list (jetpacs-date-button
                        (glasspane-ui--format-date
                         date (if today-p "Today · %a, %b %e" "%a, %b %e, %Y"))
                        (jetpacs-action "journal.goto" :when-offline "drop")
                        :value date))
                 :weight 1 :alignment "center")
                (unless today-p
                  (jetpacs-chip "Today"
                             :on-tap (jetpacs-action "journal.today"
                                                  :when-offline "drop")))
                (jetpacs-icon-button
                 "chevron_right"
                 (jetpacs-action "journal.nav" :args '((delta . 1))
                              :when-offline "drop")
                 :content-description "Next day")))))

(defun glasspane-journal--capture-row (date)
  "The always-on-top quick-capture input for DATE."
  (jetpacs-text-input
   (jetpacs-form-field-id (glasspane-journal--capture-form) "capture")
   :hint "Add to this day…"
   :single-line t
   :on-submit (jetpacs-action "journal.capture"
                           :args `((date . ,date))
                           :when-offline "queue")))

(defun glasspane-journal--day-nodes (date)
  "DATE's datetree content through the foldable reader, or a placeholder."
  (or (when-let ((pos (glasspane-journal--day-pos date)))
        (glasspane-org-reader-subtree (glasspane-journal--file) pos t))
      (list (jetpacs-text "Nothing here yet — the row above starts the day."
                       'caption))))

(defun glasspane-journal--carried-card (item)
  "One carried-over TODO with one-tap reschedule.
The buttons ride the existing allowlisted `heading.schedule' — the
orgro timestamp-tap-edit item folds in here."
  (let ((ref (alist-get 'ref item)))
    (jetpacs-card
     (list
      (jetpacs-column
       (jetpacs-text (or (alist-get 'headline item) "") 'body)
       (jetpacs-text (format "%s · %s"
                          (or (alist-get 'todo item) "TODO")
                          (or (alist-get 'scheduled item) ""))
                  'caption)
       (jetpacs-row
        (jetpacs-spacer :weight 1)
        (jetpacs-button "Today"
                     (jetpacs-action "heading.schedule"
                                  :args (append ref '((when . "+0d")))
                                  :when-offline "queue")
                     :variant "text")
        (jetpacs-date-button "Pick"
                          (jetpacs-action "heading.schedule"
                                       :args ref
                                       :when-offline "queue"))))))))

(defun glasspane-journal--view (snackbar)
  "The journal screen for the current date."
  (let* ((date (glasspane-journal--current))
         (today-p (equal date (glasspane-journal--today)))
         ;; A broken query must cost the section, not the day.
         (carried (and today-p
                       (condition-case nil
                           (glasspane-journal--carried-over)
                         (error nil)))))
    (jetpacs-shell-tab-view
     "glasspane.journal"
     (apply #'jetpacs-lazy-column
            (append
             (list (glasspane-journal--nav-row date today-p)
                   (glasspane-journal--capture-row date)
                   (jetpacs-spacer :height 4))
             (glasspane-journal--day-nodes date)
             (when carried
               (append
                (list (jetpacs-divider)
                      (jetpacs-section-header
                       (format "Carried over (%d)" (length carried))))
                (mapcar #'glasspane-journal--carried-card carried)))
             ;; The clock rides the journal (its own tab felt barren and
             ;; crowded the bottom bar) — today's time is journal matter.
             (when (and today-p (fboundp 'glasspane-ui--clock-body))
               (list (jetpacs-divider)
                     (jetpacs-section-header "Clock")
                     (glasspane-ui--clock-body)))))
     :snackbar snackbar)))

(jetpacs-shell-define-view "glasspane.journal"
                        :builder #'glasspane-journal--view
                        :tab '(:icon "today" :label "Journal")
                        :order 15)

;; ─── Landing & state resets ──────────────────────────────────────────────────

(defun glasspane-journal--apply-landing (_welcome)
  "Land on the journal when configured and no tab was chosen this session.
Depth 5: before the shell's on-connect push (10) builds the surface.

This deliberately reads and seeds the internal `jetpacs-shell--current-tab'
rather than the promoted `jetpacs-shell-current-tab' / -set-current-tab
seams: the public getter falls back to the first registered tab (so it can
never report \"no tab chosen\"), and the public setter routes through
`jetpacs-shell-push' — which at connect depth 5 would fire a premature push
and the view-switched hook before the depth-10 push builds the surface.
A public \"is a tab explicitly set / seed without pushing\" accessor does
not exist in jetpacs 1.5.0; until it does, this seam stays on the raw var."
  (when (and glasspane-journal-landing (null jetpacs-shell--current-tab))
    (setq jetpacs-shell--current-tab "glasspane.journal")))

(add-hook 'jetpacs-connected-hook #'glasspane-journal--apply-landing 5)

(defun glasspane-journal--on-view-switched (view)
  "Leaving the journal resets it to today — returning starts fresh."
  (unless (equal view "glasspane.journal")
    (setq glasspane-journal--date nil)))

(add-hook 'jetpacs-shell-view-switched-hook #'glasspane-journal--on-view-switched)

(with-jetpacs-owner "glasspane"
  (jetpacs-settings-register-section
   "Journal"
   '((glasspane-journal-landing :label "Open on the journal"))))

;; ─── Actions ─────────────────────────────────────────────────────────────────

(jetpacs-defaction "journal.nav"
  (lambda (args _)
    (let ((delta (alist-get 'delta args)))
      (when (integerp delta)
        (setq glasspane-journal--date
              (glasspane-ui--shift-date (glasspane-journal--current)
                                        delta 'day))
        (jetpacs-shell-push)))))

(jetpacs-defaction "journal.goto"
  (lambda (args _)
    (let ((date (alist-get 'value args)))
      (when (and (stringp date)
                 (string-match-p
                  "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
        (setq glasspane-journal--date date)
        (jetpacs-shell-push)))))

(jetpacs-defaction "journal.today"
  (lambda (_args _)
    (setq glasspane-journal--date nil)
    (jetpacs-shell-push)))

(jetpacs-defaction "journal.capture"
  (lambda (args _)
    (let ((text (string-trim (or (alist-get 'value args) "")))
          (date (alist-get 'date args)))
      (unless (string-empty-p text)
        (glasspane-journal--append
         text (and (stringp date) (not (string-empty-p date)) date))
        ;; Rotate the input id: the re-render clears the field.
        (jetpacs-form-reset (glasspane-journal--capture-form))
        (jetpacs-shell-notify "Added to journal")
        (jetpacs-shell-push))))
  :doc "Append text to the current journal day."
  :args '((:name value :type "text" :required t)
          (:name date :type "date")))

(provide 'glasspane-journal)
;;; glasspane-journal.el ends here
