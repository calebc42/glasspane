;;; smoke-capability.el --- W7 capability device smoke -*- lexical-binding: t; -*-
;; Invoke Companion capabilities from Emacs: read the welcome device report,
;; buzz the device (vibrate), and read its clipboard back into Emacs.
(require 'ebp)
(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("capabilities")
         :receipt-file (make-temp-file "ebp-cap-receipts")
         :ready-function
         (lambda (c)
           (message "CAPS %S" (ebp-client-device-caps c))
           (ebp-client-capability-invoke
            c "vibrate" :args '(:ms 200)
            :callback (lambda (result error)
                        (message "VIBRATE result=%S error=%S" result error)))
           (ebp-client-capability-invoke
            c "clipboard.read"
            :callback (lambda (result error)
                        (message "CLIPBOARD result=%S error=%S" result error)))))))
  (cl-loop repeat 400 do (accept-process-output nil 0.1))
  (message "capability smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-capability.el ends here
