;;; jetpacs-home-test.el --- The device init's home screen builds -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; device/init.el is host config, not a module — but its screen
;; builders are code, and a builder that signals renders the chrome
;; error screen on the tablet ("Screen home failed to build").  This
;; suite extracts the hub defuns from the init WITHOUT loading it (the
;; init sets a device load-path and dials the Companion) and builds the
;; home screen in every state.  Both bugs this harness caught on day
;; one (:pad vs :padding; :key passed as a card member) would have
;; shipped silently under the module-only suites.

(require 'ert)
(require 'jetpacs-chrome)
(require 'jetpacs-repl)
(require 'jetpacs-emacs-ui)
(require 'jetpacs-apps)
(require 'jetpacs-settings)
(require 'jetpacs-app-store)

(defconst jetpacs-home-test--root
  (expand-file-name ".." (file-name-directory
                          (or load-file-name buffer-file-name)))
  "Repo root, captured at LOAD time — nil inside a test body.")

(defvar jetpacs-home-test--loaded nil)

(defun jetpacs-home-test--load-hub-defuns ()
  "Eval every jetpacs-hub-- defun/defvar from device/init.el, once."
  (unless jetpacs-home-test--loaded
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name "device/init.el" jetpacs-home-test--root))
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (and (consp form)
                         ;; `defconst' too: the hub's REPL session id is
                         ;; one, and the screen builder is void without it.
                         (memq (car form) '(defun defvar defconst))
                         (symbolp (cadr form))
                         (string-prefix-p "jetpacs-hub--"
                                          (symbol-name (cadr form))))
                (eval form t))))
        (end-of-file nil)))
    (setq jetpacs-home-test--loaded t)))

(ert-deftest jetpacs-home-screen-builds-in-every-state ()
  "The home builder never signals: empty history, results, errors.
The history lives in `jetpacs-repl' now, keyed by session, so the
fixture is recorded rather than let-bound — and cleared first, because a
session outlives one test."
  (jetpacs-home-test--load-hub-defuns)
  (jetpacs-repl-clear jetpacs-hub--repl)
  (should (jetpacs-hub--screen nil))
  (dolist (entry '(("(+ 1 2)" "3" nil)
                   ("(broken" "End of file during parsing" t)))
    (apply #'jetpacs-repl-record jetpacs-hub--repl entry))
  ;; The elision case: an input and an output past every display bound.
  (jetpacs-repl-record jetpacs-hub--repl
                       (make-string 300 ?x) (make-string 3000 ?y) nil)
  (should (jetpacs-hub--screen nil))
  (jetpacs-repl-clear jetpacs-hub--repl))

(ert-deftest jetpacs-home-drawer-builds ()
  "The drawer composition never signals."
  (jetpacs-home-test--load-hub-defuns)
  (should (jetpacs-hub--drawer))
  (should (jetpacs-hub--tools-entry)))

(provide 'jetpacs-home-test)
;;; jetpacs-home-test.el ends here