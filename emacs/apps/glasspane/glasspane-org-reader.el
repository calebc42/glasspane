;;; glasspane-org-reader.el --- Foldable org outline renderer for Jetpacs -*- lexical-binding: t; -*-

;; Renders an org buffer (or a single subtree) into a tree of Jetpacs widgets:
;; each heading becomes an `jetpacs-collapsible' whose header is the org-highlighted
;; heading line and whose children are an optional (collapsed) PROPERTIES drawer,
;; the heading's own body as highlighted org text, and its child headings —
;; recursively. Folding is resolved entirely on the device (see the `collapsible'
;; widget), so the whole subtree is shipped once and folds without a round-trip.
;;
;; Two entry points feed the UI layer (glasspane-ui):
;;   `glasspane-org-reader-file'    — whole file, every top-level heading foldable
;;   `glasspane-org-reader-subtree' — one heading's content inline + children foldable

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'glasspane-org-rich)

(defcustom glasspane-org-reader-max-headings 400
  "Cap on headings rendered in one reader pass, to bound very large files."
  :type 'integer :group 'jetpacs)

(defcustom glasspane-org-reader-show-deadline t
  "Show each heading's DEADLINE date on its reader header (red when overdue)."
  :type 'boolean :group 'jetpacs)

(defcustom glasspane-org-reader-show-clocked nil
  "Show each heading's total clocked time on its reader header.
Off by default: computing the sums adds an `org-clock-sum' pass over
the file on every render."
  :type 'boolean :group 'jetpacs)

;; ─── Parsing ───────────────────────────────────────────────────────────────────

(defun glasspane-org-reader--record (pos next)
  "Build a record for the heading at POS, whose body ends at NEXT.
Returns a plist with :level :pos :line :props :body :body-start.
:body-start is the real-buffer position of the first non-blank char
in the body, used to map temp-buffer positions back for interactive
elements (checkboxes)."
  (save-excursion
    (goto-char pos)
    (let* ((comps (org-heading-components))
           (level (or (nth 0 comps) 1))
           (todo (nth 2 comps))
           (priority (nth 3 comps))
           (title (or (nth 4 comps) ""))
           (tags (ignore-errors (org-get-tags pos t)))
           (done (and todo (member todo org-done-keywords) t))
           (deadline (and glasspane-org-reader-show-deadline
                          (ignore-errors (org-entry-get pos "DEADLINE"))))
           (clocked (and glasspane-org-reader-show-clocked
                         (get-text-property pos :org-clock-minutes)))
           (line (buffer-substring-no-properties
                  (line-beginning-position) (line-end-position)))
           (props (ignore-errors (org-entry-properties pos 'standard)))
           (body-info
            (progn
              (goto-char pos)
              ;; No FULL arg: skip only planning + PROPERTIES (shown as
              ;; their own section).  LOGBOOK and other drawers stay in
              ;; the body, where the rich renderer folds them.
              (ignore-errors (org-end-of-meta-data))
              (let* ((b (min (point) next))
                     (raw (buffer-substring-no-properties b next))
                     (trimmed (string-trim-left raw "\\(?:[ \t]*[\n\r]\\)+"))
                     (trim-count (- (length raw) (length trimmed))))
                (list (string-trim-right trimmed) (+ b trim-count)))))
           (body (car body-info))
           (body-start (cadr body-info)))
      (list :level level :pos pos :line line :props props
            :todo todo :priority (and priority (char-to-string priority))
            :title title :tags tags :done done
            :deadline deadline :clocked clocked
            :body body :body-start body-start))))

(defun glasspane-org-reader--collect (beg end include-first)
  "Collect heading records between BEG and END.
INCLUDE-FIRST non-nil includes the heading at BEG (used for subtrees)."
  (let (positions records)
    (save-excursion
      (goto-char beg)
      (when (and include-first (org-at-heading-p))
        (push (line-beginning-position) positions)
        (end-of-line))                  ; don't re-match this heading below
      (while (re-search-forward org-heading-regexp end t)
        (push (line-beginning-position) positions)))
    (setq positions (nreverse positions))
    (cl-loop for cell on positions
             for pos = (car cell)
             for next = (or (cadr cell) end)
             do (push (glasspane-org-reader--record pos next) records))
    (nreverse records)))

(defun glasspane-org-reader--build-tree (records)
  "Nest flat RECORDS into a tree by :level. Each node gains a :children list."
  (let* ((root (list :level 0 :children nil))
         (stack (list root)))
    (dolist (rec records)
      (let ((node (append rec (list :children nil)))
            (level (plist-get rec :level)))
        (while (>= (plist-get (car stack) :level) level)
          (pop stack))
        (let ((parent (car stack)))
          (plist-put parent :children
                     (append (plist-get parent :children) (list node))))
        (push node stack)))
    (plist-get root :children)))

;; ─── Rendering ──────────────────────────────────────────────────────────────────

(defun glasspane-org-reader--props-node (props file pos)
  "A collapsed PROPERTIES drawer node for PROPS (an alist of KEY . VALUE)."
  (let ((text (mapconcat (lambda (kv) (format ":%s: %s" (car kv) (cdr kv)))
                         props "\n")))
    (jetpacs-collapsible (format "fold-props/%s/%s" file pos)
                      (jetpacs-text "PROPERTIES" 'label)
                      (list (jetpacs-text text 'mono))
                      :collapsed t)))

(defvar glasspane-org-reader-inline-props t
  "When nil, PROPERTIES drawers are not rendered inline under headings.
The detail view binds this off: its per-heading overflow menu offers
the drawer as an editable dialog (heading.props.show) instead.")

(defun glasspane-org-reader--content-nodes (n file &optional skip-props)
  "Inline content nodes for tree node N: PROPERTIES drawer, body, child headings.
When SKIP-PROPS is non-nil, omit the PROPERTIES drawer (used when the
detail view already shows properties in its own section)."
  (let ((pos (plist-get n :pos))
        (props (plist-get n :props))
        (body (plist-get n :body))
        (body-start (plist-get n :body-start))
        (children (plist-get n :children)))
    (delq nil
          (append
           (when (and props (not skip-props) glasspane-org-reader-inline-props)
             (list (glasspane-org-reader--props-node props file pos)))
           (when (and body (not (string-empty-p body)))
             ;; Native rich text (emphasis, links, #tags) instead of the
             ;; monospace org highlighter; code/tables still fall back to it.
             ;; file + offset enable interactive checkboxes.  SKIP-PROPS
             ;; marks the detail view, which shows LOGBOOK as its own
             ;; structured section — suppress the raw drawer there.
             (let ((glasspane-org-rich--skip-drawers
                    (and skip-props '("LOGBOOK"))))
               (glasspane-org-rich-body body (and file (file-name-directory file))
                                        file (when body-start (1- body-start)))))
           (mapcar (lambda (c) (glasspane-org-reader--heading-node c file)) children)))))

(defun glasspane-org-reader--clocked-in-p (pos)
  "Whether the heading at POS in the current buffer is the clocked task."
  (and (bound-and-true-p org-clock-hd-marker)
       (marker-buffer org-clock-hd-marker)
       (eq (marker-buffer org-clock-hd-marker) (current-buffer))
       (save-excursion
         (goto-char pos)
         (= (line-beginning-position)
            (save-excursion (goto-char org-clock-hd-marker)
                            (line-beginning-position))))))

(defun glasspane-org-reader-heading-menu (ref clocked-in)
  "The per-heading overflow menu: quick actions without the detail drill-in.
Schedule/Deadline/Priority/Tags arrive with no value, which the
handlers answer with a bridged prompt dialog."
  (jetpacs-menu
   (list
    (jetpacs-menu-item "Open" (jetpacs-action "heading.tap" :args ref)
                    :icon "open_in_new")
    (if clocked-in
        (jetpacs-menu-item "Clock Out" (jetpacs-action "org.clock.out")
                        :icon "timer_off")
      (jetpacs-menu-item "Clock In"
                      (jetpacs-action "heading.clock-in" :args ref
                                   :when-offline "drop")
                      :icon "timer"))
    (jetpacs-menu-item "Priority…"
                    (jetpacs-action "heading.priority"
                                 :args (cons '(ask . t) ref)
                                 :when-offline "drop")
                    :icon "flag")
    (jetpacs-menu-item "Schedule…"
                    (jetpacs-action "heading.planning.show"
                                 :args (cons '(type . "SCHEDULED") ref)
                                 :when-offline "drop")
                    :icon "event")
    (jetpacs-menu-item "Deadline…"
                    (jetpacs-action "heading.planning.show"
                                 :args (cons '(type . "DEADLINE") ref)
                                 :when-offline "drop")
                    :icon "event_busy")
    (jetpacs-menu-item "Tags…"
                    (jetpacs-action "heading.tags"
                                 :args (cons '(ask . t) ref)
                                 :when-offline "drop")
                    :icon "label")
    (jetpacs-menu-item "Properties"
                    (jetpacs-action "heading.props.show" :args ref
                                 :when-offline "drop")
                    :icon "data_object")
    (jetpacs-menu-item "Duplicate"
                    (jetpacs-action "heading.duplicate" :args ref
                                 :when-offline "queue")
                    :icon "content_copy"))))

(defconst glasspane-org-reader--todo-color "#EF5350"
  "Span color for open TODO keywords in reader headers.")
(defconst glasspane-org-reader--done-color "#66BB6A"
  "Span color for done keywords in reader headers.")
(defconst glasspane-org-reader--priority-color "#F57C00"
  "Span color for priority cookies (matches the agenda cards).")

(defconst glasspane-org-reader--overdue-color "#EF5350"
  "Span color for overdue deadline badges.")

(defun glasspane-org-reader--meta-line (n)
  "The deadline/clocked badge line for tree node N, or nil.
The deadline date shows in the priority orange, switching to red once
overdue; the clocked total renders as h:mm."
  (let* ((deadline (plist-get n :deadline))
         (ddate (and (stringp deadline)
                     (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" deadline)
                     (match-string 0 deadline)))
         (overdue (and ddate (not (plist-get n :done))
                       (string< ddate (format-time-string "%Y-%m-%d"))))
         (mins (plist-get n :clocked))
         (spans (delq nil
                      (list
                       (when ddate
                         (jetpacs-span (concat "Deadline " ddate)
                                    :bold overdue
                                    :color (if overdue
                                               glasspane-org-reader--overdue-color
                                             glasspane-org-reader--priority-color)))
                       (when (and (numberp mins) (> mins 0))
                         (jetpacs-span (format "%s%d:%02d clocked"
                                            (if ddate "  ·  " "")
                                            (/ mins 60) (% mins 60))))))))
    (when spans (jetpacs-rich-text spans))))

(defun glasspane-org-reader--heading-header (n)
  "The structured header for tree node N.
Todo keyword and priority render as colored spans, the title strikes
through when done, tags become tappable chips, and deadline/clocked
badges follow on their own line — instead of the raw org heading
line.  Falls back to org markup when the heading didn't parse (no
title)."
  (let ((todo (plist-get n :todo))
        (priority (plist-get n :priority))
        (title (plist-get n :title))
        (tags (plist-get n :tags))
        (done (plist-get n :done)))
    (if (string-empty-p (or title ""))
        (jetpacs-markup (plist-get n :line) :syntax "org")
      (let* ((line (jetpacs-rich-text
                    (delq nil
                          (list
                           (when todo
                             (jetpacs-span (concat todo " ") :bold t
                                        :color (if done
                                                   glasspane-org-reader--done-color
                                                 glasspane-org-reader--todo-color)))
                           (when priority
                             (jetpacs-span (format "[#%s] " priority) :bold t
                                        :color glasspane-org-reader--priority-color))
                           (if done
                               (jetpacs-span title :strike t)
                             (jetpacs-span title))))))
             (meta (glasspane-org-reader--meta-line n))
             (tag-row (when tags
                        (apply #'jetpacs-flow-row
                               (mapcar (lambda (tg)
                                         (jetpacs-assist-chip
                                          tg :on-tap (jetpacs-action
                                                      "search.by-tag"
                                                      :args `((tag . ,tg)))))
                                       tags)))))
        (if (or meta tag-row)
            (apply #'jetpacs-column (delq nil (list line meta tag-row)))
          line)))))

