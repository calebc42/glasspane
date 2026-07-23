;;; smoke-trigger.el --- W7 trigger device smoke -*- lexical-binding: t; -*-
;; Register a battery.level trigger from Emacs; drive the device battery with
;; `adb shell dumpsys battery set level N' to cross below 20; the Companion
;; fires trigger.fired back to Emacs and posts the on_fire notification.
(require 'ebp)
(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("triggers")
         :receipt-file (make-temp-file "ebp-trg-receipts")
         :ready-function
         (lambda (c)
           (message "TRIGGER-TYPES %S" (ebp-client-device-trigger-types c))
           (ebp-client-register-action
            c "trigger.fired"
            (lambda (_c params)
              (message "FIRED %S" (plist-get params :args))
              'accepted))
           (ebp-client-triggers-set
            c (vector
               (list :id "low-batt" :type "battery.level"
                     :params '(:below 20)
                     :policy "drop"
                     :on_fire (vector '(:notify (:text "Battery ${data.level}%")))))
            :callback
            (lambda (count error)
              (message "TRIGGERS-SET count=%S error=%S" count error)))))))
  ;; Drive the crossing from a shell:
  ;;   adb shell dumpsys battery set level 15   (then `... reset` to restore)
  (cl-loop repeat 600 do (accept-process-output nil 0.1))
  (message "trigger smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-trigger.el ends here
