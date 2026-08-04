;;; ebp-store.el --- Durable EBP action-store contract -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Storage-independent contract for the Emacs endpoint's SPEC 14.4 durable
;; EventId receipts and work items.  This module names protocol-domain
;; operations only.  It deliberately knows nothing about SQLite, files,
;; JSON-RPC, Jetpacs, UI policy, or application effects.
;;
;; An admitted event owns exactly one durable work item.  A backend must
;; commit the receipt and work atomically before returning `admitted'.  A
;; completed work item is removed while its receipt remains available for
;; duplicate suppression.  Work that cannot safely proceed remains durable;
;; there is no terminal state that silently discards an accepted effect.

;;; Code:

(require 'cl-lib)

(define-error 'ebp-store-error "EBP durable store error")
(define-error 'ebp-store-unavailable "EBP durable store unavailable"
  'ebp-store-error)
(define-error 'ebp-store-stale-lease "EBP durable work lease is stale"
  'ebp-store-error)

(defconst ebp-store-minimum-retention-ms 604800000
  "SPEC 14.4's minimum accepted-EventId retention in milliseconds.")

(cl-defstruct (ebp-store-work
               (:constructor ebp-store-work-create))
  "One durable application work item and, when claimed, its lease."
  work-id
  pairing-id
  event-id
  action
  payload-json
  accepted-at-ms
  state
  attempt-count
  available-at-ms
  lease-id
  lease-until-ms
  last-error-kind
  updated-at-ms)

(cl-defgeneric ebp-store-known-p (store pairing-id event-id)
  "Return non-nil when STORE has accepted EVENT-ID for PAIRING-ID.")

(cl-defgeneric ebp-store-admit
    (store pairing-id event-id action payload-json now-ms)
  "Atomically admit EVENT-ID and its application work into STORE.

PAIRING-ID scopes duplicate identity.  ACTION identifies the registered
application worker; PAYLOAD-JSON is its already-serialized, minimal durable
input.  NOW-MS is a caller-supplied local timestamp for deterministic tests.

Return exactly `admitted' after receipt and work commit, or `duplicate' when
the pairing already owns EVENT-ID.  Signal `ebp-store-error' for every
storage ambiguity or failure.")

(cl-defgeneric ebp-store-claim-next
    (store worker-id now-ms lease-ms &optional pairing-id)
  "Atomically claim the oldest runnable work in STORE.

A pending item is runnable at or after its availability time; a leased item
is runnable again at or after lease expiry.  Limit the search to PAIRING-ID
when non-nil.  Return nil or an `ebp-store-work' with a fresh lease ID.")

(cl-defgeneric ebp-store-complete (store work now-ms)
  "Lease-check WORK, mark its receipt complete, and erase its payload.

The completion-marker update and work-row deletion must be one transaction.
Signal `ebp-store-stale-lease' when WORK no longer owns the current lease.")

(cl-defgeneric ebp-store-retry
    (store work now-ms next-at-ms error-kind)
  "Lease-check WORK and return it to pending state at NEXT-AT-MS.

ERROR-KIND is a bounded symbolic diagnostic, never an arbitrary exception
message or protocol payload.")

(cl-defgeneric ebp-store-block (store work now-ms error-kind)
  "Lease-check WORK and retain it durably in non-runnable blocked state.")

(cl-defgeneric ebp-store-list-work (store &optional pairing-id state)
  "Return STORE's work ordered by admission.

Limit results to PAIRING-ID and one of `pending', `leased', or `blocked'
when those arguments are non-nil.  This inspection API must not claim work.")

(cl-defgeneric ebp-store-forget-pairing (store pairing-id)
  "Atomically erase PAIRING-ID's receipts and work from STORE.

Return the number of pairing partitions removed.  Other pairings must be
unchanged.")

(cl-defgeneric ebp-store-prune (store now-ms retention-ms)
  "Prune eligible completed receipts from STORE.

RETENTION-MS must be at least `ebp-store-minimum-retention-ms'.  A receipt
with pending, leased, or blocked work is never eligible.  Return the number
of receipts removed.")

(cl-defgeneric ebp-store-close (store)
  "Close STORE.  Repeated close calls are harmless.")

(provide 'ebp-store)
;;; ebp-store.el ends here
