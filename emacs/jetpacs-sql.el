;;; jetpacs-sql.el --- SQL connection & schema hub (core stock satellite) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; A stock satellite for `sql.el'.  `sql-interactive-mode' derives from
;; `comint-mode', so a live SQL session already renders as a REPL for
;; free (the comint substrate); this screen adds the connection picker
;; and session entry that had no phone surface.
;;
;;   Connections    -> cards from `sql-connection-alist'; a tap runs
;;                     `sql-connect' (its prompts — password included —
;;                     bridge from the continuation) and lands on the
;;                     SQLi REPL.
;;   New connection -> a product picker -> `sql-product-interactive'.
;;   Active session -> open the REPL, or `sql-list-all' into its own
;;                     buffer on the generic substrate.
;;
;; (Behavior reference: POC 1's jetpacs-sql.el; the multi-view shell
;; becomes one owned root surface whose product picker is a PUSHED
;; chrome screen — back is the companion-local `view.switch'.)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'sql)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-navigate)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)

(defconst jetpacs-sql-surface "jetpacs.sql"
  "The SQL hub's root surface (owner and surface name).")

(defun jetpacs-sql--sqli-buffer ()
  "The current live SQLi buffer object, or nil.
`sql-find-sqli-buffer' may return a buffer or a name; normalize."
  (when-let* ((raw (ignore-errors (sql-find-sqli-buffer))))
    (get-buffer raw)))

;;;; Cards

(defun jetpacs-sql--entry (icon title caption action)
  "A hub-grade row: leading ICON, TITLE/CAPTION, a chevron; ACTION on tap."
  (jetpacs-chrome-row title :subtitle caption :icon icon
                      :trailing (jetpacs-icon "chevron_right")
                      :on-tap action
                      :key (jetpacs-wire-id "sq" title)))

(defun jetpacs-sql--session-nodes ()
  "Nodes for a live SQLi session, or nil when none is running."
  (when-let* ((buf (jetpacs-sql--sqli-buffer)))
    (list
     (jetpacs-section-header "Active session")
     (jetpacs-sql--entry "terminal" (buffer-name buf)
                         "Open the SQL REPL"
                         (jetpacs-action "sql.open" :when-offline "drop"))
     (jetpacs-sql--entry "table_rows" "List tables"
                         "Send an object listing to the session"
                         (jetpacs-action "sql.list-tables"
                                         :when-offline "drop")))))

(defun jetpacs-sql--connection-product (entry)
  "The SQL product symbol declared in a `sql-connection-alist' ENTRY."
  (let ((val (cadr (assq 'sql-product (cdr entry)))))
    (cond ((and (consp val) (eq (car val) 'quote)) (cadr val))
          ((symbolp val) val))))

(defun jetpacs-sql--connection-card (entry)
  (let* ((name (format "%s" (car entry)))
         (prod (jetpacs-sql--connection-product entry))
         (caption (if prod
                      (or (sql-get-product-feature prod :name)
                          (symbol-name prod))
                    "Connect and open a REPL")))
    (jetpacs-sql--entry "dataset" name caption
                        (jetpacs-action "sql.connect"
                                        :args `(:connection ,name)
                                        :when-offline "drop"))))

(defun jetpacs-sql--connections-nodes ()
  (if (null sql-connection-alist)
      (list (jetpacs-empty-state
             :icon "storage" :title "No saved connections"
             :caption
             "Define connections in `sql-connection-alist', then connect here."))
    (cons (jetpacs-section-header "Connections")
          (mapcar #'jetpacs-sql--connection-card sql-connection-alist))))

(defun jetpacs-sql--products ()
  "SQL products Emacs can start an interactive session for."
  (seq-filter (lambda (p)
                (sql-get-product-feature (car p) :sqli-comint-func))
              sql-product-alist))

(defun jetpacs-sql--product-card (entry)
  (let* ((sym (car entry))
         (name (or (sql-get-product-feature sym :name)
                   (capitalize (symbol-name sym)))))
    (jetpacs-sql--entry "dataset" name
                        (format "Start a %s session" name)
                        (jetpacs-action "sql.new"
                                        :args `(:product ,(symbol-name sym))
                                        :when-offline "drop"))))

(defun jetpacs-sql--new-nodes ()
  (let ((products (jetpacs-sql--products)))
    (if (null products)
        (list (jetpacs-empty-state :icon "storage"
                                   :title "No SQL products available"))
      (cons (jetpacs-text "Pick a database product to start a session."
                          :style "caption")
            (mapcar #'jetpacs-sql--product-card products)))))

(defun jetpacs-sql--view ()
  "The root screen: sessions, saved connections, and the Add entry.
The product picker is a PUSHED screen now (the conformance sweep),
so its back arrow is the stack's companion-local `view.switch' —
the hand-rolled `sql.show' back verb died with the socket down,
where every other back arrow in the app kept working."
  (jetpacs-chrome-screen
   "Databases"
   (apply #'jetpacs-lazy-column
          (append
           (jetpacs-sql--session-nodes)
           (jetpacs-sql--connections-nodes)
           (list (jetpacs-section-header "Add")
                 (jetpacs-sql--entry "add" "New connection"
                                     "Start a REPL for a database product"
                                     (jetpacs-action
                                      "sql.new-screen"
                                      :when-offline "drop")))))))

(defun jetpacs-sql--new-screen (back)
  "Builder for the pushed product-picker screen."
  (jetpacs-chrome-screen
   "New connection"
   (apply #'jetpacs-lazy-column (jetpacs-sql--new-nodes))
   :back back))

(defun jetpacs-sql--view-buffer-of (fn)
  "Run FN in a continuation and navigate to the buffer it returns.
FN may prompt (host, user, password bridge as dialogs there); a signal
or quit costs the navigation, never the session."
  (jetpacs-flow-continue
   (lambda ()
     (condition-case err
         (let* ((last-input-event nil)
                (target (funcall fn)))
           (when target (jetpacs-navigate-buffer target)))
       (quit nil)
       (error (jetpacs-shell-notify
               (format "SQL command failed: %s"
                       (error-message-string err))))))))

;;;; Actions

(defun jetpacs-sql--action-show (_args _params)
  "Land on the Databases root from anywhere (settings link, M-x parity).
A stack RESET, not a state flip — DEFERRED, because the reset's push
rebuilds and sends the surface, and a handler never pushes inside the
dispatch extent (D2; the hub.home reset is the model)."
  (jetpacs-flow-continue
   (lambda () (jetpacs-chrome-reset-screens jetpacs-sql-surface)))
  'accepted)

(defun jetpacs-sql--action-new-screen (_args _params)
  "Push the product picker as a REAL stacked screen: its back arrow is
the companion-local `view.switch', which works with the socket down."
  (jetpacs-flow-continue
   (lambda ()
     ;; push-screen is transactional and RE-SIGNALS; a deferred caller
     ;; must catch or the signal dies in a timer (its docstring's rule).
     (condition-case err
         (jetpacs-chrome-push-screen jetpacs-sql-surface "new"
                                     #'jetpacs-sql--new-screen)
       (error (message "jetpacs-sql: picker push failed: %s"
                       (jetpacs-error-label err))))))
  'accepted)

(defun jetpacs-sql--action-connect (args _params)
  (let ((name (plist-get args :connection)))
    (if (not (and (stringp name)
                  (assoc-string name sql-connection-alist)))
        'rejected
      ;; No reset here: the connection cards render only on the ROOT
      ;; screen, so the stack is already at the hub — a reset would be
      ;; a redundant full rebuild and wire frame before every connect.
      (jetpacs-sql--view-buffer-of
       (lambda ()
         (sql-connect (intern name))
         (jetpacs-sql--sqli-buffer)))
      'accepted)))

(defun jetpacs-sql--action-new (args _params)
  (let* ((name (plist-get args :product))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (and sym (assq sym (jetpacs-sql--products))))
        'rejected
      (jetpacs-sql--view-buffer-of
       (lambda ()
         (sql-product-interactive sym)
         ;; The pick SUCCEEDED: land the drill on a RESET stack, so
         ;; back-from-REPL returns to the Databases hub, never the
         ;; spent picker (the project.switch rationale).  AFTER the
         ;; interactive call, so a quit at a bridged prompt keeps the
         ;; picker; inside the continuation, so the reset's push
         ;; stays out of the dispatch extent (D2).
         (jetpacs-chrome-reset-screens jetpacs-sql-surface)
         (jetpacs-sql--sqli-buffer)))
      'accepted)))

(defun jetpacs-sql--action-open (_args _params)
  (if (null (jetpacs-sql--sqli-buffer))
      'rejected
    (jetpacs-sql--view-buffer-of #'jetpacs-sql--sqli-buffer)
    'accepted))

(defun jetpacs-sql--action-list-tables (_args _params)
  (let ((buf (jetpacs-sql--sqli-buffer)))
    (if (null buf)
        'rejected
      (jetpacs-sql--view-buffer-of
       (lambda ()
         (with-current-buffer buf (sql-list-all))
         ;; sql-list-all pops its output into its own buffer.
         (get-buffer "*List All*")))
      'accepted)))

(with-jetpacs-owner "jetpacs.sql"
  (jetpacs-chrome-define-root jetpacs-sql-surface "home"
                              (lambda (_back) (jetpacs-sql--view))))
(jetpacs-defaction "sql.show" #'jetpacs-sql--action-show)
(jetpacs-defaction "sql.new-screen" #'jetpacs-sql--action-new-screen)
(jetpacs-defaction "sql.connect" #'jetpacs-sql--action-connect)
(jetpacs-defaction "sql.new" #'jetpacs-sql--action-new)
(jetpacs-defaction "sql.open" #'jetpacs-sql--action-open)
(jetpacs-defaction "sql.list-tables" #'jetpacs-sql--action-list-tables)

;; Entry: a card on the settings screen (order 40, after Project).
(with-eval-after-load 'jetpacs-settings
  (jetpacs-settings-add-link
   40 (lambda ()
        (jetpacs-sql--entry "storage" "Databases"
                            "SQL connections and sessions"
                            (jetpacs-action "sql.show"
                                            :when-offline "drop")))))
(declare-function jetpacs-settings-add-link "jetpacs-settings" (order builder))

(defvar jetpacs-launcher-row-icons)
(defvar jetpacs-launcher-row-labels)
(with-eval-after-load 'jetpacs-launcher
  (setf (alist-get (concat "app:" jetpacs-sql-surface)
                   jetpacs-launcher-row-icons nil nil #'equal)
        "storage")
  (setf (alist-get (concat "app:" jetpacs-sql-surface)
                   jetpacs-launcher-row-labels nil nil #'equal)
        "SQL"))

(provide 'jetpacs-sql)
;;; jetpacs-sql.el ends here