;;; glasspane-notes.el --- Vulpea bridge: wikilink completion + backlinks -*- lexical-binding: t; -*-

;; The linking loop over vulpea's note database (the PKM engine
;; decision — vulpea v2, org-roam as fallback never materialized):
;;
;;   PKM 3 — typing "[[" in the phone editor offers note titles from
;;   the vulpea index through the existing capf bridge; accepting one
;;   inserts a full "[[id:…][Title]]" link (the candidate `insert'
;;   attr, SPEC §8).
;;
;;   PKM 4 — the heading detail view grows "Linked references" (notes
;;   linking here, from the db) and on-demand "Unlinked mentions"
;;   (vulpea's async ripgrep pass) with a one-tap link.materialize.
;;
;; Everything degrades to absent when vulpea isn't installed or has no
;; database yet — no errors, no empty chrome.  The starter init
;; installs vulpea and enables `vulpea-db-autosync-mode'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-source)
(require 'jetpacs-shell)
(require 'jetpacs-sync)
(require 'glasspane-org)

(declare-function vulpea-db-search-by-title "vulpea-db-query")
(declare-function vulpea-db-query-by-links-some "vulpea-db-query")
(declare-function vulpea-db-query-by-ids "vulpea-db-query")
(declare-function vulpea-db-get-by-id "vulpea-db-query")
(declare-function vulpea-note-unlinked-mentions-async "vulpea-mentions")
(declare-function vulpea-note-id "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-path "vulpea-note")
(declare-function vulpea-note-tags "vulpea-note")
(declare-function vulpea-note-links "vulpea-note")
(declare-function vulpea-note-aliases "vulpea-note")

(defun glasspane-notes-available-p ()
  "Non-nil when the vulpea note database is usable."
  (and (featurep 'vulpea)
       (fboundp 'vulpea-db-search-by-title)))

;; ─── PKM 3: wikilink completion ──────────────────────────────────────────────

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
Candidates keep the \"[[\" so the phone replaces the whole open
bracket with the link (the strip validates the prefix by position,
so the brackets must be part of it)."
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
                    (when-let ((n (cdr (assoc c table))))
                      (file-name-nondirectory (vulpea-note-path n))))
                  :jetpacs-insert-function
                  (lambda (c)
                    (when-let ((n (cdr (assoc c table))))
                      (format "[[id:%s][%s]]"
                              (vulpea-note-id n) (vulpea-note-title n))))
                  :exclusive 'no)))))))

;; The capf bridge builds shadow buffers through this hook; installing
;; the capf there (buffer-locally, front of the list) keeps wikilink
;; completion scoped to the phone editor — desktop org buffers are the
;; user's own capf business.
(defun glasspane-notes--setup-shadow ()
  (when (derived-mode-p 'org-mode)
    (add-hook 'completion-at-point-functions
              #'glasspane-notes--wikilink-capf -10 t)))

(add-hook 'jetpacs-sync-shadow-setup-hook #'glasspane-notes--setup-shadow)

;; ─── PKM 4: backlinks + unlinked mentions ────────────────────────────────────

(defvar glasspane-notes--mentions (make-hash-table :test 'equal)
  "Note id -> computed unlinked-mentions list, `pending', or `error'.
Dropped wholesale by the cache seam.")

(defun glasspane-notes--note-ref (note)
  "The heading.tap REF alist for vulpea NOTE — id/file/headline, no pos.
nil-valued cells are pruned so the ref serialises cleanly to JSON."
  (let ((id (and (fboundp 'vulpea-note-id) (vulpea-note-id note)))
        (path (vulpea-note-path note))
        (title (vulpea-note-title note)))
    (delq nil
          (list (when (and id (stringp id) (not (string-empty-p id))) `(id . ,id))
                (when path `(file . ,path))
                (when title `(headline . ,title))))))

(defun glasspane-notes--note-card (note)
  "A tappable card for NOTE (opens its heading in the detail view)."
  (let ((title (vulpea-note-title note))
        (path (vulpea-note-path note))
        (ref (glasspane-notes--note-ref note)))
    (jetpacs-card
     (list (jetpacs-column
            (jetpacs-text title 'body)
            (jetpacs-text (file-name-nondirectory path) 'caption)))
     :on-tap (when ref
               (jetpacs-action "heading.tap" :args ref :when-offline "drop")))))

(defun glasspane-notes--mention-card (mention note-id)
  "A card for MENTION (a :note :path :line :context plist).
Current vulpea resolve plists don't carry :matched (the exact text the
scan hit) — it is forwarded when present, and link.materialize falls
back to the note's title/aliases otherwise.  The path prefers the
plist's own :path, with the mentioning note's file as backstop."
  (let* ((source (plist-get mention :note))
         (path (or (plist-get mention :path)
                   (and source (vulpea-note-path source))))
         (id (and source (fboundp 'vulpea-note-id) (vulpea-note-id source)))
         (title (if source (vulpea-note-title source)
                  (file-name-nondirectory (or path ""))))
         (ref (delq nil
                    (list (when (and id (stringp id) (not (string-empty-p id))) `(id . ,id))
                          (when path `(file . ,path))
                          (when title `(headline . ,title))))))
    (jetpacs-card
     (list
      (jetpacs-column
       (jetpacs-text title 'body)
       (jetpacs-text (or (plist-get mention :context) "") 'caption)
       (jetpacs-row
        (jetpacs-spacer :weight 1)
        (jetpacs-button "Link it"
                     (jetpacs-action "link.materialize"
                                  :args `((id . ,note-id)
                                          (path . ,path)
                                          (line . ,(plist-get mention :line))
                                          (matched . ,(plist-get mention :matched)))
                                  :when-offline "queue")
                     :variant "text" :icon "link"))))
     :on-tap (when ref
               (jetpacs-action "heading.tap" :args ref :when-offline "drop")))))

(defun glasspane-notes--ref-id (ref)
  "REF's org ID: carried in the ref, or read from the heading itself.
Reader-built drill-in refs carry only file/pos, so a child heading
with an :ID: still gets its backlink section."
  (or (alist-get 'id ref)
      (condition-case nil
          (let ((marker (jetpacs-org-resolve-ref ref)))
            (with-current-buffer (marker-buffer marker)
              (org-with-wide-buffer
               (goto-char marker)
               (org-entry-get nil "ID"))))
        (error nil))))

;; ─── The notes data source (composer-bindable note graph) ────────────────────
;;
;; The synchronous half of the note graph — backlinks and outgoing (forward)
;; links — exposed as a `jetpacs-defsource' over vulpea's db-query, normalized
;; to the domain-neutral field contract.  This is the data a `:spec' view (or
;; the no-code composer) binds; Glasspane's own detail rendering stays a
;; `:builder' that leans on the same helpers.  Unlinked mentions are the async
;; ripgrep pass and don't fit a synchronous source, so they stay builder-side.

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

(defun glasspane-notes--note-item (note)
  "Normalize vulpea NOTE to the \"glasspane.notes\" canonical fields."
  (let ((path (vulpea-note-path note)))
    (list (cons 'id        (vulpea-note-id note))
          (cons 'title     (vulpea-note-title note))
          (cons 'path      path)
          (cons 'file_name (and path (file-name-nondirectory path)))
          (cons 'tags      (append (and (fboundp 'vulpea-note-tags)
                                        (vulpea-note-tags note))
                                   nil))
          (cons 'ref       (glasspane-notes--note-ref note)))))

(defun glasspane-notes--source-query (params)
  "The \"glasspane.notes\" :query: a RELATION over a note ID -> canonical items.
RELATION is \"backlinks\" (default) or \"outgoing\".  Yields no items when
vulpea is unavailable or ID is blank — never an error."
  (let ((id (alist-get 'id params))
        (relation (or (alist-get 'relation params) "backlinks")))
    (when (and (stringp id) (not (string-empty-p id)) (glasspane-notes-available-p))
      (mapcar #'glasspane-notes--note-item
              (pcase relation
                ("outgoing" (glasspane-notes--forward-links id))
                (_          (glasspane-notes--backlinks id)))))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defsource "glasspane.notes"
    :params '((:name id       :type "text" :required t)
              (:name relation :type "enum" :values ["backlinks" "outgoing"]))
    :fields '((:name "id"        :type "text")
              (:name "title"     :type "text")
              (:name "path"      :type "text")
              (:name "file_name" :type "text")
              (:name "tags"      :type "string-list")
              (:name "ref"       :type "ref"))
    :query #'glasspane-notes--source-query))

(defun glasspane-notes-detail-nodes (ref)
  "Backlink section nodes for the detail REF (needs an org ID), or nil."
  (when-let* (((glasspane-notes-available-p))
              (id (glasspane-notes--ref-id ref)))
    (let* ((backlinks (glasspane-notes--backlinks id))
           (forward-links (glasspane-notes--forward-links id))
           (mentions (gethash id glasspane-notes--mentions 'unfetched)))
      (append
       (list (jetpacs-divider)
             (jetpacs-collapsible
              (concat "forwardlinks/" id)
              (jetpacs-section-header
               (format "Outgoing links (%d)" (length forward-links)))
              (or (mapcar #'glasspane-notes--note-card forward-links)
                  (list (jetpacs-text "No outgoing links." 'caption)))
              :collapsed (null forward-links)))
       (list (jetpacs-collapsible
              (concat "backlinks/" id)
              (jetpacs-section-header
               (format "Linked references (%d)" (length backlinks)))
              (or (mapcar #'glasspane-notes--note-card backlinks)
                  (list (jetpacs-text "Nothing links here yet." 'caption)))
              :collapsed (null backlinks)))
       (list (jetpacs-collapsible
              (concat "mentions/" id)
              (jetpacs-section-header
               (pcase mentions
                 ('unfetched "Unlinked mentions")
                 ('pending "Unlinked mentions (searching…)")
                 ('error "Unlinked mentions (search failed)")
                 (found (format "Unlinked mentions (%d)" (length found)))))
              (pcase mentions
                ('unfetched
                 (list (jetpacs-button
                        "Find mentions"
                        (jetpacs-action "notes.mentions" :args `((id . ,id))
                                     :when-offline "drop")
                        :variant "text" :icon "manage_search")))
                ('pending (list (jetpacs-progress :variant "linear")))
                ('error (list (jetpacs-text "ripgrep unavailable or the search failed."
                                         'caption)))
                ('nil (list (jetpacs-text "No unlinked mentions." 'caption)))
                (found (mapcar (lambda (m)
                                 (glasspane-notes--mention-card m id))
                               found)))
              :collapsed (eq mentions 'unfetched)))))))

;; The mention grep is the battery-risk item: computed only on the
;; explicit button tap, cached per note, dropped by the standard seam.
(jetpacs-defaction "notes.mentions"
  (lambda (args _)
    (let ((id (alist-get 'id args)))
      (when (and (stringp id) (glasspane-notes-available-p)
                 (fboundp 'vulpea-note-unlinked-mentions-async))
        (when-let ((note (vulpea-db-get-by-id id)))
          (puthash id 'pending glasspane-notes--mentions)
          (vulpea-note-unlinked-mentions-async
           note
           (lambda (mentions)
             (puthash id mentions glasspane-notes--mentions)
             (jetpacs-shell-push))
           (lambda (_err)
             (puthash id 'error glasspane-notes--mentions)
             (jetpacs-shell-push)))
          (jetpacs-shell-push)))))
  :doc "Scan for unlinked mentions of a note (async ripgrep)."
  :args '((:name id :type "text" :required t)))

(defun glasspane-notes--materialize-terms (id matched)
  "The strings to look for on the mention line, most specific first.
MATCHED when the wire carried it; otherwise the note's title and
aliases — current vulpea mention plists name the note but not the
matched text, so the fallback is what makes \"Link it\" work at all."
  (if (and (stringp matched) (not (string-empty-p matched)))
      (list matched)
    (when-let ((note (and (glasspane-notes-available-p)
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

(jetpacs-defaction "link.materialize"
  ;; Replace the first un-linked occurrence of the mention on LINE in
  ;; PATH with a real id link.  Matching is case-insensitive (search
  ;; UX); the replacement keeps the text exactly as written in the
  ;; file.  Every failure path answers with a snackbar — a tap that
  ;; silently does nothing is a bug class, not an outcome.
  (lambda (args _)
    (let* ((id (alist-get 'id args))
           (path (alist-get 'path args))
           (line (alist-get 'line args))
           (terms (and (stringp id)
                       (glasspane-notes--materialize-terms
                        id (alist-get 'matched args)))))
      (cond
       ((not (and (stringp id) (stringp path) (integerp line) terms))
        (jetpacs-shell-notify "Couldn't link — mention data incomplete"))
       ((not (file-writable-p path))
        (jetpacs-shell-notify (format "Couldn't link — %s not writable"
                                   (file-name-nondirectory path))))
       (t
        (with-current-buffer (find-file-noselect path)
          (org-with-wide-buffer
           (goto-char (point-min))
           (forward-line (1- line))
           (if (not (glasspane-notes--find-unlinked
                     terms (line-end-position)))
               (jetpacs-shell-notify
                "Couldn't find the mention — file changed? Refresh and retry")
             (replace-match (format "[[id:%s][%s]]" id (match-string 0))
                            t t)
             (let ((save-silently t)) (save-buffer))
             (remhash id glasspane-notes--mentions)
             (jetpacs-org-cache-invalidate 'glasspane)
             (jetpacs-shell-notify "Linked"))))))
      (jetpacs-shell-push))))

(add-hook 'jetpacs-shell-refresh-hook
          (lambda () (clrhash glasspane-notes--mentions)))

;; The detail view splices this module's sections through the ui seam.
(add-hook 'glasspane-ui-detail-nodes-functions #'glasspane-notes-detail-nodes)

(provide 'glasspane-notes)
;;; glasspane-notes.el ends here
