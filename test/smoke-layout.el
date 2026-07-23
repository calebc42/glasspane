;;; smoke-layout.el --- W9-e: §17.3 layout nodes -*- lexical-binding: t; -*-

;; Push tabs / card-with-swipe / reorderable_list / table / collapsible /
;; flow_row / surface / lazy_column. The adb driver taps tab B, swipes the
;; card, and drag-reorders; this client records the arrivals.
;; Assertions:
;;   1. tabs on_change carries the settled index (1 after tapping tab B);
;;   2. the card swipe dispatches once with `direction` injected;
;;   3. a completed reorder injects from/to/order (order = item keys).
;; Exit 0 iff every gesture that LANDED carried the right shape.

(require 'ebp)

(defvar ebp-smoke--events nil)

(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-layout-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 12
              :children
              [(:t "tabs" :id "tabs1"
                :items [(:label "Tab A") (:label "Tab B")]
                :children [(:t "text" :text "page A")
                           (:t "text" :text "page B")]
                :on_change (:action "demo.tab"))
               (:t "spacer" :height 8)
               (:t "card" :swipe_end (:label "Done" :icon "check"
                                      :color "primary"
                                      :on_trigger (:action "demo.swipe"))
                :children [(:t "text" :text "Swipe me left")])
               (:t "spacer" :height 8)
               (:t "reorderable_list"
                :on_reorder (:action "demo.reorder")
                :items [(:t "text" :key "ra" :text "Item A")
                        (:t "text" :key "rb" :text "Item B")
                        (:t "text" :key "rc" :text "Item C")]
                :max_height 260)
               (:t "table"
                :rows [(:kind "header"
                        :cells [(:spans [(:text "Name")])
                                (:spans [(:text "Qty")])])
                       (:kind "rule")
                       (:kind "data"
                        :cells [(:spans [(:text "Apples")])
                                (:spans [(:text "3")])])]
                :aligns ["start" "end"]
                :on_add_row (:action "demo.addrow"))
               (:t "collapsible" :id "fold1"
                :header (:t "text" :text "Fold me" :style "title")
                :children [(:t "text" :text "hidden treasure")])
               (:t "flow_row" :spacing 6 :run_spacing 6
                :children [(:t "badge" :label "one")
                           (:t "badge" :label "two")
                           (:t "badge" :label "three")])
               (:t "surface" :color "surface_variant" :shape "rounded"
                :elevation 2 :padding 8
                :children [(:t "text" :text "on a surface")])
               (:t "lazy_column" :height 120 :spacing 4
                :children [(:t "text" :key "l1" :text "lazy one")
                           (:t "text" :key "l2" :text "lazy two")
                           (:t "text" :key "l3" :text "lazy three")])])
            :callback (lambda (status error)
                        (message "LAYOUT status=%S error=%S" status error)))))))
  (dolist (a '("demo.tab" "demo.swipe" "demo.reorder" "demo.addrow"))
    (ebp-client-register-action
     client a
     (lambda (_c params)
       (let ((args (plist-get params :args)))
         (push (list (plist-get params :action) args) ebp-smoke--events)
         (message "ACTION %s args=%S" (plist-get params :action) args))
       'accepted)))
  (cl-loop repeat 500 do (accept-process-output nil 0.1))
  (let* ((events (nreverse ebp-smoke--events))
         (tab (assoc "demo.tab" events))
         (swipes (cl-count "demo.swipe" events :key #'car :test #'equal))
         (reorder (assoc "demo.reorder" events))
         (ok t))
    (message "EVENTS %S" events)
    (cond ((null tab) (message "NOTE tab tap did not land"))
          ((not (equal (plist-get (cadr tab) :value) 1))
           (message "FAIL tab value %S /= 1" (plist-get (cadr tab) :value))
           (setq ok nil)))
    (when (> swipes 1) (message "FAIL swipe dispatched %d times" swipes)
          (setq ok nil))
    (when (and (= swipes 1)
               (not (equal (plist-get (cadr (assoc "demo.swipe" events))
                                      :direction)
                           "end")))
      (message "FAIL swipe direction missing/wrong") (setq ok nil))
    (when reorder
      (let ((args (cadr reorder)))
        (unless (and (plist-get args :from) (plist-get args :to)
                     (plist-get args :order))
          (message "FAIL reorder args incomplete: %S" args) (setq ok nil))))
    (message "layout smoke: ok=%S tab=%S swipe=%d reorder=%S"
             ok (and tab t) swipes (and reorder (cadr reorder)))
    (kill-emacs (if ok 0 1))))

;;; smoke-layout.el ends here
