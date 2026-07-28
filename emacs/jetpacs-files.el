;;; jetpacs-files.el --- Sandboxed file browsing on the device (JA-6) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-6 F1 of docs/PLAN-jetpacs-apps.md: the files floor.  This phase
;; lands the effective root set (configuration plus the /sdcard probe),
;; the dired card skin with a row cap, and the three browse verbs —
;; `jetpacs.files.cd', `jetpacs.files.open', `jetpacs.files.refresh'.
;; Later JA-6 phases add the grep scanner (jetpacs-async), the five
;; file ops, the plain value+on_save editor, and the launcher.
;;
;; The security shape, stated once: RENDERING IS NOT THE BOUNDARY,
;; ACTING IS.  Cards carry raw absolute paths in `:args' because a
;; descriptor is just a description; every path that comes BACK over
;; the wire re-enters through `jetpacs-check-path' (the floor guard
;; this rung shares with jetpacs-org — JA-4 audit P1-7 is why it lives
;; on the floor), which rejects remote names before any stat, resolves
;; symlinks on both sides, and compares path components.  A dired
;; buffer for a directory outside the roots still renders — Emacs is
;; showing it, so the device may see it — but every tap on it answers
;; `rejected'.
;;
;; Two module-local bounds protect the wire and the CPU: the row cap
;; (`jetpacs-files-max-rows') bounds what one snapshot carries, and the
;; scan cap (`jetpacs-files-scan-cap') bounds how far the listing walk
;; reads at all, JC-2's bounded-scan lesson — never collect everything
;; and truncate at render.
;;
;; File names are user data: display strings pass through
;; `jetpacs-scalar-text' (an undecodable name must not make the root
;; unpushable — the JA-3 lesson), and a path that cannot round-trip the
;; wire intact renders as an INERT row rather than a tappable lie,
;; because `:args' is opaque to the shell's walkers and a raw-byte
;; string there reaches `json-serialize' and takes down the push.

;;; Code:

