;;; smoke-a8-dialog-done.el --- A8 device gate: dialog text_input Done key (LD-1) -*- lexical-binding: t; -*-

;; The dialog-`text_input' Done-key smoke the A8 plan deferred to device
;; time.  LD-1 was the dialog hang: a text_input's IME Done action fell
;; into a dispatch hole, so the keyboard's own submit affordance did
;; nothing and the user was stranded.  The T3c `RenderCtx.action'
;; override chain (967ab1e) routes it to the dialog host instead.
;;
;; The field carries `:on_submit (:builtin "dialog.submit" ...)' and
;; `:single_line t' — exactly the shape that makes the renderer set
;; ImeAction.Done (Renderer.kt:395) and submit on it (:398).  The
;; orchestrator types into the field and presses ENTER (KEYCODE 66,
;; which a single-line field maps to the IME action); the dialog MUST
;; conclude `submitted' with the typed text in `fields.name' — no OK
;; button exists in this dialog AT ALL, so only the Done path can
;; conclude it.
;;
;; Markers on stderr: SHOWN once the dialog request is on the wire.
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)

(defvar smoke-a8dd--fails 0)
(defun smoke-a8dd--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-a8dd--fails (1+ smoke-a8dd--fails))))

(defvar smoke-a8dd--ready nil)
(defvar smoke-a8dd--conclusion nil)

(defun smoke-a8dd--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("surfaces.dialog")
        :receipt-file (make-temp-file "smoke-a8dd-receipts")
        :ready-function (lambda (_c) (setq smoke-a8dd--ready t)))))

  (smoke-a8dd--drain 20 (lambda () smoke-a8dd--ready))
  (smoke-a8dd--check "session reaches READY" smoke-a8dd--ready)

  (when smoke-a8dd--ready
    (ebp-client-dialog-show
     client "a8done"
     '(:t "column" :padding 8
       :children [(:t "text" :style "headline" :text "Done-key gate")
                  (:t "spacer" :height 8)
                  (:t "text_input" :id "name" :label "Type then press Done"
                   :single_line t
                   :on_submit (:builtin "dialog.submit"
                               :capture_fields ["name"]))
                  (:t "spacer" :height 8)
                  (:t "button" :label "Cancel"
                   :on_tap (:builtin "dialog.dismiss"))])
     :callback
     (lambda (status result error)
       (setq smoke-a8dd--conclusion (list status result error))))
    (smoke-a8dd--drain 2)
    (princ "SHOWN\n")
    (message "SHOWN")

    (smoke-a8dd--drain 45 (lambda () smoke-a8dd--conclusion))
    (pcase-let ((`(,status ,result ,error) smoke-a8dd--conclusion))
      (smoke-a8dd--check "the dialog concluded (LD-1: Done must not hang)"
                         smoke-a8dd--conclusion
                         (and status (format "status %S" status)))
      (when smoke-a8dd--conclusion
        (smoke-a8dd--check "IME Done submitted (not dismissed, no error)"
                           (and (equal status "submitted") (null error))
                           (format "status %S error %S" status error))
        (smoke-a8dd--check "capture carried the typed field"
                           (equal (plist-get (plist-get result :fields) :name)
                                  "hi")
                           (format "fields %S" (plist-get result :fields))))))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-a8dd--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-a8dd--fails))
(kill-emacs (if (zerop smoke-a8dd--fails) 0 1))

;;; smoke-a8-dialog-done.el ends here
