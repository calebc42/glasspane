;; =============================================================================
;; ~/.emacs.d/init.el
;; Single source of truth for Emacs + Glasspane Android integration.
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
(require 'cl-lib)

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

;; --- 5. GLASSPANE CORE CONFIG & IO ---

(defcustom glasspane-org-dir "~/"
  "The base directory Glasspane will search for org files."
  :type 'string
  :group 'glasspane)

(defvar glasspane-config-file (expand-file-name "glasspane-config.json" user-emacs-directory)
  "Path to the Glasspane JSON configuration file.")

(defun glasspane-get-org-files ()
  "Return a list of all .org files in `glasspane-org-dir'."
  (directory-files-recursively (expand-file-name glasspane-org-dir) "\\.org$"))

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

(glasspane--load-config)
(org-id-update-id-locations (glasspane-get-org-files))

;; --- 6. CORE SDUI & JSON HELPERS ---

(defun glasspane--extract-query (key query)
  "Safely extract a query parameter and ensure it is a plain string."
  (let ((val (cdr (assoc key query))))
    (while (consp val) (setq val (car val)))
    val))

(defun glasspane--json-success (proc &optional extra-alist)
  (with-httpd-buffer proc "application/json"
    (insert (json-encode (append '((status . "success")) (or extra-alist '()))))))

(defun glasspane--json-error (proc message)
  (with-httpd-buffer proc "application/json"
    (insert (json-encode `((status . "error") (message . ,message))))))

(defmacro with-glasspane-node (proc id-expr &rest body)
  "Find the org node by ID-EXPR, execute BODY at that point."
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

;; --- 7. CONTENT PARSING HELPERS ---

(defun glasspane--get-clean-entry-text ()
  "Extract the body text of the current node, excluding drawers."
  (let ((end (save-excursion (outline-next-heading) (point)))
        (text ""))
    (save-excursion
      (forward-line 1)
      (while (< (point) end)
        (cond
         ((looking-at-p "^[ \t]*:[a-zA-Z0-9_]+:")
          (if (re-search-forward "^[ \t]*:END:[ \t]*$" end t) (forward-line 1) (forward-line 1)))
         ((looking-at-p "^[ \t]*#\\+BEGIN_LOGBOOK")
          (if (re-search-forward "^[ \t]*#\\+END_LOGBOOK[ \t]*$" end t) (forward-line 1) (forward-line 1)))
         ((looking-at-p "^[ \t]*CLOCK:") (forward-line 1))
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
        (if (re-search-forward "^[ \t]*:END:[ \t]*$" end t) (forward-line 1) (forward-line 1)))
       ((looking-at-p "^[ \t]*#\\+BEGIN_LOGBOOK")
        (if (re-search-forward "^[ \t]*#\\+END_LOGBOOK[ \t]*$" end t) (forward-line 1) (forward-line 1)))
       ((looking-at-p "^[ \t]*CLOCK:") (forward-line 1))
       (t (setq insertion-point (point)))))
    (if insertion-point
        (progn
          (delete-region insertion-point end)
          (goto-char insertion-point)
          (when (not (string-empty-p val)) (insert val "\n")))
      (goto-char end)
      (when (not (string-empty-p val)) (insert val "\n")))))

;; --- 8. SDUI NODE PARSER ---

(defun my/glasspane-parse-node-at-point ()
  "Parse the heading at point into a rich Glasspane JSON Node."
  (let* ((title (org-get-heading t t t t))
         (todo-state (org-get-todo-state))
         (priority (org-entry-get (point) "PRIORITY"))
         (tags (org-get-tags nil t))
         (all-tags (org-get-tags))
         (level (org-outline-level))
         (scheduled (org-entry-get (point) "SCHEDULED"))
         (deadline (org-entry-get (point) "DEADLINE"))
         (closed (org-entry-get (point) "CLOSED"))
         (effort (org-entry-get (point) "Effort"))
         (id (or (org-id-get) (progn (org-id-get-create) (org-id-get))))
         (custom-props (glasspane--get-custom-properties))
         (body-text (glasspane--get-clean-entry-text))
         (has-children (save-excursion
                         (let ((cur-level (org-outline-level)))
                           (outline-next-heading)
                           (and (not (eobp)) (> (org-outline-level) cur-level))))))
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

(defun glasspane--elements-for-directory (dir)
  (let ((items (directory-files dir t "^[^.].*"))
        (elements '()))
    (dolist (item items)
      (cond
       ((file-directory-p item)
        (push `((type . "Node")
                (id . ,(concat "dir:" item))
                (has_children . t)
                (elements . ,(vector `((type . "Text") (value . ,(file-name-nondirectory item)) (size . "Title")))))
              elements))
       ((and (file-regular-p item) (string-match-p "\\.org$" item))
        (push `((type . "Node")
                (id . ,(concat "file:" item))
                (has_children . t)
                (elements . ,(vector `((type . "Text") (value . ,(file-name-nondirectory item)) (size . "Title")))))
              elements))))
    (vconcat (reverse elements))))

(defun glasspane-get-view-elements (id)
  (cond
   ((or (null id) (string-empty-p id))
    (glasspane--elements-for-directory (expand-file-name glasspane-org-dir)))
   ((string-prefix-p "dir:" id) (glasspane--elements-for-directory (substring id 4)))
   ((string-prefix-p "file:" id)
    (let* ((file (substring id 5))
           (elements (org-map-entries (lambda () (my/glasspane-parse-node-at-point)) "LEVEL=1" (list file))))
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
      (vconcat (reverse elements))))))

;; --- 9. HTTP ENDPOINTS (CORE & DATA) ---

(defun httpd/glasspane-view (proc path query request)
  (let* ((id (glasspane--extract-query "id" query))
         (elements (glasspane-get-view-elements id))
         (view-title (cond
                      ((or (null id) (string-empty-p id)) "Root Directory")
                      ((string-prefix-p "file:" id) (file-name-nondirectory (substring id 5)))
                      (t "Sub-nodes")))
         (payload `((view_title . ,view-title) (elements . ,elements))))
    (glasspane--json-success proc payload)))
(defalias 'httpd/glasspane-view/ 'httpd/glasspane-view)

(defun httpd/glasspane-update (proc path query request)
  (let ((id (glasspane--extract-query "id" query))
        (prop (glasspane--extract-query "prop" query))
        (val (glasspane--extract-query "val" query)))
    (if (and id prop val (glasspane-update-property id prop val))
        (glasspane--json-success proc)
      (glasspane--json-error proc "Update failed"))))
(defalias 'httpd/glasspane-update/ 'httpd/glasspane-update)

(defun httpd/glasspane-update-body (proc path query request)
  (let ((id (glasspane--extract-query "id" query))
        (val (glasspane--extract-query "val" query)))
    (if id
        (with-glasspane-node proc id
          (glasspane-update-body-text (or val ""))
          (glasspane--json-success proc))
      (glasspane--json-error proc "Missing id"))))
(defalias 'httpd/glasspane-update-body/ 'httpd/glasspane-update-body)

(defun httpd/glasspane-update-title (proc path query request)
  (let ((id (glasspane--extract-query "id" query))
        (val (glasspane--extract-query "val" query)))
    (if (or (null id) (null val))
        (glasspane--json-error proc "Missing id or val")
      (with-glasspane-node proc id
        (org-back-to-heading t)
        (org-edit-headline val)
        (glasspane--json-success proc)))))
(defalias 'httpd/glasspane-update-title/ 'httpd/glasspane-update-title)

(defun httpd/glasspane-config-get (proc path query request)
  (let ((config (if (file-exists-p glasspane-config-file)
                    (let* ((json-object-type 'alist) (json-array-type 'vector) (json-key-type 'string))
                      (json-read-file glasspane-config-file))
                  `((capture_templates . ,(glasspane--seed-capture-templates))
                    (tags . ,(glasspane--seed-tags))
                    (todo_keywords . ,(glasspane--seed-todos))))))
    (with-httpd-buffer proc "application/json" (insert (json-encode config)))))
(defalias 'httpd/glasspane-config-get/ 'httpd/glasspane-config-get)

(defun httpd/glasspane-config-set (proc path query request)
  (let ((payload (glasspane--extract-query "payload" query)))
    (if payload
        (unwind-protect
            (progn (with-temp-file glasspane-config-file (insert payload))
                   (glasspane--load-config)
                   (glasspane--json-success proc))
          (error (glasspane--json-error proc "Could not save config")))
      (glasspane--json-error proc "Missing payload"))))
(defalias 'httpd/glasspane-config-set/ 'httpd/glasspane-config-set)

;; --- 10. HTTP ENDPOINTS (AGENDAS, SEARCH, ACTIONS) ---

(defun glasspane-get-todo-keywords ()
  "Return the full TODO keyword configuration."
  (let ((result '()))
    (dolist (seq (or org-todo-keywords '((sequence "TODO" "|" "DONE"))))
      (let ((states '())
            (done-found nil)
            (items (cdr seq)))
        (dolist (kw items)
          (cond
           ((equal kw "|") (setq done-found t))
           (t (let ((clean (if (string-match "^\\([^(]+\\)" kw) (match-string 1 kw) kw)))
                (push `((state . ,clean) (type . ,(if done-found "done" "active"))) states)))))
        (unless done-found
          (when states (setf (cdr (assoc 'type (car states))) "done")))
        (push `((sequence . ,(vconcat (reverse states)))) result)))
    (vconcat (reverse result))))

(defun glasspane-format-agenda-item (marker)
  (when (and marker (marker-buffer marker))
    (with-current-buffer (marker-buffer marker)
      (org-with-point-at marker
        (let* ((title (org-get-heading t t t t))
               (todo-state (org-get-todo-state))
               (priority (org-entry-get (point) "PRIORITY"))
               (tags (org-get-tags nil t))
               (scheduled (org-entry-get (point) "SCHEDULED"))
               (deadline (org-entry-get (point) "DEADLINE"))
               (id (or (org-id-get) (progn (org-id-get-create) (org-id-get))))
               (category (org-entry-get (point) "CATEGORY")))
          `((id . ,id) (title . ,title) (todo . ,(or todo-state "")) (priority . ,(or priority ""))
            (tags . ,(vconcat (or tags '()))) (scheduled . ,(or scheduled ""))
            (deadline . ,(or deadline "")) (category . ,(or category ""))
            (file . ,(or (buffer-file-name) ""))))))))

(defun glasspane-get-agenda (span num-days)
  (let* ((today (current-time))
         (num-days-val (or num-days 7))
         (end-date (time-add today (days-to-time num-days-val)))
         (today-str (format-time-string "%Y-%m-%d" today))
         (end-date-str (format-time-string "%Y-%m-%d" end-date))
         (items '()))
    (dolist (file (org-agenda-files))
      (when (file-exists-p file)
        (with-current-buffer (find-file-noselect file)
          (org-map-entries
           (lambda ()
             (let ((scheduled (org-entry-get (point) "SCHEDULED"))
                   (deadline (org-entry-get (point) "DEADLINE")))
               (when (or scheduled deadline)
                 (let* ((parsed (glasspane-format-agenda-item (point-marker)))
                        (date-str (or scheduled deadline))
                        (effective-date (if (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" date-str)
                                            (match-string 1 date-str) today-str)))
                   (when (and parsed (not (string< end-date-str effective-date)))
                     (push (append parsed `((effective_date . ,effective-date))) items))))))))))
    (let ((grouped '())) 
      (dolist (item (sort items (lambda (a b) (string< (cdr (assoc 'effective_date a)) (cdr (assoc 'effective_date b))))))
        (let* ((date (cdr (assoc 'effective_date item)))
               (group (assoc date grouped)))
          (if group (setcdr group (vconcat (append (cdr group) (list item))))
            (push (cons date (vector item)) grouped))))
      (vconcat (mapcar (lambda (g) `((date . ,(car g)) (items . ,(cdr g)))) (reverse grouped))))))

(defun httpd/glasspane-agenda (proc path query request)
  (let* ((span-param (string-trim (or (glasspane--extract-query "span" query) "week")))
         (span (if (string-empty-p span-param) "week" span-param))
         (num-days (cond ((equal span "day") 1) ((equal span "month") 30) (t 7)))
         (agenda-data (glasspane-get-agenda span num-days))
         (keywords (glasspane-get-todo-keywords)))
    (with-httpd-buffer proc "application/json"
      (insert (json-encode `((span . ,span)
                             (num_days . ,num-days)
                             (todo_keywords . ,keywords)
                             (groups . ,agenda-data)))))))
(defalias 'httpd/glasspane-agenda/ 'httpd/glasspane-agenda)

(defun httpd/glasspane-search (proc path query request)
  (let* ((q (glasspane--extract-query "q" query)) (results '()))
    (if (or (null q) (string-empty-p q)) (glasspane--json-error proc "Missing q parameter")
      (condition-case err
          (let ((markers (org-ql-select (org-agenda-files) (condition-case nil (read q) (error `(regexp ,q))) :action (lambda () (point-marker)))))
            (dolist (m markers) (let ((p (glasspane-format-agenda-item m))) (when p (push p results))))
            (glasspane--json-success proc `((results . ,(vconcat (reverse results))))))
        (error (glasspane--json-error proc (error-message-string err)))))))
(defalias 'httpd/glasspane-search/ 'httpd/glasspane-search)

(defun httpd/glasspane-refile (proc path query request)
  (let ((id (glasspane--extract-query "id" query)) (target-id (glasspane--extract-query "target" query)))
    (if (or (null id) (null target-id)) (glasspane--json-error proc "Missing id or target")
      (condition-case err
          (let ((source (org-id-find id t)) (target (org-id-find target-id t)))
            (if (and source target)
                (with-current-buffer (marker-buffer source)
                  (goto-char (marker-position source))
                  (org-refile nil nil (list (org-with-point-at target (org-get-heading t t t t))
                                             (buffer-file-name (marker-buffer target)) nil (marker-position target)))
                  (glasspane--json-success proc))
              (glasspane--json-error proc "Source or target not found")))
        (error (glasspane--json-error proc (error-message-string err)))))))
(defalias 'httpd/glasspane-refile/ 'httpd/glasspane-refile)

(defun httpd/glasspane-tree-edit (proc path query request)
  (let ((id (glasspane--extract-query "id" query)) (action (glasspane--extract-query "action" query)) (title (glasspane--extract-query "title" query)))
    (with-glasspane-node proc id
      (pcase action
        ("move-up" (org-move-subtree-up)) ("move-down" (org-move-subtree-down))
        ("promote" (org-do-promote)) ("demote" (org-do-demote))
        ("insert-sibling" (org-insert-heading-after-current) (insert (or title "New Node")) (org-id-get-create))
        ("insert-child" (org-insert-heading-respect-content) (org-do-demote) (insert (or title "New Subnode")) (org-id-get-create)))
      (glasspane--json-success proc))))
(defalias 'httpd/glasspane-tree-edit/ 'httpd/glasspane-tree-edit)

(defun httpd/glasspane-create-io (proc path query request)
  (let* ((type (glasspane--extract-query "type" query)) (target (glasspane--extract-query "target" query)) (name (glasspane--extract-query "name" query)))
    (pcase type
      ("file" (let* ((full-path (expand-file-name (if (string-match-p "\\.org$" target) target (concat target ".org")) glasspane-org-dir)))
                (make-directory (file-name-directory full-path) t)
                (unless (file-exists-p full-path) (write-region "" nil full-path))
                (glasspane--json-success proc)))
      ("heading" (let* ((file (if (string-prefix-p "file:" target) (substring target 5) target))
                        (full-path (expand-file-name file glasspane-org-dir)))
                   (with-current-buffer (find-file-noselect full-path)
                     (goto-char (point-max)) (unless (bolp) (insert "\n"))
                     (insert (format "* %s\n:PROPERTIES:\n:ID:       %s\n:END:\n" (or name "New Heading") (org-id-new "")))
                     (save-buffer) (glasspane--json-success proc)))))))
(defalias 'httpd/glasspane-create-io/ 'httpd/glasspane-create-io)

;; --- 11. TODO, TAGS, PRIORITY, CLOCK ---

(defun httpd/glasspane-set-todo (proc path query request)
  (let ((id (glasspane--extract-query "id" query)) (state (glasspane--extract-query "state" query)))
    (with-glasspane-node proc id
      (if (equal state "cycle") (org-todo) (org-todo state))
      (glasspane--json-success proc `((new_state . ,(or (org-get-todo-state) "")))))))
(defalias 'httpd/glasspane-set-todo/ 'httpd/glasspane-set-todo)

(defun httpd/glasspane-set-tags (proc path query request)
  (let ((id (glasspane--extract-query "id" query)) (tags (glasspane--extract-query "tags" query)))
    (with-glasspane-node proc id (org-set-tags tags) (glasspane--json-success proc))))
(defalias 'httpd/glasspane-set-tags/ 'httpd/glasspane-set-tags)

(defun httpd/glasspane-clock-in (proc path query request)
  (let ((id (glasspane--extract-query "id" query)))
    (let ((marker (org-id-find id t)))
      (if marker (progn (with-current-buffer (marker-buffer marker) (goto-char (marker-position marker)) (org-clock-in))
                        (glasspane--json-success proc))
        (glasspane--json-error proc "Node not found")))))
(defalias 'httpd/glasspane-clock-in/ 'httpd/glasspane-clock-in)

(defun httpd/glasspane-clock-out (proc path query request)
  (if (org-clock-is-active) (progn (org-clock-out) (glasspane--json-success proc))
    (glasspane--json-error proc "No active clock")))
(defalias 'httpd/glasspane-clock-out/ 'httpd/glasspane-clock-out)

(defun httpd/glasspane-clock-status (proc path query request)
  (let ((active-id (if (org-clock-is-active) (org-with-point-at org-clock-marker (or (org-id-get) "")) "")))
    (glasspane--json-success proc `((active_id . ,active-id)))))
(defalias 'httpd/glasspane-clock-status/ 'httpd/glasspane-clock-status)

;; --- 12. NOTIFICATION & CAPTURE PARSING ---

(defun glasspane-get-capture-templates ()
  "Parse `org-capture-templates' into Glasspane JSON."
  (let ((res '()))
    (dolist (tpl org-capture-templates)
      (let* ((key (nth 0 tpl)) (desc (nth 1 tpl)) (raw (nth 4 tpl))
             (content (cond ((stringp raw) raw) ((and (listp raw) (eq (car raw) 'file))
                                                (with-temp-buffer (insert-file-contents (expand-file-name (cadr raw))) (buffer-string))) (t ""))))
        (when (and (stringp key) (stringp desc))
          (let ((fields '()) (start 0))
            (while (string-match "%^{\\([^}|]+\\)\\([|][^}]*\\)?}" content start)
              (let ((prompt (match-string 1 content)))
                (unless (member prompt (mapcar (lambda (f) (cdr (assoc 'key f))) fields))
                  (push `((key . ,prompt) (label . ,prompt) (hint . "")) fields)))
              (setq start (match-end 0)))
            (push `((id . ,key) (title . ,desc) (endpoint . "/glasspane-capture") (fields . ,(vconcat (reverse fields)))) res)))))
    (vconcat (reverse res))))

(defun glasspane--seed-capture-templates ()
  (mapcar (lambda (tpl) `((id . ,(nth 0 tpl)) (title . ,(nth 1 tpl)) (file . "") (content . ,(nth 4 tpl)))) org-capture-templates))

(defun glasspane--seed-tags () (if org-tag-alist (vconcat (mapcar #'car org-tag-alist)) []))
(defun glasspane--seed-todos () (if org-todo-keywords (vconcat (cdr (car org-todo-keywords))) ["TODO" "|" "DONE"]))

;; --- 13. ASYNC TASK QUEUE ---

(defvar glasspane-task-queue '()
  "A list of pending tasks received from Android.")

(defun glasspane-process-queue ()
  (when glasspane-task-queue
    (let* ((task-query (car (last glasspane-task-queue)))
           (id (glasspane--extract-query "id" task-query))
           (original-tpl (assoc id org-capture-templates)))
      (setq glasspane-task-queue (butlast glasspane-task-queue))
      (if (not original-tpl) (message "Glasspane Async Error: Template '%s' not found" id)
        (condition-case err
            (let* ((type (nth 2 original-tpl)) (target (nth 3 original-tpl))
                   (template-string (nth 4 original-tpl)) (props (nthcdr 5 original-tpl))
                   (modified-string template-string))
              (mapc (lambda (param)
                      (let* ((key (car param)) (val (glasspane--extract-query key task-query)))
                        (when (and (stringp key) (stringp val) (not (equal key "id")))
                          (setq modified-string (replace-regexp-in-string (format "%%^{\\(%s\\)\\([|][^}]*\\)?}" (regexp-quote key)) val modified-string t t)))))
                    task-query)
              (setq props (plist-put props :immediate-finish t))
              (let* ((headless (append (list id (nth 1 original-tpl) type target modified-string) props))
                     (org-capture-templates (list headless)))
                (save-window-excursion (org-capture nil id)))
              (message "Glasspane: Background capture processed: %s" id))
          (error (message "Glasspane Background Error: %s" (error-message-string err))))))))

(run-with-idle-timer 0.5 t #'glasspane-process-queue)

(defun my/glasspane-notify-clock-in ()
  (when (and (boundp 'org-clock-current-task) org-clock-current-task)
    (my/glasspane-notify :id 42 :title org-clock-current-task :content "Clocked In" :ongoing t :chronometer t
                         :base-time-ms (truncate (* (float-time org-clock-start-time) 1000))
                         :button1-label "Clock Out" :button1-endpoint "/glasspane-clock-out")))

(add-hook 'org-clock-in-hook #'my/glasspane-notify-clock-in)
(add-hook 'org-clock-out-hook (lambda () (my/glasspane-cancel-notification 42)))

(httpd-start)