;;; smoke-editor.el --- W7 editor-sync device smoke -*- lexical-binding: t; -*-
;; Push an editor surface, then type on the device; Emacs's mirror updates.
(require 'ebp)
(let* ((seen "")
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("editor.sync")
         :receipt-file (make-temp-file "ebp-ed-receipts")
         :edit-change-function
         (lambda (_c doc eid text)
           (setq seen text)
           (message "MIRROR %s/%s = %S" doc eid text))
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 24
              :children [(:t "text" :style "headline" :text "Editor sync")
                         (:t "editor" :id "body" :document "doc:notes"
                          :value "org: ")]))))))
  (cl-loop repeat 600 do (accept-process-output nil 0.1))
  (message "editor smoke: state=%s final=%S" (ebp-client-state client) seen)
  (kill-emacs 0))
;;; smoke-editor.el ends here
