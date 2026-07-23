;;; smoke-durable-reminder.el --- W8: reminder at-most-once -*- lexical-binding: t; -*-

;; SPEC 18.6: a reminder is presented at most once for its accepted
;; (owner, id, at_ms) tuple; fired state persists BEFORE presentation, so a
;; force-stop + relaunch never re-presents it. This smoke only ARMS the
;; reminder (~6s out) and exits; the alarm fires on-device with no session, and
;; the harness inspects ebp-reminders.json (fired receipt) and the alarm table
;; before/after a force-stop to confirm at-most-once.

(require 'ebp)

(let* ((offset (string-to-number (or (getenv "EBP_AT_OFFSET") "6")))
       (at (round (* 1000 (+ offset (float-time)))))
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("surfaces.notification" "reminders.owner")
         :receipt-file (make-temp-file "ebp-rem-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-reminders-set
            c "org.agenda"
            (vector (list :id "standup" :title "Standup" :body "Room 3"
                          :at_ms at))
            :callback (lambda (count err)
                        (message "REMINDERS-SET count=%s err=%S at=%d" count err at)))))))
  (cl-loop repeat 100 until (eq (ebp-client-state client) 'ready)
           do (accept-process-output nil 0.1))
  (cl-loop repeat 20 do (accept-process-output nil 0.1))
  (message "reminder armed at=%d now=%d state=%s"
           at (round (* 1000 (float-time))) (ebp-client-state client))
  (kill-emacs 0))

;;; smoke-durable-reminder.el ends here
