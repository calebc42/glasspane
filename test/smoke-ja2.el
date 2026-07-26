;;; smoke-ja2.el --- JA-2 device gate, consolidated -*- lexical-binding: t; -*-

;; All six JA-2 hardware claims over ONE connection:
;;   P1 toast: the gated jetpacs-toast reaches the screen (grant live).
;;   P2 stack: row tap -> drill screen via current_view; on-screen
;;      arrow_back -> view.switched truncates the Emacs stack with NO
;;      re-push (companion-local back).
;;   P3 navigate: jetpacs-navigate-buffer drills a real buffer through
;;      the C7 adapter onto the same surface.
;;   P4 flow-begin: a flow ESTABLISHED in Emacs (zero event.action in
;;      the trace) bridges y-or-n-p to a live dialog.
;;   P5 teardown: surface.remove applied for one owner; the survivor
;;      still updatable.
;;   P6 retry-durable: a queue-policy tap answered 1500 twice is
;;      redelivered with the SAME event_id and concludes on accepted.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-dialog)
(require 'jetpacs-navigate)
(require 'jetpacs-chrome)

(defvar smoke-j2--fails 0)
(defun smoke-j2--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-j2--fails (1+ smoke-j2--fails))))
(defun smoke-j2--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))
(defun smoke-j2--mark (m) (princ (concat m "\n")) (message "%s" m))