(defun glasspane-org-reader--heading-node (n file)
  "Render tree node N (and its subtree) to a foldable `jetpacs-collapsible'.
Long-pressing the header opens the heading detail view when FILE is
available; the trailing overflow menu carries the quick actions."
  (let* ((pos (plist-get n :pos))
         (ref (when file
                `((file . ,file) (pos . ,pos) (headline . ""))))
         (header (glasspane-org-reader--heading-header n)))
    (jetpacs-collapsible (format "fold/%s/%s" file pos)
                      (if ref
                          (jetpacs-row
                           (jetpacs-box (list header) :weight 1)
                           (glasspane-org-reader-heading-menu
                            ref (glasspane-org-reader--clocked-in-p pos)))
                        header)
                      (glasspane-org-reader--content-nodes n file)
                      :on-long-tap (when ref
                                     (jetpacs-action "heading.tap" :args ref))
                      :on-swipe (when ref
                                  (jetpacs-action "heading.todo-cycle" :args ref)))))

;; ─── Entry points ───────────────────────────────────────────────────────────────

(defun glasspane-org-reader--cap (records)
  "Truncate RECORDS to `glasspane-org-reader-max-headings'."
  (if (> (length records) glasspane-org-reader-max-headings)
      (cl-subseq records 0 glasspane-org-reader-max-headings)
    records))

(defun glasspane-org-reader-file (file)
  "Render the whole org FILE to a list of foldable widget nodes.
Content before the first heading is not shown."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (when glasspane-org-reader-show-clocked
         (ignore-errors (org-clock-sum)))
       (let* ((records (glasspane-org-reader--cap
                        (glasspane-org-reader--collect (point-min) (point-max) nil)))
              (tree (glasspane-org-reader--build-tree records)))
         (mapcar (lambda (n) (glasspane-org-reader--heading-node n file)) tree))))))

