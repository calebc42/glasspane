;;; jetpacs-tablist.el --- Generic tabulated-list renderer (Tier 0.5) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Tier 0.5: `tabulated-list-mode' is a declarative UI framework — columns
;; come from `tabulated-list-format', rows carry their id and entry as text
;; properties — so ONE renderer covers every derivative (package menu,
;; process list, bookmarks, timers, and anything built on it).
;;
;; Registered as a skin for `tabulated-list-mode', so any tabulated-list
;; derivative renders as sortable cards instead of monospace text.  Row taps
;; reuse the `emacs.buffer.act' seam (push button / RET at position), so
;; activation adds no new dispatch surface; the only new wire actions are
;; `tablist.sort' and `tablist.refresh', both validated against the buffer's
;; own column format.
;;
;; Modes specialize without replacing the walk, through three hook alists
;; (header, row, filter).
;;
;; Rung JC-2 of docs/PLAN-jetpacs-consumers.md.  Ported from poc-v1 with the
;; format-6 drift applied and three conformance changes:
;;
;; - Row positions are recorded in JC-1's exposure table.  This skin builds
;;   its own rows instead of walking the Tier-0 renderer, so without that
;;   every row tap would be refused by `emacs.buffer.act''s SPEC 23.1 check.
;; - The actions derive SPEC 14.4 statuses, and `revert-buffer' is called
;;   noconfirm so it cannot prompt inside the dispatch extent (decision D2).
;; - Optional node types degrade to the Core Node Set when unadvertised
;;   (SPEC 16.2).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)

;; --- Configuration and host seams -------------------------------------------

(defcustom jetpacs-tablist-max-rows 100
  "Maximum rows rendered from one tabulated-list buffer.
Large lists (a full MELPA package menu is thousands of rows) are capped
with a trailing note; skins narrow with filters rather than paging."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-tablist-view-buffer-function nil
  "Function of a buffer name that navigates the companion to that buffer.
nil (the default) is the SENTINEL the navigate module's seam seizure
tests for — a lambda default would make \='unset\=' indistinguishable
from a Tier-1's registration, and the seizure would clobber it.")

;; --- Per-mode skin hooks -----------------------------------------------------

(defvar jetpacs-tablist-header-functions nil
  "Alist of (MODE . FN); FN of the buffer returns extra header nodes.
Rendered between the title row and the sort chips.  Nearest derived mode
wins, like `jetpacs-render-buffer-functions'.")

(defvar jetpacs-tablist-row-functions nil
  "Alist of (MODE . FN); FN of (ID ENTRY POS) returns a row node, or nil
to fall back to the generic row.  Called with the list buffer current.")

(defvar jetpacs-tablist-filter-functions nil
  "Alist of (MODE . FN); FN of (ID ENTRY) says whether to keep a row.
Filtering runs before the row cap, so narrowed views see deep rows.")

(defun jetpacs-tablist--mode-fn (alist)
  "The nearest-derived-mode function from ALIST for the current buffer."
  (cl-loop for (mode . fn) in alist
           when (derived-mode-p mode) return fn))

;; --- Reading the list --------------------------------------------------------

(defun jetpacs-tablist--rows ()
  "Collect (POS ID ENTRY) for each printed row of the current buffer.
Walking the printed buffer (rather than `tabulated-list-entries', which
may be a function) respects the mode's current sort and filtering."
  (save-excursion
    (goto-char (point-min))
    (let (rows)
      (while (not (eobp))
        (let ((id (tabulated-list-get-id))
              (entry (tabulated-list-get-entry)))
          (when (and id entry)
            (push (list (point) id entry) rows)))
        (forward-line 1))
      (nreverse rows))))

(defun jetpacs-tablist-col-string (col)
  "The display string of entry column COL (a string or (LABEL . PROPS))."
  (cond ((stringp col) col)
        ((consp col) (format "%s" (car col)))
        (t (format "%s" col))))

