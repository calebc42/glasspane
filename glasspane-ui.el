;;; glasspane-ui.el --- Glasspane settings, shared UI state, the at-ref funnel -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The keystone rung (docs/PLAN-glasspane-app.md, G3): the app's
;; settings surface, the shared view state the later rungs read, and
;; `glasspane-ui-at-ref' — the token→resolve→classify funnel every
;; heading mutation in G4+ rides.
;;
;; It also holds the rollback-only HUB (`glasspane-ui-home-screen', the
;; hub-wiring rung that punch-list #26 escalated), the authoritative PARA
;; destination table, and the capture FAB descriptor PA-3a contributes to
;; Jetpacs' app registry.  PA-3b replaced that hub root with Agenda; the hub
;; remains executable only behind `glasspane-ui-legacy-ia' until PA-4.  These
;; live beside shared state rather than in the entry so the entry keeps its
;; single job — identity and composition metadata.
;;
;; Retired against v1 (the plan's retirement list + G3 section):
;;
;; - The whole rendered⇄plain files block — mode vars, the editor
;;   body/actions seam hooks, org toolbar/FAB wiring, checkbox.toggle,
;;   the after-save invalidation, the files-open hook, and the
;;   files.toggle-read verb.  Foundation-owned now (the reusable
;;   reader/editor hosts, Org adapters, and after-save cache bust).  The
;;   v1 block was trimodal: the app's foldable reader and refile drag
;;   list ported in G4.  GR-2 moves their query/count/view state onto the
;;   reusable reader host's per-path store; no Files state remains here.
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
(require 'jetpacs-apps)
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
rung (G6); surfaced in the app's own settings section
\(`glasspane-ui-register') — the one app-opinion row left after the
§3 relocation moved the org/calendar schema to the foundation."
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

;;;; PARA composition rollback and capture FAB

(defvar glasspane-ui-legacy-ia nil
  "Non-nil restores Glasspane's pre-PARA navigation composition.
This is the PA-3/PA-4 soak rollback seam, not a user preference.  Change it
before calling `glasspane-register': registration snapshots the selected
integration pole while the screen builders read it at render time.")

(defun glasspane-ui-capture-fab (&optional _surface)
  "Return Glasspane's app-default capture FAB.
SURFACE is accepted for the `jetpacs-defapp' FAB-builder contract and is
otherwise unused.  In the PARA composition Jetpacs injects this node only
onto Glasspane-owned screens; the legacy rollback arm still authors it on
each historical daily screen.  The coupling to glasspane-capture.el is the
verb string alone — an early tap is rejected by the action shim, never a
signal."
  (jetpacs-icon-button "add" (jetpacs-action "org.capture.show")
                       :content-description "Capture"
                       :variant "filled" :size "large"))

(defun glasspane-ui-top-actions ()
  "Return Glasspane's destination-level top-bar actions.
Search is an app navigation opinion, so Glasspane authors its placement while
the shared chrome remains unaware of the downstream destination.  The rollback
composition keeps its historical bars byte-for-byte until PA-4 removes it."
  (unless glasspane-ui-legacy-ia
    (list (jetpacs-icon-button "search" (jetpacs-action "search.open")
                               :content-description "Search"))))

;; The PA-3d plan recorded this spelling before the sibling-private boundary
;; was enforced.  Keep it as a local compatibility name while screen modules
;; consume the public function above.
(defalias 'glasspane-ui--top-actions #'glasspane-ui-top-actions)

;;;; The hub (the home screen every ported surface hangs off)
;;
;; Punch-list #26: through G8 the app registered a dozen screen-opening
;; verbs and nothing emitted one — the G0 placeholder home was still the
;; root, so agenda/journal/search/views/review were code no finger could
;; reach.  The hub is the fix, and it lives HERE rather than in the entry
;; because this file already owns the shared view state and the FAB the
;; daily screens hang off; the entry keeps its one job, identity.

;; The entry's identity constants, declared for the compiler: this file
;; is `require'd BY glasspane.el, so a back-require would cycle.  Read
;; late (a screen builds long after the entry finished loading) — the
;; `glasspane-ui--on-teardown' rule, applied to a string.
(defvar glasspane-title)

