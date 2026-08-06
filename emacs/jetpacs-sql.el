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
;; becomes one owned root surface with a screen-state variable.)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'sql)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-navigate)
(require 'jetpacs-shell)

(defconst jetpacs-sql-surface "jetpacs.sql"
  "The SQL hub's root surface (owner and surface name).")

(defvar jetpacs-sql--screen 'hub
  "Which screen the surface shows: `hub' or `new'.")

(defun jetpacs-sql--sqli-buffer ()
  "The current live SQLi buffer object, or nil.
`sql-find-sqli-buffer' may return a buffer or a name; normalize."
  (when-let* ((raw (ignore-errors (sql-find-sqli-buffer))))
    (get-buffer raw)))

;;;; Cards

(defun jetpacs-sql--entry (icon title caption action)
  (jetpacs-card
   (jetpacs-row
    (jetpacs-icon icon)
    (jetpacs-with-attrs
     (jetpacs-column (jetpacs-text title :style "label")
                     (jetpacs-text caption :style "caption"))
     :weight 1)
    (jetpacs-icon "chevron_right"))
   :on-tap action))

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
  ;; A scaffold so chrome docks the view switcher.
  (jetpacs-scaffold
   :body
   (apply #'jetpacs-lazy-column
          (cons
          (jetpacs-row
           (unless (eq jetpacs-sql--screen 'hub)
             (jetpacs-icon-button "arrow_back"
                                  (jetpacs-action "sql.show"
                                                  :when-offline "drop")
                                  :content-description "Back to the hub"))
           (jetpacs-text (if (eq jetpacs-sql--screen 'new)
                             "New connection" "Databases")
                         :style "title"))
          (if (eq jetpacs-sql--screen 'new)
              (jetpacs-sql--new-nodes)
            (append
             (jetpacs-sql--session-nodes)
             (jetpacs-sql--connections-nodes)
             (list (jetpacs-section-header "Add")
                   (jetpacs-sql--entry "add" "New connection"
                                       "Start a REPL for a database product"
                                       (jetpacs-action
                                        "sql.new-screen"
                                        :when-offline "drop")))))))))

(defun jetpacs-sql--refresh ()
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-sql-surface)))))

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
  (setq jetpacs-sql--screen 'hub)
  (jetpacs-sql--refresh)
  'accepted)

(defun jetpacs-sql--action-new-screen (_args _params)
  (setq jetpacs-sql--screen 'new)
  (jetpacs-sql--refresh)
  'accepted)

(defun jetpacs-sql--action-connect (args _params)
  (let ((name (plist-get args :connection)))
    (if (not (and (stringp name)
                  (assoc-string name sql-connection-alist)))
        'rejected
      (setq jetpacs-sql--screen 'hub)
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
      (setq jetpacs-sql--screen 'hub)
      (jetpacs-sql--view-buffer-of
       (lambda ()
         (sql-product-interactive sym)
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
  (jetpacs-shell-define-root jetpacs-sql-surface #'jetpacs-sql--view))
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

(provide 'jetpacs-sql)
;;; jetpacs-sql.el ends here