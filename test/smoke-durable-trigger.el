;;; smoke-durable-trigger.el --- W8: a trigger fires with no session -*- lexical-binding: t; -*-

;; The headline durable-offline claim (SPEC 21.1/21.2): a queue-policy trigger
;; admitted while Emacs is DISCONNECTED commits to the durable queue and is
;; delivered on the next connect via replay. Two phases (EBP_PHASE):
;;
;;   arm   — connect, set a battery.level below-20 queue trigger, wait ready,
;;           exit: the session drops but the firing service lives on.
;;           Externally, with Emacs gone:
;;             adb shell dumpsys battery set level 15   (crosses below 20)
;;           The service (no session) admits trigger.fired to the queue file.
;;   drain — reconnect; the barrier replay MUST deliver the trigger.fired the
;;           service admitted while dead. Exit 0 iff it arrived.

(require 'ebp)

(defconst ebp-smoke--phase (or (getenv "EBP_PHASE") "arm"))

(defconst ebp-smoke--expect
  (string-to-number (or (getenv "EBP_EXPECT") "1")))

(let* ((fired 0)
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("triggers")
         :receipt-file (expand-file-name "ebp-durtrig-receipts"
                                         temporary-file-directory)
         :ready-function
         (lambda (c)
           (when (equal ebp-smoke--phase "arm")
             (let* ((throttle (string-to-number (or (getenv "EBP_THROTTLE") "0")))
                    (entry (if (equal (getenv "EBP_TYPE") "boot")
                               (list :id "on-boot" :type "boot"
                                     :policy "queue" :ttl_s 3600
                                     :on_fire (vector '(:notify (:text "Booted"))))
                             (list :id "low-batt" :type "battery.level"
                                   :params '(:below 20)
                                   :policy "queue" :ttl_s 3600
                                   :on_fire (vector '(:notify (:text "Low ${data.level}%")))))))
               (when (> throttle 0)
                 (setq entry (plist-put entry :throttle_s throttle)))
               (ebp-client-triggers-set
                c (vector entry)
                :callback
                (lambda (count error)
                  (message "TRIGGERS-SET count=%S error=%S" count error)))))))))
  (ebp-client-register-action
   client "trigger.fired"
   (lambda (_c params)
     (cl-incf fired)
     (message "FIRED #%d %S (queued_at %s)"
              fired (plist-get params :args) (plist-get params :queued_at_ms))
     'accepted))
  (pcase ebp-smoke--phase
    ("arm"
     (cl-loop repeat 100 until (eq (ebp-client-state client) 'ready)
              do (accept-process-output nil 0.1))
     (cl-loop repeat 20 do (accept-process-output nil 0.1))
     (message "arm phase done; state=%s — disconnecting"
              (ebp-client-state client))
     (kill-emacs 0))
    ("drain"
     ;; Fixed window so EVERY replayed event is collected, then assert the
     ;; count: scenario (b) expects 1; (c) expects 1 (the throttled re-cross
     ;; that survived restart produced no second event).
     (cl-loop repeat 120 do (accept-process-output nil 0.1))
     (message "drain: fired=%d expect=%d summary=%S state=%s"
              fired ebp-smoke--expect (ebp-client-replay-summary client)
              (ebp-client-state client))
     (kill-emacs (if (= fired ebp-smoke--expect) 0 1)))))

;;; smoke-durable-trigger.el ends here
