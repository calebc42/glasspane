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
(require 'jetpacs-transient)
(require 'jetpacs-devtools)   ; the push profiler + failure flight recorder
;; …the mode skins (additive: they register for their major modes)…
(require 'jetpacs-comint)
(require 'jetpacs-sections)
(require 'jetpacs-results)
(require 'jetpacs-tablist)
(require 'jetpacs-package-browser)
(require 'jetpacs-settings)
(require 'jetpacs-customize)
(require 'jetpacs-project)
(require 'jetpacs-sql)
(require 'jetpacs-apps)
(require 'jetpacs-app-store)
;; Load bundles the Manage Apps screen installed in past sessions —
;; each isolated, so one broken bundle never costs the boot.
(jetpacs-app-store-boot)
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
;; The Material 3 Compose Catalog (owner `m3catalog'): 41 components
;; and 279 examples of the node vocabulary, on its own surface.  It is
;; also the tree's first `jetpacs-defapp' registration, so its "Catalog"
;; destination composes into every dock.  Reach it there, from the Apps
;; button, or M-x jetpacs-m3-catalog.
(require 'jetpacs-m3-catalog)
;; The live editor loop (parity P1), and the `ebp-' half of the stack:
;; wire and Emacs only, no node vocabulary.  Buffer sync with its
;; riders, then the capf completion server answering `edit.complete' —
;; `jetpacs-connect' looks for it at dial time, so requiring it HERE is
;; what turns device completion on.
(require 'ebp-sync)
(require 'ebp-complete)

;; Mirror the device Emacs theme onto the chrome; `system'/`dark'/`off'
;; are the other choices (see `jetpacs-theme-mode').
(setq jetpacs-theme-mode 'mirror)

;; The curated settings content (owner: POC 1's settings had the right
;; content in the wrong shape).  Registered at boot so a queued toggle
;; replays even before the screen first renders.
(jetpacs-settings-register-section
 "Appearance"
 '((jetpacs-theme-mode :label "Companion theme")))
(jetpacs-settings-register-section
 "Editor"
 '((ebp-sync-diagnostics :label "Push diagnostics")
   (ebp-sync-fontify :label "Push syntax highlighting")))
;; The SPEC 23.3 explicit developer setting: full failure detail stays
;; local and bounded, and only while this is on.
(jetpacs-settings-register-section
 "Devtools"
 '((jetpacs-devtools-recording :label "Record failure details")))
(jetpacs-settings-register-section
 "Clipboard"
 '((jetpacs-clip-auto-refresh :label "Auto-refresh the kill ring")
   (jetpacs-clip-max-entries :label "Kill-ring entries shown")))
(jetpacs-settings-register-section
 "Files"
 '((jetpacs-files-shared-storage :label "Shared storage access")
   (jetpacs-files-max-rows :label "Directory rows shown")))

;; Every kill re-pushing the clip view would CLAIM THE SCREEN (one app
;; surface, last push wins).  Reach the kill ring with
;; M-x jetpacs-clip-show; come home with M-x jetpacs-hub.
(setq jetpacs-clip-auto-refresh nil)

;;;; The hub — the screen you land on and come home to

;; The hub chrome follows docs/CHROME-VOCABULARY.md: the DRAWER (left,
;; behind the Companion's hamburger) holds app destinations, the TOP BAR
;; keeps M-x top-right, and the view switcher — Home / Files / Eval,
;; the poc's tabs reborn — docks as the BOTTOM BAR, or as a NAVIGATION
;; RAIL when the window is expanded (SPEC 20.1.1).  Eval is *ielm*: ielm
;; derives from comint-mode, so the comint skin's pinned input row is
;; the REPL.

(defun jetpacs-hub--tools-entry ()
  "The drawer's Tools nest: the everyday utilities under one header —
Clipboard, the Messages log, the buffer switcher, and the two devtools
rows: the push-loop report, and Inspect a screen."
  (jetpacs-collapsible
   "drawer-tools"
   ;; A plain row: the header line is the expand target.
   (jetpacs-row
    (jetpacs-icon "build")
    (jetpacs-with-attrs
     (jetpacs-column (jetpacs-text "Tools")
                     (jetpacs-text "Clipboard, logs, buffers"
                                   :style "caption")
                     :spacing 2)
     :weight 1))
   (jetpacs-chrome-row
    "Clipboard" :subtitle "the kill ring" :icon "content_paste"
    :on-tap (jetpacs-action "jetpacs.launcher.open"
                            :args '(:surface "app:jetpacs.clip"))
    :key "drawer-tools-clip")
   (jetpacs-chrome-row
    "Messages" :subtitle "the Emacs log" :icon "description"
    :on-tap (jetpacs-action "hub.open" :args '(:buffer "*Messages*"))
    :key "drawer-tools-messages")
   (jetpacs-chrome-row
    "Buffers" :subtitle "every live buffer" :icon "view_list"
    :on-tap (jetpacs-action "jetpacs.emacs.buffers")
    :key "drawer-tools-buffers")
   (jetpacs-chrome-row
    "Scratch" :subtitle "lisp playground" :icon "description"
    :on-tap (jetpacs-action "hub.open" :args '(:buffer "*scratch*"))
    :key "drawer-tools-scratch")
   (jetpacs-chrome-row
    "Shell" :subtitle "comint, with input" :icon "terminal"
    :on-tap (jetpacs-action "hub.open" :args '(:buffer "*shell*"))
    :key "drawer-tools-shell")
   (jetpacs-chrome-row
    "Devtools" :subtitle "push loop, failures" :icon "build"
    :on-tap (jetpacs-action "hub.open" :args '(:buffer "*jetpacs-devtools*"))
    :key "drawer-tools-devtools")
   ;; The homoiconic loop, one tap in: the verb picks a live surface
   ;; through the bridged picker, builds its spec fresh, and shows the
   ;; Lisp on the phone.  Copy the sexp into the Eval REPL two screens
   ;; away, edit it, and `jetpacs-shell-push' it back with :spec.
   (jetpacs-chrome-row
    "Inspect a screen" :subtitle "its spec, as Lisp" :icon "data_object"
    :on-tap (jetpacs-action "jetpacs.devtools.inspect-pick")
    :key "drawer-tools-inspect")
   :collapsed t))

(defun jetpacs-hub--drawer ()
  ;; The drawer IA (owner decisions 2026-08-06, pass 4): Apps first,
  ;; then the Tools nest, then — below the divider, settings-last like
  ;; every Android app — the Settings nest.  An App = a Tier 1 elisp
  ;; package built ON jetpacs; org activates like a major mode (on file
  ;; open, never a destination); Files lives in the nav-bar dock only.
  ;; lazy_column: a plain column cannot scroll past the fold.
  (jetpacs-lazy-column
   (jetpacs-apps-drawer-row)
   (jetpacs-hub--tools-entry)
   (jetpacs-divider)
   (jetpacs-settings-drawer-entry)
   :spacing 8))

(defun jetpacs-hub--dock-items (surface)
  "The persistent view switcher's destinations, as data.
Home IS the Eval REPL now (owner decision 2026-08-06: no hub screen),
so the dock is two destinations: Home and Files."
  (let ((sel (cond ((equal surface "app:jetpacs.files") 'files)
                   ((equal surface "app:hub") 'home))))
    (list (list :label "Home" :icon "home"
                :on-tap (jetpacs-action "hub.home")
                :selected (eq sel 'home))
          (list :label "Files" :icon "folder_open"
                :on-tap (jetpacs-action "jetpacs.launcher.open"
                                        :args '(:surface "app:jetpacs.files"))
                :selected (eq sel 'files)))))

;; The hub's destinations are the HOST-authored core dock: the app
;; layer composes them with per-app destinations (single-app contract:
;; with fewer than two apps this renders exactly these items).
(setq jetpacs-apps-core-dock-items #'jetpacs-hub--dock-items)

;;;; Home IS the Eval REPL (owner decision 2026-08-06: no hub screen —
;;;; the core is a command-runner, a file explorer, and this).  POC 1's
;;;; Eval feel, improved: history cards newest-first with copy and
;;;; re-run, error results styled as errors, a pinned elisp input that
;;;; can never be pushed off-screen, and *scratch*-style multi-form
;;;; evaluation with * ** *** holding the last three results.

(defvar jetpacs-hub--eval-history nil
  "REPL history, newest first: (INPUT OUTPUT ERRORP).")

(defvar jetpacs-hub--eval-history-max 50)
(defvar jetpacs-hub--eval-output-max 2000)

(defun jetpacs-hub--eval-card (idx entry)
  (pcase-let* ((`(,input ,output ,errorp) entry)
               (shown (if (> (length output) jetpacs-hub--eval-output-max)
                          (concat (substring
                                   output 0 jetpacs-hub--eval-output-max)
                                  " …")
                        output)))
    (jetpacs-card
     (jetpacs-column
      (jetpacs-row
       (jetpacs-with-attrs
        (jetpacs-text (concat "λ> " input) :style "label" :max-lines 2)
        :weight 1)
       (jetpacs-icon-button "content_copy" (jetpacs-clipboard-copy output)
                            :content-description "Copy result")
       (jetpacs-icon-button "play_arrow"
                            (jetpacs-action "hub.eval"
                                            :args (list :value input))
                            :content-description "Re-run"))
      (jetpacs-text shown :style "mono" :selectable t
                    :color (and errorp "error"))))))

(defun jetpacs-hub--eval-card-keyed (idx entry)
  "The history card with its reconciliation key attached the legal way:
:key is a universal attribute, not a card member."
  (jetpacs-with-attrs (jetpacs-hub--eval-card idx entry)
                      :key (jetpacs-wire-id "ev" (format "%d" idx))))

(defun jetpacs-hub--screen (_back)
  (let ((i -1))
    (jetpacs-chrome-screen
     "Jetpacs"
     (jetpacs-column
      (jetpacs-with-attrs
       (if jetpacs-hub--eval-history
           (apply #'jetpacs-lazy-column
                  (mapcar (lambda (e)
                            (jetpacs-hub--eval-card-keyed (cl-incf i) e))
                          jetpacs-hub--eval-history))
         (jetpacs-empty-state
          :icon "code" :title "Elisp REPL"
          :caption (concat "Results appear here, newest first.  "
                           "* ** and *** hold the last three results.")))
       :weight 1)
      (jetpacs-divider)
      (jetpacs-with-attrs
       (jetpacs-row
        (jetpacs-with-attrs
         (jetpacs-editor "hub-eval" :chromeless t :publish-state t
                         :syntax "elisp"
                         :on-enter (jetpacs-action "hub.eval"))
         :weight 1)
        (jetpacs-icon-button "send" (jetpacs-action "hub.eval")
                             :content-description "Eval"))
       :padding 8))
     :actions (list (jetpacs-emacs-ui-mx-button))
     :drawer (jetpacs-hub--drawer))))

(defun jetpacs-hub--eval-forms (input)
  "Evaluate every form in INPUT like *scratch* would; the last value.
Feeds * ** *** the way ielm does, so follow-up expressions can chain."
  (let ((last nil))
    (with-temp-buffer
      (insert input)
      (goto-char (point-min))
      (condition-case nil
          (while t (setq last (eval (read (current-buffer)) t)))
        (end-of-file nil)))
    (set '*** (and (boundp '**) (symbol-value '**)))
    (set '** (and (boundp '*) (symbol-value '*)))
    (set '* last)
    last))

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
           ;; The devtools report regenerates on every open — stale
           ;; instrumentation is worse than none.
           (when (equal name "*jetpacs-devtools*")
             (jetpacs-devtools-report-buffer))
           (condition-case err
               (jetpacs-navigate-buffer name "app:hub")
             (error (message "hub.open: %s" (jetpacs-error-label err))))))
        'accepted))
    :any-surface t)

  (jetpacs-defaction "hub.home"
    ;; The view switcher's Home tab: back to the hub root.
    (lambda (_args _params)
      (jetpacs-flow-continue
       (lambda () (jetpacs-chrome-reset-screens "hub")))
      'accepted)
    :any-surface t)

  (jetpacs-defaction "hub.eval"
    ;; The REPL submit: the send button and re-run arrive without a
    ;; value and read the editor's published state; on-enter and the
    ;; re-run button carry :value.  Evaluation is continuation work —
    ;; user code can take arbitrarily long, prompt, or signal.
    (lambda (args _params)
      (let ((input (or (plist-get args :value)
                       (jetpacs-ui-state "hub-eval"))))
        (if (not (and (stringp input)
                      (not (string-blank-p input))))
            'rejected
          (jetpacs-flow-continue
           (lambda ()
             (let (output errorp)
               (condition-case err
                   (setq output (prin1-to-string
                                 (jetpacs-hub--eval-forms input)))
                 (error (setq output (error-message-string err)
                              errorp t))
                 (quit (setq output "Quit" errorp t)))
               (push (list input output errorp) jetpacs-hub--eval-history)
               (setq jetpacs-hub--eval-history
                     (seq-take jetpacs-hub--eval-history
                               jetpacs-hub--eval-history-max))
               (ignore-errors (jetpacs-shell-push "hub")))))
          'accepted)))
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
