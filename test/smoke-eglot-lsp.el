;;; smoke-eglot-lsp.el --- R0-R2+R5 desktop gate: a REAL language server -*- lexical-binding: t; -*-

;; MANUAL-CLASS but fully autonomous: no device, no fingers — it needs a
;; real `typescript-language-server' on `exec-path' (nodejs), which the
;; hermetic runner must never depend on, so it is NOT in run-tests.sh.
;;
;; What only a real server can prove (the fixture suites stay green
;; without any of it):
;;   R0  the live attached buffer's harvest reaches an eglot capf and the
;;       reply's candidates are the SERVER's, not the word fallback's;
;;   R1  `ebp-sync--ensure-eglot' actually spawns and connects a server
;;       at attach in a HEADLESS Emacs (the post-command deferral trap),
;;       and the diagnostics rider ships the server's squiggles as
;;       `diagnostics.show';
;;   R2  the live offer arms with the eglot capf's :exit-function;
;;   R3  candidates carry vocabulary `kind's from :company-kind;
;;   R5  `edit.candidate.doc' serves the server's JSDoc through the
;;       provider — inside a REAL jsonrpc dispatch (the with-temp-buffer
;;       context of the review's P1), against the RETAINED reply.
;;
;; Run: emacs -Q --batch -L emacs -L test -l test/smoke-eglot-lsp.el

(require 'ebp)
(require 'ebp-sync)
(require 'ebp-complete)
(load (expand-file-name "ebp-wire-test.el"
                        (file-name-directory (or load-file-name
                                                 buffer-file-name)))
      nil t)

(defvar smoke-lsp--fails 0)
(defun smoke-lsp--check (label ok &optional detail)
  (princ (format "%-56s %s%s\n" label (if ok "PASS" "FAIL")
                 (if detail (format "  (%s)" detail) "")))
  (unless ok (setq smoke-lsp--fails (1+ smoke-lsp--fails))))

(unless (executable-find "typescript-language-server")
  (princ "SKIP: typescript-language-server not on exec-path\n")
  (kill-emacs 2))

;; The fixture project: one JS file whose JSDoc is the doc needle.
(defvar smoke-lsp--dir (file-name-as-directory
                        (make-temp-file "smoke-eglot" t)))
(defvar smoke-lsp--file (concat smoke-lsp--dir "live.js"))
(defconst smoke-lsp--seed
  "const answer = {\n  /** The alpha needle documentation. */\n  alpha: 1,\n  beta: 2,\n};\nanswer.")
(write-region "{}" nil (concat smoke-lsp--dir "jsconfig.json") nil 'silent)
(write-region smoke-lsp--seed nil smoke-lsp--file nil 'silent)

;; js-mode is deliberately outside the default gate (the default list is
;; the Termux-practical set); the option exists for exactly this.
(setopt ebp-sync-eglot-modes (cons 'js-mode ebp-sync-eglot-modes))
(setopt ebp-complete-live-timeout 10.0)
(setopt ebp-complete-doc-timeout 10.0)
(ebp-complete-set-editor-kinds "doc:eglot.js" "body" t)

(defvar smoke-lsp--session (make-string 32 ?e))
(defvar smoke-lsp--replies nil "Wire replies by id, newest first.")
(defvar smoke-lsp--diags nil "The first diagnostics.show params seen.")

(let* ((send-fn nil)
       (server
        (ebp-test--start-companion
         (ebp-test--kat-script
          :welcome-fn
          (lambda (w)
            ;; The senders (diagnostics rider above all) refuse without
            ;; the grant; the KAT default grants only theme.
            (plist-put (copy-sequence w) :granted ["editor.sync" "theme"]))
          :after-ready
          (lambda (send)
            (setq send-fn send)
            (funcall send
                     `(:jsonrpc "2.0" :method "edit.open"
                       :params (:document "doc:eglot.js" :editor_id "body"
                                :session ,smoke-lsp--session :seq 0
                                :text ,smoke-lsp--seed
                                :cursor ,(length smoke-lsp--seed))))))))
       (client (ebp-test--connect
                (plist-get server :port)
                :wants '("editor.sync")
                ;; Raw ebp-connect wires NO completion source (that is
                ;; jetpacs-connect's default); the harvester is the
                ;; subject under test here.
                :edit-complete-function #'ebp-complete-edit-complete)))
  (ignore client)
  (smoke-lsp--check "session reaches READY"
                    (ebp-test--wait (lambda ()
                                      (eq (ebp-client-state client) 'ready))))
  (smoke-lsp--check "edit.open seeded the mirror"
                    (ebp-test--wait
                     (lambda ()
                       (equal (ebp-client-editor-text client "doc:eglot.js"
                                                      "body")
                              smoke-lsp--seed))))

  ;; The LIVE arm: a real buffer visiting the file, attached.
  (let ((buf (find-file-noselect smoke-lsp--file)))
    (with-current-buffer buf
      (smoke-lsp--check "the buffer is js-mode" (derived-mode-p 'js-mode)
                        (format "%s" major-mode))
      (ebp-sync-attach client "doc:eglot.js" "body" buf))

    ;; R1: ensure-eglot's direct async connect, headless.
    (smoke-lsp--check
     "R1 eglot connected a REAL server at attach"
     (ebp-test--wait (lambda ()
                       (with-current-buffer buf
                         (and (fboundp 'eglot-current-server)
                              (eglot-current-server))))
                     30)
     (with-current-buffer buf
       (and (eglot-current-server)
            (process-name
             (jsonrpc--process (eglot-current-server))))))

    ;; Server warm-up: the first completion can be slow; ask until the
    ;; reply carries the server's members.
    (defun smoke-lsp--reply (id)
      (cl-find-if (lambda (m) (equal (alist-get 'id m) id))
                  (funcall (plist-get server :received))))
    (let ((attempt 0) reply)
      (while (and (< attempt 5) (not reply))
        (cl-incf attempt)
        (let ((id (format "cpk%d" attempt)))
          (funcall send-fn
                   `(:jsonrpc "2.0" :id ,id :method "edit.complete"
                     :params (:document "doc:eglot.js" :editor_id "body"
                              :session ,smoke-lsp--session :seq 0
                              :cursor ,(length smoke-lsp--seed))))
          (ebp-test--wait (lambda () (smoke-lsp--reply id)) 15)
          (let* ((r (smoke-lsp--reply id))
                 (cands (alist-get 'candidates (alist-get 'result r))))
            (when (and cands (> (length cands) 0)
                       (cl-find-if (lambda (c)
                                     (equal (alist-get 'label c) "alpha"))
                                   (append cands nil)))
              (setq reply r)))))
      (let* ((result (alist-get 'result reply))
             (cands (append (alist-get 'candidates result) nil))
             (alpha-ix (cl-position "alpha" cands
                                    :key (lambda (c) (alist-get 'label c))
                                    :test #'equal))
             (alpha (and alpha-ix (nth alpha-ix cands))))
        (smoke-lsp--check "R0 the server's members answered the harvest"
                          (and alpha
                               (cl-find-if (lambda (c)
                                             (equal (alist-get 'label c)
                                                    "beta"))
                                           cands))
                          (format "%d candidate(s)" (length cands)))
        (smoke-lsp--check "R3 candidates carry a vocabulary kind"
                          (and alpha
                               (member (alist-get 'kind alpha)
                                       ebp-complete-kind-vocabulary))
                          (alist-get 'kind alpha))
        (smoke-lsp--check "R2 the live offer armed with an exit function"
                          (and ebp-complete-live-offer
                               (plist-get ebp-complete-live-offer :exit-fn)
                               t))

        ;; R5: the retained-reply doc fetch, through the REAL dispatch.
        (when alpha-ix
          (funcall send-fn
                   `(:jsonrpc "2.0" :id "cd1" :method "edit.candidate.doc"
                     :params (:document "doc:eglot.js" :editor_id "body"
                              :session ,smoke-lsp--session :seq 0
                              :index ,alpha-ix)))
          (ebp-test--wait (lambda () (smoke-lsp--reply "cd1")) 20)
          (let ((doc (alist-get 'doc (alist-get 'result
                                                (smoke-lsp--reply "cd1")))))
            (smoke-lsp--check
             "R5 the server's JSDoc rode edit.candidate.doc"
             (and (stringp doc)
                  (string-search "alpha needle" doc))
             (format "%S" (and (stringp doc)
                               (substring doc 0 (min 60 (length doc))))))))))

    ;; R1's other half: the diagnostics rider over a server squiggle.
    ;; A device-shaped delta appends garbage; tsserver objects; the
    ;; rider ships diagnostics.show.
    (funcall send-fn
             `(:jsonrpc "2.0" :method "edit.delta"
               :params (:document "doc:eglot.js" :editor_id "body"
                        :session ,smoke-lsp--session :seq 1
                        :start ,(length smoke-lsp--seed) :del 0
                        :text ";;;const" :len ,(+ (length smoke-lsp--seed) 8))))
    (smoke-lsp--check
     "R1 the diagnostics rider shipped the server's squiggles"
     (ebp-test--wait
      (lambda ()
        (cl-find-if (lambda (m)
                      (and (equal (alist-get 'method m) "diagnostics.show")
                           (> (length (alist-get 'diagnostics
                                                 (alist-get 'params m)))
                              0)))
                    (funcall (plist-get server :received))))
      25))

    (with-current-buffer buf (ignore-errors (ebp-sync-detach)))
    (when (fboundp 'eglot-shutdown-all) (ignore-errors (eglot-shutdown-all)))
    (kill-buffer buf))

  (ebp-client-close client 'smoke-done)
  (funcall (plist-get server :stop)))

(princ (format "\n%s (%d failure(s))\n"
               (if (zerop smoke-lsp--fails) "SMOKE PASS" "SMOKE FAIL")
               smoke-lsp--fails))
(kill-emacs (if (zerop smoke-lsp--fails) 0 1))
;;; smoke-eglot-lsp.el ends here
