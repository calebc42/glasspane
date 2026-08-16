;;; jetpacs-init.el --- Compose and start Jetpacs -*- lexical-binding: t; -*-

;; This is the package composition root loaded by `(require 'jetpacs)'.  Code
;; may come from package.el/package-vc or from the Companion's bundled offline
;; installation.  Durable state has one layout-independent home at
;; ~/.emacs.d/jetpacs; package code is never assumed to live there.

(require 'subr-x)
(declare-function server-running-p "server" ())
(declare-function server-start "server" (&optional leave-dead inhibit-prompt))

;; Android's exported file-opening activity hands warm launches to
;; emacsclient.  The user's init has already run before this managed loader,
;; so honor any server configuration it established and fill in only the
;; missing server.  This makes onboarding/repair links to the real init.el
;; work after the first Jetpacs start without affecting desktop Emacs.
(when (eq system-type 'android)
  (require 'server)
  (unless (server-running-p)
    (server-start)))

(defvar jetpacs-install-root
  (file-name-as-directory
   (expand-file-name "jetpacs/" user-emacs-directory))
  "Root of Jetpacs's removable, user-private state tree.")

(defconst jetpacs-elisp-directory
  (file-name-as-directory
   (file-name-directory
    (or load-file-name
        (locate-library "jetpacs-init")
        buffer-file-name)))
  "Directory containing the active Jetpacs package libraries.")

(defconst jetpacs-var-directory
  (expand-file-name "var/" jetpacs-install-root)
  "Durable Jetpacs protocol state, kept inside the managed tree.")

(defun jetpacs-install-conf-value (key)
  "Return KEY from this installation's simple key=value record."
  (let ((file (expand-file-name "install.conf" jetpacs-install-root)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents-literally file)
        (goto-char (point-min))
        (when (re-search-forward
               (concat "^" (regexp-quote key) "=\\(.*\\)$") nil t)
          (string-trim-right (match-string-no-properties 1) "\\r"))))))

(defvar jetpacs-vault-directory
  (file-name-as-directory
   (or (jetpacs-install-conf-value "vault")
       (getenv "HOME")
       (expand-file-name "~/")))
  "Root for user content selected during onboarding.
This is deliberately separate from HOME and `user-emacs-directory', which
remain in the private Emacs/Termux home on Android.")

(defvar jetpacs-vault-mode
  (or (jetpacs-install-conf-value "vault_mode") "advanced")
  "Onboarding label for `jetpacs-vault-directory'.")

(defvar jetpacs-home-mode
  (or (jetpacs-install-conf-value "home_mode") "emacs")
  "Onboarding label for the Unix HOME containing `user-emacs-directory'.")

(unless (and (file-name-absolute-p jetpacs-vault-directory)
             (not (file-remote-p jetpacs-vault-directory)))
  (error "Jetpacs Vault must be a local absolute directory: %s"
         jetpacs-vault-directory))

;; The user's init ran before this loader and is authoritative.  The selected
;; Vault supplies fallbacks only: an existing `org-directory' or any
;; predeclared jetpacs-* path survives unchanged.  In particular, do not reset
;; `default-directory' out from under a user's project/session setup.
(defvar org-directory (expand-file-name "org/" jetpacs-vault-directory))
(defvar jetpacs-files-default-dir jetpacs-vault-directory)
(defvar jetpacs-files-roots
  (delete-dups
   (delq nil
         (list user-emacs-directory
               (file-name-as-directory (expand-file-name "~/"))
               jetpacs-vault-directory
               (and (stringp org-directory)
                    (file-name-as-directory
                     (expand-file-name org-directory)))))))

