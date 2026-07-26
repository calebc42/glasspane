;;; smoke-a8-editor.el --- A8 device gate: inbound apply while shown + astral -*- lexical-binding: t; -*-

;; The two editor items deferred to device time by the A8 plan:
;;
;;   1. An inbound `edit.apply' arriving WHILE the editor is on screen
;;      must be adopted by the display (T2/LD-5: editorListener ->
;;      EditorMirror -> RenderEditor adoption).  Before T2, s.shadow
;;      moved and the display did not, and the next device keystroke
;;      diffed against a stale base.
;;   2. LD-4 on hardware: the applied text contains an ASTRAL scalar
;;      (U+1D11E, one scalar, TWO UTF-16 units).  The next device
;;      keystroke makes the Companion diff its shadow and emit an
;;      `edit.delta' in SCALAR positions; if UTF-16 indices leaked, the
;;      splice lands one unit off (or past the end) and the mirror
;;      garbles.  The final mirror text is the proof either way.
;;
;; Orchestration protocol (markers on stderr — unbuffered):
;;   OPENED         the editor session opened, mirror seeded
;;   APPLIED        edit.apply concluded applied; device should now show
;;                  the astral text -> dump, focus the field at its END,
;;                  `adb shell input text x'
;;   then the smoke waits for the delta and judges the mirror.
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)

(defvar smoke-a8ed--fails 0)
(defun smoke-a8ed--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-a8ed--fails (1+ smoke-a8ed--fails))))

(defconst smoke-a8ed--seed "start-")
(defconst smoke-a8ed--insert "a\U0001D11Eb")   ; a 𝄞 b — 3 scalars, 4 UTF-16
(defconst smoke-a8ed--applied-text (concat smoke-a8ed--seed smoke-a8ed--insert))
(defconst smoke-a8ed--final (concat smoke-a8ed--applied-text "x"))

(defvar smoke-a8ed--ready nil)
(defvar smoke-a8ed--opened nil)
(defvar smoke-a8ed--mirror nil)
(defvar smoke-a8ed--apply-result :pending)

(defun smoke-a8ed--drain (secs &optional stop-fn)
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
        :wants '("editor.sync")
        :receipt-file (make-temp-file "smoke-a8ed-receipts")
        :edit-open-function
        (lambda (_c doc eid seed _prior)
          (setq smoke-a8ed--opened (list doc eid seed))
          (message "OPENED"))
        :edit-change-function
        (lambda (_c _doc _eid text)
          (setq smoke-a8ed--mirror text))
        :ready-function (lambda (_c) (setq smoke-a8ed--ready t)))))

  (smoke-a8ed--drain 20 (lambda () smoke-a8ed--ready))
  (smoke-a8ed--check "session reaches READY" smoke-a8ed--ready)

  ;; Present the synchronized editor.
  (ebp-client-surface-update
   client "app:main"
   `(:t "column" :padding 24
     :children [(:t "text" :style "headline" :text "A8 editor smoke")
                (:t "editor" :id "body" :document "doc:a8"
                 :value ,smoke-a8ed--seed)]))
  (smoke-a8ed--drain 15 (lambda () smoke-a8ed--opened))
  (smoke-a8ed--check "edit.open arrived (session opened on present)"
                     (equal smoke-a8ed--opened
                            (list "doc:a8" "body" smoke-a8ed--seed))
                     (format "%S" smoke-a8ed--opened))

  ;; The inbound apply WHILE SHOWN: append the astral run.
  (when smoke-a8ed--opened
    ;; The apply callback receives (STATUS ERROR) with STATUS the STRING
    ;; "applied"/"stale" — the same convention as surface-update's
    ;; callback, and the same trap the W9 smoke notes recorded for it.
    (ebp-client-edit-apply
     client "doc:a8" "body" (length smoke-a8ed--seed) 0 smoke-a8ed--insert
     :callback (lambda (status error)
                 (setq smoke-a8ed--apply-result (or error status))))
    (smoke-a8ed--drain 15 (lambda () (not (eq smoke-a8ed--apply-result
                                              :pending))))
    (smoke-a8ed--check "edit.apply concluded applied"
                       (equal smoke-a8ed--apply-result "applied")
                       (format "%S" smoke-a8ed--apply-result))
    (smoke-a8ed--check "mirror carries the astral text"
                       (equal (ebp-client-editor-text client "doc:a8" "body")
                              smoke-a8ed--applied-text))

    ;; Hand off to the orchestrator: verify the DISPLAY adopted, then
    ;; focus the field's end and type one character.
    (princ "APPLIED\n")
    (message "APPLIED")

    ;; The device keystroke: Companion diffs its shadow, sends a scalar
    ;; edit.delta; the mirror must land exactly on seed+insert+"x".
    (smoke-a8ed--drain 40 (lambda () (equal smoke-a8ed--mirror
                                            smoke-a8ed--final)))
    (smoke-a8ed--check "device keystroke arrived as a scalar-safe delta"
                       (equal smoke-a8ed--mirror smoke-a8ed--final)
                       (format "mirror %S, wanted %S"
                               smoke-a8ed--mirror smoke-a8ed--final))
    (smoke-a8ed--check "editor session survived (no snap-back, no close)"
                       (gethash (cons "doc:a8" "body")
                                (ebp-client-editors client))))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-a8ed--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-a8ed--fails))
(kill-emacs (if (zerop smoke-a8ed--fails) 0 1))

;;; smoke-a8-editor.el ends here
