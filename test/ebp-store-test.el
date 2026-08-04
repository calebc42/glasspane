;;; ebp-store-test.el --- EBP durable store tests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Storage-contract and built-in SQLite backend tests.  These tests have no
;; dependency on Jetpacs application code or on the protocol endpoint.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'sqlite)
(require 'ebp-sqlite)

(defconst ebp-store-test-pair-a (make-string 32 ?a))
(defconst ebp-store-test-pair-b (make-string 32 ?b))
(defconst ebp-store-test-event-a "00000000000000000000000000000001")
(defconst ebp-store-test-event-b "00000000000000000000000000000002")
(defconst ebp-store-test-event-c "00000000000000000000000000000003")

(cl-defmacro ebp-store-test--with-store ((store file) &rest body)
  "Open a temporary STORE at FILE while evaluating BODY."
  (declare (indent 1) (debug ((symbolp symbolp) body)))
  `(progn
     (skip-unless (and (fboundp 'sqlite-available-p)
                       (sqlite-available-p)))
     (let* ((directory (make-temp-file "ebp-store-test-" t))
            (,file (expand-file-name "store.sqlite" directory))
            (,store nil))
       (unwind-protect
           (progn
             (setq ,store (ebp-sqlite-open ,file))
             ,@body)
         (when (and ,store
                    (ebp-sqlite-store-p ,store)
                    (not (ebp-sqlite-store-closed-p ,store)))
           (ebp-store-close ,store))
         (delete-directory directory t)))))

(defun ebp-store-test--admit
    (store event-id &optional pairing-id now-ms payload)
  "Admit EVENT-ID to STORE using compact deterministic test data."
  (ebp-store-admit
   store (or pairing-id ebp-store-test-pair-a) event-id
   "test.render" (or payload "{\"value\":1}") (or now-ms 100)))

(ert-deftest ebp-sqlite-creates-and-verifies-versioned-schema ()
  (ebp-store-test--with-store (store file)
    (let ((db (ebp-sqlite-store-db store)))
      (should (= 1 (caar (sqlite-select db "PRAGMA user_version"))))
      (should (= 1 (caar (sqlite-select db "PRAGMA foreign_keys"))))
      (should (= 2 (caar (sqlite-select db "PRAGMA synchronous"))))
      (should (= ebp-sqlite-busy-timeout-ms
                 (caar (sqlite-select db "PRAGMA busy_timeout"))))
      (should (equal "wal"
                     (downcase
                      (format "%s"
                              (caar (sqlite-select
                                     db "PRAGMA journal_mode"))))))
      (should
       (equal
        '("accepted_events" "action_work" "pairing_partitions")
        (sort
         (mapcar
          #'car
          (sqlite-select
           db
           "SELECT name FROM sqlite_master
              WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
         #'string<)))
      (should (equal '(("ok")) (sqlite-select db "PRAGMA integrity_check")))
      (should-not (sqlite-select db "PRAGMA foreign_key_check")))))

(ert-deftest ebp-sqlite-refuses-unknown-or-unversioned-existing-schema ()
  (skip-unless (and (fboundp 'sqlite-available-p) (sqlite-available-p)))
  (let ((directory (make-temp-file "ebp-store-schema-test-" t)))
    (unwind-protect
        (let ((unknown (expand-file-name "unknown.sqlite" directory))
              (legacy (expand-file-name "legacy.sqlite" directory)))
          (let ((db (sqlite-open unknown)))
            (sqlite-execute db "PRAGMA user_version = 99")
            (sqlite-close db))
          (should-error (ebp-sqlite-open unknown)
                        :type 'ebp-store-error)
          (let ((db (sqlite-open legacy)))
            (sqlite-execute db "CREATE TABLE legacy_data (id INTEGER)")
            (sqlite-close db))
          (should-error (ebp-sqlite-open legacy)
                        :type 'ebp-store-error))
      (delete-directory directory t))))

(ert-deftest ebp-sqlite-fails-closed-when-sqlite-is-unavailable ()
  (cl-letf (((symbol-function 'sqlite-available-p)
             (lambda () nil)))
    (should-error
     (ebp-sqlite-open
      (expand-file-name "unavailable.sqlite" temporary-file-directory))
     :type 'ebp-store-unavailable)))

(ert-deftest ebp-sqlite-admission-is-idempotent-across-reopen ()
  (ebp-store-test--with-store (store file)
    (should (eq 'admitted
                (ebp-store-test--admit
                 store ebp-store-test-event-a nil 100 "{\"first\":true}")))
    (should (ebp-store-known-p
             store ebp-store-test-pair-a ebp-store-test-event-a))
    (should
     (eq 'duplicate
         (ebp-store-admit
          store ebp-store-test-pair-a ebp-store-test-event-a
          "test.other" "{\"replacement\":true}" 200)))
    (let ((work (car (ebp-store-list-work store))))
      (should (equal "test.render" (ebp-store-work-action work)))
      (should (equal "{\"first\":true}" (ebp-store-work-payload-json work)))
      (should (eq 'pending (ebp-store-work-state work))))
    (ebp-store-close store)
    (setq store (ebp-sqlite-open file))
    (should (ebp-store-known-p
             store ebp-store-test-pair-a ebp-store-test-event-a))
    (should (= 1 (length (ebp-store-list-work store))))))

(ert-deftest ebp-sqlite-partitions-identical-event-ids-by-pairing ()
  (ebp-store-test--with-store (store file)
    (should (eq 'admitted
                (ebp-store-test--admit
                 store ebp-store-test-event-a ebp-store-test-pair-a)))
    (should (eq 'admitted
                (ebp-store-test--admit
                 store ebp-store-test-event-a ebp-store-test-pair-b)))
    (should (= 1 (length
                  (ebp-store-list-work store ebp-store-test-pair-a))))
    (should (= 1 (length
                  (ebp-store-list-work store ebp-store-test-pair-b))))
    (should (= 1
               (ebp-store-forget-pairing store ebp-store-test-pair-a)))
    (should (= 0
               (ebp-store-forget-pairing store ebp-store-test-pair-a)))
    (should-not (ebp-store-known-p
                 store ebp-store-test-pair-a ebp-store-test-event-a))
    (should (ebp-store-known-p
             store ebp-store-test-pair-b ebp-store-test-event-a))
    (ebp-store-close store)
    (setq store (ebp-sqlite-open file))
    (should (= 1 (length (ebp-store-list-work store))))
    (should (equal ebp-store-test-pair-b
                   (ebp-store-work-pairing-id
                    (car (ebp-store-list-work store)))))))

(ert-deftest ebp-sqlite-rolls-back-partial-admission ()
  (ebp-store-test--with-store (store file)
    (let ((ebp-sqlite--fault-function
           (lambda (point)
             (when (eq point 'after-receipt)
               (error "Injected admission failure")))))
      (should-error
       (ebp-store-test--admit store ebp-store-test-event-a)
       :type 'ebp-store-error))
    (should-not (ebp-store-known-p
                 store ebp-store-test-pair-a ebp-store-test-event-a))
    (should-not (ebp-store-list-work store))
    (ebp-store-close store)
    (setq store (ebp-sqlite-open file))
    (should-not (ebp-store-known-p
                 store ebp-store-test-pair-a ebp-store-test-event-a))
    (should-not (ebp-store-list-work store))))

(ert-deftest ebp-sqlite-never-accepts-a-false-commit-result ()
  (ebp-store-test--with-store (store file)
    (cl-letf (((symbol-function 'sqlite-commit)
               (lambda (_db) nil)))
      (should-error
       (ebp-store-test--admit store ebp-store-test-event-a)
       :type 'ebp-store-error))
    (should-not (ebp-store-known-p
                 store ebp-store-test-pair-a ebp-store-test-event-a))
    (should-not (ebp-store-list-work store))
    (ebp-store-close store)
    (setq store (ebp-sqlite-open file))
    (should-not (ebp-store-known-p
                 store ebp-store-test-pair-a ebp-store-test-event-a))))

(ert-deftest ebp-sqlite-claims-in-admission-order-and-can-scope-pairing ()
  (ebp-store-test--with-store (store file)
    (ebp-store-test--admit
     store ebp-store-test-event-a ebp-store-test-pair-a 10)
    (ebp-store-test--admit
     store ebp-store-test-event-b ebp-store-test-pair-b 20)
    (ebp-store-test--admit
     store ebp-store-test-event-c ebp-store-test-pair-a 30)
    (let ((pair-b-work
           (ebp-store-claim-next
            store "worker-b" 30 100 ebp-store-test-pair-b)))
      (should (equal ebp-store-test-pair-b
                     (ebp-store-work-pairing-id pair-b-work))))
    (let ((first (ebp-store-claim-next store "worker-a" 30 100)))
      (should (equal ebp-store-test-event-a
                     (ebp-store-work-event-id first))))
    (let ((next (ebp-store-claim-next store "worker-c" 30 100)))
      (should (equal ebp-store-test-event-c
                     (ebp-store-work-event-id next))))))

(ert-deftest ebp-sqlite-recovers-expired-leases-and-retains-blocked-work ()
  (ebp-store-test--with-store (store file)
    (ebp-store-test--admit store ebp-store-test-event-a nil 100)
    (let ((first (ebp-store-claim-next store "worker-a" 100 50)))
      (should (= 1 (ebp-store-work-attempt-count first)))
      (should (= 150 (ebp-store-work-lease-until-ms first)))
      (should-not (ebp-store-claim-next store "worker-b" 149 50))
      (ebp-store-close store)
      (setq store (ebp-sqlite-open file))
      (let ((recovered (ebp-store-claim-next store "worker-b" 150 50)))
        (should (= 2 (ebp-store-work-attempt-count recovered)))
        (should-not (equal (ebp-store-work-lease-id first)
                           (ebp-store-work-lease-id recovered)))
        (should-error (ebp-store-complete store first 151)
                      :type 'ebp-store-stale-lease)
        (should (ebp-store-retry
                 store recovered 151 200 "transient"))
        (should-not (ebp-store-claim-next store "worker-c" 199 50))
        (let ((retried (ebp-store-claim-next store "worker-c" 200 50)))
          (should (= 3 (ebp-store-work-attempt-count retried)))
          (should (ebp-store-block store retried 201 "manual.review")))))
    (let ((blocked (car (ebp-store-list-work store nil 'blocked))))
      (should blocked)
      (should (equal "manual.review"
                     (ebp-store-work-last-error-kind blocked))))
    (should-not (ebp-store-claim-next store "worker-d" 10000 50))
    (ebp-store-close store)
    (setq store (ebp-sqlite-open file))
    (should (= 1 (length (ebp-store-list-work store nil 'blocked))))))

(ert-deftest ebp-sqlite-completion-is-atomic-and-erases-work-payload ()
  (ebp-store-test--with-store (store file)
    (ebp-store-test--admit
     store ebp-store-test-event-a nil 100 "{\"secretless\":\"input\"}")
    (let ((work (ebp-store-claim-next store "worker-a" 100 50)))
      (let ((ebp-sqlite--fault-function
             (lambda (point)
               (when (eq point 'after-work-delete)
                 (error "Injected completion failure")))))
        (should-error (ebp-store-complete store work 110)
                      :type 'ebp-store-error))
      (should (= 1 (length (ebp-store-list-work store nil 'leased))))
      (should (ebp-store-complete store work 111)))
    (should-not (ebp-store-list-work store))
    (should (ebp-store-known-p
             store ebp-store-test-pair-a ebp-store-test-event-a))
    (should
     (= 111
        (caar
         (sqlite-select
          (ebp-sqlite-store-db store)
          "SELECT completed_at_ms FROM accepted_events
            WHERE pairing_id = ? AND event_id = ?"
          (list ebp-store-test-pair-a ebp-store-test-event-a)))))
    (ebp-store-close store)
    (setq store (ebp-sqlite-open file))
    (should-not (ebp-store-list-work store))
    (should
     (eq 'duplicate
         (ebp-store-test--admit store ebp-store-test-event-a)))))

(ert-deftest ebp-sqlite-prunes-only-old-completed-receipts ()
  (ebp-store-test--with-store (store file)
    (ebp-store-test--admit store ebp-store-test-event-a nil 0)
    (let ((work (ebp-store-claim-next store "worker-a" 0 10)))
      (ebp-store-complete store work 1))
    (ebp-store-test--admit store ebp-store-test-event-b nil 0)
    (should-error
     (ebp-store-prune
      store ebp-store-minimum-retention-ms
      (1- ebp-store-minimum-retention-ms))
     :type 'wrong-type-argument)
    (should
     (= 1
        (ebp-store-prune
         store (1+ ebp-store-minimum-retention-ms)
         ebp-store-minimum-retention-ms)))
    (should-not (ebp-store-known-p
                 store ebp-store-test-pair-a ebp-store-test-event-a))
    (should (ebp-store-known-p
             store ebp-store-test-pair-a ebp-store-test-event-b))
    (should (= 1 (length (ebp-store-list-work store))))))

(ert-deftest ebp-sqlite-close-is-idempotent-and-fails-closed-afterward ()
  (ebp-store-test--with-store (store file)
    (should (ebp-store-close store))
    (should (ebp-store-close store))
    (should-error
     (ebp-store-known-p
      store ebp-store-test-pair-a ebp-store-test-event-a)
     :type 'ebp-store-unavailable)
    (should-error (ebp-store-list-work store)
                  :type 'ebp-store-unavailable)))

(provide 'ebp-store-test)
;;; ebp-store-test.el ends here
