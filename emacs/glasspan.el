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
         (title-arg (if title (format "-e title '%s' " (shell-quote-argument title)) ""))
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
         ;; FIX: (shell-quote-argument title) is now correctly wrapped!
         (title-arg (if title (format "--es input_title '%s' " (shell-quote-argument title)) ""))
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

(defun glasspane-get-org-files ()
  "Return a list of all .org files in `glasspane-org-dir'."
  (directory-files-recursively (expand-file-name glasspane-org-dir) "\\.org$"))

(defvar glasspane-config-file (expand-file-name "glasspane-config.json" user-emacs-directory)
  "Path to the Glasspane JSON configuration file.")

(defun glasspane--load-config ()
  "Load glasspane config from JSON and apply to org variables."
  (when (file-exists-p glasspane-config-file)
    (condition-case err
        (let* ((json-object-type 'alist)
               (json-array-type 'list)
               (json-key-type 'string)
               (config (json-read-file glasspane-config-file))
               (templates (cdr (assoc "capture_templates" config)))
               (tags (cdr (assoc "tags" config)))
               (todos (cdr (assoc "todo_keywords" config))))
               
          (when (and templates (listp templates))
            (setq org-capture-templates
                  (mapcar (lambda (tmpl)
                            (list (cdr (assoc "id" tmpl))
                                  (cdr (assoc "title" tmpl))
                                  'entry
                                  (list 'file (cdr (assoc "file" tmpl)))
                                  (cdr (assoc "content" tmpl))
                                  :empty-lines 1))
                          templates)))
                          
          (when (and tags (vectorp tags))
            (setq org-tag-alist (mapcar (lambda (t-str) (cons t-str nil)) (append tags nil))))
            
          (when (and todos (vectorp todos))
            (setq org-todo-keywords `((sequence ,@(append todos nil))))))
      (error (message "Glasspane: Error loading config JSON: %s" (error-message-string err))))))

;; Load it at boot
(glasspane--load-config)

;; Build the ID location database once at load time, not per-request.
(org-id-update-id-locations (glasspane-get-org-files))

(defun glasspane--extract-query (key query)
  "Safely extract a query parameter and ensure it is a plain string."
  (let ((val (cdr (assoc key query))))
    (while (consp val)
      (setq val (car val)))
    val))

;; --- 5b. RESPONSE HELPERS ---
(defun glasspane--json-success (proc &optional extra-alist)
  "Write a JSON success response to PROC.
  EXTRA-ALIST is merged into the response if non-nil."
  (with-httpd-buffer proc "application/json"
    (insert (json-encode (append '((status . "success")) (or extra-alist '()))))))

(defun glasspane--json-error (proc message)
  "Write a JSON error response to PROC."
  (with-httpd-buffer proc "application/json"
    (insert (json-encode `((status . "error") (message . ,message))))))

;; --- 5c. NODE-OPERATION MACRO ---
(defmacro with-glasspane-node (proc id-expr &rest body)
  "Find the org node by ID-EXPR, execute BODY at that point.
Inside BODY, `marker' is bound to the node's marker.
Automatically handles error wrapping and save-buffer.
If the node is not found, sends a JSON error to PROC."
  (declare (indent 2))
  `(condition-case err
       (save-window-excursion
         (let ((marker (org-id-find ,id-expr t)))
           (if marker
               (with-current-buffer (marker-buffer marker)
                 (goto-char (marker-position marker))
                 ,@body
                 (save-buffer))
             (glasspane--json-error ,proc "Node not found"))))
     (error
      (glasspane--json-error ,proc (error-message-string err)))))

(defun glasspane-update-property (id property value)
  "Find the org node by ID and update PROPERTY to VALUE."
  (save-window-excursion
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

;; --- 5d. CONTENT HELPERS ---
(defun glasspane--get-clean-entry-text ()
  "Extract the body text of the current node, excluding drawers."
  (let ((end (save-excursion (outline-next-heading) (point)))
        (text ""))
    (save-excursion
      (forward-line 1)
      (while (< (point) end)
        (cond
         ((looking-at-p "^[ \t]*:[a-zA-Z0-9_]+:")
          (if (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
              (forward-line 1)
            (forward-line 1)))
         ((looking-at-p "^[ \t]*#\\+BEGIN_LOGBOOK")
          (if (re-search-forward "^[ \t]*#\\+END_LOGBOOK[ \t]*$" end t)
              (forward-line 1)
            (forward-line 1)))
         ((looking-at-p "^[ \t]*CLOCK:") 
          (forward-line 1))
         (t
          (setq text (concat text (buffer-substring-no-properties (point) (line-beginning-position 2))))
          (forward-line 1)))))
    (string-trim text)))

(defun glasspane--get-custom-properties ()
  "Return an alist of properties excluding the standard ones."
  (let ((all-props (org-entry-properties nil 'standard))
        (ignored '("ITEM" "TODO" "PRIORITY" "TAGS" "ALLTAGS" "FILE" "CATEGORY" "BLOCKED" "CLOSED" "DEADLINE" "SCHEDULED" "EFFORT"))
        (custom '()))
    (dolist (prop all-props)
      (unless (member (car prop) ignored)
        (push `((key . ,(car prop)) (value . ,(cdr prop))) custom)))
    (vconcat (reverse custom))))

(defun glasspane-update-body-text (val)
  "Update the body text of the entry at point."
  (forward-line 1)
  (let ((end (save-excursion (outline-next-heading) (point)))
        (insertion-point nil))
    (while (and (< (point) end) (not insertion-point))
      (cond
       ((looking-at-p "^[ \t]*:[a-zA-Z0-9_]+:")
        (if (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
            (forward-line 1)
          (forward-line 1)))
       ((looking-at-p "^[ \t]*#\\+BEGIN_LOGBOOK")
        (if (re-search-forward "^[ \t]*#\\+END_LOGBOOK[ \t]*$" end t)
            (forward-line 1)
          (forward-line 1)))
       ((looking-at-p "^[ \t]*CLOCK:") 
        (forward-line 1))
       (t
        (setq insertion-point (point)))))
    (if insertion-point
        (progn
          (delete-region insertion-point end)
          (goto-char insertion-point)
          (when (not (string-empty-p val))
            (insert val "\n")))
      (goto-char end)
      (when (not (string-empty-p val))
        (insert val "\n")))))

;; --- 6. SDUI NODE PARSER ---
(defun my/glasspane-parse-node-at-point ()
  "Parse the heading at point into a rich Glasspane JSON Node.
  Includes tags, priority, TODO state, timestamps, level, and effort."
  (let* ((title (org-get-heading t t t t))
         (todo-state (org-get-todo-state))
         (priority (org-entry-get (point) "PRIORITY"))
         (tags (org-get-tags nil t))  ;; local tags only, no inherited
         (all-tags (org-get-tags))    ;; includes inherited
         (level (org-outline-level))
         (scheduled (org-entry-get (point) "SCHEDULED"))
         (deadline (org-entry-get (point) "DEADLINE"))
         (closed (org-entry-get (point) "CLOSED"))
         (effort (org-entry-get (point) "Effort"))
         (id (or (org-id-get)
                 (progn (org-id-get-create) (org-id-get))))
         (custom-props (glasspane--get-custom-properties))
         (body-text (glasspane--get-clean-entry-text))
         (has-children (save-excursion
                         (let ((cur-level (org-outline-level)))
                           (outline-next-heading)
                           (and (not (eobp))
                                (> (org-outline-level) cur-level))))))
    `((type . "Node")
      (id . ,id)
      (has_children . ,(if has-children t :json-false))
      (level . ,level)
      (todo . ,(or todo-state ""))
      (priority . ,(or priority ""))
      (tags . ,(vconcat (or tags '())))
      (all_tags . ,(vconcat (or all-tags '())))
      (scheduled . ,(or scheduled ""))
      (deadline . ,(or deadline ""))
      (closed . ,(or closed ""))
      (effort . ,(or effort ""))
      (elements . ,(vconcat
                    (list `((type . "Text") (value . ,title) (size . "Title")))
                    (if (> (length custom-props) 0)
                        (list `((type . "PropertyDrawer")
                                (properties . ,custom-props)
                                (action . ((endpoint . "/glasspane-update") (id . ,id)))))
                      '())
                    (list `((type . "EditableText")
                            (value . ,body-text)
                            (action . ((endpoint . "/glasspane-update-body") (id . ,id))))))))))

(defun glasspane-get-view-elements (id)
  "Return the SDUI element vector for the given node ID."
  (let ((files (glasspane-get-org-files)))
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
  (let* ((id (glasspane--extract-query "id" query))
         (elements (glasspane-get-view-elements id))
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
  (let ((id   (glasspane--extract-query "id"   query))
        (prop (glasspane--extract-query "prop" query))
        (val  (glasspane--extract-query "val"  query)))
    (if (and id prop val (glasspane-update-property id prop val))
        (glasspane--json-success proc)
      (glasspane--json-error proc "Update failed"))))
(defalias 'httpd/glasspane-update/ 'httpd/glasspane-update)

(defun httpd/glasspane-update-body (proc path query request)
  "Update the body text of a node."
  (let ((id (glasspane--extract-query "id" query))
        (val (glasspane--extract-query "val" query)))
    (if id
        (with-glasspane-node proc id
          (glasspane-update-body-text (or val ""))
          (glasspane--json-success proc))
      (glasspane--json-error proc "Missing id"))))
(defalias 'httpd/glasspane-update-body/ 'httpd/glasspane-update-body)

(defun httpd/glasspane-update-title (proc path query request)
  "Update the title/headline of a node."
  (let ((id (glasspane--extract-query "id" query))
        (val (glasspane--extract-query "val" query)))
    (if (or (null id) (null val))
        (glasspane--json-error proc "Missing id or val")
      (with-glasspane-node proc id
        (org-back-to-heading t)
        (org-edit-headline val)
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-update-title/ 'httpd/glasspane-update-title)

(defun httpd/glasspane-capture-templates (proc path query request)
  "Serve parsed org-capture templates to Android."
  (with-httpd-buffer proc "application/json"
    (insert (json-encode (glasspane-get-capture-templates)))))
(defalias 'httpd/glasspane-capture-templates/ 'httpd/glasspane-capture-templates)

(defun httpd/glasspane-capture (proc path query request)
  "Accept capture data from Android, queue it, and release the HTTP connection immediately."
  (push query glasspane-task-queue)
  (glasspane--json-success proc '((status . "queued"))))
(defalias 'httpd/glasspane-capture/ 'httpd/glasspane-capture)

(defun glasspane--seed-capture-templates ()
  "Convert the global org-capture-templates into the JSON format."
  (let ((items '()))
    (dolist (tpl org-capture-templates)
      (let* ((key (nth 0 tpl))
             (desc (nth 1 tpl))
             (file-expr (nth 3 tpl))
             (file (if (and (listp file-expr) (eq (car file-expr) 'file))
                       (cadr file-expr)
                     ""))
             (content (nth 4 tpl)))
        (when (stringp content)
          (push `((id . ,key)
                  (title . ,desc)
                  (file . ,file)
                  (content . ,content))
                items))))
    (vconcat (reverse items))))

(defun glasspane--seed-tags ()
  "Convert the global org-tag-alist into an array of strings."
  (let ((tags '()))
    (dolist (item org-tag-alist)
      (when (and (consp item) (stringp (car item)))
        (push (car item) tags)))
    (if tags (vconcat (reverse tags)) [])))

(defun glasspane--seed-todos ()
  "Extract the first todo sequence into an array of strings."
  (if org-todo-keywords
      (let* ((seq (car org-todo-keywords))
             (items (cdr seq)))
        (vconcat items))
    ["TODO" "|" "DONE"]))

(defun httpd/glasspane-config-get (proc path query request)
  "Return the current configuration JSON.
  If glasspane-config.json does not exist, seeds it dynamically from org-capture-templates."
  (let ((config (if (file-exists-p glasspane-config-file)
                    (let* ((json-object-type 'alist)
                           (json-array-type 'vector)
                           (json-key-type 'string))
                      (json-read-file glasspane-config-file))
                  `((capture_templates . ,(glasspane--seed-capture-templates))
                    (tags . ,(glasspane--seed-tags))
                    (todo_keywords . ,(glasspane--seed-todos))))))
    (with-httpd-buffer proc "application/json"
      (insert (json-encode config)))))
(defalias 'httpd/glasspane-config-get/ 'httpd/glasspane-config-get)

(defun httpd/glasspane-config-set (proc path query request)
  "Save the configuration JSON payload and reload it into Emacs."
  (let ((payload (glasspane--extract-query "payload" query)))
    (if payload
        (unwind-protect
            (progn
              (with-temp-file glasspane-config-file
                (insert payload))
              (glasspane--load-config)
              (glasspane--json-success proc))
          (error (glasspane--json-error proc "Could not save config")))
      (glasspane--json-error proc "Missing payload"))))
(defalias 'httpd/glasspane-config-set/ 'httpd/glasspane-config-set)

;; --- 7b. TODO STATE DISCOVERY ---
(defun glasspane-get-todo-keywords ()
  "Return the full TODO keyword configuration.
  Discovers from `org-todo-keywords' (global), or per-file #+TODO lines.
  Returns a list of sequences, each a list of states with type markers."
  (let ((result '()))
    (dolist (seq (or org-todo-keywords '((sequence "TODO" "|" "DONE"))))
      (let ((states '())
            (done-found nil)
            (items (cdr seq)))  ;; skip the 'sequence or 'type symbol
        (dolist (kw items)
          (cond
           ((equal kw "|")
            (setq done-found t))
           (t
            ;; Strip fast-select key in parens, e.g. "TODO(t)" -> "TODO"
            (let ((clean (if (string-match "^\\([^(]+\\)" kw)
                            (match-string 1 kw)
                          kw)))
              (push `((state . ,clean)
                      (type . ,(if done-found "done" "active")))
                    states)))))
        ;; If no | separator was found, last state is done by convention
        (unless done-found
          (when states
            (setf (cdr (assoc 'type (car states))) "done")))
        (push `((sequence . ,(vconcat (reverse states)))) result)))
    (vconcat (reverse result))))

(defun httpd/glasspane-todo-keywords (proc path query request)
  "Serve the active TODO keyword sequences to Android."
  (with-httpd-buffer proc "application/json"
    (insert (json-encode `((keywords . ,(glasspane-get-todo-keywords)))))))
(defalias 'httpd/glasspane-todo-keywords/ 'httpd/glasspane-todo-keywords)

;; --- 7c. AGENDA ENDPOINT ---
(defun glasspane-format-agenda-item (marker)
  "Format a single agenda item from MARKER into a JSON-friendly alist."
  (when (and marker (marker-buffer marker))
    (with-current-buffer (marker-buffer marker)
      (org-with-point-at marker
        (let* ((title (org-get-heading t t t t))
               (todo-state (org-get-todo-state))
               (priority (org-entry-get (point) "PRIORITY"))
               (tags (org-get-tags nil t))
               (scheduled (org-entry-get (point) "SCHEDULED"))
               (deadline (org-entry-get (point) "DEADLINE"))
               (effort (org-entry-get (point) "Effort"))
               (id (or (org-id-get)
                       (progn (org-id-get-create) (org-id-get))))
               (category (org-entry-get (point) "CATEGORY"))
               (file (buffer-file-name)))
          `((id . ,id)
            (title . ,title)
            (todo . ,(or todo-state ""))
            (priority . ,(or priority ""))
            (tags . ,(vconcat (or tags '())))
            (scheduled . ,(or scheduled ""))
            (deadline . ,(or deadline ""))
            (effort . ,(or effort ""))
            (category . ,(or category ""))
            (file . ,(or file ""))))))))

(defun glasspane-get-agenda (span num-days)
  "Return agenda items for SPAN days starting from today."
  (let* ((today (current-time))
         (end-date (time-add today (days-to-time num-days)))
         (today-str (format-time-string "%Y-%m-%d" today))
         (end-date-str (format-time-string "%Y-%m-%d" end-date))
         (items '()))
    ;; Scheduled items
    (dolist (file (org-agenda-files))
      (when (file-exists-p file)
        (with-current-buffer (find-file-noselect file)
          (org-map-entries
           (lambda ()
             (let* ((scheduled (org-entry-get (point) "SCHEDULED"))
                    (deadline (org-entry-get (point) "DEADLINE"))
                    (todo-state (org-get-todo-state))
                    (parsed nil))
               ;; Include if it has a scheduled date or deadline
               (when (or scheduled deadline)
                 (setq parsed (glasspane-format-agenda-item (point-marker)))
                 (when parsed
                   (let* ((date-str (or scheduled deadline))
                          (effective-date
                           (if (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" date-str)
                               (match-string 1 date-str)
                             today-str))
                          (item-type (cond
                                     (deadline "deadline")
                                     (scheduled "scheduled")
                                     (t "timestamp"))))
                     ;; Only include if effective date is <= end date
                     (when (not (string< end-date-str effective-date))
                       (push (append parsed
                                     `((effective_date . ,effective-date)
                                       (item_type . ,item-type)))
                             items)))))))
           nil
           nil))))
    ;; Sort by effective date
    (setq items (sort items
                      (lambda (a b)
                        (string< (cdr (assoc 'effective_date a))
                                 (cdr (assoc 'effective_date b))))))
    ;; Group by date
    (let ((grouped '())
          (current-date nil)
          (current-group '()))
      (dolist (item items)
        (let ((date (cdr (assoc 'effective_date item))))
          (if (equal date current-date)
              (push item current-group)
            (when current-date
              (push `((date . ,current-date)
                      (items . ,(vconcat (reverse current-group))))
                    grouped))
            (setq current-date date
                  current-group (list item)))))
      (when current-date
        (push `((date . ,current-date)
                (items . ,(vconcat (reverse current-group))))
              grouped))
      (vconcat (reverse grouped)))))

(defun httpd/glasspane-agenda (proc path query request)
  "Serve the agenda view to Android.
  Query params: span=day|week|month, days=N (default 7)"
  (let* ((span (or (glasspane--extract-query "span" query) "week"))
         (num-days (cond
                    ((equal span "day") 1)
                    ((equal span "month") 30)
                    (t 7)))
         (days-param (glasspane--extract-query "days" query))
         (num-days (if days-param (string-to-number days-param) num-days))
         (agenda-data (glasspane-get-agenda span num-days))
         (keywords (glasspane-get-todo-keywords)))
    (with-httpd-buffer proc "application/json"
      (insert (json-encode `((span . ,span)
                             (num_days . ,num-days)
                             (todo_keywords . ,keywords)
                             (groups . ,agenda-data)))))))
(defalias 'httpd/glasspane-agenda/ 'httpd/glasspane-agenda)

;; --- 7d. SEARCH ENDPOINT (org-ql) ---
(defun httpd/glasspane-search (proc path query request)
  "Search org files using org-ql. Query param: q=sexp-or-string"
  (let* ((q (glasspane--extract-query "q" query))
         (results '()))
    (if (or (null q) (string-empty-p q))
        (glasspane--json-error proc "Missing q parameter")
      (condition-case err
          (let* ((query-sexp (condition-case nil
                                 (read q)
                               (error `(regexp ,q))))
                 (markers (org-ql-select
                            (org-agenda-files)
                            query-sexp
                            :action (lambda () (point-marker)))))
            (dolist (m markers)
              (let ((parsed (glasspane-format-agenda-item m)))
                (when parsed
                  (push parsed results))))
            (with-httpd-buffer proc "application/json"
              (insert (json-encode `((results . ,(vconcat (reverse results))))))))
        (error
         (glasspane--json-error proc (error-message-string err)))))))
(defalias 'httpd/glasspane-search/ 'httpd/glasspane-search)

;; --- 7e. REFILE ENDPOINT ---
(defun httpd/glasspane-refile (proc path query request)
  "Refile a node to a new target.
  Query params: id=source-node-id, target=target-node-id"
  (let* ((id (glasspane--extract-query "id" query))
         (target-id (glasspane--extract-query "target" query)))
    (if (or (null id) (null target-id))
        (glasspane--json-error proc "Missing id or target")
      (condition-case err
          (save-window-excursion
            (let ((source-marker (org-id-find id t))
                  (target-marker (org-id-find target-id t)))
              (if (and source-marker target-marker)
                  (progn
                    (with-current-buffer (marker-buffer source-marker)
                      (goto-char (marker-position source-marker))
                      (let ((org-refile-targets
                             `((nil :maxlevel . 9))))
                        (org-refile nil nil
                                   (list
                                    (org-with-point-at target-marker
                                      (org-get-heading t t t t))
                                    (buffer-file-name (marker-buffer target-marker))
                                    nil
                                    (marker-position target-marker)))))
                    (glasspane--json-success proc))
                (glasspane--json-error proc "Could not find source or target node"))))
        (error
         (glasspane--json-error proc (error-message-string err)))))))
(defalias 'httpd/glasspane-refile/ 'httpd/glasspane-refile)

;; --- 7f. ARCHIVE ENDPOINT ---
(defun httpd/glasspane-archive (proc path query request)
  "Archive a subtree by ID. Query params: id=node-id"
  (let ((id (glasspane--extract-query "id" query)))
    (if (null id)
        (glasspane--json-error proc "Missing id")
      (with-glasspane-node proc id
        (org-archive-subtree)
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-archive/ 'httpd/glasspane-archive)

;; --- 7f2. TREE EDIT ENDPOINT ---
(defun httpd/glasspane-tree-edit (proc path query request)
  "Edit tree structure. Query params: id, action (move-up, move-down, promote, demote, insert-child, insert-sibling), title"
  (let ((id (glasspane--extract-query "id" query))
        (action (glasspane--extract-query "action" query))
        (title (glasspane--extract-query "title" query)))
    (if (null id)
        (glasspane--json-error proc "Missing id")
      (with-glasspane-node proc id
        (pcase action
          ("move-up" (org-move-subtree-up))
          ("move-down" (org-move-subtree-down))
          ("promote" (org-do-promote))
          ("demote" (org-do-demote))
          ("insert-sibling"
           (org-insert-heading-after-current)
           (insert (or title "New Node"))
           (org-id-get-create))
          ("insert-child"
           (org-insert-heading-respect-content)
           (org-do-demote)
           (insert (or title "New Subnode"))
           (org-id-get-create)))
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-tree-edit/ 'httpd/glasspane-tree-edit)

;; --- 7g. SET TODO STATE ---
(defun httpd/glasspane-set-todo (proc path query request)
  "Set or cycle the TODO state of a node.
  Query params: id=node-id, state=new-state (or state=cycle)"
  (let ((id (glasspane--extract-query "id" query))
        (new-state (glasspane--extract-query "state" query)))
    (if (or (null id) (null new-state))
        (glasspane--json-error proc "Missing id or state")
      (with-glasspane-node proc id
        (if (equal new-state "cycle")
            (org-todo)
          (org-todo new-state))
        (let ((resulting-state (or (org-get-todo-state) "")))
          (glasspane--json-success proc `((new_state . ,resulting-state))))))))
(defalias 'httpd/glasspane-set-todo/ 'httpd/glasspane-set-todo)

;; --- 7h. SET TAGS ---
(defun httpd/glasspane-set-tags (proc path query request)
  "Set tags on a node.
  Query params: id=node-id, tags=:tag1:tag2: (org-style tag string)"
  (let ((id (glasspane--extract-query "id" query))
        (tags-str (glasspane--extract-query "tags" query)))
    (if (or (null id) (null tags-str))
        (glasspane--json-error proc "Missing id or tags")
      (with-glasspane-node proc id
        (org-set-tags tags-str)
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-set-tags/ 'httpd/glasspane-set-tags)

;; --- 7i. SET PRIORITY ---
(defun httpd/glasspane-set-priority (proc path query request)
  "Set priority on a node.
  Query params: id=node-id, priority=A|B|C|space (space to remove)"
  (let ((id (glasspane--extract-query "id" query))
        (pri (glasspane--extract-query "priority" query)))
    (if (or (null id) (null pri))
        (glasspane--json-error proc "Missing id or priority")
      (with-glasspane-node proc id
        (org-priority (if (equal pri " ") ?\ (string-to-char pri)))
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-set-priority/ 'httpd/glasspane-set-priority)

;; --- 7j. SCHEDULE / DEADLINE ---
(defun httpd/glasspane-schedule (proc path query request)
  "Set SCHEDULED or DEADLINE timestamp on a node.
  Query params: id=node-id, type=scheduled|deadline, date=YYYY-MM-DD, repeater=+1w|.+1d|etc, remove=true"
  (let ((id (glasspane--extract-query "id" query))
        (ts-type (or (glasspane--extract-query "type" query) "scheduled"))
        (date (glasspane--extract-query "date" query))
        (repeater (glasspane--extract-query "repeater" query))
        (remove (glasspane--extract-query "remove" query)))
    (if (null id)
        (glasspane--json-error proc "Missing id")
      (with-glasspane-node proc id
        (if (equal remove "true")
            (if (equal ts-type "deadline")
                (org-deadline '(4))
              (org-schedule '(4)))
          (let ((ts-string (concat "<" date
                                  (if repeater (concat " " repeater) "")
                                  ">")))
            (if (equal ts-type "deadline")
                (org-deadline nil ts-string)
              (org-schedule nil ts-string))))
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-schedule/ 'httpd/glasspane-schedule)

;; --- 7k. CLOCK REPORT ---
(defun httpd/glasspane-clock-report (proc path query request)
  "Return structured clock data for a scope.
  Query params: id=node-id (optional), range=today|week|month|all (default week)"
  (let* ((id (glasspane--extract-query "id" query))
         (range (or (glasspane--extract-query "range" query) "week"))
         (results '()))
    (condition-case err
        (progn
          (let ((files (if id nil (org-agenda-files))))
            (if id
                (let ((marker (org-id-find id t)))
                  (when marker
                    (with-current-buffer (marker-buffer marker)
                      (org-with-point-at marker
                        (let ((minutes (org-clock-sum-current-item)))
                          (push `((id . ,id)
                                  (title . ,(org-get-heading t t t t))
                                  (total_minutes . ,(or minutes 0)))
                                results))))))
              (dolist (file files)
                (when (file-exists-p file)
                  (with-current-buffer (find-file-noselect file)
                    (org-clock-sum)
                    (org-map-entries
                     (lambda ()
                       (let ((clocked (get-text-property (point) :org-clock-minutes)))
                         (when (and clocked (> clocked 0))
                           (push `((id . ,(or (org-id-get) ""))
                                   (title . ,(org-get-heading t t t t))
                                   (total_minutes . ,clocked)
                                   (file . ,(file-name-nondirectory file)))
                                 results))))
                     "LEVEL=1"
                     nil))))))
          (with-httpd-buffer proc "application/json"
            (insert (json-encode `((range . ,range)
                                   (entries . ,(vconcat (reverse results))))))))
      (error
       (glasspane--json-error proc (error-message-string err))))))
(defalias 'httpd/glasspane-clock-report/ 'httpd/glasspane-clock-report)

;; --- 7l. HABITS ENDPOINT ---
(defun httpd/glasspane-habits (proc path query request)
  "Return habit items with their consistency data.
  Habit items are TODOs with a STYLE=habit property and a repeating SCHEDULED."
  (let ((results '()))
    (condition-case err
        (progn
          (dolist (file (org-agenda-files))
            (when (file-exists-p file)
              (with-current-buffer (find-file-noselect file)
                (org-map-entries
                 (lambda ()
                   (when (equal (org-entry-get (point) "STYLE") "habit")
                     (let* ((title (org-get-heading t t t t))
                            (id (or (org-id-get)
                                    (progn (org-id-get-create) (org-id-get))))
                            (scheduled (org-entry-get (point) "SCHEDULED"))
                            (last-done (org-entry-get (point) "LAST_REPEAT"))
                            (hist (org-entry-get-multivalued-property (point) "DURATION_HISTORY")))
                       (push `((id . ,id)
                               (title . ,title)
                               (scheduled . ,(or scheduled ""))
                               (last_done . ,(or last-done ""))
                               (history . ,(vconcat (or hist '()))))
                             results))))
                 nil
                 nil))))
          (with-httpd-buffer proc "application/json"
            (insert (json-encode `((habits . ,(vconcat (reverse results))))))))
      (error
       (glasspane--json-error proc (error-message-string err))))))
(defalias 'httpd/glasspane-habits/ 'httpd/glasspane-habits)

;; --- 8. CLOCK ENDPOINTS ---
(defun glasspane-clock-in-id (id)
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
  (let ((id (glasspane--extract-query "id" query)))
    (if (and id (glasspane-clock-in-id id))
        (glasspane--json-success proc)
      (glasspane--json-error proc "Clock-in failed"))))
(defalias 'httpd/glasspane-clock-in/ 'httpd/glasspane-clock-in)

(defun httpd/glasspane-clock-out (proc path query request)
  (if (org-clock-is-active)
      (progn
        (org-clock-out)
        (glasspane--json-success proc))
    (glasspane--json-error proc "No active clock")))
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
   (format "am broadcast --user 0 -n 'com.example.glasspane/com.example.glasspane.GlasspaneApiReceiver' -a com.example.glasspane.api.TOAST -e text '%s'" (shell-quote-argument text))))

;; --- 10. CAPTURE TEMPLATE PARSER ---
(defun glasspane-get-capture-templates ()
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

;; =============================================================================
;; --- 12. ASYNC TASK QUEUE ---
;; =============================================================================

(defvar glasspane-task-queue '()
  "A list of pending tasks received from Android.")

(defun glasspane-process-queue ()
  "Process one item from `glasspane-task-queue' while Emacs is idle."
  (when glasspane-task-queue
    ;; Pop the oldest task off the queue (FIFO)
    (let* ((task-query (car (last glasspane-task-queue)))
           (id (my/extract-query-string "id" task-query))
           (original-tpl (assoc id org-capture-templates)))
      (setq glasspane-task-queue (butlast glasspane-task-queue))
      (if (not original-tpl)
          (message "Glasspane Async Error: Template '%s' not found" id)
        (condition-case err
            (let* ((type            (nth 2 original-tpl))
                   (target          (nth 3 original-tpl))
                   (template-string (nth 4 original-tpl))
                   (props           (nthcdr 5 original-tpl))
                   (modified-string template-string))
              ;; Run the parameter mapping
              (mapc (lambda (param)
                      (let* ((key (car param))
                             (val (glasspane--extract-query key task-query)))
                        (when (and (stringp key) (stringp val) (not (equal key "id")))
                          (setq modified-string
                                (replace-regexp-in-string
                                 (format "%%^{\\(%s\\)\\([|][^}]*\\)?}"
                                         (regexp-quote key))
                                 val modified-string t t)))))
                    task-query)
              ;; Force immediate finish so it doesn't open a buffer
              (setq props (plist-put props :immediate-finish t))
              (let* ((headless-tpl
                      (append (list id (nth 1 original-tpl) type target modified-string)
                              props))
                     (org-capture-templates (list headless-tpl)))
                ;; Execute the capture
                (save-window-excursion (org-capture nil id)))
              (message "Glasspane: Successfully processed background capture for template '%s'" id))
          ;; Handle any errors gracefully without crashing the timer loop
          (error
           (message "Glasspane Background Error: %s" (error-message-string err))))))))

;; Run the queue processor whenever Emacs has been idle for 0.5 seconds
(run-with-idle-timer 0.5 t #'glasspane-process-queue)