(defun glasspane-org-reader-subtree (file pos &optional skip-props)
  "Render the org subtree at POS in FILE.
The drilled-into heading's own PROPERTIES/body render inline (its title is
already in the top bar); its child headings render as foldable sections.
Returns a list of widget nodes (possibly empty).
When SKIP-PROPS is non-nil, the top-level PROPERTIES drawer is omitted."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (when glasspane-org-reader-show-clocked
         (ignore-errors (org-clock-sum)))
       (goto-char (min pos (point-max)))
       (unless (org-at-heading-p) (ignore-errors (org-back-to-heading t)))
       (let* ((beg (point))
              (end (save-excursion (org-end-of-subtree t t)))
              (records (glasspane-org-reader--cap
                        (glasspane-org-reader--collect beg end t)))
              (tree (glasspane-org-reader--build-tree records))
              (root (car tree)))
         (when root
           (glasspane-org-reader--content-nodes root file skip-props)))))))

(defun glasspane-org-reader-refile-list (file)
  "Render all headings in FILE as a flat reorderable item list.
Returns a single `jetpacs-reorderable-list' node for refile mode."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (let* ((records (glasspane-org-reader--cap
                        (glasspane-org-reader--collect (point-min) (point-max) nil)))
              (items (mapcar (lambda (r)
                               `((label . ,(plist-get r :line))
                                 (level . ,(plist-get r :level))
                                 (pos   . ,(plist-get r :pos))
                                 (file  . ,file)))
                             records)))
         (jetpacs-reorderable-list
          items
          :on-reorder (jetpacs-action "heading.reorder"
                                   :args `((file . ,file)))))))))

(when (fboundp 'jetpacs-settings-register-section)
  (with-jetpacs-owner "glasspane"
    (jetpacs-settings-register-section
     "Reader"
     '((glasspane-org-reader-show-deadline :label "Deadline on headings")
       (glasspane-org-reader-show-clocked :label "Clocked time on headings")))))

(provide 'glasspane-org-reader)
;;; glasspane-org-reader.el ends here
