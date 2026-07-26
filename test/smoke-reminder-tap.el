;;; smoke-reminder-tap.el --- JA-1 device gate: reminder fires + tap returns -*- lexical-binding: t; -*-

;; The JA-1 reminders exit smoke.  What only hardware can prove: the
;; exact alarm fires as a REAL notification at at_ms, and tapping it
;; enters the Section 14 pipeline carrying the Companion-injected
;; :owner/:reminder_id args with NO surface context (the SPEC 14.4 omit
;; rule for reminder events — the D1 correction this rung recorded).
;;
;; Phases:
;;   1. arm via jetpacs-reminders-set (owner "org.smoke", fires +15 s)
;;      -> ARMED PASS count=1
;;   2. the runner taps the fired notification -> handler prints
;;      TAP PASS owner=... id=..., asserts params carries NO :surface
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-device)

(defvar smoke-rt--fails 0)
(defun smoke-rt--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-rt--fails (1+ smoke-rt--fails))))

(defun smoke-rt--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(defvar smoke-rt--armed :unset)
(defvar smoke-rt--tap nil)

(with-jetpacs-owner "org.smoke"
  (jetpacs-defaction "smoke.reminder-tapped"
    (lambda (args params)
      (setq smoke-rt--tap
            (list :owner (plist-get args :owner)
                  :reminder-id (plist-get args :reminder_id)
                  :k (plist-get args :k)
                  :surface (plist-get params :surface)))
      (message "TAPPED %S" smoke-rt--tap)
      'accepted)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("reminders.owner")
        :receipt-file (make-temp-file "smoke-rt-receipts"))))

  (smoke-rt--drain 20 (lambda () (jetpacs-connected-p)))
  (smoke-rt--check "session reaches READY" (jetpacs-connected-p))
  (smoke-rt--check "reminders.owner granted"
                   (jetpacs-granted-p "reminders.owner"))

  (when (jetpacs-connected-p)
    (with-jetpacs-owner "org.smoke"
      (jetpacs-reminders-set
       (list (list :id "tap1" :title "JA-1 smoke reminder"
                   :body "tap me"
                   :at_ms (+ (round (* 1000 (float-time))) 15000)
                   :on_tap (jetpacs-action "smoke.reminder-tapped"
                                           :args '(:k "v")
                                           :when-offline 'queue :ttl-s 600)))
       :callback (lambda (count err)
                   (setq smoke-rt--armed (if err (list 'err err) count)))))
    (smoke-rt--drain 10 (lambda () (not (eq smoke-rt--armed :unset))))
    (smoke-rt--check "reminder armed (count 1)"
                     (eql smoke-rt--armed 1)
                     (format "%S" smoke-rt--armed))
    (smoke-rt--check "mirror adopted the confirmed set"
                     (= 1 (plist-get (or (jetpacs-reminders "org.smoke")
                                         '(:count 0))
                                     :count)))
    (princ "ARMED-WAIT-FOR-FIRE\n") (message "ARMED-WAIT-FOR-FIRE")

    ;; The alarm fires at +15 s; the runner taps the notification.
    (smoke-rt--drain 120 (lambda () smoke-rt--tap))
    (smoke-rt--check "tap dispatched back into Emacs"
                     (and smoke-rt--tap t))
    (when smoke-rt--tap
      (smoke-rt--check "Companion injected :owner"
                       (equal (plist-get smoke-rt--tap :owner) "org.smoke")
                       (format "%S" (plist-get smoke-rt--tap :owner)))
      (smoke-rt--check "Companion injected :reminder_id"
                       (equal (plist-get smoke-rt--tap :reminder-id) "tap1"))
      (smoke-rt--check "authored args survived"
                       (equal (plist-get smoke-rt--tap :k) "v"))
      (smoke-rt--check "NO surface context (SPEC 14.4 omit rule)"
                       (null (plist-get smoke-rt--tap :surface))
                       (format "%S" (plist-get smoke-rt--tap :surface)))))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-rt--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-rt--fails))
(kill-emacs (if (zerop smoke-rt--fails) 0 1))

;;; smoke-reminder-tap.el ends here
