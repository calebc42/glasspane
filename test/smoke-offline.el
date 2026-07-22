;;; smoke-offline.el --- W6 gate: the offline tap survives death -*- lexical-binding: t; -*-

;; Two phases, selected by the EBP_PHASE environment variable:
;;
;;   push  — connect, push a counter whose button queues offline
;;           (when_offline queue, ttl 1h), then exit: the session drops.
;;           Tap the button while disconnected (adb shell input tap),
;;           then force-stop and relaunch the app: the occurrence must
;;           survive in the durable queue file.
;;   drain — reconnect; the welcome must report the queued event; the
;;           barrier replay delivers it; the handler increments and
;;           pushes Count: 1. Exit 0 iff the event arrived.

(require 'ebp)

(defconst ebp-smoke--phase (or (getenv "EBP_PHASE") "push"))

(let* ((count 0)
       (push-counter
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           `(:t "column" :padding 24
             :children [(:t "text" :style "headline"
                         :text ,(format "Count: %d" count))
                        (:t "spacer" :height 16)
                        (:t "button" :label "+1"
                         :on_tap (:action "demo.increment"
                                  :when_offline "queue" :ttl_s 3600))
                        (:t "spacer" :height 16)
                        (:t "text" :style "caption"
                         :text "taps while disconnected queue durably and replay on reconnect")]))))
       (pushed nil)
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (expand-file-name "ebp-smoke-receipts"
                                         temporary-file-directory)
         :ready-function
         (lambda (c)
           (pcase ebp-smoke--phase
             ("push" (funcall push-counter c))
             (_ nil))))))
  (ebp-client-register-action
   client "demo.increment"
   (lambda (c params)
     (cl-incf count)
     (message "event %s -> count %d (queued_at %s)"
              (plist-get params :event_id) count
              (plist-get params :queued_at_ms))
     (funcall push-counter c)
     'accepted))
  (pcase ebp-smoke--phase
    ("push"
     (cl-loop repeat 100 until pushed
              do (accept-process-output nil 0.1)
              do (setq pushed (eq (ebp-client-state client) 'ready)))
     (cl-loop repeat 20 do (accept-process-output nil 0.1))
     (message "push phase done; disconnecting with the counter on screen")
     (kill-emacs 0))
    ("drain"
     (cl-loop repeat 150 until (> count 0)
              do (accept-process-output nil 0.1))
     (let ((summary (ebp-client-replay-summary client)))
       (message "drain: count=%d summary=%S state=%s"
                count summary (ebp-client-state client))
       (cl-loop repeat 20 do (accept-process-output nil 0.1))
       (kill-emacs (if (> count 0) 0 1))))))

;;; smoke-offline.el ends here
