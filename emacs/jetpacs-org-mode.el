;;; jetpacs-org-mode.el --- Org Mode app for Jetpacs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The composition root for Org Mode as a Jetpacs App.  The reusable
;; reader/editor hosts know nothing about Org; the two Org adapters rent
;; built-in Org behavior; this file registers them together, gives the
;; experience app identity and navigation, and composes the existing
;; Files and Habits surfaces.  Capture and recurring agenda reminders
;; live here because they belong to the Org app as a whole, not to one
;; document presentation.  This is the precedent for a future
;; `jetpacs-elisp-mode.el': a mode app supplies adapters and a thin
;; composition root, not another editor protocol or file browser.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'calendar)
(require 'org-agenda)
(require 'org-protocol)
(require 'ebp-org)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-device)
(require 'jetpacs-apps)
(require 'jetpacs-files)
(require 'jetpacs-reader)
(require 'jetpacs-editor)
(require 'jetpacs-reader-org)
(require 'jetpacs-editor-org)
(require 'jetpacs-org-habits)

(defconst jetpacs-org-mode-owner "org-mode"
  "Owner and app id for the Org Mode app.")

(defconst jetpacs-org-mode-title "Org Mode"
  "Human-facing title of the Org Mode app.")

(defconst jetpacs-org-mode-icon "description"
  "Material icon used for the Org Mode app.")

(defvar jetpacs-org-mode--registered nil
  "Non-nil while the Org Mode app is registered.")

(defcustom jetpacs-org-mode-reminder-horizon-hours 24
  "How far ahead timed Org Agenda items become device reminders.
A date-only scheduled item is not an alarm.  Repeating timestamps are
expanded by Org Agenda before reminders are built."
  :type 'natnum :group 'jetpacs-org)

(defvar jetpacs-org-mode-reminders-enabled nil
  "Non-nil when the legacy inline Org Mode reminder hook is enabled.
This pipeline has no device history and stays disabled while reminder
ownership moves to the dedicated Org reminder module.  Keep the flag
until that cutover's rollback window closes.")

(defconst jetpacs-org-mode--agenda-buffer "*Jetpacs Org Mode Agenda*"
  "Private Org Agenda buffer used while deriving reminder data.")

(defvar jetpacs-org-mode--last-reminders 'unset
  "Last reminder set confirmed by the Companion.")

(defvar jetpacs-org-mode--owns-share-action nil
  "Non-nil when this app installed the global `share.text' fallback.")

