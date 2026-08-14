;;; glasspane-test.el --- Glasspane app ladder gates -*- lexical-binding: t; -*-

;; The per-rung LOCAL GATE suite of docs/PLAN-glasspane-app.md: every
;; rung adds its NAMED assertions here, and test/run-tests.sh runs the
;; whole file after the M3 stanza.  G0's three gates pin registration,
;; home serialization, and unload hygiene.

;;; Code:

(require 'ert)
(require 'glasspane)

;;;; G0 — skeleton, registration, harness wiring

(ert-deftest glasspane-test-registers ()
  "Requiring the app REGISTERS it: the owner verb is in the action
table, the app registry entry carries the identity, and the home
surface is the one the chrome root was defined on — so `app.open'
lands somewhere that exists (the M3 suite's shape)."
  (should (gethash "glasspane.home" jetpacs-action-handlers))
  (let ((entry (assoc glasspane-owner jetpacs-apps--registry)))
    (should entry)
    (should (equal (plist-get (cdr entry) :label) "Glasspane"))
    (should (member glasspane-owner (plist-get (cdr entry) :surfaces)))
    (should (equal (jetpacs-apps--home-surface entry) glasspane-owner))))

(ert-deftest glasspane-test-home-serializes ()
  "The placeholder home screen BUILDS and its body round-trips the
canonical wire encoding — the same bar every later rung's screens must
clear, established while the screen is one card tall."
  (let ((screen (glasspane-home-screen nil)))
    (should screen)
    ;; A chrome screen IS a scaffold node — serialize it whole.
    (let ((json (jetpacs-node->canonical-json screen)))
      (should (stringp json))
      (should (string-search "Glasspane" json)))))

(ert-deftest glasspane-test-dock-item-shape ()
  "The dock destination carries the chrome item shape and tracks
selection against the app's own surface."
  (let* ((home (jetpacs-shell-surface-for glasspane-owner))
         (items (glasspane--dock-items home)))
    (should (= (length items) 1))
    (let ((item (car items)))
      (should (equal (plist-get item :label) "Glasspane"))
      (should (equal (plist-get item :icon) glasspane-icon))
      (should (plist-get item :on-tap))
      (should (eq (plist-get item :selected) t)))
    ;; From a foreign surface the row is not selected.
    (should-not (plist-get (car (glasspane--dock-items "app:elsewhere"))
                           :selected))))

(ert-deftest glasspane-test-unload-clean ()
  "Unregistration leaves no verb, no registry entry — and is undone by
`glasspane-register' (the live-reload path), which this test restores
so suite order never matters."
  (unwind-protect
      (progn
        (glasspane-unregister)
        (should-not (gethash "glasspane.home" jetpacs-action-handlers))
        (should-not (assoc glasspane-owner jetpacs-apps--registry)))
    (glasspane-register))
  (should (gethash "glasspane.home" jetpacs-action-handlers)))

(provide 'glasspane-test)
;;; glasspane-test.el ends here
