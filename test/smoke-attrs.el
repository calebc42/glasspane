;;; smoke-attrs.el --- W9-b: §16.5 universal attributes render -*- lexical-binding: t; -*-

;; Push a surface exercising the universal attributes (padding/pad, sizes,
;; fill_fraction, weight, bg, corner, border, alpha, clip, key) on core
;; nodes. PASS = the update is APPLIED (validation accepts the attributed
;; tree) and the app stays alive rendering it; the visual check is by eye.

(require 'ebp)

(let* ((applied nil)
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-attrs-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 16
              :children
              [(:t "text" :text "Universal attrs" :style "headline"
                :pad (:bottom 12))
               (:t "box" :bg "#e3f2fd" :corner 12 :padding 16 :key "card1"
                :border (:width 2 :color "primary")
                :children [(:t "text" :text "bg + corner + border + pad")])
               (:t "spacer" :height 8)
               (:t "row" :padding 4
                :children [(:t "box" :bg "#ffcdd2" :height 40 :weight 1
                            :children [(:t "text" :text "w1")])
                           (:t "spacer" :width 8)
                           (:t "box" :bg "#c8e6c9" :height 40 :weight 2
                            :children [(:t "text" :text "w2")])])
               (:t "spacer" :height 8)
               (:t "box" :bg "#fff9c4" :width 200 :height 40 :alpha 0.5
                :corner (:top_start 16 :bottom_end 16) :clip t
                :children [(:t "text" :text "alpha + per-corner + clip")])
               (:t "divider" :padding 8)
               (:t "text" :text "min/max sizing" :max_lines 1)
               (:t "box" :bg "#d1c4e9" :min_height 30 :max_width 240
                :fill_fraction 0.9
                :children [(:t "text" :text "fill_fraction 0.9")])])
            :callback
            (lambda (status error)
              (message "ATTRS status=%S error=%S" status error)
              (setq applied (equal status "applied"))))))))
  (cl-loop repeat 100 until applied do (accept-process-output nil 0.1))
  (cl-loop repeat 30 do (accept-process-output nil 0.1))
  (message "attrs smoke: applied=%S state=%s" applied (ebp-client-state client))
  (kill-emacs (if applied 0 1)))

;;; smoke-attrs.el ends here