(require 'cl-lib)
(require 'dired)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-chrome)
(require 'jetpacs-navigate)

;;;; Configuration

(defconst jetpacs-files-owner "jetpacs.files"
  "Owner string for the files surface.
A permanent wire identifier under the base-reserved `jetpacs.' prefix
(R1); never per-session.")

(defcustom jetpacs-files-roots
  (delq nil (list user-emacs-directory
                  (and (boundp 'org-directory) org-directory)
                  "~/"))
  "Directories the files browser is confined to, raw.
Navigation, opening, and (in later phases) every file operation are
refused outside these — `jetpacs-check-path' is the boundary, and it
filters and truenames these entries itself, so remote or dangling
entries are inert rather than harmful.  The /sdcard probe extends this
set at runtime without mutating it; see `jetpacs-files--roots'."
  :type '(repeat directory) :group 'jetpacs)

(defcustom jetpacs-files-default-dir "~/"
  "Directory the files view lands in.
Must lie inside `jetpacs-files-roots', or the view degrades to an
explanatory empty state."
  :type 'directory :group 'jetpacs)

(defcustom jetpacs-files-shared-storage 'auto
  "How the browser exposes Android shared storage (/sdcard).
Emacs's HOME on Android is a private per-app sandbox, so /sdcard is
unreachable from the configured roots even though the rest of the
device lives there.  `auto' probes the usual locations once and, when
one is accessible, adds it to the EFFECTIVE root set and offers a
landing shortcut; a string names an explicit directory instead; nil
disables both.  Access still depends on Emacs holding the storage
permission — without it no candidate is accessible and the feature
degrades silently."
  :type '(choice (const :tag "Auto-detect /sdcard" auto)
                 (const :tag "Disabled" nil)
                 (directory :tag "Explicit path"))
  :group 'jetpacs)

(defcustom jetpacs-files-max-rows 300
  "Ceiling on entry rows one directory snapshot renders.
Beyond it a caption reports how many entries were not shown.  The cap
protects the SPEC 4.5 aggregates (a card is several nodes), not the
scan — that is `jetpacs-files-scan-cap'."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-files-scan-cap 2000
  "Ceiling on directory entries the listing walk reads at all.
Past it the walk STOPS — JC-2's bounded-scan lesson: a cap that only
truncates at render time still paid to collect and stat everything."
  :type 'integer :group 'jetpacs)

;;;; State

(defvar jetpacs-files--dir nil
  "Directory the files view is showing (a truename), or nil = landing.
Written only by `jetpacs.files.cd' after the guard has passed; there is
one files surface under D1, so one variable is the whole state.")

(defvar jetpacs-files--shared-dir 'unset
  "Memoized `jetpacs-files-shared-dir' result, or the `unset' sentinel.")

;;;; The effective root set (config + the /sdcard probe)

(defun jetpacs-files--detect-shared-dir ()
  "Detect the primary shared-storage directory, or nil.
Honours `jetpacs-files-shared-storage'.  Candidates are local literals,
so probing them stats nothing remote."
  (pcase jetpacs-files-shared-storage
    ('nil nil)
    ((and (pred stringp) dir)
     (and (file-accessible-directory-p dir) (file-name-as-directory dir)))
    (_
     (cl-some (lambda (d)
                (and d (file-accessible-directory-p d)
                     (file-name-as-directory d)))
              (list (getenv "EXTERNAL_STORAGE")
                    "/sdcard"
                    "/storage/emulated/0"
                    "/storage/self/primary")))))

(defun jetpacs-files-shared-dir ()
  "The shared-storage directory the browser exposes, or nil.
Probed once.  Unlike the poc this does NOT mutate `jetpacs-files-roots'
— the widened sandbox lives in `jetpacs-files--roots', so disabling
`jetpacs-files-shared-storage' and re-probing (set
`jetpacs-files--shared-dir' to `unset') genuinely narrows it back."
  (when (eq jetpacs-files--shared-dir 'unset)
    (setq jetpacs-files--shared-dir (jetpacs-files--detect-shared-dir)))
  jetpacs-files--shared-dir)

(defun jetpacs-files--roots ()
  "The effective allowlist: configuration plus the probed shared dir.
Raw — `jetpacs-check-path' filters and truenames it."
  (append jetpacs-files-roots
          (and-let* ((shared (jetpacs-files-shared-dir))) (list shared))))

(defun jetpacs-files--check (path &optional require)
  "PATH through the floor guard against the effective roots.
REQUIRE as in `jetpacs-check-path' (default `readable')."
  (jetpacs-check-path path (jetpacs-files--roots)
                      :require (or require 'readable)))

(defun jetpacs-files--current-dir ()
  "The directory the view shows — the cd state or the landing."
  (or jetpacs-files--dir (expand-file-name jetpacs-files-default-dir)))

;;;; The dired card skin

(defun jetpacs-files--wire-safe-p (s)
  "Non-nil when string S crosses the wire byte-identical.
`jetpacs-scalar-text' replaces raw bytes and lone surrogates; a path it
would alter cannot be carried in `:args' and round-tripped faithfully."
  (equal (jetpacs-scalar-text s) s))

(defun jetpacs-files--entry-row (path dirp)
  "One tappable card for PATH; DIRP non-nil renders the folder form.
A wire-unsafe PATH renders inert: its name is shown (sanitized), but no
action carries it — see the Commentary."
  (let* ((name (file-name-nondirectory (directory-file-name path)))
         (shown (jetpacs-scalar-text name))
         (safe (jetpacs-files--wire-safe-p path))
         (key (jetpacs-wire-id "f" path)))
    (if dirp
        (jetpacs-chrome-row shown
                            :icon "folder"
                            :subtitle (unless safe "unencodable name — desktop only")
                            :on-tap (and safe
                                         (jetpacs-action "jetpacs.files.cd"
                                                         :args (list :dir path)))
                            :key key)
      (let ((size (or (file-attribute-size (file-attributes path)) 0)))
        (jetpacs-chrome-row shown
                            :icon "description"
                            :subtitle (if safe (file-size-human-readable size)
                                        "unencodable name — desktop only")
                            :on-tap (and safe
                                         (jetpacs-action "jetpacs.files.open"
                                                         :args (list :path path)))
                            :key key)))))

(defun jetpacs-files--up-row (dir)
  "The \"..\" card for DIR's parent, or nil at the sandbox ceiling.
The parent must itself clear the guard — at a root's edge there is no
up, which is what makes the ceiling FELT rather than an error."
  (let ((parent (file-name-directory (directory-file-name dir))))
    (when parent
      (condition-case nil
          (let ((true (jetpacs-files--check parent 'directory)))
            ;; "/" is its own parent; never offer a no-op up.
            (unless (equal (file-name-as-directory true)
                           (file-name-as-directory (file-truename dir)))
              (jetpacs-chrome-row ".."
                                  :icon "arrow_upward"
                                  :on-tap (jetpacs-action "jetpacs.files.cd"
                                                          :args (list :dir parent))
                                  :key "files-up")))
        (jetpacs-path-refused nil)))))

(defun jetpacs-files--listing (buffer)
  "Paths listed in dired BUFFER, bounded: (PATHS . TRUNCATED-P).
Walks at most `jetpacs-files-scan-cap' entries and STOPS; `.' and `..'
are filtered by their local names, non-file lines yield nil and skip."
  (with-current-buffer buffer
    (let ((n 0) (paths '()) (truncated nil))
      (save-excursion
        (goto-char (point-min))
        (while (not (or (eobp) truncated))
          (let ((local (dired-get-filename 'no-dir t)))
            (when (and local (not (member local '("." ".."))))
              (if (>= n jetpacs-files-scan-cap)
                  (setq truncated t)
                (cl-incf n)
                (push (dired-get-filename nil t) paths))))
          (forward-line 1)))
      (cons (delq nil (nreverse paths)) truncated))))

(defun jetpacs-files--dired-cards (buffer)
  "The dired skin: BUFFER's listing as dirs-first cards, capped.
Registered for `dired-mode', so ANY dired buffer — the files view or
one reached through the buffer host — renders this way.  Returns a
list of nodes per the `jetpacs-render-buffer-functions' contract."
  (pcase-let ((`(,paths . ,truncated) (jetpacs-files--listing buffer)))
    (let ((dirs '()) (files '()))
      (dolist (p paths)
        (if (file-directory-p p) (push (cons p t) dirs) (push (cons p nil) files)))
      (let* ((by-name (lambda (a b) (string< (car a) (car b))))
             (sorted (append (sort dirs by-name) (sort files by-name)))
             (total (length sorted))
             (shown (if (> total jetpacs-files-max-rows)
                        (cl-subseq sorted 0 jetpacs-files-max-rows)
                      sorted))
             (up (jetpacs-files--up-row
                  (with-current-buffer buffer
                    (expand-file-name default-directory)))))
        (append
         (and up (list up))
         (cl-loop for (p . dirp) in shown
                  collect (jetpacs-files--entry-row p dirp))
         (when (> total (length shown))
           (list (jetpacs-text (format "+%d more not shown" (- total (length shown)))
                               :style "caption")))
         (when truncated
           (list (jetpacs-text (format "listing stopped at %d entries — use dired in Emacs for the rest"
                                       jetpacs-files-scan-cap)
                               :style "caption"))))))))

(jetpacs-render-buffer-register 'dired-mode #'jetpacs-files--dired-cards)

;;;; The browse view

(defun jetpacs-files--dired-buffer (true-dir)
  "A freshly-reverted dired buffer for TRUE-DIR (already validated)."
  (let ((buf (dired-noselect true-dir)))
    (with-current-buffer buf (revert-buffer nil t))
    buf))

(defun jetpacs-files--shared-row ()
  "The landing shortcut card into shared storage, or nil.
Only at the landing, only when the probe found something, and not when
the landing already IS the shared tree."
  (and-let* (((null jetpacs-files--dir))
             (shared (jetpacs-files-shared-dir))
             ((not (file-equal-p shared (jetpacs-files--current-dir)))))
    (jetpacs-chrome-row "Shared storage"
                        :icon "sd_storage"
                        :subtitle (abbreviate-file-name
                                   (directory-file-name shared))
                        :trailing (jetpacs-icon "chevron_right")
                        :on-tap (jetpacs-action "jetpacs.files.cd"
                                                :args (list :dir (directory-file-name shared)))
                        :key "files-shared")))

(defun jetpacs-files--body ()
  "The files view body: the current directory as cards, or a degrade.
Validation happens HERE too, not only in the cd handler, because the
landing configuration never went through a handler."
  (condition-case err
      (let* ((true (jetpacs-files--check (jetpacs-files--current-dir)
                                         'directory))
             (shared (jetpacs-files--shared-row))
             (cards (jetpacs-render-buffer (jetpacs-files--dired-buffer true))))
        (apply #'jetpacs-lazy-column
               (append
                (list (jetpacs-text (jetpacs-scalar-text
                                     (abbreviate-file-name true))
                                    :style "caption"))
                (and shared (list shared))
                cards)))
    (jetpacs-path-refused
     (jetpacs-empty-state :icon "info"
                          :title "Can't open folder"
                          :caption (format "refused: %s" (cadr err))))
    (error
     ;; A listing race (deleted underneath us, permission flip) degrades
     ;; in place; the chrome error screen is for builder BUGS.
     (jetpacs-empty-state :icon "info"
                          :title "Can't open folder"
                          :caption (format "error: %s" (jetpacs--error-label err))))))

(defun jetpacs-files--screen (_back)
  "The chrome root screen builder."
  (jetpacs-chrome-screen "Files" (jetpacs-files--body)
                         :on-refresh (jetpacs-action "jetpacs.files.refresh")))

;;;; Actions (decision D2: validate -> status now; effects that can
;;;; prompt or push run from the flow continuation)

(defun jetpacs-files--event-surface (params)
  "The surface this event should answer to — the originating one (D1)."
  (or (plist-get params :surface) (concat "app:" jetpacs-files-owner)))

(defun jetpacs-files--repush (surface)
  "Deferred re-push of SURFACE, flow identity kept."
  (jetpacs-flow-continue
   (lambda ()
     (condition-case err
         (jetpacs-shell-push surface)
       (error (message "jetpacs-files: push failed: %s"
                       (jetpacs--error-label err)))))))

(with-jetpacs-owner "jetpacs.files"

  (jetpacs-chrome-define-root jetpacs-files-owner "browser"
                              #'jetpacs-files--screen)

  (jetpacs-defaction "jetpacs.files.cd"
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params)))
        (condition-case err
            (let ((true (jetpacs-files--check (plist-get args :dir)
                                              'directory)))
              ;; The effect is synchronous (14.4); only the re-push defers.
              (setq jetpacs-files--dir (file-name-as-directory true))
              (jetpacs-files--repush surface)
              'accepted)
          (jetpacs-path-refused
           (jetpacs-shell-notify (format "Folder refused: %s" (cadr err))
                                 surface)
           'rejected)))))

  (jetpacs-defaction "jetpacs.files.open"
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params)))
        (condition-case err
            (let ((true (jetpacs-files--check (plist-get args :path))))
              (if (file-directory-p true)
                  ;; A directory path routes to cd semantics: the browse
                  ;; screen is the directory UI, and keeping dired
                  ;; buffers out of the drill host keeps one directory
                  ;; from holding the same literal node keys in two
                  ;; views of a surface.
                  (progn
                    (setq jetpacs-files--dir (file-name-as-directory true))
                    (jetpacs-files--repush surface))
                ;; Opening can PROMPT (large file, changed on disk), so
                ;; the whole effect lives in the flow continuation where
                ;; JC-4a bridges prompts to the device instead of a
                ;; minibuffer nobody is looking at.
                (jetpacs-flow-continue
                 (lambda ()
                   (condition-case e2
                       ;; Device-originated opens apply only :safe
                       ;; file-local variables — the desktop query UX has
                       ;; no device counterpart; an explicit nil stays nil.
                       (let* ((enable-local-variables
                               (and enable-local-variables :safe))
                              (buf (find-file-noselect true)))
                         (jetpacs-navigate-buffer buf surface))
                     (error
                      (jetpacs-shell-notify "Could not open that file" surface)
                      (message "jetpacs-files: open failed: %s"
                               (jetpacs--error-label e2)))))))
              'accepted)
          (jetpacs-path-refused
           (jetpacs-shell-notify (format "File refused: %s" (cadr err))
                                 surface)
           'rejected)))))

  (jetpacs-defaction "jetpacs.files.refresh"
    (lambda (_args params)
      (jetpacs-files--repush (jetpacs-files--event-surface params))
      'accepted)))

;;;; Entry point and unload hygiene

(defun jetpacs-files ()
  "Push the files browser to the device now, loudly."
  (interactive)
  (jetpacs-client-or-error)
  (jetpacs-shell-push jetpacs-files-owner))

(defun jetpacs-files-unload-function ()
  "Unload hygiene: the skin registration and the owner's surfaces."
  (setq jetpacs-render-buffer-functions
        (assq-delete-all 'dired-mode jetpacs-render-buffer-functions))
  (jetpacs-teardown-owner jetpacs-files-owner)
  nil)

(provide 'jetpacs-files)
;;; jetpacs-files.el ends here
