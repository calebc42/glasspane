;;; ebp-sqlite.el --- SQLite EBP durable action store -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Built-in SQLite implementation of `ebp-store.el'.  The database is
;; pairing-partitioned and stores no credentials.  Admission commits the
;; EventId receipt and its durable work item in one BEGIN IMMEDIATE
;; transaction.  Application work always runs outside that transaction.
;;
;; Emacs 30.1's `with-sqlite-transaction' can return the body value after a
;; false `sqlite-commit' result, so this backend intentionally uses a small
;; checked wrapper over the public SQLite primitives instead.

;;; Code:

(require 'cl-lib)
(require 'sqlite)
(require 'subr-x)
(require 'ebp-store)

(defconst ebp-sqlite-schema-version 1
  "Current `ebp-sqlite' schema version.")

(defconst ebp-sqlite-busy-timeout-ms 5000
  "How long SQLite waits for another process before reporting contention.")

(defvar ebp-sqlite--fault-function nil
  "Internal test hook called with named transaction boundaries.")

(cl-defstruct (ebp-sqlite-store
               (:constructor ebp-sqlite--make-store))
  "One open SQLite-backed EBP durable store."
  path
  db
  closed-p)

(defun ebp-sqlite--fault (point)
  "Invoke the internal fault injector at POINT, when one is installed."
  (when ebp-sqlite--fault-function
    (funcall ebp-sqlite--fault-function point)))

(defun ebp-sqlite--signal-error (context err)
  "Signal `ebp-store-error' for ERR under redaction-safe CONTEXT."
  (signal 'ebp-store-error
          (list (format "%s: %s" context (error-message-string err)) err)))

(defun ebp-sqlite--invalidate (store)
  "Close and invalidate STORE after an unrecoverable transaction failure."
  (let ((db (ebp-sqlite-store-db store)))
    (setf (ebp-sqlite-store-db store) nil
          (ebp-sqlite-store-closed-p store) t)
    (when db
      (ignore-errors (sqlite-close db)))))

(defun ebp-sqlite--db (store)
  "Return STORE's open database or signal fail-closed unavailability."
  (unless (and (ebp-sqlite-store-p store)
               (not (ebp-sqlite-store-closed-p store))
               (ebp-sqlite-store-db store))
    (signal 'ebp-store-unavailable '("SQLite EBP store is closed")))
  (ebp-sqlite-store-db store))

