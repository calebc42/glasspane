;;; smoke-toolbar.el --- W9-i editor toolbar §17.7 smoke -*- lexical-binding: t; -*-
;; A LOCAL editor (no document) with a §17.7 toolbar: a `line` demote op, a
;; `line-start` snippet, and a `${date}` block snippet. Local edits publish
;; state.changed (the editor is stateful), so the driver can observe the text
;; the toolbar produced. The adb driver taps each chip.
;; PASS: demote turns "* task" into "** task"; the TODO prefix and the date
;; each land in a later state.changed.
(require 'ebp)

(defvar ebp-smoke--states nil)

(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-toolbar-receipts")
        :state-changed-function
        (lambda (_c _surface _rev id value)
          (when (equal id "ed")
            (push value ebp-smoke--states)
            (message "STATE ed=%S" value)))
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 16
             :children
             [(:t "text" :style "title" :text "Toolbar")
              (:t "editor" :id "ed" :value "* task" :publish_state t
               :toolbar [(:label "Demote" :line "demote")
                         (:label "TODO" :snippet "TODO " :placement "line-start")
                         (:label "Date" :snippet "${date}" :placement "block")])]))))))
  (cl-loop repeat 500 do (accept-process-output nil 0.1))
  (let ((states (nreverse ebp-smoke--states)))
    (message "STATES %S" states)
    (let ((demoted (cl-some (lambda (s) (string-prefix-p "** task" s)) states))
          (todo (cl-some (lambda (s) (string-match-p "TODO " s)) states))
          (dated (cl-some (lambda (s) (string-match-p "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" s)) states)))
      (message "toolbar smoke: demote=%S todo=%S date=%S" demoted todo dated)
      (kill-emacs (if (and demoted todo dated) 0 1)))))
;;; smoke-toolbar.el ends here
