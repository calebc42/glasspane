;;; jetpacs-echo.el --- Mirror echo-area messages to device toasts -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-3d: the `message'→toast bridge, in its own module and OFF BY
;; DEFAULT per the plan.  When a command runs from the device, its
;; feedback goes to the desktop echo area — a monitor that may be in
;; another room.  This module mirrors those messages to a device toast,
;; but ONLY during a device flow (`jetpacs-device-flow-p'): messages
;; produced by ambient desktop work stay on the desktop, so enabling
;; the bridge never turns the tablet into a firehose of compilation
;; noise.
;;
;; Ported from the poc's advice with its throttle (1/s, latest wins)
;; and re-entrancy guard; changed per the plan and the JA-2 floor:
;;   - default OFF (`jetpacs-echo-toast'), and installation is explicit
;;     (`jetpacs-echo-install' / `-uninstall') rather than a load-time
;;     `advice-add' — loading a module must not change `message'.
;;   - gated on the device flow, which the poc had no concept of.
;;   - delivery is `jetpacs-toast' (READY + grant gated, text capped),
;;     never a raw wire send.  A toast is best-effort (SPEC 18.2): a
;;     nil return is fine and never retried.
;;
;; The re-entrancy guard matters doubly here: `jetpacs-toast''s own
;; failure path logs via `message', and one echoed toast about a toast
;; would recurse forever.

;;; Code:

(require 'jetpacs-surfaces)

(defcustom jetpacs-echo-toast nil
  "When non-nil (and installed), device-flow messages mirror as toasts.
Off by default: enable with `setopt' and call `jetpacs-echo-install',
or simply call `jetpacs-echo-install' which enables it."
  :type 'boolean :group 'jetpacs)

(defcustom jetpacs-echo-throttle-seconds 1.0
  "Minimum seconds between mirrored toasts; the LATEST pending wins."
  :type 'number :group 'jetpacs)

(defvar jetpacs-echo--last 0.0)
(defvar jetpacs-echo--pending nil)
(defvar jetpacs-echo--timer nil)
(defvar jetpacs-echo--in-toast nil)

(defun jetpacs-echo--flush ()
  (setq jetpacs-echo--timer nil)
  (when-let* ((text jetpacs-echo--pending))
    (setq jetpacs-echo--pending nil
          jetpacs-echo--last (float-time))
    (let ((jetpacs-echo--in-toast t))
      (ignore-errors (jetpacs-toast text)))))

(defun jetpacs-echo--send (text)
  "Toast TEXT now, or hold it as the latest pending under the throttle."
  (let ((since (- (float-time) jetpacs-echo--last)))
    (if (>= since jetpacs-echo-throttle-seconds)
        (progn (setq jetpacs-echo--last (float-time))
               (let ((jetpacs-echo--in-toast t))
                 (ignore-errors (jetpacs-toast text))))
      (setq jetpacs-echo--pending text)
      (unless jetpacs-echo--timer
        (setq jetpacs-echo--timer
              (run-at-time (- jetpacs-echo-throttle-seconds since) nil
                           #'jetpacs-echo--flush))))))

(defun jetpacs-echo--after-message (format-string &rest args)
  ":after advice on `message': mirror device-flow messages."
  (when (and jetpacs-echo-toast
             (not jetpacs-echo--in-toast)
             (not inhibit-message)
             format-string
             (jetpacs-device-flow-p)
             (jetpacs-connected-p))
    (let ((text (apply #'format format-string args)))
      (when (and (not (string-empty-p text))
                 ;; Our own chatter must not echo back to the device:
                 ;; every module here logs under a "jetpacs" / "ebp"
                 ;; prefix, and a bridge message about the bridge is
                 ;; noise at best and a loop at worst.
                 (not (string-match-p "\\`\\(jetpacs\\|ebp\\)[-:. ]" text)))
        (jetpacs-echo--send text)))))

(defun jetpacs-echo-install ()
  "Enable the bridge: advise `message' and turn the mirror on."
  (interactive)
  (setq jetpacs-echo-toast t)
  (unless (advice-member-p #'jetpacs-echo--after-message 'message)
    (advice-add 'message :after #'jetpacs-echo--after-message)))

(defun jetpacs-echo-uninstall ()
  "Disable the bridge and remove the advice."
  (interactive)
  (setq jetpacs-echo-toast nil)
  (advice-remove 'message #'jetpacs-echo--after-message)
  (when (timerp jetpacs-echo--timer)
    (cancel-timer jetpacs-echo--timer))
  (setq jetpacs-echo--timer nil jetpacs-echo--pending nil))

(defun jetpacs-echo-unload-function ()
  "Unload hygiene."
  (jetpacs-echo-uninstall)
  nil)

(provide 'jetpacs-echo)
;;; jetpacs-echo.el ends here
