;;; glasspane-notes.el --- Vulpea bridge: wikilink capf + backlinks + mentions -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The knowledge-arms rung, notes half (docs/PLAN-glasspane-app.md, G7):
;; the linking loop over vulpea's note database.  PKM 3 — typing "[["
;; in the device editor offers note titles through the ebp-complete
;; shadow-buffer bridge; accepting one inserts a full "[[id:…][Title]]"
;; link via the capf's `:ebp-insert-function' (SPEC 19.3 `insert').
;; PKM 4 — the detail screen grows Linked references / Outgoing links
;; and an on-demand Unlinked mentions scan with a one-tap
;; link.materialize.  Everything degrades to absent when vulpea isn't
;; installed — no errors, no empty chrome; the functional bar for the
;; vulpea-live paths is the device gate (G9).
;;
;; Retired against v1 (the plan's retirement list + G7 section):
;;
;; - The `jetpacs-defsource' "glasspane.notes" registration and its
;;   field-normalization pair (`--note-item'/`--source-query'): the
;;   binding/source layer is ratified dead with D-3
;;   (PLAN-jetpacs-apps.md); the graph query helpers survive below as
;;   plain functions feeding the builders.
;; - The mentions hash with its `pending'/`error' sentinels, the three
;;   manual `jetpacs-shell-push' calls, and the refresh-hook `clrhash':
;;   dissolved into `jetpacs-async' — the builder reads
;;   (STATUS . PAYLOAD) from the keyed loader, completion re-push is
;;   coalesced, and eviction rides the push cycle instead of a hook.
;; - `jetpacs-nav-item' (T2): the toolbar chip is a text button, the
;;   detail rail's own composition.
;; - Raw ref/mention alists in on-wire `:args' (S5/D-4): every
;;   tappable now carries a SPEC 23.1 token from a per-render
;;   replace-set mint; the mention edit-site (file/line/matched) rides
;;   INSIDE the minted ref and never crosses the wire.
;; - `(require 'jetpacs)'/`jetpacs-source'/`jetpacs-sync' (T2):
;;   `jetpacs-sync-shadow-setup-hook' is `ebp-complete-shadow-setup-hook'
;;   now, and the capf's `:jetpacs-insert-function' property is
;;   `:ebp-insert-function'.
;; - Load-time hook installation: verbs and hooks register through the
;;   `glasspane-notes-register' pair (the G0 gate contract).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'org)
(require 'ebp-org)
(require 'ebp-complete)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-apps)
(require 'jetpacs-async)
(require 'glasspane-org)
(require 'glasspane-ui)                 ; detail seam hooks

;; vulpea is never installed on the CI Emacs: `ext:' pseudo-files keep
;; `byte-compile-error-on-warn' honest with it absent (banked trap).
(declare-function vulpea-db-search-by-title "ext:vulpea-db-query")
(declare-function vulpea-db-query-by-links-some "ext:vulpea-db-query")
(declare-function vulpea-db-query-by-ids "ext:vulpea-db-query")
(declare-function vulpea-db-get-by-id "ext:vulpea-db-query")
(declare-function vulpea-db-query-stale-notes "ext:vulpea-db-query")
(declare-function vulpea-note-level "ext:vulpea-note")
(declare-function vulpea-note-unlinked-mentions-async "ext:vulpea-mentions")
(declare-function vulpea-note-id "ext:vulpea-note")
(declare-function vulpea-note-title "ext:vulpea-note")
(declare-function vulpea-note-path "ext:vulpea-note")
(declare-function vulpea-note-links "ext:vulpea-note")
(declare-function vulpea-note-aliases "ext:vulpea-note")

(defun glasspane-notes-available-p ()
  "Non-nil when the vulpea note database is usable.
The soft probe — `featurep', never `require': this file must not be
the thing that loads vulpea (the plan keeps v1's cheaper probe as app
policy; `jetpacs-org-vulpea-available-p' is the loading kind)."
  (and (featurep 'vulpea)
       (fboundp 'vulpea-db-search-by-title)))

;;;; PKM 3: wikilink completion

(defcustom glasspane-notes-completion-limit 20
  "Notes offered per wikilink completion request."
  :type 'integer :group 'jetpacs)

(defun glasspane-notes--matches (partial)
  "Vulpea notes whose title (or alias) matches PARTIAL, capped."
  (condition-case nil
      (seq-take (vulpea-db-search-by-title partial)
                glasspane-notes-completion-limit)
    (error nil)))

(defun glasspane-notes--wikilink-capf ()
  "Complete \"[[partial\" with note titles; insert full id links.
Candidates KEEP the \"[[\" so the device replaces the whole open
bracket with the link — the strip validates the prefix by position,
so the brackets must be part of it (the G7 rule)."
  (when (and (derived-mode-p 'org-mode)
             (glasspane-notes-available-p))
    (save-excursion
      (when (looking-back "\\[\\[\\([^][\n]*\\)"
                          (max (point-min) (- (point) 120)))
        (let* ((beg (match-beginning 0))
               (partial (match-string 1))
               (notes (glasspane-notes--matches partial))
               (table (mapcar (lambda (n)
                                (cons (concat "[[" (vulpea-note-title n)) n))
                              notes)))
          (when table
            (list beg (point)
                  ;; A function table owns its own matching: vulpea
                  ;; already filtered by PARTIAL case-insensitively, so
                  ;; every candidate passes.  try-completion (the
                  ;; :exclusive-no validation probe) must also succeed,
                  ;; or the capf wrapper discards this capf entirely.
                  (lambda (string _pred action)
                    (cond
                     ((eq action t) (mapcar #'car table))
                     ((null action) (and table string))
                     ((eq action 'lambda) (and (assoc string table) t))
                     ((eq action 'metadata)
                      '(metadata (category . glasspane-wikilink)))))
                  :annotation-function
                  (lambda (c)
                    (when-let* ((n (cdr (assoc c table))))
                      (file-name-nondirectory (vulpea-note-path n))))
                  :ebp-insert-function
                  (lambda (c)
                    (when-let* ((n (cdr (assoc c table))))
                      (format "[[id:%s][%s]]"
                              (vulpea-note-id n) (vulpea-note-title n))))
                  :exclusive 'no)))))))

(defun glasspane-notes--setup-shadow ()
  "Install the wikilink capf in an org shadow buffer (buffer-local,
front of the list) — completion stays scoped to device documents;
desktop org buffers are the user's own capf business."
  (when (derived-mode-p 'org-mode)
    (add-hook 'completion-at-point-functions
              #'glasspane-notes--wikilink-capf -10 t)))

;;;; Refs and the mint discipline (S5)

(defun glasspane-notes--note-ref (note)
  "The heading ref plist for vulpea NOTE (:id :file :headline), or nil.
No :pos — vulpea rows don't carry one and `ebp-org-resolve-ref' falls
through id → file+headline.  nil without a real path: the mint
requires the :file member (P1-12) and checks it against the org
roots."
  (let ((id (and (fboundp 'vulpea-note-id) (vulpea-note-id note)))
        (path (vulpea-note-path note))
        (title (vulpea-note-title note)))
    (when (and (stringp path) (not (string-empty-p path)))
      (append (when (and (stringp id) (not (string-empty-p id)))
                (list :id id))
              (list :file path)
              (when title (list :headline title))))))

(defun glasspane-notes--mint (refs set)
  "SPEC 23.1 tokens for REFS in the app scope's SET, nils on refusal.
One bulk replace-set mint per render; a nil REFS still sweeps the set
(the views precedent).  A path that left the org roots refuses at
MINT time — that CARD then degrades to untappable instead of taking
the section, or the render, down."
  ;; `ebp-org-ref-tokens' validates ATOMICALLY, so one mention outside
  ;; the roots would nil the WHOLE section AND — the signal landing
  ;; before the replace sweep — leave the PREVIOUS render's tokens
  ;; live.  Hence the pre-filter: only the allowed refs enter the one
  ;; atomic call (so the sweep still runs), and the rejects come back
  ;; as nils in their parallel positions.  The condition-case stays as
  ;; the last-resort net for everything the filter cannot foresee.
  (condition-case nil
      (let* ((allowed (mapcar (lambda (ref)
                                (let ((file (plist-get ref :file)))
                                  (and (stringp file)
                                       (ebp-org-file-allowed-p file))))
                              refs))
             (tokens (ebp-org-ref-tokens
                      (cl-loop for ref in refs
                               for ok in allowed
                               when ok collect ref)
                      :set set :owner "glasspane")))
        (mapcar (lambda (ok) (and ok (pop tokens))) allowed))
    (error (make-list (length refs) nil))))

(defun glasspane-notes--mint-sparse (refs set)
  "Like `glasspane-notes--mint' but REFS may contain nils.
Returns a token list parallel to REFS, nil where the ref was nil."
  (let ((tokens (glasspane-notes--mint (delq nil (copy-sequence refs))
                                       set)))
    (mapcar (lambda (r) (and r (pop tokens))) refs)))

(defun glasspane-notes--ref-id (ref)
  "REF's org ID: carried in the ref, or read from the heading itself.
Reader-built drill-in refs carry only file/pos, so a child heading
with an :ID: still gets its backlink section."
  (let ((id (plist-get ref :id)))
    (if (and (stringp id) (not (string-empty-p id)))
        id
      (condition-case nil
          (let ((marker (ebp-org-resolve-ref ref)))
            (unwind-protect
                (with-current-buffer (marker-buffer marker)
                  (org-with-wide-buffer
                   (goto-char marker)
                   (org-entry-get nil "ID")))
              (set-marker marker nil)))
        (error nil)))))

;;;; The note graph (plain query helpers — the retired source's guts)

(defun glasspane-notes--backlinks (id)
  "Notes that link TO ID (the linked-references set), or nil."
  (condition-case nil (vulpea-db-query-by-links-some (list id)) (error nil)))

(defun glasspane-notes--forward-links (id)
  "Notes that ID links out to via id-type links, resolved to note objects."
  (when-let* ((note (condition-case nil (vulpea-db-get-by-id id) (error nil)))
              (dest-ids (delq nil
                              (mapcar (lambda (l)
                                        (when (equal (plist-get l :type) "id")
                                          (plist-get l :dest)))
                                      (vulpea-note-links note)))))
    (condition-case nil (vulpea-db-query-by-ids dest-ids) (error nil))))

;;;; PKM 4: backlinks + unlinked mentions on the detail screen

(defvar glasspane-notes--mentions-scans (make-hash-table :test 'equal)
  "Note id -> how many times its mention scan was requested.
Written only by the notes.mentions handler (S2); absent means the
user never asked, and an unscanned note gets no mentions chrome and
no ripgrep — the battery-risk rule unchanged from v1.  The count is
part of the `jetpacs-async' key, so a re-tap re-runs the scan under a
fresh key.  Returning to a screen whose cache entry was swept re-runs
it too: the ask is per note, sweep economics are the loader's.")

(defconst glasspane-notes--link-ttl-s 86400
  "Queue ttl for an offline Link-it tap (T4: \"queue\" requires :ttl-s).
A mention link older than a day should be re-checked against a fresh
scan rather than replayed blind.")

(defun glasspane-notes--mentions-state (id)
  "The mention scan's (STATUS . MENTIONS) for note ID, nil if never asked.
STATUS is `pending'/`ready'/`error' from the keyed loader; the loader
starts on first ask from a build — never in the dispatch extent (D2)."
  (when-let* ((scan (gethash id glasspane-notes--mentions-scans)))
    (jetpacs-async
     (list 'glasspane-notes-mentions id scan)
     (lambda (resolve reject)
       (let ((note (and (fboundp 'vulpea-note-unlinked-mentions-async)
                        (fboundp 'vulpea-db-get-by-id)
                        (ignore-errors (vulpea-db-get-by-id id)))))
         (if (null note)
             (funcall reject "note missing from the index")
           (vulpea-note-unlinked-mentions-async
            note
            (lambda (mentions) (funcall resolve mentions))
            (lambda (_err)
              (funcall reject "ripgrep unavailable or the search failed")))
           nil)))
     :owner "glasspane")))

(defun glasspane-notes--mention-tap-ref (mention)
  "The heading.tap ref plist for MENTION's source note, or nil.
The path prefers the plist's own :path, with the mentioning note's
file as backstop (current vulpea resolve plists carry both shapes)."
  (let* ((source (plist-get mention :note))
         (path (or (plist-get mention :path)
                   (and source (vulpea-note-path source)))))
    (when (and (stringp path) (not (string-empty-p path)))
      (let ((id (and source (fboundp 'vulpea-note-id)
                     (vulpea-note-id source)))
            (title (if source (vulpea-note-title source)
                     (file-name-nondirectory path))))
        (append (when (and (stringp id) (not (string-empty-p id)))
                  (list :id id))
                (list :file path)
                (when title (list :headline title)))))))

(defun glasspane-notes--mention-edit-ref (mention target-id)
  "The link.materialize edit-site ref for MENTION into TARGET-ID, or nil.
Not a heading ref: :line/:matched/:target-id ride inside the minted
plist so the wire carries only the token (S5) — :matched is forwarded
when the scan named the hit text, and the handler falls back to the
note's title/aliases otherwise."
  (let* ((source (plist-get mention :note))
         (path (or (plist-get mention :path)
                   (and source (vulpea-note-path source))))
         (line (plist-get mention :line)))
    (when (and (stringp path) (not (string-empty-p path)) (integerp line))
      (list :file path :line line
            :matched (plist-get mention :matched)
            :target-id target-id))))

(defun glasspane-notes--note-card (note token)
  "A card for NOTE opening its heading in the detail view."
  (jetpacs-card
   (list (jetpacs-column
          (jetpacs-text (or (vulpea-note-title note) "") :style "body")
          (jetpacs-text (file-name-nondirectory
                         (or (vulpea-note-path note) ""))
                        :style "caption")))
   :on-tap (and token (jetpacs-action "heading.tap"
                                      :args (list :token token)))))

(defun glasspane-notes--mention-card (mention tap link)
  "A card for MENTION: context, a Link-it button (LINK token), a tap
into the mentioning note (TAP token).  Either token may be nil — a
refused mint costs the affordance, never the card."
  (let* ((source (plist-get mention :note))
         (path (or (plist-get mention :path)
                   (and source (vulpea-note-path source))))
         (title (if source (vulpea-note-title source)
                  (file-name-nondirectory (or path "")))))
    (jetpacs-card
     (list
      (jetpacs-column
       (jetpacs-text (or title "") :style "body")
       (jetpacs-text (or (plist-get mention :context) "") :style "caption")
       (jetpacs-row
        (jetpacs-spacer :weight 1)
        (and link
             (jetpacs-button "Link it"
                             (jetpacs-action "link.materialize"
                                             :args (list :token link)
                                             :when-offline "queue"
                                             :ttl-s glasspane-notes--link-ttl-s)
                             :variant "text" :icon "link")))))
     :on-tap (and tap (jetpacs-action "heading.tap"
                                      :args (list :token tap))))))

(defun glasspane-notes-detail-nodes (ref)
  "Backlink/outgoing/mentions section nodes for the detail REF, or nil.
Contributed to `glasspane-ui-detail-nodes-functions'; runs once per
detail render, so ONE bulk mint replaces the notes-detail set each
time — swept sheets answer stale for free (S5)."
  (when-let* (((glasspane-notes-available-p))
              (id (glasspane-notes--ref-id ref)))
    (let* ((backlinks (glasspane-notes--backlinks id))
           (forward (glasspane-notes--forward-links id))
           (state (glasspane-notes--mentions-state id))
           (mentions (and (eq (car-safe state) 'ready) (cdr state)))
           (fwd-refs (mapcar #'glasspane-notes--note-ref forward))
           (back-refs (mapcar #'glasspane-notes--note-ref backlinks))
           (mention-refs
            (cl-loop for m in mentions
                     append (list (glasspane-notes--mention-tap-ref m)
                                  (glasspane-notes--mention-edit-ref m id))))
           (tokens (glasspane-notes--mint-sparse
                    (append fwd-refs back-refs mention-refs)
                    "notes-detail"))
           (fwd-toks (cl-subseq tokens 0 (length fwd-refs)))
           (back-toks (cl-subseq tokens (length fwd-refs)
                                 (+ (length fwd-refs) (length back-refs))))
           (mention-toks (nthcdr (+ (length fwd-refs) (length back-refs))
                                 tokens)))
      (append
       (list (jetpacs-divider)
             (jetpacs-collapsible
              (jetpacs-wire-id "gp-notes-fwd" id)
              (jetpacs-section-header
               (format "Outgoing links (%d)" (length forward)))
              (or (cl-mapcar #'glasspane-notes--note-card forward fwd-toks)
                  (list (jetpacs-text "No outgoing links." :style "caption")))
              :collapsed (jetpacs-bool (null forward)))
             (jetpacs-collapsible
              (jetpacs-wire-id "gp-notes-back" id)
              (jetpacs-section-header
               (format "Linked references (%d)" (length backlinks)))
              (or (cl-mapcar #'glasspane-notes--note-card backlinks back-toks)
                  (list (jetpacs-text "Nothing links here yet."
                                      :style "caption")))
              :collapsed (jetpacs-bool (null backlinks))))
       ;; The mentions section only exists once a scan has been asked
       ;; for (the toolbar chip) — an unscanned note gets no chrome.
       (when state
         (list (jetpacs-collapsible
                (jetpacs-wire-id "gp-notes-mentions" id)
                (jetpacs-section-header
                 (pcase (car state)
                   ('pending "Unlinked mentions (searching…)")
                   ('error "Unlinked mentions (search failed)")
                   (_ (format "Unlinked mentions (%d)" (length mentions)))))
                (pcase (car state)
                  ('pending (list (jetpacs-progress :variant "linear")))
                  ('error (list (jetpacs-text (cdr state) :style "caption")))
                  (_ (if (null mentions)
                         (list (jetpacs-text "No unlinked mentions."
                                             :style "caption"))
                       (cl-loop for m in mentions
                                for (tap edit) on mention-toks by #'cddr
                                collect (glasspane-notes--mention-card
                                         m tap edit))))))))))))

(defun glasspane-notes-detail-toolbar (ref)
  "The Mentions chip for the detail floating toolbar, or nil.
The chip carries a token from its own per-render set — never the note
id raw (S5; the chip joins the detail screen's mint discipline).
Chip only when the heading actually has an org ID: a scan without one
has nothing to search for."
  (when-let* (((glasspane-notes-available-p))
              ((glasspane-notes--ref-id ref))
              (token (car (glasspane-notes--mint (list ref)
                                                 "notes-toolbar"))))
    (list (jetpacs-button "Mentions"
                          (jetpacs-action "notes.mentions"
                                          :args (list :token token))
                          :icon "manage_search" :variant "text"))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-notes--on-mentions (args params)
  "Handler for notes.mentions: mark the scan wanted, defer the re-push.
The re-render's builder starts the keyed ripgrep loader — start-on-
first-ask is builder-side by design, so the dispatch extent never
blocks (D2).  The wanted-mark is the durable effect."
  ;; The S4 gate order every handler in this file follows, and the srs
  ;; sibling with it: shape -> stale -> exposure -> grant.  The token
  ;; lookup precedes the availability probe so a token the replace
  ;; sweep already retired answers `stale' — what it IS — instead of
  ;; borrowing the absent engine's `rejected'.
  (let ((token (plist-get args :token)))
    (if (not (stringp token))
        'rejected
      (let ((ref (ebp-org-token-ref token :owner "glasspane")))
        (cond
         ((null ref) 'stale)
         ((not (and (glasspane-notes-available-p)
                    (fboundp 'vulpea-note-unlinked-mentions-async)))
          'rejected)
         (t
          (let ((id (glasspane-notes--ref-id ref)))
            (if (null id)
                'stale                  ; the :ID: left with an edit
              (puthash id (1+ (gethash id glasspane-notes--mentions-scans 0))
                       glasspane-notes--mentions-scans)
              (jetpacs-app-defer-refresh params)
              'accepted))))))))

(defun glasspane-notes--materialize-terms (id matched)
  "The strings to look for on the mention line, most specific first.
MATCHED when the scan carried it; otherwise the note's title and
aliases — current vulpea mention plists name the note but not the
matched text, so the fallback is what makes Link-it work at all."
  (if (and (stringp matched) (not (string-empty-p matched)))
      (list matched)
    (when-let* ((note (and (glasspane-notes-available-p)
                           (fboundp 'vulpea-db-get-by-id)
                           (ignore-errors (vulpea-db-get-by-id id)))))
      (delq nil (cons (vulpea-note-title note)
                      (and (fboundp 'vulpea-note-aliases)
                           (ignore-errors (vulpea-note-aliases note))))))))

(defun glasspane-notes--find-unlinked (terms end)
  "Move point to the first occurrence of a TERMS member before END.
Case-insensitive; leaves the match data on the hit and returns the
term, or nil.  Occurrences already inside an org link are skipped —
the file may have changed since the mention scan, and a stale tap
must not nest a link inside a link."
  (let ((case-fold-search t)
        (start (point)))
    (cl-loop for term in terms
             do (goto-char start)
             thereis (cl-loop while (search-forward term end t)
                              unless (save-match-data
                                       (save-excursion
                                         (goto-char (match-beginning 0))
                                         (org-in-regexp org-link-any-re)))
                              return term))))

(defun glasspane-notes--materialize (ref params)
  "The resolved link.materialize body; returns the SPEC 14.4 status.
Replaces the first UN-linked occurrence of the mention on REF's line
with a real id link.  Matching is case-insensitive (search UX); the
replacement keeps the text exactly as written in the file.  Every
failure answers with a snackbar — a tap that silently does nothing is
a bug class, not an outcome (v1's rule, kept)."
  (let* ((path (plist-get ref :file))
         (line (plist-get ref :line))
         (target (plist-get ref :target-id))
         (terms (glasspane-notes--materialize-terms
                 target (plist-get ref :matched)))
         (status 'rejected))
    (cond
     ((null terms)
      (jetpacs-shell-notify "Couldn't link — mention data incomplete"))
     ((not (and (ebp-org-file-allowed-p path) (file-writable-p path)))
      (jetpacs-shell-notify (format "Couldn't link — %s not writable"
                                    (file-name-nondirectory path))))
     (t
      (condition-case err
          (with-current-buffer (find-file-noselect path)
            (org-with-wide-buffer
             (goto-char (point-min))
             (forward-line (1- line))
             (if (not (glasspane-notes--find-unlinked
                       terms (line-end-position)))
                 (progn
                   ;; The file moved under the scan: 14.5, re-present.
                   (setq status 'stale)
                   (jetpacs-shell-notify
                    "Couldn't find the mention — file changed? Refresh and retry"))
               (replace-match (format "[[id:%s][%s]]" target (match-string 0))
                              t t)
               (glasspane-org-save-and-invalidate)
               ;; The shown scan is out of date now; the section
               ;; returns to unscanned until the next chip tap (v1's
               ;; post-link behavior).
               (remhash target glasspane-notes--mentions-scans)
               (setq status 'accepted)
               (jetpacs-shell-notify "Linked"))))
        (error
         ;; The raw error stays in *Messages*; the wire never carries
         ;; it (SPEC 23.3).
         (message "glasspane: link.materialize failed: %s"
                  (jetpacs-error-label err))
         (jetpacs-shell-notify "Couldn't link — the edit failed")
         (setq status 'rejected)))))
    (jetpacs-app-defer-refresh params)
    status))

(defun glasspane-notes--on-materialize (args params)
  "Handler for link.materialize: token -> edit-site ref -> the edit.
A heading token replayed here (no :line/:target-id in its ref) is a
shape error, not a miss."
  (let ((token (plist-get args :token)))
    (if (not (stringp token))
        'rejected
      (let ((ref (ebp-org-token-ref token :owner "glasspane")))
        (cond
         ((null ref) 'stale)
         ((not (glasspane-notes-available-p)) 'rejected)
         ((not (and (stringp (plist-get ref :file))
                    (integerp (plist-get ref :line))
                    (stringp (plist-get ref :target-id))))
          'rejected)
         (t (glasspane-notes--materialize ref params)))))))

;;;; Stale files: the vulpea half of the Review screen
;;
;; `vulpea-db-query-stale-notes' joins the files table's real mtime; a
;; file leaves the list only when its content actually changes (a bare
;; touch is skipped by vulpea's hash check at sync).  Tap opens the
;; note — editing it is what marks it reviewed.  Consumed by the SRS
;; sibling's Review screen (G7's other half).

(defcustom glasspane-notes-stale-days 90
  "Days without modification before a note file counts as stale.
The Review screen lists these for a look-over."
  :type 'integer :group 'jetpacs)

(defconst glasspane-notes--stale-cap 20
  "Stale files shown at once (the oldest); the rest wait their turn.")

(defun glasspane-notes-stale-available-p ()
  "Non-nil when the stale-files query is usable (vulpea new enough)."
  (and (glasspane-notes-available-p)
       (fboundp 'vulpea-db-query-stale-notes)))

(defun glasspane-notes--stale-notes ()
  "The oldest stale note per file, oldest file first, capped.
The query returns every note in a stale file (heading-level notes
share the file's mtime); one card per file is the useful grain, and
the file-level (level 0) note names the file best when present."
  (when (glasspane-notes-stale-available-p)
    (condition-case nil
        (let ((by-path (make-hash-table :test 'equal))
              (order nil))
          (dolist (note (vulpea-db-query-stale-notes
                         glasspane-notes-stale-days))
            (let* ((path (vulpea-note-path note))
                   (seen (gethash path by-path)))
              (unless seen (push path order))
              (when (or (not seen)
                        (eql 0 (ignore-errors (vulpea-note-level note))))
                (puthash path note by-path))))
          (seq-take (mapcar (lambda (p) (gethash p by-path)) (nreverse order))
                    glasspane-notes--stale-cap))
      (error nil))))

(defun glasspane-notes--age-caption (path)
  "\"modified N days/months/years ago\" from PATH's filesystem mtime, or nil."
  (when-let* ((attrs (file-attributes path))
              (days (floor (- (float-time)
                              (float-time
                               (file-attribute-modification-time attrs)))
                           86400)))
    (cond
     ((< days 60) (format "modified %d days ago" days))
     ((< days 730) (format "modified %d months ago" (floor days 30)))
     (t (format "modified %d years ago" (floor days 365))))))

(defun glasspane-notes--stale-card (note token)
  "A card for stale NOTE: title, file, and how long untouched."
  (let* ((path (vulpea-note-path note))
         (age (glasspane-notes--age-caption path)))
    (jetpacs-card
     (list (jetpacs-column
            (jetpacs-text (or (vulpea-note-title note) "") :style "body")
            (jetpacs-text (concat (file-name-nondirectory (or path ""))
                                  (when age (concat " · " age)))
                          :style "caption")))
     :on-tap (and token (jetpacs-action "heading.tap"
                                        :args (list :token token))))))

(defun glasspane-notes-stale-section ()
  "Section nodes for the stale-files review, or nil when vulpea is absent.
One replace-set mint per render, like every other list here (S5)."
  (when (glasspane-notes-stale-available-p)
    (let* ((notes (glasspane-notes--stale-notes))
           (tokens (glasspane-notes--mint-sparse
                    (mapcar #'glasspane-notes--note-ref notes)
                    "notes-stale")))
      (if (null notes)
          (list (jetpacs-section-header "Stale files")
                (jetpacs-text (format "Nothing untouched for %d+ days."
                                      glasspane-notes-stale-days)
                              :style "caption"))
        (append
         (list (jetpacs-section-header "Stale files")
               (jetpacs-text (format "Untouched for %d+ days — oldest first."
                                     glasspane-notes-stale-days)
                             :style "caption"))
         (cl-mapcar #'glasspane-notes--stale-card notes tokens))))))

;;;; Registration

(defconst glasspane-notes--verbs '("notes.mentions" "link.materialize")
  "The verbs this module owns, for the register/unregister sweep.")

(defun glasspane-notes-register ()
  "Register the notes verbs, the detail seam hooks, and the capf hook.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "notes.mentions" #'glasspane-notes--on-mentions
                       :doc "Scan for unlinked mentions of a note (async ripgrep)")
    (jetpacs-defaction "link.materialize" #'glasspane-notes--on-materialize
                       :doc "Replace a scanned mention with a real id link"))
  (add-hook 'glasspane-ui-detail-nodes-functions
            #'glasspane-notes-detail-nodes)
  (add-hook 'glasspane-ui-detail-toolbar-functions
            #'glasspane-notes-detail-toolbar)
  (add-hook 'ebp-complete-shadow-setup-hook
            #'glasspane-notes--setup-shadow))

(defun glasspane-notes-unregister ()
  "Drop the notes verbs and hook claims.
The scan marks go too: a fresh registration owes no ripgrep to old
taps.  Nothing here clears the async cache — `jetpacs-async-clear-owner'
runs only from `jetpacs-teardown-owner', which this path never
reaches; the mention entries die on their own when a push generation
goes by without a build asking for them."
  (dolist (name glasspane-notes--verbs)
    (jetpacs-undefaction name))
  (remove-hook 'glasspane-ui-detail-nodes-functions
               #'glasspane-notes-detail-nodes)
  (remove-hook 'glasspane-ui-detail-toolbar-functions
               #'glasspane-notes-detail-toolbar)
  (remove-hook 'ebp-complete-shadow-setup-hook
               #'glasspane-notes--setup-shadow)
  (clrhash glasspane-notes--mentions-scans))

(provide 'glasspane-notes)
;;; glasspane-notes.el ends here
