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
(require 'jetpacs-emacs-ui)   ; the Buffers app + the global M-x verb
;; The org experience (JA-5).  jetpacs-org-render pulls the engine and
;; the dialogs, registers the org-mode skin, and — because jetpacs-files
;; is already loaded above — wires the editor seams, so a `.org' tapped
;; in Files opens RENDERED with the pencil toggle, the toolbar on the
;; plain editor, and the add-heading FAB.  Habits registers the
;; `jetpacs.org' owner: reach it from the Apps button.
(require 'jetpacs-org-render)
(require 'jetpacs-org-habits)
;; The Material 3 Expressive Catalog (owner `m3catalog'): 41 components
;; and 279 examples of the node vocabulary, on its own surface.  Reach
;; it from the Apps button, or M-x jetpacs-m3-catalog.
(require 'jetpacs-m3-catalog)

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

;; The hub chrome follows docs/CHROME-VOCABULARY.md: the DRAWER (left,
;; behind the Companion's hamburger) holds app destinations, the TOP BAR
;; keeps M-x top-right, and the BOTTOM BAR is the view switcher —
;; Home / Files / Eval, the poc's tabs reborn.  Eval is *ielm*: ielm
;; derives from comint-mode, so the comint skin's pinned input row is
;; the REPL.

(defun jetpacs-hub--drawer ()
  (apply #'jetpacs-column
         (append
          (list (jetpacs-text "Apps" :style "title"))
          (jetpacs-launcher-rows "app:hub")
          (list (jetpacs-divider)
                (jetpacs-chrome-row
                 "Theme" :subtitle "toggle modus light/dark"
                 :on-tap (jetpacs-action "jetpacs.theme.modus-toggle")
                 :key "drawer-theme")
                :spacing 8))))

(defun jetpacs-hub--tab (label icon on-tap &optional selected)
  (jetpacs-with-attrs
   (jetpacs-button label on-tap :icon icon
                   :variant (if selected "tonal" "text"))
   :weight 1))

;; The Eval screen is the *ielm* drill on the hub stack; the B5 minter
;; is stable across renders, so its id is computable here.
(defvar jetpacs-hub--eval-screen (jetpacs-wire-id "drill" "*ielm*"))

(defun jetpacs-hub--dock (surface)
  "The persistent view switcher, injected into EVERY chrome screen.
`jetpacs-chrome-dock-function' calls this once per surface build; the
selected tab follows where the user actually is: the files surface, the
hub's Eval drill, or the hub itself.  Every descriptor here is a global
verb — the dock renders on every owner's surface."
  (let ((sel (cond ((equal surface "app:jetpacs.files") 'files)
                   ((not (equal surface "app:hub")) nil)
                   ((equal (car (jetpacs-chrome-stack surface))
                           jetpacs-hub--eval-screen)
                    'eval)
                   (t 'home))))
    (jetpacs-row
     (jetpacs-hub--tab "Home" "home"
                       (jetpacs-action "hub.home") (eq sel 'home))
     (jetpacs-hub--tab "Files" "folder_open"
                       (jetpacs-action "jetpacs.launcher.open"
                                       :args '(:surface "app:jetpacs.files"))
                       (eq sel 'files))
     (jetpacs-hub--tab "Eval" "code"
                       (jetpacs-action "hub.open" :args '(:buffer "*ielm*"))
                       (eq sel 'eval))
     :spacing 4)))

(setq jetpacs-chrome-dock-function #'jetpacs-hub--dock)

(defun jetpacs-hub--screen (_back)
  (jetpacs-chrome-screen
   "Jetpacs"
   (jetpacs-column
    (jetpacs-hub--row "Scratch" "lisp playground" "*scratch*")
    (jetpacs-hub--row "Messages" "the Emacs log" "*Messages*")
    (jetpacs-hub--row "Shell" "comint, with input" "*shell*")
    (jetpacs-text "Kill ring: M-x jetpacs-clip-show   ·   home: M-x jetpacs-hub"
                  :style "caption")
    :spacing 8)
   :actions (list (jetpacs-emacs-ui-mx-button))
   :drawer (jetpacs-hub--drawer)))

(with-jetpacs-owner "hub"
  (jetpacs-chrome-define-root "hub" "home" #'jetpacs-hub--screen
                              :required t)
  ;; Both hub verbs are GLOBAL (the dock renders them on every chrome
  ;; surface) and target the HUB surface explicitly: tapping Eval from
  ;; Files means "take me to the hub's Eval view", never "drill ielm
  ;; onto the files stack".
  (jetpacs-defaction "hub.open"
    (lambda (args _params)
      (let ((name (plist-get args :buffer)))
        (jetpacs-flow-continue
         (lambda ()
           (when (and (equal name "*shell*") (not (get-buffer name)))
             (save-window-excursion (shell)))
           (when (and (equal name "*ielm*") (not (get-buffer name)))
             (save-window-excursion (ielm)))
           (condition-case err
               (jetpacs-navigate-buffer name "app:hub")
             (error (message "hub.open: %s" (jetpacs--error-label err))))))
        'accepted))
    :any-surface t)

  (jetpacs-defaction "hub.home"
    ;; The view switcher's Home tab: back to the hub root.
    (lambda (_args _params)
      (jetpacs-flow-continue
       (lambda () (jetpacs-chrome-reset-screens "hub")))
      'accepted)
    :any-surface t))

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
   :wants '("theme" "presentation.toast" "presentation.snackbar"
            "surfaces.dialog" "reminders.owner" "offline.wake"
            "editor.sync")
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
