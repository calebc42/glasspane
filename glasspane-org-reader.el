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
;; drag-to-reorder list).  The file also owns the reader's SURFACING:
;; the trimodal block v1 kept in glasspane-ui claims the jetpacs-files
;; body/actions seams here, AHEAD of jetpacs-org-render's own entry
;; (hooks chain — the plan's sanctioned shape), so org files open in
;; this reader while the foundation's rendered⇄plain toggle still
;; reaches the plain editor.
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
;; - files.toggle-read: the foundation's `jetpacs.org.view-mode' owns
;;   rendered⇄plain; only files.toggle-refile ports (with the state it
;;   flips), per the G3 commentary.
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
(require 'jetpacs-org-render)           ; the rendered⇄plain mode bit the
                                        ; body seam must respect
(require 'jetpacs-org-dialogs)          ; the base sheet/archive verbs the
                                        ; reader delegates to (S3)
(require 'glasspane-ui)                 ; the files-filter defvar (S2)

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
           (setf (alist-get list-id glasspane-org-reader--refile-lists
                            nil nil #'equal)
                 (list :file true :keys (nreverse keys)))
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
                                 (glasspane-org--save-and-invalidate
                                  (current-buffer)))))
                         (when prev-marker (set-marker prev-marker nil))))))
                  ;; Every recorded position is spent now; the deferred
                  ;; re-render mints the replacement table.
                  (setf (alist-get list-id glasspane-org-reader--refile-lists
                                   nil t #'equal)
                        nil)
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

;;;; Surfacing: the jetpacs-files seam claims (the trimodal replacement)

(defvar glasspane-org-reader--refile-mode nil
  "When non-nil, the org reader shows the flat drag-to-reorder list.
Single writer: the files.toggle-refile handler.")

(defun glasspane-org-reader--org-path-p (path)
  "Non-nil when PATH names an org file."
  (and (stringp path) (string-suffix-p ".org" path t)))

(defun glasspane-org-reader--filter-input ()
  "The sparse-filter row, re-seeded from the shared defvar (S2).
Persistence across re-renders IS the feature (the v1 lesson the
defvar's home documents): the submitted query lives Emacs-side and the
input takes it back as `:value' each render."
  (jetpacs-text-input "files-filter"
                      :value glasspane-ui--files-filter
                      :hint "Filter: todo:TODO tags:work text…"
                      :single-line t
                      :on-submit (jetpacs-action "files.filter")))

(defun glasspane-org-reader--reader-body (path)
  "The read-mode body for org PATH: filter row + the foldable tree."
  (let* ((query (string-trim glasspane-ui--files-filter))
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
    (cond
     (broken
      (jetpacs-lazy-column (glasspane-org-reader--filter-input)
                           (jetpacs-text broken :style "caption")))
     (t
      (apply #'jetpacs-lazy-column
             (append
              (list (glasspane-org-reader--filter-input))
              (when active
                (list (jetpacs-row
                       (jetpacs-with-attrs
                        (jetpacs-text (format "%d of %d headings" kept total)
                                      :style "caption")
                        :weight 1)
                       (jetpacs-assist-chip
                        "Clear"
                        :on-tap (jetpacs-action "files.filter"
                                                :args (list :value "")))
                       :align "center")))
              (or nodes
                  (list (jetpacs-text
                         (if active "No matches" "No headings found.")
                         :style "caption")))))))))

(defun glasspane-org-reader--files-body (path)
  "The body seam: the app reader for org PATH, or nil to pass along.
Claims AHEAD of jetpacs-org-render's entry (the plan's chain), but
respects the foundation's per-path mode: `plain' passes through to the
text editor, so the base rendered⇄plain toggle keeps working.  Policy
refusals and errors pass too — the base skin has no roots policy and
still renders the file; the reader just declines it."
  (when (and (glasspane-org-reader--org-path-p path)
             (jetpacs-org-render-rendered-p path))
    (condition-case err
        (if glasspane-org-reader--refile-mode
            (jetpacs-lazy-column
             (jetpacs-text "Drag to reorder headings" :style "caption")
             (or (glasspane-org-reader-refile-list path)
                 (jetpacs-text "No headings to show." :style "caption")))
          (glasspane-org-reader--reader-body path))
      (ebp-org-refused nil)
      (ebp-org-unresolved nil)
      (error
       (message "glasspane: reader body failed: %s"
                (jetpacs-error-label err))
       nil))))

(defun glasspane-org-reader--files-actions (path)
  "The actions seam: the reader⇄refile toggle beside the base's own.
The seams APPEND across claimants, so the foundation's edit/preview
icon (`jetpacs.org.view-mode') still appears; this contributes only the
refile flip, files.toggle-read having died with the bimodal machinery."
  (when (and (glasspane-org-reader--org-path-p path)
             (jetpacs-org-render-rendered-p path))
    (list (jetpacs-icon-button
           (if glasspane-org-reader--refile-mode "visibility" "swap_vert")
           (jetpacs-action "files.toggle-refile")
           :content-description
           (if glasspane-org-reader--refile-mode "Reader" "Refile")))))

(defun glasspane-org-reader--on-toggle-refile (_args params)
  "Flip the refile drag-list mode (S4)."
  (if (jetpacs-event-stale-p params)
      'stale
    (setq glasspane-org-reader--refile-mode
          (not glasspane-org-reader--refile-mode))
    (jetpacs-buffer-defer-refresh (plist-get params :surface))
    'accepted))

;;;; Registration

(defconst glasspane-org-reader--verbs
  '("heading.menu" "files.toggle-refile" "heading.reorder")
  "The verbs this rung's reader owns, for the register/unregister sweep.
heading.tap/props.show/duplicate/todo-cycle/clock-in are the detail
sibling's; the menu names them by wire string only.  heading.reorder
lives HERE, beside the only table that can resolve it (D-4) — views'
board re-emits the same verb in G6.")

(defun glasspane-org-reader-register ()
  "Register the reader verbs and the seam claims.
Called from `glasspane-register', not at this file's load (the G0
contract).  The \"Reader\" settings section this rung used to register
is foundation content now (jetpacs-org-settings.el, the §3
relocation): both rows were `ebp-org-outline-show-*' foundation
defcustoms all along.  Remove-then-add keeps the body claim at the
FRONT of the seam on a live re-register — ahead of
jetpacs-org-render's entry, which is what lets org files open in the
app reader at all."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "heading.menu"
                       #'glasspane-org-reader--on-heading-menu
                       :doc "Long-press sheet: the app's per-heading delta")
    (jetpacs-defaction "files.toggle-refile"
                       #'glasspane-org-reader--on-toggle-refile)
    (jetpacs-defaction "heading.reorder"
                       #'glasspane-org-reader--on-reorder
                       :doc "Apply a drag in the refile list (D-4)"))
  (remove-hook 'jetpacs-files-editor-body-functions
               #'glasspane-org-reader--files-body)
  (add-hook 'jetpacs-files-editor-body-functions
            #'glasspane-org-reader--files-body)
  (remove-hook 'jetpacs-files-editor-actions-functions
               #'glasspane-org-reader--files-actions)
  (add-hook 'jetpacs-files-editor-actions-functions
            #'glasspane-org-reader--files-actions))

(defun glasspane-org-reader-unregister ()
  "Drop the reader verbs and the seam claims."
  (dolist (name glasspane-org-reader--verbs)
    (jetpacs-undefaction name))
  (remove-hook 'jetpacs-files-editor-body-functions
               #'glasspane-org-reader--files-body)
  (remove-hook 'jetpacs-files-editor-actions-functions
               #'glasspane-org-reader--files-actions)
  (glasspane-org-reader-sheet-close)
  (setq glasspane-org-reader--refile-lists nil
        glasspane-org-reader--refile-mode nil))

(provide 'glasspane-org-reader)
;;; glasspane-org-reader.el ends here
