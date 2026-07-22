;;; smoke-dialog.el --- W7 dialog round trip -*- lexical-binding: t; -*-

;; With the app open and 127.0.0.1:8765 forwarded:
;;   emacs -Q --batch -L emacs -l test/smoke-dialog.el
;; On READY it shows a rename dialog; tap OK (or Cancel) on the device.
;; Exit 0 once the dialog concludes; prints the status and captured field.

(require 'ebp)

(let* ((done nil)
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("surfaces.dialog")
         :ready-function
         (lambda (c)
           (ebp-client-dialog-show
            c "rename"
            '(:t "column" :padding 8
              :children [(:t "text" :style "headline" :text "Rename")
                         (:t "spacer" :height 8)
                         (:t "text_input" :id "name" :label "New name"
                          :single_line t)
                         (:t "spacer" :height 8)
                         (:t "button" :label "OK"
                          :on_tap (:builtin "dialog.submit"
                                   :capture_fields ["name"]))
                         (:t "button" :label "Cancel"
                          :on_tap (:builtin "dialog.dismiss"))])
            :callback
            (lambda (status result error)
              (message "dialog concluded: status=%s fields=%S error=%S"
                       status (and result (plist-get result :fields)) error)
              (setq done t)))))))
  (cl-loop repeat 600 until done do (accept-process-output nil 0.1))
  (message "final: done=%s state=%s" done (ebp-client-state client))
  (kill-emacs (if done 0 1)))

;;; smoke-dialog.el ends here
