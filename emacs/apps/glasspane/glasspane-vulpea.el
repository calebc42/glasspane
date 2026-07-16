;;; glasspane-vulpea.el --- Mobile-context vulpea extractor -*- lexical-binding: t; -*-

;; Indexes Tasker/Mobile context properties (LOCATION, WIFI_SSID,
;; BATTERY_LEVEL, ACTIVITY, BLUETOOTH_DEVICES) into a `glasspane_mobile'
;; plugin table riding the user's vulpea note index (vulpea 2.6 extractor
;; API).  Rows are keyed to the note id with a cascade foreign key, so
;; vulpea's own delete-then-reinsert file update and file removals clean
;; them — no delete hook.
;;
;; This file is the extractor's `:worker-lib': vulpea's extraction worker
;; `require's it to resolve the extract-fn in its own process, so loading
;; it must have no side effects — definitions only.  Registration (which
;; applies the plugin schema, DDL only the main process may run) happens
;; through `glasspane-vulpea-register', called where Glasspane detects
;; vulpea: the glasspane-org load tail and the packages light-up.

;;; Code:

(declare-function emacsql "emacsql" (connection sql &rest args))
(declare-function vulpea-db "vulpea-db" ())
(declare-function vulpea-db-register-extractor "vulpea-db-extract"
                  (extractor-or-name &optional fn))
(declare-function make-vulpea-extractor "vulpea-db-extract" (&rest slots))

(defun glasspane-vulpea--extract-mobile (_ctx note-data)
  "Index NOTE-DATA's mobile context properties into `glasspane_mobile'.
Runs per note, inside vulpea's file-update transaction, after the note
row is inserted — so the row it writes can hold a foreign key against
the note.  Props-only: never reads the AST, which keeps the extractor
worker-eligible.  Returns NOTE-DATA unchanged (side-effecting
extractor)."
  (let* ((props (plist-get note-data :properties))
         (id (plist-get note-data :id))
         (location (cdr (assoc "LOCATION" props)))
         (wifi (cdr (assoc "WIFI_SSID" props)))
         (battery (cdr (assoc "BATTERY_LEVEL" props)))
         (activity (cdr (assoc "ACTIVITY" props)))
         (bluetooth (cdr (assoc "BLUETOOTH_DEVICES" props))))
    (when (and id (or location wifi battery activity bluetooth))
      (emacsql (vulpea-db)
               [:insert :into glasspane-mobile :values $v1]
               (vector id location wifi
                       (and battery (string-to-number battery))
                       activity bluetooth)))
    note-data))

(defvar glasspane-vulpea--registered nil
  "Non-nil once the mobile extractor has been registered this session.")

(defun glasspane-vulpea-register ()
  "Register the mobile-context extractor with vulpea (idempotent).
Creates the plugin table via the extractor `:schema'; the cascade
foreign key keeps it consistent from then on.  A no-op when vulpea's
extractor registry isn't loaded — Glasspane never force-loads vulpea,
it only rides an index the user's own config (or the packages
light-up) brought up."
  (when (and (not glasspane-vulpea--registered)
             (fboundp 'vulpea-db-register-extractor))
    (vulpea-db-register-extractor
     (make-vulpea-extractor
      :name 'glasspane-mobile
      :version 1
      :priority 90
      ;; Explicit nil (default is `unset'): declares the props-only
      ;; contract, so extraction never forces a full object parse and
      ;; stays eligible for the async worker.
      :requires-ast nil
      :worker-safe t
      :worker-lib 'glasspane-vulpea
      :schema '((glasspane-mobile
                 [(note-id :not-null) location wifi battery activity bluetooth]
                 (:foreign-key [note-id] :references notes [id]
                  :on-delete :cascade)))
      :extract-fn #'glasspane-vulpea--extract-mobile))
    (setq glasspane-vulpea--registered t)))

(provide 'glasspane-vulpea)
;;; glasspane-vulpea.el ends here
