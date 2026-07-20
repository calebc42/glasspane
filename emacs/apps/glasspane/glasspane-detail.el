;;; glasspane-detail.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

(require 'glasspane-ui)

(defvar glasspane-ui--detail-ref nil
  "Reference alist (id/file/pos/headline) of the heading being viewed, or nil.")

(defvar glasspane-ui--detail-read-mode t
  "When non-nil, detail view shows the foldable reader instead of the editor.")

(defun glasspane-ui--widget-row (it)
  "Build one generic widget row from agenda item IT.
All semantics live here: the row tap opens the heading in the app, the
trailing circle todo-cycles silently — the companion just renders."
  (let* ((hm (glasspane-org--item-hm (alist-get 'time it)))
         (todo (alist-get 'todo it))
         (done (and todo
                    (member todo (or (default-value 'org-done-keywords)
                                     '("DONE" "CANCELLED")))
                    t))
         (ref (alist-get 'ref it))
         (meta (glasspane-ui--widget-item-meta it hm))
         (meta (unless (string-empty-p meta) meta)))
    (jetpacs-widget-item
     (or (alist-get 'headline it) "Untitled")
     :todo todo :done done
     :meta meta
     :icon (and meta (glasspane-ui--widget-agenda-icon (alist-get 'type it)))
     :on-tap (jetpacs-action "heading.tap" :args ref) :in-app t
     :button (and todo (if done "todo_done" "todo_open"))
     :on-button (and todo (jetpacs-action "heading.todo-cycle" :args ref)))))

(defun glasspane-ui--widget-query-items (query)
  "Custom-agenda QUERY results as widget rows.
Search hits carry no agenda qualifiers — the metadata line is the file
name under a folder icon. `glasspane-org--search' is memoised, so
re-pushing is cheap."
  (mapcar
   (lambda (it)
     (let* ((todo (alist-get 'todo it))
            (done (and todo
                       (member todo (or (default-value 'org-done-keywords)
                                        '("DONE" "CANCELLED")))
                       t))
            (file (alist-get 'file it))
            (ref (alist-get 'ref it)))
       (jetpacs-widget-item
        (or (alist-get 'headline it) "Untitled")
        :todo todo :done done
        :meta (and file (file-name-nondirectory file))
        :icon (and file "folder")
        :on-tap (jetpacs-action "heading.tap" :args ref) :in-app t
        :button (and todo (if done "todo_done" "todo_open"))
        :on-button (and todo (jetpacs-action "heading.todo-cycle" :args ref)))))
   (seq-take (condition-case nil (glasspane-org--search query) (error nil))
             20)))

(defun glasspane-ui--detail-toolbar-extras (ref)
  "Every registered app layer's floating-toolbar chips for REF.
An erroring contributor costs its own chips, never the toolbar."
  (when ref
    (cl-loop for fn in glasspane-ui-detail-toolbar-functions
             append (condition-case nil (funcall fn ref)
                      (error nil)))))

(defun glasspane-ui--detail-copy-link-item (ref)
  "The Copy Link chip for REF, or nil when the ref can't resolve.
An id link when the heading already has an :ID:, a file::*headline
link otherwise — built at render time so the copy itself is
companion-local (`clipboard.copy') and works offline."
  (condition-case nil
      (let ((marker (jetpacs-org-resolve-ref ref)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (let* ((headline (org-get-heading t t t t))
                  (id (org-entry-get nil "ID"))
                  (link (if id
                            (format "[[id:%s][%s]]" id headline)
                          (format "[[file:%s::*%s][%s]]"
                                  (buffer-file-name) headline headline))))
             (jetpacs-nav-item "content_copy" "Copy Link"
                            (jetpacs-clipboard-action link))))))
    (error nil)))

(defun glasspane-ui--detail-subtree-text (ref)
  "REF's whole subtree as a string, or nil when the ref can't resolve."
  (condition-case nil
      (let ((marker (jetpacs-org-resolve-ref ref)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (buffer-substring-no-properties
            (point)
            (progn (org-end-of-subtree t t) (point))))))
    (error nil)))

(defun glasspane-ui--detail-copy-text-item (ref)
  "The Copy Text chip for REF: the whole subtree onto the clipboard.
Companion-local (`clipboard.copy'), so it works offline; nil when the
ref can't resolve."
  (when-let ((text (glasspane-ui--detail-subtree-text ref)))
    (jetpacs-nav-item "copy_all" "Copy Text"
                   (jetpacs-clipboard-action text))))

(defun glasspane-ui--detail-share-item (ref)
  "The Share chip for REF: the whole subtree through the system share
sheet (`share.send'), titled with the headline; nil when the ref
can't resolve."
  (when-let ((text (glasspane-ui--detail-subtree-text ref)))
    (jetpacs-nav-item "share" "Share"
                   (jetpacs-share-action
                    text :title (alist-get 'headline ref)))))

(defun glasspane-ui--sibling-ref (ref direction)
  "A `heading.tap' ref for REF's same-level sibling in DIRECTION, or nil.
DIRECTION is `next' or `prev'.  Drives the detail view's Prev/Next
bottom-bar navigation, which only appears when a sibling exists — so
this doubles as the availability check."
  (condition-case nil
      (let ((marker (jetpacs-org-resolve-ref ref)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (org-back-to-heading t)
           (when (org-goto-sibling (eq direction 'prev))
             (let ((file (buffer-file-name))
                   (pos (point))
                   (title (nth 4 (org-heading-components))))
               (delq nil
                     (list (when file `(file . ,file))
                           `(pos . ,pos)
                           (when (and title (not (string-empty-p title)))
                             `(headline . ,title)))))))))
    (error nil)))

(defun glasspane-ui--detail-view (snackbar)
  "The heading drill-in: reader/editor body under curated heading actions."
  (let* ((ref glasspane-ui--detail-ref)
         (file (and ref (alist-get 'file ref)))
         (pos (and ref (alist-get 'pos ref)))
         (buf (and file (find-buffer-visiting file)))
         (is-clocked-in (and buf
                             (bound-and-true-p org-clock-hd-marker)
                             (marker-buffer org-clock-hd-marker)
                             (equal buf (marker-buffer org-clock-hd-marker))
                             (with-current-buffer buf
                               (= (line-number-at-pos pos)
                                  (line-number-at-pos org-clock-hd-marker))))))
    (jetpacs-shell-nav-view
     "Detail" (glasspane-ui--detail-body-with-notes ref)
     ;; Back is pure navigation: builtin = instant, local, works offline.
     ;; heading.back stays registered for compatibility but nothing emits
     ;; it anymore.
     :actions (delq nil
                    (list
                     (when ref
                       (if is-clocked-in
                           (jetpacs-icon-button "timer_off" (jetpacs-action "org.clock.out")
                                             :content-description "Clock Out")
                         (jetpacs-icon-button "timer" (jetpacs-action "heading.clock-in" :args ref)
                                           :content-description "Clock In")))
                     (jetpacs-icon-button
                      (if glasspane-ui--detail-read-mode "edit" "visibility")
                      (jetpacs-action "detail.toggle-read")
                      :content-description
                      (if glasspane-ui--detail-read-mode "Edit" "Read"))
                     (when (and ref (glasspane-ui--org-file-p file))
                       (jetpacs-icon-button
                        "tune"
                        (jetpacs-action "files.properties.show"
                                     :args `((file . ,file)))
                        :content-description "Properties"))))
   :bottom-bar (when glasspane-ui--detail-read-mode
                 ;; Prev/Next flank the bar (leftmost / rightmost) and
                 ;; appear only when a same-level sibling exists; the two
                 ;; add actions sit between them.
                 (let ((prev (and ref (glasspane-ui--sibling-ref ref 'prev)))
                       (next (and ref (glasspane-ui--sibling-ref ref 'next))))
                   (jetpacs-bottom-bar
                    (delq nil
                          (list
                           (when prev
                             (jetpacs-nav-item
                              "chevron_left" "Prev"
                              (jetpacs-action "heading.tap" :args prev)))
                           (jetpacs-nav-item
                            "edit_note" "Log Note"
                            (jetpacs-action "heading.add-note"
                                         :args glasspane-ui--detail-ref
                                         :when-offline "drop"))
                           (jetpacs-nav-item
                            "post_add" "Add Heading"
                            (jetpacs-action "heading.add-heading"
                                         :args glasspane-ui--detail-ref
                                         :when-offline "drop"))
                           (when next
                             (jetpacs-nav-item
                              "chevron_right" "Next"
                              (jetpacs-action "heading.tap" :args next))))))))
   :floating-toolbar (when glasspane-ui--detail-read-mode
                       (vconcat
                        (delq nil
                              (list
                               (jetpacs-nav-item
                                "drive_file_move" "Refile"
                                (jetpacs-action "heading.refile"
                                             :args glasspane-ui--detail-ref
                                             :when-offline "drop"))
                               (jetpacs-nav-item
                                "archive" "Archive"
                                (jetpacs-action "heading.archive"
                                             :args glasspane-ui--detail-ref
                                             :when-offline "drop"))
                               (when ref
                                 (glasspane-ui--detail-copy-link-item ref))
                               (when ref
                                 (glasspane-ui--detail-copy-text-item ref))
                               (when ref
                                 (glasspane-ui--detail-share-item ref))
                               (jetpacs-nav-item
                                "delete" "Delete"
                                (jetpacs-action "heading.delete"
                                             :args glasspane-ui--detail-ref
                                             :when-offline "drop"))))
                        (glasspane-ui--detail-toolbar-extras ref)))
   :snackbar snackbar)))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.detail" :builder #'glasspane-ui--detail-view
                          :when (lambda () (and glasspane-ui--detail-ref t))
                          :overlay (lambda () (and glasspane-ui--detail-ref t))
                          :order 110))

(defun glasspane-ui--ref-clocked-in-p (ref)
  "Whether REF's heading is the currently clocked task.
A file that isn't even visited can't be the clock source, so this
stays cheap across a list of cards."
  (when-let* ((file (alist-get 'file ref))
              (pos (alist-get 'pos ref))
              (buf (find-buffer-visiting file)))
    (and (bound-and-true-p org-clock-hd-marker)
         (eq (marker-buffer org-clock-hd-marker) buf)
         (integerp pos)
         (with-current-buffer buf
           (org-with-wide-buffer
            (= (progn (goto-char (min pos (point-max)))
                      (line-beginning-position))
               (progn (goto-char org-clock-hd-marker)
                      (line-beginning-position))))))))

(defun glasspane-ui--agenda-card (it)
  "A detail-rich agenda card for item IT.
Leading time (or a type icon), priority-prefixed headline (struck
through when done), a todo/type/file caption, tag chips when present,
a quick complete button for open todos, and the heading overflow menu."
  (let* ((headline (or (alist-get 'headline it) "Untitled"))
         (todo (alist-get 'todo it))
         ;; Normalized "HH:MM" — the raw property is a time-grid string
         ;; like " 9:15......".
         (time (glasspane-org--item-hm (alist-get 'time it)))
         (type (alist-get 'type it))
         (file (alist-get 'file it))
         (priority (alist-get 'priority it))
         (tags (append (alist-get 'tags it) nil))
         (ref (alist-get 'ref it))
         (done (and todo (member todo (or (default-value 'org-done-keywords)
                                          '("DONE" "CANCELLED")))))
         (icon+color (glasspane-ui--agenda-type-icon type))
         (caption (string-join
                   (delq nil (list todo
                                   (and (stringp type)
                                        (glasspane-ui--agenda-type-label type))
                                   (and file (file-name-nondirectory file))))
                   "  ·  "))
         (lead (cond ((and (stringp time) (not (string-empty-p time)))
                      (jetpacs-text time 'label))
                     (icon+color
                      (jetpacs-icon (car icon+color) :size 18 :color (cdr icon+color)))))
         (headline-node
          (jetpacs-rich-text
           (delq nil
                 (list
                  (when priority
                    (jetpacs-span (format "[%s] " priority) :bold t :color "#F57C00"))
                  (if done
                      (jetpacs-span headline :strike t)
                    (jetpacs-span headline))))))
         (middle
          (apply #'jetpacs-column
                 (delq nil
                       (list
                        headline-node
                        (unless (string-empty-p caption)
                          (jetpacs-text caption 'caption))
                        (glasspane-ui--card-date-row it)
                        (when tags
                          (apply #'jetpacs-flow-row
                                 (mapcar (lambda (tg)
                                           (jetpacs-assist-chip tg :on-tap (jetpacs-action "search.by-tag" :args `((tag . ,tg)))))
                                         tags))))))))
    (let ((sides (and ref (glasspane-org-reader-swipe-sides ref))))
      (jetpacs-card
       (list (apply #'jetpacs-row
                    (delq nil (list lead
                                    (jetpacs-box (list middle) :weight 1)
                                    (when ref
                                      (glasspane-org-reader-heading-menu
                                       ref (glasspane-ui--ref-clocked-in-p ref)))))))
       :on-tap (jetpacs-action "heading.tap" :args ref)
       :on-swipe (jetpacs-action "heading.todo-cycle" :args ref)
       :swipe-start (car sides)
       :swipe-end (cdr sides)))))

;; The old agenda-files-only "files" body is superseded by the full
;; browser in jetpacs-files.el (jetpacs-files-browser-body).

(defun glasspane-ui--clock-body ()
  (let* ((status (glasspane-org--clock-status))
         (recent (condition-case nil
                     (glasspane-org--recent-clocks 5)
                   (error nil)))
         (status-card
          (if status
              (let* ((start (alist-get 'start status))
                     (mins (when start
                             (max 0 (floor (/ (- (float-time) start) 60))))))
                (jetpacs-card
                 (list (jetpacs-column
                        (jetpacs-text "Currently Clocked In" 'caption)
                        (jetpacs-text (or (alist-get 'task status) "?") 'headline)
                        (jetpacs-text (if mins (format "%d min elapsed" mins) "")
                                   'caption)
                        (jetpacs-button "Clock Out" (jetpacs-action "org.clock.out"))))))
            (jetpacs-empty-state :icon "schedule"
                              :title "Not clocked in"
                              :caption "Pick a recent task below to start.")))
         (recent-cards
          (mapcar (lambda (r)
                    (jetpacs-card
                     (list (jetpacs-text (or (alist-get 'headline r) "?") 'body))
                     :on-tap (jetpacs-action "heading.clock-in"
                                          :args (alist-get 'ref r))))
                  recent))
         (all-children (append (list status-card)
                               (when recent-cards
                                 (cons (jetpacs-section-header "Recent Tasks")
                                       recent-cards)))))
    (apply #'jetpacs-column all-children)))

(defun glasspane-ui--result-card (it)
  "Render a search/heading item IT to a tappable card with tag chips."
  (let* ((headline (or (alist-get 'headline it) "?"))
         (todo (alist-get 'todo it))
         (file (alist-get 'file it))
         (tags (append (alist-get 'tags it) nil))
         (ref (alist-get 'ref it))
         (caption (string-join
                   (delq nil (list todo (when file (file-name-nondirectory file))))
                   "  ·  "))
         (children (delq nil
                         (list
                          (jetpacs-text headline 'body)
                          (unless (string-empty-p caption)
                            (jetpacs-text caption 'caption))
                          (when tags
                            (apply #'jetpacs-flow-row
                                   (mapcar (lambda (tg)
                                             (jetpacs-assist-chip tg :on-tap (jetpacs-action "search.by-tag" :args `((tag . ,tg)))))
                                           tags)))))))
    (jetpacs-card (list (apply #'jetpacs-column children))
               :on-tap (jetpacs-action "heading.tap" :args ref))))

(defun glasspane-ui--todo-chips (current keywords ref)
  "A single-line chip rail for KEYWORDS with CURRENT selected.
Tapping an active chip removes the state.  Long sequences pan
sideways rather than wrapping into a stack."
  (apply #'jetpacs-scroll-row
         (mapcar (lambda (kw)
                   (jetpacs-chip kw
                              :selected (equal kw current)
                              :on-tap (jetpacs-action
                                       "heading.todo-set"
                                       :args (cons (cons 'state (if (equal kw current) "" kw)) ref))))
                 keywords)))

(defun glasspane-ui--priority-chips (current ref)
  "A row of priority chips (A..C) with CURRENT selected; tapping an active chip removes it."
  (let* ((hi (or (bound-and-true-p org-priority-highest) ?A))
         (lo (or (bound-and-true-p org-priority-lowest) ?C))
         (levels (mapcar #'char-to-string (number-sequence hi lo))))
    (apply #'jetpacs-flow-row
           (mapcar (lambda (p)
                     (jetpacs-chip p
                                :selected (equal p current)
                                :on-tap (jetpacs-action
                                         "heading.priority"
                                         :args (cons (cons 'value (if (equal p current) "" p)) ref))))
                   levels))))

(defun glasspane-ui--property-row (key value ref pos)
  "A two-column KEY → editable VALUE row for the detail Properties editor.
KEY renders without org's colons.  ID is shown read-only (editing it
breaks links); every other value is an inline input whose submit runs
`heading.prop-set' — submitting an empty value removes the property."
  (let* ((marker (ignore-errors (jetpacs-org-resolve-ref ref)))
         (buf (and marker (marker-buffer marker)))
         (allowed (and buf
                       (with-current-buffer buf
                         (org-with-wide-buffer (goto-char pos)
                           (ignore-errors
                             (org-property-get-allowed-values pos key))))))
         (is-boolean (or (equal allowed '("t" "nil")) (equal allowed '("true" "false"))
                         (string-match-p "\\?" key)))
         (is-date (or (string-match-p "_DATE\\|_TIME\\'" key)
                      (member key '("CREATED" "SCHEDULED" "DEADLINE"))
                      (string-match-p "\\`[[<].*?[\]>]\\'" value)))
         (is-number (and (not is-date) (string-match-p "\\`[0-9]+\\'" value)))
         (is-link (and (not (string-empty-p value)) (string-match org-link-bracket-re value)))
         (action (jetpacs-action "heading.prop-set" :args (cons `(name . ,key) ref))))
    (jetpacs-row
     (jetpacs-box (list (jetpacs-text key 'label)) :weight 2)
     (jetpacs-box
      (list (cond
             ((equal key "ID")
              (jetpacs-text value 'caption nil nil t))
             (is-boolean
              (jetpacs-switch (format "prop-%s/%s" pos key)
                           :value (member value '("t" "true" "1"))
                           :on-toggle action))
             ((and allowed (listp allowed))
              ;; :on-change is the enum-list's real callback key — the
              ;; old :on-select signalled whenever a property carried
              ;; org allowed values (KEY_ALL), killing the whole row.
              (jetpacs-enum-list (format "prop-%s/%s" pos key) allowed
                              :value (list value)
                              :on-change action))
             (is-date
              (jetpacs-date-button (if (string-empty-p value) "Set Date" value) action :value value))
             (is-number
              (let ((num (string-to-number value)))
                (if (<= num 10)
                    (jetpacs-slider (format "prop-%s/%s" pos key) :value num :min 0 :max 10 :steps 10 :on-change action)
                  (jetpacs-slider (format "prop-%s/%s" pos key) :value num :min 0 :max 100 :steps 100 :on-change action))))
             (is-link
              (let ((link (match-string 1 value))
                    (desc (match-string 2 value)))
                (jetpacs-button (or desc link)
                                (jetpacs-action "org.open-at-point" :args `((link . ,link)))
                                :variant "outlined")))
             (t
              (jetpacs-text-input (format "prop-%s/%s" pos key)
                               :value value
                               :single-line t
                               :on-submit action))))
      :weight 3))))

(defun glasspane-org--parse-logbook (text)
  ;; Keywords may be written lowercase in org files ("clock:" is as valid
  ;; as "CLOCK:"), so match case-insensitively — explicitly, like
  ;; org-element does, never relying on the ambient `case-fold-search'.
  (let ((case-fold-search t)
        (lines (split-string text "\n" t "[ \t]+"))
        entries current-entry)
    (dolist (line lines)
      (cond
       ((string-match "^CLOCK: \\[\\(.*?\\)\\]--\\[\\(.*?\\)\\] =>[ \t]+\\(.*\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'clock :start (match-string 1 line)
                                  :end (match-string 2 line)
                                  :duration (match-string 3 line))))
       ((string-match "^CLOCK: \\[\\(.*?\\)\\]$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'clock :start (match-string 1 line) :active t)))
       ((string-match "^- Note taken on \\(\\[.*?\\]\\) \\\\\\\\$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'note :timestamp (match-string 1 line) :content "")))
       ((string-match "^- State \"\\(.*?\\)\"[ \t]+from \"\\(.*?\\)\"[ \t]+\\(\\[.*?\\]\\)\\(\\(?: \\\\\\\\\\)?\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'state :to (match-string 1 line) :from (match-string 2 line)
                                  :timestamp (match-string 3 line)
                                  :has-note (not (string-empty-p (match-string 4 line)))
                                  :content "")))
       ((string-match "^- State \"\\(.*?\\)\"[ \t]+\\(\\[.*?\\]\\)\\(\\(?: \\\\\\\\\\)?\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'state :to (match-string 1 line)
                                  :timestamp (match-string 2 line)
                                  :has-note (not (string-empty-p (match-string 3 line)))
                                  :content "")))
       (t
        ;; Continuation line
        (when current-entry
          (let ((content (plist-get current-entry :content)))
            (setq current-entry (plist-put current-entry :content
                                           (if (string-empty-p content)
                                               line
                                             (concat content "\n" line)))))))))
    (when current-entry (push current-entry entries))
    (nreverse entries)))

(defun glasspane-ui--render-logbook-entry (entry)
  (let ((type (plist-get entry :type)))
    (cl-case type
      (clock
       (jetpacs-box
        (list
         (jetpacs-row
          (jetpacs-icon "timer" :color "primary" :padding [0 12 0 0])
          (jetpacs-column
           (jetpacs-text (if (plist-get entry :active)
                          (format "Started %s" (plist-get entry :start))
                        (glasspane-org--format-clock-time (plist-get entry :start) (plist-get entry :end)))
                      'body t nil nil nil [0 0 4 0])
           (jetpacs-text (plist-get entry :duration) 'caption))))
        :padding [8 16 8 16]))
      (note
       (jetpacs-box
        (list
         (jetpacs-row
          (jetpacs-icon "chat" :color "primary" :padding [0 12 0 0])
          (jetpacs-column
           (jetpacs-text (format "Note • %s" (plist-get entry :timestamp)) 'caption nil nil nil nil [0 0 4 0])
           (jetpacs-text (plist-get entry :content) 'body))))
        :padding [8 16 8 16]))
      (state
       (jetpacs-box
        (list
         (jetpacs-row
          (jetpacs-icon "change_history" :color "primary" :padding [0 12 0 0])
          (jetpacs-column
           (jetpacs-text (if (plist-get entry :from)
                          (format "%s → %s" (plist-get entry :from) (plist-get entry :to))
                        (format "Set to %s" (plist-get entry :to)))
                      'body t nil nil nil [0 0 4 0])
           (jetpacs-text (if (not (string-empty-p (plist-get entry :content)))
                          (format "%s\n%s" (plist-get entry :timestamp) (plist-get entry :content))
                        (plist-get entry :timestamp))
                      'caption))))
        :padding [8 16 8 16])))))

(defun glasspane-ui--logbook-entries (pos)
  "Return structured logbook entries for heading at POS, or nil.
Drawer delimiters are matched case-insensitively (\":logbook:\" is
valid org), explicitly rather than via ambient `case-fold-search'."
  (save-excursion
    (goto-char pos)
    (let ((case-fold-search t)
          (end (save-excursion (org-end-of-meta-data t) (point))))
      (goto-char pos)
      (when (re-search-forward "^[ \t]*:LOGBOOK:[ \t]*$" end t)
        (let ((start (match-end 0)))
          (when (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
            (glasspane-org--parse-logbook (buffer-substring-no-properties start (match-beginning 0)))))))))

(defun glasspane-ui--properties-section (props ref pos)
  "The Properties collapsible: KEY → VALUE rows plus an + Add button.
Always present (even with no properties yet) so + Add is reachable."
  (jetpacs-collapsible
   (format "detail-props/%s" pos)
   (jetpacs-text (if props (format "Properties (%d)" (length props)) "Properties")
              'label)
   (delq nil
         (append
          (mapcar (lambda (kv)
                    (glasspane-ui--property-row (car kv) (or (cdr kv) "") ref pos))
                  props)
          (list
           (when props
             (jetpacs-text "Submit an empty value to remove a property." 'caption))
           (jetpacs-row
            (jetpacs-spacer :weight 1)
            (jetpacs-button "+ Add property"
                         (jetpacs-action "heading.prop-add" :args ref)
                         :variant "outlined")))))
   :collapsed t))

(defun glasspane-ui--detail-body-with-notes (ref)
  "The detail body plus every registered app layer's sections.
The sections splice INTO a lazy_column body (nesting another scroll
container would break Compose) and wrap otherwise."
  (let ((body (glasspane-ui--detail-body ref))
        (extras (and ref
                     (cl-loop for fn in glasspane-ui-detail-nodes-functions
                              append (condition-case nil (funcall fn ref)
                                       (error nil))))))
    (cond
     ((null extras) body)
     ((equal (alist-get 't body) "lazy_column")
      (mapcar (lambda (kv)
                (if (eq (car kv) 'children)
                    (cons 'children (vconcat (cdr kv) extras))
                  kv))
              body))
     (t (apply #'jetpacs-column body extras)))))

(defun glasspane-ui--detail-body (ref)
  (condition-case err
      (let* ((marker (jetpacs-org-resolve-ref ref))
             (buf (marker-buffer marker))
             (file (buffer-file-name buf))
             (pos (marker-position marker))
             (meta (with-current-buffer buf
                     (org-with-wide-buffer
                      (goto-char pos)
                      (let ((comps (org-heading-components)))
                        (list :headline (or (nth 4 comps) "")
                              :todo (nth 2 comps)
                              :priority (and (nth 3 comps)
                                             (char-to-string (nth 3 comps)))
                              :tags (org-get-tags)
                              :local-tags (ignore-errors (org-get-tags pos t))
                              :scheduled (org-entry-get pos "SCHEDULED")
                              :deadline (org-entry-get pos "DEADLINE")
                              :keywords (or org-todo-keywords-1 '("TODO" "DONE"))
                              ;; Ancestor (TITLE . POS) pairs, outermost
                              ;; first, for the breadcrumb trail.
                              :ancestors
                              (save-excursion
                                (let (path)
                                  (ignore-errors
                                    (org-back-to-heading t)
                                    (while (org-up-heading-safe)
                                      (push (cons (substring-no-properties
                                                   (org-get-heading t t t t))
                                                  (point))
                                            path)))
                                  path)))))))
             (headline (plist-get meta :headline))
             (todo (plist-get meta :todo))
             (priority (plist-get meta :priority))
             (tags (plist-get meta :tags))
             (local-tags (plist-get meta :local-tags))
             (scheduled (plist-get meta :scheduled))
             (deadline (plist-get meta :deadline))
             (keywords (plist-get meta :keywords))
             (is-clocked-in (and (bound-and-true-p org-clock-hd-marker)
                                 (marker-buffer org-clock-hd-marker)
                                 (equal buf (marker-buffer org-clock-hd-marker))
                                 (with-current-buffer buf
                                   (= (line-number-at-pos marker)
                                      (line-number-at-pos org-clock-hd-marker)))))
             (sched-button
              (lambda (label when)
                (jetpacs-button label
                             (jetpacs-action "heading.schedule"
                                          :args (cons (cons 'when when) ref))
                             :variant "text"))))
        (if (not glasspane-ui--detail-read-mode)
            (let ((content (with-current-buffer buf
                             (org-with-wide-buffer
                              (goto-char pos)
                              (org-mark-subtree)
                              (buffer-substring-no-properties (region-beginning) (region-end))))))
              (jetpacs-column
               (jetpacs-editor (format "detail-%s" pos) content
                            :syntax "org"
                            :toolbar (glasspane-org-toolbar)
                            :line-numbers (and jetpacs-line-numbers
                                               (symbol-name jetpacs-line-numbers))
                            :on-save (jetpacs-action "detail.save"
                                                  :args `((ref . ,ref))
                                                  :when-offline "queue"
                                                  :dedupe (format "save-detail/%s" pos)))))
          (let ((sdate (glasspane-ui--ts-date scheduled))
                (ddate (glasspane-ui--ts-date deadline))
                (entry-props (ignore-errors
                               (with-current-buffer buf
                                 (org-with-wide-buffer
                                  (goto-char pos)
                                  (org-entry-properties pos 'standard)))))
                (logbook-entries (ignore-errors
                                   (with-current-buffer buf
                                     (org-with-wide-buffer
                                      (glasspane-ui--logbook-entries pos))))))
            (apply #'jetpacs-lazy-column
                   (delq nil
                         (append
                          (list
                           ;; Breadcrumb trail — the file, then each
                           ;; ancestor heading.  Every chip taps up to that
                           ;; level, so climbing out of a deep subtree never
                           ;; detours through the file picker.
                           (apply #'jetpacs-scroll-row
                                  (cons
                                   (if file
                                       (jetpacs-assist-chip
                                        (file-name-nondirectory file)
                                        :icon "description"
                                        :on-tap (jetpacs-action
                                                 "files.open"
                                                 :args `((file . ,file))))
                                     (jetpacs-text "?" 'caption))
                                   (mapcan
                                    (lambda (anc)
                                      (list (jetpacs-icon "chevron_right" :size 16)
                                            (jetpacs-assist-chip
                                             (car anc)
                                             :on-tap (jetpacs-action
                                                      "heading.tap"
                                                      :args `((file . ,file)
                                                              (pos . ,(cdr anc))
                                                              (headline . ""))))))
                                    (plist-get meta :ancestors))))
                           ;; Headline
                           (jetpacs-text headline 'title)
                           ;; State (always visible)
                           (glasspane-ui--todo-chips todo keywords ref)
                           ;; Priority (always visible)
                           (glasspane-ui--priority-chips priority ref)
                           (jetpacs-divider)
                           ;; ▸ Scheduling (collapsible — expanded when any date is set)
                           ;; The date-stamp chip IS the display (date + time);
                           ;; the raw "<2026-07-02 Thu>" caption is gone. Only a
                           ;; repeater cookie — which the chip can't show —
                           ;; surfaces as a caption.
                           (jetpacs-collapsible
                            (format "detail-sched/%s" pos)
                            (jetpacs-text "Scheduling" 'label)
                            (list
                             (jetpacs-row
                              (if sdate
                                  (jetpacs-date-stamp :date sdate
                                                   :time (glasspane-ui--ts-time scheduled))
                                (jetpacs-spacer :width 0))
                              (jetpacs-box
                               (list
                                (apply #'jetpacs-column
                                       (delq nil
                                             (list
                                              (jetpacs-text "Scheduled" 'label)
                                              (unless sdate
                                                (jetpacs-text "Not scheduled" 'caption))
                                              (when-let ((rep (glasspane-ui--ts-repeater scheduled)))
                                                (jetpacs-text (concat "Repeats " rep) 'caption))
                                              (jetpacs-flow-row
                                               (jetpacs-date-button "Set date"
                                                                 (jetpacs-action "heading.schedule" :args ref)
                                                                 :value sdate)
                                               (jetpacs-time-button "Set time"
                                                                 (jetpacs-action "heading.schedule-time" :args ref)
                                                                 :value (glasspane-ui--ts-time scheduled))
                                               (funcall sched-button "Today" "+0d")
                                               (funcall sched-button "+1d" "+1d")
                                               (funcall sched-button "+1w" "+1w")
                                               (jetpacs-button "Clear"
                                                            (jetpacs-action "heading.schedule"
                                                                         :args (cons '(clear . t) ref))
                                                            :variant "text"))))))
                               :weight 1))
                             (jetpacs-divider)
                             (jetpacs-row
                              (if ddate
                                  (jetpacs-date-stamp :date ddate
                                                   :time (glasspane-ui--ts-time deadline))
                                (jetpacs-spacer :width 0))
                              (jetpacs-box
                               (list
                                (apply #'jetpacs-column
                                       (delq nil
                                             (list
                                              (jetpacs-text "Deadline" 'label)
                                              (unless ddate
                                                (jetpacs-text "No deadline" 'caption))
                                              (when-let ((rep (glasspane-ui--ts-repeater deadline)))
                                                (jetpacs-text (concat "Repeats " rep) 'caption))
                                              (jetpacs-flow-row
                                               (jetpacs-date-button "Set date"
                                                                 (jetpacs-action "heading.deadline" :args ref)
                                                                 :value ddate)
                                               (jetpacs-button "Clear"
                                                            (jetpacs-action "heading.deadline"
                                                                         :args (cons '(clear . t) ref))
                                                            :variant "text"))))))
                               :weight 1)))
                            :collapsed (not (or sdate ddate)))
                           ;; ▸ Tags (collapsible)
                           (let* ((local-tags (or local-tags tags))
                                  (inherited-tags (seq-difference tags local-tags))
                                  (available (seq-uniq (append local-tags (mapcar (lambda (x) (if (consp x) (car x) x)) org-tag-alist))))
                                  (tags-content
                                   (apply #'jetpacs-column
                                          (delq nil
                                                (list
                                                 (jetpacs-enum-list (format "detail-tags/%s" pos) available
                                                                 :value local-tags :multi-select t :allow-add t
                                                                 :on-change (jetpacs-action "heading.tags" :args ref))
                                                 (when inherited-tags
                                                   (jetpacs-column
                                                    (jetpacs-text "Inherited" 'caption nil nil nil nil 8)
                                                    (apply #'jetpacs-flow-row
                                                           (mapcar (lambda (tg)
                                                                     (jetpacs-assist-chip tg))
                                                                   inherited-tags)))))))))
                             (jetpacs-collapsible
                              (format "detail-tags-fold/%s" pos)
                              (jetpacs-text (if tags (format "Tags (%d)" (length tags)) "Tags") 'label)
                              (list tags-content)
                              :collapsed (null tags)))
                           ;; ▸ Logbook (collapsible)
                           (when logbook-entries
                             (jetpacs-collapsible
                              (format "detail-logbook/%s" pos)
                              (jetpacs-text (format "Logbook (%d)" (length logbook-entries)) 'label)
                              (let ((notes (seq-filter (lambda (e) (eq (plist-get e :type) 'note)) logbook-entries))
                                    (states (seq-filter (lambda (e) (eq (plist-get e :type) 'state)) logbook-entries))
                                    (clocks (seq-filter (lambda (e) (eq (plist-get e :type) 'clock)) logbook-entries)))
                                (delq nil
                                      (list
                                       (when notes
                                         (jetpacs-collapsible
                                          (format "detail-logbook-notes/%s" pos)
                                          (jetpacs-text (format "Notes (%d)" (length notes)) 'label)
                                          (delq nil (cl-loop for entry in notes
                                                             for i from 0
                                                             append (list (glasspane-ui--render-logbook-entry entry)
                                                                          (when (< i (1- (length notes))) (jetpacs-divider)))))
                                          :collapsed nil))
                                       (when states
                                         (jetpacs-collapsible
                                          (format "detail-logbook-states/%s" pos)
                                          (jetpacs-text (format "State Changes (%d)" (length states)) 'label)
                                          (delq nil (cl-loop for entry in states
                                                             for i from 0
                                                             append (list (glasspane-ui--render-logbook-entry entry)
                                                                          (when (< i (1- (length states))) (jetpacs-divider)))))
                                          :collapsed t))
                                       (when clocks
                                         (jetpacs-collapsible
                                          (format "detail-logbook-clocks/%s" pos)
                                          (jetpacs-text (format "Clocks (%d)" (length clocks)) 'label)
                                          (delq nil (cl-loop for entry in clocks
                                                             for i from 0
                                                             append (list (glasspane-ui--render-logbook-entry entry)
                                                                          (when (< i (1- (length clocks))) (jetpacs-divider)))))
                                          :collapsed t)))))
                              :collapsed t))
                           ;; ▸ Properties (collapsible — collapsed by default)
                           (glasspane-ui--properties-section entry-props ref pos)
                           (jetpacs-divider))
                          ;; Reader: body (highlighted) and child headings (foldable).
                          ;; Properties are shown above (and for sub-headings
                          ;; through the overflow menu's dialog), so no
                          ;; inline drawers here.
                          (let ((glasspane-org-reader-inline-props nil))
                            (glasspane-org-reader-subtree file pos t))))))))
    (error
     (jetpacs-column
      (jetpacs-text "Error loading heading" 'title)
      (jetpacs-text (error-message-string err) 'body)))))

;; ─── The structured Scheduled/Deadline editor dialog ─────────────────────────

(defun glasspane-ui--set-repeater (type repeater)
  "Rewrite the repeater cookie on the TYPE planning timestamp at point.
TYPE is \"SCHEDULED\" or \"DEADLINE\"; REPEATER like \"+1w\" (nil
removes).  A heading without a TYPE timestamp is a no-op — the dialog
asks for a date first."
  (save-excursion
    (org-back-to-heading t)
    (let ((bound (save-excursion (outline-next-heading) (point))))
      (when (re-search-forward (concat type ":[ \t]*\\([<[]\\)") bound t)
        (let* ((beg (match-beginning 1))
               (close (if (equal (match-string 1) "<") ">" "]"))
               (end (progn (goto-char beg) (search-forward close bound)))
               (ts (buffer-substring-no-properties beg end))
               (stripped (replace-regexp-in-string
                          "[ \t]+[.+]?\\+[0-9]+[hdwmy]" "" ts))
               (new (if repeater
                        (concat (substring stripped 0 -1) " " repeater
                                (substring stripped -1))
                      stripped)))
          (delete-region beg end)
          (goto-char beg)
          (insert new))))))

(defconst glasspane-ui--repeater-choices
  '("none" "+1d" "+1w" "+2w" "+1m" "+3m" "+1y")
  "Repeater cookies offered in the planning dialog.")

(defun glasspane-ui--planning-dialog (ref type)
  "Send the structured TYPE editor dialog for REF.
TYPE is \"SCHEDULED\" or \"DEADLINE\".  Every control dispatches the
ordinary planning actions with a (dialog . TYPE) marker, and those
handlers re-send this dialog after the write so the values on screen
stay live."
  (let* ((marker (jetpacs-org-resolve-ref ref))
         (info (with-current-buffer (marker-buffer marker)
                 (org-with-wide-buffer
                  (goto-char marker)
                  (list (org-get-heading t t t t)
                        (org-entry-get nil type)))))
         (headline (nth 0 info))
         (ts (nth 1 info))
         (date (glasspane-ui--ts-date ts))
         (time (glasspane-ui--ts-time ts))
         (rep (glasspane-ui--ts-repeater ts))
         (scheduled-p (equal type "SCHEDULED"))
         (set-name (if scheduled-p "heading.schedule" "heading.deadline"))
         (mark `(dialog . ,type))
         (when-chip
          (lambda (label when)
            (jetpacs-button label
                         (jetpacs-action set-name
                                      :args (append (list mark `(when . ,when)) ref)
                                      :when-offline "queue")
                         :variant "outlined"))))
    (jetpacs-send-dialog
     (jetpacs-scroll-column
      (jetpacs-text (if scheduled-p "Edit schedule" "Edit deadline") 'title)
      (jetpacs-text headline 'caption)
      (jetpacs-row
       (jetpacs-date-button (or date "Set date")
                         (jetpacs-action set-name :args (cons mark ref))
                         :value date)
       (jetpacs-time-button (or time "Set time")
                         (jetpacs-action (if scheduled-p "heading.schedule-time"
                                        "heading.deadline-time")
                                      :args (cons mark ref))
                         :value time))
      (apply #'jetpacs-flow-row
             (mapcar (lambda (pair) (funcall when-chip (car pair) (cdr pair)))
                     '(("Today" . "+0d") ("+1d" . "+1d")
                       ("+1w" . "+1w") ("+1m" . "+1m"))))
      (jetpacs-text "Repeat" 'label)
      (jetpacs-enum-list (format "planning-rep/%s" type)
                      glasspane-ui--repeater-choices
                      :value (list (or rep "none"))
                      :on-change (jetpacs-action "heading.repeater"
                                              :args (append (list mark `(type . ,type)) ref)))
      (jetpacs-row
       (jetpacs-button "Clear"
                    (jetpacs-action set-name
                                 :args (append (list mark '(clear . t)) ref))
                    :variant "text")
       (jetpacs-spacer :weight 1)
       (jetpacs-button "Done" (jetpacs-action "dialog.dismiss") :variant "text"))))))

(defun glasspane-ui--planning-dialog-resend (args &optional type)
  "Re-send the planning dialog when ARGS carry the (dialog . TYPE) marker."
  (when-let ((marked (alist-get 'dialog args)))
    (ignore-errors
      (glasspane-ui--planning-dialog
       args (or type (and (stringp marked) marked) "SCHEDULED")))))

;; ─── Action Handlers ─────────────────────────────────────────────────────────

(defun glasspane-ui--add-heading (args child)
  "Bridged title prompt, then insert a heading at ARGS's ref.
CHILD non-nil nests one level under the ref heading at the end of its
subtree; otherwise the new heading follows the subtree as a sibling.
On a file-level note (no heading to hang off) both land top-level at
the end of the file."
  (let ((title (string-trim (condition-case nil
                                (read-string "New heading: ")
                              (quit "")))))
    (if (string-empty-p title)
        (jetpacs-shell-notify "Heading cancelled")
      (when (glasspane-ui--at-ref
             args
             (lambda ()
               (if (org-before-first-heading-p)
                   (progn (goto-char (point-max))
                          (unless (bolp) (insert "\n"))
                          (insert "* " title "\n"))
                 (let ((level (org-current-level)))
                   (org-end-of-subtree t t)
                   (unless (bolp) (insert "\n"))
                   (insert (make-string (if child (1+ level) level) ?*)
                           " " title "\n"))))
             t)
        (jetpacs-shell-notify (format "Added \"%s\"" title))))
    (jetpacs-shell-push)))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "heading.tap"
    (lambda (args _)
      ;; ARGS is the ref alist (id/file/pos/headline) the card embedded.
      ;; This push IS the navigation, so it forces the detail view.
      (setq glasspane-ui--detail-ref args)
      (setq glasspane-ui--detail-read-mode t)
      (jetpacs-shell-push nil :switch-to "glasspane.detail"))
    :doc "Open a heading in the detail view."
    :args '((:name ref :type "ref" :required t)))

  (jetpacs-defaction "detail.toggle-read"
    (lambda (_ _)
      (setq glasspane-ui--detail-read-mode (not glasspane-ui--detail-read-mode))
      (jetpacs-shell-push nil :switch-to "glasspane.detail")))

  (jetpacs-defaction "detail.save"
    (lambda (args _)
      (let ((ref (alist-get 'ref args))
            (value (alist-get 'value args)))
        (when (and ref value)
          (condition-case err
              (let* ((marker (jetpacs-org-resolve-ref ref))
                     (buf (marker-buffer marker))
                     (pos (marker-position marker)))
                (with-current-buffer buf
                  (org-with-wide-buffer
                   (goto-char pos)
                   (org-mark-subtree)
                   (delete-region (region-beginning) (region-end))
                   (insert value)
                   (goto-char pos)
                   (setq glasspane-ui--detail-ref (jetpacs-org-heading-ref))
                   (glasspane-org--save-and-invalidate)))
                (setq glasspane-ui--detail-read-mode t)
                (jetpacs-shell-notify "Saved heading"))
            (error
             (jetpacs-shell-notify (format "Save failed: %s" (error-message-string err))))))
        (jetpacs-shell-push))))

  (jetpacs-defaction "heading.back"
    ;; Legacy: detail's back button is now a companion-local view.switch.
    ;; Kept for stale cached UIs.
    (lambda (_ _)
      (setq glasspane-ui--detail-ref nil)
      (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab))))

  (jetpacs-defaction "heading.todo-set"
    (lambda (args _)
      (let* ((state (alist-get 'state args))
             (clear (equal state "")))
        (when (and state
                   (glasspane-ui--at-ref args (lambda () (org-todo (if clear 'none state))) t))
          (jetpacs-shell-notify (if clear "State cleared" (format "State → %s" state)))
          (jetpacs-shell-push))))
    :doc "Set a heading's TODO state; an empty state clears it."
    :args '((:name ref :type "ref" :required t)
            (:name state :type "text" :required t)))

  (jetpacs-defaction "heading.todo-cycle"
    (lambda (args _)
      (when (glasspane-ui--at-ref args
                                  (lambda ()
                                    (org-todo)
                                    (unless (org-get-todo-state)
                                      (org-todo)))
                                  t)
        (let* ((marker (jetpacs-org-resolve-ref args))
               (state (with-current-buffer (marker-buffer marker)
                        (org-with-wide-buffer
                         (goto-char marker)
                         (org-get-todo-state)))))
          (jetpacs-shell-notify (if state (format "State → %s" state) "State cleared"))
          (jetpacs-shell-push))))
    :doc "Cycle a heading through the TODO keyword sequence."
    :args '((:name ref :type "ref" :required t)))

  (jetpacs-defaction "heading.schedule"
    (lambda (args _)
      ;; CLEAR removes the timestamp; otherwise WHEN (relative, e.g. "+1d") or
      ;; VALUE (concrete "YYYY-MM-DD", from the date picker) sets it.  With
      ;; neither, a bridged `org-read-date' dialog asks — the overflow-menu
      ;; path ("+2d", "fri", a concrete date all work).
      (let* ((clear (alist-get 'clear args))
             (date (or (alist-get 'when args) (alist-get 'value args)))
             (prompted (and (not clear)
                            (or (null date) (string-empty-p date)))))
        (when prompted
          (setq date (condition-case nil (org-read-date)
                       (quit nil))))
        (cond
         ((and prompted (null date))
          (jetpacs-shell-notify "Schedule cancelled")
          (jetpacs-shell-push))
         ((cond
           (clear (glasspane-ui--at-ref args (lambda () (org-schedule '(4))) t))
           ((and (stringp date) (not (string-empty-p date)))
            (glasspane-ui--at-ref args (lambda () (org-schedule nil date)) t)))
          (jetpacs-shell-notify (if clear "Schedule cleared" (format "Scheduled %s" date)))
          (glasspane-ui--planning-dialog-resend args "SCHEDULED")
          (jetpacs-shell-push)))))
    :doc "Schedule a heading (WHEN relative like \"+1d\", VALUE a date, CLEAR, or a bridged prompt with neither)."
    :args '((:name ref :type "ref" :required t)
            (:name when :type "text")
            (:name value :type "date")
            (:name clear :type "bool")))

  (jetpacs-defaction "heading.schedule-time"
    ;; Adds/updates the clock time on the existing SCHEDULED date (today if
    ;; none yet). VALUE is the "HH:MM" the time picker injected.
    (lambda (args _)
      (let ((time (alist-get 'value args)))
        (when (and (stringp time) (not (string-empty-p time))
                   (glasspane-ui--at-ref
                    args
                    (lambda ()
                      (let* ((sched (org-entry-get nil "SCHEDULED"))
                             (date (or (glasspane-ui--ts-date sched)
                                       (format-time-string "%Y-%m-%d"))))
                        (org-schedule nil (format "%s %s" date time))))
                    t))
          (jetpacs-shell-notify (format "Scheduled %s" time))
          (glasspane-ui--planning-dialog-resend args "SCHEDULED")
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.deadline-time"
    ;; The deadline sibling of heading.schedule-time, for the dialog's
    ;; time picker.
    (lambda (args _)
      (let ((time (alist-get 'value args)))
        (when (and (stringp time) (not (string-empty-p time))
                   (glasspane-ui--at-ref
                    args
                    (lambda ()
                      (let* ((dl (org-entry-get nil "DEADLINE"))
                             (date (or (glasspane-ui--ts-date dl)
                                       (format-time-string "%Y-%m-%d"))))
                        (org-deadline nil (format "%s %s" date time))))
                    t))
          (jetpacs-shell-notify (format "Deadline %s" time))
          (glasspane-ui--planning-dialog-resend args "DEADLINE")
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.repeater"
    ;; VALUE from the dialog's enum ("none" removes); rewrites the
    ;; repeater cookie in place, preserving the date and time.
    (lambda (args _)
      (let* ((type (or (alist-get 'type args) "SCHEDULED"))
             (raw (alist-get 'value args))
             (value (cond
                     ((vectorp raw) (if (> (length raw) 0) (aref raw 0) "none"))
                     ((and (listp raw) raw) (car raw))
                     ((stringp raw) raw)
                     (t "none")))
             (value (unless (equal value "none") value)))
        (when (glasspane-ui--at-ref
               args (lambda () (glasspane-ui--set-repeater type value)) t)
          (jetpacs-shell-notify (if value (format "Repeats %s" value)
                                  "Repeat removed"))
          (glasspane-ui--planning-dialog-resend args type)
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.planning.show"
    ;; The structured Scheduled/Deadline editor (the overflow-menu path).
    (lambda (args _)
      (condition-case err
          (glasspane-ui--planning-dialog
           args (or (alist-get 'type args) "SCHEDULED"))
        (error
         (jetpacs-shell-notify (format "Planning: %s" (error-message-string err)))
         (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.deadline"
    (lambda (args _)
      ;; Mirrors heading.schedule, including the bridged prompt when no
      ;; date arrives on the wire.
      (let* ((clear (alist-get 'clear args))
             (date (or (alist-get 'when args) (alist-get 'value args)))
             (prompted (and (not clear)
                            (or (null date) (string-empty-p date)))))
        (when prompted
          (setq date (condition-case nil (org-read-date)
                       (quit nil))))
        (cond
         ((and prompted (null date))
          (jetpacs-shell-notify "Deadline cancelled")
          (jetpacs-shell-push))
         ((cond
           (clear (glasspane-ui--at-ref args (lambda () (org-deadline '(4))) t))
           ((and (stringp date) (not (string-empty-p date)))
            (glasspane-ui--at-ref args (lambda () (org-deadline nil date)) t)))
          (jetpacs-shell-notify (if clear "Deadline cleared" (format "Deadline %s" date)))
          (glasspane-ui--planning-dialog-resend args "DEADLINE")
          (jetpacs-shell-push))))))

  (jetpacs-defaction "heading.priority"
    (lambda (args _)
      ;; Empty VALUE means None (remove); otherwise the first char is the
      ;; priority.  ASK (the overflow-menu path) prompts through the bridge
      ;; instead of clearing on the missing value.
      (let* ((val (alist-get 'value args))
             (cancelled nil))
        (when (and (alist-get 'ask args) (null val))
          (setq val (condition-case nil
                        (upcase (string-trim
                                 (read-string "Priority (letter, empty for none): ")))
                      (quit (setq cancelled t) nil))))
        (if cancelled
            (progn (jetpacs-shell-notify "Priority cancelled")
                   (jetpacs-shell-push))
          (let* ((remove (or (null val) (string-empty-p val)))
                 (ok (glasspane-ui--at-ref
                      args
                      (lambda ()
                        (if remove (org-priority 'remove)
                          (org-priority (string-to-char val))))
                      t)))
            (when ok
              (jetpacs-shell-notify (if remove "Priority cleared"
                                      (format "Priority %s" val)))
              (jetpacs-shell-push)))))))

  (jetpacs-defaction "heading.refile"
    ;; Bridged picker over org-refile targets; refiles the whole subtree.
    (lambda (args _)
      (condition-case err
          (let ((marker (jetpacs-org-resolve-ref args)))
            (with-current-buffer (marker-buffer marker)
              (org-with-wide-buffer
               (goto-char marker)
               (let* ((org-refile-targets (or org-refile-targets
                                              '((org-agenda-files :maxlevel . 3))))
                      (targets (org-refile-get-targets))
                      (choice (condition-case nil
                                  (completing-read "Refile to: "
                                                   (mapcar #'car targets) nil t)
                                (quit nil)))
                      (target (and choice (assoc choice targets))))
                 (if (not target)
                     (jetpacs-shell-notify "Refile cancelled")
                   (org-refile nil nil target)
                   (let ((glasspane-org--inhibit-save-refresh t)
                         (save-silently t))
                     (org-save-all-org-buffers))
                   (glasspane-org--vulpea-refresh-file)
                   (jetpacs-org-cache-invalidate 'glasspane)
                   (setq glasspane-ui--detail-ref nil)
                   (jetpacs-shell-notify (format "Refiled to %s" choice))))))
            (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab)))
        (error
         (jetpacs-shell-notify (format "Refile failed: %s"
                                       (error-message-string err)))
         (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.archive"
    ;; Bridged y/n confirm, then org-archive-subtree; saves source + archive.
    (lambda (args _)
      (let ((headline (or (alist-get 'headline args) "this heading")))
        (if (not (yes-or-no-p (format "Archive \"%s\"? " headline)))
            (jetpacs-shell-notify "Archive cancelled")
          (when (glasspane-ui--at-ref
                 args
                 (lambda ()
                   (org-archive-subtree)
                   (let ((glasspane-org--inhibit-save-refresh t)
                         (save-silently t))
                     (org-save-all-org-buffers))
                   (glasspane-org--vulpea-refresh-file)))
            (setq glasspane-ui--detail-ref nil)
            (jetpacs-shell-notify "Archived")))
        (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab)))))

  (jetpacs-defaction "heading.add-note"
    ;; Quick logbook note: bridged prompt, written where org-log-into-drawer
    ;; says notes belong, in org's own note format.
    (lambda (args _)
      (let ((note (string-trim (condition-case nil
                                   (read-string "Note: ")
                                 (quit "")))))
        (if (string-empty-p note)
            (jetpacs-shell-notify "Note cancelled")
          (when (glasspane-ui--at-ref
                 args
                 (lambda ()
                   (let ((org-log-into-drawer t))
                     (goto-char (org-log-beginning t))
                     (insert (format "- Note taken on %s \\\\\n  %s\n"
                                     (format-time-string
                                      (org-time-stamp-format t t))
                                     (replace-regexp-in-string "\n" "\n  " note)))))
                 t)
            (jetpacs-shell-notify "Note added")))
        (jetpacs-shell-push))))

  (jetpacs-defaction "heading.delete"
    ;; Bridged y/n confirm, then the subtree is deleted outright —
    ;; Archive is the recoverable path; this one is for genuine junk.
    (lambda (args _)
      (let ((headline (or (alist-get 'headline args) "this heading")))
        (if (not (yes-or-no-p (format "Delete \"%s\" and its subtree? " headline)))
            (jetpacs-shell-notify "Delete cancelled")
          (when (glasspane-ui--at-ref
                 args
                 (lambda ()
                   (delete-region (point)
                                  (progn (org-end-of-subtree t t) (point))))
                 t)
            (setq glasspane-ui--detail-ref nil)
            (jetpacs-shell-notify "Deleted")))
        (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab)))))

  (jetpacs-defaction "heading.duplicate"
    ;; Copy the whole subtree and insert it right after itself — the
    ;; recurring-meeting-notes idiom (organice's Duplicate).
    (lambda (args _)
      (when (glasspane-ui--at-ref
             args
             (lambda ()
               (let ((subtree (buffer-substring-no-properties
                               (point)
                               (save-excursion (org-end-of-subtree t t) (point)))))
                 (org-end-of-subtree t t)
                 (unless (bolp) (insert "\n"))
                 (insert subtree)))
             t)
        (jetpacs-shell-notify "Duplicated")
        (jetpacs-shell-push))))

  (jetpacs-defaction "heading.add-heading"
    ;; Bridged prompt for the title; the new heading lands as a child at
    ;; the end of this subtree (or top-level at the end of a file-level
    ;; note, where there is no subtree to nest under).
    (lambda (args _) (glasspane-ui--add-heading args t)))

  (jetpacs-defaction "heading.prop-set"
    ;; VALUE arrives injected by the row input's on-submit; NAME rides in
    ;; args. An empty value deletes the property.
    (lambda (args _)
      (let* ((name (alist-get 'name args))
             (raw-val (alist-get 'value args))
             (value (cond
                     ((eq raw-val t) "t")
                     ((memq raw-val '(nil :json-false)) "nil")
                     ((vectorp raw-val) (if (> (length raw-val) 0) (aref raw-val 0) ""))
                     ((listp raw-val) (if raw-val (car raw-val) ""))
                     ((stringp raw-val) (string-trim raw-val))
                     (t (format "%s" raw-val))))
             (ok (and (stringp name) (not (string-empty-p name))
                      (glasspane-ui--at-ref
                       args
                       (lambda ()
                         (if (string-empty-p value)
                             (org-delete-property name)
                           (org-set-property name value)))
                       t))))
        (when ok
          (jetpacs-shell-notify (if (string-empty-p value)
                                    (format "Removed %s" name)
                                  (format "%s → %s" name value)))
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.prop-add"
    ;; The bridged read-string asks for the key; the new (empty) property
    ;; then appears as a row whose value column is ready to fill in.
    (lambda (args _)
      (let ((name (string-trim (condition-case nil
                                   (read-string "New property name: ")
                                 (quit "")))))
        (cond
         ((string-empty-p name) nil)
         ((string-match-p "[: \t]" name)
          (jetpacs-shell-notify "Property names can't contain colons or spaces"))
         ((glasspane-ui--at-ref args
                               (lambda () (org-set-property (upcase name) ""))
                               t)
          (jetpacs-shell-notify (format "Added %s — fill in its value" (upcase name)))))
        (jetpacs-shell-push))))

  (jetpacs-defaction "heading.props.show"
    ;; The sub-heading Properties dialog: the detail reader hides the
    ;; inline drawer, and this overflow-menu action surfaces it as
    ;; editable rows through the same heading.prop-set funnel.
    (lambda (args _)
      (condition-case err
          (let* ((marker (jetpacs-org-resolve-ref args))
                 (buf (marker-buffer marker))
                 (pos (marker-position marker))
                 (info (with-current-buffer buf
                         (org-with-wide-buffer
                          (goto-char pos)
                          (list (org-get-heading t t t t)
                                (org-entry-properties nil 'standard)
                                (buffer-file-name)))))
                 (headline (nth 0 info))
                 (props (nth 1 info))
                 (ref `((file . ,(nth 2 info)) (pos . ,pos)
                        (headline . ,headline))))
            (jetpacs-send-dialog
             (apply #'jetpacs-scroll-column
                    (delq nil
                     (append
                     (list (jetpacs-text "Properties" 'title)
                           (jetpacs-text headline 'caption))
                     (or (mapcar (lambda (kv)
                                   (glasspane-ui--property-row
                                    (car kv) (or (cdr kv) "") ref pos))
                                 props)
                         (list (jetpacs-text "No properties yet." 'caption)))
                     (list
                      (when props
                        (jetpacs-text "Submit an empty value to remove a property."
                                   'caption))
                      (jetpacs-row
                       (jetpacs-button "+ Add property"
                                    (jetpacs-action "heading.prop-add" :args ref)
                                    :variant "text")
                       (jetpacs-spacer :weight 1)
                       (jetpacs-button "Close" (jetpacs-action "dialog.dismiss")
                                    :variant "text"))))))))
        (error
         (jetpacs-shell-notify (format "Properties: %s" (error-message-string err)))
         (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.tags"
    (lambda (args _)
      ;; VALUE arrives from the tag enum-list; ASK (the overflow-menu path)
      ;; prompts through the bridged completing-read-multiple, prefilled
      ;; with the heading's current local tags.
      (let* ((val (alist-get 'value args))
             (cancelled nil))
        (when (and (alist-get 'ask args) (null val))
          (let ((current (condition-case nil
                             (let ((m (jetpacs-org-resolve-ref args)))
                               (with-current-buffer (marker-buffer m)
                                 (org-with-wide-buffer
                                  (goto-char m)
                                  (org-get-tags nil t))))
                           (error nil)))
                (candidates (seq-filter #'stringp
                                        (mapcar (lambda (x) (if (consp x) (car x) x))
                                                org-tag-alist))))
            (setq val (condition-case nil
                          (completing-read-multiple
                           "Tags: " candidates nil nil
                           (when current (concat (string-join current ",") ",")))
                        (quit (setq cancelled t) nil)))))
        (if cancelled
            (progn (jetpacs-shell-notify "Tags cancelled")
                   (jetpacs-shell-push))
          (let* ((tags (cond
                        ((vectorp val) (append val nil))
                        ((listp val) val)
                        ((stringp val) (split-string val "[ \t:,]+" t))
                        (t nil)))
                 (ok (glasspane-ui--at-ref args (lambda () (org-set-tags tags)) t)))
            (when ok
              (jetpacs-shell-notify (if tags (format "Tags: %s" (string-join tags " "))
                                      "Tags cleared"))
              (jetpacs-shell-push)))))))

  (jetpacs-defaction "heading.clock-in"
    (lambda (args _)
      (when (glasspane-ui--at-ref args #'org-clock-in)
        (jetpacs-shell-notify "Clocked in")
        (jetpacs-shell-push "clock"))))

  (jetpacs-defaction "org.link.open"
    ;; A tappable link inside rich org text. Emacs resolves it (id:, file:,
    ;; http(s):, attachment:, …) via the org link machinery; we report the
    ;; outcome back as a snackbar since the action itself happens Emacs-side.
    (lambda (args _)
      (let ((link (alist-get 'link args)))
        (when (and (stringp link) (not (string-empty-p link)))
          (let ((navigated nil))
            (condition-case err
                (progn
                  (org-link-open-from-string link)
                  (jetpacs-shell-notify (format "Opened %s" link))
                  (when (derived-mode-p 'org-mode)
                    (setq glasspane-ui--detail-ref (jetpacs-org-heading-ref))
                    (setq glasspane-ui--detail-read-mode t)
                    (setq navigated t)))
              (error
               (jetpacs-shell-notify
                (format "Couldn't open %s: %s" link (error-message-string err)))))
            (if navigated
                (jetpacs-shell-push nil :switch-to "glasspane.detail")
              (jetpacs-shell-push)))))))

  (jetpacs-defaction "heading.reorder"
    (lambda (args _)
      (let* ((file      (alist-get 'file args))
             (from-pos  (alist-get 'from_pos args))
             (after-pos (alist-get 'after_pos args))  ;; 0 or nil = move to top
             (new-level (alist-get 'new_level args)))
        (when (and file from-pos (file-readable-p file))
          (with-current-buffer (find-file-noselect file)
            (org-with-wide-buffer
             (goto-char from-pos)
             (org-back-to-heading t)
             (let* ((from-level (org-outline-level))
                    (subtree-beg (point))
                    (subtree-end (save-excursion (org-end-of-subtree t t) (point)))
                    (subtree-size (- subtree-end subtree-beg)))
               ;; Cut the subtree
               (org-cut-subtree)
               ;; Navigate to the insertion point
               (if (and after-pos (> after-pos 0))
                   (let ((target (if (> after-pos from-pos)
                                     (- after-pos subtree-size)
                                   after-pos)))
                     (goto-char (min target (point-max)))
                     (org-back-to-heading t)
                     (org-end-of-subtree t t))
                 ;; Move to top of file (before first heading)
                 (goto-char (point-min))
                 (when (re-search-forward org-heading-regexp nil t)
                   (goto-char (line-beginning-position))))
               ;; Paste at the new level (or original level if nil)
               (org-paste-subtree (or new-level from-level)))))
          (glasspane-org--save-and-invalidate (find-file-noselect file))
          ;; Views-originated drags pass `view' to land back where the
          ;; drag happened; legacy templates (no arg) keep the editor.
          (jetpacs-shell-push nil :switch-to (or (alist-get 'view args) "edit")))))))

(defun glasspane-ui--org-editor-actions (file)
  "Reader/refile toggles, add-heading, and the properties dialog for org FILE."
  (when (glasspane-ui--org-file-p file)
    (delq nil
          (list
           (when glasspane-ui--files-read-mode
             (jetpacs-icon-button
              "post_add"
              (jetpacs-action "file.add-heading" :args `((file . ,file))
                           :when-offline "drop")
              :content-description "Add Heading"))
           (when glasspane-ui--files-read-mode
             (jetpacs-icon-button
              (if glasspane-ui--files-refile-mode "visibility" "swap_vert")
              (jetpacs-action "files.toggle-refile")
              :content-description
              (if glasspane-ui--files-refile-mode "Reader" "Refile")))
           (jetpacs-icon-button
            (if glasspane-ui--files-read-mode "edit" "visibility")
            (jetpacs-action "files.toggle-read")
            :content-description
            (if glasspane-ui--files-read-mode "Edit" "Read"))
           (jetpacs-icon-button
            "tune"
            (jetpacs-action "files.properties.show" :args `((file . ,file)))
            :content-description "Properties")))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "file.add-heading"
    ;; The file-view sibling of heading.add-heading: bridged title
    ;; prompt, then a top-level heading appended at the end of FILE.
    (lambda (args _)
      (let ((file (alist-get 'file args)))
        (if (not (and (stringp file) (file-writable-p file)))
            (jetpacs-shell-notify "Can't add a heading — file not writable")
          (let ((title (string-trim (condition-case nil
                                        (read-string "New heading: ")
                                      (quit "")))))
            (if (string-empty-p title)
                (jetpacs-shell-notify "Heading cancelled")
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char (point-max))
                 (unless (bolp) (insert "\n"))
                 (insert "* " title "\n"))
                (glasspane-org--save-and-invalidate))
              (jetpacs-shell-notify (format "Added \"%s\"" title)))))
        (jetpacs-shell-push))))

  (jetpacs-defaction "files.properties.show"
    (lambda (args _)
      (let ((file (alist-get 'file args)))
        (if (not (and file (stringp file) (file-readable-p file)))
            (jetpacs-shell-notify (format "Cannot open properties: %s" (or file "no file")))
          (condition-case err
              (let* ((buf (or (get-file-buffer file) (find-file-noselect file)))
                     (kwds (with-current-buffer buf (org-collect-keywords '("TITLE" "CATEGORY" "FILETAGS" "TODO" "SEQ_TODO" "TYP_TODO" "STARTUP" "AUTHOR" "EMAIL" "DATE" "ARCHIVE"))))
                     (title (car (alist-get "TITLE" kwds nil nil #'equal)))
                     (category (car (alist-get "CATEGORY" kwds nil nil #'equal)))
                     (filetags-str (car (alist-get "FILETAGS" kwds nil nil #'equal)))
                     (filetags (when filetags-str (split-string filetags-str ":" t "[ \t\n\r]+")))
                     (available-tags (seq-uniq (append filetags (mapcar (lambda (x) (if (consp x) (car x) x)) org-tag-alist))))
                     (todo-str (or (car (alist-get "TODO" kwds nil nil #'equal))
                                   (car (alist-get "SEQ_TODO" kwds nil nil #'equal))
                                   (car (alist-get "TYP_TODO" kwds nil nil #'equal))))
                     (todo-parts (if todo-str (split-string todo-str "|") nil))
                     (todo-active (if todo-str (mapconcat #'identity (split-string (car todo-parts) "[ \t]+" t) ", ") ""))
                     (todo-finished (if (and todo-parts (cadr todo-parts))
                                        (mapconcat #'identity (split-string (cadr todo-parts) "[ \t]+" t) ", ")
                                      ""))
                     (startup (car (alist-get "STARTUP" kwds nil nil #'equal)))
                     (author (car (alist-get "AUTHOR" kwds nil nil #'equal)))
                     (email (car (alist-get "EMAIL" kwds nil nil #'equal)))
                     (date (car (alist-get "DATE" kwds nil nil #'equal)))
                     (archive (car (alist-get "ARCHIVE" kwds nil nil #'equal))))
                (jetpacs-send-dialog
                 (jetpacs-scroll-column
                  (jetpacs-text "File Properties" 'title)
                  (jetpacs-text (file-name-nondirectory file) 'caption)
                  (jetpacs-text-input "file-prop-title" :label "Title" :value title :single-line t)
                  (jetpacs-text-input "file-prop-category" :label "Category" :value category :single-line t)
                  (jetpacs-text "File Tags" 'caption nil nil nil nil 8)
                  (jetpacs-enum-list "file-prop-tags" available-tags
                                  :value filetags :multi-select t :allow-add t)
                  (jetpacs-text "TODO Sequence" 'caption nil nil nil nil 8)
                  (jetpacs-text-input "file-prop-todo-active" :label "Active States" :value todo-active :single-line t)
                  (jetpacs-text-input "file-prop-todo-finished" :label "Finished States" :value todo-finished :single-line t)
                  (jetpacs-text "Metadata" 'caption nil nil nil nil 8)
                  (jetpacs-text-input "file-prop-author" :label "Author" :value author :single-line t)
                  (jetpacs-text-input "file-prop-email" :label "Email" :value email :single-line t)
                  (jetpacs-text-input "file-prop-date" :label "Date" :value date :single-line t)
                  (jetpacs-text "Options" 'caption nil nil nil nil 8)
                  (jetpacs-text-input "file-prop-startup" :label "Startup" :value startup :single-line t)
                  (jetpacs-text-input "file-prop-archive" :label "Archive" :value archive :single-line t)
                  (jetpacs-row
                   (jetpacs-spacer :weight 1)
                   (jetpacs-button "Cancel" (jetpacs-action "dialog.dismiss") :variant "text")
                   (jetpacs-spacer :width 8)
                   (jetpacs-button "Save" (jetpacs-action "files.properties.save" :args `((file . ,file))))))))
            (error
             (jetpacs-shell-notify (format "Properties error: %s" (error-message-string err)))))))))

  (jetpacs-defaction "files.properties.save"
    (lambda (args _)
      (let* ((file (alist-get 'file args))
             (buf (or (get-file-buffer file) (find-file-noselect file)))
             (title (jetpacs-ui-state "file-prop-title"))
             (category (jetpacs-ui-state "file-prop-category"))
             (tags-val (jetpacs-ui-state "file-prop-tags"))
             (tags (cond
                    ((vectorp tags-val) (append tags-val nil))
                    ((listp tags-val) tags-val)
                    (t nil)))
             (todo-active (jetpacs-ui-state "file-prop-todo-active"))
             (todo-finished (jetpacs-ui-state "file-prop-todo-finished"))
             (todo-str (let ((a (when (stringp todo-active) (string-join (split-string todo-active "[ \t]*,[ \t]*" t) " ")))
                             (f (when (stringp todo-finished) (string-join (split-string todo-finished "[ \t]*,[ \t]*" t) " "))))
                         (if (and a f (not (string-empty-p a)) (not (string-empty-p f)))
                             (concat a " | " f)
                           (or a f))))
             (startup (jetpacs-ui-state "file-prop-startup"))
             (author (jetpacs-ui-state "file-prop-author"))
             (email (jetpacs-ui-state "file-prop-email"))
             (date (jetpacs-ui-state "file-prop-date"))
             (archive (jetpacs-ui-state "file-prop-archive")))
        (with-current-buffer buf
          (save-excursion
            (save-restriction
              (widen)
              (let ((update-kwd (lambda (kwd val)
                                  (goto-char (point-min))
                                  (if (re-search-forward (format "^[ \t]*#\\+%s:[ \t]*\\(.*\\)$" kwd) nil t)
                                      (if (and val (not (string-empty-p val)))
                                          (replace-match val t t nil 1)
                                        (delete-region (line-beginning-position) (min (1+ (line-end-position)) (point-max))))
                                    (when (and val (not (string-empty-p val)))
                                      (goto-char (point-min))
                                      ;; If inserting something else than TITLE and a TITLE exists, insert after it.
                                      (when (not (equal kwd "TITLE"))
                                        (when (re-search-forward "^[ \t]*#\\+TITLE:.*$" nil t)
                                          (forward-line 1)))
                                      (insert (format "#+%s: %s\n" kwd val)))))))
                (funcall update-kwd "TITLE" title)
                (funcall update-kwd "FILETAGS" (when tags (concat ":" (string-join tags ":") ":")))
                (funcall update-kwd "CATEGORY" category)
                (funcall update-kwd "TODO" todo-str)
                (funcall update-kwd "STARTUP" startup)
                (funcall update-kwd "AUTHOR" author)
                (funcall update-kwd "EMAIL" email)
                (funcall update-kwd "DATE" date)
                (funcall update-kwd "ARCHIVE" archive))
              (glasspane-org--save-and-invalidate))))
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-push)))))

(provide 'glasspane-detail)