(defun jetpacs-tablist-entry-col (entry name)
  "ENTRY's column named NAME per the current buffer's format, or nil.
Part of the skin-author API: row/filter hooks read a column by its header
label instead of a fragile index."
  (let ((i (cl-position name tabulated-list-format :key #'car :test #'equal)))
    (and i (< i (length entry))
         (jetpacs-tablist-col-string (aref entry i)))))

;; --- Rendering ---------------------------------------------------------------

(defun jetpacs-tablist--sort-chips ()
  "A chip row for the sortable columns of the current buffer, or nil.
Nil when `chip' or `flow_row' is unadvertised (SPEC 16.2): sorting is
chrome, and a Core-only Companion is better served by the rows alone."
  (when (and (jetpacs-node-advertised-p "chip")
             (jetpacs-node-advertised-p "flow_row"))
    (let* ((key (car tabulated-list-sort-key))
           (desc (cdr tabulated-list-sort-key))
           (chips (cl-loop for col across tabulated-list-format
                           for name = (car col)
                           when (nth 2 col)   ; sortable
                           collect (jetpacs-chip
                                    (if (equal name key)
                                        (concat name (if desc " ↓" " ↑"))
                                      name)
                                    ;; format 6: booleans are t / :json-false
                                    :selected (jetpacs-bool (equal name key))
                                    :on-tap (jetpacs-action
                                             "tablist.sort"
                                             :args (list :buffer (buffer-name)
                                                         :column name))))))
      (when chips (apply #'jetpacs-flow-row chips)))))

(defun jetpacs-tablist--default-row (buf-name pos entry)
  "Generic row card: first column as title, the rest as a caption.
Records POS in the exposure table — this skin bypasses the Tier-0 walk,
so nothing else would make POS a legitimate `emacs.buffer.act' target."
  (jetpacs-buffer-expose buf-name pos "emacs.buffer.act")
  (let* ((cols (mapcar #'jetpacs-tablist-col-string (append entry nil)))
         (title (or (car cols) ""))
         (rest (string-join (cl-remove-if #'string-empty-p (cdr cols))
                            "  ·  "))
         (action (jetpacs-action "emacs.buffer.act"
                                 :args (list :buffer buf-name :pos pos)))
         (body (apply #'jetpacs-column
                      (delq nil
                            (list (jetpacs-text title :style "label")
                                  (unless (string-empty-p rest)
                                    (jetpacs-text rest :style "caption")))))))
    (if (jetpacs-node-advertised-p "card")
        (jetpacs-card body :on-tap action)
      ;; Core fallback: keep the row visible AND tappable.
      (jetpacs-column body (jetpacs-button title action)))))

(defun jetpacs-tablist-render (buf)
  "Tier-1 skin: BUF (a tabulated-list buffer) as sortable, tappable cards."
  (with-current-buffer buf
    (let* ((name (buffer-name))
           (header-fn (jetpacs-tablist--mode-fn jetpacs-tablist-header-functions))
           (row-fn (jetpacs-tablist--mode-fn jetpacs-tablist-row-functions))
           (filter-fn (jetpacs-tablist--mode-fn jetpacs-tablist-filter-functions))
           (rows (jetpacs-tablist--rows))
           (rows (if filter-fn
                     (cl-remove-if-not
                      (lambda (r) (funcall filter-fn (nth 1 r) (nth 2 r)))
                      rows)
                   rows))
           (total (length rows))
           (shown (cl-subseq rows 0 (min total jetpacs-tablist-max-rows)))
           (refresh (jetpacs-action "tablist.refresh"
                                    :args (list :buffer name))))
      ;; This render supersedes the last one for this buffer.
      (jetpacs-buffer-forget-exposed name)
      (append
       (list (jetpacs-row
              (jetpacs-with-attrs
               (jetpacs-box (jetpacs-text (format "%d rows" total)
                                          :style "caption"))
               :weight 1)
              (if (jetpacs-node-advertised-p "icon_button")
                  (jetpacs-icon-button "refresh" refresh
                                       :content-description "Refresh list")
                (jetpacs-button "Refresh" refresh))))
       (when header-fn (funcall header-fn buf))
       (let ((chips (jetpacs-tablist--sort-chips)))
         (and chips (list chips)))
       (mapcar (lambda (r)
                 (or (and row-fn
                          (funcall row-fn (nth 1 r) (nth 2 r) (nth 0 r)))
                     (jetpacs-tablist--default-row name (nth 0 r) (nth 2 r))))
               shown)
       (when (> total (length shown))
         (list (jetpacs-text
                (format "Showing %d of %d — narrow with a filter."
                        (length shown) total)
                :style "caption")))))))

(jetpacs-render-buffer-register 'tabulated-list-mode #'jetpacs-tablist-render)

;; --- Actions -----------------------------------------------------------------

(defun jetpacs-tablist--refresh-view (params)
  "Re-push the surface the event came from, through the JC-1 seam.
The seam takes the originating surface as of JC-1: under decision D1
every owner has its own surface, so a zero-arg call would push the
wrong one."
  (when (functionp jetpacs-buffer-refresh-function)
    (funcall jetpacs-buffer-refresh-function (plist-get params :surface))))

(defun jetpacs-tablist--buffer-arg (args)
  "The live tabulated-list buffer named by ARGS, or nil (SPEC 23.1)."
  (let* ((name (plist-get args :buffer))
         (buf (and (stringp name) (get-buffer name))))
    (and buf
         (with-current-buffer buf (derived-mode-p 'tabulated-list-mode))
         buf)))

(jetpacs-defaction "tablist.sort"
  (lambda (args params)
    (let ((buf (jetpacs-tablist--buffer-arg args))
          (col (plist-get args :column)))
      (cond
       ((null buf) 'rejected)
       ;; The column must exist in THIS buffer's own format: a name off the
       ;; wire can only ever select a real sortable column (SPEC 23.1).
       ((not (and (stringp col)
                  (with-current-buffer buf
                    (cl-find col tabulated-list-format
                             :key #'car :test #'equal))))
        'rejected)
       (t
        (with-current-buffer buf
          ;; Same column: flip direction; new column: ascending.
          (setq tabulated-list-sort-key
                (cons col (and (equal (car tabulated-list-sort-key) col)
                               (not (cdr tabulated-list-sort-key)))))
          (tabulated-list-print t))
        (jetpacs-tablist--refresh-view params)
        'accepted)))))

(jetpacs-defaction "tablist.refresh"
  (lambda (args params)
    (let ((buf (jetpacs-tablist--buffer-arg args)))
      (if (null buf)
          'rejected
        (with-current-buffer buf
          ;; noconfirm: a prompting revert would block the jsonrpc dispatch
          ;; extent, and the Companion would never learn the outcome (D2).
          (ignore-errors (revert-buffer nil t)))
        (jetpacs-tablist--refresh-view params)
        'accepted))))

(provide 'jetpacs-tablist)
;;; jetpacs-tablist.el ends here
