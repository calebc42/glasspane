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
;;   emphasis inside the reader (open question 2).  Actual list checkboxes
;;   and Org tables and standalone images are upgraded by this applet.
;; - `:strike' on done titles: RichSpan has no member (gap #7) — the
;;   keyword keeps its done green, the title degrades to
;;   the neutral on_surface role.
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
(require 'org-footnote)
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
(require 'glasspane-ui)                 ; shared Area and tag presentation
(require 'jetpacs-org-render)            ; native drawer visibility controls

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

(defun glasspane-org-reader--drawers (n &optional skip-props)
  "Return N's native drawer records, omitting properties when SKIP-PROPS.
The caller is in N's source buffer.  Inline properties also honor
`glasspane-org-reader-inline-props', as the detail screen owns its own editor."
  (when (and (derived-mode-p 'org-mode) (integerp (plist-get n :pos)))
    (jetpacs-org-render-exclusive-drawers
     (cl-remove-if
      (lambda (drawer)
        (and (equal (plist-get drawer :name) "PROPERTIES")
             (or skip-props (not glasspane-org-reader-inline-props))))
      (jetpacs-org-render-heading-drawers (plist-get n :pos))))))

(defun glasspane-org-reader--logbook-nodes (text)
  "Render clocks in logbook TEXT, preserving other lines in source order.
The EBP Org parser owns clock recognition.  Parse each line independently
so freeform text and notes are never discarded by structured extraction."
  (let (nodes lines)
    (cl-labels ((flush-text
                 ()
                 (let ((plain (string-trim-right
                               (mapconcat #'identity (nreverse lines) "\n"))))
                   (unless (string-blank-p plain)
                     (push (jetpacs-text plain :syntax "org") nodes)))
                 (setq lines nil)))
      (dolist (line (split-string text "\n"))
        (let ((entry (car (ebp-org-parse-logbook line))))
          (if (eq (plist-get entry :type) 'clock)
              (progn
                (flush-text)
                (push (glasspane-ui-clock-entry entry) nodes))
            (push line lines))))
      (flush-text))
    (nreverse nodes)))

(defun glasspane-org-reader--property-nodes (drawer)
  "Render DRAWER's local properties as compact name and value rows.
Org's parser owns property recognition.  Preserve source order and values,
including repeated keys; unrecognized lines remain visible as plain text."
  (save-excursion
    (let ((end (progn (goto-char (plist-get drawer :end))
                      (line-beginning-position)))
          nodes)
      (goto-char (plist-get drawer :begin))
      (forward-line 1)
      (while (< (point) end)
        (let ((element (org-element-at-point)))
          (if (eq (org-element-type element) 'node-property)
              (let* ((key (org-element-property :key element))
                     (value (or (org-element-property :value element) ""))
                     (upper (upcase key))
                     (label (cond ((member upper '("ID" "URL" "URI")) upper)
                                  ((equal upper "CUSTOM_ID") "Custom ID")
                                  (t (capitalize (subst-char-in-string ?_ ?\s key))))))
                (push
                 (jetpacs-row
                  (jetpacs-with-attrs
                   (jetpacs-text label :style "caption" :color "outline")
                   :width 96)
                  (jetpacs-with-attrs
                   (jetpacs-text (if (string-empty-p value) "—" value)
                                 :style (if (member upper '("ID" "CUSTOM_ID"))
                                            "mono" "body")
                                 :selectable t)
                   :weight 1)
                  :fill t :align "top" :spacing 12)
                 nodes))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (unless (string-blank-p line)
                (push (jetpacs-text line :selectable t) nodes)))))
        (forward-line 1))
      (nreverse nodes))))

(defun glasspane-org-reader--drawer-node (drawer)
  "Render DRAWER's contents when its native tonal control shows it.
The shared Jetpacs visibility state is the sole expansion authority.  Omit
separate disclosure headers and Org delimiters while preserving contents."
  (unless (plist-get drawer :hidden)
    (let* ((name (plist-get drawer :name))
           (beg (plist-get drawer :begin))
           (end (plist-get drawer :end))
           (text (save-excursion
                   (goto-char beg)
                   (forward-line 1)
                   (let ((content-start (point)))
                     (goto-char end)
                     (buffer-substring-no-properties
                      content-start (max content-start (line-beginning-position)))))))
      (jetpacs-card
       (jetpacs-with-attrs
        (jetpacs-column
         (jetpacs-row
          (jetpacs-icon (if (equal name "PROPERTIES") "tune" "history")
                        :size 16 :color "primary")
          (jetpacs-text (capitalize name) :style "caption" :color "primary")
          :fill t :arrange "start" :spacing 4)
         (if (equal name "PROPERTIES")
             (apply #'jetpacs-column
                    (append (glasspane-org-reader--property-nodes drawer)
                            (list :spacing 8)))
           (apply #'jetpacs-column
                  (append (glasspane-org-reader--logbook-nodes text)
                          (list :spacing 6))))
         :spacing 6)
        :padding 10)
       :variant "outlined"))))

(defun glasspane-org-reader--checkbox-record (pos)
  "Return the real Org checkbox item at line position POS, or nil.
Org's item parser excludes lookalikes in source blocks and other prose."
  (save-excursion
    (goto-char pos)
    (when (org-at-item-checkbox-p)
      (let* ((beg (match-beginning 1))
             (end (match-end 1))
             (element (org-element-at-point beg)))
        (when (eq (org-element-type element) 'item)
          (list :pos beg
                :label-start (save-excursion (goto-char end) (skip-chars-forward " \t") (point))
                :state (pcase (org-element-property :checkbox element)
                         ('on "on") ('trans "indeterminate") (_ "off"))
                :label (string-trim-left
                        (buffer-substring-no-properties end (line-end-position)))
                :bullet (string-trim (org-element-property :bullet element))
                :indent (current-indentation)))))))

(defun glasspane-org-reader--checkbox-node (record)
  "Render checkbox RECORD with native completion and long-press progress.
The source buffer's modification tick binds both gestures to this snapshot."
  (let* ((pos (plist-get record :pos))
         (name (buffer-name))
         (state (plist-get record :state))
         (description (pcase state
                        ("on" "Complete") ("indeterminate" "In progress")
                        (_ "Not complete")))
         (label (plist-get record :label))
         (bullet (plist-get record :bullet))
         (args (list :buffer name :pos pos :tick (buffer-chars-modified-tick)))
         (tap (jetpacs-action "glasspane.checkbox" :args args))
         (progress (jetpacs-action "glasspane.checkbox"
                                   :args (append args (list :state "indeterminate")))))
    (jetpacs-buffer-expose name pos "glasspane.checkbox")
    (jetpacs-with-semantics
     (jetpacs-with-attrs
      (jetpacs-box
       (jetpacs-row
        (unless (member bullet '("-" "+" "*"))
          (jetpacs-text bullet :style "caption" :color "outline"))
        (jetpacs-box
         (jetpacs-with-semantics
          (jetpacs-checkbox (jetpacs-claim-node-id
                            (jetpacs-wire-id "gp-checkbox" (format "%s/%d" name pos)))
                            :state state :on-change tap)
          :name (if (string-empty-p label) "Checkbox" label))
         ;; The native input consumes a held pointer as a short click.
         ;; A matching touch layer owns both gestures; the checkbox keeps
         ;; its native appearance and ordinary accessibility activation.
         (jetpacs-with-semantics
          (jetpacs-box (jetpacs-spacer :width 48 :height 48)
                       :on-tap tap :on-long-tap progress)
          :name (if (string-empty-p label) "Checkbox" label)
          :state-description description
          :actions (list (jetpacs-semantic-action "Mark in progress" progress))))
        (jetpacs-with-attrs
         (glasspane-org-reader--prose-node label t (when (equal state "on") "outline")
                                           (plist-get record :label-start))
         :weight 1)
        :fill t :align "center" :spacing 4)
       :on-tap tap :on-long-tap progress)
      :pad (list :start (min 48 (* 8 (plist-get record :indent)))))
     :name (if (string-empty-p label) "Checkbox item" label)
     :state-description description
     :actions (list (jetpacs-semantic-action "Mark in progress" progress)))))

(defun glasspane-org-reader--table-at (start limit)
  "Return (END . NODE) for a complete Org table at START before LIMIT.
NODE is nil when native rendering is unavailable or exceeds the budget.
Skip the full source extent even on fallback; never upgrade example blocks."
  (when (looking-at-p "[ \t]*|")
    (let* ((element (org-element-at-point start))
           (end (org-element-property :contents-end element)))
      (when (and (eq (org-element-type element) 'table)
                 (eq (org-element-property :type element) 'org)
                 (eql start (org-element-property :contents-begin element))
                 (integerp end) (<= end limit))
        (cons end (jetpacs-org-render-table element t))))))

(defun glasspane-org-reader--image-at (start limit)
  "Return (END . NODE) for a standalone image at START before LIMIT.
Org identifies the paragraph and any affiliated caption/attributes.  A nil
NODE retains the entire source when image support or its budget is absent."
  (when (looking-at-p "[ \t]*\\(?:\\[\\[\\|#\\+\\)")
    (let ((element (org-element-at-point start)))
      (when (and (eq (org-element-type element) 'paragraph)
                 (eql start (org-element-property :begin element)))
        (let ((end (save-excursion
                     (goto-char (org-element-property :end element))
                     (skip-chars-backward " \t\n")
                     (min (point-max) (line-beginning-position 2)))))
          (when (<= end limit)
            (cons end (jetpacs-org-render-image element))))))))

(defvar glasspane-org-reader--source-scope "reader-file"
  "Explicit reader location used to distinguish retained source-block views.")

(defvar glasspane-org-reader--source-edit nil
  "One active inline Babel draft: source identity, original text and save guard.")

(defvar glasspane-org-reader--source-edit-sequence 0
  "Action-owned generation for fresh inline input identities after Cancel.")

(defvar glasspane-org-reader--in-results nil
  "Non-nil when rendering output, which must not acquire code-edit actions.")

(defconst glasspane-org-reader--source-edit-limit 65536
  "Maximum characters retained in the single inline code-edit session.")

(defun glasspane-org-reader--source-bounds (element)
  "Return the exact code-body bounds of source block ELEMENT."
  (cons (save-excursion
          (goto-char (org-element-property :post-affiliated element))
          (line-beginning-position 2))
        (save-excursion
          (goto-char (org-element-property :end element))
          (skip-chars-backward " \t\n") (line-beginning-position))))

(defun glasspane-org-reader--source-results (element end limit)
  "Return (END . NODES) for ELEMENT's adjacent results after END before LIMIT.
Use Babel's result association and extent reader without inserting results.
Named results elsewhere in the document remain at their original location."
  (save-excursion
    (goto-char (org-element-property :post-affiliated element))
    (when-let* ((result (org-babel-where-is-src-block-result)))
      (when (and (<= end result) (< result limit)
                 (string-blank-p (buffer-substring-no-properties end result)))
        (goto-char result)
        (forward-line)
        (let* ((beg (point))
               (stop (org-babel-result-end)))
          (when (and (> stop beg) (<= stop limit))
            (let* ((glasspane-org-reader--in-results t)
                   (parsed (org-element-at-point beg))
                   (nodes (if (eq (org-element-type parsed) 'fixed-width)
                              (list (jetpacs-text
                                     (string-trim-right (org-element-property :value parsed))
                                     :style "mono"))
                            (glasspane-org-reader--text-nodes
                             (buffer-substring-no-properties result stop) result))))
              (cons stop (append (list (jetpacs-divider)
                                      (jetpacs-text "Results" :style "caption"
                                                    :color "on_surface_variant"))
                                 nodes)))))))))

(defun glasspane-org-reader--source-editor (session)
  "Render SESSION's inline code field and explicit Save/Cancel actions."
  (let* ((id (jetpacs-claim-node-id (plist-get session :id)))
         (language-id (jetpacs-claim-node-id (plist-get session :language-id)))
         (args (list :session (plist-get session :id) :field id :language-field language-id))
         (save (jetpacs-action "glasspane.source.save" :args args
                               :capture-fields (list id language-id))))
    (jetpacs-buffer-expose (plist-get session :buffer) (plist-get session :pos)
                           "glasspane.source.save")
    (jetpacs-column
     (jetpacs-dropdown
      language-id
      (mapcar (lambda (language)
                (jetpacs-enum-option (if (string-empty-p language) "Unspecified" language) language))
              (plist-get session :languages))
      :value (plist-get session :language) :label "Language")
     (jetpacs-text-input id :value (plist-get session :text) :label "Code"
                         :monospace t :min-lines 4 :max-lines 16
                         :max-length glasspane-org-reader--source-edit-limit)
     (jetpacs-row
      (jetpacs-button "Cancel" (jetpacs-action "glasspane.source.cancel" :args args)
                      :variant "text")
      (jetpacs-button "Save" save :variant "filled")
      :arrange "end" :spacing 8)
     :spacing 8)))

(defun glasspane-org-reader--source-at (start limit)
  "Return (END . NODE) for a complete source block at START before LIMIT.
Use Jetpacs's Emacs-face renderer and Babel action inside a Glasspane card."
  (when (and (not glasspane-org-reader--in-results) (looking-at-p "[ \t]*#\\+"))
    (let ((element (org-element-at-point start)))
      (when (and (eq (org-element-type element) 'src-block)
                 (eql start (org-element-property :begin element)))
        (let ((end (save-excursion
                     (goto-char (org-element-property :end element))
                     (skip-chars-backward " \t\n")
                     (min (point-max) (line-beginning-position 2)))))
          (when (<= end limit)
            (when-let* ((content (jetpacs-org-render-source-block element)))
              (let* ((pos (org-element-property :post-affiliated element))
                     (name (buffer-name))
                     (bounds (glasspane-org-reader--source-bounds element))
                     (session glasspane-org-reader--source-edit)
                     (editing (and session (equal name (plist-get session :buffer))
                                   (= pos (plist-get session :pos))
                                   (equal glasspane-org-reader--source-scope
                                          (plist-get session :scope))))
                     (children (append (plist-get content :children) nil))
                     (header (car children))
                     (results (glasspane-org-reader--source-results element end limit))
                     (editable (and (jetpacs-node-advertised-p "text_input")
                                    (jetpacs-node-advertised-p "dropdown")
                                    (jetpacs-node-advertised-p "icon_button")
                                    (<= (- (cdr bounds) (car bounds))
                                        glasspane-org-reader--source-edit-limit)))
                     (args (list :buffer name :pos pos :tick (buffer-chars-modified-tick)
                                 :scope glasspane-org-reader--source-scope)))
                (when editable
                  (jetpacs-buffer-expose name pos "glasspane.source.edit")
                  (setq header
                        (apply #'jetpacs-row
                               (append (list (aref (plist-get header :children) 0))
                                       ;; Running while editing would execute the old text.
                                       (unless editing (cdr (append (plist-get header :children) nil)))
                                       (unless editing
                                         (list (jetpacs-icon-button
                                                "edit" (jetpacs-action "glasspane.source.edit" :args args)
                                                :content-description "Edit source block")))
                                       (list :align "center" :spacing 8)))))
                (cons (if results (car results) end)
                      (jetpacs-with-attrs
                       (jetpacs-card
                        (jetpacs-collapsible
                         (jetpacs-claim-node-id
                          (jetpacs-wire-id
                           "gp-source" (format "%s/%s/%d/%s" name glasspane-org-reader--source-scope
                                                pos (if editing (plist-get session :id) "read"))))
                         header
                         (apply #'jetpacs-column
                                (append (if editing
                                            (list (glasspane-org-reader--source-editor session))
                                          (cdr children))
                                        (cdr results) (list :spacing 8))))
                        :variant "outlined")
                       :pad '(:horizontal 12 :vertical 8)))))))))))

(defun glasspane-org-reader--on-source-edit (args params)
  "Open an inline source draft from ARGS and event PARAMS without editing Org."
  (let* ((name (plist-get args :buffer)) (pos (plist-get args :pos))
         (tick (plist-get args :tick)) (scope (plist-get args :scope))
         (buffer (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buffer (integerp pos) (integerp tick) (stringp scope))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos "glasspane.source.edit")) 'rejected)
     (glasspane-org-reader--source-edit
      (jetpacs-shell-notify "Save or cancel the open Babel draft first." (plist-get params :surface))
      'rejected)
     (t
      (with-current-buffer buffer
        (org-with-wide-buffer
         (if (or (/= tick (buffer-chars-modified-tick))
                 (not (<= (point-min) pos (point-max))))
             'stale
           (let ((element (org-element-at-point pos)))
             (if (not (and (eq (org-element-type element) 'src-block)
                           (eql pos (org-element-property :post-affiliated element))))
                 'stale
               (let* ((bounds (glasspane-org-reader--source-bounds element))
                      (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
                      (language (or (org-element-property :language element) ""))
                      (language-bounds
                       (save-excursion
                         (goto-char pos)
                         (let ((case-fold-search t))
                           (re-search-forward "^[ \t]*#\\+begin_src\\b" (line-end-position)))
                         (unless (string-empty-p language) (skip-chars-forward " \t"))
                         (cons (point) (+ (point) (length language)))))
                      (languages (sort (delete-dups
                                        (cons language (mapcar (lambda (entry) (symbol-name (car entry)))
                                                               org-babel-load-languages)))
                                       #'string<)))
                 (if (> (length text) glasspane-org-reader--source-edit-limit)
                     'rejected
                   (let ((id (jetpacs-wire-id "gp-code-edit"
                                              (format "%s/%d/%d" name pos
                                                      (cl-incf glasspane-org-reader--source-edit-sequence)))))
                     (setq glasspane-org-reader--source-edit
                           (list :buffer name :pos pos :tick tick :scope scope
                                 :surface (plist-get params :surface) :bounds bounds :text text
                                 :language language :language-bounds language-bounds
                                 :languages (cons language (seq-take (remove language languages) 127))
                                 :language-id (jetpacs-wire-id "gp-code-language" id) :id id)))
                   (jetpacs-buffer-defer-refresh (plist-get params :surface))
                   'accepted)))))))))))

(defun glasspane-org-reader--on-source-cancel (args params)
  "Discard the inline session identified by ARGS from PARAMS without writing."
  (if (not (and glasspane-org-reader--source-edit
                (equal (plist-get args :session) (plist-get glasspane-org-reader--source-edit :id))
                (equal (plist-get params :surface) (plist-get glasspane-org-reader--source-edit :surface))))
      'stale
    (setq glasspane-org-reader--source-edit nil)
    (jetpacs-buffer-defer-refresh (plist-get params :surface))
    'accepted))

(defun glasspane-org-reader--source-field (fields id)
  "Return captured ID from FIELDS without interning untrusted field names."
  (when (and (stringp id) (proper-list-p fields) (zerop (% (length fields) 2)))
    (cl-loop for (key value) on fields by #'cddr
             when (and (symbolp key) (equal (symbol-name key) (concat ":" id)))
             return value)))

(defun glasspane-org-reader--source-field-p (field base)
  "Whether FIELD is BASE or its document allocator's numeric suffix."
  (and (stringp field) (stringp base)
       (string-match-p (concat "\\`" (regexp-quote base) "\\(?:-[0-9]+\\)?\\'") field)))

(defun glasspane-org-reader--on-source-save (args params)
  "Save the code body and language of the inline session in ARGS from PARAMS.
Validate the original source tick, exact body and disk freshness first.
Failed writes roll back the Org buffer and keep the draft open."
  (let* ((session glasspane-org-reader--source-edit)
         (field (plist-get args :field))
         (language-field (plist-get args :language-field))
         (value (glasspane-org-reader--source-field (plist-get params :fields) field))
         (language (glasspane-org-reader--source-field (plist-get params :fields) language-field))
         (buffer (and session (get-buffer (plist-get session :buffer)))))
    (cond
     ((not (and session buffer (equal (plist-get args :session) (plist-get session :id))
                (equal (plist-get params :surface) (plist-get session :surface)))) 'stale)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (and (stringp value) (<= (length value) glasspane-org-reader--source-edit-limit)
                (glasspane-org-reader--source-field-p field (plist-get session :id))
                (glasspane-org-reader--source-field-p language-field (plist-get session :language-id))
                (member language (plist-get session :languages))
                (not (string-match-p "^[ \t]*#\\+[Ee][Nn][Dd]_[Ss][Rr][Cc][ \t]*$" value))
                (jetpacs-buffer-exposed-p (plist-get session :buffer) (plist-get session :pos)
                                         "glasspane.source.save"))) 'rejected)
     (t
      (condition-case err
          (with-current-buffer buffer
            (org-with-wide-buffer
             (let ((beg (car (plist-get session :bounds))) (end (cdr (plist-get session :bounds))))
               (if (or (/= (plist-get session :tick) (buffer-chars-modified-tick))
                       (not (verify-visited-file-modtime buffer))
                       (not (equal (plist-get session :text) (buffer-substring-no-properties beg end))))
                   (progn (jetpacs-shell-notify "Source changed. Cancel and reopen the code editor." (plist-get params :surface))
                          'stale)
                 (ebp-org--check-file buffer-file-name)
                 (ebp-org--with-clamped-io
                   (atomic-change-group
                     (save-excursion
                       (goto-char beg) (delete-region beg end)
                       (insert value)
                       (unless (or (string-empty-p value) (string-suffix-p "\n" value)) (insert "\n"))
                       (unless (equal language (plist-get session :language))
                         (let ((range (plist-get session :language-bounds)))
                           (goto-char (car range)) (delete-region (car range) (cdr range))
                           (when (string-empty-p (plist-get session :language)) (insert " "))
                           (insert language))))
                     (glasspane-org-save-and-invalidate buffer)))
                 (setq glasspane-org-reader--source-edit nil)
                 (jetpacs-buffer-defer-refresh (plist-get params :surface))
                 'accepted))))
        (error (jetpacs-shell-notify (jetpacs-error-label err) (plist-get params :surface)) 'rejected))))))

(defconst glasspane-org-reader--call-edit-limit 8192
  "Maximum characters retained in one inline Babel argument draft.")

(defun glasspane-org-reader--call-argument-bounds (element)
  "Return ELEMENT's argument bounds using Org's parsed literal components.
Only return a range when the original parentheses and parsed text agree."
  (save-excursion
    (goto-char (org-element-property :post-affiliated element))
    (when (search-forward ":" (line-end-position) t)
      (skip-chars-forward " \t")
      (forward-char (length (org-element-property :call element)))
      (when-let* ((inside (org-element-property :inside-header element)))
        (forward-char (+ 2 (length inside))))
      (when (eq (char-after) ?\()
        (forward-char)
        (let ((beg (point)) (arguments (org-element-property :arguments element)))
          (if arguments (forward-char (length arguments)) (skip-chars-forward " \t"))
          (when (eq (char-after) ?\)) (cons beg (point))))))))

(defun glasspane-org-reader--call-editor (session)
  "Render SESSION's native argument field and Save/Cancel controls."
  (let* ((id (jetpacs-claim-node-id (plist-get session :id)))
         (args (list :session (plist-get session :id) :field id)))
    (jetpacs-column
     (jetpacs-text-input id :value (plist-get session :text) :label "Arguments"
                         :hint "n=5, other=…" :monospace t :single-line t
                         :max-length glasspane-org-reader--call-edit-limit)
     (jetpacs-text "Use Org arguments, for example n=5. Save, then press Play to run."
                   :style "caption" :color "outline")
     (jetpacs-row
      (jetpacs-button "Cancel" (jetpacs-action "glasspane.call.cancel" :args args) :variant "text")
      (jetpacs-button "Save" (jetpacs-action "glasspane.call.save" :args args :capture-fields (list id))
                      :variant "filled") :spacing 8)
     :spacing 8)))

(defun glasspane-org-reader--on-call-edit (args params)
  "Open an argument draft identified by ARGS and PARAMS without evaluating it."
  (let* ((name (plist-get args :buffer)) (pos (plist-get args :pos))
         (tick (plist-get args :tick)) (scope (plist-get args :scope))
         (buffer (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buffer (integerp pos) (integerp tick) (stringp scope))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos "glasspane.call.edit")) 'rejected)
     (glasspane-org-reader--source-edit
      (jetpacs-shell-notify "Save or cancel the open Babel draft first." (plist-get params :surface))
      'rejected)
     (t
      (condition-case err
          (with-current-buffer buffer
            (org-with-wide-buffer
             (if (or (/= tick (buffer-chars-modified-tick))
                     (not (<= (point-min) pos (point-max))))
                 'stale
               (let* ((element (org-element-at-point pos))
                      (bounds (and (eq (org-element-type element) 'babel-call)
                                   (eql pos (org-element-property :post-affiliated element))
                                   (glasspane-org-reader--call-argument-bounds element))))
                 (if (not (and bounds (<= (- (cdr bounds) (car bounds)) glasspane-org-reader--call-edit-limit)))
                     'rejected
                   (setq glasspane-org-reader--source-edit
                         (list :kind 'call :buffer name :pos pos :tick tick :scope scope
                               :surface (plist-get params :surface) :bounds bounds
                               :text (buffer-substring-no-properties (car bounds) (cdr bounds))
                               :id (jetpacs-wire-id "gp-call-edit"
                                                    (format "%s/%d/%d" name pos
                                                            (cl-incf glasspane-org-reader--source-edit-sequence)))))
                   (jetpacs-buffer-defer-refresh (plist-get params :surface))
                   'accepted)))))
        (error (jetpacs-shell-notify (jetpacs-error-label err) (plist-get params :surface)) 'rejected))))))

(defun glasspane-org-reader--call-valid-arguments-p (value prefix suffix)
  "Whether VALUE remains entirely within the arguments between PREFIX and SUFFIX.
Use Org's parser without resolving any Babel expressions."
  (and (stringp value) (<= (length value) glasspane-org-reader--call-edit-limit)
       (not (string-match-p "[\n\r]" value))
       (with-temp-buffer
         (insert prefix value suffix)
         (delay-mode-hooks (org-mode))
         (let* ((element (org-element-at-point (point-min)))
                (bounds (and (eq (org-element-type element) 'babel-call)
                             (glasspane-org-reader--call-argument-bounds element))))
           (and bounds (= (car bounds) (1+ (length prefix)))
                (= (- (cdr bounds) (car bounds)) (length value)))))))

(defun glasspane-org-reader--on-call-save (args params)
  "Save captured argument ARGS from PARAMS without executing the Babel call.
Require the original source and disk revision; preserve everything outside
its parentheses.  Failed writes roll back the buffer and retain the draft."
  (let* ((session glasspane-org-reader--source-edit)
         (field (plist-get args :field))
         (value (glasspane-org-reader--source-field (plist-get params :fields) field))
         (buffer (and session (get-buffer (plist-get session :buffer)))))
    (cond
     ((not (and buffer (eq (plist-get session :kind) 'call)
                (equal (plist-get args :session) (plist-get session :id))
                (equal (plist-get params :surface) (plist-get session :surface)))) 'stale)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (and (stringp value) (<= (length value) glasspane-org-reader--call-edit-limit)
                (glasspane-org-reader--source-field-p field (plist-get session :id))
                (jetpacs-buffer-exposed-p (plist-get session :buffer) (plist-get session :pos)
                                         "glasspane.call.save"))) 'rejected)
     (t
      (condition-case err
          (with-current-buffer buffer
            (org-with-wide-buffer
             (let ((beg (car (plist-get session :bounds))) (end (cdr (plist-get session :bounds))))
               (cond
                ((or (/= (plist-get session :tick) (buffer-chars-modified-tick))
                     (not (verify-visited-file-modtime buffer)))
                 (jetpacs-shell-notify "Call changed. Cancel and reopen its arguments." (plist-get params :surface))
                 'stale)
                ((not (glasspane-org-reader--call-valid-arguments-p
                       value (buffer-substring-no-properties (plist-get session :pos) beg)
                       (save-excursion (goto-char end) (buffer-substring-no-properties end (line-end-position)))))
                 (jetpacs-shell-notify "Keep the arguments on one line with balanced parentheses." (plist-get params :surface))
                 'rejected)
                (t
                 (ebp-org--check-file buffer-file-name)
                 (ebp-org--with-clamped-io
                   (atomic-change-group
                     (save-excursion (goto-char beg) (delete-region beg end) (insert value))
                     (glasspane-org-save-and-invalidate buffer)))
                 (setq glasspane-org-reader--source-edit nil)
                 (jetpacs-buffer-defer-refresh (plist-get params :surface))
                 'accepted)))))
        (error (jetpacs-shell-notify (jetpacs-error-label err) (plist-get params :surface)) 'rejected))))))

(defun glasspane-org-reader--call-at (start limit)
  "Return (END . NODE) for a Babel call at START wholly before LIMIT.
Read only Org syntax here: resolving a call can evaluate header arguments
or open another file, so resolution belongs exclusively to the Play action."
  (when (and (not glasspane-org-reader--in-results)
             (looking-at-p "[ \t]*#\\+")
             (jetpacs-node-advertised-p "card")
             (jetpacs-node-advertised-p "row")
             (jetpacs-node-advertised-p "column"))
    (let ((element (org-element-at-point start)))
      (when (and (eq (org-element-type element) 'babel-call)
                 (eql start (org-element-property :begin element))
                 (org-element-property :call element))
        (let* ((pos (org-element-property :post-affiliated element))
               (end (save-excursion (goto-char pos) (line-beginning-position 2))))
          (when (<= end limit)
            (let* ((name (buffer-name))
                   (target (org-element-property :call element))
                   (arguments (org-element-property :arguments element))
                   (label (org-element-property :name element))
                   (inside (org-element-property :inside-header element))
                   (outside (org-element-property :end-header element))
                   (results (glasspane-org-reader--source-results element end limit))
                   (session glasspane-org-reader--source-edit)
                   (editing (and (eq (plist-get session :kind) 'call)
                                 (equal name (plist-get session :buffer))
                                 (eql pos (plist-get session :pos))
                                 (equal glasspane-org-reader--source-scope (plist-get session :scope))))
                   (bounds (glasspane-org-reader--call-argument-bounds element))
                   (edit (when (and (not editing) bounds
                                    (<= (- (cdr bounds) (car bounds)) glasspane-org-reader--call-edit-limit)
                                    (jetpacs-node-advertised-p "text_input")
                                    (jetpacs-node-advertised-p "button")
                                    (jetpacs-node-advertised-p "icon_button"))
                           (jetpacs-icon-button
                            "edit" (jetpacs-action "glasspane.call.edit"
                                                   :args (list :buffer name :pos pos :tick (buffer-chars-modified-tick)
                                                               :scope glasspane-org-reader--source-scope))
                            :content-description "Edit call arguments")))
                   (run (when (and (not editing) (jetpacs-node-advertised-p "icon_button"))
                          (jetpacs-icon-button
                           "play_arrow"
                           (jetpacs-action "glasspane.call.execute"
                                           :args (list :buffer name :pos pos
                                                       :tick (buffer-chars-modified-tick)))
                           :content-description "Execute Babel call")))
                   (node
                    (jetpacs-with-attrs
                     (jetpacs-card
                      (apply #'jetpacs-column
                             (append
                              (list
                               (jetpacs-row
                                (jetpacs-text "Call" :style "caption" :color "outline")
                                (jetpacs-with-attrs (jetpacs-text target :style "label") :weight 1)
                                run edit :align "center" :spacing 12)
                               (if editing (glasspane-org-reader--call-editor session)
                                 (jetpacs-text (if arguments (format "(%s)" arguments) "No arguments")
                                               :style "mono" :color "on_surface_variant")))
                              (when label (list (jetpacs-text (concat "Name · " label) :style "caption" :color "outline")))
                              (when inside (list (jetpacs-text (concat "Block options · " inside) :style "caption" :color "outline")))
                              (when outside (list (jetpacs-text (concat "Call options · " outside) :style "caption" :color "outline")))
                              (cdr results) (list :spacing 6)))
                      :variant "outlined")
                     :pad '(:horizontal 12 :vertical 8)))
                   (bytes (jetpacs-buffer-node-bytes node))
                   (left (cdr-safe jetpacs-buffer-budget)))
              (when (or (null left) (<= bytes left))
                (when left (setcdr jetpacs-buffer-budget (- left bytes)))
                (when run (jetpacs-buffer-expose name pos "glasspane.call.execute"))
                (when edit (jetpacs-buffer-expose name pos "glasspane.call.edit"))
                (when editing (jetpacs-buffer-expose name pos "glasspane.call.save"))
                (cons (if results (car results) end) node)))))))))

(defun glasspane-org-reader--on-call-execute (args params)
  "Execute the exposed Babel call in ARGS from PARAMS and save its results.
Revalidate the source tick, call identity and disk before resolving arguments.
The explicit Play gesture uses the same Babel confirmation policy as the
source-block Play control.  No evaluation happens in the reader builder."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (tick (plist-get args :tick))
         (buffer (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buffer (integerp pos) (integerp tick))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos "glasspane.call.execute")) 'rejected)
     (t
      (condition-case err
          (with-current-buffer buffer
            (org-with-wide-buffer
             (if (or (not (derived-mode-p 'org-mode))
                     (/= tick (buffer-chars-modified-tick))
                     (not (<= (point-min) pos (point-max)))
                     (not (verify-visited-file-modtime buffer)))
                 'stale
               (save-excursion
                 (goto-char pos)
                 (let ((element (org-element-at-point)))
                   (if (not (and (eq (org-element-type element) 'babel-call)
                                 (eql pos (org-element-property :post-affiliated element))))
                       'stale
                     (ebp-org--check-file buffer-file-name)
                     (require 'ob-lob)
                     (ebp-org--with-clamped-io
                       ;; Play is the explicit execution request, as for source blocks.
                       (let ((org-confirm-babel-evaluate nil))
                         (atomic-change-group
                           (unless (org-babel-lob-execute-maybe)
                             (user-error "Babel call target could not be resolved"))
                           (glasspane-org-save-and-invalidate buffer))))
                     (jetpacs-buffer-defer-refresh (plist-get params :surface))
                     'accepted))))))
        (error (jetpacs-shell-notify (jetpacs-error-label err) (plist-get params :surface))
               'rejected))))))

(defconst glasspane-org-reader--footnote-limit 16384
  "Maximum editable footnote length, bounded before building the dialog.")

(defvar glasspane-org-reader--footnote-dialog nil
  "The outstanding footnote editor and its source snapshot, or nil.")

(defvar glasspane-org-reader--footnote-sequence 0
  "Sequence of action-created footnote dialogs; never read by builders.")

(defun glasspane-org-reader--footnote-record (pos)
  "Resolve the reference at POS to an editable definition in the current buffer.
Org owns normal, named inline and anonymous reference syntax and lookup.
Return nil for an undefined reference.  Preserve separators outside the body."
  (save-excursion
    (goto-char pos)
    (let* ((reference (org-element-context))
           (label (org-element-property :label reference)))
      (when (and (eq (org-element-type reference) 'footnote-reference)
                 (eql pos (org-element-property :begin reference)))
        (let ((element
               (if (eq (org-element-property :type reference) 'inline) reference
                 (when-let* ((definition (org-footnote-get-definition label)))
                   (goto-char (nth 1 definition))
                   (org-element-context)))))
          (when (memq (org-element-type element) '(footnote-definition footnote-reference))
            (let* ((start (org-element-property :begin element))
                   (finish (min (point-max) (org-element-property :end element)))
                   (inline (eq (org-element-type element) 'footnote-reference))
                   (beg (or (org-element-property :contents-begin element)
                            (save-excursion (goto-char start) (search-forward "]" finish) (point))))
                   (end (if inline (org-element-property :contents-end element)
                          (save-excursion
                            (goto-char (or (org-element-property :contents-end element) beg))
                            (skip-chars-backward " \t\r\n" beg) (point)))))
              (when (<= (- finish start) glasspane-org-reader--footnote-limit)
                (list :buffer (buffer-name) :pos pos :tick (buffer-chars-modified-tick)
                      :label label :inline inline :start start :finish finish :beg beg :end end
                      :text (buffer-substring-no-properties beg end)
                      :original (buffer-substring-no-properties start finish)
                      :prefix (buffer-substring-no-properties start beg)
                      :suffix (buffer-substring-no-properties end finish))))))))))

(defun glasspane-org-reader--footnote-close ()
  "Retire the current footnote dialog without changing its source."
  (let ((session glasspane-org-reader--footnote-dialog))
    (setq glasspane-org-reader--footnote-dialog nil)
    (when-let* ((client (jetpacs-client))
                (request (plist-get session :request-id)))
      (ignore-errors (ebp-client-abandon client request)))))

(defun glasspane-org-reader--footnote-spec (session)
  "Build the reading and editing dialog from the explicit SESSION snapshot."
  (let ((id (plist-get session :id))
        (field (plist-get session :field))
        (text (plist-get session :text))
        (editing (plist-get session :editing)))
    (jetpacs-column
     (jetpacs-text (if-let* ((label (plist-get session :label)))
                      (concat "Footnote · " label) "Footnote") :style "title")
     (if editing
         (jetpacs-text-input field :value text :label "Footnote text"
                             :single-line nil :min-lines 3 :max-lines 4
                             :max-length glasspane-org-reader--footnote-limit)
       (if (string-empty-p text) (jetpacs-text "Empty footnote" :color "outline")
         (glasspane-org-reader--prose-node text)))
     (jetpacs-row
      (jetpacs-spacer :weight 1)
      (jetpacs-button (if editing "Cancel" "Close") (jetpacs-dialog-dismiss) :variant "text")
      (if editing
          (jetpacs-button "Save"
                      (jetpacs-action "glasspane.footnote.save"
                                      :args (list :session id)
                                      :capture-fields (list field)))
        (jetpacs-button "Edit"
                        (jetpacs-action "glasspane.footnote.edit" :args (list :session id))))
      :spacing 8)
     :spacing 12)))

(defun glasspane-org-reader--show-footnote (session)
  "Show SESSION outside action dispatch, keeping its origin for refresh.
The remote Save action commits synchronously; dismissal never writes."
  (glasspane-org-reader--footnote-close)
  (when-let* ((client (jetpacs-client)))
    (setq session (plist-put session :request-id nil))
    (setq glasspane-org-reader--footnote-dialog session)
    (condition-case err
        (let ((request
               (ebp-client-dialog-show
                client (plist-get session :id) (glasspane-org-reader--footnote-spec session)
                :callback (lambda (_status _result _error)
                            (when (eq glasspane-org-reader--footnote-dialog session)
                              (setq glasspane-org-reader--footnote-dialog nil))))))
          (if request (setf (plist-get session :request-id) request)
            (setq glasspane-org-reader--footnote-dialog nil)))
      (error (setq glasspane-org-reader--footnote-dialog nil)
             (jetpacs-shell-notify (jetpacs-error-label err) (plist-get session :surface))))))

(defun glasspane-org-reader--on-footnote-open (args params)
  "Open ARGS' exposed footnote in a dialog originating from PARAMS.
Reject arbitrary buffers/positions, and resolve definitions only in the
allowlisted source file.  Opening this transient UI has no document effect."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (tick (plist-get args :tick))
         (buffer (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buffer (integerp pos) (integerp tick)
                (jetpacs-buffer-exposed-p name pos "glasspane.footnote.open"))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (and (jetpacs-client) (jetpacs-granted-p "surfaces.dialog"))) 'rejected)
     (t
      (condition-case err
          (with-current-buffer buffer
            (org-with-wide-buffer
             (ebp-org--check-file buffer-file-name)
             (cond
              ((or (/= tick (buffer-chars-modified-tick))
                   (not (<= (point-min) pos (point-max)))) 'stale)
              (t
               (let ((session (glasspane-org-reader--footnote-record pos)))
                 (if (not session)
                     (progn (jetpacs-shell-notify "Footnote missing or too large to edit here."
                                                  (plist-get params :surface)) 'rejected)
                   (let ((id (jetpacs-wire-id "gp-footnote"
                                              (format "%s/%d/%d" name pos
                                                      (cl-incf glasspane-org-reader--footnote-sequence)))))
                     (setq session (append session (list :id id :field "footnote-text"
                                                         :surface (plist-get params :surface))))
                     (jetpacs-flow-continue (lambda () (glasspane-org-reader--show-footnote session)))
                     'accepted)))))))
        (error (jetpacs-shell-notify (jetpacs-error-label err) (plist-get params :surface)) 'rejected))))))

(defun glasspane-org-reader--footnote-valid-p (session value)
  "Whether VALUE stays one complete Org definition inside SESSION's delimiters.
Parsing a temporary copy rejects structural escapes, extra definitions and
unbalanced inline brackets without executing content or touching the source."
  (with-temp-buffer
    (insert (plist-get session :prefix) value (plist-get session :suffix))
    (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
    (goto-char (point-min))
    (let ((element (org-element-context)))
      (and (eq (org-element-type element)
               (if (plist-get session :inline) 'footnote-reference 'footnote-definition))
           (= (org-element-property :end element) (point-max))
           (or (not (plist-get session :inline))
               (= (org-element-property :contents-end element)
                  (+ 1 (length (plist-get session :prefix)) (length value))))))))

(defun glasspane-org-reader--on-footnote-edit (args params)
  "Switch ARGS' reading dialog from PARAMS to a compact footnote editor.
Use a fresh dialog identity so the retired preview cannot save or dismiss
the new editor.  The original source snapshot continues to guard Save."
  (let ((session glasspane-org-reader--footnote-dialog))
    (if (not (and session (plist-get session :request-id)
                  (not (plist-get session :editing))
                  (equal (plist-get args :session) (plist-get session :id))
                  (equal (plist-get params :dialog_id) (plist-get session :id))))
        'stale
      (let ((editor (copy-sequence session)))
        (setq editor (plist-put editor :editing t))
        (setf (plist-get editor :id)
              (jetpacs-wire-id "gp-footnote-edit"
                               (format "%s/%d" (plist-get session :id)
                                       (cl-incf glasspane-org-reader--footnote-sequence))))
        (jetpacs-flow-continue (lambda () (glasspane-org-reader--show-footnote editor)))
        'accepted))))

(defun glasspane-org-reader--on-footnote-save (args params)
  "Commit captured footnote text from ARGS and PARAMS before accepting Save.
Only the outstanding dialog can write.  Source/disk drift rejects stale
drafts, and failed writes roll back the buffer while leaving the dialog open."
  (let* ((session glasspane-org-reader--footnote-dialog)
         (buffer (and session (get-buffer (plist-get session :buffer))))
         (value (glasspane-org-reader--source-field (plist-get params :fields)
                                                   (plist-get session :field)))
         (surface (plist-get session :surface)))
    (cond
     ((not (and session buffer (plist-get session :editing) (plist-get session :request-id)
                (equal (plist-get args :session) (plist-get session :id))
                (equal (plist-get params :dialog_id) (plist-get session :id)))) 'stale)
     ((not (and (stringp value) (<= (length value) glasspane-org-reader--footnote-limit))) 'rejected)
     (t
      (condition-case err
          (with-current-buffer buffer
            (org-with-wide-buffer
             (cond
              ((or (/= (plist-get session :tick) (buffer-chars-modified-tick))
                   (not (verify-visited-file-modtime buffer))
                   (not (equal (plist-get session :original)
                               (buffer-substring-no-properties (plist-get session :start)
                                                               (plist-get session :finish)))))
               (jetpacs-shell-notify "Footnote source changed. Cancel and reopen it." surface)
               'stale)
              (t
               ;; An originally empty definition may have no separator after ].
               (when (and (not (plist-get session :inline))
                          (string-suffix-p "]" (plist-get session :prefix))
                          (not (string-empty-p value)))
                 (setq value (concat " " value)))
               (if (not (glasspane-org-reader--footnote-valid-p session value))
                   (progn (jetpacs-shell-notify "Keep the text inside one Org footnote definition." surface)
                          'rejected)
                 (ebp-org--check-file buffer-file-name)
                 (ebp-org--with-clamped-io
                   (atomic-change-group
                     (save-excursion
                       (goto-char (plist-get session :beg))
                       (delete-region (plist-get session :beg) (plist-get session :end))
                       (insert value))
                     (glasspane-org-save-and-invalidate buffer)))
                 (glasspane-org-reader--footnote-close)
                 (jetpacs-buffer-defer-refresh surface)
                 'accepted)))))
        (error (jetpacs-shell-notify (jetpacs-error-label err) surface) 'rejected))))))

(defconst glasspane-org-reader--literal-background "#80808024"
  "Subtle translucent background shared by inline literals and examples.")

(defun glasspane-org-reader--emphasis-spans (text &optional inline weight color source-start)
  "Render Org emphasis in TEXT as native spans without its delimiters.
INLINE parses a heading or label; otherwise parse full Org elements so code,
examples, keywords and fixed-width text remain literal.  WEIGHT and COLOR
supply base styling.  SOURCE-START maps TEXT to the current Org buffer for
footnote links.  Only the temporary presentation copy is modified.
Return nil when there is no emphasis or the native budget cannot fit it.
RichSpan has no strike decoration; strike-through loses only its markers."
  (when (and (jetpacs-node-advertised-p "rich_text")
             (or (string-match-p "[*_/+~=]" text)
                 (and source-start (string-search "[fn:" text))))
    (let* ((source-buffer (current-buffer))
           (tree (if inline
                     (org-element-parse-secondary-string text (org-element-restriction 'paragraph))
                   (with-temp-buffer
                     (insert text)
                     (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
                     (org-element-parse-buffer))))
           (objects (org-element-map tree '(bold italic underline strike-through code verbatim footnote-reference)
                      #'identity))
           spans exposed)
      (when objects
        (with-temp-buffer
          (insert text)
          (dolist (object objects)
            (let* ((type (org-element-type object))
                   (beg (org-element-property :begin object))
                   (cb (or (org-element-property :contents-begin object) (1+ beg)))
                   (ce (or (org-element-property :contents-end object)
                           (+ cb (length (org-element-property :value object)))))
                   (attributes (pcase type
                                 ('bold '(gp-weight "bold"))
                                 ('italic '(gp-italic t))
                                 ('underline '(gp-underline t))
                                 ((or 'code 'verbatim)
                                  (list 'gp-mono t 'gp-color "secondary"
                                        'gp-bg glasspane-org-reader--literal-background)))))
              (when (and (not (eq type 'footnote-reference))
                         (<= (point-min) beg cb ce (1+ ce) (point-max)))
                (put-text-property beg cb 'gp-hide t)
                (put-text-property ce (1+ ce) 'gp-hide t)
                (when attributes (add-text-properties cb ce attributes)))))
          (when source-start
            (dolist (object objects)
              (when (and (eq (org-element-type object) 'footnote-reference)
                         (not (org-element-lineage object '(footnote-reference))))
                (let* ((beg (org-element-property :begin object))
                       (end (- (org-element-property :end object)
                               (or (org-element-property :post-blank object) 0)))
                       (pos (+ source-start (1- beg)))
                       (label (or (org-element-property :label object) "note"))
                       (action (with-current-buffer source-buffer
                                 (jetpacs-action "glasspane.footnote.open"
                                                 :args (list :buffer (buffer-name) :pos pos
                                                             :tick (buffer-chars-modified-tick))))))
                  (when (<= (point-min) beg end (point-max))
                    (set-text-properties beg end nil)
                    (add-text-properties beg (1+ beg)
                                         (list 'gp-replacement (concat "[" label "]")
                                               'gp-action action 'gp-color "primary" 'gp-underline t))
                    (put-text-property (1+ beg) end 'gp-hide t)
                    (push pos exposed))))))
          (goto-char (point-min))
          (while (< (point) (point-max))
            (let* ((beg (point))
                   (end (next-property-change beg nil (point-max))))
              (unless (get-text-property beg 'gp-hide)
                (push (jetpacs-span
                       (or (get-text-property beg 'gp-replacement)
                           (buffer-substring-no-properties beg end))
                       :font-weight (or (get-text-property beg 'gp-weight) weight)
                       :italic (get-text-property beg 'gp-italic)
                       :underline (get-text-property beg 'gp-underline)
                       :mono (get-text-property beg 'gp-mono)
                       :color (or (get-text-property beg 'gp-color) color)
                       :bg (get-text-property beg 'gp-bg)
                       :on-tap (get-text-property beg 'gp-action))
                      spans))
              (goto-char end))))
        (setq spans (nreverse spans))
        (let ((remaining (car-safe jetpacs-buffer-budget))
              (bytes-left (cdr-safe jetpacs-buffer-budget))
              (bytes (jetpacs-buffer-node-bytes (jetpacs-rich-text spans :style "body"))))
          (when (and (or (null remaining) (<= (length spans) remaining))
                     (or (null bytes-left) (<= bytes bytes-left)))
            (when remaining (setcar jetpacs-buffer-budget (- remaining (length spans))))
            (when bytes-left (setcdr jetpacs-buffer-budget (- bytes-left bytes)))
            (with-current-buffer source-buffer
              (dolist (pos exposed)
                (jetpacs-buffer-expose (buffer-name) pos "glasspane.footnote.open")))
            spans))))))

(defun glasspane-org-reader--prose-node (text &optional inline color source-start)
  "Render TEXT with Org emphasis hidden, optionally INLINE and in COLOR.
SOURCE-START is its original buffer position for interactive footnotes.
Retain the original syntax when no emphasis or native support is available."
  (if-let* ((spans (glasspane-org-reader--emphasis-spans text inline nil color source-start)))
      (jetpacs-rich-text spans :style "body")
    (jetpacs-text text :syntax "org" :color color)))

(defun glasspane-org-reader--centered-block (text italic &optional source-start)
  "Center each authored line of TEXT, applying ITALIC for verse.
SOURCE-START enables footnote links.  Split parsed spans to preserve lines."
  (let ((spans (or (glasspane-org-reader--emphasis-spans text t nil nil source-start)
                   (list (jetpacs-span text))))
        line lines)
    (dolist (span spans)
      (let ((parts (split-string (plist-get span :text) "\n" nil)))
        (while parts
          (let ((part (pop parts)))
            (unless (string-empty-p part)
              (let ((piece (copy-sequence span)))
                (setq piece (plist-put piece :text part))
                (when italic (setq piece (plist-put piece :italic t)))
                (push piece line))))
          (when parts
            (push (nreverse line) lines)
            (setq line nil)))))
    (push (nreverse line) lines)
    (apply #'jetpacs-column
           (append
            (mapcar (lambda (items)
                      (if items (jetpacs-rich-text items :style "body")
                        (jetpacs-text " " :style "body")))
                    (nreverse lines))
            (list :align "center" :fill t :spacing 0)))))

(defun glasspane-org-reader--export-code-node (beg end)
  "Render literal export code from BEG to END with prepared Emacs faces.
Copy only face properties into a temporary buffer: visibility, display and
keymaps cannot hide export text or create actions.  Never fontify or export
from a builder; Jetpacs owns conversion of Emacs faces into native spans."
  (let ((code (buffer-substring beg end)) (name (buffer-name)) spans)
    (with-temp-buffer
      (let ((cursor 0))
        (while (< cursor (length code))
          (let ((next (next-property-change cursor code (length code))))
            (insert (propertize (substring-no-properties code cursor next)
                                'face (or (get-text-property cursor 'face code)
                                          (get-text-property cursor 'font-lock-face code))))
            (setq cursor next))))
      (let ((jetpacs-buffer-monospace t)
            (jetpacs-buffer-emit-colors t)
            (jetpacs-buffer-span-action-function nil))
        (goto-char (point-min))
        (while (< (point) (point-max))
          (setq spans (nconc spans (jetpacs-buffer-line-spans (point) (line-end-position) name)))
          (when (< (line-end-position) (point-max))
            (setq spans (nconc spans (list (jetpacs-span "\n" :mono t)))))
          (forward-line))))
    (jetpacs-rich-text (or spans (list (jetpacs-span "" :mono t))) :style "mono")))

(defun glasspane-org-reader--prose-block-at (start limit)
  "Return (END . NODE) for an Org presentation block at START before LIMIT.
Quotes have a left rule; verse/center preserve centered lines.  Examples,
fixed-width text, comments and exports are literal.  Special blocks have
folding titled cards.  Read Org's parsed extents, never execute or export
content, and keep unsupported or oversized blocks as source text."
  (when (looking-at-p "[ \t]*[#:]")
    (let* ((element (org-element-at-point start))
           (type (org-element-type element)))
      (when (and (memq type '(quote-block verse-block center-block example-block
                                         fixed-width comment-block comment export-block special-block))
                 (eql start (org-element-property :begin element)))
        (let* ((pos (org-element-property :post-affiliated element))
               (end (save-excursion
                      (goto-char (org-element-property :end element))
                      (skip-chars-backward " \t\n")
                      (min (point-max) (line-beginning-position 2))))
               (beg (save-excursion (goto-char pos) (line-beginning-position 2)))
               (body-end (save-excursion
                           (goto-char (org-element-property :end element))
                           (skip-chars-backward " \t\n") (line-beginning-position))))
          (when (<= end limit)
            (cons
             end
             (when (and (jetpacs-node-advertised-p "box")
                        (jetpacs-node-advertised-p "column")
                        (or (not (memq type '(export-block special-block)))
                            (and (jetpacs-node-advertised-p "card")
                                 (jetpacs-node-advertised-p "collapsible")
                                 (jetpacs-node-advertised-p "rich_text")
                                 (<= (count-lines beg body-end) jetpacs-buffer-max-lines)))
                        (or (not (memq type '(verse-block center-block)))
                            (and (jetpacs-node-advertised-p "rich_text")
                                 (<= (count-lines beg body-end) jetpacs-buffer-max-lines))))
               (let* ((text (if (memq type '(comment fixed-width)) (org-element-property :value element)
                              (buffer-substring-no-properties beg body-end)))
                      ;; Only the structural final newline is omitted, never indentation.
                      ;; Org already removes it from fixed-width values.
                      (text (if (and (not (eq type 'fixed-width)) (string-suffix-p "\n" text))
                                (substring text 0 -1) text))
                      (metadata (buffer-substring-no-properties start pos))
                      ;; Account for the final tree once, including split verse spans.
                      (node
                       (let ((jetpacs-buffer-budget nil))
                         (let ((body
                                (pcase type
                                  ('quote-block
                                   (jetpacs-with-attrs
                                    (jetpacs-box
                                     (jetpacs-with-attrs
                                      (jetpacs-box
                                       (jetpacs-with-attrs
                                        (jetpacs-column (glasspane-org-reader--prose-node text nil nil beg) :fill t)
                                        :pad '(:start 12 :end 8 :vertical 6)))
                                      :bg "surface" :pad '(:start 3)))
                                    :bg "secondary"))
                                  ((or 'verse-block 'center-block)
                                   (glasspane-org-reader--centered-block text (eq type 'verse-block) beg))
                                  ((or 'comment-block 'comment)
                                   (jetpacs-text text :style "caption" :color "outline"))
                                  ((or 'export-block 'special-block)
                                   (jetpacs-card
                                    (jetpacs-collapsible
                                     (jetpacs-claim-node-id
                                      (jetpacs-wire-id (if (eq type 'export-block) "gp-export" "gp-special")
                                                       (format "%s/%s/%d" (buffer-name)
                                                               glasspane-org-reader--source-scope pos)))
                                     (jetpacs-text (concat (or (org-element-property :type element) "Text")
                                                           (if (eq type 'export-block) " export" ""))
                                                  :style "label" :color "on_surface_variant")
                                     (if (eq type 'export-block)
                                         (glasspane-org-reader--export-code-node beg (+ beg (length text)))
                                       (let ((content (glasspane-org-reader--prose-node text nil nil beg))
                                             (parameters (org-element-property :parameters element)))
                                         (if (not parameters) content
                                           (jetpacs-column
                                            (jetpacs-text parameters :style "caption" :color "outline")
                                            content :spacing 6)))))
                                    :variant "outlined"))
                                  (_
                                   (jetpacs-with-attrs
                                    (jetpacs-box
                                     (jetpacs-with-attrs
                                      (jetpacs-column (jetpacs-text text :style "mono") :fill t)
                                      :padding 12))
                                    :bg glasspane-org-reader--literal-background :corner 6)))))
                           (jetpacs-with-attrs
                            (jetpacs-box
                             (if (string-empty-p metadata) body
                               (jetpacs-column
                               (jetpacs-text (string-trim-right metadata) :style "caption" :color "outline")
                               body :spacing 6)))
                            :pad '(:horizontal 12 :vertical 8)))))
                      (spans 0)
                      (bytes (jetpacs-buffer-node-bytes node))
                      (left (car-safe jetpacs-buffer-budget))
                      (bytes-left (cdr-safe jetpacs-buffer-budget)))
                 (cl-labels ((count-spans (item)
                               (when (listp item)
                                 (cl-incf spans (length (plist-get item :spans)))
                                 (mapc #'count-spans (plist-get item :children)))))
                   (count-spans node))
                 (when (and (or (null left) (<= spans left))
                            (or (null bytes-left) (<= bytes bytes-left)))
                   (when left (setcar jetpacs-buffer-budget (- left spans)))
                   (when bytes-left (setcdr jetpacs-buffer-budget (- bytes-left bytes)))
                   node))))))))))

(defun glasspane-org-reader--text-nodes (text start)
  "Render TEXT from START with native checkboxes, tables, images and code.
Keep all other text, continuation lines, and block examples in source order.
Without a source position or native support, retain plain Org text."
  (if (not (and (integerp start) (derived-mode-p 'org-mode)))
      (unless (string-blank-p text) (list (jetpacs-text text :syntax "org")))
    (let ((limit (+ start (length text))) (cursor start)
          (checkboxes (and (not glasspane-org-reader--in-results)
                           (jetpacs-node-advertised-p "checkbox")
                           (jetpacs-node-member-advertised-p "checkbox" "state")
                           (jetpacs-node-member-advertised-p "box" "on_long_tap")))
          nodes)
      (cl-labels ((flush (end)
                    (let ((plain (substring text (- cursor start) (- end start))))
                      (unless (string-blank-p plain)
                        (push (glasspane-org-reader--prose-node (string-trim-right plain) nil nil cursor) nodes)))))
        (save-excursion
          (goto-char start)
          (while (< (point) limit)
            (let* ((line-start (point))
                   (next (min limit (1+ (line-end-position))))
                   (at-start (= line-start (line-beginning-position)))
                   (definition (and at-start (looking-at-p "\\[fn:")
                                    (let ((element (org-element-at-point line-start)))
                                      (and (eq (org-element-type element) 'footnote-definition)
                                           (eql line-start (org-element-property :begin element))
                                           (min limit (org-element-property :end element))))))
                   (table (and at-start (glasspane-org-reader--table-at line-start limit)))
                   (image (and at-start (not table)
                               (glasspane-org-reader--image-at line-start limit)))
                   (source (and at-start (not table) (not image)
                                (glasspane-org-reader--source-at line-start limit)))
                   (call (and at-start (not table) (not image) (not source)
                              (glasspane-org-reader--call-at line-start limit)))
                   (prose (and at-start (not table) (not image) (not source) (not call)
                               (glasspane-org-reader--prose-block-at line-start limit)))
                   (block (or table image source call prose))
                   (record (and at-start checkboxes (not block)
                                (glasspane-org-reader--checkbox-record line-start))))
              (cond
               (definition
                (flush line-start)
                (setq next definition cursor definition))
               (block
                (setq next (car block))
                (when (cdr block)
                  (flush line-start)
                  (push (cdr block) nodes)
                  (setq cursor next)))
               (record
                (flush line-start)
                (push (glasspane-org-reader--checkbox-node record) nodes)
                (setq cursor next)))
              (goto-char next))))
        (if (and (null nodes) (= cursor start))
            (unless (string-blank-p text)
              (push (glasspane-org-reader--prose-node text nil nil start) nodes))
          (flush limit)))
      (nreverse nodes))))

(defun glasspane-org-reader--on-checkbox (args params)
  "Apply checkbox ARGS from PARAMS and synchronously save before acceptance.
Revalidate exposure, source tick, Org item identity and disk freshness.  Org
owns checkbox transitions and statistics; Glasspane owns the native gestures."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (tick (plist-get args :tick))
         (state (plist-get args :state))
         (buffer (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buffer (integerp pos) (integerp tick)
                (member state '(nil "indeterminate")))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos "glasspane.checkbox")) 'rejected)
     (t
      (condition-case nil
          (with-current-buffer buffer
            (org-with-wide-buffer
             (if (or (/= tick (buffer-chars-modified-tick))
                     (not (<= (point-min) pos (point-max)))
                     (not (verify-visited-file-modtime buffer)))
                 'stale
               (let ((record (glasspane-org-reader--checkbox-record pos)))
                 (if (not (and record (= pos (plist-get record :pos))))
                     'stale
                   (ebp-org--check-file buffer-file-name)
                   (ebp-org--with-clamped-io
                     (save-excursion
                       (goto-char pos)
                       (let ((mark-active nil))
                         (atomic-change-group
                           (unless (equal state (plist-get record :state))
                             (org-toggle-checkbox (when (equal state "indeterminate") '(16))))
                           (glasspane-org-save-and-invalidate buffer)))))
                   (jetpacs-buffer-defer-refresh (plist-get params :surface))
                   'accepted)))))
        (error 'rejected))))))

(defun glasspane-org-reader--body-nodes (n drawers)
  "Render N's body, replacing DRAWERS with their visible contents.
Source offsets preserve prose order around each drawer.  Hidden drawers emit
no section; the heading's native tonal icons directly show or hide contents."
  (let* ((body (or (plist-get n :body) ""))
         (start (plist-get n :body-start))
         (cursor 0)
         nodes)
    (when (integerp start)
      (dolist (drawer drawers)
        (let ((beg (- (plist-get drawer :begin) start))
              (end (- (plist-get drawer :end) start)))
          (when (and (<= cursor beg) (<= beg end) (<= end (length body)))
            (let ((before (substring body cursor beg)))
              (dolist (node (glasspane-org-reader--text-nodes before (+ start cursor)))
                (push node nodes)))
            (when-let* ((section (glasspane-org-reader--drawer-node drawer)))
              (push section nodes))
            (setq cursor end)))))
    (let ((after (substring body cursor)))
      (dolist (node (glasspane-org-reader--text-nodes after (and start (+ start cursor))))
        (push node nodes)))
    (nreverse nodes)))

(defun glasspane-org-reader--content-nodes (n file tokens &optional skip-props)
  "Render N's visible drawers, body and children from FILE using TOKENS.
SKIP-PROPS omits properties owned by the detail view.  Jetpacs's native drawer
icons and overlays directly control visibility without extra fold headers."
  (let* ((drawers (glasspane-org-reader--drawers n skip-props))
         (properties (cl-find "PROPERTIES" drawers
                              :key (lambda (drawer) (plist-get drawer :name))
                              :test #'equal)))
    (delq nil
          (append
           ;; The outline reader omits the metadata Properties drawer from
           ;; :body; Logbook stays in :body and is replaced at its offset.
           (when (and properties
                      (or (not (integerp (plist-get n :body-start)))
                          (<= (plist-get properties :end)
                              (plist-get n :body-start))))
             (list (glasspane-org-reader--drawer-node properties)))
           (glasspane-org-reader--body-nodes n drawers)
           (mapcar (lambda (child)
                     (glasspane-org-reader--heading-node child file tokens))
                   (plist-get n :children))))))

(defconst glasspane-org-reader--duplicate-ttl-s 86400
  "Offline ttl for the queued Duplicate (SPEC 14.1; plan T4, reader:89).
A day: the token lives Emacs-side, so a replay after reconnect still
names the heading the user meant, and anything older is better dropped
than sprung on a file edited since.")

(defconst glasspane-org-reader--priority-color "warning"
  "Span color for priority cookies (matches the agenda cards).")
(defconst glasspane-org-reader--overdue-color "error"
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
  (jetpacs-with-semantics
   (jetpacs-menu
    (mapcar (lambda (op)
              (jetpacs-menu-item (nth 0 op) (nth 2 op) :icon (nth 1 op)))
            (glasspane-org-reader--heading-ops token archive buffer pos
                                               clocked)))
   ;; SPEC 16.4: without a name the trigger announces as its icon.
   :name "Heading actions"))

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

(defun glasspane-org-reader--todo-spans (todo)
  "Render TODO with its source buffer's native Org keyword face.
Use the public buffer span walker so inherited faces, custom keyword colors
and color normalization follow the same rules as Emacs buffer presentation."
  (when todo
    (let ((face (org-get-todo-face todo))
          (jetpacs-buffer-emit-colors t)
          (jetpacs-buffer-monospace nil))
      (with-temp-buffer
        (insert (propertize (concat todo " ") 'face face))
        (jetpacs-buffer-line-spans (point-min) (point-max) (buffer-name))))))

(defun glasspane-org-reader--heading-header (n &optional areas)
  "Build tree node N's inline TODO/title and right-aligned AREAS.
AREAS are effective memberships resolved in the source document.  Ordinary
tags stay below the title without duplicating the elevated Area chips."
  (let* ((title (plist-get n :title))
         (todo (plist-get n :todo))
         (title-start (when (and (integerp (plist-get n :pos)) (derived-mode-p 'org-mode))
                        (save-excursion
                          (goto-char (plist-get n :pos))
                          (let ((case-fold-search nil))
                            (when (and (looking-at org-complex-heading-regexp)
                                       (equal title (match-string-no-properties 4)))
                              (match-beginning 4))))))
         (priority (plist-get n :priority))
         (tags (cl-remove-if (lambda (tag) (member tag areas))
                             (plist-get n :tags))))
    (if (string-empty-p (or title ""))
        (jetpacs-text (or (plist-get n :line) "") :syntax "org")
      (let ((headline
             (jetpacs-rich-text
              (append (glasspane-org-reader--todo-spans todo)
                      (or (glasspane-org-reader--emphasis-spans title t "bold" "on_surface" title-start)
                          (list (jetpacs-span title :font-weight "bold"
                                              :color "on_surface")))))))
        (jetpacs-column
         (if areas
             (jetpacs-row
              (jetpacs-with-attrs headline :weight 1)
              (jetpacs-with-attrs (glasspane-ui-tag-chips areas t) :weight 1)
              :fill t :align "center" :spacing 8)
           headline)
         (when priority
           (jetpacs-rich-text
            (list (jetpacs-span (format "Priority %s" priority)
                                :color glasspane-org-reader--priority-color))
            :style "caption"))
         (glasspane-org-reader--meta-line n)
         (glasspane-ui-tag-chips tags)
         :spacing 4)))))

(defun glasspane-org-reader-swipe-sides (token archive)
  "The (START . END) per-side swipe pair for a heading's minted pair.
Rightward reveals the todo cycle (green); leftward the base archive
(red) — `jetpacs.org.archive' with the descriptor-level confirm, so the
Companion asks before the event exists (SPEC 14.1).  Shared with the
agenda/tasks cards."
  (cons (jetpacs-swipe
         (list (jetpacs-swipe-action
                "Cycle" :icon "check" :color "success"
                :on-trigger (jetpacs-action "heading.todo-cycle"
                                            :args (list :token token)))))
        (and archive
             (jetpacs-swipe
              (list (jetpacs-swipe-action
                     "Archive" :icon "archive" :color "error"
                     :on-trigger (jetpacs-action
                                  "jetpacs.org.archive"
                                  :args (list :token archive)
                                  :confirm "Archive this subtree?")))))))

(defun glasspane-org-reader--heading-node (n file tokens)
  "Render tree node N from FILE to a foldable `jetpacs-collapsible'.
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
         (areas (glasspane-org-item-tag-group-members
                 `((file . ,file) (pos . ,pos) (tags . ,(plist-get n :tags)))
                 glasspane-area-tag-group))
         (header (glasspane-org-reader--heading-header n areas))
         (drawer-controls
          (jetpacs-org-render-drawer-controls
           (glasspane-org-reader--drawers n) buffer t)))
    (when token
      (jetpacs-buffer-expose buffer pos "jetpacs.org.heading"))
    (jetpacs-collapsible
     ;; A retained file and its drilled subtree share one surface document.
     ;; Keep the first fold's identity and claim a distinct ID for each copy.
     (jetpacs-claim-node-id
      (jetpacs-wire-id "fold" (format "%s/%d" file pos)))
     (apply #'jetpacs-row
            (append
             (list (jetpacs-with-attrs header :weight 1))
             drawer-controls
             (when token
               (list
                (jetpacs-icon-button
                 "open_in_new"
                 (jetpacs-action "heading.tap" :args (list :token token))
                 :content-description "Open heading")
                (glasspane-org-reader-heading-menu
                 token archive buffer pos (ebp-org-clocked-in-p pos))))
             (list :spacing 4 :align "center")))
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
  (let* ((tokens (glasspane-org-reader--mint nodes set))
         (glasspane-org-reader--source-scope set)
         (context jetpacs-files-editor-context)
         (mark-pos (and (equal (plist-get context :path) true)
                        (plist-get context :mark-pos))))
    (cl-labels ((contains-mark-p (node)
                  (or (and (integerp mark-pos)
                           (integerp (plist-get node :pos))
                           (= (plist-get node :pos) mark-pos))
                      (cl-some #'contains-mark-p
                               (plist-get node :children)))))
      ;; LazyColumn honors `scroll_here' only on one of its direct children,
      ;; so a nested target marks the top-level fold that contains it.
      (mapcar (lambda (n)
                (let ((rendered
                       (glasspane-org-reader--heading-node n true tokens)))
                  (if (contains-mark-p n)
                      (jetpacs-with-attrs rendered :scroll_here t)
                    rendered)))
              nodes))))

;;;; Entry points

(defun glasspane-org-reader--without-footnote-sections (nodes)
  "Return NODES without definition sections, preserving the original records.
Honor Org's configured footnote heading and the conventional singular/plural
names.  This is presentation only; source definitions remain editable."
  (cl-loop for node in nodes
           unless (member (downcase (or (plist-get node :title) ""))
                          (append '("footnote" "footnotes")
                                  (when (stringp org-footnote-section)
                                    (list (downcase org-footnote-section)))))
           collect (plist-put (copy-sequence node) :children
                              (glasspane-org-reader--without-footnote-sections
                               (plist-get node :children)))))

(defun glasspane-org-reader--reader-parts (file query)
  "(NODES KEPT TOTAL) for FILE with sparse filter QUERY over top levels.
Signals `user-error' on a query that doesn't parse (the caller's error
caption), and the root-policy conditions of the access funnel."
  (glasspane-org-reader--with-file
   file
   (lambda (true)
     (let* ((records (ebp-org-outline-cap
                      (ebp-org-outline-collect (point-min) (point-max) nil)))
            (tree (glasspane-org-reader--without-footnote-sections (ebp-org-outline-tree records)))
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
     (let* ((glasspane-org-reader--source-scope (format "%s/%d" (or set "reader-subtree") pos))
            (beg (point))
            (end (save-excursion (org-end-of-subtree t t)))
            (records (ebp-org-outline-cap
                      (ebp-org-outline-collect beg end t)))
            (tree (glasspane-org-reader--without-footnote-sections (ebp-org-outline-tree records)))
            (root (car tree)))
       (when root
         (jetpacs-buffer-forget-exposed (buffer-name))
         (let ((tokens (glasspane-org-reader--mint
                        tree (or set "reader-subtree"))))
           (let ((controls (jetpacs-org-render-drawer-controls
                            (glasspane-org-reader--drawers root skip-props)
                            (buffer-name) t)))
             (append
              (when controls
                (list (apply #'jetpacs-row
                             (append controls (list :arrange "end" :spacing 4)))))
              (glasspane-org-reader--content-nodes root true tokens
                                                   skip-props)))))))))

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
   :hint "Find a heading…"
   :label "Filter outline"
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
              (list
               (jetpacs-column
                (jetpacs-text "Outline" :style "title")
                (jetpacs-text "Tap a heading to unfold it. Use the open button for details."
                              :style "caption")
                :spacing 4)
               (glasspane-org-reader--filter-input path))
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
                       (jetpacs-material3-assist-chip
                        "Clear"
                        :on-tap (jetpacs-action "files.filter"
                                                :args (list :path path
                                                            :value "")))
                       :align "center")))
              (or nodes
                  (list (jetpacs-text
                         (if active "No matches" "No headings found.")
                         :style "caption")))
              (list :spacing 12 :content-padding 16)))))))

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
      nil))))

(defun glasspane-org-reader--adapter-transition (path presentation)
  "Apply the stock Org transition discipline to PATH and PRESENTATION."
  (jetpacs-reader-org--transition path presentation))

(defun glasspane-org-reader-prepare-landing (path)
  "Prepare PATH for a contextual Files landing in the foldable reader.
The detail screen's `Open in file' affordance is an app opinion over
the generic Files mark-position seam.  Clear a prior sparse filter and
refile presentation so the requested heading is actually present in the
direct LazyColumn children, and select the rendered presentation."
  (jetpacs-reader-state-set path :presentation 'reader)
  (jetpacs-reader-state-set path :gp-fold-mode 'tree)
  (jetpacs-reader-state-set path :gp-filter-query "")
  (jetpacs-reader-state-set path :gp-filter-kept nil)
  (jetpacs-reader-state-set path :gp-filter-total nil))

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
  '("heading.menu" "files.filter" "files.toggle-refile" "heading.reorder"
    "glasspane.checkbox" "glasspane.source.edit" "glasspane.source.save" "glasspane.source.cancel" "glasspane.call.execute"
    "glasspane.call.edit" "glasspane.call.save" "glasspane.call.cancel"
    "glasspane.footnote.open" "glasspane.footnote.edit" "glasspane.footnote.save")
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
    (jetpacs-defaction "glasspane.footnote.open" #'glasspane-org-reader--on-footnote-open
                       :any-surface t :doc "Read and edit the definition of this exposed Org footnote")
    (jetpacs-defaction "glasspane.footnote.edit" #'glasspane-org-reader--on-footnote-edit
                       :any-surface t :doc "Switch this footnote dialog from reading to editing")
    (jetpacs-defaction "glasspane.footnote.save" #'glasspane-org-reader--on-footnote-save
                       :any-surface t :doc "Save this dialog's footnote text after checking source and disk freshness")
    (jetpacs-defaction "glasspane.call.edit" #'glasspane-org-reader--on-call-edit
                       :any-surface t :doc "Open an inline argument draft for this Babel call")
    (jetpacs-defaction "glasspane.call.save" #'glasspane-org-reader--on-call-save
                       :any-surface t :doc "Save call arguments without executing the call")
    (jetpacs-defaction "glasspane.call.cancel" #'glasspane-org-reader--on-source-cancel
                       :any-surface t :doc "Discard the inline Babel argument draft")
    (jetpacs-defaction "glasspane.call.execute" #'glasspane-org-reader--on-call-execute
                       :any-surface t :doc "Execute this Babel call through Org and save its results")
    (jetpacs-defaction "glasspane.source.edit" #'glasspane-org-reader--on-source-edit
                       :any-surface t :doc "Open an inline draft of this source block's code and language")
    (jetpacs-defaction "glasspane.source.save" #'glasspane-org-reader--on-source-save
                       :any-surface t :doc "Save the captured code and language after revalidating their source")
    (jetpacs-defaction "glasspane.source.cancel" #'glasspane-org-reader--on-source-cancel
                       :any-surface t :doc "Discard the inline code draft without changing Org")
    (jetpacs-defaction "glasspane.checkbox"
                       #'glasspane-org-reader--on-checkbox
                       :any-surface t
                       :doc "Toggle an Org checkbox or mark it in progress, then save")
    (jetpacs-defaction "heading.menu"
                       #'glasspane-org-reader--on-heading-menu
                       :any-surface t
                       :doc "Long-press sheet: the app's per-heading delta")
    (jetpacs-defaction "files.filter"
                       #'glasspane-org-reader--on-files-filter
                       :any-surface t
                       :doc "Filter the current Org document with one grammar")
    (jetpacs-defaction "files.toggle-refile"
                       #'glasspane-org-reader--on-toggle-refile
                       :any-surface t
                       :doc "Toggle the current document's tree/refile presentation")
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
  (glasspane-org-reader--footnote-close)
  (setq glasspane-org-reader--refile-lists nil)
  (setq glasspane-org-reader--source-edit nil)
  (jetpacs-reader-org-register))

(provide 'glasspane-org-reader)
;;; glasspane-org-reader.el ends here
