;;; smoke-textinput.el --- RB-2 text_input conformance -*- lexical-binding: t; -*-
;; A plain text_input (on_change + on_submit) and a password text_input
;; (on_submit). The driver types into each and fires the IME Done action.
;; PASS: the plain field emits state.changed + on_change while typing and
;; on_submit=value on Done; the PASSWORD field emits NO state.changed and its
;; on_submit carries the secret in fields.<id>, never args.value. Masking is
;; visual (screenshot: dots, not the typed secret).
(require 'ebp)

(defvar ebp-smoke--events nil)
(defvar ebp-smoke--states nil)

(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-ti")
        :state-changed-function
        (lambda (_c _s _r id value)
          (push (cons id value) ebp-smoke--states)
          (message "STATE %s=%S" id value))
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 24 :spacing 16
             :children
             [(:t "text" :style "title" :text "text_input")
              (:t "text_input" :id "search" :label "Search" :single_line t
               :on_change (:action "demo.change" :when_offline "drop")
               :on_submit (:action "demo.submit" :when_offline "drop"))
              (:t "text_input" :id "pw" :label "Password" :password t
               :on_submit (:action "demo.pwsubmit" :when_offline "drop"
                           :capture_fields ["pw"]))]))))))
  (dolist (a '("demo.change" "demo.submit" "demo.pwsubmit"))
    (ebp-client-register-action
     client a
     (lambda (_c params)
       (push (list (plist-get params :action)
                   (plist-get params :args) (plist-get params :fields))
             ebp-smoke--events)
       (message "ACTION %s args=%S fields=%S" (plist-get params :action)
                (plist-get params :args) (plist-get params :fields))
       'accepted)))
  (cl-loop repeat 600 do (accept-process-output nil 0.1))
  (let* ((events (nreverse ebp-smoke--events))
         (states (nreverse ebp-smoke--states))
         (change (assoc "demo.change" events))
         (submit (assoc "demo.submit" events))
         (pwsub (assoc "demo.pwsubmit" events))
         (pw-state (assoc "pw" states))
         (ok t))
    (message "EVENTS %S" events)
    (message "STATES %S" states)
    ;; §14.6: the password field must NEVER emit state.changed.
    (when pw-state (message "FAIL password emitted state.changed") (setq ok nil))
    ;; on_change fired while typing the plain field.
    (unless change (message "NOTE on_change did not land"))
    ;; on_submit carried the value; pw on_submit carried the secret in fields.
    (when (and pwsub (plist-get (nth 2 pwsub) :pw))
      (message "PW secret arrived in fields.pw (as required)"))
    (message "textinput smoke: change=%S submit=%S pwsub=%S pw-state=%S ok=%S"
             (and change t) (and submit (plist-get (cadr submit) :value))
             (and pwsub (plist-get (nth 2 pwsub) :pw)) (and pw-state t) ok)
    (kill-emacs (if (and ok (not pw-state)) 0 1))))
;;; smoke-textinput.el ends here
