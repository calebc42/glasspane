;;; init.el --- Jetpacs on-device daily driver -*- lexical-binding: t; -*-

;; ONBOARDING (one line): put this in the DEVICE Emacs's ~/.emacs.d/init.el:
;;
;;   (load "/sdcard/Documents/jetpacs/init.el")
;;
;; Everything else lives here, on /sdcard, where `device/install.sh'
;; can refresh it over adb without touching app-private storage.

(add-to-list 'load-path "/sdcard/Documents/jetpacs")

;; The base stack…
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-navigate)
(require 'jetpacs-chrome)
(require 'jetpacs-dialog)
(require 'jetpacs-complete)
;; …the mode skins (additive: they register for their major modes)…
(require 'jetpacs-comint)
(require 'jetpacs-sections)
(require 'jetpacs-results)
(require 'jetpacs-tablist)
(require 'jetpacs-hypertext)
;; …and the apps.
(require 'jetpacs-theme)
(require 'jetpacs-clip)
(require 'jetpacs-device)
(require 'jetpacs-files)
(require 'jetpacs-launcher)
;; The org experience (JA-5).  jetpacs-org-render pulls the engine and
;; the dialogs, registers the org-mode skin, and — because jetpacs-files
;; is already loaded above — wires the editor seams, so a `.org' tapped
;; in Files opens RENDERED with the pencil toggle, the toolbar on the
;; plain editor, and the add-heading FAB.  Habits registers the
;; `jetpacs.org' owner: reach it from the Apps button.
(require 'jetpacs-org-render)
(require 'jetpacs-org-habits)

;; Mirror the device Emacs theme onto the chrome; `system'/`dark'/`off'
;; are the other choices (see `jetpacs-theme-mode').
(setq jetpacs-theme-mode 'mirror)

;; Every kill re-pushing the clip view would CLAIM THE SCREEN (one app
;; surface, last push wins).  Reach the kill ring with
;; M-x jetpacs-clip-show; come home with M-x jetpacs-hub.
(setq jetpacs-clip-auto-refresh nil)

;;;; The hub — the screen you land on and come home to

(defun jetpacs-hub--row (title subtitle buffer)
  (jetpacs-chrome-row title :subtitle subtitle :icon "description"
                      :key (jetpacs-wire-id "hubrow" buffer)
                      :on-tap (jetpacs-action "hub.open"
                                              :args (list :buffer buffer))))

(defun jetpacs-hub--screen (_back)
  (jetpacs-chrome-screen
   "Jetpacs"
   (jetpacs-column
    (jetpacs-hub--row "Scratch" "lisp playground" "*scratch*")
    (jetpacs-hub--row "Messages" "the Emacs log" "*Messages*")
    (jetpacs-hub--row "Shell" "comint, with input" "*shell*")
    (jetpacs-text "Kill ring: M-x jetpacs-clip-show   ·   files: M-x jetpacs-files   ·   home: M-x jetpacs-hub"
                  :style "caption")
    :spacing 8)
   :actions (list (jetpacs-button
                   "Theme" (jetpacs-action "jetpacs.theme.modus-toggle"))
                  (jetpacs-launcher-button))))

(with-jetpacs-owner "hub"
  (jetpacs-chrome-define-root "hub" "home" #'jetpacs-hub--screen
                              :required t)
  (jetpacs-defaction "hub.open"
    (lambda (args params)
      (let ((name (plist-get args :buffer))
            (surface (plist-get params :surface)))
        (jetpacs-flow-continue
         (lambda ()
           (when (and (equal name "*shell*") (not (get-buffer name)))
             (save-window-excursion (shell)))
           (condition-case err
               (jetpacs-navigate-buffer name surface)
             (error (message "hub.open: %s" (jetpacs--error-label err))))))
        'accepted))))

;;;; Connection

(defun jetpacs-start (&optional attempt)
  "Dial the Companion on this device and land on the hub.
Retries for ~45 s at 3 s intervals: at boot — and after the Companion
is opened by hand — the listener can bind well after Emacs starts, and
a 4 s window (the first cut) lost that race whenever the app came up
second.  After the last attempt it says exactly what to do, instead of
an error nobody is watching for."
  (interactive)
  (condition-case err
      (jetpacs--start-1)
    (error
     (if (>= (or attempt 0) 15)
         (message "jetpacs: Companion not reachable — open the EBP \
Companion app, then M-x jetpacs-start")
       (run-at-time 3 nil #'jetpacs-start (1+ (or attempt 0)))
       (when (zerop (or attempt 0))
         (message "jetpacs: Companion not up yet; retrying for 45 s…"))))))

(defun jetpacs--start-1 ()
  (jetpacs-connect
   "127.0.0.1" 8765
   :client-name "device-emacs" :client-version emacs-version
   :pairing-id "101112131415161718191a1b1c1d1e1f"
   :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
   :wants '("theme" "presentation.toast" "surfaces.dialog"
            "reminders.owner" "offline.wake" "editor.sync")
   :receipt-file (expand-file-name "jetpacs-receipts.sqlite"
                                   user-emacs-directory)
   :ready-function (lambda (_c) (jetpacs-hub))))

(defun jetpacs-hub ()
  "Bring the hub back to the screen (from clip, or anywhere)."
  (interactive)
  (jetpacs-shell-push "app:hub" :current-view "home"))

(defun jetpacs-stop ()
  "Close the session."
  (interactive)
  (when-let* ((c (jetpacs-client)))
    (ebp-client-close c 'user-quit)
    (jetpacs-detach)))

;; Auto-connect at startup; demoted so a Companion that is not running
;; yet never breaks init — M-x jetpacs-start once it is.
(add-hook 'after-init-hook
          (lambda () (with-demoted-errors "jetpacs-start: %S"
                       (jetpacs-start))))

;;; init.el ends here
