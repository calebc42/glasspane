;;; smoke-disabled.el --- RB-5 disabled editor toolbar inert -*- lexical-binding: t; -*-
;; A DISABLED (enabled:false) local editor with a toolbar. The driver taps the
;; Demote toolbar op. PASS: NO state.changed arrives (the toolbar is inert).
(require 'ebp)
(defvar smoke-states nil)
(let ((client (ebp-connect "127.0.0.1" 8765 :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme") :receipt-file (make-temp-file "ebp-dis")
        :state-changed-function (lambda (_c _s _r id v) (push (cons id v) smoke-states)
                                  (message "STATE %s=%S" id v))
        :ready-function
        (lambda (c)
          (ebp-client-surface-update c "app:main"
           '(:t "column" :padding 24 :spacing 12
             :children [(:t "text" :style "title" :text "disabled editor")
                        (:t "editor" :id "ed" :value "* task" :publish_state t
                         :enabled :json-false
                         :toolbar [(:label "Demote" :line "demote")])]))))))
  (cl-loop repeat 400 do (accept-process-output nil 0.1))
  (message "disabled smoke: states=%S" (nreverse smoke-states))
  (kill-emacs (if smoke-states 1 0)))