(defun ebp-sqlite--call-with-transaction (store function)
  "Call FUNCTION inside STORE's explicitly checked immediate transaction."
  (let ((db (ebp-sqlite--db store))
        begun committed result)
    (condition-case err
        (unwind-protect
            (progn
              (unless (integerp (sqlite-execute db "BEGIN IMMEDIATE"))
                (signal 'ebp-store-error
                        '("SQLite BEGIN IMMEDIATE did not succeed")))
              (setq begun t)
              (setq result (funcall function))
              (ebp-sqlite--fault 'before-commit)
              ;; `sqlite-commit' returns nil rather than signaling for some
              ;; failures.  A false result must never escape as acceptance.
              (unless (sqlite-commit db)
                (signal 'ebp-store-error
                        '("SQLite COMMIT did not succeed")))
              (setq committed t)
              result)
          (when (and begun (not committed))
            (unless (ignore-errors (sqlite-rollback db))
              ;; A failed rollback leaves the handle's state unknowable.
              (ebp-sqlite--invalidate store))))
      (ebp-store-error (signal (car err) (cdr err)))
      (sqlite-error (ebp-sqlite--signal-error "SQLite transaction failed" err))
      (error (ebp-sqlite--signal-error "Durable transaction failed" err)))))

(defun ebp-sqlite--scalar (db query &optional values)
  "Return the single scalar selected from DB by QUERY and VALUES."
  (let ((rows (sqlite-select db query values)))
    (unless (and (= (length rows) 1) (= (length (car rows)) 1))
      (signal 'ebp-store-error
              (list (format "Expected one SQLite scalar for %s" query))))
    (caar rows)))

(defun ebp-sqlite--set-pragma (db pragma)
  "Set PRAGMA on DB, signaling instead of accepting a false result."
  (unless (sqlite-pragma db pragma)
    (signal 'ebp-store-error
            (list (format "SQLite PRAGMA failed: %s" pragma)))))

(defun ebp-sqlite--configure (db)
  "Configure and verify DB's required durability and integrity settings."
  (ebp-sqlite--set-pragma db
                           (format "busy_timeout = %d"
                                   ebp-sqlite-busy-timeout-ms))
  (ebp-sqlite--set-pragma db "journal_mode = WAL")
  (ebp-sqlite--set-pragma db "synchronous = FULL")
  (ebp-sqlite--set-pragma db "foreign_keys = ON")
  (unless (= (ebp-sqlite--scalar db "PRAGMA busy_timeout")
             ebp-sqlite-busy-timeout-ms)
    (signal 'ebp-store-error '("SQLite busy timeout was not applied")))
  (unless (equal (downcase (format "%s"
                                  (ebp-sqlite--scalar
                                   db "PRAGMA journal_mode")))
                 "wal")
    (signal 'ebp-store-error '("SQLite WAL journal mode is unavailable")))
  (unless (= (ebp-sqlite--scalar db "PRAGMA synchronous") 2)
    (signal 'ebp-store-error '("SQLite synchronous=FULL was not applied")))
  (unless (= (ebp-sqlite--scalar db "PRAGMA foreign_keys") 1)
    (signal 'ebp-store-error '("SQLite foreign keys are disabled"))))

(defun ebp-sqlite--user-tables (db)
  "Return DB's sorted non-internal table names."
  (sort (mapcar #'car
                (sqlite-select
                 db
                 "SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
        #'string<))

(defun ebp-sqlite--create-schema (store)
  "Create STORE's complete schema version 1 in one transaction."
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (sqlite-execute
        db
        "CREATE TABLE pairing_partitions (
           pairing_id TEXT PRIMARY KEY NOT NULL,
           created_at_ms INTEGER NOT NULL,
           CHECK (length(pairing_id) = 32
                  AND pairing_id NOT GLOB '*[^0-9a-f]*')
         )")
       (sqlite-execute
        db
        "CREATE TABLE accepted_events (
           pairing_id TEXT NOT NULL,
           event_id TEXT NOT NULL,
           accepted_at_ms INTEGER NOT NULL,
           completed_at_ms INTEGER,
           PRIMARY KEY (pairing_id, event_id),
           FOREIGN KEY (pairing_id)
             REFERENCES pairing_partitions(pairing_id) ON DELETE CASCADE,
           CHECK (length(event_id) = 32
                  AND event_id NOT GLOB '*[^0-9a-f]*')
         )")
       (sqlite-execute
        db
        "CREATE TABLE action_work (
           work_id INTEGER PRIMARY KEY AUTOINCREMENT,
           pairing_id TEXT NOT NULL,
           event_id TEXT NOT NULL,
           action TEXT NOT NULL,
           payload_json TEXT NOT NULL,
           state TEXT NOT NULL,
           attempt_count INTEGER NOT NULL DEFAULT 0,
           available_at_ms INTEGER NOT NULL,
           lease_id TEXT,
           lease_until_ms INTEGER,
           last_error_kind TEXT,
           updated_at_ms INTEGER NOT NULL,
           UNIQUE (pairing_id, event_id),
           FOREIGN KEY (pairing_id, event_id)
             REFERENCES accepted_events(pairing_id, event_id)
             ON DELETE CASCADE,
           CHECK (state IN ('pending', 'leased', 'blocked')),
           CHECK ((state = 'leased'
                   AND lease_id IS NOT NULL AND lease_until_ms IS NOT NULL)
                  OR
                  (state <> 'leased'
                   AND lease_id IS NULL AND lease_until_ms IS NULL))
         )")
       (sqlite-execute
        db
        "CREATE INDEX action_work_ready
           ON action_work(state, available_at_ms, work_id)")
       (sqlite-execute db "PRAGMA user_version = 1")
       t))))

(defun ebp-sqlite--verify-schema (db)
  "Fail closed unless DB is the complete, healthy schema version 1."
  (unless (equal (ebp-sqlite--user-tables db)
                 '("accepted_events" "action_work" "pairing_partitions"))
    (signal 'ebp-store-error '("SQLite EBP schema tables do not match v1")))
  (unless (equal (sqlite-select db "PRAGMA integrity_check") '(("ok")))
    (signal 'ebp-store-error '("SQLite EBP integrity check failed")))
  (when (sqlite-select db "PRAGMA foreign_key_check")
    (signal 'ebp-store-error '("SQLite EBP foreign-key check failed"))))

(defun ebp-sqlite-open (file)
  "Open FILE as a versioned, fail-closed `ebp-sqlite-store'."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (signal 'ebp-store-unavailable '("Emacs was built without SQLite")))
  (unless (stringp file)
    (signal 'wrong-type-argument (list 'stringp file)))
  (let* ((path (expand-file-name file))
         (directory (file-name-directory path)))
    (unless (and directory (file-directory-p directory))
      (signal 'ebp-store-unavailable
              (list (format "SQLite store directory does not exist: %s"
                            directory))))
    (let ((db (condition-case err
                  (sqlite-open path)
                (error (ebp-sqlite--signal-error
                        "Could not open SQLite EBP store" err)))))
      (unless db
        (signal 'ebp-store-unavailable
                (list (format "Could not open SQLite EBP store: %s" path))))
      (let ((store (ebp-sqlite--make-store :path path :db db)))
        (condition-case err
            (progn
              (ebp-sqlite--configure db)
              (let ((version (ebp-sqlite--scalar db "PRAGMA user_version")))
                (cond
                 ((= version 0)
                  (when (ebp-sqlite--user-tables db)
                    (signal 'ebp-store-error
                            '("Unversioned non-empty SQLite store refused")))
                  (ebp-sqlite--create-schema store))
                 ((/= version ebp-sqlite-schema-version)
                  (signal 'ebp-store-error
                          (list (format "Unsupported SQLite EBP schema %s"
                                        version))))))
              (ebp-sqlite--verify-schema db)
              ;; Best effort on platforms whose permission model supports
              ;; Unix modes.  Credentials never enter this database.
              (ignore-errors (set-file-modes path #o600))
              store)
          (ebp-store-error
           (ebp-sqlite--invalidate store)
           (signal (car err) (cdr err)))
          (error
           (ebp-sqlite--invalidate store)
           (ebp-sqlite--signal-error "Could not initialize SQLite store"
                                     err)))))))

(defun ebp-sqlite--require-id (value name)
  "Require VALUE to be a lowercase 32-hex identifier named NAME."
  (unless (and (stringp value)
               (string-match-p "\\`[0-9a-f]\\{32\\}\\'" value))
    (signal 'wrong-type-argument (list name value))))

(defun ebp-sqlite--require-time (value name)
  "Require VALUE to be a non-negative integer timestamp named NAME."
  (unless (and (integerp value) (>= value 0))
    (signal 'wrong-type-argument (list name value))))

(defun ebp-sqlite--require-action (action)
  "Require ACTION to be an EBP namespaced identifier."
  (unless (and (stringp action)
               (string-search "." action)
               (<= (string-bytes action) 128)
               (string-match-p
                "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" action))
    (signal 'wrong-type-argument (list 'ebp-action action))))

(defun ebp-sqlite--require-error-kind (kind)
  "Require KIND to be nil or a bounded symbolic diagnostic string."
  (unless (or (null kind)
              (and (stringp kind)
                   (<= (string-bytes kind) 128)
                   (string-match-p
                    "\\`[A-Za-z0-9][A-Za-z0-9._:-]*\\'" kind)))
    (signal 'wrong-type-argument (list 'ebp-error-kind kind))))

(defun ebp-sqlite--normalize-state (state)
  "Return STATE as a checked database string, or nil."
  (when state
    (let ((name (if (symbolp state) (symbol-name state) state)))
      (unless (member name '("pending" "leased" "blocked"))
        (signal 'wrong-type-argument (list 'ebp-work-state state)))
      name)))

(defun ebp-sqlite--row-to-work (row)
  "Convert one joined action-work ROW into `ebp-store-work'."
  (pcase-let ((`(,work-id ,pairing-id ,event-id ,action ,payload-json
                   ,accepted-at-ms ,state ,attempt-count ,available-at-ms
                   ,lease-id ,lease-until-ms ,last-error-kind ,updated-at-ms)
                row))
    (ebp-store-work-create
     :work-id work-id :pairing-id pairing-id :event-id event-id
     :action action :payload-json payload-json
     :accepted-at-ms accepted-at-ms :state (intern state)
     :attempt-count attempt-count :available-at-ms available-at-ms
     :lease-id lease-id :lease-until-ms lease-until-ms
     :last-error-kind last-error-kind :updated-at-ms updated-at-ms)))

(defconst ebp-sqlite--work-columns
  "w.work_id, w.pairing_id, w.event_id, w.action, w.payload_json,
   e.accepted_at_ms, w.state, w.attempt_count, w.available_at_ms,
   w.lease_id, w.lease_until_ms, w.last_error_kind, w.updated_at_ms"
  "Columns selected, in `ebp-sqlite--row-to-work' order.")

(defun ebp-sqlite--select-work-by-id (db work-id)
  "Return DB's WORK-ID as an `ebp-store-work', or nil."
  (when-let* ((row (car (sqlite-select
                          db
                          (concat "SELECT " ebp-sqlite--work-columns
                                  " FROM action_work w
                                    JOIN accepted_events e
                                      USING (pairing_id, event_id)
                                   WHERE w.work_id = ?")
                          (list work-id)))))
    (ebp-sqlite--row-to-work row)))

(cl-defmethod ebp-store-known-p
  ((store ebp-sqlite-store) pairing-id event-id)
  (ebp-sqlite--require-id pairing-id 'ebp-pairing-id)
  (ebp-sqlite--require-id event-id 'ebp-event-id)
  (and (sqlite-select (ebp-sqlite--db store)
                      "SELECT 1 FROM accepted_events
                        WHERE pairing_id = ? AND event_id = ? LIMIT 1"
                      (list pairing-id event-id))
       t))

(cl-defmethod ebp-store-admit
  ((store ebp-sqlite-store) pairing-id event-id action payload-json now-ms)
  (ebp-sqlite--require-id pairing-id 'ebp-pairing-id)
  (ebp-sqlite--require-id event-id 'ebp-event-id)
  (ebp-sqlite--require-action action)
  (unless (stringp payload-json)
    (signal 'wrong-type-argument (list 'stringp payload-json)))
  (ebp-sqlite--require-time now-ms 'ebp-now-ms)
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (sqlite-execute
        db
        "INSERT OR IGNORE INTO pairing_partitions
           (pairing_id, created_at_ms) VALUES (?, ?)"
        (list pairing-id now-ms))
       (let ((inserted
              (sqlite-execute
               db
               "INSERT OR IGNORE INTO accepted_events
                  (pairing_id, event_id, accepted_at_ms)
                  VALUES (?, ?, ?)"
               (list pairing-id event-id now-ms))))
         (cond
          ((= inserted 0) 'duplicate)
          ((/= inserted 1)
           (signal 'ebp-store-error
                   '("Receipt insertion affected an unexpected row count")))
          (t
           (ebp-sqlite--fault 'after-receipt)
           (unless (= 1
                      (sqlite-execute
                       db
                       "INSERT INTO action_work
                          (pairing_id, event_id, action, payload_json, state,
                           available_at_ms, updated_at_ms)
                          VALUES (?, ?, ?, ?, 'pending', ?, ?)"
                       (list pairing-id event-id action payload-json
                             now-ms now-ms)))
             (signal 'ebp-store-error
                     '("Work insertion affected an unexpected row count")))
           (ebp-sqlite--fault 'after-work)
           'admitted)))))))

(cl-defmethod ebp-store-claim-next
  ((store ebp-sqlite-store) worker-id now-ms lease-ms &optional pairing-id)
  (unless (and (stringp worker-id) (not (string-empty-p worker-id)))
    (signal 'wrong-type-argument (list 'ebp-worker-id worker-id)))
  (ebp-sqlite--require-time now-ms 'ebp-now-ms)
  (unless (and (integerp lease-ms) (> lease-ms 0))
    (signal 'wrong-type-argument (list 'ebp-lease-ms lease-ms)))
  (when pairing-id
    (ebp-sqlite--require-id pairing-id 'ebp-pairing-id))
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (let* ((where
               (concat
                " WHERE ((w.state = 'pending' AND w.available_at_ms <= ?)
                          OR (w.state = 'leased' AND w.lease_until_ms <= ?))"
                (when pairing-id " AND w.pairing_id = ?")))
              (row (car (sqlite-select
                         db
                         (concat "SELECT " ebp-sqlite--work-columns
                                 " FROM action_work w
                                   JOIN accepted_events e
                                     USING (pairing_id, event_id)"
                                 where " ORDER BY w.work_id LIMIT 1")
                         (append (list now-ms now-ms)
                                 (when pairing-id (list pairing-id)))))))
         (when row
           (let* ((work (ebp-sqlite--row-to-work row))
                  (attempt (1+ (ebp-store-work-attempt-count work)))
                  (lease-id
                   (secure-hash
                    'sha256
                    (format "%s\0%d\0%d\0%d" worker-id now-ms
                            (ebp-store-work-work-id work) attempt)))
                  (lease-until (+ now-ms lease-ms)))
             (unless
                 (= 1
                    (sqlite-execute
                     db
                     "UPDATE action_work
                         SET state = 'leased', attempt_count = ?,
                             lease_id = ?, lease_until_ms = ?,
                             last_error_kind = NULL, updated_at_ms = ?
                       WHERE work_id = ?"
                     (list attempt lease-id lease-until now-ms
                           (ebp-store-work-work-id work))))
               (signal 'ebp-store-error
                       '("Work claim affected an unexpected row count")))
             (ebp-sqlite--select-work-by-id
              db (ebp-store-work-work-id work)))))))))

(defun ebp-sqlite--require-leased-work (work)
  "Require WORK to carry a complete lease identity."
  (unless (and (ebp-store-work-p work)
               (integerp (ebp-store-work-work-id work))
               (stringp (ebp-store-work-lease-id work)))
    (signal 'wrong-type-argument (list 'ebp-leased-work work))))

(cl-defmethod ebp-store-complete
  ((store ebp-sqlite-store) work now-ms)
  (ebp-sqlite--require-leased-work work)
  (ebp-sqlite--require-time now-ms 'ebp-now-ms)
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (unless
           (= 1
              (sqlite-execute
               db
               "DELETE FROM action_work
                 WHERE work_id = ? AND pairing_id = ? AND event_id = ?
                   AND state = 'leased' AND lease_id = ?"
               (list (ebp-store-work-work-id work)
                     (ebp-store-work-pairing-id work)
                     (ebp-store-work-event-id work)
                     (ebp-store-work-lease-id work))))
         (signal 'ebp-store-stale-lease '("Work lease is no longer current")))
       (ebp-sqlite--fault 'after-work-delete)
       (unless
           (= 1
              (sqlite-execute
               db
               "UPDATE accepted_events SET completed_at_ms = ?
                 WHERE pairing_id = ? AND event_id = ?"
               (list now-ms (ebp-store-work-pairing-id work)
                     (ebp-store-work-event-id work))))
         (signal 'ebp-store-error '("Accepted receipt disappeared")))
       t))))

(cl-defmethod ebp-store-retry
  ((store ebp-sqlite-store) work now-ms next-at-ms error-kind)
  (ebp-sqlite--require-leased-work work)
  (ebp-sqlite--require-time now-ms 'ebp-now-ms)
  (ebp-sqlite--require-time next-at-ms 'ebp-next-at-ms)
  (when (< next-at-ms now-ms)
    (signal 'wrong-type-argument (list 'ebp-next-at-ms next-at-ms)))
  (ebp-sqlite--require-error-kind error-kind)
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (unless
           (= 1
              (sqlite-execute
               db
               "UPDATE action_work
                   SET state = 'pending', available_at_ms = ?,
                       lease_id = NULL, lease_until_ms = NULL,
                       last_error_kind = ?, updated_at_ms = ?
                 WHERE work_id = ? AND state = 'leased' AND lease_id = ?"
               (list next-at-ms error-kind now-ms
                     (ebp-store-work-work-id work)
                     (ebp-store-work-lease-id work))))
         (signal 'ebp-store-stale-lease '("Work lease is no longer current")))
       t))))

(cl-defmethod ebp-store-block
  ((store ebp-sqlite-store) work now-ms error-kind)
  (ebp-sqlite--require-leased-work work)
  (ebp-sqlite--require-time now-ms 'ebp-now-ms)
  (ebp-sqlite--require-error-kind error-kind)
  (unless error-kind
    (signal 'wrong-type-argument '(ebp-error-kind nil)))
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (unless
           (= 1
              (sqlite-execute
               db
               "UPDATE action_work
                   SET state = 'blocked', lease_id = NULL,
                       lease_until_ms = NULL, last_error_kind = ?,
                       updated_at_ms = ?
                 WHERE work_id = ? AND state = 'leased' AND lease_id = ?"
               (list error-kind now-ms (ebp-store-work-work-id work)
                     (ebp-store-work-lease-id work))))
         (signal 'ebp-store-stale-lease '("Work lease is no longer current")))
       t))))

(cl-defmethod ebp-store-list-work
  ((store ebp-sqlite-store) &optional pairing-id state)
  (when pairing-id
    (ebp-sqlite--require-id pairing-id 'ebp-pairing-id))
  (let* ((state-name (ebp-sqlite--normalize-state state))
         (conditions nil)
         (values nil))
    (when pairing-id
      (push "w.pairing_id = ?" conditions)
      (setq values (append values (list pairing-id))))
    (when state-name
      (push "w.state = ?" conditions)
      (setq values (append values (list state-name))))
    (mapcar
     #'ebp-sqlite--row-to-work
     (sqlite-select
      (ebp-sqlite--db store)
      (concat "SELECT " ebp-sqlite--work-columns
              " FROM action_work w
                JOIN accepted_events e USING (pairing_id, event_id)"
              (when conditions
                (concat " WHERE "
                        (mapconcat #'identity (nreverse conditions) " AND ")))
              " ORDER BY w.work_id")
      values))))

(cl-defmethod ebp-store-forget-pairing
  ((store ebp-sqlite-store) pairing-id)
  (ebp-sqlite--require-id pairing-id 'ebp-pairing-id)
  (let ((db (ebp-sqlite--db store)))
    (ebp-sqlite--call-with-transaction
     store
     (lambda ()
       (sqlite-execute db
                       "DELETE FROM pairing_partitions WHERE pairing_id = ?"
                       (list pairing-id))))))

(cl-defmethod ebp-store-prune
  ((store ebp-sqlite-store) now-ms retention-ms)
  (ebp-sqlite--require-time now-ms 'ebp-now-ms)
  (unless (and (integerp retention-ms)
               (>= retention-ms ebp-store-minimum-retention-ms))
    (signal 'wrong-type-argument (list 'ebp-retention-ms retention-ms)))
  (let ((db (ebp-sqlite--db store))
        (cutoff (- now-ms retention-ms)))
    (if (< cutoff 0)
        0
      (ebp-sqlite--call-with-transaction
       store
       (lambda ()
         (sqlite-execute
          db
          "DELETE FROM accepted_events AS e
            WHERE e.completed_at_ms IS NOT NULL
              AND e.accepted_at_ms <= ?
              AND NOT EXISTS (
                    SELECT 1 FROM action_work AS w
                     WHERE w.pairing_id = e.pairing_id
                       AND w.event_id = e.event_id)"
          (list cutoff)))))))

(cl-defmethod ebp-store-close ((store ebp-sqlite-store))
  (unless (ebp-sqlite-store-closed-p store)
    (let ((db (ebp-sqlite-store-db store)))
      (condition-case err
          (when (and db (not (sqlite-close db)))
            (signal 'ebp-store-error '("SQLite close did not succeed")))
        (sqlite-error (ebp-sqlite--signal-error "SQLite close failed" err)))
      (setf (ebp-sqlite-store-db store) nil
            (ebp-sqlite-store-closed-p store) t)))
  t)

(provide 'ebp-sqlite)
;;; ebp-sqlite.el ends here
