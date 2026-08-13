;;; smoke-r5-docs.el --- R3/R4/R5 device gate: kinds, docs, settings -*- lexical-binding: t; -*-

;; MANUAL. NOT run by test/run-tests.sh: it dials a real Companion on
;; 127.0.0.1:8765 and needs the runner's adb fingers and eyes.
;;
;; The completion-ladder device batch in one session:
;;   R3  the candidate `kind' icons actually DRAW in the dropdown
;;       (CompletionKindIconTest proves the map; only a screen proves
;;       the pixels).
;;   R5  long-press on a row fetches documentation lazily
;;       (edit.candidate.doc) and the panel renders it under the rows;
;;       a candidate whose doc is EMPTY shows NO panel (the universal
;;       degradation arm must be visibly distinct from a crash — the
;;       review's decision point 6); the tap-accept still lands and its
;;       delta carries `accept: true' (#170, asserted at the splice
;;       hook).
;;   R4  the Companion settings dialog (companion.settings.open) carries
;;       the completion-narrowing row; switching to Contains persists
;;       (reopen shows it; prefs file carries it) and is switched BACK
;;       to Strict — the reference default — before the smoke ends.
;;
;; Drive (runner does the adb half; each *-DO-n* prints when it's time):
;;   1. wait for PUSHED; screenshot; tap the editor field's right end
;;   2. `adb shell input text -' -> settle ~2s -> screenshot: THREE rows
;;      with DISTINCT leading icons (alpha=function, beta=variable,
;;      gamma=class)
;;   3. long-press the gamma row (~700ms same-point swipe) -> settle ->
;;      screenshot + uiautomator dump: the gamma doc text under the rows
;;   4. long-press the beta row -> settle -> screenshot: NO panel
;;   5. tap the alpha row -> the mirror adopts the completion
;;   6. tap the Settings button -> dialog -> tap Contains -> Done ->
;;      reopen -> confirm Contains held -> tap Strict -> Done
;;
;; Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'ebp-complete)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)

(defvar smoke-r5--fails 0)
(defun smoke-r5--check (label ok &optional detail)
  (princ (format "%-56s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-r5--fails (1+ smoke-r5--fails))))
(defun smoke-r5--drain (secs &optional stop-fn)
  (let ((deadline (+ (float-time) secs)))
    (while (and (< (float-time) deadline)
                (not (and stop-fn (funcall stop-fn))))
      (accept-process-output nil 0.1))))
(defun smoke-r5--mark (m) (princ (concat m "\n")) (message "%s" m))

(defconst smoke-r5--doc-gamma
  "smoke-r5-gamma: the documented needle.\nSecond line, verbatim per SPEC 16.4 — *markdown stays punctuation*."
  "Gamma's documentation — the panel must show THIS text.")

(defconst smoke-r5--seed "(smoke-r5")
(defconst smoke-r5--want "(smoke-r5-alpha")

;; The completion source: a capf in the SHADOW buffer for smoke-r5.el,
;; carrying :company-kind (R3) and :company-doc-buffer (R5).  Kinds are
;; author-registered for the editor (the #169 sender-omit rule).
(ebp-complete-set-editor-kinds "smoke-r5.el" "body" t)
(add-hook 'ebp-complete-shadow-setup-hook
          (lambda ()
            (setq-local
             completion-at-point-functions
             (list (lambda ()
                     (let ((end (point))
                           (beg (save-excursion
                                  (skip-syntax-backward "w_") (point))))
                       (list beg end
                             '("smoke-r5-alpha" "smoke-r5-beta"
                               "smoke-r5-gamma")
                             :company-kind
                             (lambda (c)
                               (pcase (substring-no-properties c)
                                 ("smoke-r5-alpha" 'function)
                                 ("smoke-r5-beta" 'variable)
                                 ("smoke-r5-gamma" 'class)))
                             :company-doc-buffer
                             (lambda (c)
                               (with-current-buffer
                                   (get-buffer-create " *r5 smoke doc*")
                                 (erase-buffer)
                                 (insert
                                  (pcase (substring-no-properties c)
                                    ("smoke-r5-gamma" smoke-r5--doc-gamma)
                                    ("smoke-r5-alpha" "alpha doc")
                                    (_ "")))   ; beta: the empty arm
                                 (current-buffer))))))))))

(defun smoke-r5--builder ()
  (jetpacs-column
   (jetpacs-text "R3/R4/R5 — kinds, lazy docs, settings" :style "headline")
   (jetpacs-editor "body" :document "smoke-r5.el"
                   :value smoke-r5--seed :complete t)
   (jetpacs-button "Settings"
                   (jetpacs-make-node nil :builtin
                                      "companion.settings.open"))))

(with-jetpacs-owner "r5"
  (jetpacs-shell-define-root "r5" #'smoke-r5--builder))

(defvar smoke-r5--ready nil)
(defvar smoke-r5--mirror :unset)
(defvar smoke-r5--doc-calls nil
  "Each entry: (INDEX . DOC-STRING) answered by the real handler.")
(defvar smoke-r5--accept-splices nil
  "Each entry: the ACCEPT flag of an inbound splice (the #170 marker).")

(advice-add 'ebp-client--handle-candidate-doc :around
            (lambda (orig client params)
              (let ((r (funcall orig client params)))
                (push (cons (plist-get params :index) (plist-get r :doc))
                      smoke-r5--doc-calls)
                (message "CANDIDATE-DOC index=%s -> %d chars"
                         (plist-get params :index)
                         (length (plist-get r :doc)))
                r)))

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("editor.sync")
        :receipt-file (make-temp-file "smoke-r5-receipts")
        :edit-splice-function
        (lambda (_c doc eid _start _del _text accept)
          (when (and (equal doc "smoke-r5.el") (equal eid "body"))
            (push accept smoke-r5--accept-splices)))
        :edit-change-function
        (lambda (_c doc eid text)
          (when (and (equal doc "smoke-r5.el") (equal eid "body")
                     (stringp text))
            (setq smoke-r5--mirror text)
            (message "MIRROR = %S" text)))
        :ready-function (lambda (_c) (setq smoke-r5--ready t)))))

  (smoke-r5--drain 20 (lambda () smoke-r5--ready))
  (smoke-r5--check "session reaches READY" smoke-r5--ready)

  (when smoke-r5--ready
    (with-jetpacs-owner "r5" (jetpacs-shell-push "r5"))
    (smoke-r5--drain 3)
    (smoke-r5--mark "PUSHED")
    (smoke-r5--mark "*-DO-1* tap the editor field's right end.")
    (smoke-r5--mark "*-DO-2* type `-'; wait; screenshot the 3 icon rows.")
    (smoke-r5--mark "*-DO-3* long-press the gamma row; screenshot panel.")
    (smoke-r5--mark "*-DO-4* long-press the beta row; screenshot NO panel.")
    (smoke-r5--mark "*-DO-5* tap the alpha row.")
    (smoke-r5--drain 240 (lambda () (equal smoke-r5--mirror smoke-r5--want)))

    (smoke-r5--check "R5 the gamma long-press fetched THE doc"
                     (cl-find-if (lambda (c) (equal (cdr c)
                                                    smoke-r5--doc-gamma))
                                 smoke-r5--doc-calls)
                     (format "%d doc call(s)" (length smoke-r5--doc-calls)))
    (smoke-r5--check "R5 the beta long-press answered the EMPTY arm"
                     (cl-find-if (lambda (c) (equal (cdr c) ""))
                                 smoke-r5--doc-calls))
    (smoke-r5--check "the tapped candidate landed through the mirror"
                     (equal smoke-r5--mirror smoke-r5--want)
                     (format "%S" smoke-r5--mirror))
    (smoke-r5--check "#170 the accept delta carried `accept: true'"
                     (memq t smoke-r5--accept-splices)
                     (format "splice accepts: %S" smoke-r5--accept-splices))

    (smoke-r5--mark "*-DO-6* tap Settings; Contains; Done; reopen to \
confirm it held; then Strict; Done.")
    (smoke-r5--drain 120))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-r5--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-r5--fails))
(kill-emacs (if (zerop smoke-r5--fails) 0 1))
;;; smoke-r5-docs.el ends here
