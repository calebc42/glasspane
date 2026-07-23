;;; smoke-widgets.el --- W9-c: §17.2 content nodes render -*- lexical-binding: t; -*-

;; Push a surface exercising the seven newly advertised content nodes
;; (rich_text, icon, badge, section_header, empty_state, progress,
;; date_stamp). PASS = the update is APPLIED and the app stays alive.

(require 'ebp)

(let* ((applied nil)
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-widgets-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 16
              :children
              [(:t "section_header" :title "Content nodes"
                :trailing (:t "badge" :label "7"))
               (:t "rich_text" :style "body"
                :spans [(:text "plain, ")
                        (:text "bold 700, " :font_weight 700)
                        (:text "italic, " :italic t)
                        (:text "mono, " :mono t)
                        (:text "underlined, " :underline t)
                        (:text "colored, " :color "primary")
                        (:text "tappable" :on_tap (:action "demo.span"))])
               (:t "spacer" :height 8)
               (:t "row" :padding 4
                :children [(:t "icon" :name "star" :size 32 :color "primary"
                            :badge "3" :content_description "Starred")
                           (:t "spacer" :width 12)
                           (:t "badge" :label "TODO" :color "error" :icon "flag")
                           (:t "spacer" :width 12)
                           (:t "badge" :label "")])
               (:t "spacer" :height 8)
               (:t "row"
                :children [(:t "date_stamp" :day 23 :month "JUL"
                            :month_index 7 :year 2026 :time "14:30")
                           (:t "spacer" :width 16)
                           (:t "progress" :variant "circular")
                           (:t "spacer" :width 16)
                           (:t "progress" :variant "linear" :value 0.6
                            :width 120)])
               (:t "empty_state" :icon "inbox" :title "Nothing here"
                :caption "This is the empty state"
                :action_label "Do something"
                :on_tap (:action "demo.empty"))])
            :callback
            (lambda (status error)
              (message "WIDGETS status=%S error=%S" status error)
              (setq applied (equal status "applied"))))))))
  (cl-loop repeat 100 until applied do (accept-process-output nil 0.1))
  (cl-loop repeat 30 do (accept-process-output nil 0.1))
  (message "widgets smoke: applied=%S state=%s" applied (ebp-client-state client))
  (kill-emacs (if applied 0 1)))

;;; smoke-widgets.el ends here
