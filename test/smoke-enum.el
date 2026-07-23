;;; smoke-enum.el --- RB-4 enum_list value retention -*- lexical-binding: t; -*-
;; Push an enum_list [Apple,Banana,Cherry]; the driver taps Banana. Then a
;; same-identity re-push REORDERS the options to [Cherry,Banana,Apple].
;; PASS (visual, screenshot): Banana stays selected by VALUE after the reorder
;; (the old index-2 was Cherry, so an index-keyed impl would corrupt it).
;; The state.changed after the tap carries the value "b".
(require 'ebp)

(defvar ebp-smoke--states nil)

(defun smoke-enum--surface (client opts)
  (ebp-client-surface-update
   client "app:main"
   `(:t "column" :padding 24 :spacing 12
     :children [(:t "text" :style "title" :text "enum_list")
                (:t "enum_list" :id "pick"
                 :options ,opts
                 :on_change (:action "demo.pick" :when_offline "drop"))])))

(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-enum")
        :state-changed-function
        (lambda (_c _s _r id value)
          (when (equal id "pick")
            (push value ebp-smoke--states)
            (message "STATE pick=%S" value)))
        :ready-function
        (lambda (c)
          (smoke-enum--surface
           c [(:label "Apple" :value "a") (:label "Banana" :value "b")
              (:label "Cherry" :value "c")])))))
  (ebp-client-register-action
   client "demo.pick"
   (lambda (_c params) (message "PICK %S" (plist-get params :args)) 'accepted))
  ;; Phase 1: wait for the tap (driven externally) -> state "b".
  (cl-loop repeat 250 until ebp-smoke--states do (accept-process-output nil 0.1))
  ;; Phase 2: re-push with REORDERED options (same id).
  (smoke-enum--surface
   client [(:label "Cherry" :value "c") (:label "Banana" :value "b")
           (:label "Apple" :value "a")])
  (cl-loop repeat 200 do (accept-process-output nil 0.1))
  (let ((states (nreverse ebp-smoke--states)))
    (message "STATES %S" states)
    (message "enum smoke: first=%S" (car states))
    (kill-emacs (if (equal (car states) "b") 0 1))))
;;; smoke-enum.el ends here