(defconst glasspane-ui--legacy-destinations
  '((:key "agenda" :label "Agenda" :icon "event"
     :subtitle "Today's schedule, deadlines, and the month grid"
     :verb "agenda.open")
    (:key "tasks" :label "Tasks" :icon "task_alt"
     :subtitle "Every TODO, under its keyword filter"
     :verb "tasks.open")
    (:key "journal" :label "Journal" :icon "calendar_today"
     :subtitle "The datetree day, with what carried over"
     :verb "journal.open")
    (:key "capture" :label "Capture" :icon "add_circle"
     :subtitle "File a note through an org capture template"
     :verb "org.capture.show")
    (:key "search" :label "Search" :icon "search"
     :subtitle "Query the vault offline, with the filter builder"
     :verb "search.open")
    (:key "views" :label "Saved views" :icon "manage_search"
     :subtitle "Named queries as lists, boards, and calendars"
     :verb "views.hub")
    (:key "review" :label "Review" :icon "school"
     :subtitle "Flashcards due today, and notes gone stale"
     :verb "review.open"))
  "The pre-PARA hub rows retained only by `glasspane-ui-legacy-ia'.")

(defconst glasspane-ui-destinations
  '((:key "agenda" :label "Agenda" :icon "event"
     :subtitle "Today's schedule, deadlines, and the month grid"
     :verb "agenda.open" :badge glasspane-agenda-dock-badge :bar t)
    (:key "projects" :label "Projects" :icon "task_alt"
     :subtitle "Open work grouped by project file"
     :verb "projects.open" :bar t)
    (:key "areas" :label "Areas" :icon "category"
     :subtitle "Responsibilities grouped by Org category"
     :verb "areas.open" :bar t)
    (:key "resources" :label "Resources" :icon "topic"
     :subtitle "Browse the vault through native Files"
     :verb "resources.open" :bar t)
    (:key "review" :label "Review" :icon "school"
     :subtitle "Flashcards due today, and notes gone stale"
     :verb "review.open" :bar t)
    (:key "archive" :label "Archive" :icon "archive"
     :subtitle "Browse native Org archive files"
     :verb "archive.open" :bar nil))
  "Glasspane's authoritative PARA destinations, in navigation order.
ONE table feeds the host destination registry, the five-item primary bar,
the temporary hub body, and both drawer projections.  `:bar' nil makes
Archive a deep-linkable drawer destination without spending a bar slot.
Each `:verb' is registered by the sibling module that owns the screen; the
coupling is the wire string alone, so an early tap is rejected by the action
shim rather than signalling.

