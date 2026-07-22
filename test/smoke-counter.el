;;; smoke-counter.el --- W5 gate: the counter round trip -*- lexical-binding: t; -*-

;; Run with the companion app open and the loopback forwarded, then tap
;; the +1 button on the device (or `adb shell input tap ...`).  Each tap
;; travels: Compose -> dispatchAction -> event.action request ->
;; registered handler here -> accepted (receipt committed) -> re-push of
;; the surface at a new revision -> tablet re-renders.  Prints one line
;; per event; runs for 45 seconds then reports the final count.

(require 'ebp)

(let* ((count 0)
       (receipts (make-temp-file "ebp-counter-receipts"))
       (push-counter
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           `(:t "column" :padding 24
             :children [(:t "text" :style "headline"
                         :text ,(format "Count: %d" count))
                        (:t "spacer" :height 16)
                        (:t "button" :label "+1"
                         :on_tap (:action "demo.increment"))
                        (:t "spacer" :height 16)
                        (:t "text" :style "caption"
                         :text "each tap is an event.action request; each count a new revision")]))))
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file receipts
         :ready-function (lambda (c) (funcall push-counter c)))))
  (ebp-client-register-action
   client "demo.increment"
   (lambda (c params)
     (cl-incf count)
     (message "event %s -> count %d (revision_seen %s)"
              (plist-get params :event_id) count
              (plist-get params :revision_seen))
     (funcall push-counter c)
     'accepted))
  (cl-loop repeat 450 do (accept-process-output nil 0.1))
  (message "final count: %d (state %s)" count (ebp-client-state client))
  (delete-file receipts)
  (kill-emacs (if (> count 0) 0 1)))

;;; smoke-counter.el ends here
