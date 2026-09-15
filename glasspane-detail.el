;;; glasspane-detail.el --- Glasspane heading detail: pushed screen + mutations -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The heading drill-in (docs/PLAN-glasspane-app.md, G4): the detail
;; screen is a PUSHED chrome screen whose builder closure captures the
;; heading ref (S1) — `heading.tap' resolves the tapped token and
;; pushes; there is no `glasspane-ui--detail-ref' defvar anymore, the
;; closure IS the state.  Every list this file renders addresses
;; headings through SPEC 23.1 tokens minted per screen (S5, set
;; \"detail\"); every handler answers a SPEC 14.4 status through the
;; G3 `glasspane-ui-at-ref' funnel (S4).
;;
;; Retired against v1 (the plan's retirement list + G4 section):
;;
;; - The home-screen widget rows (`glasspane-ui--widget-row',
;;   `--widget-query-items', v1 detail:25,48): no widget/tile node
;;   vocabulary (FOUNDATION-GAPS #1).
;; - `glasspane-ui--ref-clocked-in-p' (v1:236-251): `ebp-org-clocked-in-p'
;;   owns it (ebp-org.el:1319).
;; - The `jetpacs-shell-define-view' overlay block and `heading.back'
;;   (stale-cached-UI compatibility): chrome's stack + the device-local
;;   back arrow replace both.
;; - The planning dialog + its resend loop (v1:797-866) and the
;;   wholesale-delegated handlers — heading.schedule-time,
;;   heading.deadline-time, heading.repeater, heading.planning.show,
;;   heading.deadline, heading.archive, heading.add-heading: the
;;   shipped foundation dialogs own the picker flows
;;   (jetpacs-org-dialogs.el:385-745,1165-1169).  The app keeps token-based
;;   delegation verbs for planning and tags.  `detail.planning.edit'
;;   seeds the foundation timestamp dialog for SCHEDULED/DEADLINE;
;;   `detail.tags.edit' opens its grouped local-tag picker and
;;   `detail.priority.edit' its priority dialog.  Archive rides
;;   the base `jetpacs.org.archive' verb on a token minted under the
;;   base owner's scope, with the SPEC 14.1 device-side confirm.
;; - The (ask . t)/empty-date PROMPT arms of todo-set/schedule/
;;   priority/tags: only the direct arg arms survive (G4's dedup
;;   decision) — the overflow pickers are the base heading sheet's.
;; - `heading.reorder': its per-list key resolution belongs to the
;;   reorderable-list builders (the reader's refile list this rung,
;;   views' board in G6) — registered beside the lists, not here.
;; - The detail bottom bar's Add Heading item: the base
;;   `jetpacs.org.add-heading' is buffer-exposure-gated and the files
;;   editor FAB already carries the affordance; a subtree-child add
;;   returns only if dogfood misses it.
;; - v1's `yes-or-no-p' confirms (archive/delete): the descriptor-level
;;   `:confirm' (SPEC 14.1) parks the dispatch behind a device
;;   AlertDialog instead — no bridge round-trip at all.
;;
;; The v1 app-owned save-function rebind retired at GR-6: native Org
;; durability is Jetpacs policy now.  This module contributes only the
;; opinionated file-properties action through a second editor adapter.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-clock)
(require 'org-refile)
(require 'ebp)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-buffer)
(require 'jetpacs-navigate)
(require 'jetpacs-dialog)
(require 'jetpacs-editor)
(require 'jetpacs-org-toolbar)
(require 'jetpacs-org-dialogs)
(require 'glasspane-org)
(require 'glasspane-ui)
(require 'glasspane-navigation)
(require 'jetpacs-org-settings)      ; the shared tag vocabulary

(declare-function jetpacs-material3-assist-chip "jetpacs-material3"
                  (label &rest keys))
(declare-function jetpacs-material3-split-button "jetpacs-material3"
                  (label on-tap &rest keys))
;; The note graph is an optional later rung, consulted by name only.
(declare-function glasspane-notes-available-p "glasspane-notes" ())
(declare-function glasspane-notes-backlink-count "glasspane-notes" (id))

;; Same-rung sibling: the foldable reader.  This file must build (and
;; the detail body must render) with the reader absent, so the require
;; is soft and the body degrades to plain org text (gap #6).
(require 'glasspane-org-reader nil t)
(declare-function glasspane-org-reader-subtree "glasspane-org-reader"
                  (file pos &optional skip-props set))
(defvar glasspane-org-reader-inline-props)

;; Later-rung siblings (G5's pure agenda formatters): declared, never
;; required forward — `glasspane-detail-agenda-card' has no caller until
;; the agenda screens land beside these definitions.
(declare-function glasspane-agenda-type-icon "glasspane-agenda" (type))
(declare-function glasspane-agenda-type-label "glasspane-agenda" (type))
(declare-function glasspane-agenda-card-date-row "glasspane-agenda" (it))

;;;; State (S2 — the handlers below are the only writers)

(defvar glasspane-ui--detail-read-mode t
  "When non-nil the detail screen shows the foldable reader, else the editor.")

(defvar glasspane-detail--section nil
  "The metadata panel the detail's tonal icons currently show.
Nil or a section symbol from `glasspane-detail--sections': only one panel
is shown at a time, as with the outline reader's drawers.  `detail.section'
is the toggle writer; opening another heading resets it.")

(defconst glasspane-detail--sections
  '(("tags" tags "label" "Tags")
    ("scheduled" scheduled "event" "Scheduled")
    ("deadline" deadline "flag" "Deadline")
    ("props" props "tune" "Properties")
    ("logbook" logbook "history" "Logbook")
    ("links" links "link" "Connections"))
  "Detail drawer records: (WIRE-NAME STATE ICON LABEL).
STATE is a `glasspane-detail--section' value.  The same record supplies the
`detail.section' argument, the tonal control, and the open drawer's header.
Connections holds what the app layers contribute (backlinks, outgoing
links, unlinked mentions) and is offered only when something did.")

(defvar glasspane-detail--dialog nil
  "The live detail-owned dialog, (:request-id ID :params PARAMS), or nil.
PARAMS are the OPENING event's — a Save fired from inside the dialog
arrives in dialog context with no `:surface' (SPEC 14.4), so its
refresh needs the surface the dialog was opened from.")

(defconst glasspane-detail--screen-id "glasspane-detail"
  "The one detail screen id: re-tapping a heading replaces the top
entry (chrome's stack-insert truncate) instead of stacking drill-ins,
the v1 single-detail-view behavior.")

(defconst glasspane-detail--save-ttl-s 86400
  "Offline ttl for the queued `detail.save' (plan T4: detail:607-609).")

;;;; Small helpers

(defun glasspane-detail--org-file-p (file)
  "Whether FILE names an org document (plain or gpg-wrapped)."
  (and (stringp file) (string-match-p "\\.org\\(\\.gpg\\)?\\'" file)))

(defun glasspane-detail--key (file pos)
  "The stable wire-id stem for the heading at POS in FILE."
  (format "%s#%s" (or file "") pos))

(defun glasspane-detail--token-ref (args)
  "ARGS' `:token' resolved in the app's scope, or nil (handler: stale)."
  (ebp-org-token-ref (plist-get args :token) :owner "glasspane"))

(defun glasspane-detail--with-prompting (fn params)
  "Run FN only if a prompt raised now would reach the device.
The JA-6 P2 shape (jetpacs-org-dialogs.el:74-80): refusing loudly
beats wedging silently, and a flow error surfaces as a symbol, never
text (SPEC 23.3)."
  (if (not (jetpacs-dialog-can-bridge-p))
      (jetpacs-shell-notify
       (if (bound-and-true-p jetpacs-dialog--pending)
           "Busy — finish the open dialog first"
         "This needs the Companion dialog bridge")
       (plist-get params :surface))
    (condition-case err
        (funcall fn)
      (error (message "glasspane: detail flow failed: %s"
                      (jetpacs-error-label err))
             (jetpacs-shell-notify "That did not work"
                                   (plist-get params :surface))))))

(defun glasspane-detail--dialog-close ()
  "Retire the live detail dialog (S3 handler-side dismissal).
`ebp-client-abandon' sends rpc.cancel; the Companion concludes the
dialog with error 1301, which the show callback treats as a no-op."
  (let ((sheet glasspane-detail--dialog))
    (setq glasspane-detail--dialog nil)
    (when-let* ((client (jetpacs-client))
                (request-id (plist-get sheet :request-id)))
      (ignore-errors (ebp-client-abandon client request-id)))))

(cl-defun glasspane-detail--show-dialog (id spec &key params)
  "Show SPEC as dialog ID; stash the request for handler-side abandon.
Both detail dialogs (sub-heading properties, file properties) conclude
through a remote action's handler, so one live slot is enough."
  (when-let* ((client (jetpacs-client)))
    (let ((request-id
           (ebp-client-dialog-show
            client id spec
            :callback (lambda (_status _result _error)
                        ;; Dismissal and the abandon's 1301 land here.
                        (setq glasspane-detail--dialog nil)))))
      (when request-id
        (setq glasspane-detail--dialog
              (list :request-id request-id :params params))))))

(defun glasspane-detail--leave (params)
  "Leave the detail screen after its heading stopped existing here.
Pops when detail is on top (refile/delete landed from it), else just
repushes the surface.  Runs OUTSIDE the dispatch extent."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (if (equal (car (jetpacs-chrome-stack surface))
               glasspane-detail--screen-id)
        (jetpacs-chrome-pop-screen surface)
      (ignore-errors (jetpacs-shell-push surface)))))

(defun glasspane-detail--push-screen (surface ref)
  "Defer-push the detail screen for REF onto SURFACE (D2)."
  (jetpacs-flow-continue
   (lambda ()
     (condition-case err
         (jetpacs-chrome-push-screen
          surface glasspane-detail--screen-id
          (lambda (back) (glasspane-detail--screen ref back)))
       (error (message "glasspane: detail push failed: %s"
                       (jetpacs-error-label err)))))))

;;;; The header: state control, status pills, and the resting tag line

(defun glasspane-detail--today (info)
  "INFO's :today, the render's one calendar read, or today's ISO date."
  (or (plist-get info :today) (format-time-string "%Y-%m-%d")))

(defun glasspane-detail--priority-levels ()
  "The current buffer's priority letters, highest first, or nil."
  (let ((hi (or (bound-and-true-p org-priority-highest) ?A))
        (lo (or (bound-and-true-p org-priority-lowest) ?C)))
    (and (integerp hi) (integerp lo) (<= hi lo)
         (mapcar #'char-to-string (number-sequence hi lo)))))

(defun glasspane-detail--priority-color (priority levels)
  "The theme role carrying PRIORITY's urgency among LEVELS, highest first."
  (pcase (cl-position priority levels :test #'equal)
    (0 "error")
    (1 "warning")
    (_ "on_surface")))

(defun glasspane-detail--backlink-count (pos)
  "How many notes link to the heading at POS, or nil without a note graph.
Only a heading with an ID can be linked to by id, and the notes layer is
consulted by name only: it is an optional later rung."
  (when (and (fboundp 'glasspane-notes-available-p)
             (fboundp 'glasspane-notes-backlink-count)
             (glasspane-notes-available-p))
    (when-let* ((id (org-entry-get pos "ID")))
      (ignore-errors (glasspane-notes-backlink-count id)))))

(defun glasspane-detail--todo-control (info main)
  "Build INFO's TODO state control for the heading token MAIN.
A Material split button: the leading half shows the keyword and cycles
the sequence on tap (Org's `C-c C-t' reflex); the trailing chevron opens
every keyword plus No state as a dropdown, so the title row never grows.
An open keyword is filled, a done one tonal, and a heading without a
state shows an outlined empty ring.  Nil when no keywords are declared."
  (let ((todo (plist-get info :todo))
        (keywords (plist-get info :keywords)))
    (when keywords
      (jetpacs-with-semantics
       (jetpacs-material3-split-button
        todo
        (jetpacs-action "heading.todo-cycle" :args (list :token main))
        :icon (and (null todo) "radio_button_unchecked")
        :variant (cond ((null todo) "outlined")
                       ((plist-get info :done) "tonal")
                       (t "filled"))
        :size "xsmall"
        :trailing-description "Choose TODO state"
        :items (append
                (mapcar (lambda (kw)
                          (jetpacs-menu-item
                           kw
                           (jetpacs-action "heading.todo-set"
                                           :args (list :token main :state kw))
                           :enabled (and (equal kw todo) :json-false)))
                        keywords)
                (list (jetpacs-menu-item
                       "No state"
                       (jetpacs-action "heading.todo-set"
                                       :args (list :token main :state ""))
                       :enabled (and (null todo) :json-false)))))
       :name "TODO state" :state-description (or todo "No state")
       :description "Tap to advance; the arrow lists every state"))))

(cl-defun glasspane-detail--pill (label &key icon color on-tap on-long-tap
                                        name state)
  "A tinted status pill reading LABEL beside ICON in theme role COLOR.
The whole pill dispatches ON-TAP and ON-LONG-TAP; NAME and STATE name
it for assistive technology."
  (jetpacs-with-semantics
   (jetpacs-with-attrs
    (jetpacs-box (jetpacs-badge label :icon icon :color color)
                 :alignment "center_start"
                 :on-tap on-tap :on-long-tap on-long-tap)
    :min_height 36)
   :name (or name label) :state-description state))

(defun glasspane-detail--status-pills (info main)
  "INFO's planning, priority and clock facts as one wrapping pill row, or nil.
Only facts that are set appear, so a plain note shows nothing here.  A
date pill opens its drawer on tap and the foundation timestamp dialog on
long-press; the priority pill opens the foundation priority dialog; the
clock pill clocks out.  MAIN is the heading token the edits address."
  (let* ((today (glasspane-detail--today info))
         (done (plist-get info :done))
         (warn (or (plist-get info :warn-days) 14))
         (planning
          (lambda (kind stamp icon label)
            (when-let* ((h (glasspane-ui-human-date
                            stamp today :done done :kind kind :warn-days warn)))
              (let ((name (symbol-name kind))
                    (type (if (eq kind 'deadline) "DEADLINE" "SCHEDULED")))
                (glasspane-detail--pill
                 (plist-get h :label) :icon icon :color (plist-get h :color)
                 :on-tap (jetpacs-action "detail.section"
                                         :args (list :section name))
                 :on-long-tap (jetpacs-action "detail.planning.edit"
                                              :args (list :token main :type type))
                 :name label :state stamp)))))
         (pills
          (delq nil
                (list
                 (funcall planning 'scheduled (plist-get info :scheduled)
                          "event" "Scheduled")
                 (funcall planning 'deadline (plist-get info :deadline)
                          "flag" "Deadline")
                 (when-let* ((p (plist-get info :priority)))
                   (glasspane-detail--pill
                    (concat "Priority " p) :icon "priority_high"
                    :color (glasspane-detail--priority-color
                            p (plist-get info :priority-levels))
                    :on-tap (jetpacs-action "detail.priority.edit"
                                            :args (list :token main))
                    :name "Priority" :state p))
                 (when (plist-get info :clocked-in)
                   (glasspane-detail--pill
                    "Clocking" :icon "timer" :color "success"
                    :on-tap (jetpacs-action "org.clock.out")
                    :name "Clock" :state "running"))))))
    (when pills
      (apply #'jetpacs-flow-row
             (append pills (list :spacing 6 :run-spacing 4 :align "center"))))))

(defun glasspane-detail--tag-line (info)
  "INFO's Areas and local plain tags as one wrapping chip line, or nil.
Areas keep their elevated icon chips; the other local tags are flat
assist chips; inherited tags stay out of the resting view (the Tags
drawer explains them).  A tap searches by tag."
  (let* ((areas (plist-get info :areas))
         (chip (lambda (tag area)
                 (jetpacs-material3-assist-chip
                  tag
                  :icon (and area (glasspane-area-icon tag))
                  :variant (and area "elevated")
                  :on-tap (jetpacs-action "search.by-tag"
                                          :args (list :tag tag)))))
         (chips (append
                 (mapcar (lambda (tag) (funcall chip tag t)) areas)
                 (mapcar (lambda (tag) (funcall chip tag nil))
                         (cl-remove-if (lambda (tag) (member tag areas))
                                       (plist-get info :local-tags))))))
    (when chips
      (apply #'jetpacs-flow-row
             (append chips (list :spacing 4 :run-spacing 4))))))

(defun glasspane-detail--title (info)
  "INFO's headline as reading text: link markup shows its description."
  (org-link-display-format (or (plist-get info :headline) "")))

;;;; Shared cards (agenda G5 and search G6 render through these)
;;
;; Item alists carry a `token' the LIST's builder minted into its own
;; per-screen set (S5) — one bulk `ebp-org-ref-tokens' per render, so a
;; per-card mint would sweep its siblings.  `archive-token', when
;; present, was minted under `jetpacs-org-dialogs-owner' so the base
;; `jetpacs.org.archive' verb can resolve it; without one the card just
;; has no archive swipe.

(defun glasspane-detail--agenda-tag-chips (tags &optional areas arrange)
  "Build wrapping TAGS using the shared chip presentation.
With AREAS, elevate the chips, add Area icons, and align them right unless
ARRANGE says otherwise (see `glasspane-ui-tag-chips')."
  (glasspane-ui-tag-chips tags areas arrange))

(defun glasspane-detail-agenda-card (it &optional area-tags)
  "A detail-rich agenda card for item IT, distinguishing AREA-TAGS.
Leading time (or a type icon), priority-prefixed headline (done titles
degrade to neutral on_surface — no strike span, FOUNDATION-GAPS #7),
a todo/type/file caption, tag chips, and the tap/long-tap/swipe wiring.
AREA-TAGS, when supplied by Projects, align right beside the headline as
elevated chips with their configured icons on medium and expanded windows;
a compact window stacks them start-aligned beneath the headline so the
title keeps the card's full width.  Ordinary tags use the full bottom row
without duplicating Areas."
  (let* ((headline (or (alist-get 'headline it) "Untitled"))
         (todo (alist-get 'todo it))
         ;; Normalized "HH:MM" — the raw property is a time-grid string
         ;; like " 9:15......".
         (time (glasspane-org-item-hm (alist-get 'time it)))
         (type (alist-get 'type it))
         (file (alist-get 'file it))
         (priority (alist-get 'priority it))
         (area-tags (delete-dups (copy-sequence area-tags)))
         (tags (cl-remove-if (lambda (tag) (member tag area-tags))
                             (append (alist-get 'tags it) nil)))
         (token (alist-get 'token it))
         (archive-token (alist-get 'archive-token it))
         (done (and todo
                    (member todo (or (default-value 'org-done-keywords)
                                     '("DONE" "CANCELLED")))
                    t))
         (icon+color (glasspane-agenda-type-icon type))
         (caption (string-join
                   (delq nil (list todo
                                   (and (stringp type)
                                        (glasspane-agenda-type-label type))
                                   (and file (file-name-nondirectory file))))
                   "  ·  "))
         (lead (cond ((and (stringp time) (not (string-empty-p time)))
                      (jetpacs-text time :style "label"))
                     (icon+color
                      (jetpacs-icon (car icon+color) :size 18
                                    :color (cdr icon+color)))))
         (headline-node
          (jetpacs-rich-text
           (delq nil
                 (list
                  (when priority
                    (jetpacs-span (format "[%s] " priority)
                                  :font-weight "bold" :color "warning"))
                  (jetpacs-span headline
                                :color (and done "on_surface"))))))
         (middle
          (apply #'jetpacs-column
                 (delq nil
                       (append
                        (glasspane-ui-headline-with-areas headline-node
                                                          area-tags)
                        (list
                        (unless (string-empty-p caption)
                          (jetpacs-text caption :style "caption"))
                        (glasspane-agenda-card-date-row it)
                        (glasspane-detail--agenda-tag-chips tags)))))))
    (jetpacs-card
     (list (apply #'jetpacs-row
                  (delq nil
                        (list lead
                              (jetpacs-with-attrs (jetpacs-box middle)
                                                  :weight 1)))))
     :on-tap (glasspane-navigation-heading-action token)
     :on-long-tap (and token (jetpacs-action "heading.menu"
                                             :args (list :token token)))
     :swipe-start (and token
                       (jetpacs-swipe
                        (list (jetpacs-swipe-action
                               "Cycle" :icon "check" :color "success"
                               :on-trigger
                               (jetpacs-action "heading.todo-cycle"
                                               :args (list :token token))))))
     :swipe-end
     (and archive-token
          (jetpacs-swipe
           (list (jetpacs-swipe-action
                  "Archive" :icon "archive" :color "error"
                  :on-trigger
                  (jetpacs-action
                   "jetpacs.org.archive" :args (list :token archive-token)
                   :confirm "Archive this subtree?"))))))))

(defun glasspane-detail-result-card (it)
  "Render a search/heading item IT to a tappable card with tag chips.
Areas elevate beside (or, on a phone, beneath) the headline exactly as the
agenda card places them; ordinary tags keep the full bottom row."
  (let* ((headline (or (alist-get 'headline it) "?"))
         (todo (alist-get 'todo it))
         (file (alist-get 'file it))
         (areas (glasspane-ui-item-areas it))
         (tags (cl-remove-if (lambda (tag) (member tag areas))
                             (append (alist-get 'tags it) nil)))
         (token (alist-get 'token it))
         (caption (string-join
                   (delq nil (list todo
                                   (when file (file-name-nondirectory file))))
                   "  ·  "))
         (children (delq nil
                         (append
                          (glasspane-ui-headline-with-areas
                           (jetpacs-text headline :style "body") areas)
                          (list
                           (unless (string-empty-p caption)
                             (jetpacs-text caption :style "caption"))
                           (glasspane-ui-tag-chips tags))))))
    (jetpacs-card (list (apply #'jetpacs-column children))
                  :on-tap (and token (jetpacs-action
                                      "heading.tap"
                                      :args (list :token token))))))

(defun glasspane-detail-clock-body ()
  "The clock status body: current task card plus recent-task cards.
Journal's today card embeds it.  Recent refs are filtered through the
TOTAL root policy and the mint is best-effort: a history entry whose
file left the roots (or the disk) costs the recent list, never the
body."
  (let* ((status (glasspane-org-clock-status))
         (recent (condition-case nil
                     (glasspane-org-recent-clocks 5)
                   (error nil)))
         (recent (cl-remove-if-not
                  (lambda (r)
                    (let ((f (plist-get (alist-get 'ref r) :file)))
                      (and (stringp f) (not (string-empty-p f))
                           (ebp-org-file-allowed-p f))))
                  recent))
         (tokens (and recent
                      (condition-case nil
                          (ebp-org-ref-tokens
                           (mapcar (lambda (r) (alist-get 'ref r)) recent)
                           :set "clock-recent" :owner "glasspane")
                        (error nil))))
         (status-card
          (if status
              (let* ((start (alist-get 'start status))
                     (mins (when start
                             (max 0 (floor (- (float-time) start) 60)))))
                (jetpacs-card
                 (list (jetpacs-column
                        (jetpacs-text "Currently clocked in" :style "caption")
                        (jetpacs-text (or (alist-get 'task status) "?")
                                      :style "headline")
                        (jetpacs-text (if mins (format "%d min elapsed" mins)
                                        "")
                                      :style "caption")
                        (jetpacs-button "Clock out"
                                        (jetpacs-action "org.clock.out"))
                        :spacing 4))))
            (jetpacs-empty-state :icon "schedule"
                                 :title "Not clocked in"
                                 :caption "Pick a recent task below to start.")))
         (recent-cards
          (and tokens
               (cl-mapcar (lambda (r tok)
                            (jetpacs-chrome-row
                             (or (alist-get 'headline r) "?")
                             :icon "history"
                             :on-tap (jetpacs-action
                                      "heading.clock-in"
                                      :args (list :token tok))))
                          recent tokens))))
    (apply #'jetpacs-column
           (append (list status-card)
                   (when recent-cards
                     (cons (jetpacs-section-header "Recent tasks")
                           recent-cards))
                   (list :spacing 8)))))

;;;; Detail extraction

(defun glasspane-ui--sibling-ref (ref direction)
  "A ref for REF's same-level sibling in DIRECTION (`next'/`prev'), or nil.
Drives the detail bottom bar's Prev/Next, which only appears when a
sibling exists — so this doubles as the availability check."
  (condition-case nil
      (let ((marker (ebp-org-resolve-ref ref)))
        (unwind-protect
            (with-current-buffer (marker-buffer marker)
              (org-with-wide-buffer
               (goto-char marker)
               (org-back-to-heading t)
               (when (org-goto-sibling (eq direction 'prev))
                 (ebp-org-ref-at-point))))
          (set-marker marker nil)))
    (error nil)))

(defun glasspane-ui--detail-meta (ref)
  "Resolve REF and extract everything the detail screen renders.
Signals like `ebp-org-resolve-ref'; the screen builder classifies."
  (let ((marker (ebp-org-resolve-ref ref)))
    (unwind-protect
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (org-back-to-heading t)
           (let* ((pos (point))
                  (file (buffer-file-name))
                  (end (save-excursion
                         (org-end-of-subtree t t)
                         (point)))
                  (comps (org-heading-components))
                  (membership (glasspane-org-tag-groups-at pos)))
             (list :buf (current-buffer)
                   :file file
                   :pos pos
                   :edit-mtime (glasspane-org-mtime-stamp file)
                   :edit-beg pos
                   :edit-end end
                   :edit-tick (buffer-chars-modified-tick)
                   :ref (ebp-org-ref-at-point)
                   :headline (or (nth 4 comps) "")
                   :todo (nth 2 comps)
                   :priority (and (nth 3 comps)
                                  (char-to-string (nth 3 comps)))
                   :tag-groups membership
                   :tags (plist-get membership :tags)
                   :local-tags (plist-get membership :local)
                   :inherited-tags (plist-get membership :inherited)
                   :areas (plist-get
                           (glasspane-org-tag-group
                            (plist-get membership :groups)
                            glasspane-area-tag-group)
                           :members)
                   :scheduled (org-entry-get pos "SCHEDULED")
                   :deadline (org-entry-get pos "DEADLINE")
                   :keywords (or org-todo-keywords-1 '("TODO" "DONE"))
                   :done (and (nth 2 comps)
                              (member (nth 2 comps) org-done-keywords) t)
                   ;; The render's one calendar read: every date word
                   ;; below is a pure function of this day.
                   :today (format-time-string "%Y-%m-%d")
                   :warn-days org-deadline-warning-days
                   :priority-levels (glasspane-detail--priority-levels)
                   :file-title (or (ignore-errors
                                     (cadr (assoc "TITLE"
                                                  (org-collect-keywords
                                                   '("TITLE")))))
                                   (and file (file-name-base file)))
                   :backlinks (glasspane-detail--backlink-count pos)
                   :clocked-in (and (ebp-org-clocked-in-p pos) t)
                   :props (ignore-errors
                            (org-entry-properties pos 'standard))
                   :logbook (ignore-errors (ebp-org-logbook-entries pos))
                   ;; Ancestor (TITLE . POS) pairs, outermost first,
                   ;; for the breadcrumb trail.
                   :ancestors
                   (save-excursion
                     (let (path)
                       (ignore-errors
                         (while (org-up-heading-safe)
                           (push (cons (substring-no-properties
                                        (org-get-heading t t t t))
                                       (point))
                                 path)))
                       path))
                   :prev-ref (glasspane-ui--sibling-ref ref 'prev)
                   :next-ref (glasspane-ui--sibling-ref ref 'next)))))
      (set-marker marker nil))))

(defun glasspane-detail--tokens (info)
  "Mint the detail screen's token sets from INFO; a token plist.
One \"detail\" set under the app's scope for everything an app verb
resolves (S4/S5), plus a single-ref set under the BASE dialogs owner —
`jetpacs.org.archive' resolves in ITS scope, and a token is only ever
a key into the scope it was minted for."
  (let* ((file (plist-get info :file))
         (main-ref (plist-get info :ref))
         (anc-refs (mapcar (lambda (anc)
                             (list :id nil :file (or file "")
                                   :pos (cdr anc)
                                   :headline (or (car anc) "")))
                           (plist-get info :ancestors)))
         (prev (plist-get info :prev-ref))
         (next (plist-get info :next-ref))
         (tokens (ebp-org-ref-tokens
                  (append (list main-ref) anc-refs
                          (and prev (list prev))
                          (and next (list next)))
                  :set "detail" :owner "glasspane"))
         (main (pop tokens))
         (anc-tokens (cl-loop repeat (length anc-refs)
                              collect (pop tokens)))
         (prev-tok (and prev (pop tokens)))
         (next-tok (and next (pop tokens)))
         (archive (condition-case nil
                      (car (ebp-org-ref-tokens
                            (list main-ref)
                            :set "glasspane-detail"
                            :owner jetpacs-org-dialogs-owner))
                    (error nil))))
    (list :main main :ancestors anc-tokens
          :prev prev-tok :next next-tok :archive archive)))

;;;; Detail builders

(defun glasspane-ui--detail-toolbar-extras (ref)
  "Every registered app layer's floating-toolbar chips for REF.
An erroring contributor costs its own chips, never the toolbar."
  (when ref
    (cl-loop for fn in glasspane-ui-detail-toolbar-functions
             append (condition-case nil (funcall fn ref)
                      (error nil)))))

(defun glasspane-ui--detail-subtree-text (ref)
  "REF's whole subtree as a string, or nil when the ref can't resolve."
  (condition-case nil
      (let ((marker (ebp-org-resolve-ref ref)))
        (unwind-protect
            (with-current-buffer (marker-buffer marker)
              (org-with-wide-buffer
               (goto-char marker)
               (buffer-substring-no-properties
                (point)
                (progn (org-end-of-subtree t t) (point)))))
          (set-marker marker nil)))
    (error nil)))

(defun glasspane-detail--share-items (ref)
  "The Copy link, Copy text and Share menu items for REF, or nil.
The link is an id link when the heading has an :ID:, a file::*headline
link otherwise — built at render time so the copy itself is
companion-local (`clipboard.copy') and works offline.  The subtree text
is read once for both the copy and the share sheet."
  (condition-case nil
      (let ((marker (ebp-org-resolve-ref ref)))
        (unwind-protect
            (with-current-buffer (marker-buffer marker)
              (org-with-wide-buffer
               (goto-char marker)
               (let* ((headline (org-get-heading t t t t))
                      (id (org-entry-get nil "ID"))
                      (link (if id
                                (format "[[id:%s][%s]]" id headline)
                              (format "[[file:%s::*%s][%s]]"
                                      (buffer-file-name) headline headline)))
                      (text (buffer-substring-no-properties
                             (point)
                             (progn (org-end-of-subtree t t) (point)))))
                 (list
                  (jetpacs-menu-item "Copy link" (jetpacs-clipboard-copy link)
                                     :icon "content_copy")
                  (jetpacs-menu-item "Copy text" (jetpacs-clipboard-copy text)
                                     :icon "copy_all")
                  (jetpacs-menu-item "Share…"
                                     (jetpacs-share text :title headline)
                                     :icon "share")))))
          (set-marker marker nil)))
    (error nil)))

(defun glasspane-ui--render-logbook-entry (entry)
  "One logbook ENTRY (a plist from `ebp-org-logbook-entries') as a row."
  (pcase (plist-get entry :type)
    ('clock (glasspane-ui-clock-entry entry))
    ('note
     (jetpacs-row
      (jetpacs-icon "chat" :color "primary")
      (jetpacs-column
       (jetpacs-text (format "Note • %s" (plist-get entry :timestamp))
                     :style "caption")
       (jetpacs-text (or (plist-get entry :content) "") :style "body")
       :spacing 2)
      :spacing 12))
    ('state
     (let ((content (plist-get entry :content)))
       (jetpacs-row
        (jetpacs-icon "change_history" :color "primary")
        (jetpacs-column
         (jetpacs-text (if (plist-get entry :from)
                           (format "%s → %s" (plist-get entry :from)
                                   (plist-get entry :to))
                         (format "Set to %s" (plist-get entry :to)))
                       :style "body" :font-weight "bold")
         (jetpacs-text (if (and (stringp content)
                                (not (string-empty-p content)))
                           (format "%s\n%s" (plist-get entry :timestamp)
                                   content)
                         (or (plist-get entry :timestamp) ""))
                       :style "caption")
         :spacing 2)
        :spacing 12)))))

(defun glasspane-detail--logbook-group (label entries key collapsed)
  "One inner logbook collapsible: LABEL over ENTRIES, id minted on KEY."
  (when entries
    (apply #'jetpacs-collapsible
           (jetpacs-wire-id "gp-logbook" key)
           (jetpacs-text (format "%s (%d)" label (length entries))
                         :style "label")
           (append
            (delq nil
                  (cl-loop for entry in entries
                           for i from 0
                           append (list (glasspane-ui--render-logbook-entry
                                         entry)
                                        (when (< i (1- (length entries)))
                                          (jetpacs-divider)))))
            (list :collapsed (jetpacs-bool collapsed))))))

(defun glasspane-detail--logbook-panel (entries key)
  "The Logbook panel nodes for ENTRIES grouped by type, or nil.
Shown beneath the tonal `history' icon; the inner type groups keep
their own folds, with ids minted on KEY."
  (when entries
    (let ((notes (seq-filter (lambda (e) (eq (plist-get e :type) 'note))
                             entries))
          (states (seq-filter (lambda (e) (eq (plist-get e :type) 'state))
                              entries))
          (clocks (seq-filter (lambda (e) (eq (plist-get e :type) 'clock))
                              entries)))
      (delq nil
            (list
             (glasspane-detail--logbook-group
              "Notes" notes (concat key "/notes") nil)
             (glasspane-detail--logbook-group
              "State changes" states (concat key "/states") t)
             (glasspane-detail--logbook-group
              "Clocks" clocks (concat key "/clocks") t))))))

(defun glasspane-ui--property-row (key value token pos &optional allowed)
  "A two-column KEY → editable VALUE row for the Properties editor.
ID is read-only (editing it breaks links); a value with ALLOWED
choices renders an enum, booleans a switch, dates a date button,
small numbers a slider, links a follow button; everything else is an
inline input whose submit runs `heading.prop-set' — submitting an
empty value removes the property."
  (let* ((id (jetpacs-wire-id "gp-prop" (format "%s/%s" pos key)))
         (is-boolean (or (equal allowed '("t" "nil"))
                         (equal allowed '("true" "false"))
                         (string-match-p "\\?" key)))
         (is-date (or (string-match-p "_DATE\\|_TIME\\'" key)
                      (member key '("CREATED" "SCHEDULED" "DEADLINE"))
                      (string-match-p "\\`[[<].*?[]>]\\'" value)))
         (is-number (and (not is-date)
                         (string-match-p "\\`[0-9]+\\'" value)))
         (is-link (and (not (string-empty-p value))
                       (string-match-p org-link-bracket-re value)))
         (action (jetpacs-action "heading.prop-set"
                                 :args (list :name key :token token))))
    (jetpacs-row
     (jetpacs-with-attrs (jetpacs-box (jetpacs-text key :style "label"))
                         :weight 2)
     (jetpacs-with-attrs
      (jetpacs-box
       (cond
        ((equal key "ID")
         (jetpacs-text value :style "caption" :selectable t))
        (is-boolean
         (jetpacs-switch id
                         :checked (jetpacs-bool
                                   (member value '("t" "true" "1")))
                         :on-change action))
        ((and allowed (proper-list-p allowed) (cl-every #'stringp allowed))
         (let ((opts (cl-remove-duplicates allowed :test #'equal
                                           :from-end t)))
           (jetpacs-enum-list id
                              (mapcar (lambda (v) (jetpacs-enum-option v v))
                                      opts)
                              ;; Single-select: ONE option value (T3),
                              ;; and only when it names a live option.
                              :value (car (member value opts))
                              :on-change action)))
        ;; Before the date arm: a [[link][desc]] value also matches the
        ;; bracketed-value date heuristic (v1 rendered links as dead
        ;; date buttons through exactly this misorder).
        (is-link
         (progn (string-match org-link-bracket-re value)
                (let ((link (match-string 1 value))
                      (desc (match-string 2 value)))
                  (jetpacs-button (or desc link)
                                  (jetpacs-action "org.link.open"
                                                  :args (list :link link))
                                  :variant "outlined"))))
        (is-date
         (jetpacs-date-button (if (string-empty-p value) "Set date" value)
                              action
                              :value (ebp-org-ts-date value)))
        (is-number
         (let ((num (string-to-number value)))
           (if (<= num 10)
               (jetpacs-slider id action :values (number-sequence 0 10)
                               :value num)
             (jetpacs-slider id action :value (min num 100)
                             :min 0 :max 100))))
        (t
         (jetpacs-text-input id :value value :single-line t
                             :on-submit action))))
      :weight 3)
     :align "center" :spacing 8)))

(defun glasspane-detail--allowed-values (buf pos key)
  "KEY's org-allowed values at POS in BUF, or nil."
  (ignore-errors
    (with-current-buffer buf
      (org-with-wide-buffer
       (goto-char pos)
       (org-property-get-allowed-values pos key)))))

(defun glasspane-ui--properties-panel (props token pos &optional buf)
  "The Properties drawer nodes: PROPS as key/value rows.
Rows edit the heading at POS through TOKEN, with BUF supplying allowed
values.  The drawer header carries the add action, so an empty drawer
is only a hint."
  (if (null props)
      (list (jetpacs-text "No properties yet." :style "caption"
                          :color "outline"))
    (append
     (mapcar (lambda (kv)
               (glasspane-ui--property-row
                (car kv) (or (cdr kv) "") token pos
                (and buf (glasspane-detail--allowed-values buf pos (car kv)))))
             props)
     (list (jetpacs-text "Submit an empty value to remove a property."
                         :style "caption" :color "outline")))))

;;;; The drawers: tonal controls and the one open panel

(defun glasspane-detail--section-badge (info section)
  "The count badge for SECTION's control from INFO, or nil when empty."
  (let ((n (pcase section
             ('tags (length (plist-get info :tags)))
             ('props (length (plist-get info :props)))
             ('logbook (length (plist-get info :logbook)))
             ('links (plist-get info :backlinks)))))
    (and (integerp n) (> n 0) (number-to-string n))))

(defun glasspane-detail--section-controls (info &optional extras)
  "Build INFO's tonal drawer controls, start-aligned under the header.
Each icon is tooltipped with its drawer's name and badged with a count
when the drawer has content.  The selected icon is tonal in the primary
accent; tapping it closes its drawer, tapping another switches.  The
Connections drawer is offered only when an app layer contributed EXTRAS."
  (apply #'jetpacs-row
         (append
          (cl-loop for (name section icon label) in glasspane-detail--sections
                   unless (and (eq section 'links) (null extras))
                   collect
                   (let ((shown (eq glasspane-detail--section section)))
                     (jetpacs-tooltip
                      label
                      (jetpacs-icon-button
                       icon
                       (jetpacs-action "detail.section"
                                       :args (list :section name))
                       :variant (and shown "tonal")
                       :color (and shown "primary")
                       :badge (glasspane-detail--section-badge info section)
                       :content-description
                       (concat "Toggle " (downcase label)))
                      :position "below")))
          (list :fill t :arrange "start" :spacing 0 :align "center"))))

(defun glasspane-detail--section-action (main section)
  "The trailing header action of SECTION's open drawer for token MAIN."
  (let ((button (lambda (icon action label)
                  (jetpacs-icon-button icon action
                                       :variant "tonal" :size "small"
                                       :content-description label))))
    (pcase section
      ('tags (funcall button "edit"
                      (jetpacs-action "detail.tags.edit"
                                      :args (list :token main))
                      "Edit tags"))
      ((or 'scheduled 'deadline)
       (funcall button "edit_calendar"
                (jetpacs-action "detail.planning.edit"
                                :args (list :token main
                                            :type (if (eq section 'scheduled)
                                                      "SCHEDULED" "DEADLINE")))
                "Edit timestamp"))
      ('props (funcall button "add"
                       (jetpacs-action "heading.prop-add"
                                       :args (list :token main))
                       "Add property"))
      ('logbook (funcall button "edit_note"
                         (jetpacs-action "heading.add-note"
                                         :args (list :token main))
                         "Log note")))))

(defun glasspane-detail--strip-leading-dividers (nodes)
  "NODES without any leading divider: the drawer supplies its own edges."
  (seq-drop-while (lambda (node) (equal (plist-get node :t) "divider"))
                  nodes))

(defun glasspane-detail--section-panel (info main key &optional extras)
  "Build INFO's open drawer as a filled card, or nil when all are closed.
MAIN identifies the heading for edits, KEY supplies stable child ids and
EXTRAS are the app layers' Connections nodes.  A section header names
the drawer and carries its one editing action; the tonal icon above is
the only other chrome."
  (let* ((record (cl-find glasspane-detail--section
                          glasspane-detail--sections :key #'cadr))
         (section (cadr record))
         (children
          (pcase section
            ('props (glasspane-ui--properties-panel
                     (plist-get info :props) main (plist-get info :pos)
                     (plist-get info :buf)))
            ('logbook (or (glasspane-detail--logbook-panel
                           (plist-get info :logbook) key)
                          (list (jetpacs-text "Nothing logged yet."
                                              :style "caption"
                                              :color "outline"))))
            ('tags (list (glasspane-detail--tags-panel info main key)))
            ((or 'scheduled 'deadline)
             (glasspane-detail--planning-panel info main section))
            ('links (glasspane-detail--strip-leading-dividers extras)))))
    (when children
      (jetpacs-with-attrs
       (jetpacs-card
        (apply #'jetpacs-column
               (jetpacs-section-header
                (nth 3 record)
                :trailing (glasspane-detail--section-action main section))
               (append children (list :spacing 8)))
        :variant "filled")
       :id (jetpacs-wire-id "gp-detail-panel" key)))))

(defun glasspane-detail--relative-date (today when)
  "The ISO date that WHEN (\"+0d\", \"+1d\", \"+1w\") names from ISO TODAY.
Nil for any other spelling."
  (when (and (stringp when)
             (string-match "\\`\\+\\([0-9]+\\)\\([dw]\\)\\'" when))
    (jetpacs-dates-shift today (string-to-number (match-string 1 when))
                         (if (equal (match-string 2 when) "w") 'week 'day))))

(defun glasspane-detail--planning-panel (info main section)
  "Build INFO's SECTION (`scheduled' or `deadline') drawer for token MAIN.
A summary row (tinted icon, the human date, the full sentence beneath)
opens the foundation timestamp dialog, where time, repeater and delay
cookies are edited; a scrolling row of quick chips moves the day
without losing any of them, a native picker chooses a day, and Clear
removes the stamp.  Deadline chips ride the same verb with `:type'."
  (let* ((scheduled (eq section 'scheduled))
         (type (if scheduled "SCHEDULED" "DEADLINE"))
         (stamp (plist-get info (if scheduled :scheduled :deadline)))
         (today (glasspane-detail--today info))
         (h (glasspane-ui-human-date
             stamp today :done (plist-get info :done) :kind section
             :warn-days (or (plist-get info :warn-days) 14)))
         (date (plist-get h :date))
         (type-args (unless scheduled (list :type type)))
         (color (if h (plist-get h :color) "outline"))
         (quick (lambda (label when)
                  (jetpacs-chip
                   label
                   :selected (jetpacs-bool
                              (and date
                                   (equal date (glasspane-detail--relative-date
                                                today when))))
                   :on-tap (jetpacs-action
                            "heading.schedule"
                            :args (append (list :when when :token main)
                                          type-args))))))
    (list
     (jetpacs-with-semantics
      (jetpacs-with-attrs
       (jetpacs-box
        (jetpacs-row
         (jetpacs-icon (if scheduled "event" "flag") :size 22 :color color)
         (jetpacs-with-attrs
          (jetpacs-column
           (jetpacs-text (if h (plist-get h :label)
                           (if scheduled "Not scheduled" "No deadline"))
                         :style "body" :font-weight 500 :color color)
           (jetpacs-text (if h (plist-get h :long)
                           "Tap to pick a date, time or repeater.")
                         :style "caption" :color "outline")
           :spacing 2)
          :weight 1)
         (jetpacs-icon "chevron_right" :size 20 :color "outline")
         :fill t :align "center" :spacing 12)
        :alignment "center_start"
        :on-tap (jetpacs-action "detail.planning.edit"
                                :args (list :token main :type type)))
       :min_height 48)
      :name (if scheduled "Scheduled" "Deadline")
      :state-description (or stamp "not set"))
     (apply #'jetpacs-row
            (append
             (list (funcall quick "Today" "+0d")
                   (funcall quick "Tomorrow" "+1d")
                   (funcall quick "Next week" "+1w")
                   (jetpacs-date-button
                    "Pick date…"
                    (jetpacs-action "heading.schedule"
                                    :args (append (list :token main) type-args))
                    :value date))
             (when stamp
               (list (jetpacs-material3-assist-chip
                      "Clear" :icon "close"
                      :on-tap (jetpacs-action
                               "heading.schedule"
                               :args (append (list :clear t :token main)
                                             type-args)))))
             (list :scroll t :spacing 6 :align "center"))))))

(defun glasspane-detail--toggled-local-tags (local group tag)
  "LOCAL tags after toggling TAG within GROUP, a tag-groups plist or nil.
A tag already local leaves; otherwise it joins, ousting its siblings
first when GROUP is exclusive.  Pure."
  (cond ((member tag local) (remove tag local))
        ((plist-get group :exclusive)
         (append (cl-remove-if (lambda (candidate)
                                 (member candidate (plist-get group :tags)))
                               local)
                 (list tag)))
        (t (append local (list tag)))))

(defun glasspane-detail--area-group (info)
  "INFO's Area tag group plist, or nil when the vocabulary lacks one."
  (glasspane-org-tag-group (plist-get (plist-get info :tag-groups) :groups)
                           glasspane-area-tag-group))

(defun glasspane-detail--tag-toggle-chip (info main group tag)
  "A chip toggling TAG's membership in GROUP for INFO's heading MAIN.
Selected when the heading carries it; disabled when it is only
inherited, because Org can drop a tag only where it was set."
  (let* ((local (plist-get info :local-tags))
         (set (member tag local))
         (inherited (and (not set)
                         (member tag (plist-get info :inherited-tags))))
         (area (and group (eq group (glasspane-detail--area-group info)))))
    (jetpacs-chip tag
                  :selected (jetpacs-bool (or set inherited))
                  :enabled (and inherited :json-false)
                  :icon (cond (area (glasspane-area-icon tag))
                              (set "check"))
                  :on-tap (jetpacs-action
                           "heading.tags"
                           :args (list :token main
                                       :value (vconcat
                                               (glasspane-detail--toggled-local-tags
                                                local group tag)))))))

(defun glasspane-detail--tags-panel (info main key)
  "Build INFO's Tags drawer for token MAIN with its content id from KEY.
Every declared tag group shows its whole vocabulary as toggle chips, the
Area group with its icons, so known tags are one tap away and an
exclusive group swaps by construction; loose tags follow, with a chip
that opens the foundation picker for anything free-form."
  (let* ((membership (plist-get info :tag-groups))
         (groups (cl-remove-if-not (lambda (group) (plist-get group :tags))
                                   (plist-get membership :groups)))
         (loose (plist-get membership :loose)))
    (jetpacs-with-attrs
     (apply
      #'jetpacs-column
      (append
       (cl-loop for group in groups
                append
                (list
                 (jetpacs-text (concat (or (plist-get group :name) "Choose one")
                                       (when (plist-get group :exclusive)
                                         " · one of"))
                               :style "label" :color "outline")
                 (apply #'jetpacs-flow-row
                        (append
                         (mapcar (lambda (tag)
                                   (glasspane-detail--tag-toggle-chip
                                    info main group tag))
                                 (plist-get group :tags))
                         (list :spacing 4 :run-spacing 4)))))
       (list
        (jetpacs-text (if loose "Other tags" "Free tags")
                      :style "label" :color "outline")
        (apply #'jetpacs-flow-row
               (append
                (mapcar (lambda (tag)
                          (glasspane-detail--tag-toggle-chip info main nil tag))
                        loose)
                (list (jetpacs-material3-assist-chip
                       "Add tag…" :icon "add"
                       :on-tap (jetpacs-action "detail.tags.edit"
                                               :args (list :token main))))
                (list :spacing 4 :run-spacing 4))))
       (list :spacing 6)))
     :id (jetpacs-wire-id "gp-detail-tags" key))))

(defun glasspane-detail--breadcrumbs (info tokens)
  "The ancestor trail as one tappable caption line, or nil at the top level.
Each ancestor span opens that heading, so climbing out of a deep subtree
never detours through the file picker; the file itself is the top bar's
title and the overflow menu's Open in file.  TOKENS supplies the
ancestors' minted tokens."
  (let ((ancestors (plist-get info :ancestors))
        (anc-tokens (plist-get tokens :ancestors)))
    (when ancestors
      (jetpacs-rich-text
       (cl-loop for anc in ancestors
                for tok in anc-tokens
                for i from 0
                append
                (delq nil
                      (list (when (> i 0)
                              (jetpacs-span " › " :color "outline"))
                            (jetpacs-span (car anc) :color "primary"
                                          :on-tap (and tok
                                                       (jetpacs-action
                                                        "heading.tap"
                                                        :args (list :token tok)))))))
       :style "caption"))))

(defun glasspane-detail--reader-nodes (info)
  "The child-subtree reader nodes; plain org text when the reader is
absent or declines (the gap #6 degrade)."
  (let ((file (plist-get info :file))
        (pos (plist-get info :pos)))
    (or (and (fboundp 'glasspane-org-reader-subtree)
             (condition-case nil
                 (let ((glasspane-org-reader-inline-props nil))
                   ;; Own token set, never the subtree default: that set's
                   ;; replace sweep retires the tokens of any other live
                   ;; subtree render (a reader screen still on the stack)
                   ;; the moment a second caller exists.  The root's
                   ;; Properties and Logbook are this screen's tonal panels.
                   (glasspane-org-reader-subtree file pos 'all "detail-subtree"))
               (error nil)))
        (let ((body (with-current-buffer (plist-get info :buf)
                      (org-with-wide-buffer
                       (goto-char pos)
                       (org-back-to-heading t)
                       (forward-line 1)
                       (buffer-substring-no-properties
                        (point)
                        (progn (org-end-of-subtree t t) (point)))))))
          (unless (string-blank-p body)
            (list (jetpacs-text body :syntax "org")))))))

(defun glasspane-ui--detail-body (info tokens &optional extras)
  "The detail body: the header, its drawers and the reader, or the editor.
EXTRAS are the app layers' Connections nodes, shown in that drawer."
  (let* ((buf (plist-get info :buf))
         (file (plist-get info :file))
         (pos (plist-get info :pos))
         (key (glasspane-detail--key file pos))
         (main (plist-get tokens :main)))
    (if (not glasspane-ui--detail-read-mode)
        (let ((content (with-current-buffer buf
                         (org-with-wide-buffer
                          (goto-char pos)
                          (buffer-substring-no-properties
                           (point)
                           (progn (org-end-of-subtree t t) (point)))))))
          (jetpacs-column
           (jetpacs-editor (jetpacs-wire-id "gp-detail-editor" key)
                           :value content
                           :syntax "org"
                           :toolbar (jetpacs-org-toolbar)
                           :line-numbers (jetpacs-bool jetpacs-line-numbers)
                           :on-save (jetpacs-action
                                     "detail.save"
                                     :args (list
                                            :token main
                                            :mtime (plist-get info :edit-mtime)
                                            :beg (plist-get info :edit-beg)
                                            :end (plist-get info :edit-end)
                                            :tick (plist-get info :edit-tick))
                                     :when-offline "queue"
                                     :ttl-s glasspane-detail--save-ttl-s
                                     :dedupe (jetpacs-wire-id "gp-save" key)))))
      ;; Reader: the heading as a page.  Root metadata lives in the
      ;; pills and drawers above the body (sub-headings keep the swipe
      ;; reveal), so the reader renders no root drawers.
      (let ((reader (glasspane-detail--reader-nodes info)))
        (apply #'jetpacs-lazy-column
               (append
                (delq nil
                      (list
                       (glasspane-detail--breadcrumbs info tokens)
                       (apply #'jetpacs-row
                              (delq nil
                                    (list
                                     (glasspane-detail--todo-control info main)
                                     (jetpacs-with-attrs
                                      (jetpacs-text
                                       (glasspane-detail--title info)
                                       :style "headline" :font-weight 500
                                       :color (if (plist-get info :done)
                                                  "outline" "on_surface"))
                                      :weight 1)
                                     :fill t :align "top" :spacing 10)))
                       (glasspane-detail--status-pills info main)
                       (glasspane-detail--tag-line info)
                       (glasspane-detail--section-controls info extras)
                       (glasspane-detail--section-panel info main key extras)
                       (and reader (jetpacs-divider))))
                reader
                (list :spacing 8 :content-padding 16)))))))

(defun glasspane-ui--detail-body-with-notes (info tokens)
  "The detail body with every registered app layer's Connections nodes.
The layers' nodes fill the Connections drawer instead of trailing the
body, so backlinks and mentions are found where the other metadata is."
  (glasspane-ui--detail-body
   info tokens
   (cl-loop for fn in glasspane-ui-detail-nodes-functions
            append (condition-case nil
                       (funcall fn (plist-get info :ref))
                     (error nil)))))

(defun glasspane-detail--overflow-menu (info tokens)
  "The heading's overflow menu: everything that is not a resting affordance.
Grouped so two taps reach any of it; Delete keeps its device-side
confirm.  The Org actions… item exposes the heading to the foundation
sheet at build time, the reader's own route (SPEC 23.1)."
  (let* ((file (plist-get info :file))
         (buf (plist-get info :buf))
         (pos (plist-get info :pos))
         (main (plist-get tokens :main))
         (org-file (glasspane-detail--org-file-p file))
         (bufname (and (bufferp buf) (buffer-live-p buf) (buffer-name buf))))
    (when (and bufname (integerp pos))
      (jetpacs-buffer-expose bufname pos "jetpacs.org.heading"))
    (jetpacs-with-semantics
     (jetpacs-menu
      nil :icon "more_vert"
      :groups
      (delq nil
            (list
             (jetpacs-menu-group
              "Heading"
              (list
               (if (plist-get info :clocked-in)
                   (jetpacs-menu-item "Clock out" (jetpacs-action "org.clock.out")
                                      :icon "timer_off")
                 (jetpacs-menu-item "Clock in"
                                    (jetpacs-action "heading.clock-in"
                                                    :args (list :token main))
                                    :icon "timer"))
               (jetpacs-menu-item "Priority…"
                                  (jetpacs-action "detail.priority.edit"
                                                  :args (list :token main))
                                  :icon "priority_high")
               (jetpacs-menu-item "Log note…"
                                  (jetpacs-action "heading.add-note"
                                                  :args (list :token main))
                                  :icon "edit_note")
               (jetpacs-menu-item "Duplicate"
                                  (jetpacs-action "heading.duplicate"
                                                  :args (list :token main))
                                  :icon "content_copy")
               ;; Delete is unrecoverable — Archive is the kept path —
               ;; so the device confirm gates it (SPEC 14.1).
               (jetpacs-menu-item
                "Delete"
                (jetpacs-action "heading.delete"
                                :args (list :token main)
                                :confirm "Delete this heading and its subtree?")
                :icon "delete")))
             (when-let* ((items (glasspane-detail--share-items
                                 (plist-get info :ref))))
               (jetpacs-menu-group "Share" items))
             (when (or org-file bufname)
               (jetpacs-menu-group
                "Org"
                (delq nil
                      (list
                       (when org-file
                         (jetpacs-menu-item
                          "Open in file"
                          (glasspane-navigation-heading-action main)
                          :icon "open_in_new"))
                       (when org-file
                         (jetpacs-menu-item
                          "File properties…"
                          (jetpacs-action "files.properties.show"
                                          :args (list :file file))
                          :icon "tune"))
                       (when (and bufname (integerp pos))
                         (jetpacs-menu-item
                          "Org actions…"
                          (jetpacs-action "jetpacs.org.heading"
                                          :args (list :buffer bufname :pos pos))
                          :icon "more_horiz")))))))))
     :name "Heading actions")))

(defun glasspane-detail--top-actions (info tokens)
  "Detail top actions: a clock-out light while clocked in, the read/edit
toggle, and the overflow menu in read mode.  Three icons at most, so the
bar title has room beside the shell's own globals.  TOKENS carries the
heading token the menu addresses."
  (delq nil
        (list
         (when (plist-get info :clocked-in)
           (jetpacs-icon-button "timer_off" (jetpacs-action "org.clock.out")
                                :variant "tonal" :color "primary"
                                :content-description "Clock out"))
         (jetpacs-icon-button
          (if glasspane-ui--detail-read-mode "edit" "visibility")
          (jetpacs-action "detail.toggle-read")
          :content-description
          (if glasspane-ui--detail-read-mode "Edit Org text" "Read"))
         (when glasspane-ui--detail-read-mode
           (glasspane-detail--overflow-menu info tokens)))))

(defun glasspane-detail--bottom-bar (tokens)
  "Prev · Log note · Next, the note action centred whichever siblings exist.
Prev and Next appear only when a same-level sibling exists."
  (let ((main (plist-get tokens :main))
        (prev (plist-get tokens :prev))
        (next (plist-get tokens :next)))
    (jetpacs-row
     (if prev
         (jetpacs-button "Prev"
                         (jetpacs-action "heading.tap" :args (list :token prev))
                         :icon "chevron_left" :variant "text")
       (jetpacs-spacer :width 0))
     (jetpacs-spacer :weight 1)
     (jetpacs-button "Log note"
                     (jetpacs-action "heading.add-note" :args (list :token main))
                     :icon "edit_note" :variant "text")
     (jetpacs-spacer :weight 1)
     (if next
         (jetpacs-button "Next"
                         (jetpacs-action "heading.tap" :args (list :token next))
                         :icon "chevron_right" :variant "text")
       (jetpacs-spacer :width 0))
     :fill t :align "center")))

(defun glasspane-detail--floating-toolbar (info tokens)
  "The one-tap heading actions: Refile, Archive, and the app layers' extras.
Everything rarer lives in the top bar's overflow menu."
  (let ((ref (plist-get info :ref))
        (main (plist-get tokens :main))
        (archive (plist-get tokens :archive)))
    (apply #'jetpacs-row
           (append
            (delq nil
                  (list
                   (jetpacs-button "Refile"
                                   (jetpacs-action "heading.refile"
                                                   :args (list :token main))
                                   :icon "drive_file_move" :variant "text")
                   (when archive
                     (jetpacs-button
                      "Archive"
                      (jetpacs-action "jetpacs.org.archive"
                                      :args (list :token archive)
                                      :confirm "Archive this subtree?")
                      :icon "archive" :variant "text"))))
            (glasspane-ui--detail-toolbar-extras ref)
            (list :scroll t)))))

(defun glasspane-detail--screen (ref back)
  "The pushed detail screen for REF.
The bar names the document (its #+TITLE, else the file's base name);
the heading is the page's own headline.  A ref that stopped resolving
degrades to a go-back placeholder — the builder runs on every stack
rebuild, long after the heading may have moved (SPEC 14.5: re-present,
never guess)."
  (condition-case err
      (let* ((info (glasspane-ui--detail-meta ref))
             (tokens (glasspane-detail--tokens info)))
        (jetpacs-chrome-screen
         (or (plist-get info :file-title) "Detail")
         (glasspane-ui--detail-body-with-notes info tokens)
         :back back
         :actions (glasspane-detail--top-actions info tokens)
         :bottom-bar (when glasspane-ui--detail-read-mode
                       (glasspane-detail--bottom-bar tokens))
         :floating-toolbar (when glasspane-ui--detail-read-mode
                             (glasspane-detail--floating-toolbar
                              info tokens))))
    ((ebp-org-refused ebp-org-unresolved)
     (jetpacs-chrome-screen
      "Detail"
      (jetpacs-empty-state :icon "search_off"
                           :title "Heading moved or gone"
                           :caption "Go back and reopen it from a fresh list.")
      :back back))
    (error
     (jetpacs-chrome-screen
      "Detail"
      (jetpacs-column
       (jetpacs-text "Error loading heading" :style "title")
       (jetpacs-text (jetpacs-error-label err) :style "body"))
      :back back))))

;;;; Action handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-detail--on-tap (args params)
  "Open the tapped heading in the pushed detail screen."
  (let ((token (plist-get args :token)))
    (if (not (stringp token))
        'rejected
      (let ((ref (ebp-org-token-ref token :owner "glasspane")))
        (if (null ref)
            'stale
          (setq glasspane-ui--detail-read-mode t
                glasspane-detail--section nil)
          (glasspane-detail--push-screen
           (or (plist-get params :surface)
               (jetpacs-shell-surface-for "glasspane"))
           ref)
          'accepted)))))

(defun glasspane-detail--ref-location (ref)
  "Resolve REF to (BUFFER FILE POSITION), releasing its marker."
  (let ((marker (ebp-org-resolve-ref ref)))
    (unwind-protect
        (list (marker-buffer marker)
              (buffer-file-name (marker-buffer marker))
              (marker-position marker))
      (set-marker marker nil))))

(defun glasspane-detail--location-status (err)
  "Map engine condition ERR to a handler result, including retry."
  (pcase (ebp-org-refusal-disposition err)
    ('retry (jetpacs-retry-later))
    (status status)))

(defun glasspane-detail--on-visit (args _params)
  "Resolve ARGS' heading token and use the canonical document presenter."
  (let ((token (plist-get args :token)))
    (cond
     ((not (stringp token)) 'rejected)
     (t
      (if-let* ((ref (ebp-org-token-ref token :owner "glasspane")))
          (condition-case err
              (pcase-let ((`(,_buffer ,file ,pos)
                            (glasspane-detail--ref-location ref)))
                (glasspane-navigation-open-document file pos))
            ((ebp-org-refused ebp-org-unavailable ebp-org-unresolved)
             (glasspane-detail--location-status err)))
        'stale)))))

(defun glasspane-detail--on-open-file (args params)
  "Compatibility adapter for cached `detail.open-file' events.
New builders emit `heading.visit'; both token verbs deliberately call the
same resolver and canonical presenter with ARGS and PARAMS."
  (glasspane-detail--on-visit args params))

(defun glasspane-detail--on-toggle-read (_args params)
  "Flip the reader/editor mode; the builder re-reads the flag."
  (setq glasspane-ui--detail-read-mode (not glasspane-ui--detail-read-mode))
  (jetpacs-app-defer-refresh params)
  'accepted)

(defun glasspane-detail--on-section (args params)
  "Show ARGS' `:section' panel, or hide it when it is already shown.
The tonal icons' verb: one panel at a time, so showing the other
replaces it, and PARAMS' surface re-pushes.  A name outside
`glasspane-detail--sections' rejects."
  (let ((section (cadr (assoc (plist-get args :section)
                              glasspane-detail--sections))))
    (if (null section)
        'rejected
      (setq glasspane-detail--section
            (unless (eq glasspane-detail--section section) section))
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-detail--on-save (args params)
  "Freshness-check and replace the subtree with the editor's `:value'.
The rewrite returns an ID-aware fresh ref so the screen can be re-pushed
over the heading's new coordinates."
  (let ((value (plist-get args :value))
        (ref (glasspane-detail--token-ref args)))
    (cond
     ((not (stringp value)) 'rejected)
     ;; Shape-gated BEFORE the region is touched, because this failure is
     ;; destructive rather than merely a wrong answer: a value whose
     ;; leading stars the user deleted signals inside
     ;; `ebp-org-ref-at-point' only AFTER delete-region+insert, so the
     ;; buffer keeps an unsaved mutation that the next unrelated save
     ;; flushes to disk.
     ((not (string-match-p "\\`\\*+\\(?:[ \t]\\|$\\)" value)) 'rejected)
     ((null ref) 'stale)
     (t
      (condition-case err
          (let ((new-ref
                 (glasspane-org-fresh-splice
                  ref value
                  (plist-get args :mtime)
                  (plist-get args :beg)
                  (plist-get args :end)
                  (plist-get args :tick))))
            (setq glasspane-ui--detail-read-mode t)
            (jetpacs-shell-notify "Saved heading"
                                  (plist-get params :surface))
            (glasspane-detail--push-screen
             (or (plist-get params :surface)
                 (jetpacs-shell-surface-for "glasspane"))
             new-ref)
            'accepted)
        (glasspane-org-splice-refused
         (jetpacs-shell-notify (cadr err) (plist-get params :surface))
         'rejected)
        (ebp-org-refused 'rejected)
        (ebp-org-unresolved 'stale)
        (error (message "glasspane: detail save failed: %s"
                        (jetpacs-error-label err))
               (jetpacs-toast "Save failed")
               'rejected))))))

(defun glasspane-detail--on-todo-set (args params)
  "Set the TODO state to `:state'; an empty state clears it."
  (let ((state (plist-get args :state)))
    (if (not (stringp state))
        'rejected
      (let* ((clear (string-empty-p state))
             (status (glasspane-ui-at-ref
                      args (lambda () (org-todo (if clear 'none state))) t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify (if clear "State cleared"
                                  (format "State → %s" state))
                                (plist-get params :surface))
          (jetpacs-app-defer-refresh params))
        status))))

(defun glasspane-detail--on-todo-cycle (args params)
  "Cycle the heading through the TODO keyword sequence."
  (let* ((state nil)
         (status (glasspane-ui-at-ref
                  args
                  (lambda ()
                    (org-todo)
                    (unless (org-get-todo-state) (org-todo))
                    (setq state (org-get-todo-state)))
                  t)))
    (when (eq status 'accepted)
      (jetpacs-shell-notify (if state (format "State → %s" state)
                              "State cleared")
                            (plist-get params :surface))
      (jetpacs-app-defer-refresh params))
    status))

(defun glasspane-detail--on-schedule (args params)
  "Move the heading's SCHEDULED stamp, or its DEADLINE with `:type'.
`:when' is relative to today (\"+0d\", \"+1d\", \"+1w\"), `:value' an ISO
date from the picker, and `:clear' removes the stamp.  A moved stamp
keeps its time of day, repeater and delay cookie: only the day changes.
No prompting arm — the empty-args tap is a build-time bug, not a user
path (the picker flows are the foundation dialog's)."
  (let* ((deadline (equal (plist-get args :type) "DEADLINE"))
         (prop (if deadline "DEADLINE" "SCHEDULED"))
         (setter (if deadline #'org-deadline #'org-schedule))
         (clearp (let ((c (plist-get args :clear)))
                   (and c (not (eq c :json-false)))))
         (when (plist-get args :when))
         (value (plist-get args :value))
         (date (or (and (stringp when) (not (string-empty-p when))
                        (or (glasspane-detail--relative-date
                             (format-time-string "%Y-%m-%d") when)
                            when))
                   (and (stringp value) (not (string-empty-p value)) value)))
         (surface (plist-get params :surface)))
    (cond
     (clearp
      (let ((status (glasspane-ui-at-ref
                     args (lambda () (funcall setter '(4))) t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify (if deadline "Deadline cleared"
                                  "Schedule cleared")
                                surface)
          (jetpacs-app-defer-refresh params))
        status))
     (date
      (let ((status
             (glasspane-ui-at-ref
              args
              (lambda ()
                ;; Org rebuilds the stamp from the date it is given and
                ;; re-attaches the old repeater and delay itself; the
                ;; time of day survives only when handed back.
                (let ((time (glasspane-ui-ts-time-range
                             (org-entry-get nil prop))))
                  (funcall setter nil
                           (if (and time (ebp-org-ts-date date))
                               (concat date " " time)
                             date))))
              t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify (format "%s %s" (if deadline "Deadline"
                                                  "Scheduled")
                                        date)
                                surface)
          (jetpacs-app-defer-refresh params))
        status))
     (t 'rejected))))

(defun glasspane-detail--on-priority (args params)
  "Set the priority to `:value'; an empty value removes it."
  (let ((val (plist-get args :value)))
    (if (not (stringp val))
        'rejected
      (let* ((remove (string-empty-p val))
             (status (glasspane-ui-at-ref
                      args
                      (lambda ()
                        (if remove (org-priority 'remove)
                          (org-priority (string-to-char (upcase val)))))
                      t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify (if remove "Priority cleared"
                                  (format "Priority %s" (upcase val)))
                                (plist-get params :surface))
          (jetpacs-app-defer-refresh params))
        status))))

(defun glasspane-detail--on-tags (args params)
  "Replace the heading's local tags with `:value' (the enum's vector).
Device-injected strings are 23.1 input: each member must be in org's
own tag charset or the whole write refuses."
  (let ((val (plist-get args :value)))
    (if (not (or (vectorp val) (proper-list-p val)))
        'rejected
      (let ((tags (append val nil)))
        (if (not (cl-every (lambda (tg)
                             (and (stringp tg)
                                  (string-match-p "\\`[[:alnum:]_@#%]+\\'"
                                                  tg)))
                           tags))
            'rejected
          (let ((status (glasspane-ui-at-ref
                         args (lambda () (org-set-tags tags)) t)))
            (when (eq status 'accepted)
              (jetpacs-shell-notify (if tags (format "Tags: %s"
                                                     (string-join tags " "))
                                      "Tags cleared")
                                    (plist-get params :surface))
              (jetpacs-app-defer-refresh params))
            status))))))

(defun glasspane-detail--refile-flow (ref params)
  "The bridged refile picker; runs in a continuation behind can-bridge."
  (glasspane-detail--with-prompting
   (lambda ()
     (let ((marker (ebp-org-resolve-ref ref)))
       (unwind-protect
           (with-current-buffer (marker-buffer marker)
             (org-with-wide-buffer
              (goto-char marker)
              (let* ((org-refile-targets
                      (or org-refile-targets
                          '((org-agenda-files :maxlevel . 3))))
                     (targets (org-refile-get-targets))
                     (choice (condition-case nil
                                 (completing-read "Refile to: "
                                                  (mapcar #'car targets)
                                                  nil t)
                               (quit nil)))
                     (target (and choice (assoc choice targets))))
                (if (not target)
                    (jetpacs-shell-notify "Refile cancelled"
                                          (plist-get params :surface))
                  (org-refile nil nil target)
                  ;; Refile may dirty both source and target.  Put every
                  ;; affected Org buffer through the native policy so neither
                  ;; side can bypass Org Crypt or leave another namespace's
                  ;; projection memo stale.
                  (dolist (buffer (org-buffer-list 'files t))
                    (when (buffer-modified-p buffer)
                      (glasspane-org-save-and-invalidate buffer)))
                  (jetpacs-shell-notify (format "Refiled to %s" choice)
                                        (plist-get params :surface))))))
         (set-marker marker nil)))
     (glasspane-detail--leave params))
   params))

(defun glasspane-detail--on-refile (args params)
  "Refile the whole subtree through a bridged target picker."
  (let ((ref (glasspane-detail--token-ref args)))
    (cond
     ((not (stringp (plist-get args :token))) 'rejected)
     ((null ref) 'stale)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-detail--refile-flow ref params)))
      'accepted))))

(defun glasspane-detail--insert-note (note)
  "Insert NOTE where org-log says notes belong, in org's own format."
  (let ((org-log-into-drawer t))
    (goto-char (org-log-beginning t))
    (insert (format "- Note taken on %s \\\\\n  %s\n"
                    (format-time-string (org-time-stamp-format t t))
                    (replace-regexp-in-string "\n" "\n  " note)))))

(defun glasspane-detail--on-add-note (args params)
  "Quick logbook note through a bridged prompt."
  (cond
   ((not (stringp (plist-get args :token))) 'rejected)
   ((null (glasspane-detail--token-ref args)) 'stale)
   (t
    (jetpacs-flow-continue
     (lambda ()
       (glasspane-detail--with-prompting
        (lambda ()
          (let ((note (string-trim
                       (condition-case nil (read-string "Note: ")
                         (quit "")))))
            (if (string-empty-p note)
                (jetpacs-shell-notify "Note cancelled"
                                      (plist-get params :surface))
              (when (eq (glasspane-ui-at-ref
                         args
                         (lambda ()
                           (glasspane-detail--insert-note
                            (jetpacs-scalar-text note)))
                         t)
                        'accepted)
                (jetpacs-shell-notify "Note added"
                                      (plist-get params :surface))))
            (ignore-errors
              (jetpacs-shell-push (plist-get params :surface)))))
        params)))
    'accepted)))

(defun glasspane-detail--on-delete (args params)
  "Delete the subtree outright.  The 14.1 `:confirm' on the emitting
descriptor already parked this behind a device AlertDialog — Archive
is the recoverable path; this one is for genuine junk."
  (let ((status (glasspane-ui-at-ref
                 args
                 (lambda ()
                   (delete-region (point)
                                  (progn (org-end-of-subtree t t) (point))))
                 t)))
    (when (eq status 'accepted)
      (jetpacs-shell-notify "Deleted" (plist-get params :surface))
      (jetpacs-flow-continue (lambda () (glasspane-detail--leave params))))
    status))

(defun glasspane-detail--on-duplicate (args params)
  "Copy the subtree and insert it right after itself — the
recurring-meeting-notes idiom."
  (let ((status (glasspane-ui-at-ref
                 args
                 (lambda ()
                   (let ((subtree (buffer-substring-no-properties
                                   (point)
                                   (save-excursion
                                     (org-end-of-subtree t t) (point)))))
                     (org-end-of-subtree t t)
                     (unless (bolp) (insert "\n"))
                     (insert subtree)))
                 t)))
    (when (eq status 'accepted)
      (jetpacs-shell-notify "Duplicated" (plist-get params :surface))
      (jetpacs-app-defer-refresh params))
    status))

(defun glasspane-detail--on-prop-set (args params)
  "Set property `:name' to the row input's injected `:value'.
An empty value deletes the property."
  (let* ((name (plist-get args :name))
         (raw (plist-get args :value))
         (value (cond
                 ((eq raw t) "t")
                 ((memq raw '(nil :json-false)) "nil")
                 ((vectorp raw) (if (> (length raw) 0)
                                    (format "%s" (aref raw 0))
                                  ""))
                 ((proper-list-p raw) (if raw (format "%s" (car raw)) ""))
                 ((stringp raw) (string-trim raw))
                 (t (format "%s" raw)))))
    (if (not (and (stringp name) (not (string-empty-p name))))
        'rejected
      (let ((status (glasspane-ui-at-ref
                     args
                     (lambda ()
                       (if (string-empty-p value)
                           (org-delete-property name)
                         (org-set-property name value)))
                     t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify (if (string-empty-p value)
                                    (format "Removed %s" name)
                                  (format "%s → %s" name value))
                                (plist-get params :surface))
          (jetpacs-app-defer-refresh params))
        status))))

(defun glasspane-detail--on-prop-add (args params)
  "Ask for a property key through the bridge; the new (empty) property
then appears as a row whose value column is ready to fill in."
  (cond
   ((not (stringp (plist-get args :token))) 'rejected)
   ((null (glasspane-detail--token-ref args)) 'stale)
   (t
    (jetpacs-flow-continue
     (lambda ()
       (glasspane-detail--with-prompting
        (lambda ()
          (let ((name (string-trim
                       (condition-case nil
                           (read-string "New property name: ")
                         (quit "")))))
            (cond
             ((string-empty-p name) nil)
             ((string-match-p "[: \t]" name)
              (jetpacs-shell-notify
               "Property names can't contain colons or spaces"
               (plist-get params :surface)))
             ((eq (glasspane-ui-at-ref
                   args
                   (lambda () (org-set-property (upcase name) ""))
                   t)
                  'accepted)
              (jetpacs-shell-notify
               (format "Added %s — fill in its value" (upcase name))
               (plist-get params :surface))))
            (ignore-errors
              (jetpacs-shell-push (plist-get params :surface)))))
        params)))
    'accepted)))

(defun glasspane-detail--show-props-dialog (ref params)
  "The sub-heading Properties dialog: editable rows through the same
`heading.prop-set' funnel, on a token minted for THIS dialog."
  (condition-case err
      (let (info)
        (let ((marker (ebp-org-resolve-ref ref)))
          (unwind-protect
              (with-current-buffer (marker-buffer marker)
                (org-with-wide-buffer
                 (goto-char marker)
                 (org-back-to-heading t)
                 (setq info (list :headline (org-get-heading t t t t)
                                  :props (org-entry-properties nil 'standard)
                                  :pos (point)
                                  :ref (ebp-org-ref-at-point)))))
            (set-marker marker nil)))
        (let* ((token (car (ebp-org-ref-tokens (list (plist-get info :ref))
                                               :set "detail-props"
                                               :owner "glasspane")))
               (pos (plist-get info :pos))
               (props (plist-get info :props)))
          (glasspane-detail--show-dialog
           (jetpacs-wire-id "gp-props" (glasspane-detail--key
                                        (plist-get (plist-get info :ref) :file)
                                        pos))
           (apply #'jetpacs-column
                  (append
                   (list (jetpacs-text "Properties" :style "title")
                         (jetpacs-text (or (plist-get info :headline) "")
                                       :style "caption"))
                   (or (mapcar (lambda (kv)
                                 (glasspane-ui--property-row
                                  (car kv) (or (cdr kv) "") token pos))
                               props)
                       (list (jetpacs-text "No properties yet."
                                           :style "caption")))
                   (delq nil
                         (list
                          (when props
                            (jetpacs-text
                             "Submit an empty value to remove a property."
                             :style "caption"))
                          (jetpacs-row
                           (jetpacs-button "+ Add property"
                                           (jetpacs-action
                                            "heading.prop-add"
                                            :args (list :token token))
                                           :variant "text")
                           (jetpacs-spacer :weight 1)
                           (jetpacs-button "Close" (jetpacs-dialog-dismiss)
                                           :variant "text"))))
                   (list :spacing 8)))
           :params params)))
    (error (message "glasspane: properties dialog failed: %s"
                    (jetpacs-error-label err))
           (jetpacs-shell-notify "Properties failed"
                                 (plist-get params :surface)))))

(defun glasspane-detail--on-props-show (args params)
  "Surface a sub-heading's properties as an editable dialog (S3)."
  (let ((ref (glasspane-detail--token-ref args)))
    (cond
     ((not (stringp (plist-get args :token))) 'rejected)
     ((null ref) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-detail--show-props-dialog ref params)))
      'accepted))))

(defun glasspane-detail--delegate-heading (args params value)
  "Open the foundation heading editor VALUE for ARGS' token using PARAMS.
VALUE names a `jetpacs.org.heading' sheet candidate (\"tags\",
\"priority\", …).  Look up the app-owned token's ref before scheduling
presentation.  Resolve that ref in the continuation before delegating to
the registered heading action.  Only the resolved heading position
crosses that boundary; the device cannot supply a raw position."
  (let ((token (plist-get args :token))
        (handler (gethash "jetpacs.org.heading" jetpacs-action-handlers)))
    (cond
     ((not (stringp token)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (functionp handler)) 'rejected)
     ((not (and (jetpacs-client) (jetpacs-granted-p "surfaces.dialog")))
      'rejected)
     (t
      (if-let* ((ref (ebp-org-token-ref token :owner "glasspane")))
          (progn
            (jetpacs-flow-continue
             (lambda ()
               (condition-case err
                   (pcase-let ((`(,buf ,_file ,pos)
                                (glasspane-detail--ref-location ref)))
                     (jetpacs-buffer-expose (buffer-name buf) pos
                                             "jetpacs.org.heading")
                     (funcall handler
                              (list :buffer (buffer-name buf) :pos pos
                                    :value value)
                              params))
                 (error
                  (jetpacs-shell-notify
                   (jetpacs-error-label err) (plist-get params :surface))))))
            'accepted)
        'stale)))))

(defun glasspane-detail--on-tags-edit (args params)
  "Open the foundation grouped tag picker for ARGS' token using PARAMS."
  (glasspane-detail--delegate-heading args params "tags"))

(defun glasspane-detail--on-priority-edit (args params)
  "Open the foundation priority dialog for ARGS' token using PARAMS."
  (glasspane-detail--delegate-heading args params "priority"))

(defun glasspane-detail--on-planning-edit (args params)
  "Open the foundation timestamp dialog on this heading's `:type' stamp.
The whole picker flow — date, time, repeater cookies, clear — is the
base module's (jetpacs-org-dialogs.el:558-745); this verb only seeds it,
which is the G4 delegation replacing v1's app planning dialog."
  (let ((type (plist-get args :type))
        (ref (glasspane-detail--token-ref args)))
    (cond
     ((not (member type '("SCHEDULED" "DEADLINE"))) 'rejected)
     ((not (stringp (plist-get args :token))) 'rejected)
     ((null ref) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (let ((stamp (let ((marker (ebp-org-resolve-ref ref)))
                            (unwind-protect
                                (with-current-buffer (marker-buffer marker)
                                  (org-with-wide-buffer
                                   (goto-char marker)
                                   (org-entry-get nil type)))
                              (set-marker marker nil)))))
               (jetpacs-org-dialogs--ts-open
                (list :kind 'planning :ref ref :which type)
                stamp params))
           (error (message "glasspane: planning editor failed: %s"
                           (jetpacs-error-label err))))))
      'accepted))))

(defun glasspane-detail--on-link-open (args params)
  "Open `:link' through org's link machinery, Emacs-side.
Landing on an org heading pushes the detail screen over it; anything
else (http, images) reports back as a snackbar."
  (let ((link (plist-get args :link)))
    (if (not (and (stringp link) (not (string-empty-p link))))
        'rejected
      (let ((surface (or (plist-get params :surface)
                         (jetpacs-shell-surface-for "glasspane"))))
        (jetpacs-flow-continue
         (lambda ()
           (condition-case err
               (progn
                 (org-link-open-from-string link)
                 (if (and (derived-mode-p 'org-mode)
                          (buffer-file-name)
                          (ignore-errors (org-back-to-heading t) t))
                     (let ((ref (ebp-org-ref-at-point)))
                       (setq glasspane-ui--detail-read-mode t)
                       ;; Already outside the dispatch extent: push now.
                       (condition-case perr
                           (jetpacs-chrome-push-screen
                            surface glasspane-detail--screen-id
                            (lambda (back)
                              (glasspane-detail--screen ref back)))
                         (error (message "glasspane: link push failed: %s"
                                         (jetpacs-error-label perr)))))
                   (jetpacs-shell-notify
                    (format "Opened %s" (jetpacs-truncate-text
                                         (jetpacs-scalar-text link) 60))
                    surface)
                   (ignore-errors (jetpacs-shell-push surface))))
             (error
              (message "glasspane: link open failed: %s"
                       (jetpacs-error-label err))
              (jetpacs-shell-notify "Couldn't open that link" surface)
              (ignore-errors (jetpacs-shell-push surface))))))
        'accepted))))

(defun glasspane-detail--on-clock-in (args params)
  "Clock in at the tapped heading."
  (let ((status (glasspane-ui-at-ref args #'org-clock-in)))
    (when (eq status 'accepted)
      (jetpacs-shell-notify "Clocked in" (plist-get params :surface))
      (jetpacs-app-defer-refresh params))
    status))

;;;; The file-properties dialog pair

(defconst glasspane-detail--file-prop-fields
  '("file-prop-title" "file-prop-category" "file-prop-tags"
    "file-prop-todo-active" "file-prop-todo-finished"
    "file-prop-author" "file-prop-email" "file-prop-date"
    "file-prop-startup" "file-prop-archive")
  "The captured field ids of the file-properties dialog, in save order.")

(defun glasspane-detail--show-file-props-dialog (file params)
  "The whole-file keyword editor.  Seeding is each field's `:value'
\(S2): the Save action captures every field and echoes them back in
its own event — no state round-trip (v1 read 9 `jetpacs-ui-state's)."
  (condition-case err
      (let* ((buf (or (get-file-buffer file) (find-file-noselect file t)))
             (kwds (with-current-buffer buf
                     (org-collect-keywords
                      '("TITLE" "CATEGORY" "FILETAGS" "TODO" "SEQ_TODO"
                        "TYP_TODO" "STARTUP" "AUTHOR" "EMAIL" "DATE"
                        "ARCHIVE"))))
             (get (lambda (k) (car (alist-get k kwds nil nil #'equal))))
             (filetags-str (funcall get "FILETAGS"))
             (filetags (when filetags-str
                         (split-string filetags-str ":" t "[ \t\n\r]+")))
             (available (cl-remove-duplicates
                         (append filetags (jetpacs-org-settings-tag-options))
                         :test #'equal :from-end t))
             (todo-str (or (funcall get "TODO")
                           (funcall get "SEQ_TODO")
                           (funcall get "TYP_TODO")))
             (todo-parts (and todo-str (split-string todo-str "|")))
             (todo-active (if todo-parts
                              (string-join (split-string (car todo-parts)
                                                         "[ \t]+" t)
                                           ", ")
                            ""))
             (todo-finished (if (and todo-parts (cadr todo-parts))
                                (string-join (split-string (cadr todo-parts)
                                                           "[ \t]+" t)
                                             ", ")
                              "")))
        (glasspane-detail--show-dialog
         (jetpacs-wire-id "gp-file-props" file)
         (jetpacs-column
          (jetpacs-text "File properties" :style "title")
          (jetpacs-text (file-name-nondirectory file) :style "caption")
          (jetpacs-text-input "file-prop-title" :label "Title"
                              :value (or (funcall get "TITLE") "")
                              :single-line t)
          (jetpacs-text-input "file-prop-category" :label "Category"
                              :value (or (funcall get "CATEGORY") "")
                              :single-line t)
          (jetpacs-text "File tags" :style "caption")
          (jetpacs-enum-list "file-prop-tags"
                             (mapcar (lambda (tg) (jetpacs-enum-option tg tg))
                                     available)
                             :value (cl-remove-duplicates filetags
                                                          :test #'equal)
                             :multi-select t :allow-add t)
          (jetpacs-text "TODO sequence" :style "caption")
          (jetpacs-text-input "file-prop-todo-active" :label "Active states"
                              :value todo-active :single-line t)
          (jetpacs-text-input "file-prop-todo-finished"
                              :label "Finished states"
                              :value todo-finished :single-line t)
          (jetpacs-text "Metadata" :style "caption")
          (jetpacs-text-input "file-prop-author" :label "Author"
                              :value (or (funcall get "AUTHOR") "")
                              :single-line t)
          (jetpacs-text-input "file-prop-email" :label "Email"
                              :value (or (funcall get "EMAIL") "")
                              :single-line t)
          (jetpacs-text-input "file-prop-date" :label "Date"
                              :value (or (funcall get "DATE") "")
                              :single-line t)
          (jetpacs-text "Options" :style "caption")
          (jetpacs-text-input "file-prop-startup" :label "Startup"
                              :value (or (funcall get "STARTUP") "")
                              :single-line t)
          (jetpacs-text-input "file-prop-archive" :label "Archive"
                              :value (or (funcall get "ARCHIVE") "")
                              :single-line t)
          (jetpacs-row
           (jetpacs-spacer :weight 1)
           (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
           (jetpacs-spacer :width 8)
           (jetpacs-button "Save"
                           (jetpacs-action
                            "files.properties.save"
                            :args (list :file file)
                            :capture-fields
                            glasspane-detail--file-prop-fields)))
          :spacing 8)
         :params params))
    (error (message "glasspane: file properties dialog failed: %s"
                    (jetpacs-error-label err))
           (jetpacs-shell-notify "Properties failed"
                                 (plist-get params :surface)))))

(defun glasspane-detail--on-file-props-show (args params)
  "Open the file-properties editor dialog for `:file'."
  (let ((file (plist-get args :file)))
    (cond
     ((not (and (glasspane-detail--org-file-p file)
                (ebp-org-file-allowed-p file)))
      'rejected)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-detail--show-file-props-dialog file params)))
      'accepted))))

(defun glasspane-detail--update-keyword (kwd val)
  "Set, replace, or (VAL empty/nil) remove #+KWD in the current buffer.
Point discipline is the caller's `org-with-wide-buffer'; an inserted
non-TITLE keyword lands after an existing #+TITLE line."
  (goto-char (point-min))
  (if (re-search-forward (format "^[ \t]*#\\+%s:[ \t]*\\(.*\\)$"
                                 (regexp-quote kwd))
                         nil t)
      (if (and val (not (string-empty-p val)))
          (replace-match val t t nil 1)
        (delete-region (line-beginning-position)
                       (min (1+ (line-end-position)) (point-max))))
    (when (and val (not (string-empty-p val)))
      (goto-char (point-min))
      (unless (equal kwd "TITLE")
        (when (re-search-forward "^[ \t]*#\\+TITLE:.*$" nil t)
          (forward-line 1)))
      (insert (format "#+%s: %s\n" kwd val)))))

(defun glasspane-detail--on-file-props-save (args params)
  "Write the captured dialog fields back as file keywords, durably."
  (let ((file (plist-get args :file))
        (fields (plist-get params :fields)))
    (cond
     ((not (and (glasspane-detail--org-file-p file)
                (ebp-org-file-allowed-p file)
                (file-writable-p file)))
      'rejected)
     ((not (and (consp fields) (keywordp (car fields)))) 'rejected)
     (t
      (condition-case err
          (let* ((buf (or (get-file-buffer file) (find-file-noselect file t)))
                 (fget (lambda (k) (let ((v (plist-get fields k)))
                                     (and (stringp v) v))))
                 (tags-val (plist-get fields :file-prop-tags))
                 (tags (cl-remove-if-not
                        #'stringp
                        (cond ((vectorp tags-val) (append tags-val nil))
                              ((proper-list-p tags-val) tags-val))))
                 (join-states
                  (lambda (s)
                    (when (stringp s)
                      (let ((words (split-string s "[ \t]*,[ \t]*" t)))
                        (when words (string-join words " "))))))
                 (active (funcall join-states
                                  (funcall fget :file-prop-todo-active)))
                 (finished (funcall join-states
                                    (funcall fget :file-prop-todo-finished)))
                 (todo-str (if (and active finished)
                               (concat active " | " finished)
                             (or active finished))))
            (with-current-buffer buf
              (org-with-wide-buffer
               (glasspane-detail--update-keyword
                "TITLE" (funcall fget :file-prop-title))
               (glasspane-detail--update-keyword
                "FILETAGS" (when tags
                             (concat ":" (string-join tags ":") ":")))
               (glasspane-detail--update-keyword
                "CATEGORY" (funcall fget :file-prop-category))
               (glasspane-detail--update-keyword "TODO" todo-str)
               (glasspane-detail--update-keyword
                "STARTUP" (funcall fget :file-prop-startup))
               (glasspane-detail--update-keyword
                "AUTHOR" (funcall fget :file-prop-author))
               (glasspane-detail--update-keyword
                "EMAIL" (funcall fget :file-prop-email))
               (glasspane-detail--update-keyword
                "DATE" (funcall fget :file-prop-date))
               (glasspane-detail--update-keyword
                "ARCHIVE" (funcall fget :file-prop-archive))
               ;; Stock Emacs 30.1's org-element.elc mis-compiles
               ;; `org-element--get-category's cache-miss arm into a
               ;; CALL of the `org-element-with-disabled-cache' macro:
               ;; once a fresh #+CATEGORY line exists outside the
               ;; element cache, the next `org-get-tags' in this buffer
               ;; dies with invalid-function.  Priming the line into
               ;; the cache keeps every later render on the good arm.
               (goto-char (point-min))
               (when (re-search-forward "^[ \t]*#\\+CATEGORY:" nil t)
                 (ignore-errors (org-element-at-point)))))
            (glasspane-org-save-and-invalidate buf)
            ;; The Save event arrives in dialog context (no :surface) —
            ;; refresh where the dialog was opened, then retire it.
            (let ((origin (or (plist-get glasspane-detail--dialog :params)
                              params)))
              (glasspane-detail--dialog-close)
              (jetpacs-shell-notify "File properties saved"
                                    (plist-get origin :surface))
              (jetpacs-app-defer-refresh origin))
            'accepted)
        (error (message "glasspane: file properties save failed: %s"
                        (jetpacs-error-label err))
               'rejected))))))

;;;; The files editor adapter (the Properties top-bar action; the read/
;;;; refile toggles are the reader adapter's contribution)

(defun glasspane-detail--editor-actions (path)
  "The file-properties top-bar action for org PATH (files editor seam)."
  (when (glasspane-detail--org-file-p path)
    (list (jetpacs-icon-button "tune"
                               (jetpacs-action "files.properties.show"
                                               :args (list :file path))
                               :content-description "File properties"))))

;;;; Registration

(defconst glasspane-detail--verbs
  '("heading.tap"
    "heading.visit"
    "detail.open-file"
    "detail.toggle-read"
    "detail.section"
    "detail.priority.edit"
    "detail.save"
    "detail.planning.edit"
    "detail.tags.edit"
    "heading.todo-set"
    "heading.todo-cycle"
    "heading.schedule"
    "heading.priority"
    "heading.tags"
    "heading.refile"
    "heading.add-note"
    "heading.delete"
    "heading.duplicate"
    "heading.prop-set"
    "heading.prop-add"
    "heading.props.show"
    "heading.clock-in"
    "org.link.open"
    "files.properties.show"
    "files.properties.save")
  "The verbs this rung owns, for the register/unregister sweep.
heading.menu lives with the reader's sheet (G4 sibling);
heading.reorder with the reorderable-list builders; search.by-tag
with the search state (G6).")

(defun glasspane-detail-register ()
  "Register the detail verbs and downstream Org editor adapter.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "heading.tap" #'glasspane-detail--on-tap
                       :doc "Open a heading in the pushed detail screen")
    (jetpacs-defaction "heading.visit" #'glasspane-detail--on-visit
                       :doc "Resolve a heading and open its canonical document"
                       :args '((:name token :type "text" :required t)))
    (jetpacs-defaction "detail.open-file" #'glasspane-detail--on-open-file
                       :doc "Compatibility alias for cached heading file opens"
                       :args '((:name token :type "text" :required t)))
    (jetpacs-defaction "detail.toggle-read"
                       #'glasspane-detail--on-toggle-read
                       :doc "Flip the detail reader/editor mode")
    (jetpacs-defaction "detail.section" #'glasspane-detail--on-section
                       :doc "Show or hide one of the heading's metadata drawers"
                       :args '((:name section :type "text" :required t)))
    (jetpacs-defaction "detail.priority.edit"
                       #'glasspane-detail--on-priority-edit
                       :doc "Open the foundation priority dialog for a heading"
                       :args '((:name token :type "text" :required t)))
    (jetpacs-defaction "detail.save" #'glasspane-detail--on-save
                       :doc "Replace the subtree with the editor value")
    (jetpacs-defaction "detail.planning.edit"
                       #'glasspane-detail--on-planning-edit
                       :doc "Open the foundation SCHEDULED/DEADLINE editor")
    (jetpacs-defaction "detail.tags.edit" #'glasspane-detail--on-tags-edit
                       :doc "Open the grouped local-tag picker for a heading"
                       :args '((:name token :type "text" :required t)))
    (jetpacs-defaction "heading.todo-set" #'glasspane-detail--on-todo-set
                       :doc "Set a heading's TODO state; empty clears")
    (jetpacs-defaction "heading.todo-cycle"
                       #'glasspane-detail--on-todo-cycle
                       :doc "Cycle a heading through the TODO sequence")
    (jetpacs-defaction "heading.schedule" #'glasspane-detail--on-schedule
                       :doc "Schedule: :when relative, :value date, :clear")
    (jetpacs-defaction "heading.priority" #'glasspane-detail--on-priority
                       :doc "Set a heading's priority; empty clears")
    (jetpacs-defaction "heading.tags" #'glasspane-detail--on-tags
                       :doc "Replace a heading's local tags")
    (jetpacs-defaction "heading.refile" #'glasspane-detail--on-refile
                       :doc "Refile the subtree via a bridged picker")
    (jetpacs-defaction "heading.add-note" #'glasspane-detail--on-add-note
                       :doc "Add a logbook note via a bridged prompt")
    (jetpacs-defaction "heading.delete" #'glasspane-detail--on-delete
                       :doc "Delete the subtree (device-confirmed)")
    (jetpacs-defaction "heading.duplicate"
                       #'glasspane-detail--on-duplicate
                       :doc "Duplicate the subtree after itself")
    (jetpacs-defaction "heading.prop-set" #'glasspane-detail--on-prop-set
                       :doc "Set a property; empty value removes")
    (jetpacs-defaction "heading.prop-add" #'glasspane-detail--on-prop-add
                       :doc "Add a property via a bridged key prompt")
    (jetpacs-defaction "heading.props.show"
                       #'glasspane-detail--on-props-show
                       :doc "Open the sub-heading properties dialog")
    (jetpacs-defaction "heading.clock-in" #'glasspane-detail--on-clock-in
                       :doc "Clock in at the heading")
    (jetpacs-defaction "org.link.open" #'glasspane-detail--on-link-open
                       :doc "Open an org link Emacs-side")
    (jetpacs-defaction "files.properties.show"
                       #'glasspane-detail--on-file-props-show
                       :doc "Open the file keyword editor dialog")
    (jetpacs-defaction "files.properties.save"
                       #'glasspane-detail--on-file-props-save
                       :doc "Write the captured file keywords"))
  ;; A distinct id composes with the stock Org adapter: action lists append,
  ;; while omitted single-value slots leave its body/toolbar/FAB untouched.
  (jetpacs-editor-register
   'glasspane-org
   :predicate #'glasspane-detail--org-file-p
   :actions #'glasspane-detail--editor-actions
   :after-save #'glasspane-org-vulpea-refresh-file))

(defun glasspane-detail-unregister ()
  "Drop the detail verbs, editor adapter, and any live dialog."
  (dolist (name glasspane-detail--verbs)
    (jetpacs-undefaction name))
  (jetpacs-editor-unregister 'glasspane-org)
  (glasspane-detail--dialog-close))

(provide 'glasspane-detail)
;;; glasspane-detail.el ends here
