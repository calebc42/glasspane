;;; smoke-views.el --- W9-f: view.switch + multi-view -*- lexical-binding: t; -*-

;; Push a multi-view surface (main/detail); the adb driver taps the
;; view.switch button. PASS = the device switches locally (visual) and Emacs
;; receives the generated view.switched action with args.view = "detail"
;; (SPEC 14.2).

(require 'ebp)

(defvar ebp-smoke--switched nil)

(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-views-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:initial_view "main"
              :views
              (:main (:t "column" :padding 24
                      :children [(:t "text" :text "Main view" :style "headline")
                                 (:t "button" :label "Go to detail"
                                  :on_tap (:builtin "view.switch"
                                           :view "detail"))])
               :detail (:t "column" :padding 24
                        :children [(:t "text" :text "Detail view"
                                    :style "headline")
                                   (:t "text" :text "switched locally")])))
            :callback (lambda (status error)
                        (message "VIEWS status=%S error=%S" status error)))))))
  ;; SPEC 14.2: allowlist the generated view.switched action.
  (ebp-client-register-action
   client "view.switched"
   (lambda (_c params)
     (setq ebp-smoke--switched (plist-get (plist-get params :args) :view))
     (message "SWITCHED view=%S" ebp-smoke--switched)
     'accepted))
  (cl-loop repeat 300 until ebp-smoke--switched
           do (accept-process-output nil 0.1))
  (message "views smoke: switched=%S state=%s"
           ebp-smoke--switched (ebp-client-state client))
  (kill-emacs (if (equal ebp-smoke--switched "detail") 0 1)))

;;; smoke-views.el ends here
