;;; glasspane-packages-test.el --- Tests for glasspane-packages
;;; Code:

(require 'glasspane-test-helpers)
(require 'glasspane-packages)

;; Load package.el up front: `glasspane-packages-ensure' requires it
;; lazily, and a mid-test load would redefine the very functions the
;; mocks below replace — clobbering them and reaching for the network.
(require 'package)

;; ─── Engine self-provisioning (installs fully mocked — batch stays offline) ──

(ert-deftest glasspane-packages-auto-install-gates ()
  "The automatic attempt: interactive sessions only, device installs
only, at most once a session."
  (let ((timers nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (&rest args) (push args timers)))
              ((symbol-function 'glasspane-packages--missing)
               (lambda () '(vulpea))))
      ;; Batch (`noninteractive' is t under the suite): never schedules —
      ;; and never even probes for MELPA.
      (let ((glasspane-packages--attempted nil)
            (jetpacs-installed-bundles '("glasspane.el")))
        (glasspane-packages-maybe-auto-install)
        (should-not timers))
      ;; Interactive + installed as a device app: exactly one attempt.
      (let ((noninteractive nil)
            (glasspane-packages--attempted nil)
            (jetpacs-installed-bundles '("glasspane.el")))
        (glasspane-packages-maybe-auto-install)
        (glasspane-packages-maybe-auto-install)
        (should (= 1 (length timers))))
      ;; Interactive but not a device install (desktop require): never.
      (setq timers nil)
      (let ((noninteractive nil)
            (glasspane-packages--attempted nil)
            (jetpacs-installed-bundles nil))
        (glasspane-packages-maybe-auto-install)
        (should-not timers))
      ;; Disabled via the defcustom: never.
      (let ((noninteractive nil)
            (glasspane-packages-auto-install nil)
            (glasspane-packages--attempted nil)
            (jetpacs-installed-bundles '("glasspane.el")))
        (glasspane-packages-maybe-auto-install)
        (should-not timers)))))

(ert-deftest glasspane-packages-ensure-installs-and-lights-up ()
  "Ensure installs exactly the missing set, lights features up on
success, and never signals on failure."
  ;; Success: both missing engines install, then the light-up runs.
  (let ((installed nil) (lit nil) (missing '(vulpea org-srs)))
    (cl-letf (((symbol-function 'glasspane-packages--missing)
               (lambda () missing))
              ((symbol-function 'glasspane-packages--light-up)
               (lambda () (setq lit t)))
              ((symbol-function 'package-refresh-contents) (lambda (&rest _)))
              ((symbol-function 'package-initialize) (lambda (&rest _)))
              ((symbol-function 'package-installed-p) (lambda (_) nil))
              ((symbol-function 'package-install)
               (lambda (pkg)
                 (push pkg installed)
                 (setq missing (remq pkg missing)))))
      (should (glasspane-packages-ensure))
      (should (equal (nreverse installed) '(vulpea org-srs)))
      (should lit)))
  ;; Nothing missing: ensure still lights up (the pull-to-retry path)
  ;; and reports success without touching package.el.
  (let ((lit nil))
    (cl-letf (((symbol-function 'glasspane-packages--missing) (lambda () nil))
              ((symbol-function 'glasspane-packages--light-up)
               (lambda () (setq lit t)))
              ((symbol-function 'package-install)
               (lambda (_) (ert-fail "no install should run"))))
      (should (glasspane-packages-ensure))
      (should lit)))
  ;; A signaling install never escapes; the verdict is nil and the
  ;; re-entrancy guard is released for the next attempt.
  (cl-letf (((symbol-function 'glasspane-packages--missing)
             (lambda () '(vulpea)))
            ((symbol-function 'package-refresh-contents) (lambda (&rest _)))
            ((symbol-function 'package-initialize) (lambda (&rest _)))
            ((symbol-function 'package-installed-p) (lambda (_) nil))
            ((symbol-function 'package-install)
             (lambda (_) (error "network down"))))
    (should-not (glasspane-packages-ensure))
    (should-not glasspane-packages--installing)))

(ert-deftest glasspane-packages-install-action-allowlisted ()
  "The on-demand install rides the allowlisted wire action."
  (should (gethash "packages.install" jetpacs-action-handlers)))

(ert-deftest glasspane-packages-wanted-respects-sqlite ()
  "vulpea is only wanted on an Emacs built with SQLite; the other
engines are wanted regardless."
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () t)))
    (should (memq 'vulpea (glasspane-packages--wanted))))
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () nil)))
    (should-not (memq 'vulpea (glasspane-packages--wanted)))
    (should (memq 'org-ql (glasspane-packages--wanted)))
    (should (memq 'org-srs (glasspane-packages--wanted)))))

(provide 'glasspane-packages-test)
