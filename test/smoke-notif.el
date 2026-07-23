;;; smoke-notif.el --- W9-l notification meta/actions device smoke -*- lexical-binding: t; -*-
;; Push a notification:* surface with §18.5 meta (high priority + category +
;; chronometer) and two actions: a "Snooze" (remote, dismiss:true) and a
;; "Reply" inline text reply. The driver expands the shade and taps Snooze.
;; PASS: the Snooze action tap routes back as demo.snooze (safe-admission
;; dismissal follows). Rendering (chronometer, both actions) is visual.
(require 'ebp)

(defvar ebp-smoke--events nil)

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
          (ebp-client-surface-update
           c "notification:build"
           '(:body (:t "column"
                    :children [(:t "text" :style "title" :text "Build finished")
                               (:t "text" :text "org-agenda compiled in 4.2s")])
             :meta (:channel "builds" :priority "high" :category "status"
                    :chronometer (:base_ms 0)
                    :actions [(:label "Snooze" :icon "snooze" :dismiss t
                               :on_tap (:action "demo.snooze"
                                        :when_offline "drop"))
                              (:label "Reply"
                               :input (:hint "Type a reply" :key "reply")
                               :on_tap (:action "demo.reply"
                                        :when_offline "drop"))])))))))
  (dolist (a '("demo.snooze" "demo.reply"))
    (ebp-client-register-action
     client a
     (lambda (_c params)
       (push (list (plist-get params :action)
                   (plist-get params :fields))
             ebp-smoke--events)
       (message "ACTION %s fields=%S" (plist-get params :action)
                (plist-get params :fields))
       'accepted)))
  (cl-loop repeat 700 do (accept-process-output nil 0.1))
  (let ((events (nreverse ebp-smoke--events)))
    (message "EVENTS %S" events)
    (message "notif smoke: snooze=%S state=%s"
             (and (assoc "demo.snooze" events) t) (ebp-client-state client))
    (kill-emacs (if (assoc "demo.snooze" events) 0 1))))
;;; smoke-notif.el ends here
