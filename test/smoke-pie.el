;;; smoke-pie.el --- W7 pie menu device smoke -*- lexical-binding: t; -*-
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme" "presentation.pie-menu")
        :receipt-file (make-temp-file "ebp-pie-receipts")
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 24
             :children [(:t "text" :style "headline" :text "Pie menu below")]))
          (ebp-client-pie-menu-show
           c "capture"
           [(:label "Todo"  :on_tap (:action "demo.todo"))
            (:label "Note"  :on_tap (:action "demo.note"))
            (:label "Event" :on_tap (:action "demo.event"))
            (:label "Link"  :on_tap (:action "demo.link"))]
           :center-label "Capture")))))
  (dolist (a '("demo.todo" "demo.note" "demo.event" "demo.link"))
    (ebp-client-register-action
     client a (lambda (_c params)
                (message "SELECTED %s args=%S" a (plist-get params :args))
                'accepted)))
  (cl-loop repeat 250 do (accept-process-output nil 0.1))
  (message "pie smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-pie.el ends here