(defvar smoke-j2--retry-runs 0)
(defvar smoke-j2--retry-ids '())
(defvar smoke-j2--flow-answer :unset)

;; P2/P3 chrome root.
(with-jetpacs-owner "ja2"
  (jetpacs-chrome-define-root
   "ja2" "hub"
   (lambda (_back)
     (jetpacs-chrome-screen
      "JA-2 hub"
      (jetpacs-column
       (jetpacs-chrome-row "Open detail" :icon "folder"
                           :on-tap (jetpacs-action "ja2.open"))))))
  (jetpacs-defaction "ja2.open"
    (lambda (_args params)
      (let ((surface (plist-get params :surface)))
        (jetpacs-flow-continue
         (lambda ()
           (jetpacs-chrome-push-screen
            surface "detail"
            (lambda (back)
              (jetpacs-chrome-screen "Detail" (jetpacs-text "drilled")
                                     :back back)))))
        'accepted))))

;; P5/P6 second owner.
(with-jetpacs-owner "ja2b"
  (jetpacs-shell-define-root
   "ja2b"
   (lambda ()
     (jetpacs-scaffold
      :body (jetpacs-column
             (jetpacs-text "survivor" :style "headline")
             (jetpacs-button "Retry me"
                             (jetpacs-action "ja2b.retry"
                                             :when-offline 'queue
                                             :ttl-s 600))))))
  (jetpacs-defaction "ja2b.retry"
    (lambda (_args params)
      (cl-incf smoke-j2--retry-runs)
      (push (plist-get params :event_id) smoke-j2--retry-ids)
      (if (< smoke-j2--retry-runs 3)
          (jetpacs-retry-later 2)
        'accepted))))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("presentation.toast" "surfaces.dialog")
        :receipt-file (make-temp-file "smoke-j2-receipts"))))

  (smoke-j2--drain 20 (lambda () (jetpacs-connected-p)))
  (smoke-j2--check "session reaches READY" (jetpacs-connected-p))

  (when (jetpacs-connected-p)
    ;; P1 toast.
    (smoke-j2--check "presentation.toast granted"
                     (jetpacs-granted-p "presentation.toast"))
    (smoke-j2--check "jetpacs-toast sent" (jetpacs-toast "JA-2 smoke toast"
                                                         :duration-s 3))
    (smoke-j2--mark "P1-TOAST-SHOT")
    (smoke-j2--drain 4)

    ;; P2 stack: push the hub, runner taps the row then back.
    (with-jetpacs-owner "ja2" (jetpacs-shell-push "ja2"))
    (smoke-j2--drain 2)
    (smoke-j2--mark "P2-TAP-ROW")
    (smoke-j2--drain 150 (lambda () (equal (jetpacs-chrome-stack "ja2")
                                           '("detail" "hub"))))
    (smoke-j2--check "row tap drilled to detail"
                     (equal (jetpacs-chrome-stack "ja2") '("detail" "hub")))
    (let ((rev-before (gethash "app:ja2" jetpacs--applied-revisions)))
      (smoke-j2--mark "P2-TAP-BACK")
      (smoke-j2--drain 150 (lambda () (equal (jetpacs-chrome-stack "ja2")
                                             '("hub"))))
      (smoke-j2--check "arrow_back truncated the stack (view.switched)"
                       (equal (jetpacs-chrome-stack "ja2") '("hub")))
      (smoke-j2--check "back was companion-local (no re-push)"
                       (equal rev-before
                              (gethash "app:ja2" jetpacs--applied-revisions))))

    ;; P3 navigate: drill *scratch* through the C7 adapter.
    (get-buffer-create "*scratch*")
    (smoke-j2--check "navigate-buffer returned the surface"
                     (equal (jetpacs-navigate-buffer "*scratch*" "app:ja2")
                            "app:ja2"))
    (smoke-j2--drain 3)
    (smoke-j2--check "drill screen on the stack"
                     (= (length (jetpacs-chrome-stack "ja2")) 2))
    (jetpacs-chrome-reset-screens "ja2")
    (smoke-j2--drain 2)

    ;; P4 flow-begin bridges a prompt with no dispatch anywhere.
    (jetpacs-flow-begin "ja2"
                        (lambda ()
                          (setq smoke-j2--flow-answer
                                (condition-case nil (y-or-n-p "Bridge? ")
                                  (quit 'quit)))))
    (smoke-j2--mark "P4-TAP-YES")
    (smoke-j2--drain 150 (lambda () (not (eq smoke-j2--flow-answer :unset))))
    (smoke-j2--check "flow-begin bridged y-or-n-p to the device"
                     (eq smoke-j2--flow-answer t)
                     (format "%S" smoke-j2--flow-answer))
    (smoke-j2--check "flow marker not leaked" (not (jetpacs-device-flow-p)))

    ;; P5 teardown ja2; ja2b survives.
    (with-jetpacs-owner "ja2b" (jetpacs-shell-push "ja2b"))
    (smoke-j2--drain 2)
    (jetpacs-teardown-owner "ja2")
    (smoke-j2--drain 3)
    (smoke-j2--check "teardown left no pending removal"
                     (null jetpacs-shell--pending-removals))
    (smoke-j2--check "torn-down push is a no-op"
                     (null (jetpacs-shell-push "ja2")))
    (smoke-j2--check "survivor still updatable"
                     (integerp (with-jetpacs-owner "ja2b"
                                 (jetpacs-shell-push "ja2b"))))
    (smoke-j2--drain 2)

    ;; P6 retry-durable: runner taps Retry me once.
    (smoke-j2--mark "P6-TAP-RETRY")
    (smoke-j2--drain 180 (lambda () (>= smoke-j2--retry-runs 3)))
    (smoke-j2--check "delivered three times (1500 x2 then accepted)"
                     (= smoke-j2--retry-runs 3)
                     (format "%d run(s)" smoke-j2--retry-runs))
    (smoke-j2--check "same event_id across all deliveries"
                     (and (= (length smoke-j2--retry-ids) 3)
                          (= 1 (length (delete-dups
                                        (copy-sequence
                                         smoke-j2--retry-ids))))))
    ;; A settle window: no fourth delivery after accepted.
    (smoke-j2--drain 8)
    (smoke-j2--check "record deleted on accepted (no 4th delivery)"
                     (= smoke-j2--retry-runs 3)))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-j2--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-j2--fails))
(kill-emacs (if (zerop smoke-j2--fails) 0 1))

;;; smoke-ja2.el ends here
