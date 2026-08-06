;;; smoke-complete.el --- JC-5 device gate: the buffer harvester -*- lexical-binding: t; -*-

;; The JC-5 exit smoke.  A REAL app-surface synchronized editor (not the
;; dialog picker) whose `edit.complete' requests are answered by the
;; ported harvester through the `:edit-complete-function' seam that
;; `jetpacs-connect' wired BY DEFAULT — no dialog module loaded, so the
;; harvester is the only possible answer source.
;;
;; What only hardware can show: that a seeded app editor opens a SPEC 19
;; session, that a device keystroke's delta re-arms the completion
;; request with the LIVE caret (a fresh session's cursor is 0, so the
;; render-time request harvests nothing — the keystroke is what makes
;; the dropdown appear), that the elisp capf's candidate renders as a
;; tappable row, and that tapping it lands a local edit whose delta
;; reaches the mirror: the final text can only come from §19.
;;
;; Drive (runner does the adb half):
;;   1. wait for PUSHED, screenshot, tap the editor field's right end
;;   2. `adb shell input text e` -> settle -> dump -> tap the candidate
;;      row "smoke-complete-harvest-needle"
;;   3. the mirror adopts the completed text and the smoke concludes
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'ebp-complete)

(defvar smoke-jc5--fails 0)
(defun smoke-jc5--check (label ok &optional detail)
  (princ (format "%-52s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-jc5--fails (1+ smoke-jc5--fails))))

(defvar smoke-complete-harvest-needle 42
  "The completion target: interned HERE, found via the elisp capf in the
shadow buffer for `smoke-note.el'.  Never in the editor's text, so the
word fallback cannot produce it — only the capf path can.")

(defconst smoke-jc5--seed "(setq smoke-complete-harvest-n"
  "Editor seed: variable position, one keystroke short of unambiguous.")

(defconst smoke-jc5--want "(setq smoke-complete-harvest-needle"
  "The mirror after the tapped candidate replaced the typed prefix.")

(defvar smoke-jc5--ready nil)
(defvar smoke-jc5--mirror :unset)
(defvar smoke-jc5--harvests 0)
(defvar smoke-jc5--offered 0
  "Harvest answers that actually carried candidates.")

(defun smoke-jc5--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))

(defun smoke-jc5--builder ()
  (jetpacs-column
   (jetpacs-text "JC-5 completion — the harvester" :style "headline")
   (jetpacs-editor "body" :document "smoke-note.el"
                   :value smoke-jc5--seed :complete t)))

(with-jetpacs-owner "jc5"
  (jetpacs-shell-define-root "jc5" #'smoke-jc5--builder))

;; Count harvester answers, so the smoke proves WHICH source answered
;; (the JC-4b vacuous-pass lesson: assert the path, not just the outcome).
(advice-add 'ebp-complete-edit-complete :around
            (lambda (orig &rest args)
              (cl-incf smoke-jc5--harvests)
              (let ((r (apply orig args)))
                (when (cdr r) (cl-incf smoke-jc5--offered))
                (message "HARVEST prefix=%S n=%d" (car r) (length (cdr r)))
                r)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("editor.sync")
        :receipt-file (make-temp-file "smoke-jc5-receipts")
        :edit-change-function
        (lambda (_c doc eid text)
          ;; edit.close fires this hook with text nil (SPEC 18.1/19.3
          ;; path in ebp) — strings only, the JC-4b device lesson.
          (when (and (equal doc "smoke-note.el") (equal eid "body")
                     (stringp text))
            (setq smoke-jc5--mirror text)
            (message "MIRROR %s/%s = %S" doc eid text)))
        :ready-function (lambda (_c) (setq smoke-jc5--ready t)))))

  (smoke-jc5--drain 20 (lambda () smoke-jc5--ready))
  (smoke-jc5--check "session reaches READY" smoke-jc5--ready)
  (smoke-jc5--check "editor.sync granted"
                    (and (member "editor.sync"
                                 (append (ebp-client-granted client) nil))
                         t))
  (smoke-jc5--check "`editor' advertised for app surfaces"
                    (jetpacs-node-advertised-p "editor" :app))
  (smoke-jc5--check "jetpacs-connect wired the harvester by default"
                    (eq (plist-get (ebp-client-config client)
                                   :edit-complete-function)
                        #'ebp-complete-edit-complete))

  (when smoke-jc5--ready
    (with-jetpacs-owner "jc5" (jetpacs-shell-push "jc5"))
    (smoke-jc5--drain 3)
    (princ "PUSHED\n")
    (message "PUSHED")
    ;; The runner taps the field end, types `e', and taps the candidate.
    (smoke-jc5--drain 90 (lambda () (equal smoke-jc5--mirror smoke-jc5--want)))

    (smoke-jc5--check "the keystroke's delta reached the mirror"
                      (and (stringp smoke-jc5--mirror)
                           (not (equal smoke-jc5--mirror smoke-jc5--seed)))
                      (format "mirror %S" smoke-jc5--mirror))
    (smoke-jc5--check "the harvester answered edit.complete"
                      (> smoke-jc5--harvests 0)
                      (format "%d request(s)" smoke-jc5--harvests))
    (smoke-jc5--check "at least one answer carried candidates"
                      (> smoke-jc5--offered 0)
                      (format "%d offer(s)" smoke-jc5--offered))
    (smoke-jc5--check "the tapped candidate landed through the mirror"
                      (equal smoke-jc5--mirror smoke-jc5--want)
                      (format "%S (wanted %S)" smoke-jc5--mirror
                              smoke-jc5--want)))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-jc5--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-jc5--fails))
(kill-emacs (if (zerop smoke-jc5--fails) 0 1))

;;; smoke-complete.el ends here
