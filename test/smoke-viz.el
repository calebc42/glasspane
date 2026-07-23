;;; smoke-viz.el --- W9-k visualization §17.5 smoke -*- lexical-binding: t; -*-
;; Push a chart (bar, tappable points), a canvas (line/rect/circle/path/text),
;; and a month_grid (marks + selected + on_day_tap). The driver taps a chart
;; point and a day cell.
;; PASS: on_point_tap returns the COMPLETE authored point object (x/y/meta),
;; and on_day_tap returns the tapped ISO date.
(require 'ebp)

(defvar ebp-smoke--events nil)

(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-viz-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 16 :spacing 16
              :children
              [(:t "text" :style "title" :text "Viz")
               (:t "chart" :kind "bar" :height 160
                :summary "sales by week"
                :series [(:name "w" :color "primary"
                          :points [(:x 0 :y 10 :meta (:label "Mon"))
                                   (:x 1 :y 24 :meta (:label "Tue"))
                                   (:x 2 :y 16 :meta (:label "Wed"))
                                   (:x 3 :y 30 :meta (:label "Thu"))])]
                :on_point_tap (:action "demo.point"))
               (:t "canvas" :width 300 :height 100
                :ops [(:op "rect" :x 4 :y 4 :width 90 :height 90
                       :fill "secondary")
                      (:op "circle" :cx 150 :cy 50 :radius 40 :color "primary"
                       :stroke_width 3)
                      (:op "line" :x1 200 :y1 10 :x2 290 :y2 90
                       :color "tertiary" :width 4)
                      (:op "path" :points [(:x 200 :y 90) (:x 245 :y 30)
                                           (:x 290 :y 90)]
                       :color "primary" :closed t)
                      (:op "bogus" :x 0 :y 0)
                      (:op "text" :x 10 :y 98 :text "canvas" :size 14)])
               (:t "month_grid" :month "2026-07"
                :selected "2026-07-15"
                :marks (:2026-07-10 (:dots 2 :color "primary")
                        :2026-07-20 (:dots 1))
                :on_day_tap (:action "demo.day")
                :on_month_change (:action "demo.month"))])
            :callback (lambda (status error)
                        (message "VIZ status=%S error=%S" status error)))))))
  (dolist (a '("demo.point" "demo.day" "demo.month"))
    (ebp-client-register-action
     client a
     (lambda (_c params)
       (push (list (plist-get params :action) (plist-get params :args))
             ebp-smoke--events)
       (message "ACTION %s args=%S" (plist-get params :action)
                (plist-get params :args))
       'accepted)))
  (cl-loop repeat 500 do (accept-process-output nil 0.1))
  (let* ((events (nreverse ebp-smoke--events))
         (point (assoc "demo.point" events))
         (day (assoc "demo.day" events))
         (ok t))
    (message "EVENTS %S" events)
    (when point
      (let ((v (plist-get (cadr point) :value)))
        ;; §17.5: the complete authored point object, incl. its meta.
        (unless (and (plist-get v :x) (plist-get v :y)
                     (plist-get v :meta))
          (message "FAIL point value incomplete: %S" v) (setq ok nil))))
    (when day
      (unless (string-match-p "2026-07-[0-9][0-9]"
                              (format "%s" (plist-get (cadr day) :value)))
        (message "FAIL day value %S" (plist-get (cadr day) :value))
        (setq ok nil)))
    (message "viz smoke: point=%S day=%S ok=%S"
             (and point (plist-get (cadr point) :value))
             (and day (plist-get (cadr day) :value)) ok)
    (kill-emacs (if (and point day ok) 0 1))))
;;; smoke-viz.el ends here
