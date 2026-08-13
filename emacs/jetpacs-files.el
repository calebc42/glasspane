;;; jetpacs-files.el --- Sandboxed file browsing on the device (JA-6) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-6 F1+F2 of docs/PLAN-jetpacs-apps.md: the files floor and the
;; content search.  F1 lands the effective root set (configuration plus
;; the /sdcard probe), the dired card skin with a row cap, and the three
;; browse verbs — `jetpacs.files.cd', `jetpacs.files.open',
;; `jetpacs.files.refresh'.  F2 lands `jetpacs.files.grep': a
;; `text_input' `:on-submit' on the browse screen (no dialog, no D2
;; exposure), a bounded CHUNKED scan running as a `jetpacs-async'
;; loader, and a pushed results screen — leaving the results screen
;; evicts the async entry, which CANCELS an in-flight scan; a new query
;; is a new key, so supersession and teardown both come free from the
;; async cache's sweep.  Later JA-6 phases add the five file ops, the
;; plain value+on_save editor, and the launcher.
;;
;; The security shape, stated once: RENDERING IS NOT THE BOUNDARY,
;; ACTING IS.  Cards carry raw absolute paths in `:args' because a
;; descriptor is just a description; every path that comes BACK over
;; the wire re-enters through `ebp-check-path' (the shared path guard
;; this rung and jetpacs-org both require — JA-4 audit P1-7 is why it
;; is shared), which rejects remote names before any stat, resolves
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
(require 'ebp-sync)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
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
refused outside these — `ebp-check-path' is the boundary, and it
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

