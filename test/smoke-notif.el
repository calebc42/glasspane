;;; smoke-notif.el --- W7 notification + reminder device smoke -*- lexical-binding: t; -*-
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("surfaces.notification" "reminders.owner")
        :receipt-file (make-temp-file "ebp-notif-receipts")
        :ready-function
        (lambda (c)
          ;; A notification:* surface -> a persistent system notification.
          (ebp-client-surface-update
           c "notification:build"
           '(:body (:t "column"
                    :children [(:t "text" :text "Build finished")
                               (:t "text" :text "org-agenda compiled in 4.2s")])
             :meta (:channel "builds" :priority "high")))
          ;; A reminder firing ~6 seconds from now.
          (ebp-client-reminders-set
           c "org.agenda"
           (vector (list :id "standup"
                         :title "Standup in 5 min"
                         :body "Room 3"
                         :at_ms (round (* 1000 (+ 6 (float-time))))))
           :callback (lambda (count err)
                       (message "reminders count=%s err=%S" count err)))))))
  (cl-loop repeat 120 do (accept-process-output nil 0.1))
  (message "notif smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-notif.el ends here
