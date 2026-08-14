;;; emacs-init.el --- Jetpacs onboarding harness (Termux + eglot) -*- lexical-binding: t; -*-

;; INSTALLED by tools/onboard-tablet.sh as
;;   $EMACS_HOME/.emacs.d/jetpacs-onboard-init.el
;; and LOADED by a single line appended to $EMACS_HOME/.emacs.d/init.el.
;;
;; It is installed beside init.el rather than AS init.el on purpose:
;; docs/ONBOARDING-device.md's daily-driver setup puts
;;   (load "/sdcard/Documents/jetpacs/init.el")
;; in that exact file, and overwriting it would silently uninstall the
;; daily driver.  The load line is APPENDED, so whatever was already in
;; init.el still runs first, and stage 5 below declines to dial when a
;; client is already attached -- which is what makes composing the two
;; safe rather than a race for the single Companion session.
;;
;; This is NOT device/init.el (the full jetpacs daily driver).  This is
;; the minimal harness the onboard flow uses to prove the device can
;;   (a) see the Termux toolchain on its exec-path/PATH,
;;   (b) load the elisp tree the bundle deployed under Termux's home,
;;   (c) dial the Companion and reach READY, and
;;   (d) serve the deployed Python fixtures through the Files app with
;;       live editor sync -- which is what lights up eglot/pylsp.
;;
;; Two Emacs-visible HOMEs, one shared uid:
;;   - Termux's HOME is /data/data/com.termux/files/home ("~" there).
;;   - org.gnu.emacs's HOME is its own app-private directory, set by the
;;     Android port from getFilesDir().getCanonicalPath() (src/android.c
;;     `setenv ("HOME", android_files_dir, 1)') -- NOT the above.  So
;;     this file NEVER writes "~/jetpacs/...": every path into the
;;     Termux side is the absolute /data/data/com.termux/... form.  The
;;     shared uid is what lets this process read those files at all;
;;     it does not merge the two homes.
;;
;; Contract with the rest of the onboarding flow:
;;   - IDEMPOTENT: safe to reinstall and safe to reload/re-eval -- every
;;     stage either checks before mutating (exec-path, PATH, load-path,
;;     files-roots) or is naturally idempotent (require, setq).
;;   - SELF-NARRATING: every stage logs a `jetpacs-emacs-init:'
;;     breadcrumb, success or failure, so *Messages* alone tells the
;;     whole provisioning story without a debugger attached.
;;   - NEVER ERRORS AT STARTUP: each stage is individually
;;     condition-cased, and the dial additionally runs under
;;     `with-demoted-errors' -- a broken or partial deploy degrades one
;;     stage at a time and still leaves a usable stock Emacs.
;;
;; Manual fallbacks (also self-narrated in *Messages* when needed):
;;   M-x jetpacs-emacs-init-connect   retry the Companion dial by hand
;;   M-x jetpacs-emacs-init-report    dump current state to *Messages*
;;
;; See device/MANIFEST.md for the deploy side of this contract.

;;; Code:

;;;; Stage 0: breadcrumb helper

(defun jetpacs-emacs-init--log (fmt &rest args)
  "Write a `jetpacs-emacs-init:' breadcrumb to *Messages* AND the log
file under Termux home — the file half is what the desktop can read
over ssh (the shared uid), which is how a headless session gets
diagnosed at all (the G9 practice: *Messages* is unreachable from
adb).  File IO failures are swallowed: logging must never break init."
  (let ((line (apply #'format fmt args)))
    (message "jetpacs-emacs-init: %s" line)
    (ignore-errors
      (with-temp-buffer
        (insert (format-time-string "%F %T ") line "\n")
        (append-to-file (point-min) (point-max)
                        (concat jetpacs-emacs-init-termux-home
                                "/jetpacs/init.log"))))))

;;;; Paths -- the deploy locations tools/onboard-tablet.sh populates.
;;;; If a stage below logs "NOT FOUND", the script's deploy target and
;;;; these constants have drifted apart and one of them needs fixing.
;;;; `defvar' on purpose: an override can be set before this file is
;;;; loaded (earlier in init.el) without editing it.

(defvar jetpacs-emacs-init-termux-home "/data/data/com.termux/files/home"
  "Termux's own HOME, absolute -- never reachable via \"~\" from here.")

(defvar jetpacs-emacs-init-termux-bin "/data/data/com.termux/files/usr/bin"
  "Termux's usr/bin, absolute.  Where python, pylsp, ssh &c. live.")

(defvar jetpacs-emacs-init-root
  (concat jetpacs-emacs-init-termux-home "/jetpacs")
  "The bundle root under Termux's home.
Added whole to `jetpacs-files-roots', so both the elisp tree and the
Python fixtures are browsable from the device.")

(defvar jetpacs-emacs-init-elisp-root
  (concat jetpacs-emacs-init-root "/emacs")
  "Where the onboard bundle deploys the jetpacs elisp tree.
The repo's emacs/ directory, apps/ subdirectories preserved.")

(defvar jetpacs-emacs-init-py-dir
  (concat jetpacs-emacs-init-root "/py")
  "Where the onboard bundle deploys the Python fixtures/work files.
`jetpacs-files-default-dir' lands here, so these are the files the
device Files app opens first -- and, being python-mode, the ones that
trigger the eglot/pylsp path.")

;;;; Stage 1: environment probe.  The two-HOME split above is a claim,
;;;; not a certainty, until this line runs on the actual device.

(jetpacs-emacs-init--log
 "own HOME=%S user-emacs-directory=%S system-type=%S"
 (getenv "HOME") user-emacs-directory system-type)

;;;; Stage 2: exec-path + PATH gain Termux's usr/bin.
;;;; Two independent reasons: `executable-find' and subprocess creation
;;;; consult `exec-path'; anything that shells out (and any server a
;;;; language server itself spawns) consults $PATH.  ebp-sync.el's
;;;; `ebp-sync-eglot' names this exact requirement.

(defun jetpacs-emacs-init--path-entries ()
  "Current $PATH, split, with trailing slashes normalized."
  (mapcar #'directory-file-name
          (split-string (or (getenv "PATH") "") path-separator t)))

(condition-case err
    (if (not (file-directory-p jetpacs-emacs-init-termux-bin))
        (jetpacs-emacs-init--log
         "Termux bin NOT FOUND at %s -- Termux not provisioned yet? \
eglot/pylsp will not be reachable until this exists."
         jetpacs-emacs-init-termux-bin)
      (let ((had-exec-path (and (member jetpacs-emacs-init-termux-bin
                                        exec-path)
                                t))
            (had-path (and (member (directory-file-name
                                    jetpacs-emacs-init-termux-bin)
                                   (jetpacs-emacs-init--path-entries))
                           t)))
        (add-to-list 'exec-path jetpacs-emacs-init-termux-bin)
        (unless had-path
          (setenv "PATH" (concat jetpacs-emacs-init-termux-bin
                                 path-separator (or (getenv "PATH") ""))))
        (jetpacs-emacs-init--log
         "Termux bin on exec-path (%s) and PATH (%s): %s"
         (if had-exec-path "already present" "added")
         (if had-path "already present" "added")
         jetpacs-emacs-init-termux-bin)
        ;; The single most useful breadcrumb on this page.  eglot
        ;; resolves its python server with `executable-find' at guess
        ;; time (30.1's `eglot-alternatives'), and when nothing resolves
        ;; it signals INSIDE `ebp-sync--ensure-eglot''s condition-case --
        ;; which logs a one-line "eglot connect failed (%s)" naming only
        ;; the error symbol, and nothing about why.  Answer the why
        ;; here, before any file is ever opened.
        (jetpacs-emacs-init--log
         "pylsp resolves to: %s"
         (or (executable-find "pylsp")
             "NOTHING -- eglot will find no python server"))))
  (error (jetpacs-emacs-init--log "exec-path/PATH stage FAILED: %s"
                                  (error-message-string err))))

;;;; Stage 3: load-path gains the deployed elisp tree, then the jetpacs
;;;; stack.  `jetpacs-files' alone pulls the whole graph (it requires
;;;; ebp-sync and every jetpacs- module it needs), but the list is
;;;; spelled out in test/smoke-files-sync.el's proven order anyway, each
;;;; require individually guarded, so a missing module names ITSELF in
;;;; *Messages* instead of hiding behind one failed top-level require.

(defvar jetpacs-emacs-init--elisp-ready nil
  "Non-nil once the elisp tree's root has been added to `load-path'.")

(condition-case err
    (if (not (file-directory-p jetpacs-emacs-init-elisp-root))
        (jetpacs-emacs-init--log
         "elisp tree NOT FOUND at %s -- has tools/onboard-tablet.sh run \
yet? every jetpacs require below is skipped."
         jetpacs-emacs-init-elisp-root)
      (add-to-list 'load-path jetpacs-emacs-init-elisp-root)
      ;; apps/<name>/*.el keeps its own subdirectory on-device (unlike
      ;; device/install.sh's /sdcard flatten).  Generic walk, not
      ;; hardcoded to m3-catalog -- though note jetpacs-m3-catalog.el
      ;; ALSO self-registers its own directory relative to its own file,
      ;; so this is belt-and-braces for a future app that does not.
      (let ((apps-dir (concat jetpacs-emacs-init-elisp-root "/apps")))
        (when (file-directory-p apps-dir)
          (dolist (d (directory-files apps-dir t "\\`[^.]"))
            (when (file-directory-p d) (add-to-list 'load-path d)))))
      (setq jetpacs-emacs-init--elisp-ready t)
      (jetpacs-emacs-init--log "load-path gained %s (+ apps/*)"
                               jetpacs-emacs-init-elisp-root))
  (error (jetpacs-emacs-init--log "load-path stage FAILED: %s"
                                  (error-message-string err))))

(when jetpacs-emacs-init--elisp-ready
  ;; jetpacs-launcher is load-bearing for MULTI-APP hosts (G9 catch):
  ;; it self-registers the GLOBAL `jetpacs.launcher.open' verb every
  ;; dock/drawer row dispatches — without it a dock tap answers
  ;; "action not allowlisted" and app switching silently dies.
  (dolist (feat '(ebp ebp-sync ebp-complete
                  jetpacs-widgets jetpacs-async jetpacs-surfaces
                  jetpacs-shell jetpacs-buffer jetpacs-navigate
                  jetpacs-chrome jetpacs-launcher jetpacs-files))
    (condition-case err
        (progn (require feat) (jetpacs-emacs-init--log "required %s" feat))
      (error (jetpacs-emacs-init--log "require %s FAILED: %s" feat
                                      (error-message-string err))))))

;; eglot itself is NOT required here on purpose: `ebp-sync--ensure-eglot'
;; pulls it in lazily with `(require 'eglot nil t)', only for an attached
;; buffer whose major-mode is in `ebp-sync-eglot-modes' (python-mode and
;; python-ts-mode are both in the default set), and Emacs 30.1 ships
;; eglot built in.  Stage 2 is the only thing this init owes it.

;;;; Stage 3b: the DEVICE timing profile (measured on the Pixel
;;;; Tablet, 2026-08-13).  A cold pylsp overruns the 1s desktop
;;;; defaults -- the live harvest answered empty until the server
;;;; warmed, and the doc fetch has a synchronous completionItem/resolve
;;;; inside it.  5s keeps a thinking server a degraded answer rather
;;;; than a dead feature; the with-timeout bound still protects the
;;;; session either way.

(with-eval-after-load 'ebp-complete
  (setq ebp-complete-live-timeout 5.0)
  (setq ebp-complete-doc-timeout 5.0))

;;;; Stage 4: jetpacs-files-roots gains the deployed bundle root.
;;;; EXTEND, not replace: the stock defaults (`user-emacs-directory',
;;;; `org-directory', "~/") all resolve inside org.gnu.emacs's own
;;;; sandboxed HOME -- a different tree than Termux's -- so they are
;;;; harmless, and keeping them means this harness never narrows what a
;;;; stock Emacs already offered.

(condition-case err
    (cond
     ((not (featurep 'jetpacs-files))
      (jetpacs-emacs-init--log
       "jetpacs-files not loaded -- skipping files-roots setup"))
     ((not (file-directory-p jetpacs-emacs-init-root))
      (jetpacs-emacs-init--log
       "bundle root NOT FOUND at %s -- leaving jetpacs-files-roots at its \
default; has tools/onboard-tablet.sh run yet?"
       jetpacs-emacs-init-root))
     (t
      (add-to-list 'jetpacs-files-roots jetpacs-emacs-init-root)
      ;; Deterministic harness: no /sdcard probe, so no storage
      ;; permission dialog anywhere in this flow.  The deployed tree is
      ;; reachable without one.
      (setq jetpacs-files-shared-storage nil)
      (when (file-directory-p jetpacs-emacs-init-py-dir)
        (setq jetpacs-files-default-dir jetpacs-emacs-init-py-dir))
      (jetpacs-emacs-init--log "jetpacs-files-roots now %S (default-dir %s)"
                               jetpacs-files-roots
                               jetpacs-files-default-dir)))
  (error (jetpacs-emacs-init--log "files-roots stage FAILED: %s"
                                  (error-message-string err))))

;;;; Stage 4b: the engine set + the Glasspane app (G9).  The elpa dirs
;;;; are PUSHED by the onboarding channel (desktop-staged vulpea /
;;;; org-srs / ef-themes + deps -- the tablet never dials MELPA);
;;;; package-initialize just wires what is already on disk.  Glasspane
;;;; registers at require (owner, chrome root, dock) and its packages
;;;; module lights the vulpea features up when the probe finds the
;;;; engines.  Both guarded: a tree without the app, or an elpa without
;;;; the engines, degrades to exactly the pre-G9 init.

(condition-case err
    (progn
      (require 'package)
      (package-initialize)
      (jetpacs-emacs-init--log "elpa initialized: %d package dir(s)"
                               (length package-alist)))
  (error (jetpacs-emacs-init--log "elpa stage FAILED: %s"
                                  (error-message-string err))))

(condition-case err
    (if (require 'glasspane nil t)
        (progn
          (jetpacs-emacs-init--log "glasspane registered (vulpea=%s org-srs=%s)"
                                   (featurep 'vulpea) (featurep 'org-srs))
          ;; Dev/in-tree installs never appear in the app store, so the
          ;; managed-config seeding is the HOST's explicit opt-in
          ;; (glasspane-config.el's own contract: "dev first-boot
          ;; seeding is manual").  This harness IS the dev host.
          ;; ensure = write-once then load-only; user edits survive.
          (glasspane-config-ensure)
          (jetpacs-emacs-init--log
           "glasspane config ensured: %d capture template(s), notes=%s"
           (length (bound-and-true-p org-capture-templates))
           (bound-and-true-p org-default-notes-file)))
      (jetpacs-emacs-init--log "glasspane not on load-path -- skipped"))
  (error (jetpacs-emacs-init--log "glasspane stage FAILED: %s"
                                  (error-message-string err))))

;;;; Stage 5: connect -- the KAT pairing every smoke in this tree uses,
;;;; with a retry timer for the boot race (Emacs can start before the
;;;; Companion app's listener binds 127.0.0.1:8765, and the reverse --
;;;; the Companion opened by hand afterwards -- needs the same retry).
;;;;
;;;; `jetpacs-connect' -> `ebp-connect' dials with `make-network-process'
;;;; WITHOUT :nowait, so a not-yet-listening port signals HERE, inside
;;;; the call; that signal is what the retry loop reschedules on.  A
;;;; socket that opens but never reaches READY is NOT covered by this
;;;; loop and never will be -- that is a live session sitting in
;;;; SYNCING, not a failed dial, and the right diagnostic for it is
;;;; M-x jetpacs-emacs-init-report.

(defvar jetpacs-emacs-init-retry-interval 3
  "Seconds between Companion dial attempts.")

(defvar jetpacs-emacs-init-retry-max 20
  "Attempts before giving up and waiting for a manual retry.
See `jetpacs-emacs-init-connect'.  At the default interval this is 60s.")

(defun jetpacs-emacs-init--session-owned-p ()
  "Non-nil when SOMETHING already owns the single Companion session.
The daily driver loaded earlier in init.el (docs/ONBOARDING-device.md's
/sdcard flow) attaches its own client, and `jetpacs-attach' errors on a
second live one -- so this harness must not race it.  Checked on the
internal `jetpacs--client' rather than `jetpacs-connected-p' on purpose:
a client that is merely SYNCING is still an owner, and the public
predicate answers nil for it."
  (and (boundp 'jetpacs--client)
       (symbol-value 'jetpacs--client)
       t))

(defun jetpacs-emacs-init--on-ready (_client)
  "READY: push the Files app so the deployed py dir is on screen."
  (jetpacs-emacs-init--log "session READY -- pushing %s" jetpacs-files-owner)
  (condition-case err
      (progn (jetpacs-shell-push jetpacs-files-owner)
             (jetpacs-emacs-init--log "Files pushed; onboarding connect done"))
    (error (jetpacs-emacs-init--log "Files push FAILED: %s"
                                    (error-message-string err)))))

(defun jetpacs-emacs-init--connect-1 ()
  "One dial attempt.
Signals on a synchronous connect failure (the Companion not listening
yet) -- callers retry on that signal."
  (jetpacs-connect
   "127.0.0.1" 8765
   :client-name "device-emacs" :client-version "30.1"
   :pairing-id "101112131415161718191a1b1c1d1e1f"
   :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
   :wants '("editor.sync" "surfaces.dialog" "theme")
   :receipt-file (expand-file-name "jetpacs-receipts.sqlite"
                                   user-emacs-directory)
   :ready-function #'jetpacs-emacs-init--on-ready))

(defun jetpacs-emacs-init-connect (&optional attempt)
  "Dial the Companion, retrying on a refused connection.
Retries every `jetpacs-emacs-init-retry-interval' seconds, up to
`jetpacs-emacs-init-retry-max' attempts.  ATTEMPT is the zero-based
retry counter and is supplied by the timer.  Safe to call by hand at
any time; a no-op when a session is already owned."
  (interactive)
  (cond
   ((not (fboundp 'jetpacs-connect))
    (jetpacs-emacs-init--log
     "jetpacs-connect unavailable (elisp tree/requires stage failed) \
-- nothing to dial"))
   ((jetpacs-emacs-init--session-owned-p)
    (jetpacs-emacs-init--log
     "a client is already attached (connected=%s) -- not dialing"
     (and (fboundp 'jetpacs-connected-p) (jetpacs-connected-p))))
   (t
    (condition-case err
        (progn (jetpacs-emacs-init--connect-1)
               (jetpacs-emacs-init--log
                "dial attempt %d: socket opened, awaiting READY"
                (1+ (or attempt 0))))
      (error
       (if (>= (or attempt 0) jetpacs-emacs-init-retry-max)
           (jetpacs-emacs-init--log
            "Companion not reachable after %d attempts (%s) -- open the \
EBP Companion app, then M-x jetpacs-emacs-init-connect"
            (1+ (or attempt 0)) (error-message-string err))
         (when (zerop (or attempt 0))
           (jetpacs-emacs-init--log
            "Companion not up yet (%s); retrying every %ds for up to %ds..."
            (error-message-string err) jetpacs-emacs-init-retry-interval
            (* jetpacs-emacs-init-retry-interval
               jetpacs-emacs-init-retry-max)))
         (run-at-time jetpacs-emacs-init-retry-interval nil
                      #'jetpacs-emacs-init-connect (1+ (or attempt 0)))))))))

(defun jetpacs-emacs-init-report ()
  "Dump current onboarding state to *Messages*.
The manual fallback diagnostic when the breadcrumb trail alone is not
enough."
  (interactive)
  (jetpacs-emacs-init--log
   "report: elisp-ready=%s owned=%s connected=%s pylsp=%s \
exec-path-has-termux=%s path-has-termux=%s files-roots=%S"
   jetpacs-emacs-init--elisp-ready
   (jetpacs-emacs-init--session-owned-p)
   (and (fboundp 'jetpacs-connected-p) (jetpacs-connected-p))
   (executable-find "pylsp")
   (and (member jetpacs-emacs-init-termux-bin exec-path) t)
   (and (member (directory-file-name jetpacs-emacs-init-termux-bin)
                (jetpacs-emacs-init--path-entries))
        t)
   (and (boundp 'jetpacs-files-roots) jetpacs-files-roots)))

(defun jetpacs-emacs-init--boot ()
  "Auto-dial, demoted so a Companion that never comes up costs nothing."
  (with-demoted-errors "jetpacs-emacs-init: unexpected error: %S"
    (jetpacs-emacs-init-connect)))

;; A NAMED function, not a lambda: `add-hook' can then dedupe, so
;; reloading this file (M-x load-file while debugging on the tablet)
;; does not stack a second copy.  And when the file is reloaded AFTER
;; startup, `after-init-hook' has already run and will never fire again
;; -- so dial straight away in that case instead of silently doing
;; nothing, which is what a bare `add-hook' would have done.
(if after-init-time
    (jetpacs-emacs-init--boot)
  (add-hook 'after-init-hook #'jetpacs-emacs-init--boot))

(provide 'jetpacs-onboard-init)
;;; emacs-init.el ends here
