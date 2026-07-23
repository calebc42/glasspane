;;; smoke-parity.el --- W9-m parity gate over widgets.golden -*- lexical-binding: t; -*-
;; Drive every per-widget vector in ebp/goldens/widgets.golden through a LIVE
;; session as an app:main surface root, asserting each is accepted ("applied").
;; A rejection or a stale would mean the renderer advertises a type or member
;; it cannot validate+render — the whole point of the §10.2/§16.2 gate. This is
;; the W9 exit criterion: the corpus that covers all 39 node types renders
;; through the real engine end to end.
(require 'ebp)
(require 'json)

(defvar ebp-parity--applied 0)
(defvar ebp-parity--total 0)
(defvar ebp-parity--stale nil)

(defun ebp-parity--vectors ()
  "The NODE vectors in widgets.golden (the `NN ' prefix stripped).
The corpus also carries ActionDescriptor/builtin shapes with no `t`; those
are not surface roots, so only vectors with a `t` are driven here."
  (with-temp-buffer
    (insert-file-contents "ebp/goldens/widgets.golden")
    (let (out)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (when (string-match "\\`[0-9]+ \\(.*\\)\\'" line)
            (let ((spec (json-parse-string (match-string 1 line)
                                           :object-type 'plist
                                           :array-type 'array
                                           :false-object :json-false
                                           :null-object nil)))
              (when (plist-get spec :t) (push spec out)))))
        (forward-line 1))
      (nreverse out))))

(let* ((vectors (ebp-parity--vectors))
       (client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-parity-receipts")
         :ready-function
         (lambda (c)
           (setq ebp-parity--total (length vectors))
           ;; The client owns the revisions; each push auto-increments.
           (dolist (spec vectors)
             (ebp-client-surface-update
              c "app:main" spec
              :callback
              (lambda (status _error)
                (cond ((equal status "applied")
                       (setq ebp-parity--applied (1+ ebp-parity--applied)))
                      (t (push status ebp-parity--stale))))))))))
  (cl-loop repeat 400
           until (and (> ebp-parity--total 0)
                      (>= (+ ebp-parity--applied (length ebp-parity--stale))
                          ebp-parity--total))
           do (accept-process-output nil 0.1))
  (message "parity: applied=%d/%d stale=%S"
           ebp-parity--applied ebp-parity--total (nreverse ebp-parity--stale))
  (kill-emacs (if (and (> ebp-parity--total 0)
                       (= ebp-parity--applied ebp-parity--total))
                  0 1)))
;;; smoke-parity.el ends here
