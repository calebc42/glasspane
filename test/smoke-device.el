;;; smoke-device.el --- W4 gate: elisp text on the phone -*- lexical-binding: t; -*-

;; Run with the companion app open on the device and the loopback
;; forwarded:   adb forward tcp:8765 tcp:8765
;;   emacs -Q --batch -L emacs -l test/smoke-device.el
;;
;; Uses the SPEC 9.3 known-answer pairing that the W4 companion smoke
;; build advertises. Exit 0 iff the handshake reaches READY and the
;; surface push returns applied.

(require 'ebp)

(let* ((token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw"))
       (push-status nil)
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token token
         :wants '("theme")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 24
              :children [(:t "text" :style "headline"
                          :text "Hello from Emacs 30.1")
                         (:t "divider")
                         (:t "text"
                          :text "EBP 2.0.0-draft — conformant wire, rung W4")
                         (:t "spacer" :height 16)
                         (:t "text" :style "caption"
                          :text "pushed over android-loopback-tcp via adb forward")])
            :callback (lambda (status _error) (setq push-status status)))))))
  (cl-loop repeat 100 until push-status
           do (accept-process-output nil 0.1))
  (message "smoke: state=%s push=%s close=%S"
           (ebp-client-state client) push-status
           (ebp-client-close-reason client))
  (kill-emacs (if (equal push-status "applied") 0 1)))

;;; smoke-device.el ends here
