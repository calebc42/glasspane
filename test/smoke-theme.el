;;; smoke-theme.el --- W7 theme atom device smoke -*- lexical-binding: t; -*-
;; Push a surface, then force dark; the app flips to a dark scheme.
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-theme-receipts")
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 24
             :children [(:t "text" :style "headline" :text "Theme: forced dark")
                        (:t "text" :text "pushed via theme.set dark=true")]))
          (ebp-client-theme-set c :dark t)))))
  (cl-loop repeat 60 do (accept-process-output nil 0.1))
  (message "theme smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-theme.el ends here