Subtitles are STATIC on purpose.  Chrome rebuilds every screen on the
stack for every push, so a live count here would re-extract org on
every frame the user is anywhere in the app; the Agenda and Review
screens carry their own in-screen counts instead (FOUNDATION-GAPS #5).

No Notes row: glasspane-notes owns no screen of its own — its surfaces
are the detail view's backlinks/mentions sections and the Review
screen's stale-files half, both reached from rows that ARE here.")

(defun glasspane-ui-active-destinations ()
  "Return the destination table selected by the PA-3 rollback seam."
  (if glasspane-ui-legacy-ia
      glasspane-ui--legacy-destinations
    glasspane-ui-destinations))

(defun glasspane-ui-open-destination (route id builder &optional params)
  "Open Glasspane destination ROUTE as peer screen ID via BUILDER.
PARAMS is the originating action event.  In the PARA composition every
Tier-1 destination first abandons the previous destination and its drills,
then pushes its own screen.  Agenda is the pinned-root exception: its pushed
ID equals the root ID, so chrome's same-ID truncation performs the reset in
one operation.  The legacy rollback arm retains the historical plain-push
stack shape.

The selected route is recorded before the deferred push so the snapshot built
for direct/M-x navigation has honest primary-bar selection.  The handler's
effect remains outside the dispatch extent and presentation failures stay
isolated there.  Return `accepted'."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane")))
        (legacy glasspane-ui-legacy-ia))
    (unless legacy
      (jetpacs-apps-note-route "glasspane" route))
    (jetpacs-flow-continue
     (lambda ()
       (condition-case err
           (progn
             (unless (or legacy (equal id "glasspane-agenda"))
               (jetpacs-chrome-reset-screens surface))
             (jetpacs-chrome-push-screen surface id builder))
         (error (message "glasspane: %s destination push failed: %s"
                         id (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-ui--route-for-screen (view)
  "Return the primary route represented by chrome screen id VIEW.
Transient detail/search/drill screens deliberately return nil: their origin
remains selected while they are on top."
  (when (stringp view)
    (cond
     ((equal view "glasspane-agenda") "agenda")
     ((equal view "glasspane-projects") "projects")
     ((or (equal view "glasspane-areas")
          (string-prefix-p "area-" view))
      "areas")
     ((equal view "glasspane-archive") "archive")
     ((equal view "glasspane-review") "review")
     ((string-prefix-p "view-" view) "agenda"))))

(defun glasspane-ui--on-view-change (surface view)
  "Keep Glasspane's primary route honest after a local switch to VIEW.
Only a route-changing switch schedules a bounded repush; switching between a
destination and one of its drills therefore costs no extra frame."
  (when (and (not glasspane-ui-legacy-ia)
             (jetpacs-owned-surface-p surface "glasspane"))
    (when-let* ((route (glasspane-ui--route-for-screen view)))
      (when (jetpacs-apps-note-route "glasspane" route)
        (jetpacs-shell--schedule-repush surface)))))

(defun glasspane-ui--home-destinations ()
  "Return the destinations projected into the temporary hub body.
The legacy hub shows every historical row.  The PARA hub mirrors the
persistent bar, leaving drawer-only Archive in the drawer."
  (if glasspane-ui-legacy-ia
      (glasspane-ui-active-destinations)
    (cl-remove-if (lambda (dest)
                    (and (plist-member dest :bar)
                         (null (plist-get dest :bar))))
                  (glasspane-ui-active-destinations))))

(defun glasspane-ui--destination-row (dest prefix)
  "One `jetpacs-chrome-row' for DEST, keyed under PREFIX.
The body and the drawer ship in the SAME document, so the two copies
of a destination need distinct SPEC 16.5 keys — the key is the
reconciler's identity for the row, not a label."
  (jetpacs-chrome-row (plist-get dest :label)
                      :subtitle (plist-get dest :subtitle)
                      :icon (plist-get dest :icon)
                      :on-tap (jetpacs-action (plist-get dest :verb))
                      :key (concat prefix (plist-get dest :key))))

(defun glasspane-ui--home-body ()
  "The hub body: one tappable row per destination."
  (apply #'jetpacs-lazy-column
         (append (mapcar (lambda (dest)
                           (glasspane-ui--destination-row dest "hub-"))
                         (glasspane-ui--home-destinations))
                 (list :spacing 8 :content-padding 12))))

(declare-function jetpacs-launcher-rows "jetpacs-launcher" (&optional exclude))

(defun glasspane-ui--drawer-app-rows ()
  "The OTHER apps' destinations for the drawer's foot, or nil.
`jetpacs-launcher-rows' is the base's own drawer convention
\(jetpacs-launcher.el) and it is how the org reader is reachable at
all: the reader claims the files editor body seam and registers no
opening verb, so a `.org' tapped in Files IS its entry point.
Resolved at render time (the `glasspane-srs-stale-section' idiom), so
the hub still builds in an image without the launcher — the batch
suite's, and any device profile that drops it.  Excludes this app's
own surface: a row to where you already are is not a destination."
  (when (fboundp 'jetpacs-launcher-rows)
    (condition-case nil
        (when-let* ((rows (jetpacs-launcher-rows
                           (jetpacs-shell-surface-for "glasspane"))))
          (append (list (jetpacs-divider) (jetpacs-section-header "Apps"))
                  rows))
      (error nil))))

(defun glasspane-ui--home-drawer ()
  "The navigation drawer: the app's canonical destination list.
Home first (the root the stack resets to), then the body's own
destinations, then the app's settings screen, then the other apps.
Destinations only, never a document mutation, and every row is
reachable elsewhere — M-x for the commands, the Settings root for the
satellites (docs/CHROME-VOCABULARY.md).  Authored on the ROOT screen
alone: chrome renders the stack as one multi_view, and a drawer
repeated on every pushed screen would duplicate its rows in the same
document."
  (apply #'jetpacs-column
         (append
          (list (jetpacs-chrome-row "Home"
                                    :subtitle "The hub"
                                    :icon "home"
                                    :on-tap (jetpacs-action "glasspane.home")
                                    :key "drawer-home"))
          (mapcar (lambda (dest)
                    (glasspane-ui--destination-row dest "drawer-"))
                  (glasspane-ui-active-destinations))
          (list (jetpacs-chrome-row
                 "Settings"
                 :subtitle "Saved searches"
                 :icon "settings"
                 :on-tap (jetpacs-action "glasspane.settings.open")
                 :key "drawer-settings"))
          (glasspane-ui--drawer-app-rows)
          (list :spacing 4 :scroll t))))

(defun glasspane-ui-home-screen (back)
  "The app's home screen: the hub `glasspane-register' defines as root.
BACK is the chrome builder contract's argument — nil at the stack
bottom, which is where this screen lives.  In the PARA composition the
screen leaves its FAB slot absent for the app registry to inject Capture;
the rollback arm authors the historical FAB directly."
  (jetpacs-chrome-screen
   glasspane-title
   (glasspane-ui--home-body)
   :back back
   :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab))
   :drawer (and glasspane-ui-legacy-ia (glasspane-ui--home-drawer))))