(defconst jetpacs-org-mode--asset-directory
  (let* ((library (or load-file-name (locate-library "jetpacs-org-mode")))
         (base (and library (file-name-directory library))))
    (and base
         (cl-find-if
          #'file-directory-p
          (list (expand-file-name "org" base)
                (expand-file-name "../org" base)))))
  "Distribution directory containing the Org starter and manual bundle.
The first location is the flattened device install; the second is the
source-tree layout.")

(defun jetpacs-org-mode-seed-paths ()
  "Return destination paths for the starter inbox and bundled manual."
  (let* ((root (file-name-as-directory (expand-file-name org-directory)))
         (manual-dir (expand-file-name "org-mode-walkthrough" root)))
    (list :root root
          :inbox (expand-file-name "inbox.org" root)
          :manual-directory manual-dir
          :manual (expand-file-name "orgro-manual.org" manual-dir))))

(defun jetpacs-org-mode--copy-missing (source destination)
  "Recursively copy SOURCE to DESTINATION without overwriting anything."
  (cond
   ((file-directory-p source)
    (make-directory destination t)
    (dolist (entry (directory-files
                    source t directory-files-no-dot-files-regexp))
      (jetpacs-org-mode--copy-missing
       entry (expand-file-name (file-name-nondirectory entry) destination))))
   ((and (file-regular-p source) (not (file-exists-p destination)))
    (make-directory (file-name-directory destination) t)
    (copy-file source destination nil t))))

(defun jetpacs-org-mode-seed ()
  "Seed the starter inbox and complete Orgro manual bundle.
Files land below `org-directory'. Existing destinations are never
overwritten, making this safe and idempotent. Remote Org directories
and installations missing their distributed assets are left untouched.
Return the paths plist from `jetpacs-org-mode-seed-paths', or nil."
  (let* ((paths (jetpacs-org-mode-seed-paths))
         (root (plist-get paths :root)))
    (cond
     ((file-remote-p root)
      (message "jetpacs-org-mode: refusing to seed a remote Org directory")
      nil)
     ((not (and jetpacs-org-mode--asset-directory
                (file-directory-p jetpacs-org-mode--asset-directory)))
      (message "jetpacs-org-mode: seed assets are unavailable")
      nil)
     (t
      (make-directory root t)
      (jetpacs-org-mode--copy-missing
       (expand-file-name "inbox.org" jetpacs-org-mode--asset-directory)
       (plist-get paths :inbox))
      (jetpacs-org-mode--copy-missing
       (expand-file-name
        "org-mode-walkthrough" jetpacs-org-mode--asset-directory)
       (plist-get paths :manual-directory))
      (ebp-org-cache-invalidate)
      paths))))

(defun jetpacs-org-mode--seed-safely ()
  "Seed app content while keeping an asset failure local to the app."
  (condition-case err
      (jetpacs-org-mode-seed)
    (error
     (message "jetpacs-org-mode: seed failed: %s"
              (jetpacs-error-label err))
     nil)))

;;;; Capture

(defun jetpacs-org-mode--capture-templates ()
  "Return selectable, non-prefix Org capture template plists."
  (cl-remove-if-not
   (lambda (template)
     (let ((entry (assoc (plist-get template :key) org-capture-templates)))
       (and entry (> (length entry) 4))))
   (ebp-org-capture-templates)))

(defun jetpacs-org-mode--capture-choice (templates)
  "Prompt for and return one member of TEMPLATES."
  (let* ((choices
          (mapcar
           (lambda (template)
             (cons (format "%s — %s"
                           (plist-get template :key)
                           (or (plist-get template :description)
                               "Capture"))
                   template))
           templates))
         (label (completing-read "Capture template: " choices nil t)))
    (cdr (assoc label choices))))

(defun jetpacs-org-mode--capture-values (template subject)
  "Collect TEMPLATE fields, seeding its Headline from SUBJECT."
  (mapcar
   (lambda (prompt)
     (cons prompt
           (read-string (format "%s: " prompt)
                        (and (equal prompt "Headline") subject))))
   (append (plist-get template :prompts) nil)))

(defun jetpacs-org-mode--protocol-info (text)
  "Return Org Protocol capture info encoded by TEXT, or nil.
Both modern query-string and legacy slash-separated capture URLs use
the parser shipped with Org."
  (when (and (stringp text)
             (string-match
              "\\`org-protocol:/+capture\\(:/+\\|/*\\?\\)" text))
    (let ((separator (match-string 1 text))
          (data (substring text (match-end 0))))
      (if (string-suffix-p "?" separator)
          (org-protocol-parse-parameters data t)
        data))))

(defun jetpacs-org-mode--protocol-parts (info)
  "Normalize built-in Org Protocol capture INFO to a plist."
  (pcase (org-protocol-parse-parameters info)
    ((let `(,(pred keywordp) . ,_) info) info)
    (parts
     (let ((keys (if (= 1 (length (car parts)))
                     '(:template :url :title :body)
                   '(:url :title :body))))
       (org-protocol-assign-parameters parts keys)))))

(defun jetpacs-org-mode--protocol-capture (info templates)
  "Run Org Protocol capture INFO using one of TEMPLATES, headlessly.
Org's parser, link properties, template expansion, and capture engine
remain authoritative; Jetpacs only gathers any template prompts and
forces the existing safe headless finalization path."
  (let* ((parts (jetpacs-org-mode--protocol-parts info))
         (requested (or (plist-get parts :template)
                        org-protocol-default-template-key))
         (template
          (if (and (stringp requested) (not (string-empty-p requested)))
              (cl-find requested templates :key (lambda (item)
                                                  (plist-get item :key))
                       :test #'equal)
            (jetpacs-org-mode--capture-choice templates))))
    (unless template
      (user-error "Org Protocol requested an unknown capture template"))
    (let* ((url (and (plist-get parts :url)
                     (org-protocol-sanitize-uri (plist-get parts :url))))
           (title (or (plist-get parts :title) ""))
           (body (or (plist-get parts :body) ""))
           (type (and url (string-match "^\\([a-z]+\\):" url)
                      (match-string 1 url)))
           (orglink (if (null url) title
                      (org-link-make-string
                       url (or (org-string-nw-p title) url))))
           (org-capture-link-is-already-stored t))
      (when url (push (list url title) org-stored-links))
      (org-link-store-props :type type
                            :link url
                            :description title
                            :annotation orglink
                            :initial body
                            :query parts)
      (ebp-org-capture-run
       (plist-get template :key)
       (jetpacs-org-mode--capture-values template title)))))

(defun jetpacs-org-mode--capture-now (&optional shared-text shared-subject)
  "Run one bridged Org capture, optionally carrying shared-in content."
  (if (not (jetpacs-connected-p))
      (message "jetpacs-org-mode: capture cancelled after disconnect")
    (condition-case err
        (let ((templates (jetpacs-org-mode--capture-templates)))
          (if (null templates)
              (jetpacs-shell-notify
               "No Org capture templates are configured"
               jetpacs-org-mode-owner)
            (if-let ((protocol-info
                      (jetpacs-org-mode--protocol-info shared-text)))
                (jetpacs-org-mode--protocol-capture protocol-info templates)
              (let* ((template (jetpacs-org-mode--capture-choice templates))
                     (values (jetpacs-org-mode--capture-values
                              template shared-subject)))
                (ebp-org-capture-run (plist-get template :key)
                                     values shared-text)))
              (ebp-org-cache-invalidate)
              (jetpacs-shell-notify "Captured ✓"
                                    jetpacs-org-mode-owner)))
      (quit
       (jetpacs-shell-notify "Capture cancelled" jetpacs-org-mode-owner))
      (error
       (message "jetpacs-org-mode: capture failed: %s"
                (jetpacs-error-label err))
       (jetpacs-shell-notify "Capture failed" jetpacs-org-mode-owner)))))

(defun jetpacs-org-mode--on-capture (_args _params)
  "Open the Org capture flow from the app home."
  (if (not (jetpacs-connected-p))
      'rejected
    (jetpacs-flow-continue #'jetpacs-org-mode--capture-now)
    'accepted))

(defun jetpacs-org-mode--on-share (args _params)
  "Capture text and subject supplied by the Companion share sheet."
  (let* ((raw-text (plist-get args :text))
         (raw-subject (plist-get args :subject))
         (text (and (stringp raw-text)
                    (not (string-empty-p (string-trim raw-text)))
                    (string-trim raw-text)))
         (subject (and (stringp raw-subject)
                       (not (string-empty-p (string-trim raw-subject)))
                       (string-trim raw-subject)))
         (body (or text subject)))
    (if (not (jetpacs-connected-p))
        'rejected
      (jetpacs-flow-continue
       (lambda () (jetpacs-org-mode--capture-now body subject)))
      'accepted)))

;;;; Agenda reminders

(defun jetpacs-org-mode--agenda-scope ()
  "Return existing local Org agenda files, expanding directories."
  (cl-mapcan
   (lambda (entry)
     (cond
      ((file-directory-p entry)
       (directory-files entry t org-agenda-file-regexp))
      ((file-exists-p entry) (list entry))))
   (ebp-org-agenda-files)))

(defun jetpacs-org-mode--agenda-items-1 (days)
  "Extract the next DAYS of Org Agenda entries needed for reminders."
  (let ((files (jetpacs-org-mode--agenda-scope)))
    (when files
      (let ((org-agenda-span days)
            (org-agenda-start-day nil)
            (org-agenda-files files)
            (org-agenda-buffer-tmp-name jetpacs-org-mode--agenda-buffer)
            (org-agenda-sticky nil)
            (inhibit-redisplay t)
            items)
        (unwind-protect
            (save-window-excursion
              (let ((org-agenda-window-setup 'current-window))
                (ebp-org--with-clamped-io (org-agenda nil "a")))
              (with-current-buffer jetpacs-org-mode--agenda-buffer
                (goto-char (point-min))
                (while (not (eobp))
                  (let* ((marker (get-text-property (point) 'org-marker))
                         (time (get-text-property (point) 'time))
                         (type (get-text-property (point) 'type))
                         (raw-date (get-text-property (point) 'date))
                         (date
                          (cond
                           ((consp raw-date) raw-date)
                           ((numberp raw-date)
                            (calendar-gregorian-from-absolute raw-date)))))
                    (when (and marker date)
                      (with-current-buffer (marker-buffer marker)
                        (save-excursion
                          (goto-char marker)
                          (push
                           (list
                            :headline (nth 4 (org-heading-components))
                            :file (buffer-file-name)
                            :pos (marker-position marker)
                            :time time
                            :date (format "%04d-%02d-%02d"
                                          (nth 2 date) (nth 0 date)
                                          (nth 1 date))
                            :type (and type (format "%s" type)))
                           items)))))
                  (forward-line 1))))
          (when-let ((buffer (get-buffer jetpacs-org-mode--agenda-buffer)))
            (kill-buffer buffer)))
        (nreverse items)))))

(defun jetpacs-org-mode--agenda-items (days)
  "Memoized reminder projection for the next DAYS of Org Agenda."
  (ebp-org-with-cache 'org-mode (list 'reminder-agenda days)
    (jetpacs-org-mode--agenda-items-1 days)))

(defun jetpacs-org-mode--item-hour-minute (raw)
  "Normalize Org Agenda RAW time-grid text to HH:MM, or nil."
  (when (stringp raw)
    (let ((text (string-trim raw)))
      (when (string-match
             "\\`\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)" text)
        (format "%02d:%s" (string-to-number (match-string 1 text))
                (match-string 2 text))))))

