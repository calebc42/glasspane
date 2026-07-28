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

(cl-defun jetpacs-files--check (path &optional (require 'readable))
  "PATH through the floor guard against the effective roots.
REQUIRE as in `jetpacs-check-path'; the default applies only when the
argument is OMITTED — an explicit nil means containment-only, and an
`(or ... \\='readable)' here once silently turned delete's nil into a
readability stat."
  (jetpacs-check-path path (jetpacs-files--roots) :require require))

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
                         :actions (list (jetpacs-icon-button
                                         "add"
                                         (jetpacs-action "jetpacs.files.new")
                                         :content-description
                                         "New file or folder"))
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

(defun jetpacs-files--op-finish (surface)
  "Re-push SURFACE after an op; already on a timer stack, so directly."
  (condition-case err
      (jetpacs-shell-push surface)
    (error (message "jetpacs-files: op push failed: %s"
                    (jetpacs--error-label err)))))

(defun jetpacs-files--op-rename (path surface)
  "Rename PATH within its directory; the new name is a bridged prompt.
Runs inside a device flow."
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
          (let ((target (jetpacs-files--check
                         (expand-file-name
                          new (file-name-directory (directory-file-name path)))
                         'absent)))
            (rename-file path target)
            (jetpacs-shell-notify (format "Renamed to %s" new) surface))
        (jetpacs-path-refused
         (jetpacs-files--op-notify-refused "Rename" (cadr err) surface))
        (error (jetpacs-shell-notify
                (format "Rename failed: %s" (jetpacs--error-label err))
                surface))))))
  (jetpacs-files--op-finish surface))

(defun jetpacs-files--op-move (path surface)
  "Move PATH into a destination directory; a bridged prompt names it.
Runs inside a device flow."
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
          (let* ((destdir (jetpacs-files--check (expand-file-name dest)
                                                'directory))
                 (target (jetpacs-files--check
                          (expand-file-name name (file-name-as-directory destdir))
                          'absent)))
            (rename-file path target)
            (jetpacs-shell-notify
             (format "Moved to %s" (abbreviate-file-name destdir)) surface))
        (jetpacs-path-refused
         (jetpacs-files--op-notify-refused "Move" (cadr err) surface))
        (error (jetpacs-shell-notify
                (format "Move failed: %s" (jetpacs--error-label err))
                surface)))))
  (jetpacs-files--op-finish surface))

(defun jetpacs-files--op-duplicate (path surface)
  "Copy PATH beside itself under a fresh \"NAME copy\" name; no prompt."
  (condition-case err
      (let ((target (jetpacs-files--check (jetpacs-files--duplicate-name path)
                                          'absent)))
        (if (file-directory-p path)
            (copy-directory path target)
          (copy-file path target))
        (jetpacs-shell-notify
         (format "Duplicated to %s"
                 (jetpacs-scalar-text
                  (file-name-nondirectory (directory-file-name target))))
         surface))
    (jetpacs-path-refused
     (jetpacs-files--op-notify-refused "Duplicate" (cadr err) surface))
    (error (jetpacs-shell-notify
            (format "Duplicate failed: %s" (jetpacs--error-label err))
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
            (jetpacs-path-refused
             (jetpacs-files--op-notify-refused "Create" (cadr err) surface))
            (error (jetpacs-shell-notify
                    (format "Create failed: %s" (jetpacs--error-label err))
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
              (let ((true (jetpacs-files--check (plist-get args :path))))
                ;; The dialog itself is a request; raising it from the
                ;; continuation keeps this handler's reply prompt (D2).
                (jetpacs-flow-continue
                 (lambda () (jetpacs-files--ops-menu-show true surface)))
                'accepted)
            (jetpacs-path-refused
             (jetpacs-files--op-notify-refused "Menu" (cadr err) surface)
             'rejected)))))))

  (jetpacs-defaction "jetpacs.files.delete"
    ;; The Companion presented `:confirm' BEFORE creating this event
    ;; (SPEC 14.1), so there is no prompt here — validate, act
    ;; synchronously (14.4: `accepted' only once the effect is
    ;; durable), defer only the re-push.  Containment-only guard: an
    ;; unreadable-but-owned file is still the user's to delete.
    (lambda (args params)
      (let ((surface (jetpacs-files--event-surface params)))
        (condition-case err
            (let ((true (jetpacs-files--check (plist-get args :path) nil)))
              (cond
               ((not (file-exists-p true))
                ;; The row the user confirmed no longer names anything:
                ;; the snapshot is outdated, which is what stale MEANS.
                'stale)
               (t
                (if (file-directory-p true)
                    (delete-directory true t)
                  (delete-file true))
                (jetpacs-shell-notify
                 (format "Deleted %s"
                         (jetpacs-scalar-text
                          (file-name-nondirectory (directory-file-name true))))
                 surface)
                (jetpacs-files--repush surface)
                'accepted)))
          (jetpacs-path-refused
           (jetpacs-files--op-notify-refused "Delete" (cadr err) surface)
           'rejected)
          (error
           (jetpacs-shell-notify
            (format "Delete failed: %s" (jetpacs--error-label err)) surface)
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
            (jetpacs-path-refused
             (jetpacs-files--op-notify-refused "Create" (cadr err) surface)
             'rejected)))))))

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
                                     (jetpacs--error-label e2))))))
                'accepted)
            (jetpacs-path-refused
             (jetpacs-shell-notify (format "Folder refused: %s" (cadr err))
                                   surface)
             'rejected))))))))

;;;; Entry point and unload hygiene

(defun jetpacs-files ()
  "Push the files browser to the device now, loudly."
  (interactive)
  (jetpacs-client-or-error)
  (jetpacs-shell-push jetpacs-files-owner))

(defun jetpacs-files-unload-function ()
  "Unload hygiene: the skin registration and the owner's surfaces.
`jetpacs-teardown-owner' also clears the owner's async entries, which
cancels any in-flight scan."
  (setq jetpacs-render-buffer-functions
        (assq-delete-all 'dired-mode jetpacs-render-buffer-functions))
  (setq jetpacs-files--grep-request nil)
  (jetpacs-teardown-owner jetpacs-files-owner)
  nil)

(provide 'jetpacs-files)
;;; jetpacs-files.el ends here
