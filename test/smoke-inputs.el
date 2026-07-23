;;; smoke-inputs.el --- W9-d: §17.4 input nodes -*- lexical-binding: t; -*-

;; Push checkbox / discrete slider / disabled button (+ the other input
;; families for visual render). The harness drives taps/swipes via adb while
;; this client records state.changed + event.action arrivals in order.
;; Assertions (§17.4):
;;   1. a checkbox flip produces state.changed (boolean) BEFORE its on_change
;;      action carrying the boolean in args.value;
;;   2. the discrete slider publishes an EXACT authored number (9, not 8.97);
;;   3. enabled:false suppresses dispatch entirely (demo.never never arrives).
;; Exit 0 iff 1 holds whenever the tap landed; failures print the event log.

(require 'ebp)

(defvar ebp-smoke--events nil)

(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-inputs-receipts")
         :state-changed-function
         (lambda (_c _surface _rev id value)
           (push (list :state id value) ebp-smoke--events)
           (message "STATE %s = %S" id value))
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "column" :padding 16
              :children
              [(:t "text" :text "Input nodes" :style "headline")
               (:t "checkbox" :id "cb" :label "Flip me"
                :on_change (:action "demo.cb"))
               (:t "switch" :id "sw" :label "Switch me")
               (:t "slider" :id "sl" :values [1 5 9]
                :on_change (:action "demo.sl"))
               (:t "row"
                :children [(:t "button" :label "Never" :enabled :json-false
                            :on_tap (:action "demo.never"))
                           (:t "spacer" :width 8)
                           (:t "icon_button" :icon "add" :badge "2"
                            :on_tap (:action "demo.iconbtn"))
                           (:t "spacer" :width 8)
                           (:t "chip" :label "Chip" :icon "label"
                            :on_tap (:action "demo.chip"))
                           (:t "spacer" :width 8)
                           (:t "assist_chip" :label "Assist"
                            :on_tap (:action "demo.assist"))
                           (:t "spacer" :width 8)
                           (:t "menu" :icon "more_vert"
                            :items [(:label "One" :on_tap (:action "demo.m1"))])])
               (:t "enum_list" :id "en" :multi_select t
                :options [(:label "Alpha" :value "a")
                          (:label "Beta" :value "b")
                          (:label "Gamma" :value 3)]
                :on_change (:action "demo.en"))
               (:t "row"
                :children [(:t "date_button" :label "Pick date"
                            :value "2026-07-23" :on_pick (:action "demo.date"))
                           (:t "spacer" :width 8)
                           (:t "time_button" :label "Pick time"
                            :value "14:30" :on_pick (:action "demo.time"))])])
            :callback (lambda (status error)
                        (message "INPUTS status=%S error=%S" status error)))))))
  (dolist (a '("demo.cb" "demo.sl" "demo.never" "demo.iconbtn" "demo.chip"
               "demo.assist" "demo.m1" "demo.en" "demo.date" "demo.time"))
    (ebp-client-register-action
     client a
     (lambda (_c params)
       (push (list :action (plist-get params :action)
                   (plist-get (plist-get params :args) :value))
             ebp-smoke--events)
       (message "ACTION %s value=%S" (plist-get params :action)
                (plist-get (plist-get params :args) :value))
       'accepted)))
  ;; 45s window for the adb driver to tap/swipe.
  (cl-loop repeat 450 do (accept-process-output nil 0.1))
  (let* ((events (nreverse ebp-smoke--events))
         (cb-state (cl-position-if (lambda (e) (and (eq (car e) :state)
                                                    (equal (nth 1 e) "cb")))
                                   events))
         (cb-action (cl-position-if (lambda (e) (and (eq (car e) :action)
                                                     (equal (nth 1 e) "demo.cb")))
                                    events))
         (never (cl-find-if (lambda (e) (and (eq (car e) :action)
                                             (equal (nth 1 e) "demo.never")))
                            events))
         (sl-action (cl-find-if (lambda (e) (and (eq (car e) :action)
                                                 (equal (nth 1 e) "demo.sl")))
                                events))
         (ok t))
    (message "EVENTS %S" events)
    ;; 3: a disabled control never dispatches.
    (when never (message "FAIL disabled button dispatched") (setq ok nil))
    ;; 1: state-before-action for the checkbox (when the tap landed).
    (cond ((null cb-action) (message "NOTE checkbox tap did not land"))
          ((null cb-state) (message "FAIL on_change without state.changed")
           (setq ok nil))
          ((> cb-state cb-action)
           (message "FAIL state.changed after on_change") (setq ok nil)))
    ;; 2: the discrete slider publishes an exact authored number.
    (when (and sl-action (not (memq (nth 2 sl-action) '(1 5 9))))
      (message "FAIL slider value %S not an authored number" (nth 2 sl-action))
      (setq ok nil))
    (message "inputs smoke: ok=%S cb=%S sl=%S" ok (and cb-action t)
             (and sl-action (nth 2 sl-action)))
    (kill-emacs (if ok 0 1))))

;;; smoke-inputs.el ends here
