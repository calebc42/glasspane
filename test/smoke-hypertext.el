;;; smoke-hypertext.el --- JC-3b device gate -*- lexical-binding: t; -*-

;; Drives the hypertext skin against a live Companion with REAL shr:
;;
;;   real HTML -> libxml -> shr renders into an eww-mode buffer ->
;;   jetpacs-render-buffer dispatches to the JC-3b skin -> the document
;;   pushes with a nav toolbar, native table rows (the DOM pass), an
;;   https image the DEVICE fetches, and a data: image inlined by the
;;   resolver -> tapping Reload exercises hypertext.nav end to end.
;;
;; This is the half the ERT structurally cannot see: whether live shr
;; still writes the props the firewall section reads, and whether the
;; Companion's advertised features/limits accept what the resolver
;; emits.  Run with the app open and `adb forward tcp:8765 tcp:8765'.

(require 'ebp)
(require 'eww)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-hypertext)

(defvar smoke-ht--fails 0)
(defun smoke-ht--check (label ok &optional detail)
  (princ (format "%-46s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-ht--fails (1+ smoke-ht--fails))))

;; An 8x8 red/blue checker PNG, real and decodable — the data-path
;; image.  (An earlier hand-written literal here had a corrupt IDAT;
;; the resolver rightly inlined it — magic and IHDR were valid — and
;; the Companion rightly showed the 17.2 neutral placeholder.  Keep
;; this one generated, never hand-typed.)
(defconst smoke-ht--png
  (base64-decode-string
   (concat "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAGklEQVR4nGM4"
           "YGAAR0jMAwxUlEDmICuiogQAImxIAbGdpa0AAAAASUVORK5CYII=")))

(defconst smoke-ht--html
  (concat
   "<html><head><title>JC-3b live smoke</title></head><body>"
   "<h1>Document substrate</h1>"
   "<p>A paragraph with <a href='https://www.gnu.org/software/emacs/'>"
   "a real link</a> that should reflow across lines on a narrow render "
   "width, proving the block scan joins them.</p>"
   "<pre>code block: (jetpacs-hypertext--emit model)</pre>"
   "<blockquote>A quoted line on a tinted surface.</blockquote>"
   "<table><tr><th>Rung</th><th>State</th></tr>"
   "<tr><td>JC-3a</td><td>landed</td></tr>"
   "<tr><td>JC-3b</td><td>this push</td></tr></table>"
   "<p><img src='https://www.gnu.org/software/emacs/images/emacs.png'"
   " alt='Emacs logo (device-fetched)'></p>"
   "<p><img src='data:image/png;base64,"
   (base64-encode-string smoke-ht--png t)
   "' alt='Inline 2x2 (data path)'></p>"
   "</body></html>"))

(defvar smoke-ht--doc
  (with-current-buffer (get-buffer-create "*smoke-eww*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (let ((dom (with-temp-buffer
                   (insert smoke-ht--html)
                   (libxml-parse-html-region (point-min) (point-max))))
            (shr-width 48))
        (shr-insert-document dom)))
    (eww-mode)
    (setq-local eww-data (list :title "JC-3b live smoke"
                               :source smoke-ht--html
                               :url "https://example.org/smoke"))
    (setq-local eww-history (list (list :url "https://example.org/prev"))
                eww-history-position 0)
    (current-buffer)))

(defvar smoke-ht--ready nil)
(defvar smoke-ht--navs 0)

(let ((client
       (jetpacs-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "smoke-ht-receipts")
        :ready-function (lambda (_c) (setq smoke-ht--ready t)))))

  (smoke-ht--check "the JC-3b skin claims eww-mode"
                   (eq (with-current-buffer smoke-ht--doc
                         (seq-some (lambda (c)
                                     (and (derived-mode-p (car c)) (cdr c)))
                                   jetpacs-render-buffer-functions))
                       #'jetpacs-hypertext-render))

  ;; The scanner against LIVE shr output (the ERT used a hand fixture).
  (let* ((model (jetpacs-hypertext--scan-shr smoke-ht--doc))
         (kinds (mapcar (lambda (s) (plist-get s :kind)) model)))
    (smoke-ht--check "live shr scan recovers a heading"
                     (memq 'heading kinds))
    (smoke-ht--check "live shr scan recovers the table region"
                     (memq 'table kinds))
    (smoke-ht--check "live shr scan recovers both images"
                     (= (cl-count 'image kinds) 2)
                     (format "kinds %S" kinds))
    (let ((resolved (jetpacs-hypertext--eww-resolve-tables
                     model smoke-ht--doc)))
      (smoke-ht--check "the DOM pass upgraded the table to native rows"
                       (cl-some (lambda (s) (plist-get s :rows)) resolved))))

  ;; Count nav arrivals without disturbing the registered handler.
  (let ((real (gethash "hypertext.nav" jetpacs-action-handlers)))
    (puthash "hypertext.nav"
             (lambda (args params)
               (cl-incf smoke-ht--navs)
               (funcall real args params))
             jetpacs-action-handlers))

  (with-jetpacs-owner "hypertext"
    (jetpacs-shell-define-root
     "hypertext"
     ;; The renderer seam returns a LIST of nodes; the caller wraps.
     (lambda () (apply #'jetpacs-column
                       (jetpacs-render-buffer smoke-ht--doc)))))

  (let ((deadline (+ (float-time) 20)))
    (while (and (not smoke-ht--ready) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (smoke-ht--check "session reaches READY" smoke-ht--ready)

  (when smoke-ht--ready
    ;; What did the device actually advertise?
    (let* ((profile (plist-get (ebp-client-profiles client) :app))
           (features (append (plist-get profile :features) nil)))
      (smoke-ht--check "Companion advertises both image URI forms"
                       (and (member "image.https" features)
                            (member "image.data" features))
                       (format "%S" features)))
    (with-jetpacs-owner "hypertext"
      (smoke-ht--check "document pushed through every gate"
                       (integerp (jetpacs-shell-push))))
    (smoke-ht--check "whole-buffer record authorizes hypertext.nav"
                     (jetpacs-buffer-exposed-buffer-p
                      (buffer-name smoke-ht--doc) "hypertext.nav"))

    (princ "\n  -- 45s: check the render, then tap the Reload nav icon --\n")
    (let ((deadline (+ (float-time) 45)))
      (while (< (float-time) deadline)
        (accept-process-output nil 0.2)))

    (smoke-ht--check "a hypertext.nav event arrived from the device"
                     (> smoke-ht--navs 0)
                     (format "%d nav(s)" smoke-ht--navs)))

  (ebp-client-close client 'smoke-done))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-ht--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-ht--fails))
(kill-emacs (if (zerop smoke-ht--fails) 0 1))