(defcustom jetpacs-files-max-bytes (* 256 1024)
  "Upper bound on files the plain editor will host, in bytes.
The EFFECTIVE ceiling is usually lower: `jetpacs-files--editor-cap'
derives it from the session's wire limits (the seed rides the surface
push, and the save must come back as one event — B11).  This custom
bound is the absolute ceiling a generous Companion cannot raise.
Larger files open read-only through the buffer host."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-files-sync-editor t
  "When non-nil, eligible files open in the synchronized SPEC 19 editor.
The device then edits a REAL Emacs buffer: keystrokes arrive as
splices, the buffer's own completions, flymake diagnostics, font-lock
colours and eldoc ride back, and a save writes the buffer.  Set to nil
to keep the plain seed-and-save editor, which every file that does not
qualify — oversize, binary, or opened while a modified desktop buffer
holds it — still gets."
  :type 'boolean :group 'jetpacs)

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

(defvar jetpacs-files--edit nil
  "The file the editor screen shows:
\(:path TRUENAME :seed S :mtime T :coding C) plus, on the SYNCHRONIZED
rung, (:document D :editor-id E :buffer B).  C is the coding system
the file was READ with — the save writes it back in the same one.
Written by `jetpacs-files--edit-open' after eligibility passed, and by
a successful save (fresh seed and stamp, everything else carried
forward).  The screen BUILDER reads only this — never the disk — so a
re-push while editing re-renders the same seed, and what actually shows
is the Companion's SPEC 13.6 draft: the user's typing.  Under sync the
seed is a RECONNECT seed only (SPEC 19.3: `value' seeds a NEW session
and a later snapshot MUST NOT replace live text).")

(defvar jetpacs-files-after-save-hook nil
  "Run with the saved truename after `jetpacs.files.save' lands on disk.
The first JA-6 app seam: org affordances (cache invalidation, outline
refresh) attach here rather than being wired into base.")

;;;; The editor app seams
;;
;; Base renders a PLAIN editor; everything file-type-shaped lives above
;; it, attached through these four seams (the poc's names, kept so the
;; org port recognizes its own extension points).  All four run inside
;; the screen BUILDER: a seam function that signals costs that screen —
;; the chrome error card — and nothing else, which is the E1b
;; containment and needs no extra isolation here.

(defvar jetpacs-files-editor-body-functions nil
  "Abnormal hook: functions of (PATH) that may REPLACE the editor body.
Run until one returns a node, which becomes the edit screen's body in
place of the plain editor — the seam the org render skin (JA-5) claims
.org files through.  Returning nil passes.")

(defvar jetpacs-files-editor-actions-functions nil
  "Abnormal hook: functions of (PATH) returning top-bar action nodes.
All results are appended into the edit screen's `:actions' slot — the
poc used this for the HTML \"open rendered\" and org \"Outline\"
buttons.")

(defvar jetpacs-files-editor-toolbar-function nil
  "Function of (PATH) returning the editor's `:toolbar', or nil.
A registered toolbar id string or a list of `jetpacs-toolbar-item's;
validation rides `jetpacs-editor'.  A `:command' op requires a
synchronized `:document', which the SYNCHRONIZED rung has — and since
R6 `edit.command' has a real handler (jetpacs-emacs-ui.el: the command
runs at the device's point/region, gated by
`jetpacs-emacs-ui-command-predicate'), so `:command' items ship.
`:snippet' and `:line' never contact Emacs and work on both rungs.")

(defvar jetpacs-files-editor-fab-function nil
  "Function of (PATH) returning the edit screen's FAB node, or nil.
The poc's org add-heading FAB attaches here.")

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
Raw — `ebp-check-path' filters and truenames it."
  (append jetpacs-files-roots
          (and-let* ((shared (jetpacs-files-shared-dir))) (list shared))))

(cl-defun jetpacs-files--check (path &optional (require 'readable))
  "PATH through the shared path guard against the effective roots.
REQUIRE as in `ebp-check-path'; the default applies only when the
argument is OMITTED — an explicit nil means containment-only, and an
`(or ... \\='readable)' here once silently turned delete's nil into a
readability stat."
  (ebp-check-path path (jetpacs-files--roots) :require require))

(defun jetpacs-files--current-dir ()
  "The directory the view shows — the cd state or the landing."
  (or jetpacs-files--dir (expand-file-name jetpacs-files-default-dir)))

;;;; The dired card skin

(defun jetpacs-files--wire-safe-p (s)
  "Non-nil when string S crosses the wire byte-identical.
`jetpacs-scalar-text' replaces raw bytes and lone surrogates; a path it
would alter cannot be carried in `:args' and round-tripped faithfully."
  (equal (jetpacs-scalar-text s) s))

(defun jetpacs-files--entry-delete-button (path shown dirp)
  "The trailing delete affordance for PATH (displayed as SHOWN).
The descriptor carries SPEC 14.1 `:confirm', so the COMPANION shows the
native confirmation before the event exists — the handler never
prompts, and delete keeps working without the dialog capability.  DIRP
changes the wording: directory deletion is recursive and the user
confirms that, not a euphemism."
  (jetpacs-icon-button
   "delete"
   (jetpacs-action "jetpacs.files.delete"
                   :args (list :path path)
                   :confirm (if dirp
                                (format "Delete %s and everything in it?" shown)
                              (format "Delete %s?" shown)))
   :content-description "Delete"))

(defun jetpacs-files--entry-row (path dirp)
  "One tappable card for PATH; DIRP non-nil renders the folder form.
Tap opens/enters; long-press raises the ops menu; the trailing button
deletes (Companion-confirmed).  A wire-unsafe PATH renders inert: its
name is shown (sanitized), but no action carries it — see the
Commentary."
  (let* ((name (file-name-nondirectory (directory-file-name path)))
         (shown (jetpacs-scalar-text name))
         (safe (jetpacs-files--wire-safe-p path))
         (key (jetpacs-wire-id "f" path))
         (long-tap (and safe
                        (jetpacs-action "jetpacs.files.menu"
                                        :args (list :path path))))
         (trash (and safe
                     (jetpacs-files--entry-delete-button path shown dirp))))
    (if dirp
        (jetpacs-chrome-row shown
                            :icon "folder"
                            :subtitle (unless safe "unencodable name — desktop only")
                            :on-tap (and safe
                                         (jetpacs-action "jetpacs.files.cd"
                                                         :args (list :dir path)))
                            :on-long-tap long-tap
                            :trailing trash
                            :key key)
      (let ((size (or (file-attribute-size (file-attributes path)) 0)))
        (jetpacs-chrome-row shown
                            :icon "description"
                            :subtitle (if safe (file-size-human-readable size)
                                        "unencodable name — desktop only")
                            :on-tap (and safe
                                         (jetpacs-action "jetpacs.files.open"
                                                         :args (list :path path)))
                            :on-long-tap long-tap
                            :trailing trash
                            :key key)))))

(defun jetpacs-files--up-row (dir)
  "The \"..\" card for DIR's parent, or nil at the sandbox ceiling.
The parent must itself clear the guard — at a root's edge there is no
up, which is what makes the ceiling FELT rather than an error.  A
parent the wire cannot carry gets no row either (the Commentary's
`:args' rule): the row's whole point is its `:args', so unlike an
entry row there is nothing honest to render inert — absence IS the
ceiling behavior."
  (let ((parent (file-name-directory (directory-file-name dir))))
    (when (and parent (jetpacs-files--wire-safe-p parent))
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
        (ebp-path-refused nil)))))

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
Only at the landing, only when the probe found something, not when
the landing already IS the shared tree, and never for a path the wire
cannot carry (the Commentary's `:args' rule)."
  (and-let* (((null jetpacs-files--dir))
             (shared (jetpacs-files-shared-dir))
             ((jetpacs-files--wire-safe-p (directory-file-name shared)))
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
                                    :style "caption")
                      ;; The F2 entry point: SPEC 14.3 injects the
                      ;; submitted text as `value' into the action's
                      ;; args — no dialog, no D2 exposure.  Stable id,
                      ;; no clear-on-submit: 13.6 keeps the draft, so
                      ;; refining a search is an edit, not a retype.
                      (jetpacs-text-input
                       (jetpacs-claim-node-id "files-grep-input")
                       :hint "Search contents — Enter runs"
                       :single-line t
                       :on-submit (jetpacs-action "jetpacs.files.grep")))
                (and shared (list shared))
                cards)))
    (ebp-path-refused
     (jetpacs-empty-state :icon "info"
                          :title "Can't open folder"
                          :caption (format "refused: %s" (cadr err))))
    (error
     ;; A listing race (deleted underneath us, permission flip) degrades
     ;; in place; the chrome error screen is for builder BUGS.
     (jetpacs-empty-state :icon "info"
                          :title "Can't open folder"
                          :caption (format "error: %s" (jetpacs-error-label err))))))

(declare-function jetpacs-launcher-button "jetpacs-launcher" ())

(defun jetpacs-files--screen (_back)
  "The chrome root screen builder."
  (jetpacs-chrome-screen "Files" (jetpacs-files--body)
                         :actions (append
                                   (list (jetpacs-icon-button
                                          "add"
                                          (jetpacs-action "jetpacs.files.new")
                                          :content-description
                                          "New file or folder"))
                                   ;; Soft coupling: the switcher rides
                                   ;; along when its module is loaded.
                                   (when (featurep 'jetpacs-launcher)
                                     (list (jetpacs-launcher-button))))
                         :on-refresh (jetpacs-action "jetpacs.files.refresh")))

;;;; Content search (F2)
;;
;; A pure-elisp scan: portable (no external grep on Android) and
;; bounded four ways — hit cap, examined-file cap, per-file size cap,
;; and a NUL-in-the-first-KiB binary guard — plus an exclude list for
;; VCS/build trees.  The QUERY IS A LITERAL, never compiled into a
;; regexp: SPEC amendment #137's lesson is that an exposed pattern
;; grammar is received interpretation, and a C-level regexp match never
;; yields to timers.  The walk is iterative and CHUNKED on timers (the
;; poc enumerated the whole tree before its cap even started counting),
;; and it NEVER crosses a symlink — the guard validated the start
;; directory, and a link out of the sandbox must not let the scan read
;; what `jetpacs.files.open' would refuse to open.

(defcustom jetpacs-files-grep-max-hits 200
  "Content search stops after this many matching lines."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-files-grep-max-files 2000
  "Content search stops after examining this many files.
Search from a subdirectory rather than a root to keep scans quick."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-files-grep-max-file-bytes (* 1024 1024)
  "Files larger than this are skipped by the content search."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-files-grep-max-query-chars 200
  "Ceiling on the submitted query's length.
The query is peer content; its interpretation cost is bounded before
any work happens (the SPEC #138 discipline), independent of the
transport's own message limits."
  :type 'integer :group 'jetpacs)

(defcustom jetpacs-files-grep-exclude-dirs
  '(".git" ".hg" ".svn" "node_modules" ".gradle" "build" "dist" "target")
  "Directory names the content search never descends into."
  :type '(repeat string) :group 'jetpacs)

(defcustom jetpacs-files-grep-items-per-tick 25
  "Queue items (files or directories) one timer tick processes.
The chunk size trades scan latency against event-loop stalls; each tick
ends by re-arming a short timer, so the socket filter and the dispatch
pump keep breathing under a large tree."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-files--grep-request nil
  "The search the results screen shows: (:query Q :dir D), or nil.
Written only by `jetpacs.files.grep' after the guard has passed.")

(defun jetpacs-files--grep-file (file query hits-left)
  "Matching lines of FILE for literal QUERY, at most HITS-LEFT.
Case-insensitive, one hit per line, each hit (FILE LINE TEXT) with TEXT
capped at 200 chars.  A NUL in the first KiB marks a binary: no line
of it is worth showing, and its \"lines\" can be enormous."
  (when (> hits-left 0)
    (with-temp-buffer
      (when (ignore-errors (insert-file-contents file) t)
        (goto-char (point-min))
        (unless (search-forward "\0" (min 1024 (point-max)) t)
          (goto-char (point-min))
          (let ((case-fold-search t)
                (out '()))
            (while (and (> hits-left 0) (search-forward query nil t))
              (push (list file (line-number-at-pos)
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (min (line-end-position)
                                (+ (line-beginning-position) 200))))
                    out)
              (cl-decf hits-left)
              (end-of-line))
            (nreverse out)))))))

(defun jetpacs-files--grep-start (dir query resolve)
  "Begin the chunked scan of DIR for literal QUERY; RESOLVE gets the result.
The `jetpacs-async' loader body: returns a cancel thunk, calls RESOLVE
at most once with (:query Q :dir D :hits ((FILE LINE TEXT)...)
:truncated BOOL), hits sorted by file then line.  Each tick processes
`jetpacs-files-grep-items-per-tick' queue items and re-arms a short
timer, so a large tree never wedges the event loop; the cancel thunk
kills the timer, so an evicted entry (screen left, query superseded,
owner torn down) stops paying immediately."
  (let ((queue (ignore-errors
                 (directory-files dir t directory-files-no-dot-files-regexp t)))
        (files 0) (hits '()) (nhits 0)
        (truncated nil) (timer nil) (dead nil))
    (cl-labels
        ((finish ()
           (unless dead
             (setq dead t)
             (funcall resolve
                      (list :query query :dir dir
                            :hits (sort (nreverse hits)
                                        (lambda (a b)
                                          (if (equal (car a) (car b))
                                              (< (cadr a) (cadr b))
                                            (string< (car a) (car b)))))
                            :truncated truncated))))
         (step ()
           (setq timer nil)
           (unless dead
             (let ((budget jetpacs-files-grep-items-per-tick))
               (while (and queue (> budget 0) (not truncated))
                 (cl-decf budget)
                 (let ((path (pop queue)))
                   (cond
                    ;; Never cross a link — see the section comment.
                    ((file-symlink-p path) nil)
                    ((file-directory-p path)
                     (unless (member (file-name-nondirectory
                                      (directory-file-name path))
                                     jetpacs-files-grep-exclude-dirs)
                       (setq queue
                             (nconc queue
                                    (ignore-errors
                                      (directory-files
                                       path t
                                       directory-files-no-dot-files-regexp t))))))
                    (t
                     (cl-incf files)
                     (cond
                      ((> files jetpacs-files-grep-max-files)
                       (setq truncated t))
                      ;; Backups and auto-saves are stale copies: they
                      ;; double every hit.
                      ((or (backup-file-name-p path)
                           (auto-save-file-name-p
                            (file-name-nondirectory path)))
                       nil)
                      ;; A FIFO/socket/device blocks in open(2) FOREVER
                      ;; inside a non-yielding tick — no timer can
                      ;; interrupt it.  Symlinks were already dropped at
                      ;; the top, so the follow in `file-regular-p' is
                      ;; moot here.
                      ((not (file-regular-p path)) nil)
                      ((not (let ((size (file-attribute-size
                                         (file-attributes path))))
                              (and size
                                   (<= size jetpacs-files-grep-max-file-bytes))))
                       nil)
                      ((not (file-readable-p path)) nil)
                      (t
                       (dolist (hit (jetpacs-files--grep-file
                                     path query
                                     (- jetpacs-files-grep-max-hits nhits)))
                         (push hit hits)
                         (cl-incf nhits))
                       (when (>= nhits jetpacs-files-grep-max-hits)
                         (setq truncated t))))))))
               (if (or truncated (null queue))
                   (finish)
                 (setq timer (run-at-time 0.01 nil #'step)))))))
      (setq timer (run-at-time 0.01 nil #'step))
      (lambda ()
        (setq dead t)
        (when (timerp timer)
          (cancel-timer timer)
          (setq timer nil))))))

(defun jetpacs-files--grep-hit-card (dir hit)
  "One result card for HIT (FILE LINE TEXT), relative to DIR.
The tap re-enters through `jetpacs.files.open', so the sandbox guard
runs again on arrival; a wire-unsafe FILE renders inert (F1's rule)."
  (pcase-let* ((`(,file ,line ,text) hit)
               (name (jetpacs-scalar-text (file-name-nondirectory file)))
               (rel (file-name-directory (file-relative-name file dir)))
               (safe (jetpacs-files--wire-safe-p file))
               (snippet (jetpacs-scalar-text (string-trim text))))
    (jetpacs-with-attrs
     (jetpacs-card
      (list (jetpacs-column
             (apply #'jetpacs-row
                    (append
                     (list (jetpacs-with-attrs
                            (apply #'jetpacs-column
                                   (append
                                    (list (jetpacs-text name))
                                    (when (and rel (not (string-empty-p rel)))
                                      (list (jetpacs-text
                                             (jetpacs-scalar-text rel)
                                             :style "caption")))
                                    (list :spacing 2)))
                            :weight 1))
                     (list (jetpacs-text (format "L%d" line) :style "caption"))
                     (list :align "center" :spacing 12)))
             ;; 16.2: `rich_text' is not Core; degrade the mono snippet.
             (if (jetpacs-node-advertised-p "rich_text")
                 (jetpacs-rich-text (list (jetpacs-span snippet :mono t)))
               (jetpacs-text snippet :style "caption"))
             :spacing 4))
      :on-tap (and safe
                   (jetpacs-action "jetpacs.files.open"
                                   :args (list :path file))))
     :key (jetpacs-wire-id "g" (format "%s:%d" file line)))))

(defun jetpacs-files--grep-cards (result)
  "The results body for a finished scan RESULT."
  (let ((query (plist-get result :query))
        (dir (plist-get result :dir))
        (hits (plist-get result :hits)))
    (if (null hits)
        (jetpacs-empty-state :icon "manage_search"
                             :title "No matches"
                             :caption (format "\"%s\" under %s"
                                              (jetpacs-scalar-text query)
                                              (jetpacs-scalar-text
                                               (abbreviate-file-name dir))))
      (apply #'jetpacs-lazy-column
             (jetpacs-text (format "%d matching line%s%s"
                                   (length hits)
                                   (if (= (length hits) 1) "" "s")
                                   (if (plist-get result :truncated)
                                       " — stopped early, narrow the search"
                                     ""))
                           :style "caption")
             (mapcar (lambda (hit) (jetpacs-files--grep-hit-card dir hit))
                     hits)))))

(defun jetpacs-files--grep-screen (back)
  "Builder for the pushed search-results screen.
Asks `jetpacs-async' for the scan keyed on (dir, query): the first build
starts the loader and shows progress, the completion re-pushes the
owner, the next build reads the cached result — and a build that stops
asking (back tapped, new query pushed) lets the sweep cancel the scan."
  (jetpacs-chrome-screen
   "Search"
   (let ((req jetpacs-files--grep-request))
     (if (null req)
         (jetpacs-empty-state :icon "info" :title "No search"
                              :caption "Submit a search from the browser")
       (let ((dir (plist-get req :dir))
             (query (plist-get req :query)))
         (pcase (jetpacs-async (list 'jetpacs-files-grep dir query)
                               (lambda (resolve _reject)
                                 (jetpacs-files--grep-start dir query resolve)))
           (`(error . ,e)
            (jetpacs-empty-state :icon "info" :title "Search failed"
                                 :caption e))
           (`(ready . ,result) (jetpacs-files--grep-cards result))
           (_ (jetpacs-column
               (jetpacs-progress)
               (jetpacs-text (format "Searching for \"%s\"…"
                                     (jetpacs-scalar-text query))
                             :style "caption")
               :spacing 8))))))
   :back back))


;;;; The editor (F4) — a three-rung ladder
;;
;; SYNCHRONIZED -> PLAIN -> READ VIEW, and the top rung is the DEFAULT
;; for files that qualify.  G4 (the editor<->buffer binding decision D-1
;; deferred) lands here: the device edits a real Emacs buffer through
;; `ebp-sync', so keystrokes are splices, the buffer's own completions,
;; flymake diagnostics, font-lock colours and eldoc ride back, and the
;; save writes the buffer.
;;
;; The PLAIN rung is not obsolete and is not a fallback for failure — it
;; is the honest answer for the files sync cannot host: the two bounds
;; `jetpacs-files--editor-cap' derives exist because the seed rides the
;; surface push and the save returns as ONE event, and NEITHER is true
;; under sync, where the seed is a reconnect seed and edits are deltas.
;; The governing bound there is `max_editor_bytes' (SPEC 19, amendment
;; #84), which is larger.  So a file between the two ceilings stays on
;; the plain editor rather than losing an editor entirely.
;;
;; An mtime stamp rides the save descriptor on both rungs, so a save
;; over a file that changed underneath answers `stale' instead of
;; clobbering it.  Files neither rung can host honestly fall back to the
;; read-only buffer host.

(defun jetpacs-files--editor-cap ()
  "Byte ceiling for a file the plain editor may host.
Two wire bounds gate a local editor: the seed rides the surface push
\(`max_frame_bytes', SHARED with every other screen in the multi_view),
and the save must come back as ONE `event.action'
\(`jetpacs-max-event-bytes' — B11; the Companion drops anything bigger
with only a local diagnostic).  JSON escaping can double the content
and the seed is not the frame's only tenant, so the ceiling is
\(min of both bounds - headroom) / 4 — on the minimum-conforming floor
\(262144) that is ~60 KiB, which covers the init.el use-case this rung
exists for, and it scales with a richer Companion.  Always bounded by
`jetpacs-files-max-bytes'; offline the custom cap alone (nothing can
push anyway)."
  (let* ((event (jetpacs-max-event-bytes))
         (frame (cdr (jetpacs-buffer-budgets)))
         (wire (cond ((and event frame) (min event frame))
                     (event event)
                     (frame frame))))
    (if wire
        (min jetpacs-files-max-bytes (max 1024 (/ (- wire 16384) 4)))
      jetpacs-files-max-bytes)))

(defun jetpacs-files--sync-cap (client)
  "Byte ceiling for a file the SYNCHRONIZED editor may host.
The §19 bound, not the plain editor's: `max_editor_bytes' (SPEC 19,
amendment #84 — REQUIRED when `editor.sync' is granted, at least 65536)
governs the document, and `ebp-client-edit-apply' already enforces it
locally on every splice with a synthetic 1201 `editor-too-large'.  The
plain rung's /4 JSON-escape division and its `max_event_bytes' term do
not apply: the seed is a reconnect seed and the save reads the buffer.
Still bounded by `jetpacs-files-max-bytes', the absolute ceiling a
generous Companion cannot raise."
  (let ((limit (plist-get (ebp-client-limits client) :max_editor_bytes)))
    (and limit (min jetpacs-files-max-bytes limit))))

(defun jetpacs-files--document-id (true)
  "The SPEC 19 document identifier for TRUE — EXTENSION-PRESERVING.
Deliberately NOT `jetpacs-wire-id', which appends the sha1 LAST: the
document id is what `ebp-complete--mode-for' matches against
`auto-mode-alist' to pick the shadow's major mode, so a hash-tailed id
silently downgrades every synced file to `fundamental-mode' and no
completions.  The hash keeps ids unique and path-free (SPEC 19.3
requires an Emacs-assigned id, never a raw Companion-supplied path);
`:' and `.' are legal SPEC 4.4 characters and the id begins alnum."
  (concat "doc:" (substring (sha1 true) 0 16)
          (or (file-name-extension true t) "")))

(defun jetpacs-files--syntax-for (true)
  "The SPEC 17.4 `syntax' language for TRUE, or nil.
First-paint only: once a buffer is attached, Emacs's own font-lock runs
arrive as `fontify.show' and WIN over the client tokenizer.  It still
matters — it is what colours the editor before the first push lands,
and the whole of it for a plain-rung file."
  (pcase (downcase (or (file-name-extension true) ""))
    ((or "el" "elc") "elisp")
    ("org" "org")
    ("py" "python")
    ("rs" "rust")
    ((or "sh" "bash") "shell")
    ((or "c" "h") "c")
    ((or "cc" "cpp" "hpp") "cpp")
    (_ nil)))

(defun jetpacs-files--mtime-stamp (path)
  "PATH's modification time as an opaque comparable string, or nil.
Microsecond textual form, compared by `equal' only and never parsed —
the same file state always yields the same string, and nil (the file
is gone) can never equal a stamp."
  (when-let* ((mt (file-attribute-modification-time
                   (file-attributes path))))
    (format-time-string "%s.%6N" mt)))

(defun jetpacs-files--synced-buffer (true)
  "The live buffer bound to TRUE's SPEC 19 editor session, or nil.
Nil is the PLAIN leg, where the frame's `value' is the whole content
and the save writes it.  Non-nil is the SYNCHRONIZED leg, where the
buffer is the authority and `value' is a mirror of it — every device
keystroke already arrived as an `edit.apply', so a save is a write, not
a transfer.  Keyed off the current edit record, so a save for some
other path never finds a session."
  (let ((req jetpacs-files--edit))
    (when (and req (equal (plist-get req :path) true))
      (when-let* ((client (jetpacs-client))
                  (doc (plist-get req :document))
                  (eid (plist-get req :editor-id)))
        (ebp-sync-buffer client doc eid)))))

(defun jetpacs-files--read-fallback (true surface reason)
  "Show TRUE through the buffer host; explain REASON when it surprises.
`binary' and `unencodable' stay quiet — a read view is simply what
those files get — but a text file refused for size or for unsaved
desktop edits would otherwise look broken."
  (pcase reason
    ('oversize
     (jetpacs-shell-notify "Too large to edit here — read-only" surface))
    ('desktop-modified
     (jetpacs-shell-notify "Unsaved desktop edits — read-only" surface)))
  (condition-case err
      ;; Device-originated opens apply only :safe file-local variables —
      ;; the desktop query UX has no device counterpart; an explicit nil
      ;; stays nil.
      (let* ((enable-local-variables (and enable-local-variables :safe))
             (buf (find-file-noselect true)))
        (jetpacs-navigate-buffer buf surface))
    (error
     (jetpacs-shell-notify "Could not open that file" surface)
     (message "jetpacs-files: open failed: %s"
              (jetpacs-error-label err)))))

(defun jetpacs-files--sync-cap-for (true)
  "The synchronized rung's byte ceiling for TRUE, or nil when it is off.
Nil means the ladder skips straight to the plain rung: the toggle is
off, no client is attached, `editor.sync' is not granted, this
Companion does not advertise the `editor' node, or it negotiated no
`max_editor_bytes'."
  (ignore true)
  (when-let* ((client (and jetpacs-files-sync-editor (jetpacs-client))))
    (and (jetpacs-granted-p "editor.sync" client)
         (jetpacs-node-advertised-p "editor" :app)
         (jetpacs-files--sync-cap client))))

(defun jetpacs-files--sync-attach (true)
  "Upgrade TRUE's already-recorded edit to the SYNCHRONIZED rung, or not.
NEVER SIGNALS.  The synchronized rung is an upgrade over an editor that
already works, so anything that goes wrong here degrades to the plain
one rather than costing the user the screen.

Runs from `jetpacs-files--edit-open' and NEVER from the screen builder:
`jetpacs-chrome--build' rebuilds the whole stack on every push, so an
attach in the builder would re-run its detach/erase/adopt on every
re-push — including the save handler's — and drop unflushed edits each
time.  Attaching BEFORE the push also lands the routing entry before
the Companion opens the session on node presence, so `edit.open' finds
a bound buffer and the annotation riders arm on the reseed."
  (condition-case err
      (let* ((doc (jetpacs-files--document-id true))
             ;; The editor id on the wire is the NODE id, because that is
             ;; what the Companion stamps into `edit.open'/`edit.delta'.
             ;; Minted here from the same base the builder claims, so the
             ;; routing key `ebp-sync-attach' registers is the key the
             ;; frames arrive under — a mismatch here is silent and total:
             ;; the session opens, the phone edits, and nothing ever
             ;; reaches the buffer.
             (eid (jetpacs-wire-id "fedit" true))
             ;; Device-originated opens apply only :safe file-local
             ;; variables — the same rule the read fallback applies.
             (buf (let ((enable-local-variables
                         (and enable-local-variables :safe)))
                    (find-file-noselect true)))
             (seed (with-current-buffer buf
                     ;; POC 1's prepare-real-buffer discipline: phone
                     ;; keystrokes must not litter #autosave# files —
                     ;; the phone's explicit Save owns persistence.
                     (setq-local buffer-auto-save-file-name nil)
                     ;; WIDEN, the same way the save at the other end
                     ;; does.  THIS LINE DECIDES WHAT THE §19 MIRROR
                     ;; MEANS, and every offset on the wire — the
                     ;; outbound `(1- beg)', diagnostics, fontify runs,
                     ;; the inbound splice — is a whole-DOCUMENT offset.
                     ;; Seeded from the accessible portion instead, the
                     ;; mirror was a fragment while the coordinates
                     ;; stayed absolute: not an edge case, a guaranteed
                     ;; shift of `(1- (point-min))' on every splice.
                     (save-restriction
                       (widen)
                       (buffer-substring-no-properties
                        (point-min) (point-max))))))
        ;; The BUFFER is the seed, not the disk: a visiting buffer with
        ;; unsaved desktop edits is exactly the case sync handles best,
        ;; and seeding from its own text is what makes the reseed a
        ;; no-op instead of a silent revert.  The gates below read the
        ;; same widened seed on purpose: a NUL or an unencodable char
        ;; hidden outside the restriction otherwise passed the check
        ;; that exists to keep it out of the round trip, and the widened
        ;; save then wrote exactly those bytes.
        (unless (or (string-search "\0" seed)
                    (not (jetpacs-files--wire-safe-p seed)))
          (ebp-sync-attach (jetpacs-client) doc eid buf)
          ;; Amendment #169 (R3), the author-time half of the sender-omit
          ;; rule: this editor presents in the files APP surface, so its
          ;; completion replies may carry `kind' exactly when the app
          ;; profile advertises the member-gating feature — evaluated
          ;; against the LIVE welcome (the bare predicate fails open
          ;; offline, which is the wrong direction for a sender MUST).
          (when (fboundp 'ebp-complete-set-editor-kinds)
            (ebp-complete-set-editor-kinds
             doc eid
             (and (jetpacs-client)
                  (jetpacs-feature-advertised-p
                   "editor.candidate_kind" :app))))
          (setq jetpacs-files--edit
                (list :path true :seed seed
                      :mtime (plist-get jetpacs-files--edit :mtime)
                      :coding (plist-get jetpacs-files--edit :coding)
                      :document doc :editor-id eid :buffer buf))
          t))
    (error
     (message "jetpacs-files: live editing unavailable: %s"
              (jetpacs-error-label err))
     nil)))

(defun jetpacs-files--edit-open (true surface)
  "Open TRUE in an editor, or fall back to the read view.
Three rungs, best first: the SYNCHRONIZED SPEC 19 editor over a real
buffer, the PLAIN seed-and-save editor, and the read-only buffer host.
Runs in a flow continuation.  Returns the fallback reason symbol, or
nil when an editor screen was pushed.  A non-regular file (FIFO,
socket, device) is refused OUTRIGHT — both this read and the
fallback's `find-file-noselect' would block in open(2) forever, and
no in-process timer can interrupt that.  A PATH the wire cannot carry
byte-identically never seeds the editor either (the Commentary's
`:args' rule — the save descriptor would take the push down); the
read fallback hosts it.  A file whose CONTENT the wire cannot carry
is likewise never editable through it — the round-trip would corrupt
exactly the bytes `jetpacs-scalar-text' replaces — and a NUL marks a
binary whose \"text\" is not worth a seed.  The file's own coding is
captured off the read and stored with the seed, so the save can write
the file back in it.

The SIZE gate takes whichever rung reaches higher, because the two
ceilings measure different things (see the section Commentary), and a
modified desktop buffer refuses only the rungs that would LOSE its
text — the synchronized rung seeds from the buffer, so it keeps them."
  (let* ((cap (jetpacs-files--editor-cap))
         (sync-cap (jetpacs-files--sync-cap-for true))
         (size (or (file-attribute-size (file-attributes true)) 0))
         (syncable (and sync-cap (<= size sync-cap)))
         (buf (get-file-buffer true))
         (coding nil)
         (reason
          (cond
           ((not (file-regular-p true)) 'not-a-file)
           ((not (jetpacs-files--wire-safe-p true)) 'unencodable)
           ((> size (max cap (or sync-cap 0))) 'oversize)
           ((and buf (buffer-modified-p buf) (not syncable))
            'desktop-modified)
           (t (let ((content (with-temp-buffer
                               (insert-file-contents true)
                               (setq coding last-coding-system-used)
                               (buffer-string))))
                (cond
                 ((string-search "\0" content) 'binary)
                 ((not (jetpacs-files--wire-safe-p content)) 'unencodable)
                 ((> size cap)
                  ;; Past the plain rung's ceiling: sync or nothing.
                  (setq jetpacs-files--edit
                        (list :path true :seed content
                              :mtime (jetpacs-files--mtime-stamp true)
                              :coding coding))
                  (if (and syncable (jetpacs-files--sync-attach true))
                      nil
                    (setq jetpacs-files--edit nil)
                    'oversize))
                 (t (setq jetpacs-files--edit
                          (list :path true :seed content
                                :mtime (jetpacs-files--mtime-stamp true)
                                :coding coding))
                    (when syncable (jetpacs-files--sync-attach true))
                    nil)))))))
    (cond
     ;; NEVER the fallback for a non-regular file: its
     ;; `find-file-noselect' is the same blocking open.
     ((eq reason 'not-a-file)
      (jetpacs-files--op-notify-refused "Open" 'not-a-file surface))
     (reason
      (jetpacs-files--read-fallback true surface reason))
     (t
      (condition-case err
          (jetpacs-chrome-push-screen surface "edit"
                                      #'jetpacs-files--edit-screen)
        (error (message "jetpacs-files: edit push failed: %s"
                        (jetpacs-error-label err))))))
    reason))

(defun jetpacs-files--edit-screen (back)
  "Builder for the pushed editor screen, the four app seams applied.
Reads the edit record and NEVER attaches: the chrome rebuilds the whole
stack on every push, so a binding made here would be remade — and its
predecessor's unflushed edits discarded — on every re-push.

The NODE id stays `jetpacs-wire-id': it is the SPEC 16.1 presentation
identity that keeps the session alive across surface replacements.  The
DOCUMENT id is a separate, extension-preserving mint, for the reason
`jetpacs-files--document-id' records.  `:value' rides along even under
sync, because SPEC 19.3 keeps it as a seed for a NEW session — the
reconnect-over-a-cached-snapshot case — while forbidding a later
snapshot from replacing live text."
  (let ((req jetpacs-files--edit))
    (if (null req)
        (jetpacs-chrome-screen
         "Edit" (jetpacs-empty-state :icon "info" :title "Nothing being edited")
         :back back)
      ;; Amendment #169 (R3): re-register the kind verdict on EVERY
      ;; build — the registry's own invariant.  The sync-attach
      ;; registration alone goes stale on exactly this builder's
      ;; reconnect-over-a-cached-snapshot path (a new session opens over
      ;; the same doc/eid with no re-attach), and a stale `allowed'
      ;; against a downgraded welcome is a sender MUST violation whose
      ;; symptom is a silently dead dropdown.  A pure table write, so
      ;; the builder's never-attach rule is untouched.
      (when (and (fboundp 'ebp-complete-set-editor-kinds)
                 (plist-get req :document) (plist-get req :editor-id))
        (ebp-complete-set-editor-kinds
         (plist-get req :document) (plist-get req :editor-id)
         (and (jetpacs-client)
              (jetpacs-feature-advertised-p "editor.candidate_kind" :app))))
      (let* ((path (plist-get req :path))
             (document (plist-get req :document))
             (body (or (run-hook-with-args-until-success
                        'jetpacs-files-editor-body-functions path)
                       (jetpacs-editor
                        ;; The SAME base the sync attach registered its
                        ;; routing key under (see `jetpacs-files--sync-attach').
                        (jetpacs-claim-node-id
                         (or (plist-get req :editor-id)
                             (jetpacs-wire-id "fedit" path)))
                        :document document
                        ;; An `fboundp'/`boundp' seam, never a require:
                        ;; `jetpacs-connect' adopts the capf harvester
                        ;; when it is loaded, and asking for completions
                        ;; nothing can answer only buys round trips.
                        :complete (and document
                                       (fboundp 'ebp-complete-edit-complete)
                                       (bound-and-true-p ebp-complete-enabled)
                                       t)
                        :syntax (jetpacs-files--syntax-for path)
                        :value (plist-get req :seed)
                        :toolbar (and jetpacs-files-editor-toolbar-function
                                      (funcall jetpacs-files-editor-toolbar-function
                                               path))
                        :on-save (jetpacs-action "jetpacs.files.save"
                                                 :args (list :path path
                                                             :mtime (plist-get req :mtime))))))
             (actions (apply #'append
                             (mapcar (lambda (f) (funcall f path))
                                     jetpacs-files-editor-actions-functions)))
             (fab (and jetpacs-files-editor-fab-function
                       (funcall jetpacs-files-editor-fab-function path))))
        (jetpacs-chrome-screen
         (jetpacs-scalar-text (file-name-nondirectory path))
         body
         :actions actions
         :fab fab
         :back back)))))

;;;; The five ops (F3)
;;
;; Reaching them: DELETE is a trailing icon-button on every entry row
;; whose descriptor carries SPEC 14.1 `:confirm' — the Companion shows
;; the native confirmation BEFORE creating the event, so the handler
;; never prompts and works without the dialog capability.  The other
;; ops live behind long-press: `jetpacs.files.menu' raises a single
;; 18.1 dialog (the `jetpacs-sections--show-menu' template) whose rows
;; conclude with an op key; the callback re-enters through
;; `jetpacs-flow-begin' — an ebp callback has no dispatch to inherit a
;; flow from, and that seam exists for exactly this stack — and the op
;; prompts (rename's new name, move's destination) bridge to the device
;; from there.  DUPLICATE needs no prompt at all.  NEW rides a top-bar
;; button on the browse screen and prompts the same way.
;;
;; Every op target goes through the guard's `absent' mode, which is
;; what F1 built it for: exists-refusal (never clobber), containment on
;; the RESOLVED name (a rename/move/create target smuggled through an
;; in-root symlink is refused), and the reason symbol travels alone.
;;
;; Every op SOURCE goes through `jetpacs-files--check-op': containment
;; confirmed on BOTH sides — the truename AND the literal entry — and
;; the op then acts on the LITERAL directory entry, never the
;; truename.  Acting on the truename once meant deleting a symlink row
;; recursively wiped the link's TARGET tree; a link is unlinked,
;; relocated, or content-copied (each primitive's native behavior),
;; never followed.

(defvar jetpacs-files--dialog-seq 0
  "Monotonic suffix for ops-menu dialog ids.
The sections lesson: 18.1 answers a REUSED outstanding `dialog_id' with
1201, and an impatient double long-press is exactly that.")

(defun jetpacs-files--duplicate-name (path)
  "A non-colliding \"NAME copy[.EXT]\" sibling path for PATH.
Bumps to \"NAME copy 2\", \"NAME copy 3\", ... until the name is free."
  (let* ((path (directory-file-name path))
         (dir (file-name-directory path))
         (base (file-name-nondirectory path))
         (dir-p (file-directory-p path))
         (stem (if dir-p base (file-name-sans-extension base)))
         (ext (if dir-p "" (or (file-name-extension base t) "")))
         (n 0) target)
    (while (progn
             (setq target (expand-file-name
                           (format "%s copy%s%s" stem
                                   (if (zerop n) "" (format " %d" (1+ n))) ext)
                           dir))
             (file-exists-p target))
      (setq n (1+ n)))
    target))

(defun jetpacs-files--op-notify-refused (op reason surface)
  "The one wording for a guard refusal, so tests can pin it."
  (jetpacs-shell-notify (format "%s refused: %s" op reason) surface))

(cl-defun jetpacs-files--check-op (path &optional (require 'readable))
  "PATH validated for a DESTRUCTIVE op; returns the literal act path.
Containment is confirmed on BOTH sides: the full truename (via
`jetpacs-files--check', REQUIRE as given — the straddle rule) AND the
literal entry — the parent's truename plus the final component — so an
op can neither follow a link out of the sandbox nor unlink an
out-of-sandbox entry that points in.  The returned act path is the
exact directory entry delete/rename/copy touch; links are handled
natively (unlinked, relocated, content-copied), never followed.
REQUIRE defaults like `jetpacs-files--check''s: only when OMITTED —
an explicit nil is containment-only on both sides."
  (jetpacs-files--check path require)
  (let* ((dfn (directory-file-name (expand-file-name path)))
         (parent (file-name-directory dfn)))
    (when (null parent)                 ; "/" — never an op target
      (signal 'ebp-path-refused (list 'outside-roots)))
    (concat (file-name-as-directory (jetpacs-files--check parent nil))
            (file-name-nondirectory dfn))))

(defun jetpacs-files--op-finish (surface)
  "Re-push SURFACE after an op; already on a timer stack, so directly."
  (condition-case err
      (jetpacs-shell-push surface)
    (error (message "jetpacs-files: op push failed: %s"
                    (jetpacs-error-label err)))))

(defun jetpacs-files--op-rename (path surface)
  "Rename PATH within its directory; the new name is a bridged prompt.
Runs inside a device flow.  Acts on the LITERAL entry (re-validated at
act time via `jetpacs-files--check-op'): a symlink is renamed as a
link — rename(2) — never followed."
  (let* ((old (file-name-nondirectory (directory-file-name path)))
         (new (string-trim
               (condition-case nil
                   (read-string (format "Rename %s to: " old) old)
                 (quit "")))))
    (cond
     ((string-empty-p new)
      (jetpacs-shell-notify "Rename cancelled" surface))
     ((string-search "/" new)
      (jetpacs-shell-notify "Name can't contain '/'" surface))
     (t
      (condition-case err
          (let* ((src (jetpacs-files--check-op path))
                 (target (jetpacs-files--check
                          (expand-file-name new (file-name-directory src))
                          'absent)))
            (rename-file src target)
            (jetpacs-shell-notify (format "Renamed to %s" new) surface))
        (ebp-path-refused
         (jetpacs-files--op-notify-refused "Rename" (cadr err) surface))
        (error (jetpacs-shell-notify
                (format "Rename failed: %s" (jetpacs-error-label err))
                surface))))))
  (jetpacs-files--op-finish surface))

(defun jetpacs-files--op-move (path surface)
  "Move PATH into a destination directory; a bridged prompt names it.
Runs inside a device flow.  Acts on the LITERAL entry (re-validated at
act time via `jetpacs-files--check-op'): a symlink relocates as a
link, never followed."
  (let* ((name (file-name-nondirectory (directory-file-name path)))
         (src-dir (file-name-directory (directory-file-name path)))
         (dest (string-trim
                (condition-case nil
                    (read-string (format "Move %s to directory: " name)
                                 (abbreviate-file-name src-dir))
                  (quit "")))))
    (if (string-empty-p dest)
        (jetpacs-shell-notify "Move cancelled" surface)
      (condition-case err
          (let* ((src (jetpacs-files--check-op path))
                 (destdir (jetpacs-files--check (expand-file-name dest)
                                                'directory))
                 (target (jetpacs-files--check
                          (expand-file-name name (file-name-as-directory destdir))
                          'absent)))
            (rename-file src target)
            (jetpacs-shell-notify
             (format "Moved to %s" (abbreviate-file-name destdir)) surface))
        (ebp-path-refused
         (jetpacs-files--op-notify-refused "Move" (cadr err) surface))
        (error (jetpacs-shell-notify
                (format "Move failed: %s" (jetpacs-error-label err))
                surface)))))
  (jetpacs-files--op-finish surface))

(defun jetpacs-files--op-duplicate (path surface)
  "Copy PATH beside itself under a fresh \"NAME copy\" name; no prompt.
Acts on the LITERAL entry (re-validated at act time via
`jetpacs-files--check-op'); for a file symlink, `copy-file' follows it
natively — the copy is a REGULAR file with the target's content."
  (condition-case err
      (let* ((src (jetpacs-files--check-op path))
             (target (jetpacs-files--check (jetpacs-files--duplicate-name src)
                                           'absent)))
        (if (file-directory-p src)
            (copy-directory src target)
          (copy-file src target))
        (jetpacs-shell-notify
         (format "Duplicated to %s"
                 (jetpacs-scalar-text
                  (file-name-nondirectory (directory-file-name target))))
         surface))
    (ebp-path-refused
     (jetpacs-files--op-notify-refused "Duplicate" (cadr err) surface))
    (error (jetpacs-shell-notify
            (format "Duplicate failed: %s" (jetpacs-error-label err))
            surface)))
  (jetpacs-files--op-finish surface))

(defconst jetpacs-files--menu-ops
  '(("rename"    "Rename"    jetpacs-files--op-rename)
    ("move"      "Move"      jetpacs-files--op-move)
    ("duplicate" "Duplicate" jetpacs-files--op-duplicate))
  "The long-press menu: (KEY LABEL FN), FN of (PATH SURFACE) in a flow.
Delete is deliberately absent — it has a better home (the row button
with descriptor `:confirm') and must keep working without the dialog
capability.")

(defun jetpacs-files--ops-menu-show (path surface)
  "Raise the single 18.1 ops dialog for PATH.
Rows conclude via `jetpacs-dialog-submit'; the callback re-enters a
fresh device flow (`jetpacs-flow-begin' — an ebp callback's stack has
no dispatch to inherit from) and runs the op."
  (when-let* ((client (jetpacs-client)))
    (ebp-client-dialog-show
     client
     (format "files-%s-%d" (abs (sxhash path))
             (cl-incf jetpacs-files--dialog-seq))
     (apply #'jetpacs-column
            (jetpacs-text (jetpacs-scalar-text
                           (file-name-nondirectory (directory-file-name path)))
                          :style "title")
            (append
             (mapcar (pcase-lambda (`(,key ,label ,_fn))
                       (jetpacs-button label (jetpacs-dialog-submit :value key)))
                     jetpacs-files--menu-ops)
             (list (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))))
     :callback
     (lambda (status result _error)
       (when-let* (((equal status "submitted"))
                   (key (plist-get result :value))
                   (op (nth 2 (assoc key jetpacs-files--menu-ops))))
         (jetpacs-flow-begin surface (lambda () (funcall op path surface))))))))

(defun jetpacs-files--op-new (dir surface)
  "Create a file or folder in DIR; name and kind are bridged prompts.
Runs inside a device flow."
  (let ((name (string-trim
               (condition-case nil
                   (read-string (format "New in %s — name: "
                                        (abbreviate-file-name dir)))
                 (quit "")))))
    (cond
     ((string-empty-p name)
      (jetpacs-shell-notify "Create cancelled" surface))
     ;; Single segment only: traversal never even reaches the guard.
     ((string-search "/" name)
      (jetpacs-shell-notify "Name can't contain '/'" surface))
     (t
      (let ((kind (condition-case nil
                      (completing-read "Create: " '("File" "Folder") nil t)
                    (quit nil))))
        (if (null kind)
            (jetpacs-shell-notify "Create cancelled" surface)
          (condition-case err
              (let ((target (jetpacs-files--check (expand-file-name name dir)
                                                  'absent)))
                (if (equal kind "Folder")
                    (make-directory target)
                  (write-region "" nil target nil 'silent))
                (jetpacs-shell-notify (format "Created %s" name) surface))
            (ebp-path-refused
             (jetpacs-files--op-notify-refused "Create" (cadr err) surface))
            (error (jetpacs-shell-notify
                    (format "Create failed: %s" (jetpacs-error-label err))
                    surface))))))))
  (jetpacs-files--op-finish surface))

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
                       (jetpacs-error-label err)))))))

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
          (ebp-path-refused
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
                ;; The whole effect lives in the flow continuation:
                ;; eligibility stats and reads the file, the read
                ;; fallback can PROMPT (changed on disk), and JC-4a
                ;; bridges prompts to the device only from there.
                (jetpacs-flow-continue
                 (lambda () (jetpacs-files--edit-open true surface))))
              'accepted)
          (ebp-path-refused
           (jetpacs-shell-notify (format "File refused: %s" (cadr err))
                                 surface)
           'rejected)))))

  (jetpacs-defaction "jetpacs.files.refresh"
    (lambda (_args params)
      (jetpacs-files--repush (jetpacs-files--event-surface params))
      'accepted))

  (jetpacs-defaction "jetpacs.files.menu"
    ;; Long-press: the ops dialog.  Gated on the dialog capability —
    ;; without it there is no non-blocking way to offer the menu, so
    ;; say so rather than hang (the sections precedent).
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params)))
        (cond
         ((not (jetpacs-granted-p "surfaces.dialog"))
          (jetpacs-shell-notify "Needs the dialog capability" surface)
          'rejected)
         (t
          (condition-case err
              ;; Both-sides validation, and the ACT path — the literal
              ;; entry, not the truename — is what the menu's ops get:
              ;; an op on a symlink row must touch the link itself.
              (let ((act (jetpacs-files--check-op (plist-get args :path))))
                ;; The dialog itself is a request; raising it from the
                ;; continuation keeps this handler's reply prompt (D2).
                (jetpacs-flow-continue
                 (lambda () (jetpacs-files--ops-menu-show act surface)))
                'accepted)
            (ebp-path-refused
             (jetpacs-files--op-notify-refused "Menu" (cadr err) surface)
             'rejected)))))))

  (jetpacs-defaction "jetpacs.files.delete"
    ;; The Companion presented `:confirm' BEFORE creating this event
    ;; (SPEC 14.1), so there is no prompt here — validate, act
    ;; synchronously (14.4: `accepted' only once the effect is
    ;; durable), defer only the re-push.  Containment-only guard (on
    ;; BOTH sides — `jetpacs-files--check-op'): an unreadable-but-owned
    ;; file is still the user's to delete, but the delete acts on the
    ;; LITERAL entry — a symlink row is UNLINKED, never followed (the
    ;; truename route once recursively wiped a link's target tree).
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params)))
        (condition-case err
            (let ((act (jetpacs-files--check-op (plist-get args :path) nil)))
              (cond
               ((not (or (file-symlink-p act) (file-exists-p act)))
                ;; The row the user confirmed no longer names anything:
                ;; the snapshot is outdated, which is what stale MEANS.
                ;; (A DANGLING link still names an entry — deletable.)
                'stale)
               (t
                (cond
                 ;; The explicit symlink leg is mandatory, not just for
                 ;; not-following: `delete-directory' RECURSIVE on a
                 ;; link skips recursion and rmdirs under `files--force'
                 ;; (30.1 files.el) — a silent no-op.
                 ((file-symlink-p act) (delete-file act))
                 ((file-directory-p act) (delete-directory act t))
                 (t (delete-file act)))
                (jetpacs-shell-notify
                 (format "Deleted %s"
                         (jetpacs-scalar-text
                          (file-name-nondirectory (directory-file-name act))))
                 surface)
                (jetpacs-files--repush surface)
                'accepted)))
          (ebp-path-refused
           (jetpacs-files--op-notify-refused "Delete" (cadr err) surface)
           'rejected)
          (error
           (jetpacs-shell-notify
            (format "Delete failed: %s" (jetpacs-error-label err)) surface)
           'rejected)))))

  (jetpacs-defaction "jetpacs.files.new"
    ;; The top-bar "+": name and kind are bridged prompts, so the whole
    ;; effect lives in the flow continuation (JC-4a), like open.
    (lambda (_args params)
      (let ((surface (jetpacs-files--event-surface params)))
        (cond
         ((not (jetpacs-granted-p "surfaces.dialog"))
          (jetpacs-shell-notify "Needs the dialog capability" surface)
          'rejected)
         (t
          (condition-case err
              (let ((dir (jetpacs-files--check (jetpacs-files--current-dir)
                                               'directory)))
                (jetpacs-flow-continue
                 (lambda () (jetpacs-files--op-new dir surface)))
                'accepted)
            (ebp-path-refused
             (jetpacs-files--op-notify-refused "Create" (cadr err) surface)
             'rejected)))))))

  (jetpacs-defaction "jetpacs.files.save"
    ;; SPEC 14.3: `on_save' injects the editor's full content as
    ;; `value' into a copy of the descriptor's args; the path and the
    ;; open-time mtime stamp ride the descriptor itself.  Containment-
    ;; only guard: the stamp gate owns "is this still the file the
    ;; user opened", and writability is pre-checked as its own refusal
    ;; leg — BEFORE anything mutates.
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params))
            (value (plist-get args :value))
            (stamp (plist-get args :mtime)))
        (condition-case err
            (let ((true (jetpacs-files--check (plist-get args :path) nil)))
              (cond
               ((not (stringp value)) 'rejected)
               ((> (string-bytes value) jetpacs-files-max-bytes)
                ;; #138: the write is the interpretation; bound it even
                ;; though a conforming Companion could not have sent it.
                (jetpacs-shell-notify "Save too large" surface)
                'rejected)
               ((not (equal stamp (jetpacs-files--mtime-stamp true)))
                ;; Changed — or vanished — on disk since the editor
                ;; opened: the seed the user edited is outdated, and the
                ;; newer state is NOT written over.
                (jetpacs-shell-notify "File changed on disk — not saved"
                                      surface)
                'stale)
               ((not (file-writable-p true))
                ;; REFUSE BEFORE MUTATING anything.  The old buffer
                ;; route reached `save-buffer''s interactive recovery
                ;; (30.1 files.el `basic-save-buffer-2': "File %s is
                ;; write-protected; try to save anyway?") AFTER the
                ;; buffer was already replaced, leaving the desktop
                ;; buffer holding the device's text as unsaved edits.
                (jetpacs-files--op-notify-refused "Save" 'unwritable surface)
                'rejected)
               (t
                (let* ((buf (get-file-buffer true))
                       ;; The leg selector.  Nil until an editor screen
                       ;; actually attaches a buffer, so this whole
                       ;; branch is today's plain save, unchanged.
                       (synced (jetpacs-files--synced-buffer true))
                       (written value))
                  ;; The desktop-modified refusal belongs to the PLAIN
                  ;; leg ALONE.  A synchronized buffer is INTENTIONALLY
                  ;; modified — that is what every device keystroke does
                  ;; to it — so leaving this gate unscoped would refuse
                  ;; every synced save forever.
                  (if (and (null synced) buf (buffer-modified-p buf))
                      (progn
                        (jetpacs-shell-notify
                         "Unsaved desktop edits — not saved" surface)
                        'rejected)
                    ;; SYNCHRONIZED: flush FIRST, so an edit the tracker
                    ;; has seen but not yet sent is IN the text written
                    ;; below.  Deliberately OUTSIDE the coding binding
                    ;; that follows: that binding exists for the write
                    ;; and must not span a send.  `process-send-string'
                    ;; is re-entrant — a frame large enough to fill the
                    ;; socket buffer blocks in `send_process', which
                    ;; spins in `wait_reading_process_output', which runs
                    ;; timers, and jsonrpc.el dispatches from timers — so
                    ;; a flush inside the binding could run inbound
                    ;; handlers with the edited file's coding still in
                    ;; force over their own I/O.  The wire itself was
                    ;; never at risk: `ebp-connect' pins the socket
                    ;; `:coding utf-8-unix' at creation, and that, not
                    ;; the ambient binding, is what encodes a frame.
                    (when synced (ebp-sync-flush synced))
                    ;; THE WRITE COMES FIRST, and it is always
                    ;; `write-region' — never `save-buffer', whose
                    ;; recovery prompts signal `inhibited-interaction'
                    ;; under the dispatch's no-prompt regime.  The
                    ;; file's own coding (captured at open) rides the
                    ;; write while the edit record is still current —
                    ;; the mtime gate above already proved the file
                    ;; unchanged since that open; nil keeps the
                    ;; ambient behavior.
                    (let ((coding-system-for-write
                           (and (equal (plist-get jetpacs-files--edit :path)
                                       true)
                                (plist-get jetpacs-files--edit :coding))))
                      (if synced
                          ;; Write the BUFFER, not `value': the buffer is
                          ;; the superset — it also carries whatever
                          ;; Emacs itself changed since the device's last
                          ;; delta.
                          (with-current-buffer synced
                            ;; WIDEN, or a narrowed buffer saves only its
                            ;; accessible portion OVER the whole file:
                            ;; both `buffer-substring-no-properties' and
                            ;; `write-region' honor the restriction.  The
                            ;; snapshot is inside the widen too — the
                            ;; seed must describe what actually landed on
                            ;; disk, or the next reseed hands the device
                            ;; truncated text.  The flag and the modtime
                            ;; are buffer-global and stay outside; the
                            ;; user's own restriction is restored.
                            (save-restriction
                              (widen)
                              (setq written (buffer-substring-no-properties
                                             (point-min) (point-max)))
                              (write-region (point-min) (point-max) true
                                            nil 'silent))
                            (set-buffer-modified-p nil)
                            (set-visited-file-modtime))
                        (write-region value nil true nil 'silent)))
                    ;; Only once the write is durable does a visiting
                    ;; (already-unmodified) buffer get refreshed:
                    ;; `revert-buffer' re-reads, widens, updates the
                    ;; visited modtime and clears the modified flag.  A
                    ;; refresh failure must NOT flip a durable
                    ;; `accepted' (14.4 makes the answer permanent).
                    ;; NEVER on the synced leg: a re-read is a buffer
                    ;; change track-changes sees as a local edit and
                    ;; echoes back as a spurious `edit.apply'.  The
                    ;; write above already cleared the flag and stamped
                    ;; the modtime, which is all the revert was for.
                    (when (and buf (null synced))
                      (condition-case rerr
                          (with-current-buffer buf
                            (revert-buffer :ignore-auto :noconfirm
                                           :preserve-modes))
                        (error
                         (message "jetpacs-files: buffer refresh failed: %s"
                                  (jetpacs-error-label rerr)))))
                    ;; Effect durable -> accepted (14.4).  Keep the edit
                    ;; state coherent for the NEXT save: a fresh stamp
                    ;; and the text just written.  Under sync that text
                    ;; is only a RECONNECT SEED — SPEC.md:3199-3201 makes
                    ;; `value' seed a NEW session and forbids a later
                    ;; snapshot from replacing live text — so the record
                    ;; is edited in place rather than rebuilt, and the
                    ;; session keys the builder emits survive.
                    (when (equal (plist-get jetpacs-files--edit :path) true)
                      (setq jetpacs-files--edit
                            (plist-put
                             (plist-put (copy-sequence jetpacs-files--edit)
                                        :seed written)
                             :mtime (jetpacs-files--mtime-stamp true))))
                    ;; ISOLATED: the write is already durable, so a
                    ;; third-party seam subscriber that signals must not
                    ;; turn this into `rejected' — SPEC 14.4 makes that
                    ;; PERMANENT, and the Companion would re-deliver a
                    ;; save that already landed.  (Caught by the F4 gate:
                    ;; a broken subscriber flipped an accepted save.)
                    (jetpacs-run-isolated 'jetpacs-files-after-save-hook
                                          true)
                    (jetpacs-shell-notify
                     (if (and user-init-file
                              (file-exists-p user-init-file)
                              (file-equal-p true user-init-file))
                         ;; Re-loading init mid-session never applies
                         ;; cleanly; the honest instruction is a restart.
                         "Saved init — restart Emacs to apply config changes"
                       (format "Saved %s"
                               (jetpacs-scalar-text
                                (file-name-nondirectory true))))
                     surface)
                    (jetpacs-files--repush surface)
                    'accepted)))))
          (ebp-path-refused
           (jetpacs-files--op-notify-refused "Save" (cadr err) surface)
           'rejected)
          (error
           (jetpacs-shell-notify
            (format "Save failed: %s" (jetpacs-error-label err)) surface)
           'rejected)))))

  (jetpacs-defaction "jetpacs.files.grep"
    ;; SPEC 14.3: `on_submit' injects the submitted text as `value'
    ;; into a copy of the descriptor's args, so the query arrives in
    ;; ARGS.  The scan itself runs from the results screen's builder
    ;; through `jetpacs-async' — this handler only validates, records
    ;; the request, and defers the screen push.
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params))
            (query (plist-get args :value)))
        (cond
         ((not (stringp query)) 'rejected)
         ((string-empty-p (string-trim query)) 'rejected)
         ((> (length query) jetpacs-files-grep-max-query-chars)
          (jetpacs-shell-notify "Search text too long" surface)
          'rejected)
         (t
          (condition-case err
              (let ((dir (jetpacs-files--check (jetpacs-files--current-dir)
                                               'directory)))
                (setq jetpacs-files--grep-request
                      (list :query (substring-no-properties
                                    (string-trim query))
                            :dir dir))
                (jetpacs-flow-continue
                 (lambda ()
                   ;; push-screen is TRANSACTIONAL and re-signals on a
                   ;; refused push; a deferred caller must catch or the
                   ;; signal dies in a timer (its own docstring's rule).
                   (condition-case e2
                       (jetpacs-chrome-push-screen
                        surface "grep" #'jetpacs-files--grep-screen)
                     (error (message "jetpacs-files: search push failed: %s"
                                     (jetpacs-error-label e2))))))
                'accepted)
            (ebp-path-refused
             (jetpacs-shell-notify (format "Folder refused: %s" (cadr err))
                                   surface)
             'rejected))))))))

;;;; Entry point and unload hygiene

(defun jetpacs-files ()
  "Push the files browser to the device now, loudly."
  (interactive)
  (jetpacs-client-or-error)
  (jetpacs-shell-push jetpacs-files-owner))

(defun jetpacs-files-reset ()
  "Release a synchronized editor binding the session outlived.
A BELT, not the mechanism: the Companion sends `edit.close' on node
removal, document change or presentation-identity change, and ebp-sync
detaches from that.  This catches the case no close can cover — the
session ended under the editor — so a stray tracker never survives into
the next connection.  The BUFFER survives on purpose: it is the user's
file buffer, and it was theirs before the phone ever saw it."
  (when-let* ((req jetpacs-files--edit)
              (buf (plist-get req :buffer)))
    (when (buffer-live-p buf)
      (ebp-sync-detach buf)))
  (setq jetpacs-files--edit nil))

(add-hook 'jetpacs-reset-functions #'jetpacs-files-reset)

(defun jetpacs-files-unload-function ()
  "Unload hygiene: the skin registration and the owner's surfaces.
`jetpacs-teardown-owner' also clears the owner's async entries, which
cancels any in-flight scan."
  (setq jetpacs-render-buffer-functions
        (assq-delete-all 'dired-mode jetpacs-render-buffer-functions))
  (setq jetpacs-files--grep-request nil)
  (remove-hook 'jetpacs-reset-functions #'jetpacs-files-reset)
  (jetpacs-teardown-owner jetpacs-files-owner)
  nil)

(provide 'jetpacs-files)
;;; jetpacs-files.el ends here
