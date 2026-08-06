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
                         (memq (car form) '(defun defvar))
                         (symbolp (cadr form))
                         (string-prefix-p "jetpacs-hub--"
                                          (symbol-name (cadr form))))
                (eval form t))))
        (end-of-file nil)))
    (setq jetpacs-home-test--loaded t)))

(ert-deftest jetpacs-home-screen-builds-in-every-state ()
  "The home builder never signals: empty history, results, errors."
  (jetpacs-home-test--load-hub-defuns)
  (let ((jetpacs-hub--eval-history nil))
    (should (jetpacs-hub--screen nil)))
  (let ((jetpacs-hub--eval-history
         (list (list "(+ 1 2)" "3" nil)
               (list "(broken" "End of file during parsing" t)
               (list (make-string 300 ?x) (make-string 3000 ?y) nil))))
    (should (jetpacs-hub--screen nil))))

(ert-deftest jetpacs-home-drawer-builds ()
  "The drawer composition never signals."
  (jetpacs-home-test--load-hub-defuns)
  (should (jetpacs-hub--drawer))
  (should (jetpacs-hub--tools-entry)))

(provide 'jetpacs-home-test)
;;; jetpacs-home-test.el ends here