;;; glasspane-org-reader.el --- Foldable org outline renderer for Glasspane -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The G4 reader (docs/PLAN-glasspane-app.md): an org file (or one
;; subtree) rendered as a tree of `jetpacs-collapsible' nodes — folding
;; resolves on the device, so a subtree ships once and folds without a
;; round trip.  Three entry points: `glasspane-org-reader-file' (whole
;; file), `glasspane-org-reader-subtree' (one heading, used by the
;; detail and journal rungs), `glasspane-org-reader-refile-list' (flat
;; drag-to-reorder list).  The whole-file presentation replaces the
;; foundation reader adapter's stable `org' registry slot while
;; Glasspane is loaded.  The reusable host remains the sole Files seam
;; claimant and owns rendered⇄plain transitions; unloading Glasspane
;; reasserts the stock Org adapter in the same slot.
;;
;; Retired against v1 (the plan's retirement list + G4 section):
;;
;; - jetpacs-org-rich: no v3 body renderer (FOUNDATION-GAPS #6) —
;;   bodies degrade to `jetpacs-text :syntax "org"', losing inline
;;   checkboxes/tables/emphasis inside the reader (open question 2).
;; - `:strike' on done titles: RichSpan has no member (gap #7) — the
;;   keyword keeps its done green, the title degrades to
;;   on_surface_variant.
;; - The menu's Priority…/Schedule…/Deadline…/Tags… prompt rows: those
;;   arms are retired wholesale to the shipped foundation dialogs; one
;;   "Org actions…" row rides `jetpacs.org.heading' (the base sheet
;;   carries set-todo/schedule/deadline/priority/tags/refile/archive),
;;   authorized per heading through the SPEC 23.1 exposure route.
;; - The heading swipe's app archive verb: swipe-end now emits the base
;;   `jetpacs.org.archive' (descriptor-level :confirm replaces v1's
;;   handler-side confirm).  Its handler resolves only tokens in the
;;   `jetpacs-org-dialogs-owner' scope, so the render mints a SECOND,
;;   app-named set there — the only cross-owner mint in the app.
;; - The collapsible's legacy single-action `:on-swipe': no v3 member —
;;   the per-side `:swipe-start'/`:swipe-end' pair is the whole story.
;; - files.toggle-read: the reader host's `jetpacs.reader.toggle' owns
;;   rendered⇄plain; files.toggle-refile remains the tree/list switch.
;; - v1's read-mode surfacing listed level-1 cards through
;;   jetpacs-org-outline-body with the AGENDA card — a G5 builder this
;;   rung may not require forward — so read mode surfaces this file's
;;   own foldable tree instead (flagged to the plan as a deviation).

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'ebp)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-buffer)
(require 'jetpacs-files)
(require 'jetpacs-reader)
(require 'jetpacs-reader-org)           ; stock fallback, decrypt action,
                                        ; and narrowed-editor transition
(require 'jetpacs-org-dialogs)          ; the base sheet/archive verbs the
                                        ; reader delegates to (S3)
(require 'glasspane-org)                ; durable mutation/save funnel

;;;; File access (the G1 funnel: policy first, clamped IO always)

(defun glasspane-org-reader--with-file (file fn)
  "Run FN with validated FILE's buffer current, wide, and clock-summed.
FN receives the truename.  `ebp-org--check-file' signals
`ebp-org-refused' outside the roots and `ebp-org-unresolved' when the
file is gone — the callers' status arms — and the visit runs clamped so
a drifted file becomes a status, never a prompt (D2)."
  (let ((true (ebp-org--check-file file)))
    (ebp-org--with-clamped-io
      (with-current-buffer (find-file-noselect true t)
        (unless (derived-mode-p 'org-mode) (org-mode))
        (org-with-wide-buffer
         (when ebp-org-outline-show-clocked
           (ignore-errors (org-clock-sum)))
         (funcall fn true))))))

;;;; Token minting (S5 — one :set per rendered list, replace semantics)

(defun glasspane-org-reader--flatten (nodes)
  "Every tree node in NODES, depth first — the mint's ref order."
  (cl-loop for n in nodes
           append (cons n (glasspane-org-reader--flatten
                           (plist-get n :children)))))

(defun glasspane-org-reader--mint (nodes set)
  "Mint tap + archive tokens for every node in NODES; POS -> (TAP . ARCHIVE).
Runs in the file's buffer.  Refs come from `ebp-org-ref-at-point' so a
heading with an ID drifts by ID, not by position.  Two sets because the
base `jetpacs.org.archive' resolves only `jetpacs-org-dialogs-owner'
tokens: the app rents the disjoint \"glasspane-SET\" set in that scope
rather than registering an archive verb of its own (retirement list).
Minted even when NODES is empty — the replace sweep is what retires the
previous render's tokens."
  (let* ((flat (glasspane-org-reader--flatten nodes))
         (refs (mapcar (lambda (n)
                         (save-excursion
                           (goto-char (plist-get n :pos))
                           (ebp-org-ref-at-point)))
                       flat))
         (taps (ebp-org-ref-tokens refs :set set :owner "glasspane"))
         (archives (ebp-org-ref-tokens refs :set (concat "glasspane-" set)
                                       :owner jetpacs-org-dialogs-owner))
         (table (make-hash-table :test #'eql)))
    (cl-loop for n in flat for tap in taps for arch in archives
             do (puthash (plist-get n :pos) (cons tap arch) table))
    table))

;;;; Node builders

(defvar glasspane-org-reader-inline-props t
  "When nil, PROPERTIES drawers are not rendered inline under headings.
The detail view binds this off: its per-heading affordances offer the
drawer as an editable dialog instead.")

(defun glasspane-org-reader--props-node (props file pos)
  "A collapsed PROPERTIES drawer node for PROPS (an alist of KEY . VALUE)."
  (let ((text (mapconcat (lambda (kv) (format ":%s: %s" (car kv) (cdr kv)))
                         props "\n")))
    (jetpacs-collapsible (jetpacs-wire-id "fold-props"
                                          (format "%s/%d" file pos))
                         (jetpacs-text "PROPERTIES" :style "label")
                         (jetpacs-text text :style "mono")
                         :collapsed t)))

(defun glasspane-org-reader--content-nodes (n file tokens &optional skip-props)
  "Inline content nodes for tree node N: PROPERTIES, body, child headings.
TOKENS is the render's POS -> (TAP . ARCHIVE) table.  SKIP-PROPS marks
the detail view, which shows properties as its own section."
  (let ((pos (plist-get n :pos))
        (props (plist-get n :props))
        (body (plist-get n :body))
        (children (plist-get n :children)))
    (delq nil
          (append
           (when (and props (not skip-props) glasspane-org-reader-inline-props)
             (list (glasspane-org-reader--props-node props file pos)))
           (when (and body (not (string-empty-p body)))
             (list (jetpacs-text body :syntax "org")))
           (mapcar (lambda (c)
                     (glasspane-org-reader--heading-node c file tokens))
                   children)))))

(defconst glasspane-org-reader--duplicate-ttl-s 86400
  "Offline ttl for the queued Duplicate (SPEC 14.1; plan T4, reader:89).
A day: the token lives Emacs-side, so a replay after reconnect still
names the heading the user meant, and anything older is better dropped
than sprung on a file edited since.")

(defconst glasspane-org-reader--todo-color "#EF5350"
  "Span color for open TODO keywords in reader headers.")
(defconst glasspane-org-reader--done-color "#66BB6A"
  "Span color for done keywords in reader headers.")
(defconst glasspane-org-reader--priority-color "#F57C00"
  "Span color for priority cookies (matches the agenda cards).")
(defconst glasspane-org-reader--overdue-color "#EF5350"
  "Span color for overdue deadline badges.")

(defun glasspane-org-reader--heading-ops (token archive buffer pos clocked)
  "Per-heading quick actions as (LABEL ICON DESCRIPTOR) triples.
TOKEN/ARCHIVE are the render's minted pair; BUFFER/POS the exposure
route the \"Org actions…\" bridge needs — the base sheet carries every
editor this app no longer owns (set-todo, schedule, deadline, priority,
tags, refile, archive), so only the delta the base cannot offer stays
app-verbed here (FOUNDATION-GAPS #12)."
  (delq nil
        (list
         (list "Open" "open_in_new"
               (jetpacs-action "heading.tap" :args (list :token token)))
         (if clocked
             (list "Clock Out" "timer_off" (jetpacs-action "org.clock.out"))
           (list "Clock In" "timer"
                 (jetpacs-action "heading.clock-in"
                                 :args (list :token token))))
         (list "Properties" "data_object"
               (jetpacs-action "heading.props.show"
                               :args (list :token token)))
         (list "Duplicate" "content_copy"
               (jetpacs-action "heading.duplicate"
                               :args (list :token token)
                               :when-offline "queue"
                               :ttl-s glasspane-org-reader--duplicate-ttl-s))
         (when buffer
           (list "Org actions…" "edit_note"
                 (jetpacs-action "jetpacs.org.heading"
                                 :args (list :buffer buffer :pos pos))))
         (when archive
           (list "Archive" "archive"
                 (jetpacs-action "jetpacs.org.archive"
                                 :args (list :token archive)
                                 :confirm "Archive this subtree?"))))))

(defun glasspane-org-reader-heading-menu (token archive buffer pos clocked)
  "The per-heading overflow (more_vert) dropdown of quick actions."
  (jetpacs-menu
   (mapcar (lambda (op)
             (jetpacs-menu-item (nth 0 op) (nth 2 op) :icon (nth 1 op)))
           (glasspane-org-reader--heading-ops token archive buffer pos
                                              clocked))))

(defun glasspane-org-reader--meta-line (n)
  "The deadline/clocked badge line for tree node N, or nil.
The deadline date shows in the priority orange, switching to red once
overdue; the clocked total renders as h:mm."
  (let* ((deadline (plist-get n :deadline))
         (ddate (and (stringp deadline)
                     (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
                                   deadline)
                     (match-string 0 deadline)))
         (overdue (and ddate (not (plist-get n :done))
                       (string< ddate (format-time-string "%Y-%m-%d"))))
         (mins (plist-get n :clocked))
         (spans (delq nil
                      (list
                       (when ddate
                         (jetpacs-span (concat "Deadline " ddate)
                                       :font-weight (and overdue "bold")
                                       :color (if overdue
                                                  glasspane-org-reader--overdue-color
                                                glasspane-org-reader--priority-color)))
                       (when (and (numberp mins) (> mins 0))
                         (jetpacs-span (format "%s%d:%02d clocked"
                                               (if ddate "  ·  " "")
                                               (/ mins 60) (% mins 60))))))))
    (when spans (jetpacs-rich-text spans))))

(defun glasspane-org-reader--heading-header (n)
  "The structured header for tree node N.
Todo keyword and priority render as colored spans, tags become tappable
chips, and deadline/clocked badges follow on their own line.  A done
title takes on_surface_variant — the gap #7 degrade, RichSpan having no
strike member.  Falls back to raw org markup when the heading didn't
parse (no title)."
  (let ((todo (plist-get n :todo))
        (priority (plist-get n :priority))
        (title (plist-get n :title))
        (tags (plist-get n :tags))
        (done (plist-get n :done)))
    (if (string-empty-p (or title ""))
        (jetpacs-text (or (plist-get n :line) "") :syntax "org")
      (let* ((line (jetpacs-rich-text
                    (delq nil
                          (list
                           (when todo
                             (jetpacs-span (concat todo " ")
                                           :font-weight "bold"
                                           :color (if done
                                                      glasspane-org-reader--done-color
                                                    glasspane-org-reader--todo-color)))
                           (when priority
                             (jetpacs-span (format "[#%s] " priority)
                                           :font-weight "bold"
                                           :color glasspane-org-reader--priority-color))
                           (if done
                               (jetpacs-span title
                                             :color "on_surface_variant")
                             (jetpacs-span title))))))
             (meta (glasspane-org-reader--meta-line n))
             (tag-row (when tags
                        (apply #'jetpacs-flow-row
                               (mapcar (lambda (tg)
                                         (jetpacs-assist-chip
                                          tg :on-tap (jetpacs-action
                                                      "search.by-tag"
                                                      :args (list :tag tg))))
                                       tags)))))
        (if (or meta tag-row)
            (apply #'jetpacs-column (delq nil (list line meta tag-row)))
          line)))))

(defun glasspane-org-reader-swipe-sides (token archive)
  "The (START . END) per-side swipe pair for a heading's minted pair.
Rightward reveals the todo cycle (green); leftward the base archive
(red) — `jetpacs.org.archive' with the descriptor-level confirm, so the
Companion asks before the event exists (SPEC 14.1).  Shared with the
agenda/tasks cards."
  (cons (jetpacs-swipe "Cycle" :icon "check" :color "#4CAF50"
                       :on-trigger (jetpacs-action "heading.todo-cycle"
                                                   :args (list :token token)))
        (and archive
             (jetpacs-swipe "Archive" :icon "archive" :color "#E53935"
                            :on-trigger (jetpacs-action
                                         "jetpacs.org.archive"
                                         :args (list :token archive)
                                         :confirm "Archive this subtree?")))))

(defun glasspane-org-reader--heading-node (n file tokens)
  "Render tree node N (and its subtree) to a foldable `jetpacs-collapsible'.
TOKENS is the render's POS -> (TAP . ARCHIVE) table.  Long-press opens
the detail view; the trailing overflow menu carries the quick actions;
the header swipes right = todo cycle, left = archive.  The \"Org
actions…\" bridge is authorized here through the exposure route
\(SPEC 23.1): the base `jetpacs.org.heading' refuses any position this
render did not record."
  (let* ((pos (plist-get n :pos))
         (cell (gethash pos tokens))
         (token (car cell))
         (archive (cdr cell))
         (buffer (buffer-name))
         (sides (and token (glasspane-org-reader-swipe-sides token archive)))
         (header (glasspane-org-reader--heading-header n)))
    (when token
      (jetpacs-buffer-expose buffer pos "jetpacs.org.heading"))
    (jetpacs-collapsible
     (jetpacs-wire-id "fold" (format "%s/%d" file pos))
     (if token
         (jetpacs-row
          (jetpacs-with-attrs header :weight 1)
          (glasspane-org-reader-heading-menu
           token archive buffer pos (ebp-org-clocked-in-p pos)))
       header)
     (glasspane-org-reader--content-nodes n file tokens)
     :on-long-tap (and token
                       (jetpacs-action "heading.tap"
                                       :args (list :token token)))
     :swipe-start (car sides)
     :swipe-end (cdr sides))))

(defun glasspane-org-reader--render-tree (nodes true set)
  "Widget nodes for tree NODES of file TRUE; mints token set SET.
Runs in the file's buffer.  The exposure record is superseded once per
render, then every heading accumulates into it (the document-scope
contract of `jetpacs-buffer-forget-exposed')."
  (jetpacs-buffer-forget-exposed (buffer-name))
  (let ((tokens (glasspane-org-reader--mint nodes set)))
    (mapcar (lambda (n) (glasspane-org-reader--heading-node n true tokens))
            nodes)))

;;;; Entry points

(defun glasspane-org-reader--reader-parts (file query)
  "(NODES KEPT TOTAL) for FILE with sparse filter QUERY over top levels.
Signals `user-error' on a query that doesn't parse (the caller's error
caption), and the root-policy conditions of the access funnel."
  (glasspane-org-reader--with-file
   file
   (lambda (true)
     (let* ((records (ebp-org-outline-cap
                      (ebp-org-outline-collect (point-min) (point-max) nil)))
            (tree (ebp-org-outline-tree records))
            (total (length tree))
            (tq (and query (not (string-empty-p query))
                     (ebp-org-parse-query query)))
            (kept (if tq
                      (cl-remove-if-not
                       (lambda (n)
                         (save-excursion
                           (goto-char (plist-get n :pos))
                           (ebp-org-entry-matches-p tq)))
                       tree)
                    tree)))
       (list (glasspane-org-reader--render-tree kept true "reader-file")
             (length kept) total)))))

(defun glasspane-org-reader-file (file)
  "Render the whole org FILE to a list of foldable widget nodes.
Content before the first heading is not shown."
  (car (glasspane-org-reader--reader-parts file nil)))

(defun glasspane-org-reader-subtree (file pos &optional skip-props set)
  "Render the org subtree at POS in FILE.
The drilled-into heading's own PROPERTIES/body render inline (its title
is already in the top bar); its child headings render as foldable
sections.  Returns a list of widget nodes (possibly empty).  SKIP-PROPS
omits the top-level PROPERTIES drawer.  SET names the token set
\(default \"reader-subtree\"): a caller whose screens STACK subtree
renders — the detail rung — passes its own per-screen set, because the
default's replace sweep would retire a still-visible screen's tokens."
  (glasspane-org-reader--with-file
   file
   (lambda (true)
     (goto-char (min pos (point-max)))
     (unless (org-at-heading-p) (ignore-errors (org-back-to-heading t)))
     (let* ((beg (point))
            (end (save-excursion (org-end-of-subtree t t)))
            (records (ebp-org-outline-cap
                      (ebp-org-outline-collect beg end t)))
            (tree (ebp-org-outline-tree records))
            (root (car tree)))
       (when root
         (jetpacs-buffer-forget-exposed (buffer-name))
         (let ((tokens (glasspane-org-reader--mint
                        tree (or set "reader-subtree"))))
           (glasspane-org-reader--content-nodes root true tokens
                                                skip-props)))))))

;;;; The refile list (D-4: pos + per-list resolution, never raw paths)

(defvar glasspane-org-reader--refile-lists nil
  "Alist LIST-ID -> (:file TRUENAME :keys ((ITEM-KEY . POS) ...)).
The Emacs-side resolution the wire ids point back to: the reorder
event carries the minted list id and the device's `order' of item
keys, and the handler recovers file and positions HERE — a path never
rides in `:args'.  Each render replaces its own list's entry.")

(defun glasspane-org-reader-refile-lookup (list-id)
  "LIST-ID's (:file TRUENAME :keys ((KEY . POS) ...)) record, or nil.
The heading.reorder handler's resolution seam."
  (alist-get list-id glasspane-org-reader--refile-lists nil nil #'equal))

(defun glasspane-org-reader-refile-store (list-id record)
  "Store LIST-ID's refile RECORD, or remove it when RECORD is nil.
This is the writer half of `glasspane-org-reader-refile-lookup'.
Reorderable-list producers own their minted ids, while this module
keeps the resolution table private and remains the only module that
knows its representation.  Return RECORD."
  (setf (alist-get list-id glasspane-org-reader--refile-lists
                   nil (null record) #'equal)
        record))

(defun glasspane-org-reader-refile-list (file)
  "Render all headings in FILE as a flat reorderable item list.
Returns a single `jetpacs-reorderable-list' node, or nil when the file
has no headings.  Item keys and the list id mint through
`jetpacs-wire-id'; the raw heading line (stars and all) is the label,
so the level stays visible without a widget-side indent."
  (glasspane-org-reader--with-file
   file
   (lambda (true)
     (let ((records (ebp-org-outline-cap
                     (ebp-org-outline-collect (point-min) (point-max) nil))))
       (when records
         (let* ((list-id (jetpacs-wire-id "refile" true))
                (keys nil)
                (items
                 (mapcar
                  (lambda (r)
                    (let* ((pos (plist-get r :pos))
                           (key (jetpacs-wire-id
                                 "rf" (format "%s@%d" true pos))))
                      (push (cons key pos) keys)
                      (jetpacs-with-attrs
                       (jetpacs-text (or (plist-get r :line) "")
                                     :style "body" :max-lines 2)
                       :key key)))
                  records)))
           (glasspane-org-reader-refile-store
            list-id (list :file true :keys (nreverse keys)))
           (jetpacs-reorderable-list
            items
            :on-reorder (jetpacs-action "heading.reorder"
                                        :args (list :list list-id)))))))))

(defun glasspane-org-reader--on-reorder (args params)
  "Apply a refile-list drag: move one subtree to the device's drop slot.
The event carries the minted `:list' plus the injected `:from'/`:to'
indices and `:order' — the full key sequence after the drop (SPEC
17.3, every item keyed).  File and positions come from the per-list
table (D-4); a table swept by a newer render, or an order naming keys
this list never minted, answers `stale' — the list moved under the
user's finger.  The whole subtree moves (children ride along, the v1
drag's semantics) and pastes back at its own level; a drop inside the
moved subtree's own span — dragging a parent just past its child rows —
is a no-op, and the refresh snaps the list back (SPEC 14.5)."
  (let* ((list-id (plist-get args :list))
         (from (plist-get args :from))
         (to (plist-get args :to))
         (order (let ((o (plist-get args :order)))
                  (cond ((vectorp o) (append o nil))
                        ((proper-list-p o) o)))))
    (if (not (and (stringp list-id) (integerp from) (integerp to)
                  order (cl-every #'stringp order)))
        'rejected
      (let* ((record (glasspane-org-reader-refile-lookup list-id))
             (keys (plist-get record :keys)))
        (cond
         ((null record) 'stale)
         ((not (and (= (length order) (length keys))
                    (< -1 from (length keys))
                    (< -1 to (length order))
                    (equal (nth to order) (car (nth from keys)))
                    (cl-every (lambda (k) (assoc k keys)) order)))
          'stale)
         ((= from to)
          (jetpacs-buffer-defer-refresh (plist-get params :surface))
          'accepted)
         (t
          (let ((moved (car (nth from keys)))
                (prev (and (> to 0) (nth (1- to) order))))
            (condition-case nil
                (progn
                  (glasspane-org-reader--with-file
                   (plist-get record :file)
                   (lambda (_true)
                     ;; A marker, not the recorded position: the cut
                     ;; shifts everything after it before the paste
                     ;; point is ever visited.
                     (let ((prev-marker (and prev
                                             (copy-marker
                                              (cdr (assoc prev keys))))))
                       (unwind-protect
                           (progn
                             (goto-char (cdr (assoc moved keys)))
                             (org-back-to-heading t)
                             (let ((level (org-outline-level))
                                   (beg (point))
                                   (end (save-excursion
                                          (org-end-of-subtree t t)
                                          (point))))
                               (unless (and prev-marker
                                            (<= beg (marker-position
                                                     prev-marker))
                                            (< (marker-position prev-marker)
                                               end))
                                 (org-cut-subtree)
                                 (if prev-marker
                                     (progn
                                       (goto-char prev-marker)
                                       (org-back-to-heading t)
                                       (org-end-of-subtree t t))
                                   (goto-char (point-min))
                                   (if (re-search-forward
                                        org-heading-regexp nil t)
                                       (goto-char (line-beginning-position))
                                     (goto-char (point-max))))
                                 (org-paste-subtree level)
                                 (glasspane-org-save-and-invalidate
                                  (current-buffer)))))
                         (when prev-marker (set-marker prev-marker nil))))))
                  ;; Every recorded position is spent now; the deferred
                  ;; re-render mints the replacement table.
                  (glasspane-org-reader-refile-store list-id nil)
                  (jetpacs-buffer-defer-refresh (plist-get params :surface))
                  'accepted)
              (ebp-org-refused 'rejected)
              (ebp-org-unresolved 'stale)
              (error 'rejected)))))))))

;;;; The app heading sheet (S3 — the delta the base sheet cannot carry)

(defvar glasspane-org-reader--sheet nil
  "The live heading sheet, (:request-id ID :token TOK :params PARAMS), or nil.
Single-slot, the base module's shape: PARAMS are the OPENING event's —
the conclusion arrives in dialog context with no `:surface' (SPEC 14.4),
so the dispatched arm needs the surface the sheet was opened from.")

(defun glasspane-org-reader-sheet-close ()
  "Retire the live heading sheet (the S3 handler-side dismissal).
`ebp-client-abandon' sends rpc.cancel; the Companion concludes with
error 1301, which the show callback treats as a no-op."
  (let ((sheet glasspane-org-reader--sheet))
    (setq glasspane-org-reader--sheet nil)
    (when-let* ((client (jetpacs-client))
                (request-id (plist-get sheet :request-id)))
      (ignore-errors (ebp-client-abandon client request-id)))))

(defun glasspane-org-reader--sheet-candidates (ref)
  "Fresh (VALUE . LABEL) candidates for REF's sheet.
Rebuilt at dispatch time too — the submitted value must name a
candidate the sheet WOULD offer now (SPEC 23.2).  Only the delta the
base sheet's hardcoded list cannot carry (FOUNDATION-GAPS #12): drill
in, the clock pair, properties."
  (let ((clocked (condition-case nil
                     (let ((m (ebp-org-resolve-ref ref)))
                       (unwind-protect
                           (with-current-buffer (marker-buffer m)
                             (org-with-wide-buffer
                              (ebp-org-clocked-in-p (marker-position m))))
                         (set-marker m nil)))
                   (error nil))))
    (append '(("open" . "Open"))
            (if clocked
                '(("clock-out" . "Clock Out"))
              '(("clock-in" . "Clock In")))
            '(("props" . "Properties")))))

(defun glasspane-org-reader--dispatch (name args params)
  "Funcall NAME's registered handler with ARGS/PARAMS; its status back.
The sheet's arms are OTHER modules' verbs (detail's drill-in and
properties, the clock service's out) — dispatching through the handler
table keeps this file decoupled from sibling function names, and a
rung that hasn't landed yet degrades to a toast, not an unbound-symbol
error."
  (let ((fn (gethash name jetpacs-action-handlers)))
    (if (functionp fn)
        (funcall fn args params)
      (jetpacs-toast "That action isn't available yet")
      'rejected)))

(defun glasspane-org-reader--show-sheet (token ref params)
  "Show the app heading sheet for TOKEN/REF; PARAMS is the opening event's."
  (glasspane-org-reader-sheet-close)
  (when-let* ((client (jetpacs-client)))
    (let* ((title (let ((h (plist-get ref :headline)))
                    (if (and (stringp h) (not (string-empty-p h)))
                        h
                      "Heading")))
           (request-id
            (ebp-client-dialog-show
             client
             (jetpacs-wire-id "gp-sheet" (format "%s/%s"
                                                 (plist-get ref :file)
                                                 (plist-get ref :pos)))
             (apply #'jetpacs-column
                    (jetpacs-text title :style "title")
                    (append
                     (mapcar (lambda (c)
                               (jetpacs-button
                                (cdr c)
                                (jetpacs-dialog-submit :value (car c))
                                :variant "text"))
                             (glasspane-org-reader--sheet-candidates ref))
                     (list (jetpacs-button "Cancel"
                                           (jetpacs-dialog-dismiss)))))
             :style "sheet"
             :callback
             (lambda (status result _error)
               (setq glasspane-org-reader--sheet nil)
               (when (and (equal status "submitted")
                          (stringp (plist-get result :value)))
                 (let ((value (plist-get result :value))
                       ;; Re-read, not captured: the list may have
                       ;; moved while the sheet was up.
                       (ref (ebp-org-token-ref token :owner "glasspane")))
                   (cond
                    ((null ref)
                     (jetpacs-toast "That heading moved — refresh"))
                    ((not (assoc value
                                 (glasspane-org-reader--sheet-candidates
                                  ref)))
                     nil)
                    (t
                     (pcase value
                       ("open"
                        (glasspane-org-reader--dispatch
                         "heading.tap" (list :token token) params))
                       ("clock-in"
                        (glasspane-org-reader--dispatch
                         "heading.clock-in" (list :token token) params))
                       ("clock-out"
                        (glasspane-org-reader--dispatch
                         "org.clock.out" nil params))
                       ("props"
                        (glasspane-org-reader--dispatch
                         "heading.props.show" (list :token token)
                         params)))))))))))
      (when request-id
        (setq glasspane-org-reader--sheet
              (list :request-id request-id :token token :params params))))))

(defun glasspane-org-reader--on-heading-menu (args params)
  "The long-press sheet verb (S4): gate order shape -> stale -> grant."
  (let* ((token (plist-get args :token))
         (ref (and (stringp token)
                   (ebp-org-token-ref token :owner "glasspane"))))
    (cond
     ((not (stringp token)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((null ref) 'stale)
     ((not (jetpacs-granted-p "surfaces.dialog")) 'rejected)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-org-reader--show-sheet token ref params)))
      'accepted))))

;;;; Reader adapter (the trimodal replacement on the reusable host)

(defun glasspane-org-reader--fold-mode (path)
  "Return PATH's Glasspane tree presentation: `tree' or `refile'."
  (jetpacs-reader-state-get path :gp-fold-mode 'tree))

(defun glasspane-org-reader--filter-query (path)
  "Return PATH's submitted ONE-grammar filter query."
  (jetpacs-reader-state-get path :gp-filter-query ""))

(defun glasspane-org-reader--filter-input (path)
  "The sparse-filter row for PATH, re-seeded from host-owned state."
  (jetpacs-text-input
   (jetpacs-wire-id "files-filter" path)
   :value (glasspane-org-reader--filter-query path)
   :hint "Filter: todo:TODO tags:work text…"
   :single-line t
   :on-submit (jetpacs-action "files.filter" :args (list :path path))))

(defun glasspane-org-reader--reader-body (path)
  "The read-mode body for org PATH: filter row + the foldable tree."
  (let* ((query (string-trim
                 (glasspane-org-reader--filter-query path)))
         (active (not (string-empty-p query)))
         (broken nil)
         (parts (if (not active)
                    (glasspane-org-reader--reader-parts path nil)
                  (condition-case err
                      (glasspane-org-reader--reader-parts path query)
                    (user-error
                     ;; Vetted exception to T2's user-facing-error rule
                     ;; (SPEC 23.3): this arm catches only
                     ;; `ebp-org-parse-query' user-errors, whose messages
                     ;; are fixed strings plus the user's own query
                     ;; keyword — no org payload can reach the caption,
                     ;; and `jetpacs-error-label' would degrade it to the
                     ;; useless "user-error".
                     (setq broken (error-message-string err))
                     nil))))
         (nodes (nth 0 parts))
         (kept (nth 1 parts))
         (total (nth 2 parts)))
    ;; Counts belong to the document whose render produced them.  Keeping
    ;; them beside the query prevents one Files tab from reporting another
    ;; file's filter result after a route switch.
    (jetpacs-reader-state-set path :gp-filter-kept
                              (and (not broken) kept))
    (jetpacs-reader-state-set path :gp-filter-total
                              (and (not broken) total))
    (cond
     (broken
      (jetpacs-lazy-column (glasspane-org-reader--filter-input path)
                           (jetpacs-text broken :style "caption")))
     (t
      (apply #'jetpacs-lazy-column
             (append
              (list (glasspane-org-reader--filter-input path))
              (when active
                (list (jetpacs-row
                       (jetpacs-with-attrs
                        (jetpacs-text
                         (format "%d of %d headings"
                                 (jetpacs-reader-state-get
                                  path :gp-filter-kept 0)
                                 (jetpacs-reader-state-get
                                  path :gp-filter-total 0))
                         :style "caption")
                        :weight 1)
                       (jetpacs-assist-chip
                        "Clear"
                        :on-tap (jetpacs-action "files.filter"
                                                :args (list :path path
                                                            :value "")))
                       :align "center")))
              (or nodes
                  (list (jetpacs-text
                         (if active "No matches" "No headings found.")
                         :style "caption")))))))))

(defun glasspane-org-reader--adapter-render (path)
  "Render PATH's Glasspane tree, degrading to the stock Org adapter.
The replacement of registry id `org' is intentionally a single point of
selection.  Its failure mode is therefore guarded here: an app-side tree,
policy, or refiling error gets the foundation reader rather than a blank or
generic host error screen."
  (condition-case err
      (if (eq (glasspane-org-reader--fold-mode path) 'refile)
          (let ((list (glasspane-org-reader-refile-list path)))
            ;; `reorderable_list' owns a LazyColumn on the device.  It must
            ;; receive the screen's finite remainder, never sit as an item in
            ;; another lazy/scrolling container (Compose rejects that with an
            ;; infinite-height measurement).  A weighted child of this root
            ;; column is the bounded list viewport; the caption stays fixed.
            (jetpacs-column
             (jetpacs-text "Drag to reorder headings" :style "caption")
             (if list
                 (jetpacs-with-attrs list :weight 1)
               (jetpacs-text "No headings to show." :style "caption"))
             :fill t))
        (glasspane-org-reader--reader-body path))
    (error
     (message "glasspane: reader adapter fell back: %s"
              (jetpacs-error-label err))
     (jetpacs-reader-org--render path))))

(defun glasspane-org-reader--adapter-actions (path)
  "Return Glasspane's reader actions for PATH plus Org Crypt decrypt.
The stock typography, visibility, and org-occur icons deliberately do not
ride this presentation: the in-body ONE-grammar filter owns tree search."
  (when (jetpacs-reader-active-p path)
    (delq
     nil
     (list
      (jetpacs-icon-button
       (if (eq (glasspane-org-reader--fold-mode path) 'refile)
           "visibility" "swap_vert")
       (jetpacs-action "files.toggle-refile" :args (list :path path))
       :content-description
       (if (eq (glasspane-org-reader--fold-mode path) 'refile)
           "Reader" "Refile"))
      (when (jetpacs-reader-org--encrypted-p path)
        (jetpacs-icon-button
         "lock_open"
         (jetpacs-action "jetpacs.reader.org.decrypt"
                         :args (list :path path))
         :content-description "Decrypt Org Crypt entries"))))))

(defun glasspane-org-reader--adapter-transition (path presentation)
  "Apply the stock Org transition discipline to PATH and PRESENTATION."
  (jetpacs-reader-org--transition path presentation))

(defun glasspane-org-reader--action-path (args params)
  "Return a validated current Org path, or a status symbol."
  (let ((path (plist-get args :path)))
    (cond
     ((not (jetpacs-reader-org-path-p path)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-reader-current-path-p path)) 'stale)
     (t path))))

(defun glasspane-org-reader--on-files-filter (args params)
  "Store the current document's ONE-grammar filter; empty clears it."
  (let ((path (glasspane-org-reader--action-path args params))
        (value (plist-get args :value)))
    (cond
     ((symbolp path) path)
     ((not (stringp value)) 'rejected)
     (t
      (jetpacs-reader-state-set path :gp-filter-query value)
      (jetpacs-reader-state-set path :gp-filter-kept nil)
      (jetpacs-reader-state-set path :gp-filter-total nil)
      (jetpacs-reader-refresh params)
      'accepted))))

(defun glasspane-org-reader--on-toggle-refile (args params)
  "Flip the current document between foldable tree and refile list."
  (let ((path (glasspane-org-reader--action-path args params)))
    (if (symbolp path) path
      (jetpacs-reader-state-set
       path :gp-fold-mode
       (if (eq (glasspane-org-reader--fold-mode path) 'refile)
           'tree 'refile))
      (jetpacs-reader-refresh params)
      'accepted)))

;;;; Registration

(defconst glasspane-org-reader--verbs
  '("heading.menu" "files.filter" "files.toggle-refile" "heading.reorder")
  "The verbs this rung's reader owns, for the register/unregister sweep.
heading.tap/props.show/duplicate/todo-cycle/clock-in are the detail
sibling's; the menu names them by wire string only.  heading.reorder
lives HERE, beside the only table that can resolve it (D-4) — views'
board re-emits the same verb in G6.  files.filter lives beside its
path-keyed reader state rather than in the app-wide UI module.")

(defun glasspane-org-reader-register ()
  "Register the Glasspane Org adapter and reader verbs.
Called from `glasspane-register', not at this file's load (the G0
contract).  The \"Reader\" settings section this rung used to register
is foundation content now (jetpacs-org-settings.el, the §3
relocation): both rows were `ebp-org-outline-show-*' foundation
defcustoms all along.  The generic reader host remains the only Files
body/actions claimant; this app replaces the stock adapter in the stable
`org' slot and restores it during unregister."
  ;; Ensure the stock action family (especially Org Crypt decrypt) exists
  ;; before replacing only its adapter slot.  The registrar is deliberately
  ;; reassertive, so this also makes live reload deterministic.
  (jetpacs-reader-org-register)
  (jetpacs-reader-register
   'org :predicate #'jetpacs-reader-org-path-p
   :render #'glasspane-org-reader--adapter-render
   :actions #'glasspane-org-reader--adapter-actions
   :transition #'glasspane-org-reader--adapter-transition)
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "heading.menu"
                       #'glasspane-org-reader--on-heading-menu
                       :any-surface t
                       :doc "Long-press sheet: the app's per-heading delta")
    (jetpacs-defaction "files.filter"
                       #'glasspane-org-reader--on-files-filter
                       :any-surface t)
    (jetpacs-defaction "files.toggle-refile"
                       #'glasspane-org-reader--on-toggle-refile
                       :any-surface t)
    (jetpacs-defaction "heading.reorder"
                       #'glasspane-org-reader--on-reorder
                       :any-surface t
                       :doc "Apply a drag in the refile list (D-4)"))
  ;; Clean up claims made by an older/live-loaded pre-adapter version.
  (remove-hook 'jetpacs-files-editor-body-functions
               'glasspane-org-reader--files-body)
  (remove-hook 'jetpacs-files-editor-actions-functions
               'glasspane-org-reader--files-actions))

(defun glasspane-org-reader-unregister ()
  "Drop Glasspane reader state and restore the stock Org adapter."
  (dolist (name glasspane-org-reader--verbs)
    (jetpacs-undefaction name))
  ;; Sweep hooks left by any live-loaded pre-GR-2 implementation.  This
  ;; version never adds them: `jetpacs-reader--files-*' are the only reader
  ;; seam functions.
  (remove-hook 'jetpacs-files-editor-body-functions
               'glasspane-org-reader--files-body)
  (remove-hook 'jetpacs-files-editor-actions-functions
               'glasspane-org-reader--files-actions)
  (glasspane-org-reader-sheet-close)
  (setq glasspane-org-reader--refile-lists nil)
  (jetpacs-reader-org-register))

(provide 'glasspane-org-reader)
;;; glasspane-org-reader.el ends here
