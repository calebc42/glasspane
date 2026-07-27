;;; jetpacs-org.el --- The org extraction and mutation engine -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-4 of docs/PLAN-jetpacs-apps.md: the org API the entire app tier
;; stands on — cache, heading refs and their wire tokens, the org-ql-
;; subset query grammar, mutations, and the shared primitives (capture,
;; LOGBOOK, planning cookies, TBLFM).  UI-FREE by construction: this
;; module requires no widgets and builds no nodes; JA-5's skin and any
;; Tier-1 (the D-1 block editor, glasspane at its port rung) consume it.
;;
;; Ported from poc-v1's jetpacs-org.el engine ranges, NOT transliterated.
;; Twelve poc defects are fixed here rather than restored — the audit
;; map lives in the JA-4 plan; the load-bearing ones are named at their
;; fix sites.  Do not "restore" any of the following from the source:
;;
;;   - `(read q)' on a wire string (obarray poisoning, measured; and an
;;     RCE hand-off when org-ql is installed).  The sexp arm reads under
;;     a throwaway obarray and vets against an allowlist (O2).
;;   - `org-id-find' in ref resolution: its miss path runs a FULL org-id
;;     rescan and falls back to the ambient current buffer — inside the
;;     socket filter.  Resolution never calls it.
;;   - the raw `save-buffer' idle timer: supersession and file locks both
;;     PROMPT, and a prompt in a timer wedges a daemon.  The save path
;;     refuses loudly instead.
;;   - absolute paths in error messages: refs carry paths, errors do not
;;     (D-4; `jetpacs--error-label' prints symbols only).
;;
;; THE WIRE CONTRACT (D-4, ratified + amended 2026-07-27): refs are
;; Emacs-side plists and NEVER cross the wire; the wire carries opaque
;; per-owner tokens minted against a replace-set table (the
;; `results.visit' :index contract generalized).  Status mapping for
;; handlers: token miss -> `stale'; `jetpacs-org-unresolved' -> `stale';
;; `jetpacs-org-refused' -> `rejected'.  The glasspane alist->plist
;; migration deliberately did NOT ride this rung — glasspane cannot load
;; against the rewrite yet, and migrates once, at its own port rung.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)                       ; org-id-locations / find-id-in-file
(require 'org-capture)                  ; O3: templates, capture-run
(require 'org-table)                    ; O3: org-table-current-begin-pos defvar
(require 'jetpacs-surfaces)             ; owner floor: teardown, current-owner

(defgroup jetpacs-org nil
  "The Jetpacs org extraction and mutation engine."
  :group 'jetpacs)

;;;; Errors — the handler status boundary

(define-error 'jetpacs-org-refused "jetpacs-org: ref refused")
(define-error 'jetpacs-org-unresolved "jetpacs-org: heading not found")

;;;; The root allowlist

(defcustom jetpacs-org-roots nil
  "Directories `jetpacs-org-resolve-ref' may touch.
nil derives the set from `org-directory' and the directories of
`org-agenda-files'.  Matching is by true-name path components, never
by string prefix — /org-evil does not sit under /org."
  :type '(repeat directory))

(defun jetpacs-org--roots ()
  "The effective allowlist, true-named."
  (delq nil
        (mapcar (lambda (d)
                  (and (stringp d) (file-directory-p d)
                       (file-truename d)))
                (or jetpacs-org-roots
                    (delete-dups
                     (cons org-directory
                           (mapcar #'file-name-directory
                                   (ignore-errors (org-agenda-files)))))))))

(defun jetpacs-org--check-file (file)
  "FILE validated against policy, returned as a truename, or signal.
Guard order is load-bearing: `file-remote-p' inspects the NAME and runs
first, because for a remote path the stat IS the connection —
`file-truename' or `file-readable-p' on /ssh:host:… dials the host."
  (unless (and (stringp file) (not (string-empty-p file))
               (file-name-absolute-p file))
    (signal 'jetpacs-org-refused (list 'not-absolute)))
  (when (file-remote-p file)
    (signal 'jetpacs-org-refused (list 'remote)))
  (let ((true (file-truename file))
        (roots (jetpacs-org--roots)))
    (unless (cl-some (lambda (root) (file-in-directory-p true root)) roots)
      ;; The symbol only — no path may ride an error toward the device.
      (signal 'jetpacs-org-refused (list 'outside-roots)))
    (unless (file-readable-p true)
      (signal 'jetpacs-org-refused (list 'unreadable)))
    true))

;;;; Cache layer

(defvar jetpacs-org--cache (make-hash-table :test #'equal)
  "Memoised org extraction results.")

(defcustom jetpacs-org-stat-ttl 1.0
  "Seconds the agenda-file mtime stamp is trusted between stats.
The poc statted every agenda file on EVERY cache lookup, hits included
— N truename+stat syscalls per lookup.  Within this window the stamp is
reused; `jetpacs-org-cache-invalidate' clears it, so a mutation is
never masked by the memo."
  :type 'number)

(defvar jetpacs-org--stamp-memo nil
  "(EXPIRY-FLOAT . STAMP) — the memoised file stamp, or nil.")

(defun jetpacs-org--files-stamp ()
  "A full-resolution freshness stamp for the agenda file set.
A LIST of (TRUENAME . MTIME-TIME-VALUE) conses — not a max float: the
poc's max-of-float-time collided inside one clock tick (two writes,
same double => stale hit) and was blind to set MEMBERSHIP changes
\(dropping the newest file left the max unchanged).  Time values keep
their native resolution and compare with `equal'."
  (let ((now (float-time)))
    (if (and jetpacs-org--stamp-memo
             (< now (car jetpacs-org--stamp-memo)))
        (cdr jetpacs-org--stamp-memo)
      (let ((stamp
             (delq nil
                   (mapcar
                    (lambda (file)
                      (when (file-exists-p file)
                        (let ((true (file-truename file)))
                          (cons true
                                (file-attribute-modification-time
                                 (file-attributes true))))))
                    (ignore-errors (org-agenda-files))))))
        (setq jetpacs-org--stamp-memo
              (cons (+ now jetpacs-org-stat-ttl) stamp))
        stamp))))

(defun jetpacs-org--cache-key (namespace &rest parts)
  "Build a cache key from NAMESPACE and PARTS.
Scoped to today's date and the agenda files' stamp, so external edits,
membership changes, and date roll-over all bust the cache.  NAMESPACE
stays at `nth 2' — `jetpacs-org-cache-invalidate' reads it there."
  (cons (format-time-string "%Y-%m-%d")
        (cons (jetpacs-org--files-stamp)
              (cons namespace parts))))

(defmacro jetpacs-org-with-cache (namespace key &rest body)
  "Memoise BODY's result in `jetpacs-org--cache' under NAMESPACE and KEY."
  (declare (indent 2))
  (let ((k (gensym "key")) (hit (gensym "hit")))
    `(let* ((,k (jetpacs-org--cache-key ,namespace ,key))
            (,hit (gethash ,k jetpacs-org--cache 'jetpacs-org--miss)))
       (if (eq ,hit 'jetpacs-org--miss)
           (puthash ,k (progn ,@body) jetpacs-org--cache)
         ,hit))))

(defun jetpacs-org-cache-invalidate (&optional namespace)
  "Drop memoised org extractions (and the stat memo).
With NAMESPACE, only entries under it.  Keys are collected before
removal — never `remhash' inside the `maphash' walk."
  (setq jetpacs-org--stamp-memo nil)
  (if namespace
      (let (dead)
        (maphash (lambda (k _v)
                   (when (equal (nth 2 k) namespace) (push k dead)))
                 jetpacs-org--cache)
        (dolist (k dead) (remhash k jetpacs-org--cache)))
    (clrhash jetpacs-org--cache)))

;;;; Heading references — Emacs-side plists, never on the wire

(defun jetpacs-org-ref-at-point ()
  "Ref plist for the org heading at point:
\(:id ID-or-nil :file TRUENAME :pos INT :headline STRING).
Emacs-internal; a ref NEVER crosses the wire (D-4) — mint a token with
`jetpacs-org-ref-tokens'.  :file is a truename so the resolve-time root
check compares like with like."
  (save-excursion
    (unless (org-at-heading-p)
      (ignore-errors (org-back-to-heading t)))
    (let ((id (org-entry-get nil "ID"))
          (file (buffer-file-name)))
      (list :id (and (stringp id) (not (string-empty-p id)) id)
            :file (if file (file-truename file) "")
            :pos (point)
            :headline (or (nth 4 (org-heading-components)) "")))))

(defun jetpacs-org--find-in-file-by-id (id file)
  "Marker for ID in validated FILE, or nil.  Never `org-id-find':
its miss path runs `org-id-update-id-locations' — a full rescan of the
org-id file set — and falls back to the CURRENT buffer's file, which
inside the socket filter is whatever happened to be current."
  (ignore-errors (org-id-find-id-in-file id file 'marker)))

(defun jetpacs-org-resolve-ref (ref)
  "Resolve REF (a plist from `jetpacs-org-ref-at-point') to a marker.
Signals `jetpacs-org-refused' on policy (absolute/remote/roots/
readable — handler answer: `rejected') and `jetpacs-org-unresolved'
when the heading is genuinely gone (content drift — handler answer:
`stale', the Companion re-presents).  Resolution: id in the validated
file, id via `org-id-locations' (the mapped file re-validated), trusted
pos with a headline check, then a headline scan."
  (let ((id (plist-get ref :id))
        (file (plist-get ref :file))
        (pos (plist-get ref :pos))
        (headline (plist-get ref :headline)))
    ;; A whole-valued pos can arrive as a float after a JSON round trip
    ;; (org.json emits the trailing .0); without the coercion the
    ;; trusted-position path fails and the headline scan may resolve the
    ;; wrong heading among duplicate titles.
    (when (numberp pos) (setq pos (truncate pos)))
    (let* ((true (and (stringp file) (not (string-empty-p file))
                      (jetpacs-org--check-file file)))
           (marker
            (or
             ;; 1. The stable id, in the ref's own (validated) file.
             (and true (stringp id) (not (string-empty-p id))
                  (jetpacs-org--find-in-file-by-id id true))
             ;; 2. The id, wherever org-id last recorded it — with the
             ;;    mapped file put through the SAME policy guards.
             (and (stringp id) (not (string-empty-p id))
                  (hash-table-p org-id-locations)
                  (when-let* ((mapped (gethash id org-id-locations))
                              (mapped-true
                               (condition-case nil
                                   (jetpacs-org--check-file mapped)
                                 (jetpacs-org-refused nil))))
                    (jetpacs-org--find-in-file-by-id id mapped-true)))
             ;; 3. Trusted position, only while its headline still holds.
             (and true
                  (with-current-buffer (find-file-noselect true)
                    (org-with-wide-buffer
                     (when (and (integerp pos)
                                (<= (point-min) pos (point-max)))
                       (goto-char pos)
                       (when (ignore-errors (org-back-to-heading t) t)
                         (when (or (not (stringp headline))
                                   (string-empty-p headline)
                                   (equal (nth 4 (org-heading-components))
                                          headline))
                           (copy-marker (point))))))))
             ;; 4. Headline scan — first match wins, ambiguous by
             ;;    construction among duplicate titles.
             (and true (stringp headline) (not (string-empty-p headline))
                  (with-current-buffer (find-file-noselect true)
                    (org-with-wide-buffer
                     (goto-char (point-min))
                     (catch 'found
                       (while (re-search-forward org-heading-regexp nil t)
                         (when (equal (nth 4 (org-heading-components))
                                      headline)
                           (throw 'found
                                  (copy-marker
                                   (line-beginning-position)))))
                       nil)))))))
      (or marker
          ;; The SYMBOL path only: no filename, no headline text — the
          ;; poc formatted the absolute path into this error and callers
          ;; pushed it to a device snackbar.
          (signal 'jetpacs-org-unresolved nil)))))

;;;; Wire tokens — the D-4 opaque per-owner replace-set table

(defconst jetpacs-org-token-set-max 512
  "Refs per (owner,set); minting beyond signals (a build-time error).")

(defconst jetpacs-org-token-sets-max 32
  "Sets per owner; minting a new set beyond signals.")

(defvar jetpacs-org--tokens (make-hash-table :test #'equal)
  "TOKEN-STRING -> (:owner O :set S :ref REF-PLIST).")

(defvar jetpacs-org--token-sets (make-hash-table :test #'equal)
  "(OWNER . SET) -> list of live token strings, for the replace sweep.")

(defvar jetpacs-org--token-nonce
  (format "%08x" (random #x100000000))
  "Per-session opacity salt; re-minted by `jetpacs-org-reset'.")

(defvar jetpacs-org--token-counter 0)

(cl-defun jetpacs-org-ref-tokens (refs &key (set "default") owner)
  "Mint one opaque token per REF, REPLACING the (OWNER,SET) entry.
OWNER defaults to `jetpacs-current-owner'; neither is an error.  Every
token previously minted for this (owner,set) dies NOW — a re-render
re-mints, so the table size stays equal to the live sets and a swept
token is a plain miss (the `results.visit' replace-set shape).  A ref
whose :file fails the resolve policy signals at MINT time: statically
invalid input fails at build, not at tap.  Returns tokens in REFS
order."
  (let ((owner (or owner jetpacs-current-owner)))
    (unless (stringp owner)
      (error "jetpacs-org-ref-tokens: no owner (bind via with-jetpacs-owner or pass :owner)"))
    (when (> (length refs) jetpacs-org-token-set-max)
      (error "jetpacs-org-ref-tokens: %d refs exceeds the %d per-set cap"
             (length refs) jetpacs-org-token-set-max))
    (let ((key (cons owner set)))
      (unless (gethash key jetpacs-org--token-sets)
        (let ((sets 0))
          (maphash (lambda (k _v) (when (equal (car k) owner)
                                    (setq sets (1+ sets))))
                   jetpacs-org--token-sets)
          (when (>= sets jetpacs-org-token-sets-max)
            (error "jetpacs-org-ref-tokens: owner %s exceeds %d sets"
                   owner jetpacs-org-token-sets-max))))
      ;; The replace sweep: the old generation dies before the new mints.
      (dolist (old (gethash key jetpacs-org--token-sets))
        (remhash old jetpacs-org--tokens))
      (let (tokens)
        (dolist (ref refs)
          (let ((file (plist-get ref :file)))
            (when (and (stringp file) (not (string-empty-p file)))
              (jetpacs-org--check-file file)))
          (let ((token (format "o%s-%x" jetpacs-org--token-nonce
                               (cl-incf jetpacs-org--token-counter))))
            (puthash token (list :owner owner :set set :ref ref)
                     jetpacs-org--tokens)
            (push token tokens)))
        (puthash key (reverse tokens) jetpacs-org--token-sets)
        (nreverse tokens)))))

(cl-defun jetpacs-org-token-ref (token &key owner)
  "TOKEN -> its ref plist, or nil.
nil for an unknown token, an owner mismatch, a swept set, or a
non-string TOKEN — all of which a handler answers as `stale' (14.5:
the list moved under the user; re-present, never mis-jump).  The
handler distinguishes arg-SHAPE errors (`rejected') itself."
  (when (stringp token)
    (let ((owner (or owner jetpacs-current-owner))
          (entry (gethash token jetpacs-org--tokens)))
      (when (and entry (equal (plist-get entry :owner) owner))
        (plist-get entry :ref)))))

(defun jetpacs-org--on-teardown (owner)
  "Sweep OWNER's token sets with its registration (live-reload hygiene)."
  (let (dead)
    (maphash (lambda (key _tokens)
               (when (equal (car key) owner) (push key dead)))
             jetpacs-org--token-sets)
    (dolist (key dead)
      (dolist (token (gethash key jetpacs-org--token-sets))
        (remhash token jetpacs-org--tokens))
      (remhash key jetpacs-org--token-sets))))

(add-hook 'jetpacs-teardown-functions #'jetpacs-org--on-teardown)

;;;; Mutations

(defvar-local jetpacs-org--save-timer nil
  "This buffer's pending deferred save, or nil.  ONE per buffer: the
poc armed a fresh timer per mutation — ten taps, ten timers, nine
no-op wakeups all holding the buffer.")

(defun jetpacs-org--save-now (buf)
  "The deferred save body: save BUF, refusing loudly where the stock
path would PROMPT — `basic-save-buffer' raises `yes-or-no-p' on
supersession and `ask-user-about-lock' on a foreign lock, and a prompt
inside a timer wedges a daemon with nobody to answer it."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq jetpacs-org--save-timer nil)
      (when (buffer-modified-p)
        (cond
         ((not (verify-visited-file-modtime buf))
          (message "jetpacs-org: NOT saving %s — file changed on disk \
(resolve in Emacs, then save)" (buffer-name buf)))
         ((let ((lock (file-locked-p buffer-file-name)))
            (and lock (not (eq lock t))))
          (message "jetpacs-org: NOT saving %s — locked by another \
process" (buffer-name buf)))
         (t (save-buffer)))))))

(defun jetpacs-org-defer-save ()
  "Schedule ONE idle save for the current buffer."
  (unless (timerp jetpacs-org--save-timer)
    (setq jetpacs-org--save-timer
          (run-with-idle-timer 0.5 nil #'jetpacs-org--save-now
                               (current-buffer)))))

(defmacro jetpacs-org-with-mutation (ref namespace &rest body)
  "Resolve REF, run BODY at its heading widened, bust NAMESPACE, defer save.
Widening is load-bearing: the poc mutated without it, and a narrowed
buffer whose restriction excluded the marker silently edited the wrong
position.  The marker is released after use."
  (declare (indent 2))
  `(let ((marker (jetpacs-org-resolve-ref ,ref)))
     (unwind-protect
         (with-current-buffer (marker-buffer marker)
           (org-with-wide-buffer
            (goto-char marker)
            (prog1 (progn ,@body)
              (jetpacs-org-cache-invalidate ,namespace)
              (jetpacs-org-defer-save))))
       (set-marker marker nil))))

(defun jetpacs-org-set-property (ref namespace prop value)
  "Set PROP to VALUE on the heading at REF."
  (jetpacs-org-with-mutation ref namespace
    (org-entry-put (point) prop value)))

(defun jetpacs-org-toggle-todo (ref namespace &optional state)
  "Set the TODO state at REF to STATE, or toggle if nil.
Flushes org's state/repeat log note inline — `org-todo' queues it onto
`post-command-hook' (via `org-add-log-setup'), which never fires here:
a phone action runs inside the socket process filter, not the command
loop.  The flush is GATED on `org-log-note-how' being `time' or
`state': only those store immediately (org 9.7 `org-add-log-note'
branches on exactly that set) — every other kind pops a modal
*Org Note* buffer waiting for a C-c C-c the device can never send,
while `save-window-excursion' hides the damage and the LOGBOOK line is
never written.  For those kinds the pending note is CANCELLED instead
and the skip is surfaced; free-text notes arrive with JA-5's
capture_fields dialog."
  (jetpacs-org-with-mutation ref namespace
    (org-todo state)
    (when (bound-and-true-p org-log-setup)
      (if (and (boundp 'org-log-note-how)
               (memq org-log-note-how '(time state)))
          (save-window-excursion
            (let ((this-command org-log-note-this-command))
              (org-add-log-note)))
        ;; Cancel the deferred note outright: on a shared interactive
        ;; Emacs the hook WOULD later fire and pop *Org Note* into the
        ;; desktop user's face for a device action they never took.
        (remove-hook 'post-command-hook 'org-add-log-note)
        (setq org-log-setup nil)
        (message "jetpacs-org: log note skipped — %S needs interactive \
input (free-text notes arrive with the JA-5 dialog)"
                 (and (boundp 'org-log-note-how) org-log-note-how))))))

(defun jetpacs-org-set-planning (ref namespace which date-str)
  "Set the WHICH planning stamp at REF to DATE-STR.
WHICH is \"SCHEDULED\" or \"DEADLINE\"; an empty or nil DATE-STR
removes the stamp.  `org-add-planning-info' wants the type as a symbol,
and removal is the trailing remove-arg form — the string form and the
nonexistent `org-remove-planning-info' both signalled (pinned in ERT:
this is undocumented org behavior we depend on)."
  (let ((type (pcase (upcase (or which ""))
                ("SCHEDULED" 'scheduled)
                ("DEADLINE" 'deadline)
                (_ (user-error "Unsupported planning type: %s" which)))))
    (jetpacs-org-with-mutation ref namespace
      (if (or (null date-str) (string-empty-p date-str))
          (org-add-planning-info nil nil type)
        (org-add-planning-info type date-str)))))

;;;; Typed extraction

(defun jetpacs-org-entry-typed-value (prop type)
  "Extract the value of PROP at point according to TYPE.
TYPE is one of `text', `checkbox', `date', `enum', `number', `list'."
  (let ((val (org-entry-get (point) prop)))
    (pcase type
      ('checkbox (equal val "[X]"))
      ('date (and val (not (string-empty-p val)) val))
      ('number (and val (string-to-number val)))
      ('enum
       ;; A PROP_ALL constraint, when present, is enforced.
       (let ((allowed (org-entry-get (point) (concat prop "_ALL") t)))
         (if allowed
             (let ((options (split-string allowed "[ \t]+" t)))
               (if (member val options) val nil))
           (and val (not (string-empty-p val)) val))))
      ('list
       (and val (split-string val "[, \t]+" t)))
      (_ (or val "")))))

;;;; Query parser — the wire-facing grammar (O2)

(defconst jetpacs-org-ql-literals '(today nil t < <= > >= =)
  "Symbols with grammar meaning that vetting must not stringify.")

(defconst jetpacs-org-note-query-terms
  '(and or not todo done tags priority heading regexp property level
        scheduled deadline habit)
  "The head symbols of the built-in query grammar.
Doubles as the SPEC 23.2 allowlist for the sexp arm: a wire query may
name these heads and nothing else.")

(defconst jetpacs-org--query-max-depth 8)
(defconst jetpacs-org--query-max-nodes 128)

(defun jetpacs-org--read-query (q)
  "Read exactly ONE form from wire string Q, obarray-safely.
The read runs under a THROWAWAY obarray (the ebp.el E4b move): a bare
`read' on a wire string interns every distinct symbol in every query
ever sent into the global obarray, permanently — measured, not
theoretical.  `read-circle' is nil so #1=#1# dies as a reader error
instead of looping the interpreter.  Trailing content after the form is
refused: a smuggled second form must never parse as
accepted-and-ignored."
  (let* ((obarray (obarray-make))
         (read-circle nil)
         (parse (condition-case nil
                    (read-from-string q)
                  (error (user-error "Malformed query"))))
         (rest (string-trim (substring q (cdr parse)))))
    (unless (string-empty-p rest)
      (user-error "Malformed query (trailing content)"))
    (car parse)))

(defun jetpacs-org--vet-query (form)
  "Vet, normalize and RE-HOME sexp query FORM in one walk.
Output invariant: only globally interned allowlisted symbols
\(`jetpacs-org-note-query-terms' heads, `jetpacs-org-ql-literals',
the :on/:from/:to keywords), fresh strings, and integers — so the
throwaway-obarray symbols from `jetpacs-org--read-query' die here, and
the interpreter's fallthrough becomes an internal invariant.  Vetted by
NAME, replaced by the canonical global symbol.  `quote' wrappers are
unwrapped (the reader minted them from \\='(...) input); bare symbols
in argument position become strings, exactly as the poc normalizer
did.
Everything else — floats, vectors, records, byte-code objects (the
reader will happily mint one from #[...]), hash-table forms, stray
keywords — is refused outright, and cap violations never echo the
query (it is user data)."
  (let ((nodes 0))
    (cl-labels
        ((vet (x depth head-position)
           (when (> depth jetpacs-org--query-max-depth)
             (user-error "Query too deep"))
           (when (> (cl-incf nodes) jetpacs-org--query-max-nodes)
             (user-error "Query too large"))
           (cond
            ((consp x)
             ;; Unwrap 'FORM before treating the car as a head.
             (if (and (symbolp (car x))
                      (equal (symbol-name (car x)) "quote")
                      (consp (cdr x)))
                 (vet (cadr x) depth head-position)
               (unless (and (symbolp (car x)) (proper-list-p x))
                 (user-error "Malformed query clause"))
               (let* ((name (symbol-name (car x)))
                      (head (cl-find name jetpacs-org-note-query-terms
                                     :key #'symbol-name :test #'equal)))
                 (unless head
                   (user-error "Unsupported query term"))
                 (cons head
                       (mapcar (lambda (a) (vet a (1+ depth) nil))
                               (cdr x))))))
            ((stringp x) x)
            ((integerp x) x)
            ((symbolp x)
             (let ((name (symbol-name x)))
               (cond
                ((member name '(":on" ":from" ":to")) (intern name))
                ((cl-find name jetpacs-org-ql-literals
                          :key #'symbol-name :test #'equal))
                ((string-prefix-p ":" name)
                 (user-error "Unsupported query keyword"))
                ;; nil reads as the global nil (special), handled by the
                ;; literals branch above; any other symbol is data.
                (t name))))
            (t (user-error "Unsupported query value")))))
      (vet form 0 t))))

(defun jetpacs-org--query-tokens (q)
  "Split query Q on whitespace, keeping \"quoted phrases\" whole."
  (let ((pos 0) (tokens nil))
    (while (string-match "\"\\([^\"]*\\)\"\\|\\S-+" q pos)
      (push (or (match-string 1 q) (match-string 0 q)) tokens)
      (setq pos (match-end 0)))
    (nreverse tokens)))

(defun jetpacs-org-parse-query (query)
  "Parse the search QUERY string into a vetted query sexp, or nil if empty.
Accepts three input shapes:
- a query sexp:    (and (todo \"TODO\") (tags \"work\"))
- filter tokens:   todo:TODO,NEXT tags:work priority:A
- free text:       \"exact phrase\" or bare words
The sexp arm is wire-hardened (SPEC 23.2): obarray-safe read, head and
leaf allowlists, depth/size caps — see `jetpacs-org--vet-query'.  The
token and free-text arms never touch the reader.  Signals `user-error'
on anything malformed."
  (let ((q (string-trim (or query ""))))
    (cond
     ((string-empty-p q) nil)
     ((string-match-p "\\`'?(" q)
      (jetpacs-org--vet-query (jetpacs-org--read-query q)))
     (t
      (let ((clauses
             (mapcar
              (lambda (tok)
                (cond
                 ((string-prefix-p "todo:" tok)
                  `(todo ,@(split-string (substring tok 5) "," t)))
                 ((string-prefix-p "tags:" tok)
                  `(tags ,@(split-string (substring tok 5) "," t)))
                 ((string-prefix-p "priority:" tok)
                  `(priority ,@(split-string (substring tok 9) "," t)))
                 (t `(regexp ,(regexp-quote tok)))))
              (jetpacs-org--query-tokens q))))
        (if (cdr clauses) `(and ,@clauses) (car clauses)))))))

;;;; The query interpreter

(defun jetpacs-org--planning-day (spec)
  "Resolve a query date SPEC to an absolute day number."
  (cond
   ((eq spec 'today) (time-to-days (current-time)))
   ((integerp spec) (+ (time-to-days (current-time)) spec))
   ((stringp spec) (time-to-days (org-time-string-to-time spec)))
   (t (user-error "Unsupported query date %S" spec))))

(defun jetpacs-org--planning-match-spec (stamp args)
  "Match raw planning STAMP string against ARGS plist (:on / :from / :to).
Empty ARGS means mere presence of the stamp."
  (and (stringp stamp) (not (string-empty-p stamp))
       (let ((day (time-to-days (org-time-string-to-time stamp)))
             (on (plist-get args :on))
             (from (plist-get args :from))
             (to (plist-get args :to)))
         (and (or (not on) (equal day (jetpacs-org--planning-day on)))
              (or (not from) (>= day (jetpacs-org--planning-day from)))
              (or (not to) (<= day (jetpacs-org--planning-day to)))))))

(defun jetpacs-org--entry-priority ()
  "The priority character of the heading at point, or nil."
  (save-excursion (org-back-to-heading t) (nth 3 (org-heading-components))))

(defun jetpacs-org--matches-p (tree get)
  "Non-nil when the entry read through accessor GET matches query TREE.
The ONE interpreter of the built-in grammar.  GET is
\(funcall GET WHAT &rest ARGS) with WHAT one of:
  todo / done / tags / priority / title / level / property NAME /
  planning WHICH / habit / regexp-match RE.
The fallthrough is an INTERNAL invariant: `jetpacs-org--vet-query'
admits only interpretable heads, so an unsupported term here means a
caller bypassed `jetpacs-org-parse-query' with a hand-built tree."
  (pcase tree
    (`(and . ,cs) (cl-every (lambda (c) (jetpacs-org--matches-p c get)) cs))
    (`(or . ,cs) (and (cl-some (lambda (c) (jetpacs-org--matches-p c get)) cs) t))
    (`(not ,c) (not (jetpacs-org--matches-p c get)))
    (`(todo . ,kws)
     (let ((st (funcall get 'todo)))
       (and st (if kws (and (member st kws) t)
                 (not (funcall get 'done))))))
    (`(done) (and (funcall get 'done) t))
    (`(tags . ,tags)
     (let ((have (funcall get 'tags)))
       (if tags (and (cl-some (lambda (tg) (member tg have)) tags) t)
         (and have t))))
    (`(priority ,(and op (pred symbolp)) ,val)
     (let ((pr (funcall get 'priority))
           (want (if (stringp val) (string-to-char val) val)))
       ;; org urgency runs A > B > C — the higher priority is the
       ;; smaller character, so the comparator flips against the chars.
       (and pr (pcase op
                 ('< (> pr want)) ('<= (>= pr want))
                 ('> (< pr want)) ('>= (<= pr want))
                 ('= (= pr want))
                 (_ (user-error "Unsupported priority comparator %s" op))))))
    (`(priority . ,ps)
     (let ((pr (funcall get 'priority)))
       (if ps (and pr (member (char-to-string pr) ps) t)
         (and pr t))))
    (`(heading . ,texts)
     (let ((hl (or (funcall get 'title) ""))
           (case-fold-search t))
       (cl-every (lambda (s) (string-match-p (regexp-quote s) hl)) texts)))
    (`(regexp . ,res)
     (cl-every (lambda (re) (funcall get 'regexp-match re)) res))
    (`(property ,name . ,val)
     (let ((v (funcall get 'property name)))
       (if val (equal v (car val)) (and v t))))
    (`(level ,n) (eql (funcall get 'level) n))
    (`(level ,n ,m) (let ((l (funcall get 'level))) (and l (<= n l m))))
    (`(scheduled . ,args)
     (jetpacs-org--planning-match-spec (funcall get 'planning "SCHEDULED") args))
    (`(deadline . ,args)
     (jetpacs-org--planning-match-spec (funcall get 'planning "DEADLINE") args))
    (`(habit) (and (funcall get 'habit) t))
    (_ (user-error "Unsupported query term %S" tree))))

(defun jetpacs-org--point-get (what &rest args)
  "The grammar accessor over the org entry AT POINT."
  (pcase what
    ('todo (org-get-todo-state))
    ('done (let ((st (org-get-todo-state)))
             (and st (member st org-done-keywords) t)))
    ('tags (org-get-tags nil t))
    ('priority (jetpacs-org--entry-priority))
    ('title (nth 4 (org-heading-components)))
    ('level (org-current-level))
    ('property (org-entry-get (point) (car args)))
    ('planning (org-entry-get (point) (car args)))
    ;; `org-is-habit-p' tests only the STYLE=habit property; repeater
    ;; validity is enforced later by `org-habit-parse-todo'.
    ('habit (and (fboundp 'org-is-habit-p) (org-is-habit-p)))
    ('regexp-match
     ;; The point haystack is the entry's body up to the next heading.
     (let ((end (save-excursion (outline-next-heading) (point)))
           (case-fold-search t))
       (save-excursion (re-search-forward (car args) end t))))))

;; The vulpea arm is OPTIONAL: never required at load, entered only when
;; a caller hands us a note, gated by `jetpacs-org-vulpea-available-p'.
;; The "ext:" pseudo-file keeps `byte-compile-error-on-warn' honest
;; without vulpea on the load path (the sections/magit-section shape).
(declare-function vulpea-note-todo "ext:vulpea-note" (note))
(declare-function vulpea-note-closed "ext:vulpea-note" (note))
(declare-function vulpea-note-tags "ext:vulpea-note" (note))
(declare-function vulpea-note-priority "ext:vulpea-note" (note))
(declare-function vulpea-note-title "ext:vulpea-note" (note))
(declare-function vulpea-note-level "ext:vulpea-note" (note))
(declare-function vulpea-note-properties "ext:vulpea-note" (note))
(declare-function vulpea-note-deadline "ext:vulpea-note" (note))
(declare-function vulpea-note-scheduled "ext:vulpea-note" (note))
(declare-function vulpea-note-path "ext:vulpea-note" (note))
(declare-function vulpea-note-outline-path "ext:vulpea-note" (note))
(declare-function vulpea-db-query "ext:vulpea-db" (&optional pred))
(declare-function vulpea-db-query-by-directory "ext:vulpea-db" (dir &optional level))

(defun jetpacs-org--note-get (note what &rest args)
  "The grammar accessor over a `vulpea-note' NOTE (index only, no visit)."
  (pcase what
    ('todo (vulpea-note-todo note))
    ;; The index carries no per-file DONE keyword set: done-ness is a
    ;; global done keyword (falling back to the near-universal \"DONE\"
    ;; in a headless scan) or a CLOSED stamp.
    ('done (let ((s (vulpea-note-todo note)))
             (or (and s (member s (or org-done-keywords '("DONE"))) t)
                 (and (vulpea-note-closed note) t))))
    ('tags (vulpea-note-tags note))
    ;; vulpea priority may be a char (org's native form) or a string.
    ('priority (let ((p (vulpea-note-priority note)))
                 (cond ((null p) nil)
                       ((characterp p) p)
                       ((and (stringp p) (> (length p) 0)) (aref p 0))
                       (t (let ((s (format "%s" p)))
                            (and (> (length s) 0) (aref s 0)))))))
    ('title (vulpea-note-title note))
    ('level (vulpea-note-level note))
    ;; vulpea indexes drawer keys upper-cased; match case-insensitively.
    ('property (cdr (assoc-string (car args) (vulpea-note-properties note) t)))
    ('planning (let ((s (if (equal (car args) "DEADLINE")
                            (vulpea-note-deadline note)
                          (vulpea-note-scheduled note))))
                 (and (stringp s) s)))
    ('habit (equal "habit"
                   (cdr (assoc-string "STYLE" (vulpea-note-properties note) t))))
    ('regexp-match
     ;; The index haystack is title + properties — the body is not
     ;; indexed.  SEMANTIC DIFFERENCE from the point accessor, by design.
     (let ((hay (concat (or (vulpea-note-title note) "") " "
                        (mapconcat #'cdr (vulpea-note-properties note) " ")))
           (case-fold-search t))
       (string-match-p (car args) hay)))))

(defun jetpacs-org-entry-matches-p (tree)
  "Non-nil when the org entry at point matches query sexp TREE."
  (jetpacs-org--matches-p tree #'jetpacs-org--point-get))

(defun jetpacs-org-note-matches-p (tree note)
  "Non-nil when `vulpea-note' NOTE matches query sexp TREE.
The same grammar as `jetpacs-org-entry-matches-p', evaluated entirely
off the vulpea index (no file visit); the `regexp' term searches
title + properties here (the body is not indexed)."
  (jetpacs-org--matches-p
   tree (lambda (what &rest args) (apply #'jetpacs-org--note-get note what args))))

(defun jetpacs-org-note-query-supported-p (tree)
  "Non-nil when query sexp TREE uses only index-evaluable terms.
Empty (nil) TREE — no filter — is trivially supported."
  (pcase tree
    ('nil t)
    (`(and . ,cs) (cl-every #'jetpacs-org-note-query-supported-p cs))
    (`(or . ,cs) (cl-every #'jetpacs-org-note-query-supported-p cs))
    (`(not ,c) (jetpacs-org-note-query-supported-p c))
    (`(,head . ,_) (and (memq head jetpacs-org-note-query-terms) t))
    (_ nil)))

;;;; High-level query

(defun jetpacs-org--run-query (tree action)
  "Run vetted query TREE over the agenda files, calling ACTION at matches."
  (let (items)
    (org-map-entries
     (lambda ()
       (when (jetpacs-org-entry-matches-p tree)
         (push (funcall action) items)))
     nil 'agenda)
    (nreverse items)))

(defun jetpacs-org-query (namespace tree action)
  "Run query sexp TREE over the agenda files, calling ACTION at matches.
Results are cached under NAMESPACE.  ALWAYS the built-in interpreter:
the poc dispatched to `org-ql-select' when installed, which meant (a) a
permanently untested semantic fork whose results silently changed when
a package appeared, and (b) an arbitrary-code hand-off — org-ql
COMPILES query sexps.  If full org-ql is ever wanted, it enters as a
new, separately vetted entry point, never as an fboundp fork here."
  (when tree
    (jetpacs-org-with-cache namespace (format "%S" tree)
      (jetpacs-org--run-query tree action))))

;;;; Vulpea note index (optional engine)

(defun jetpacs-org-vulpea-available-p ()
  "Non-nil when the vulpea note index is loadable on this Emacs.
vulpea is never required at load; callers gate their index reads here.
Probing DOES load vulpea when present."
  (and (require 'vulpea nil t) (fboundp 'vulpea-db-query) t))

(defun jetpacs-org-vulpea-source-notes (source)
  "The `vulpea-note' records backing SOURCE, a scope plist.
SOURCE is one of:
  (:dir D)               -> the file-level notes of vault directory D;
  (:file F :heading H)   -> the id'd headings directly under H in F;
  (:file F)              -> the id'd level-1 headings of F.
Headings must already carry `:ID:' properties for the index to see
them.  Callers gate on `jetpacs-org-vulpea-available-p'."
  (let ((dir (plist-get source :dir))
        (file (plist-get source :file))
        (heading (plist-get source :heading)))
    (cond
     (dir (vulpea-db-query-by-directory (directory-file-name dir) 0))
     (file
      (let ((want (expand-file-name file)))
        (vulpea-db-query
         (lambda (n)
           (and (equal (expand-file-name (vulpea-note-path n)) want)
                (if heading
                    (equal (vulpea-note-outline-path n) (list heading))
                  (= (vulpea-note-level n) 1)))))))
     (t (user-error "Source needs :dir or :file: %S" source)))))

(defun jetpacs-org-vulpea-query (source &optional tree)
  "Notes of SOURCE matching query sexp TREE, off the vulpea index.
A nil TREE admits every note of the scope.  TREE must stay inside
`jetpacs-org-note-query-terms' — check
`jetpacs-org-note-query-supported-p' first."
  (let ((notes (jetpacs-org-vulpea-source-notes source)))
    (if tree
        (cl-remove-if-not (lambda (n) (jetpacs-org-note-matches-p tree n)) notes)
      notes)))

;;;; Reset (the test seam; wired into `jetpacs-test-reset-state')

(defun jetpacs-org-reset ()
  "Reset engine state: cache, stat memo, tokens (fresh nonce), timers."
  (clrhash jetpacs-org--cache)
  (setq jetpacs-org--stamp-memo nil)
  (clrhash jetpacs-org--tokens)
  (clrhash jetpacs-org--token-sets)
  (setq jetpacs-org--token-nonce (format "%08x" (random #x100000000))
        jetpacs-org--token-counter 0)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (timerp jetpacs-org--save-timer)
        (cancel-timer jetpacs-org--save-timer)
        (setq jetpacs-org--save-timer nil)))))

(defun jetpacs-org-unload-function ()
  "Unload hygiene."
  (remove-hook 'jetpacs-teardown-functions #'jetpacs-org--on-teardown)
  (jetpacs-org-reset)
  nil)

(provide 'jetpacs-org)
;;; jetpacs-org.el ends here
