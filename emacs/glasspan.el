;; =============================================================================
;; GLASSPANE INIT
;; Single source of truth for Emacs + Glasspane Android integration.
;; Replaces both the old init.el and glasspane.el.
;; =============================================================================

;; --- 1. SERVER SOCKET ---
(require 'server)
(setq server-socket-dir "~/.emacs.d/server")
(unless (server-running-p)
  (server-start))

;; --- 2. ORG DIRECTORIES ---
(setq org-directory "~/org")
(setq org-agenda-files (list (concat org-directory "/trackers.org")))

;; --- 3. PACKAGES & DEPENDENCIES ---
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(dolist (pkg '(simple-httpd org-ql))
  (unless (package-installed-p pkg)
    (package-install pkg)))

(require 'org-ql)
(require 'json)
(require 'simple-httpd)
(require 'org-id)
(require 'org-capture)

;; --- 4. CAPTURE TEMPLATES ---
(setq org-capture-templates
      '(("t" "Quick Task" entry (file "~/inbox.org")
         "* TODO %^{Task}\n%^{Details}\n%U"
         :empty-lines 1)
        ("s" "Scheduled Task" entry (file "~/inbox.org")
         "* TODO %^{Task}\nSCHEDULED: %t\n%^{Details}\n"
         :empty-lines 1)
        ("w" "Workout Log" entry (file "~/health.org")
         "* Training Log: %U\n- Pistol Squats: %^{Pistol Squats|0}\n- Muscle-Ups: %^{Muscle-Ups|0}\n- Miles Hiked: %^{Rim to Rim Prep|0}\n"
         :empty-lines 1)
        ("q" "Save Quote" entry (file "~/quotes.org")
         "* %^{Source/Author}\n#+BEGIN_QUOTE\n%^{Quote}\n#+END_QUOTE\nCaptured: %U"
         :empty-lines 1)
        ("i" "Server Concept / FOSS Idea" entry (file "~/inbox.org")
         "* IDEA %^{Concept Title} :server:\n%^{Description}\n%U"
         :empty-lines 1)))

;; NOTIFICATIONS

(require 'cl-lib)

(cl-defun my/glasspane-notify (&key (id 1) title content ongoing chronometer base-time-ms button1-label button1-endpoint)
  "Construct and send a dynamic notification primitive to Android."
  (let* ((id-arg (format "--ei id %d " id))
         (title-arg (if title (format "-e title '%s' " title) ""))
         (content-arg (if content (format "-e content '%s' " content) ""))
         (ongoing-arg (if ongoing "--ez ongoing true " ""))
         (chrono-arg (if chronometer "--ez chronometer true " ""))
         (time-arg (if base-time-ms (format "--el base_time_ms %d " base-time-ms) ""))
         (b1-lbl-arg (if button1-label (format "-e button1_label '%s' " button1-label) ""))
         (b1-end-arg (if button1-endpoint (format "-e button1_endpoint '%s' " button1-endpoint) ""))

         ;; Compile the shell command
         (cmd (concat "am broadcast --user 0 -n 'com.example.glasspane/com.example.glasspane.GlasspaneApiReceiver' -a com.example.glasspane.api.NOTIFICATION "
                      id-arg title-arg content-arg ongoing-arg chrono-arg time-arg b1-lbl-arg b1-end-arg)))

    (start-process-shell-command "glasspane-notify" nil cmd)))

(defun my/glasspane-cancel-notification (id)
  "Cancel an active Android notification by ID."
  (start-process-shell-command "glasspane-cancel" nil
			       (format "am broadcast --user 0 -n 'com.example.glasspane/com.example.glasspane.GlasspaneApiReceiver' -a com.example.glasspane.api.CANCEL_NOTIFICATION --ei id %d" id)))

(cl-defun my/glasspane-dialog (&key method title hint values endpoint)
  "Launch a native Android dialog and route the answer to an HTTP endpoint."
  (let* ((method-arg (if method (format "--es input_method '%s' " method) "--es input_method 'text' "))
         (title-arg (if title (format "--es input_title '%s' " title) ""))
         (hint-arg (if hint (format "--es input_hint '%s' " hint) ""))
         (vals-arg (if values (format "--es input_values '%s' " values) ""))
         (end-arg (if endpoint (format "--es endpoint '%s' " endpoint) ""))

         ;; Compile the shell command (Note the 'am start' instead of 'am broadcast')
         (cmd (concat "am start --user 0 -n 'com.example.glasspane/com.example.glasspane.DialogActivity' "
                      method-arg title-arg hint-arg vals-arg end-arg)))

    (start-process-shell-command "glasspane-dialog" nil cmd)))

;; --- 5. GLASSPANE CONFIGURATION ---
(defcustom glasspane-org-dir "~/"
  "The base directory Glasspane will search for org files."
  :type 'string
  :group 'glasspane)

(defun my/glasspane-get-org-files ()
  "Return a list of all .org files in `glasspane-org-dir'."
  (directory-files-recursively (expand-file-name glasspane-org-dir) "\\.org$"))

(defun my/extract-query-string (key query)
  "Safely extract a query parameter and ensure it is a plain string."
  (let ((val (cdr (assoc key query))))
    (while (consp val)
      (setq val (car val)))
    val))

(defun my/glasspane-update-property (id property value)
  "Find the org node by ID and update PROPERTY to VALUE."
  (save-window-excursion
    (org-id-update-id-locations (my/glasspane-get-org-files))
    (let ((marker (org-id-find id t)))
      (if marker
          (progn
            (with-current-buffer (marker-buffer marker)
              (goto-char (marker-position marker))
              (org-entry-put (point) property value)
              (save-buffer))
            t)
        (message "Glasspane Error: Could not find node with ID %s" id)
        nil))))

;; --- 6. SDUI NODE PARSER ---
(defun my/glasspane-parse-node-at-point ()
  "Parse the heading at point into a Glasspane JSON Node."
  (let* ((title (org-get-heading t t t t))
         (status (or (org-entry-get (point) "STATUS") "No Status"))
         (id (or (org-id-get)
                 (progn (org-id-get-create) (save-buffer) (org-id-get))))
         (has-children (save-excursion
                         (let ((cur-level (org-outline-level)))
                           (outline-next-heading)
                           (> (org-outline-level) cur-level)))))
    `((type . "Node")
      (id . ,id)
      (has_children . ,(if has-children t :json-false))
      (elements . ,(vector
                    `((type . "Text") (value . ,title) (size . "Title"))
                    `((type . "Text") (value . ,(concat "Status: " status)) (size . "Body"))
                    `((type . "Button")
                      (label . "Clock In")
                      (action . ((method . "POST")
                                 (endpoint . "/glasspane-clock-in")
                                 (id . ,id)
                                 (require_input . :json-false))))
                    `((type . "Button")
                      (label . "Update Status")
                      (action . ((method . "POST")
                                 (endpoint . "/glasspane-update")
                                 (id . ,id)
                                 (prop . "STATUS")
                                 (require_input . t)
                                 (input_prompt . "Enter new status:")))))))))

(defun my/glasspane-get-view-elements (id)
  "Return the SDUI element vector for the given node ID."
  (let ((files (my/glasspane-get-org-files)))
    (cond
     ((or (null id) (string-empty-p id))
      (vconcat
       (mapcar (lambda (file)
                 `((type . "Node")
                   (id . ,(concat "file:" file))
                   (has_children . t)
                   (elements . ,(vector
                                 `((type . "Text")
                                   (value . ,(file-name-nondirectory file))
                                   (size . "Title"))))))
               files)))
     ((string-prefix-p "file:" id)
      (let* ((file (substring id 5))
             (elements (org-map-entries
                        (lambda () (my/glasspane-parse-node-at-point))
                        "LEVEL=1"
                        (list file))))
        (vconcat elements)))
     (t
      (let ((elements '())
            (marker (org-id-find id t)))
        (if (not marker)
            (message "Glasspane: Could not find node with ID %s" id)
          (with-current-buffer (marker-buffer marker)
            (org-with-point-at (marker-position marker)
              (let ((parent-level (org-outline-level))
                    (end (save-excursion (org-end-of-subtree t) (point))))
                (outline-next-heading)
                (while (and (< (point) end) (not (eobp)))
                  (when (= (org-outline-level) (1+ parent-level))
                    (push (my/glasspane-parse-node-at-point) elements))
                  (outline-next-heading))))))
        (vconcat (reverse elements)))))))

;; --- 7. HTTP ENDPOINTS ---
(defun httpd/glasspane-view (proc path query request)
  "Serve the lazy-loaded tree view."
  (let* ((id (my/extract-query-string "id" query))
         (elements (my/glasspane-get-view-elements id))
         (view-title (cond
                      ((or (null id) (string-empty-p id)) "Root Directory")
                      ((string-prefix-p "file:" id)
                       (file-name-nondirectory (substring id 5)))
                      (t "Sub-nodes")))
         (payload `((view_title . ,view-title)
                    (elements . ,elements))))
    (with-httpd-buffer proc "application/json"
      (insert (json-encode payload)))))
(defalias 'httpd/glasspane-view/ 'httpd/glasspane-view)

(defun httpd/glasspane-update (proc path query request)
  "Handle property updates."
  (let ((id   (my/extract-query-string "id"   query))
        (prop (my/extract-query-string "prop" query))
        (val  (my/extract-query-string "val"  query)))
    (if (and id prop val (my/glasspane-update-property id prop val))
        (with-httpd-buffer proc "application/json"
          (insert "{\"status\": \"success\"}"))
      (with-httpd-buffer proc "application/json"
        (insert "{\"status\": \"error\", \"message\": \"Update failed\"}")))))
(defalias 'httpd/glasspane-update/ 'httpd/glasspane-update)

(defun httpd/glasspane-capture-templates (proc path query request)
  "Serve parsed org-capture templates to Android."
  (with-httpd-buffer proc "application/json"
    (insert (json-encode (my/glasspane-get-capture-templates)))))
(defalias 'httpd/glasspane-capture-templates/ 'httpd/glasspane-capture-templates)

(defun httpd/glasspane-capture (proc path query request)
  "Execute an org-capture template headlessly using Android data."
  (let* ((id (my/extract-query-string "id" query))
         (original-tpl (assoc id org-capture-templates)))
    (if (not original-tpl)
        (with-httpd-buffer proc "application/json"
          (insert "{\"status\": \"error\", \"message\": \"Template not found\"}"))
      (condition-case err
          (let* ((type            (nth 2 original-tpl))
                 (target          (nth 3 original-tpl))
                 (template-string (nth 4 original-tpl))
                 (props           (nthcdr 5 original-tpl))
                 (modified-string template-string))
            (mapc (lambda (param)
                    (let* ((key (car param))
                           (val (my/extract-query-string key query)))
                      (when (and (stringp key) (stringp val) (not (equal key "id")))
                        (setq modified-string
                              (replace-regexp-in-string
                               (format "%%^{\\(%s\\)\\([|][^}]*\\)?}"
                                       (regexp-quote key))
                               val modified-string t t)))))
                  query)
            (setq props (plist-put props :immediate-finish t))
            (let* ((headless-tpl
                    (append (list id (nth 1 original-tpl) type target modified-string)
                            props))
                   (org-capture-templates (list headless-tpl)))
              (save-window-excursion (org-capture nil id)))
            (with-httpd-buffer proc "application/json"
              (insert "{\"status\": \"success\"}")))
        (error
         (with-httpd-buffer proc "application/json"
           (insert (json-encode `((status . "error")
                                  (message . ,(error-message-string err)))))))))))
(defalias 'httpd/glasspane-capture/ 'httpd/glasspane-capture)

;; --- 8. CLOCK ENDPOINTS ---
(defun my/glasspane-clock-in-id (id)
  "Find the node by ID and start org-clock."
  (save-window-excursion
    (let ((marker (org-id-find id t)))
      (if marker
          (progn
            (with-current-buffer (marker-buffer marker)
              (goto-char (marker-position marker))
              (org-clock-in))
            t)
        nil))))

(defun httpd/glasspane-clock-in (proc path query request)
  (let ((id (my/extract-query-string "id" query)))
    (if (and id (my/glasspane-clock-in-id id))
        (with-httpd-buffer proc "application/json"
          (insert "{\"status\": \"success\"}"))
      (with-httpd-buffer proc "application/json"
        (insert "{\"status\": \"error\"}")))))
(defalias 'httpd/glasspane-clock-in/ 'httpd/glasspane-clock-in)

(defun httpd/glasspane-clock-out (proc path query request)
  (if (org-clock-is-active)
      (progn
        (org-clock-out)
        (with-httpd-buffer proc "application/json"
          (insert "{\"status\": \"success\"}")))
    (with-httpd-buffer proc "application/json"
      (insert "{\"status\": \"error\", \"message\": \"No active clock\"}"))))
(defalias 'httpd/glasspane-clock-out/ 'httpd/glasspane-clock-out)

(defun httpd/glasspane-clock-status (proc path query request)
  "Return the org-id of the currently clocked-in heading, or empty string."
  (let ((active-id
         (if (org-clock-is-active)
             (org-with-point-at org-clock-marker
               (or (org-id-get) ""))
           "")))
    (with-httpd-buffer proc "application/json"
      (insert (json-encode `((active_id . ,active-id)))))))
(defalias 'httpd/glasspane-clock-status/ 'httpd/glasspane-clock-status)

;; --- 9. CLOCK HOOKS ---
;; These are the ONLY clock hooks. The old ChronoCast hooks
;; (my-chronocast-start / my-chronocast-stop) are intentionally absent.
(defun my/glasspane-notify-clock-in ()
  "Broadcast an ongoing chronometer notification when org-clock starts."
  (when (and (boundp 'org-clock-current-task) org-clock-current-task)
    (let* ((title (replace-regexp-in-string "'" "" org-clock-current-task))
           (time-sec (float-time org-clock-start-time))
           (time-ms (truncate (* time-sec 1000))))

      (my/glasspane-notify
       :id 42
       :title title
       :content "Clocked In"
       :ongoing t
       :chronometer t
       :base-time-ms time-ms
       :button1-label "Clock Out"
       :button1-endpoint "/glasspane-clock-out"))))

(defun my/glasspane-notify-clock-out ()
  "Cancel the Chronometer notification when org-clock stops."
  (my/glasspane-cancel-notification 42))

(defun my/log-timestamped-seconds-on-clock-out ()
  "Append elapsed seconds with a date stamp to the DURATION_HISTORY property."
  (when (and (boundp 'org-clock-start-time) org-clock-start-time)
    (let* ((elapsed-seconds (round (float-time (time-since org-clock-start-time))))
           (date-stamp (format-time-string "%Y-%m-%d"))
           (val-string (format "%s=%d" date-stamp elapsed-seconds)))
      (org-entry-add-to-multivalued-property nil "DURATION_HISTORY" val-string))))

(add-hook 'org-clock-in-hook  #'my/glasspane-notify-clock-in)
(add-hook 'org-clock-out-hook #'my/glasspane-notify-clock-out)
(add-hook 'org-clock-out-hook #'my/log-timestamped-seconds-on-clock-out)

;; Vibrate API

(defun glasspane-api-vibrate (&optional duration-ms)
  "Trigger the Android device to vibrate via Glasspane API."
  (interactive "nDuration (ms): ")
  (let ((dur (or duration-ms 500)))
    (start-process-shell-command "glasspane-vibrate" nil
     (format "am broadcast --user 0 -n 'com.example.glasspane/com.example.glasspane.GlasspaneApiReceiver' -a com.example.glasspane.api.VIBRATE --ei duration_ms %d" dur))))

(defun glasspane-api-toast (text)
  "Show a native Android toast notification."
  (interactive "sToast message: ")
  (start-process-shell-command "glasspane-toast" nil
   (format "am broadcast --user 0 -n 'com.example.glasspane/com.example.glasspane.GlasspaneApiReceiver' -a com.example.glasspane.api.TOAST -e text '%s'" text)))

;; --- 10. CAPTURE TEMPLATE PARSER ---
(defun my/glasspane-get-capture-templates ()
  "Parse `org-capture-templates' into Glasspane JSON."
  (let ((glasspane-templates '()))
    (dolist (tpl org-capture-templates)
      (let* ((key (nth 0 tpl))
             (desc (nth 1 tpl))
             (raw-template (nth 4 tpl))
             (template-string
              (cond
               ((stringp raw-template) raw-template)
               ((and (listp raw-template) (eq (car raw-template) 'file))
                (with-temp-buffer
                  (insert-file-contents (expand-file-name (cadr raw-template)))
                  (buffer-string)))
               (t nil))))
        (when (and (stringp key) (stringp desc) (stringp template-string))
          (let ((fields '())
                (start 0))
            (while (string-match "%^{\\([^}|]+\\)\\([|][^}]*\\)?}"
                                 template-string start)
              (let ((prompt (match-string 1 template-string)))
                (unless (seq-find
                         (lambda (f) (equal (cdr (assoc 'key f)) prompt))
                         fields)
                  (push `((key . ,prompt) (label . ,prompt) (hint . "")) fields)))
              (setq start (match-end 0)))
            (push `((id     . ,key)
                    (title  . ,desc)
                    (endpoint . "/glasspane-capture")
                    (fields . ,(vconcat (reverse fields))))
                  glasspane-templates)))))
    (vconcat (reverse glasspane-templates))))

;; --- 11. START HTTP SERVER ---
(httpd-start)
