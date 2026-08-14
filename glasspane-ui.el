;;; glasspane-ui.el --- Glasspane settings, shared UI state, the at-ref funnel -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The keystone rung (docs/PLAN-glasspane-app.md, G3): the app's
;; settings surface, the shared view state the later rungs read, and
;; `glasspane-ui--at-ref' — the token→resolve→classify funnel every
;; heading mutation in G4+ rides.
;;
;; Retired against v1 (the plan's retirement list + G3 section):
;;
;; - The whole rendered⇄plain files block — mode vars, the editor
;;   body/actions seam hooks, org toolbar/FAB wiring, checkbox.toggle,
;;   the after-save invalidation, the files-open hook, and the
;;   files.toggle-read verb.  Foundation-owned now
;;   (jetpacs-org-render.el:740-851: the `jetpacs.org.view-mode' verb,
;;   the seam claims, the after-save cache bust).  The v1 block was
;;   trimodal: the app's own foldable reader and the refile drag list
;;   have no foundation home and port in G4 with their own surfacing —
;;   `glasspane-ui--files-filter', the reader filter's write target,
;;   therefore survives HERE, and files.toggle-refile moves to G4 with
;;   the state it flips.
;; - file.view: T2 ruling "route through the jetpacs.files.open verb or
;;   drop" — it existed for v1's cached UIs, which no v3 device has.
;; - The widget/capture-tile push hooks and their memo (v1 ui:53-70):
;;   no widget/tile node vocabulary (FOUNDATION-GAPS #1).  The
;;   reminder sync hook moves to G5's `jetpacs-reminders-set' callback.
;; - The vanilla-app block (v1 ui:107-108): the single-app contract is
;;   automatic in v3 (jetpacs-apps.el).
;; - The v1 nav fabric (defapp/define-view/tab-view/top-action): S1 —
;;   app identity and the chrome root live in glasspane.el (G0); the
;;   settings view is now a Settings satellite link plus a pushed
;;   chrome screen.  search.clear-filters registers in G6 beside the
;;   filter state it clears.
;; - The desktop-save auto-refresh block (v1 ui:603-620): the
;;   `jetpacs-shell-save-refresh-*' seam has no v3 counterpart; a
;;   device-side save invalidates through the foundation's files
;;   after-save seam, and a desktop edit lands on the next refresh.
;; - The duplicate `provide'.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'ebp)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-settings)
(require 'glasspane-org)

;; v1 hard-required glasspane-magit (it lives outside the app
;; directory); its port is out of the plan's scope, so the require
;; goes soft — nothing in this file calls into it.
(require 'glasspane-magit nil t)

(defcustom glasspane-org-custom-agendas nil
  "Alist of saved searches (NAME . QUERY) in the ebp-org grammar."
  :type '(alist :key-type string :value-type string)
  :group 'jetpacs)

(defcustom glasspane-babel-timeout 30
  "Seconds before a phone-triggered babel execution is abandoned.
Best-effort: the timer can't interrupt a synchronous subprocess
mid-call, but it fires between process reads and stops a runaway
block from wedging the bridge forever.  Consumed by the table/babel
rung (G6); registered in its settings section."
  :type 'integer :group 'jetpacs)

;;;; Shared view state (S2)
;;
;; `jetpacs-ui-state' is read-through only in v3, so the v1 ui-state
;; anchors become app defvars whose SINGLE writer is the action
;; handler below; the widgets re-seed from them on every render.

(defvar glasspane-ui-agenda-anchor nil
  "The agenda's anchor date (\"YYYY-MM-DD\"), or nil for today.
Written only by the agenda.* handlers; the agenda builders (G5) read
it back each render.")

(defvar glasspane-ui-agenda-selected-date nil
  "The month grid's selected day (\"YYYY-MM-DD\"), or nil.
Written only by the agenda.* handlers.")

(defvar glasspane-ui--files-filter ""
  "Sparse-filter query for the org reader body; empty = everything.
Persistence across re-renders IS the feature (the v1 lesson at
glasspane-search.el:39-48): the reconciled input model would clear a
device-side draft, so the submitted query lives here and the reader
\(G4) re-seeds its input from it.")

;;;; Detail extension hooks (consumed by G4, contributed to by G7)

(defvar glasspane-ui-detail-nodes-functions nil
  "Abnormal hook: functions from a detail REF to extra section nodes.
App layers (notes backlinks, SRS flashcards) contribute detail-view
sections here; each returns a node list or nil.  An erroring function
costs its own section, never the body.")

(defvar glasspane-ui-detail-toolbar-functions nil
  "Abnormal hook: functions from a detail REF to floating-toolbar nodes.
App layers contribute chip nodes after the built-in Refile/Archive
pair; each returns a node list or nil.  An erroring function costs
its own chips, never the toolbar.")

;;;; The capture FAB (FOUNDATION-GAPS #2)

(defun glasspane-ui--capture-fab ()
  "The capture FAB every daily surface passes to its chrome `:fab' slot.
v1's app-default FAB registry (`jetpacs-apps-set-default-fab') has no
v3 successor, so each screen authors this node itself; the coupling to
glasspane-capture.el is the verb string alone — the handler registers
there, and a tap before that load lands answers `rejected' from the
action shim, never a signal."
  (jetpacs-icon-button "add" (jetpacs-action "org.capture.show")
                       :content-description "Capture"
                       :variant "filled" :size "large"))

;;;; Deferral

(defun glasspane-ui--defer-refresh (params)
  "Schedule a repush of PARAMS' surface once the dispatch returns (D2).
A dialog-context event carries no `:surface' (SPEC 14.4); the nil
falls through to `jetpacs-shell-push's zero-arg meaning — the flow
owner's surface, which `jetpacs-flow-continue' keeps."
  (let ((surface (plist-get params :surface)))
    (jetpacs-flow-continue
     (lambda ()
       (ignore-errors (jetpacs-shell-push surface))))))

;;;; The at-ref funnel (S4/S5 — the classifier every later rung copies)

(defun glasspane-ui--at-ref (args fn &optional save)
  "Resolve ARGS' `:token' to its heading and run FN with point there.
Returns the SPEC 14.4 status the calling handler answers with:

  no/unknown token          -> `stale'    (swept set: the list moved)
  `ebp-org-refused'         -> `rejected' (file policy — permanent)
  `ebp-org-unresolved'      -> `stale'    (heading gone or ambiguous)
  any other signal          -> `rejected' (mutation did not land)
  FN returned               -> `accepted' (effect durable, see below)

With SAVE non-nil the buffer is saved through
`glasspane-org--save-and-invalidate'.  Deliberately NOT
`ebp-org-with-mutation': the engine defers saves to an idle timer,
which leaves the file not-yet-on-disk for flows that read it back
immediately (capture finalize, offline-queue replay) and fires the
after-save refresh outside `glasspane-org--inhibit-save-refresh's
extent.  Save timing is app policy and stays here; resolution and
cache discipline are the engine's (`ebp-org-resolve-ref',
`ebp-org-cache-invalidate')."
  (let ((ref (ebp-org-token-ref (plist-get args :token)
                                :owner "glasspane")))
    (if (null ref)
        'stale
      (condition-case err
          (let ((marker (ebp-org-resolve-ref ref)))
            (unwind-protect
                (with-current-buffer (marker-buffer marker)
                  (org-with-wide-buffer
                   (goto-char marker)
                   (funcall fn))
                  (if save
                      (glasspane-org--save-and-invalidate)
                    (ebp-org-cache-invalidate 'glasspane)))
              (set-marker marker nil))
            'accepted)
        (ebp-org-refused 'rejected)
        (ebp-org-unresolved 'stale)
        (error
         ;; The raw error stays in *Messages*; the wire never carries
         ;; it (SPEC 23.3).
         (message "glasspane: heading action failed: %s"
                  (jetpacs-error-label err))
         (jetpacs-toast "That heading action failed")
         'rejected)))))

;;;; Token minting (S5 — the mint side of the funnel above)

(defun glasspane-ui--tokenize-tap (items set)
  "ITEMS with a `token' cell attached, minted as one bulk SET (S5).
Refs whose file left the org roots would SIGNAL at mint time
\(ebp-org.el's policy-at-mint rule), so they are filtered first — the
item still renders, just untappable — as is any overflow past
`ebp-org-token-set-max', the per-set cap.  Tap tokens only: cards
built from these carry no swipe arms.  Minted even when ITEMS is
empty, because the replace sweep on SET is what retires the previous
render's tokens — which is also why one screen at a time may use a
given SET."
  (let* ((mintable (cl-remove-if-not
                    (lambda (it)
                      (let ((f (plist-get (alist-get 'ref it) :file)))
                        (and (stringp f) (not (string-empty-p f))
                             (ebp-org-file-allowed-p f))))
                    items))
         (mintable (seq-take mintable ebp-org-token-set-max))
         (refs (mapcar (lambda (it) (alist-get 'ref it)) mintable))
         (tokens (ebp-org-ref-tokens refs :set set :owner "glasspane"))
         (table (make-hash-table :test #'eq)))
    (cl-loop for it in mintable for tok in tokens
             do (puthash it tok table))
    (mapcar (lambda (it)
              (let ((tok (gethash it table)))
                (if tok (cons (cons 'token tok) it) it)))
            items)))

;;;; TODO keyword helpers (pure)

(defun glasspane-ui--bare-keyword (word)
  "WORD without its fast-access annotation: \"TODO(t!)\" -> \"TODO\"."
  (if (string-match "^\\([a-zA-Z0-9_-]+\\)" word)
      (match-string 1 word)
    word))

(defun glasspane-ui--global-todo-keywords ()
  "Flat list of all global TODO keywords from `org-todo-keywords'."
  (let ((kws nil))
    (dolist (seq (default-value 'org-todo-keywords))
      (dolist (w (cdr seq))
        (unless (string-equal w "|")
          (push (glasspane-ui--bare-keyword w) kws))))
    (nreverse kws)))

(defun glasspane-ui--split-todo-sequence (seq)
  "Split `org-todo-keywords' entry SEQ into (ACTIVE . FINISHED) lists.
Keywords keep their fast-access annotations (\"TODO(t!)\").  Mirrors
org's rule for sequences without an explicit \"|\": the last keyword
is the finished state."
  (let ((words (cdr seq))
        (active nil)
        (finished nil)
        (target 'active))
    (dolist (w words)
      (if (equal w "|")
          (setq target 'finished)
        (if (eq target 'active)
            (push w active)
          (push w finished))))
    (setq active (nreverse active)
          finished (nreverse finished))
    (when (and (null finished) (not (member "|" words)))
      (setq finished (last active)
            active (butlast active)))
    (cons active finished)))

;;;; Settings nodes

(defun glasspane-ui--tag-options ()
  "The global tag names from `org-tag-alist', strings only, distinct.
Group markers (`:startgroup' and friends) are cons-free symbols the
enum cannot carry; duplicates would fail the widget's SPEC 4.3
distinctness check at build time."
  (cl-remove-duplicates
   (cl-remove-if-not #'stringp
                     (mapcar (lambda (x) (if (consp x) (car x) x))
                             org-tag-alist))
   :test #'equal :from-end t))

(defun glasspane-ui--tags-enum ()
  "The editable global-tags chip list."
  (let ((tags (glasspane-ui--tag-options)))
    (jetpacs-enum-list "settings-tags"
                       (mapcar (lambda (tg) (jetpacs-enum-option tg tg))
                               tags)
                       :value tags
                       :multi-select t
                       :allow-add t
                       :on-change (jetpacs-action "settings.tags"))))

(defun glasspane-ui--line-numbers-node ()
  "The Display block: the line-number mode as a single-select enum.
The `:render' of the registry entry `glasspane-ui-register' installs —
it draws on the Settings root, replacing the schema-derived control."
  (let ((value (pcase jetpacs-line-numbers
                 ('absolute "Absolute")
                 ('relative "Relative")
                 (_ "Off"))))
    (jetpacs-column
     (jetpacs-text "Line numbers" :style "label")
     (jetpacs-text "Line numbers in the buffer view and editor."
                   :style "caption")
     (jetpacs-enum-list "settings-linenum"
                        (mapcar (lambda (label)
                                  (jetpacs-enum-option label label))
                                '("Off" "Absolute" "Relative"))
                        :value value
                        :on-change (jetpacs-action "settings.line-numbers"))
     :spacing 4)))

(defun glasspane-ui--agenda-card (name query)
  "One saved-search card with its edit/delete affordances."
  (jetpacs-card
   (list
    (jetpacs-row
     ;; The text column carries the flex weight itself: the client
     ;; renders columns fillMaxWidth, so an unweighted one swallows
     ;; the row and pushes the buttons off-screen.
     (jetpacs-with-attrs
      (jetpacs-column (jetpacs-text name :style "label")
                      (jetpacs-text query :style "body")
                      :spacing 2)
      :weight 1)
     (jetpacs-icon-button "edit"
                          (jetpacs-action "settings.agenda.edit"
                                          :args (list :name name))
                          :content-description "Edit search")
     (jetpacs-icon-button "delete"
                          (jetpacs-action "settings.agenda.delete"
                                          :args (list :name name))
                          :content-description "Delete search")
     :align "center"))))

(defun glasspane-ui--sequence-cards ()
  "One card per global TODO sequence, with edit/delete affordances.
The error arm costs the section, never the screen — and shows the
SPEC 23.3 label, not the raw error text."
  (condition-case err
      (cl-loop for seq in (or (default-value 'org-todo-keywords)
                              '((sequence "TODO" "DONE")))
               for i from 0
               collect
               (let* ((split (glasspane-ui--split-todo-sequence seq))
                      (active (mapcar #'glasspane-ui--bare-keyword
                                      (car split)))
                      (finished (mapcar #'glasspane-ui--bare-keyword
                                        (cdr split))))
                 (jetpacs-card
                  (list
                   (jetpacs-row
                    (jetpacs-with-attrs
                     (jetpacs-column
                      (jetpacs-text (format "Sequence %d" (1+ i))
                                    :style "label")
                      (jetpacs-text
                       (concat (mapconcat #'identity active ", ")
                               " | "
                               (mapconcat #'identity finished ", "))
                       :style "body")
                      :spacing 2)
                     :weight 1)
                    (jetpacs-icon-button
                     "edit"
                     (jetpacs-action "settings.todo.edit"
                                     :args (list :index i))
                     :content-description "Edit sequence")
                    (jetpacs-icon-button
                     "delete"
                     (jetpacs-action "settings.todo.delete"
                                     :args (list :index i))
                     :content-description "Delete sequence")
                    :align "center")))))
    (error (list (jetpacs-text (format "Error loading sequences: %s"
                                       (jetpacs-error-label err))
                               :style "caption")))))

(defun glasspane-ui--settings-body ()
  "The app settings screen body.
The Display block lives on the Settings ROOT via the registry entry
\(`glasspane-ui--line-numbers-node'), and the schema-driven org
sections are the Settings surface's own — this screen holds only what
needs authored management UI.  lazy_column, not column: the scaffold
body has no scroll container on the client."
  (apply #'jetpacs-lazy-column
         (append
          (list (jetpacs-section-header "Saved Searches")
                (jetpacs-text "Manage your saved search queries."
                              :style "caption"))
          (mapcar (lambda (cell)
                    (glasspane-ui--agenda-card (car cell) (cdr cell)))
                  glasspane-org-custom-agendas)
          (list (jetpacs-button "New Saved Search"
                                (jetpacs-action "settings.agenda.edit")
                                :variant "outlined")
                (jetpacs-divider)
                (jetpacs-section-header "Global TODO Sequences")
                (jetpacs-text
                 "Manage your global TODO states and workflows."
                 :style "caption"))
          (glasspane-ui--sequence-cards)
          (list (jetpacs-button "Add Sequence"
                                (jetpacs-action "settings.todo.edit"
                                                :args (list :index -1))
                                :variant "outlined")
                (jetpacs-divider)
                (jetpacs-section-header "Global Org Tags")
                (jetpacs-text
                 "Manage the global tag list (org-tag-alist)."
                 :style "caption")
                (glasspane-ui--tags-enum)))))

(defun glasspane-ui--settings-screen (back)
  "The pushed Glasspane settings screen."
  (jetpacs-chrome-screen "Glasspane" (glasspane-ui--settings-body)
                         :back back))

(defun glasspane-ui--settings-link ()
  "The Settings-root satellite row leading to the app settings screen."
  (jetpacs-chrome-row "Glasspane"
                      :subtitle "Saved searches, TODO workflows, org tags"
                      :icon "menu_book"
                      :on-tap (jetpacs-action "glasspane.settings.open")
                      :key "glasspane-settings-link"))

;;;; Dialogs (S3 — one shape: ebp-client-dialog-show + captured fields)

(defvar glasspane-ui--settings-dialog nil
  "The live settings dialog, (:request-id ID :params PARAMS), or nil.
PARAMS are the OPENING event's — a Save/Delete fired from inside the
dialog arrives in dialog context with no `:surface' (SPEC 14.4), so
its refresh needs the surface the dialog was opened from.")

(defun glasspane-ui-settings-dialog-close ()
  "Retire the live settings dialog (the S3 handler-side dismissal).
`ebp-client-abandon' sends rpc.cancel; the Companion concludes the
dialog with error 1301, which the show callback treats as a no-op."
  (let ((sheet glasspane-ui--settings-dialog))
    (setq glasspane-ui--settings-dialog nil)
    (when-let* ((client (jetpacs-client))
                (request-id (plist-get sheet :request-id)))
      (ignore-errors (ebp-client-abandon client request-id)))))

(cl-defun glasspane-ui--show-dialog (id spec &key params on-submit)
  "Show SPEC as dialog ID; stash the request for handler-side abandon.
ON-SUBMIT, when given, receives the conclusion's `:fields' plist —
the `jetpacs-dialog-submit' route; dialogs whose Save is a remote
action instead conclude through `glasspane-ui-settings-dialog-close'
in that action's handler.  Nowhere else shows settings dialogs, so
one live request slot is enough."
  (when-let* ((client (jetpacs-client)))
    ;; The slot holds ONE request and this is its only writer, so a
    ;; still-live prior dialog is abandoned here rather than orphaned
    ;; (its device dialog would otherwise linger with no way back to
    ;; it), and each callback clears only its own id: the first show's
    ;; 1301 must not clear the second show's slot, or the Save handler
    ;; finds no request to close and loses the origin params.  CELL
    ;; carries the id into the callback, which cannot close over
    ;; REQUEST-ID — the show that returns it is that binding's init.
    (glasspane-ui-settings-dialog-close)
    (let* ((cell (list nil))
           (request-id
            (ebp-client-dialog-show
             client id spec
             :callback
             (lambda (status result _error)
               ;; Dismissal and the abandon's 1301 both land here.
               (when (equal (plist-get glasspane-ui--settings-dialog
                                       :request-id)
                            (car cell))
                 (setq glasspane-ui--settings-dialog nil))
               ;; Outside the identity guard: a submitted conclusion
               ;; runs its handler whoever owns the slot by then.
               (when (and on-submit (equal status "submitted"))
                 (funcall on-submit (plist-get result :fields)))))))
      (when request-id
        (setcar cell request-id)
        (setq glasspane-ui--settings-dialog
              (list :request-id request-id :params params))))))

(defun glasspane-ui--show-todo-dialog (idx params)
  "Show the TODO-sequence editor for sequence IDX (-1 = new).
The sequence is re-read HERE, not in the dispatching handler: the
show runs deferred, and the list may have changed in between."
  (let* ((seqs (or (default-value 'org-todo-keywords)
                   '((sequence "TODO" "DONE"))))
         (seq (if (>= idx 0) (nth idx seqs) '(sequence "TODO" "|" "DONE"))))
    (if (null seq)
        (jetpacs-toast "That sequence no longer exists")
      ;; Raw keyword strings, fast-access keys and all ("TODO(t!)"),
      ;; so an untouched save round-trips losslessly.  Seeding is the
      ;; field's `:value' (S2): no state round-trip — the Save action
      ;; captures the fields and echoes them back in its event.
      (let* ((type (car seq))
             (split (glasspane-ui--split-todo-sequence seq))
             (active (mapconcat #'identity (car split) ", "))
             (finished (mapconcat #'identity (cdr split) ", ")))
        (glasspane-ui--show-dialog
         "glasspane-todo-edit"
         (apply #'jetpacs-column
                (append
                 (list
                  (jetpacs-text (if (>= idx 0) "Edit Sequence" "New Sequence")
                                :style "title")
                  (jetpacs-text
                   "Comma-separated states; fast keys like TODO(t) are kept."
                   :style "caption")
                  (jetpacs-text-input "todo-active" :label "Active States"
                                      :value active :single-line t)
                  (jetpacs-text-input "todo-finished"
                                      :label "Finished States"
                                      :value finished :single-line t)
                  (apply #'jetpacs-row
                         (append
                          (list (jetpacs-spacer :weight 1))
                          (when (>= idx 0)
                            (list (jetpacs-button
                                   "Delete"
                                   (jetpacs-action "settings.todo.delete"
                                                   :args (list :index idx))
                                   :variant "text")))
                          (list (jetpacs-button "Cancel"
                                                (jetpacs-dialog-dismiss)
                                                :variant "text")
                                (jetpacs-spacer :width 8)
                                (jetpacs-button
                                 "Save"
                                 (jetpacs-action
                                  "settings.todo.save"
                                  :args (list :index idx
                                              :type (symbol-name type))
                                  :capture-fields '("todo-active"
                                                    "todo-finished")))))))
                 (list :spacing 8)))
         :params params)))))

(defun glasspane-ui--show-agenda-dialog (name params)
  "Show the saved-search editor for NAME (nil = new)."
  (let ((query (or (and name (cdr (assoc name glasspane-org-custom-agendas)))
                   "")))
    (glasspane-ui--show-dialog
     "glasspane-agenda-edit"
     (jetpacs-column
      (jetpacs-text (if name "Edit Saved Search" "New Saved Search")
                    :style "title")
      (jetpacs-text "Display name and a query in the search grammar."
                    :style "caption")
      (jetpacs-text-input "agenda-name" :label "Name"
                          :value (or name "") :single-line t)
      (jetpacs-text-input "agenda-query" :label "Query String"
                          :value query)
      (apply #'jetpacs-row
             (append
              (list (jetpacs-spacer :weight 1))
              (when name
                (list (jetpacs-button
                       "Delete"
                       (jetpacs-action "settings.agenda.delete"
                                       :args (list :name name))
                       :variant "text")))
              (list (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)
                                    :variant "text")
                    (jetpacs-spacer :width 8)
                    (jetpacs-button
                     "Save"
                     (jetpacs-action
                      "settings.agenda.save"
                      :args (list :old-name name)
                      :capture-fields '("agenda-name" "agenda-query"))))))
      :spacing 8)
     :params params)))

(defun glasspane-ui--save-agenda (name query)
  "Store QUERY as saved search NAME (replacing) and persist."
  (setq glasspane-org-custom-agendas
        (append (assoc-delete-all name glasspane-org-custom-agendas)
                (list (cons name query))))
  (jetpacs-settings-save-variable 'glasspane-org-custom-agendas
                                  glasspane-org-custom-agendas))

(defun glasspane-ui--show-save-custom-dialog (query params)
  "Name-and-save dialog for the current agenda QUERY.
The v1 handler read the name with an inline `read-string' (ui:454);
the v3 no-prompt regime forbids that in the dispatch extent, so the
name is a captured dialog field and the save runs in the conclusion."
  (glasspane-ui--show-dialog
   "glasspane-agenda-name"
   (jetpacs-column
    (jetpacs-text "Save Search" :style "title")
    (jetpacs-text query :style "caption")
    (jetpacs-text-input "agenda-name" :label "Name"
                        :single-line t :autofocus t)
    (jetpacs-row
     (jetpacs-spacer :weight 1)
     (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
     (jetpacs-spacer :width 8)
     (jetpacs-button "Save"
                     (jetpacs-dialog-submit
                      :capture-fields '("agenda-name"))))
    :spacing 8)
   :params params
   :on-submit
   (lambda (fields)
     (let ((name (plist-get fields :agenda-name)))
       (if (or (not (stringp name))
               (string-empty-p (string-trim name)))
           (jetpacs-toast "Name cannot be empty")
         (setq name (string-trim name))
         (glasspane-ui--save-agenda name query)
         (jetpacs-shell-notify (format "Saved custom agenda: %s" name))
         (glasspane-ui--defer-refresh params))))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-ui--on-settings-open (_args params)
  "Push the app settings screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       ;; A deferred `jetpacs-chrome-push-screen' must catch its own
       ;; re-signal or a refused gate dies in a timer.
       (condition-case err
           (jetpacs-chrome-push-screen surface "glasspane-settings"
                                       #'glasspane-ui--settings-screen)
         (error (message "glasspane: settings push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-ui--on-line-numbers (args params)
  "Set `jetpacs-line-numbers'.  Single-select enum: `:value' is ONE
option value, or nil when the user deselected — which counts as Off."
  (let ((choice (plist-get args :value)))
    (if (and choice (not (stringp choice)))
        'rejected
      (jetpacs-settings-save-variable 'jetpacs-line-numbers
                                      (pcase choice
                                        ("Absolute" 'absolute)
                                        ("Relative" 'relative)
                                        (_ nil)))
      (jetpacs-toast (format "Line numbers: %s" (or choice "Off")))
      (glasspane-ui--defer-refresh params)
      'accepted)))

(defun glasspane-ui--on-tags (args params)
  "Rebuild `org-tag-alist' from the multi-select `:value' (a vector).
Existing alist entries keep their fast-select keys.  Deselecting every
chip sends a well-formed empty vector and writes nothing (the v1
contract — clearing every chip is not a bulk delete): that is
`accepted', with the deferred refresh re-seeding the chips from the
untouched alist; `rejected' is reserved for non-sequence junk and
non-string members."
  (let ((val (plist-get args :value)))
    (if (not (or (vectorp val) (proper-list-p val)))
        'rejected
      (let ((tags (append val nil)))
        (if (not (cl-every #'stringp tags))
            'rejected
          (when tags
            (setq org-tag-alist
                  (mapcar (lambda (tg) (or (assoc tg org-tag-alist) tg))
                          tags))
            (jetpacs-settings-save-variable 'org-tag-alist org-tag-alist)
            (jetpacs-shell-notify "Settings saved"))
          (glasspane-ui--defer-refresh params)
          'accepted)))))

(defun glasspane-ui--on-todo-edit (args params)
  "Open the sequence editor dialog for `:index' (-1 = new)."
  (let ((idx (plist-get args :index)))
    ;; A whole-valued integer can arrive as a float after the JSON
    ;; round trip (org.json emits the trailing .0).
    (when (numberp idx) (setq idx (truncate idx)))
    (cond
     ((not (integerp idx)) 'rejected)
     ((and (>= idx 0)
           (null (nth idx (or (default-value 'org-todo-keywords)
                              '((sequence "TODO" "DONE"))))))
      ;; The card outlived the list it was rendered from.
      (jetpacs-toast "That sequence no longer exists")
      (glasspane-ui--defer-refresh params)
      'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-ui--show-todo-dialog idx params)))
      'accepted))))

(defun glasspane-ui--on-agenda-edit (args params)
  "Open the saved-search editor dialog for `:name' (absent = new)."
  (let ((name (plist-get args :name)))
    (cond
     ((and name (not (stringp name))) 'rejected)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-ui--show-agenda-dialog name params)))
      'accepted))))

(defun glasspane-ui--on-agenda-delete (args params)
  "Delete saved search `:name'; fired from a card or the edit dialog."
  (let ((name (plist-get args :name)))
    (cond
     ((not (stringp name)) 'rejected)
     ((not (assoc name glasspane-org-custom-agendas))
      (glasspane-ui--defer-refresh params)
      'stale)
     (t
      (setq glasspane-org-custom-agendas
            (assoc-delete-all name glasspane-org-custom-agendas))
      (jetpacs-settings-save-variable 'glasspane-org-custom-agendas
                                      glasspane-org-custom-agendas)
      ;; From the dialog's Delete this event has no :surface — refresh
      ;; where the dialog was opened, then retire it.
      (let ((origin (or (plist-get glasspane-ui--settings-dialog :params)
                        params)))
        (glasspane-ui-settings-dialog-close)
        (jetpacs-shell-notify (format "Deleted saved search: %s" name))
        (glasspane-ui--defer-refresh origin))
      'accepted))))

(defun glasspane-ui--on-agenda-save (args params)
  "Save the edited search: fields captured by the dialog's Save action."
  (let* ((fields (plist-get params :fields))
         (old-name (plist-get args :old-name))
         (new-name (plist-get fields :agenda-name))
         (query (let ((q (plist-get fields :agenda-query)))
                  (if (stringp q) q ""))))
    (if (not (and (stringp new-name)
                  (not (string-empty-p (string-trim new-name)))))
        (progn (jetpacs-toast "Name cannot be empty")
               'rejected)
      (setq new-name (string-trim new-name))
      (when (and (stringp old-name) (not (equal old-name new-name)))
        (setq glasspane-org-custom-agendas
              (assoc-delete-all old-name glasspane-org-custom-agendas)))
      (glasspane-ui--save-agenda new-name query)
      (let ((origin (or (plist-get glasspane-ui--settings-dialog :params)
                        params)))
        (glasspane-ui-settings-dialog-close)
        (jetpacs-shell-notify "Saved custom agenda")
        (glasspane-ui--defer-refresh origin))
      'accepted)))

(defun glasspane-ui--on-agenda-save-custom (args params)
  "Name and save the agenda's current `:query' through a dialog."
  (let ((query (plist-get args :query)))
    (cond
     ((not (stringp query)) 'rejected)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-ui--show-save-custom-dialog query params)))
      'accepted))))

(defun glasspane-ui--on-agenda-today (_args params)
  "Reset the anchor and any month-grid selection back to today."
  (setq glasspane-ui-agenda-anchor nil
        glasspane-ui-agenda-selected-date nil)
  (glasspane-ui--defer-refresh params)
  'accepted)

(defun glasspane-ui--on-agenda-select-date (args params)
  "Select a day.  `:date' comes from a composed grid's per-cell args;
`:value' is what the curated month grid's on_day_tap injects."
  (let ((date (or (plist-get args :date) (plist-get args :value))))
    (if (and (stringp date)
             (string-match-p
              "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
        (progn
          (setq glasspane-ui-agenda-selected-date date)
          (glasspane-ui--defer-refresh params)
          'accepted)
      'rejected)))

(defun glasspane-ui--on-agenda-set-month (args params)
  "Anchor on the 1st of the month on_month_change reported (`:value')."
  (let ((month (plist-get args :value)))
    (if (and (stringp month)
             (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}\\'" month))
        (progn
          (setq glasspane-ui-agenda-anchor (concat month "-01"))
          (glasspane-ui--defer-refresh params)
          'accepted)
      'rejected)))

(defun glasspane-ui--on-files-filter (args params)
  "Store the reader's sparse filter (\"\" clears).  State only —
matching happens at render, in the G4 reader that seeds from the var."
  (let ((value (plist-get args :value)))
    (if (stringp value)
        (progn
          (setq glasspane-ui--files-filter value)
          (glasspane-ui--defer-refresh params)
          'accepted)
      'rejected)))

;;;; The settings after-set seam (T2)

(defun glasspane-ui-org-after-set (_sym _value)
  "Registry `:after-set' for org/calendar-derived entries.
The v1 `jetpacs-settings-after-set-hook' member's per-entry successor:
org-derived views are memoised, so every settings write over org or
calendar state must drop the memo or the phone keeps rendering stale
data.  G6's schema sections attach this to each such entry."
  (ebp-org-cache-invalidate 'glasspane))

;;;; Refresh hooks

(defun glasspane-ui--refresh-invalidate ()
  "An explicit refresh (pull-to-refresh, queue drain) recomputes
everything: drop the WHOLE org memo table, no namespace."
  (ebp-org-cache-invalidate))

(defun glasspane-ui--refresh-if-connected (&rest _)
  "Re-push the app surface when there's a live session.
Safe on any hook: a no-op while disconnected.  Invalidates the
extraction memo first — this runs on clock in/out, which mutate the
org buffer without necessarily saving it.  The clock hooks also fire
from `org-clock-out'/`org-clock-in-last' INSIDE the org.clock.*
handlers, so the push takes the D2 seam (the glasspane-clock--soon
shape): deferred past the dispatch extent when inside one, immediate
for a desktop M-x."
  (when (jetpacs-connected-p)
    (ebp-org-cache-invalidate 'glasspane)
    (let ((push (lambda () (jetpacs-shell-push "glasspane"))))
      (if (jetpacs-in-action-p)
          (jetpacs-flow-continue push)
        (funcall push)))))

(defun glasspane-ui-remove-hooks ()
  "Detach everything `glasspane-ui-register' hooked."
  (remove-hook 'jetpacs-shell-refresh-hook
               #'glasspane-ui--refresh-invalidate)
  (remove-hook 'org-clock-in-hook #'glasspane-ui--refresh-if-connected)
  (remove-hook 'org-clock-out-hook #'glasspane-ui--refresh-if-connected)
  (remove-hook 'jetpacs-teardown-functions #'glasspane-ui--on-teardown))

(defun glasspane-ui--on-teardown (owner)
  "Drop the UI hooks when OWNER is the Glasspane app.
`glasspane-owner' is read late and defensively: the entry file defines
it and `require's this one, so a back-`require' would cycle — and by
the time any teardown runs, the entry has long finished loading."
  (when (equal owner (bound-and-true-p glasspane-owner))
    (glasspane-ui-remove-hooks)))

;;;; Registration

(defconst glasspane-ui--verbs
  '("glasspane.settings.open"
    "settings.line-numbers"
    "settings.tags"
    "settings.todo.edit"
    "settings.agenda.edit"
    "settings.agenda.delete"
    "settings.agenda.save"
    "agenda.save-custom"
    "agenda.today"
    "agenda.select-date"
    "agenda.set-month"
    "files.filter")
  "The verbs this rung owns, for the register/unregister sweep.
settings.todo.save/.delete live with the sequence writers (G5),
search.clear-filters with the filter state it clears (G6),
files.toggle-refile with the reader surfacing (G4).")

(defun glasspane-ui-register ()
  "Register the UI verbs, the settings section/link, and the hooks.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers and
registry entries in place, and the link is re-added exactly once."
  ;; :any-surface — D1 GLOBAL verbs on the ef precedent
  ;; (glasspane-ef.el:361-366): the satellite link and the Display
  ;; section both draw on the Settings ROOT, and the screen they lead
  ;; to is pushed onto whatever surface was tapped, so every verb whose
  ;; only emission site is there arrives on a surface Glasspane does
  ;; not own and the owned-surface gate would refuse it before the
  ;; handler ran (jetpacs-surfaces.el:770-785).  The rest stay
  ;; owner-scoped: the save verbs fire from dialog conclusions, which
  ;; carry no `:surface' at all (SPEC 14.4), and the agenda/files verbs
  ;; from screens on this owner's own surface.
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "glasspane.settings.open"
                       #'glasspane-ui--on-settings-open
                       :any-surface t
                       :doc "Open Glasspane's settings management screen")
    (jetpacs-defaction "settings.line-numbers"
                       #'glasspane-ui--on-line-numbers
                       :any-surface t)
    (jetpacs-defaction "settings.tags" #'glasspane-ui--on-tags
                       :any-surface t)
    (jetpacs-defaction "settings.todo.edit" #'glasspane-ui--on-todo-edit
                       :any-surface t)
    (jetpacs-defaction "settings.agenda.edit"
                       #'glasspane-ui--on-agenda-edit
                       :any-surface t)
    (jetpacs-defaction "settings.agenda.delete"
                       #'glasspane-ui--on-agenda-delete
                       :any-surface t)
    (jetpacs-defaction "settings.agenda.save"
                       #'glasspane-ui--on-agenda-save)
    (jetpacs-defaction "agenda.save-custom"
                       #'glasspane-ui--on-agenda-save-custom)
    (jetpacs-defaction "agenda.today" #'glasspane-ui--on-agenda-today)
    (jetpacs-defaction "agenda.select-date"
                       #'glasspane-ui--on-agenda-select-date)
    (jetpacs-defaction "agenda.set-month"
                       #'glasspane-ui--on-agenda-set-month)
    (jetpacs-defaction "files.filter" #'glasspane-ui--on-files-filter)
    (jetpacs-settings-register-section
     "Glasspane"
     (list (list 'jetpacs-line-numbers
                 :label "Line numbers"
                 :render #'glasspane-ui--line-numbers-node)))
    (setq jetpacs-settings-links
          (cl-remove #'glasspane-ui--settings-link jetpacs-settings-links
                     :key #'cadr))
    ;; v1's settings view sat at order 80 among the app's views.
    (jetpacs-settings-add-link 80 #'glasspane-ui--settings-link))
  (add-hook 'jetpacs-shell-refresh-hook #'glasspane-ui--refresh-invalidate)
  ;; Depth 90: after glasspane-clock's assert/retire on the same
  ;; hooks, so the repush renders the notification state they set.
  (add-hook 'org-clock-in-hook #'glasspane-ui--refresh-if-connected 90)
  (add-hook 'org-clock-out-hook #'glasspane-ui--refresh-if-connected 90)
  (add-hook 'jetpacs-teardown-functions #'glasspane-ui--on-teardown))

(defun glasspane-ui-unregister ()
  "Drop the UI verbs, the settings section/link, and the hooks."
  (dolist (name glasspane-ui--verbs)
    (jetpacs-undefaction name))
  (jetpacs-settings-remove-section "Glasspane")
  (setq jetpacs-settings-links
        (cl-remove #'glasspane-ui--settings-link jetpacs-settings-links
                   :key #'cadr))
  (glasspane-ui-settings-dialog-close)
  (glasspane-ui-remove-hooks))

(provide 'glasspane-ui)
;;; glasspane-ui.el ends here