(defun jetpacs-org-mode--upcoming-reminders (&optional horizon-hours now)
  "Return timed Org Agenda reminders within HORIZON-HOURS of NOW.
NOW is an Emacs time value and defaults to `current-time'."
  (let* ((hours (or horizon-hours jetpacs-org-mode-reminder-horizon-hours))
         (horizon (* hours 3600))
         (now-seconds (float-time (or now (current-time))))
         (days (max 1 (1+ (ceiling (/ hours 24.0)))))
         reminders
         seen)
    (dolist (item (jetpacs-org-mode--agenda-items days))
      (when-let* ((date (plist-get item :date))
                  (hm (jetpacs-org-mode--item-hour-minute
                       (plist-get item :time))))
        (let ((at (float-time
                   (org-time-string-to-time (concat date " " hm)))))
          (when (and (> at now-seconds) (< (- at now-seconds) horizon))
            (let* ((identity
                    (format "%sT%s|%s|%s" date hm
                            (or (plist-get item :file) "")
                            (or (plist-get item :pos) 0)))
                   (id (format "org-rem-%s"
                               (substring (sha1 identity) 0 20))))
              ;; A heading scheduled and deadlined for the same instant
              ;; appears twice in Org Agenda but must create one alarm.
              (unless (member id seen)
                (push id seen)
                (push
                 (list :id id
                       :at_ms (truncate (* at 1000))
                       :title (or (plist-get item :headline)
                                  "Org reminder")
                       :body (concat hm
                                     (when-let ((type
                                                 (plist-get item :type)))
                                       (concat " · " type))))
                 reminders)))))))
    (nreverse reminders)))

(defun jetpacs-org-mode--sync-reminders ()
  "Synchronize recurring Org Agenda alarms after a successful push."
  (when (and (jetpacs-connected-p)
             (jetpacs-granted-p "reminders.owner"))
    (let ((reminders
           (condition-case err
               (jetpacs-org-mode--upcoming-reminders)
             (error
              (message "jetpacs-org-mode: reminder scan failed: %s"
                       (jetpacs-error-label err))
              nil))))
      (unless (equal reminders jetpacs-org-mode--last-reminders)
        (condition-case err
            (jetpacs-reminders-set
             reminders :owner jetpacs-org-mode-owner
             :callback
             (lambda (_count error)
               (unless error
                 (setq jetpacs-org-mode--last-reminders reminders))))
          (error
           (message "jetpacs-org-mode: reminder sync failed: %s"
                    (jetpacs-error-label err))))))))

(defun jetpacs-org-mode--surface (owner)
  "Return OWNER's negotiated surface name."
  (jetpacs-shell-surface-for owner))

(defun jetpacs-org-mode--on-open-seed (args params)
  "Open a known seeded document selected by ARGS through the Files app."
  (let ((document (plist-get args :document)))
    (cond
     ((not (member document '("manual" "inbox"))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t
      (condition-case err
          (let* ((paths (jetpacs-org-mode-seed))
                 (path (and paths
                            (plist-get paths
                                       (if (equal document "manual")
                                           :manual :inbox)))))
            (if (not (stringp path))
                'rejected
              ;; This is intentionally the exact public path used by a Files
              ;; row—not a look-alike document view on the Org surface.  It
              ;; performs the same root check, canonicalization, document-host
              ;; selection, and navigation on the canonical Files surface.
              (jetpacs-files-open-path
               path (jetpacs-org-mode--surface jetpacs-files-owner))))
        (error
         (message "jetpacs-org-mode: opening seed failed: %s"
                  (jetpacs-error-label err))
         'rejected))))))

(defun jetpacs-org-mode--screen (back)
  "Build the Org Mode app home screen with BACK navigation."
  (jetpacs-chrome-screen
   jetpacs-org-mode-title
   (jetpacs-lazy-column
    (jetpacs-text
     "A complete Org app powered by Emacs itself: reader mode, visibility cycling, search and sparse trees; whole-file or narrowed editing; structured edits, links, media, citations, attachments, LaTeX, tables, Org Crypt, capture, and recurring reminders."
     :style "body")
    (jetpacs-chrome-row
     "Open Org files"
     :subtitle "Browse, read, and edit .org documents"
     :icon "folder_open"
     :on-tap (jetpacs-action
              "jetpacs.launcher.open"
              :args (list :surface
                          (jetpacs-org-mode--surface jetpacs-files-owner)))
     :key "org-mode-files")
    (jetpacs-chrome-row
     "Orgro manual"
     :subtitle "Bundled upstream guide and feature examples"
     :icon "menu_book"
     :on-tap (jetpacs-action "org-mode.open-seed"
                             :args '(:document "manual"))
     :key "org-mode-manual")
    (jetpacs-chrome-row
     "Starter inbox"
     :subtitle "A safe, editable seed created only when missing"
     :icon "inbox"
     :on-tap (jetpacs-action "org-mode.open-seed"
                             :args '(:document "inbox"))
     :key "org-mode-inbox")
    (jetpacs-chrome-row
     "Quick capture"
     :subtitle "Use your built-in org-capture templates"
     :icon "add_task"
     :on-tap (jetpacs-action "org-mode.capture")
     :key "org-mode-capture")
    (jetpacs-chrome-row
     "Habits"
     :subtitle "Consistency graphs from built-in org-habit"
     :icon "event_repeat"
     :on-tap (jetpacs-action
              "jetpacs.launcher.open"
              :args (list :surface
                          (jetpacs-org-mode--surface
                           jetpacs-org-habits-owner)))
     :key "org-mode-habits")
    (jetpacs-card
     (jetpacs-column
      (jetpacs-text "Built-in-backed" :style "title")
      (jetpacs-text
       "Org parses and edits the document; Jetpacs only presents it. Timed agenda entries become recurring-aware device reminders when permission is granted. The bundled walkthrough is Orgro's upstream manual; its transclusion section is retained as source documentation, but transclusion remains Jetpacs' sole intentional omission because it is not built into Emacs."
       :style "body")
      :spacing 6))
    :spacing 12)
   :back back))

(defun jetpacs-org-mode--claimed-surfaces ()
  "Owners whose surfaces form the Org Mode app experience."
  (list jetpacs-org-mode-owner
        jetpacs-files-owner
        jetpacs-org-habits-owner))

(defun jetpacs-org-mode--dock-items (surface)
  "Return the Org Mode dock destination for SURFACE."
  (let ((selected
         (member surface
                 (mapcar #'jetpacs-org-mode--surface
                         (jetpacs-org-mode--claimed-surfaces)))))
    (list
     (list :label jetpacs-org-mode-title
           :icon jetpacs-org-mode-icon
           :on-tap (jetpacs-action
                    "jetpacs.launcher.open"
                    :args (list :surface
                                (jetpacs-org-mode--surface
                                 jetpacs-org-mode-owner)))
           :selected (and selected t)))))

(defun jetpacs-org-mode-register ()
  "Register the Org adapters, root surface, and app identity."
  (unless jetpacs-org-mode--registered
    (setq jetpacs-org-mode--registered t)
    (jetpacs-reader-install)
    (jetpacs-editor-install)
    (jetpacs-reader-org-register)
    (jetpacs-editor-org-register)
    (with-jetpacs-owner jetpacs-org-mode-owner
      (jetpacs-defaction "org-mode.capture"
                         #'jetpacs-org-mode--on-capture
                         :doc "Run an Org capture template")
      (jetpacs-defaction "org-mode.open-seed"
                         #'jetpacs-org-mode--on-open-seed
                         :doc "Open bundled Org Mode content")
      (jetpacs-chrome-define-root jetpacs-org-mode-owner "home"
                                  #'jetpacs-org-mode--screen))
    ;; The Companion's share verb is global.  An installed PKM app may
    ;; already own a richer intake; in that case leave it untouched and
    ;; let the Org Mode app supply only its explicit Quick Capture path.
    (unless (gethash "share.text" jetpacs-action-handlers)
      (jetpacs-defaction "share.text" #'jetpacs-org-mode--on-share
                         :any-surface t
                         :doc "Capture text shared from another app")
      (setq jetpacs-org-mode--owns-share-action t))
    (when jetpacs-org-mode-reminders-enabled
      (add-hook 'jetpacs-shell-after-push-hook
                #'jetpacs-org-mode--sync-reminders))
    (jetpacs-defapp
     jetpacs-org-mode-owner
     :label jetpacs-org-mode-title
     :icon jetpacs-org-mode-icon
     :surfaces (jetpacs-org-mode--claimed-surfaces)
     :dock #'jetpacs-org-mode--dock-items
     :order 40))
  (unless noninteractive
    (jetpacs-org-mode--seed-safely))
  t)

(defun jetpacs-org-mode-unregister ()
  "Unregister the Org Mode app and its mode adapters."
  (when jetpacs-org-mode--registered
    (setq jetpacs-org-mode--registered nil)
    (remove-hook 'jetpacs-shell-after-push-hook
                 #'jetpacs-org-mode--sync-reminders)
    (setq jetpacs-org-mode--last-reminders 'unset)
    (jetpacs-undefaction "org-mode.capture")
    (jetpacs-undefaction "org-mode.open-seed")
    (when jetpacs-org-mode--owns-share-action
      ;; Do not tear down a handler another app installed after us.
      (when (eq (gethash "share.text" jetpacs-action-handlers)
                #'jetpacs-org-mode--on-share)
        (jetpacs-undefaction "share.text"))
      (setq jetpacs-org-mode--owns-share-action nil))
    (jetpacs-apps-unregister jetpacs-org-mode-owner)
    (jetpacs-chrome-remove jetpacs-org-mode-owner)
    (jetpacs-reader-org-unregister)
    (jetpacs-editor-org-unregister))
  t)

(jetpacs-org-mode-register)

;;;###autoload
(defun jetpacs-org-mode ()
  "Open the Org Mode app on the connected device."
  (interactive)
  (jetpacs-org-mode--seed-safely)
  (jetpacs-shell-push jetpacs-org-mode-owner))

(defun jetpacs-org-mode-unload-function ()
  "Unload hygiene for the Org Mode app."
  (jetpacs-org-mode-unregister)
  nil)

(provide 'jetpacs-org-mode)
;;; jetpacs-org-mode.el ends here
