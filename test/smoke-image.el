;;; smoke-image.el --- W9-j image + guard stack smoke -*- lexical-binding: t; -*-
;; Push a data:image/png (a red square) and an https image pointed at loopback.
;; PASS is visual (screenshot): the data image renders as a red square; the
;; loopback https image is SSRF-rejected and shows the neutral placeholder
;; (broken-image glyph), never any response content.
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-image-receipts")
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 20 :spacing 16
             :children
             [(:t "text" :style "title" :text "Images")
              (:t "text" :text "data:image/png (should be a red square):")
              (:t "image" :width 120 :height 120 :content_description "red square"
               :url "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHgAAAB4CAYAAAA5ZDbSAAABLUlEQVR4nO3RMQ0AIADAMDRx418FXkAGyejRf8nGnuvQNV4HYDAGY/CnDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7gOIPjDI4zOM7guAsKYZHBjX6WswAAAABJRU5ErkJggg==")
              (:t "text" :text "https loopback (SSRF -> placeholder):")
              (:t "image" :width 120 :height 120 :content_description "blocked"
               :url "https://127.0.0.1:9/secret.png")])))
          (message "IMAGE surface pushed"))))
  (cl-loop repeat 80 do (accept-process-output nil 0.1))
  (message "image smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-image.el ends here