(add-to-list 'load-path jetpacs-elisp-directory)

;; Repo apps keep their subdirectories in the managed installation instead of
;; being flattened into one ambiguous directory.
(let ((apps-dir (expand-file-name "apps/" jetpacs-elisp-directory)))
  (when (file-directory-p apps-dir)
    (dolist (dir (directory-files apps-dir t directory-files-no-dot-files-regexp))
      (when (file-directory-p dir)
        (add-to-list 'load-path dir)))))

(make-directory jetpacs-var-directory t)

;; Profile defaults are established before their defining libraries load.
;; Any value already set by the user's init or Emacs Custom remains bound and
;; therefore wins; the libraries' defvar/defcustom forms preserve it too.
(declare-function jetpacs-emacs-ui-mx-button "jetpacs-emacs-ui" ())
(defvar jetpacs-apps-core-global-actions
  (lambda (_surface) (list (jetpacs-emacs-ui-mx-button))))
(defvar jetpacs-apps-core-dock-items #'jetpacs-hub--dock-items)
(defvar jetpacs-apps-core-drawer-rows #'jetpacs-hub--drawer-rows)
(defvar jetpacs-theme-mode 'mirror)
(defvar jetpacs-clip-auto-refresh nil)

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
(require 'jetpacs-repl)      ; the Elisp REPL this home screen IS
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
(defvar ebp-org-roots (jetpacs-files-effective-roots)
  "Directories structured Org actions may resolve by default.
Jetpacs uses the same effective allowlist as the Files app so an Org document
opened from the user's Vault never renders action controls that the Org engine
then silently refuses.  A value set by the user's init remains authoritative.")
(require 'jetpacs-launcher)
(require 'jetpacs-emacs-ui)   ; the Buffers app + the global M-x verb
;; Org Mode is a real Jetpacs App.  Its composition root installs the
;; reusable reader/editor hosts, their Org adapters, the existing Org
;; renderer/dialogs/habits modules, and app identity.  A `.org' file in
;; Files therefore opens in the reader with a text-editor toggle, while
;; the Apps view also gains an Org Mode home.  This is the template a
;; future `jetpacs-elisp-mode' app can reuse.
(require 'jetpacs-org-mode)
;; Glasspane is an in-tree app in this development bundle.  It registers its
;; own routes and config subtree; the Org reader remains owned by Org Mode, so
;; loading Glasspane cannot replace the Files/manual reading path.
(when (require 'glasspane nil t)
  (when (and (not noninteractive)
             (fboundp 'glasspane-config-ensure))
    (glasspane-config-ensure)))
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

;; The curated settings content (owner: POC 1's settings had the right
;; content in the wrong shape).  Registered at boot so a queued toggle
;; replays even before the screen first renders.  The org/calendar
;; sections + the phone-generic org seeding are the foundation
;; module's (the ratified §3 relocation) — required here under the
;; same boot rule.
(require 'jetpacs-org-settings)
(jetpacs-settings-register-section
 "Appearance"
 '((jetpacs-theme-mode :label "Companion theme")
   ;; The §3 fold-in: the app's authored enum node retired — the
   ;; choice-of-consts custom-type renders an equivalent enum.
   (jetpacs-line-numbers :label "Line numbers")))
(jetpacs-settings-register-section
 "Editor"
 '((ebp-sync-diagnostics :label "Push diagnostics")
   (ebp-sync-fontify :label "Push syntax highlighting")
   (ebp-sync-eldoc :label "Push documentation")))
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
 '((jetpacs-files-sync-editor :label "Live editing")
   (jetpacs-files-shared-storage :label "Shared storage access")
   (jetpacs-files-max-rows :label "Directory rows shown")))

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

(defun jetpacs-hub--drawer-rows (_surface)
  ;; The host's drawer TAIL (owner decisions 2026-08-06, pass 4): the
  ;; Tools nest, then — below the divider, settings-last like every
  ;; Android app — the Settings nest.  The HEAD (the Apps row and the
  ;; S1 destination nests) is `jetpacs-apps-drawer''s own; this seed
  ;; composes below it through `jetpacs-apps-core-drawer-rows', and
  ;; the S8 seam hangs the finished drawer on every build-within
  ;; root — the hub stopped authoring it by hand.  An App = a Tier 1
  ;; elisp package built ON jetpacs; org activates like a major mode
  ;; (on file open, never a destination); Files lives in the nav-bar
  ;; dock only.
  (list (jetpacs-hub--tools-entry)
        (jetpacs-divider)
        (jetpacs-settings-drawer-entry)))

(defun jetpacs-hub--dock-items (surface)
  "The persistent view switcher's destinations, as data.
The hub root IS the Eval REPL (owner decision 2026-08-06: no separate
home screen), so the two global destinations are named honestly: Eval
and Files."
  (let ((sel (cond ((equal surface "app:jetpacs.files") 'files)
                   ((equal surface "app:hub") 'home))))
    (list (list :label "Eval" :icon "code"
                :on-tap (jetpacs-action "hub.home")
                :selected (eq sel 'home))
          (list :label "Files" :icon "folder_open"
                :on-tap (jetpacs-action "jetpacs.launcher.open"
                                        :args '(:surface "app:jetpacs.files"))
                :selected (eq sel 'files)))))

;;;; Home IS the Eval REPL (owner decision 2026-08-06: no hub screen —
;;;; the core is a command-runner, a file explorer, and this).  POC 1's
;;;; Eval feel, improved: history cards newest-first with copy and
;;;; re-run, error results styled as errors, a pinned elisp input that
;;;; can never be pushed off-screen, and *scratch*-style multi-form
;;;; evaluation with * ** *** holding the last three results.

(defconst jetpacs-hub--repl "hub"
  "The hub's `jetpacs-repl' session id.")

(defun jetpacs-hub--screen (_back)
  ;; Amendment #169 (R3): the REPL editor below presents in the hub APP
  ;; surface — register whether its completion replies may carry
  ;; candidate `kind', per the live welcome (the author-time half of the
  ;; sender-omit rule; re-evaluated every build, so it follows a
  ;; reconnect's welcome).  The editor node itself now comes from
  ;; `jetpacs-repl-input-row', but the ids are the same pair.
  (when (fboundp 'ebp-complete-set-editor-kinds)
    (ebp-complete-set-editor-kinds
     "scratch.el" "hub-eval"
     (and (jetpacs-client)
          (jetpacs-feature-advertised-p "editor.candidate_kind" :app))))
  (jetpacs-chrome-screen
   "Jetpacs"
   (jetpacs-column
    (jetpacs-with-attrs
     (if-let* ((cards (jetpacs-repl-cards jetpacs-hub--repl :verb "hub.eval")))
         (apply #'jetpacs-lazy-column cards)
       (jetpacs-repl-empty-state))
     :weight 1)
    (jetpacs-divider)
    ;; A SYNCHRONIZED §19 editor, not a local draft: `:document' makes
    ;; the Companion open an edit session on the next push, so the text
    ;; arrives as deltas into `ebp.el''s mirror and `hub.eval' reads it
    ;; from there.  (Since R0 a bridged `completing-read' picker claims
    ;; only its OWN document in ebp.el's override table, so this
    ;; dropdown keeps answering while a prompt is up.)
    (jetpacs-repl-input-row :editor-id "hub-eval" :document "scratch.el"
                            :verb "hub.eval"))
   ;; No :drawer here since S8: the seam hangs the composed host
   ;; drawer on this root — and on every other build-within root —
   ;; from `jetpacs-apps-drawer'; authoring it here too would merely
   ;; shadow the same node.
   :actions (list (jetpacs-emacs-ui-mx-button))))

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
    ;; The REPL submit: the send button arrives without a value and
    ;; reads the SYNCHRONIZED mirror — the editor carries `:document',
    ;; so it is no longer a stateful draft and `jetpacs-ui-state' would
    ;; be nil forever.  `on-enter' and the re-run button carry :value.
    ;; Evaluation is continuation work — user code can take arbitrarily
    ;; long, prompt, or signal.
    (lambda (args _params)
      (let ((input (or (plist-get args :value)
                       (when-let* ((client (jetpacs-client)))
                         (ebp-client-editor-text
                          client "scratch.el" "hub-eval")))))
        (if (not (and (stringp input)
                      (not (string-blank-p input))))
            'rejected
          (jetpacs-flow-continue
           (lambda ()
             (jetpacs-repl-run jetpacs-hub--repl input)
             (ignore-errors (jetpacs-shell-push "hub"))))
          'accepted)))
    :any-surface t))

;;;; Connection

(defvar jetpacs-pairing-id "101112131415161718191a1b1c1d1e1f"
  "Pairing identity used to authenticate this Emacs to the Companion.")

(defvar jetpacs-pairing-token "AAECAwQFBgcICQoLDA0ODw"
  "Display-form pairing token used to authenticate to the Companion.")

(defun jetpacs-start (&optional attempt)
  "Dial the Companion on this device and land on the hub.
Retries for ~45 s at 3 s intervals: at boot — and after the Companion
is opened by hand — the listener can bind well after Emacs starts, and
a 4 s window (the first cut) lost that race whenever the app came up
second.  After the last attempt it says exactly what to do, instead of
an error nobody is watching for."
  (interactive)
  (condition-case nil
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
   :pairing-id jetpacs-pairing-id
   :token (ebp-decode-pairing-token jetpacs-pairing-token)
   :wants '("theme" "presentation.toast" "presentation.snackbar"
            "surfaces.dialog" "reminders.owner" "offline.wake"
            "editor.sync")
   :receipt-file (expand-file-name "receipts.sqlite"
                                   jetpacs-var-directory)
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

;; Personal overrides are deliberately last and deliberately inside the one
;; removable tree.  Onboarding never creates or overwrites this file.
(let ((user-file (expand-file-name "user.el" jetpacs-install-root)))
  (when (file-readable-p user-file)
    (load user-file nil 'nomessage)))

(provide 'jetpacs-init)
;;; jetpacs-init.el ends here
