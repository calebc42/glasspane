;;; smoke-snackbar.el --- W7 scaffold+snackbar device smoke -*- lexical-binding: t; -*-
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-snack-receipts")
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "scaffold"
             :top_bar (:t "text" :style "headline" :text "Scaffold + Snackbar")
             :body (:t "column" :padding 24
                    :children [(:t "text" :text "the snackbar below is scaffold chrome, not a toast")])
             :snackbar "Saved to inbox (v2)"
             :snackbar_action (:label "UNDO"
                               :on_tap (:action "demo.undo"))))))))
  (ebp-client-register-action client "demo.undo"
                              (lambda (_c _p) (message "UNDO tapped") 'accepted))
  (cl-loop repeat 120 do (accept-process-output nil 0.1))
  (message "snackbar smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-snackbar.el ends here