;;;; The at-ref funnel (S4/S5 — the classifier every later rung copies)

(defun glasspane-ui-at-ref (args fn &optional save)
  "Resolve ARGS' `:token' to its heading and run FN with point there.
Returns the SPEC 14.4 status the calling handler answers with:

  no/unknown token          -> `stale'    (swept set: the list moved)
  `ebp-org-refused'         -> `rejected' (file policy — permanent)
  `ebp-org-unresolved'      -> `stale'    (heading gone or ambiguous)
  any other signal          -> `rejected' (mutation did not land)
  FN returned               -> `accepted' (effect durable, see below)

With SAVE non-nil the buffer is saved through
`glasspane-org-save-and-invalidate'.  Deliberately NOT
`ebp-org-with-mutation': the engine defers saves to an idle timer,
which leaves the file not-yet-on-disk for flows that read it back
immediately (capture finalize, offline-queue replay) and fires the
after-save refresh outside `glasspane-org-inhibit-save-refresh's
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
                      (glasspane-org-save-and-invalidate)
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

(defun glasspane-ui-tokenize-tap (items set)
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

;;;; Settings nodes
;;
;; The TODO-sequence and tag editors left with §3 step 2: they manage
;; org's own state and live in jetpacs-org-settings.el now, behind the
;; foundation's "Org workflow" satellite.  What remains here is the one
;; managed UI that is genuinely app opinion — the saved searches.

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

(defun glasspane-ui--settings-body ()
  "The app settings screen body: the saved searches, nothing else.
The org/calendar schema sections live on the Settings ROOT with the
foundation that registers them, and the TODO-sequence/tags editors
behind its \"Org workflow\" satellite (jetpacs-org-settings.el, §3
steps 1-2) — this screen holds only the app's own managed UI.
lazy_column, not column: the scaffold body has no scroll container on
the client."
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
                                :variant "outlined")))))

(defun glasspane-ui--settings-screen (back)
  "The pushed Glasspane settings screen."
  (jetpacs-chrome-screen "Glasspane" (glasspane-ui--settings-body)
                         :back back))

(defun glasspane-ui--settings-link ()
  "The Settings-root satellite row leading to the app settings screen."
  (jetpacs-chrome-row "Glasspane"
                      :subtitle "Saved searches"
                      :icon "menu_book"
                      :on-tap (jetpacs-action "glasspane.settings.open")
                      :key "glasspane-settings-link"))

;;;; Dialogs (S3 — one shape: ebp-client-dialog-show + captured fields)
;;
;; The one-live-dialog slot is the FOUNDATION's now
;; (jetpacs-settings-show-dialog, §3 step 2): the app's saved-search
;; editors share it with the org-workflow editors that moved out, and
;; the agenda writers stopped reaching across modules into a private
;; slot for their origin params.

(defun glasspane-ui--show-agenda-dialog (name params)
  "Show the saved-search editor for NAME (nil = new)."
  (let ((query (or (and name (cdr (assoc name glasspane-org-custom-agendas)))
                   "")))
    (jetpacs-settings-show-dialog
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
  (jetpacs-settings-show-dialog
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
         (jetpacs-app-defer-refresh params))))))

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

(defun glasspane-ui--on-agenda-delete (args _params)
  "Delete saved search `:name'; fired from a card or the edit dialog."
  (let ((name (plist-get args :name)))
    (cond
     ((not (stringp name)) 'rejected)
     ((not (assoc name glasspane-org-custom-agendas))
      (jetpacs-settings-refresh)
      'stale)
     (t
      (setq glasspane-org-custom-agendas
            (assoc-delete-all name glasspane-org-custom-agendas))
      (jetpacs-settings-save-variable 'glasspane-org-custom-agendas
                                      glasspane-org-custom-agendas)
      ;; A dialog event has no :surface; this editor is a Settings
      ;; satellite, so use the foundation's canonical refresh target.
      (jetpacs-settings-dialog-close)
      (jetpacs-shell-notify (format "Deleted saved search: %s" name))
      (jetpacs-settings-refresh)
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
      (jetpacs-settings-dialog-close)
      (jetpacs-shell-notify "Saved custom agenda")
      (jetpacs-settings-refresh)
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
  (jetpacs-app-defer-refresh params)
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
          (jetpacs-app-defer-refresh params)
          'accepted)
      'rejected)))

(defun glasspane-ui--on-agenda-set-month (args params)
  "Anchor on the 1st of the month on_month_change reported (`:value')."
  (let ((month (plist-get args :value)))
    (if (and (stringp month)
             (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}\\'" month))
        (progn
          (setq glasspane-ui-agenda-anchor (concat month "-01"))
          (jetpacs-app-defer-refresh params)
          'accepted)
      'rejected)))

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
handlers, so the push takes the D2 seam (the glasspane-clock-soon
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
  (remove-hook 'jetpacs-shell-view-change-functions
               #'glasspane-ui--on-view-change)
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
    "settings.agenda.edit"
    "settings.agenda.delete"
    "settings.agenda.save"
    "agenda.save-custom"
    "agenda.today"
    "agenda.select-date"
    "agenda.set-month")
  "The verbs this rung owns, for the register/unregister sweep.
The TODO-sequence/tags verbs left with §3 step 2 (they are the
foundation's ownerless jetpacs.org.* family now);
search.clear-filters lives with the filter state it clears (G6),
files.filter and files.toggle-refile with the reader adapter (G4/GR-2).")

(defun glasspane-ui-register ()
  "Register the UI verbs, the settings section/link, and the hooks.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers and
registry entries in place, and the link is re-added exactly once."
  ;; :any-surface — ONLY the opener now.  The satellite link draws on
  ;; the Settings ROOT, a surface Glasspane does not own, so the tap
  ;; that OPENS the management screen arrives before any guest screen
  ;; exists and still needs the global flag.  The verbs emitted FROM
  ;; that screen (edit/delete) no longer do: the opener's push
  ;; registers the screen as a sanctioned GUEST
  ;; (`jetpacs-chrome-push-screen', S4), and the D1 gate admits an
  ;; owner's verbs from any surface where one of its guest screens is
  ;; live (`jetpacs-guest-delegation-function') — revoked the moment
  ;; the screen leaves the stack, which a blanket :any-surface never
  ;; was.  The rest stay owner-scoped: the save verbs fire from dialog
  ;; conclusions, which carry no `:surface' at all (SPEC 14.4), and
  ;; the agenda/files verbs from screens on this owner's own surface.
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "glasspane.settings.open"
                       #'glasspane-ui--on-settings-open
                       :any-surface t
                       :doc "Open Glasspane's settings management screen")
    (jetpacs-defaction "settings.agenda.edit"
                       #'glasspane-ui--on-agenda-edit)
    (jetpacs-defaction "settings.agenda.delete"
                       #'glasspane-ui--on-agenda-delete)
    (jetpacs-defaction "settings.agenda.save"
                       #'glasspane-ui--on-agenda-save)
    (jetpacs-defaction "agenda.save-custom"
                       #'glasspane-ui--on-agenda-save-custom)
    (jetpacs-defaction "agenda.today" #'glasspane-ui--on-agenda-today)
    (jetpacs-defaction "agenda.select-date"
                       #'glasspane-ui--on-agenda-select-date)
    (jetpacs-defaction "agenda.set-month"
                       #'glasspane-ui--on-agenda-set-month)
    ;; The app's own section — CONSOLIDATED (§3 step 2's recorded
    ;; opportunity): Babel timeout and Packages auto-install share ONE
    ;; "Glasspane" section.  Journal landing rejoins them only in the
    ;; legacy rollback arm; active PARA navigation always lands on Agenda.
    ;; The sibling defcustoms stay where they live; this is the single
    ;; registration site, so glasspane-journal/glasspane-packages no longer
    ;; register sections of their own.  All plain: none feeds a memoised
    ;; extraction.
    (jetpacs-settings-register-section
     "Glasspane"
     (append
      (list (list 'glasspane-babel-timeout
                  :label "Babel run timeout (s)"))
      (when glasspane-ui-legacy-ia
        (list (list 'glasspane-journal-landing
                    :label "Open on the journal")))
      (list (list 'glasspane-packages-auto-install
                  :label "Auto-install packages (org-ql, vulpea, org-srs, ef-themes)"))))
    (jetpacs-settings-remove-link #'glasspane-ui--settings-link)
    ;; v1's settings view sat at order 80 among the app's views.
    (jetpacs-settings-add-link 80 #'glasspane-ui--settings-link))
  (add-hook 'jetpacs-shell-refresh-hook #'glasspane-ui--refresh-invalidate)
  (remove-hook 'jetpacs-shell-view-change-functions
               #'glasspane-ui--on-view-change)
  (unless glasspane-ui-legacy-ia
    (add-hook 'jetpacs-shell-view-change-functions
              #'glasspane-ui--on-view-change))
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
  (jetpacs-settings-remove-link #'glasspane-ui--settings-link)
  (jetpacs-settings-dialog-close)
  (glasspane-ui-remove-hooks))

(provide 'glasspane-ui)
;;; glasspane-ui.el ends here
