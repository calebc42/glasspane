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
;;   (jetpacs-org-dialogs.el:385-745,1165-1169).  The app keeps ONE
;;   delegation verb, `detail.planning.edit', which seeds the
;;   foundation timestamp dialog for SCHEDULED/DEADLINE; Archive rides
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
(require 'jetpacs-dialog)
(require 'jetpacs-editor)
(require 'jetpacs-org-toolbar)
(require 'jetpacs-org-dialogs)
(require 'glasspane-org)
(require 'glasspane-ui)
(require 'jetpacs-org-settings)      ; the shared tag vocabulary

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

;;;; Shared chip rails (the detail metadata block; views reuse the verbs)

(defun glasspane-ui--todo-chips (current keywords token)
  "A single-line chip rail for KEYWORDS with CURRENT selected.
Tapping the active chip clears the state (`:state' \"\").  Long
sequences pan sideways rather than wrapping into a stack."
  (apply #'jetpacs-row
         (append
          (mapcar (lambda (kw)
                    (jetpacs-chip kw
                                  :selected (jetpacs-bool (equal kw current))
                                  :on-tap (jetpacs-action
                                           "heading.todo-set"
                                           :args (list :state
                                                       (if (equal kw current)
                                                           "" kw)
                                                       :token token))))
                  keywords)
          (list :scroll t :spacing 4))))

(defun glasspane-ui--priority-chips (current token)
  "A row of priority chips with CURRENT selected; the active chip clears."
  (let* ((hi (or (bound-and-true-p org-priority-highest) ?A))
         (lo (or (bound-and-true-p org-priority-lowest) ?C))
         (levels (and (integerp hi) (integerp lo) (<= hi lo)
                      (mapcar #'char-to-string (number-sequence hi lo)))))
    (when levels
      (apply #'jetpacs-flow-row
             (append
              (mapcar (lambda (p)
                        (jetpacs-chip p
                                      :selected (jetpacs-bool (equal p current))
                                      :on-tap (jetpacs-action
                                               "heading.priority"
                                               :args (list :value
                                                           (if (equal p current)
                                                               "" p)
                                                           :token token))))
                      levels)
              (list :spacing 4))))))

;;;; Shared cards (agenda G5 and search G6 render through these)
;;
;; Item alists carry a `token' the LIST's builder minted into its own
;; per-screen set (S5) — one bulk `ebp-org-ref-tokens' per render, so a
;; per-card mint would sweep its siblings.  `archive-token', when
;; present, was minted under `jetpacs-org-dialogs-owner' so the base
;; `jetpacs.org.archive' verb can resolve it; without one the card just
;; has no archive swipe.

(defun glasspane-detail-agenda-card (it)
  "A detail-rich agenda card for item IT.
Leading time (or a type icon), priority-prefixed headline (done titles
degrade to on_surface_variant — no strike span, FOUNDATION-GAPS #7),
a todo/type/file caption, tag chips, and the tap/long-tap/swipe wiring."
  (let* ((headline (or (alist-get 'headline it) "Untitled"))
         (todo (alist-get 'todo it))
         ;; Normalized "HH:MM" — the raw property is a time-grid string
         ;; like " 9:15......".
         (time (glasspane-org-item-hm (alist-get 'time it)))
         (type (alist-get 'type it))
         (file (alist-get 'file it))
         (priority (alist-get 'priority it))
         (tags (append (alist-get 'tags it) nil))
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
                                  :font-weight "bold" :color "#F57C00"))
                  (jetpacs-span headline
                                :color (and done "on_surface_variant"))))))
         (middle
          (apply #'jetpacs-column
                 (delq nil
                       (list
                        headline-node
                        (unless (string-empty-p caption)
                          (jetpacs-text caption :style "caption"))
                        (glasspane-agenda-card-date-row it)
                        (when tags
                          (apply #'jetpacs-flow-row
                                 (mapcar
                                  (lambda (tg)
                                    (jetpacs-assist-chip
                                     tg :on-tap (jetpacs-action
                                                 "search.by-tag"
                                                 :args (list :tag tg))))
                                  tags))))))))
    (jetpacs-card
     (list (apply #'jetpacs-row
                  (delq nil
                        (list lead
                              (jetpacs-with-attrs (jetpacs-box middle)
                                                  :weight 1)))))
     :on-tap (and token (jetpacs-action "heading.tap"
                                        :args (list :token token)))
     :on-long-tap (and token (jetpacs-action "heading.menu"
                                             :args (list :token token)))
     :swipe-start (and token
                       (jetpacs-swipe "Cycle" :icon "check" :color "#4CAF50"
                                      :on-trigger
                                      (jetpacs-action "heading.todo-cycle"
                                                      :args (list :token token))))
     :swipe-end (and archive-token
                     (jetpacs-swipe "Archive" :icon "archive" :color "#E53935"
                                    :on-trigger
                                    (jetpacs-action
                                     "jetpacs.org.archive"
                                     :args (list :token archive-token)
                                     :confirm "Archive this subtree?"))))))

(defun glasspane-detail-result-card (it)
  "Render a search/heading item IT to a tappable card with tag chips."
  (let* ((headline (or (alist-get 'headline it) "?"))
         (todo (alist-get 'todo it))
         (file (alist-get 'file it))
         (tags (append (alist-get 'tags it) nil))
         (token (alist-get 'token it))
         (caption (string-join
                   (delq nil (list todo
                                   (when file (file-name-nondirectory file))))
                   "  ·  "))
         (children (delq nil
                         (list
                          (jetpacs-text headline :style "body")
                          (unless (string-empty-p caption)
                            (jetpacs-text caption :style "caption"))
                          (when tags
                            (apply #'jetpacs-flow-row
                                   (mapcar
                                    (lambda (tg)
                                      (jetpacs-assist-chip
                                       tg :on-tap (jetpacs-action
                                                   "search.by-tag"
                                                   :args (list :tag tg))))
                                    tags)))))))
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
                            (jetpacs-card
                             (list (jetpacs-text
                                    (or (alist-get 'headline r) "?")
                                    :style "body"))
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
                  (comps (org-heading-components)))
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
                   :tags (org-get-tags)
                   :local-tags (ignore-errors (org-get-tags pos t))
                   :scheduled (org-entry-get pos "SCHEDULED")
                   :deadline (org-entry-get pos "DEADLINE")
                   :keywords (or org-todo-keywords-1 '("TODO" "DONE"))
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

(defun glasspane-ui--detail-copy-link-item (ref)
  "The Copy Link chip for REF, or nil when the ref can't resolve.
An id link when the heading already has an :ID:, a file::*headline
link otherwise — built at render time so the copy itself is
companion-local (`clipboard.copy') and works offline."
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
                                      (buffer-file-name) headline headline))))
                 (jetpacs-button "Copy link" (jetpacs-clipboard-copy link)
                                 :icon "content_copy" :variant "text"))))
          (set-marker marker nil)))
    (error nil)))

(defun glasspane-ui--detail-copy-text-item (ref)
  "The Copy Text chip for REF: the whole subtree onto the clipboard."
  (when-let* ((text (glasspane-ui--detail-subtree-text ref)))
    (jetpacs-button "Copy text" (jetpacs-clipboard-copy text)
                    :icon "copy_all" :variant "text")))

(defun glasspane-ui--detail-share-item (ref)
  "The Share chip for REF: the whole subtree through the share sheet."
  (when-let* ((text (glasspane-ui--detail-subtree-text ref)))
    (jetpacs-button "Share"
                    (jetpacs-share text :title (plist-get ref :headline))
                    :icon "share" :variant "text")))

(defun glasspane-detail--date-stamp (ts)
  "A date-stamp node for org timestamp string TS, or nil."
  (when-let* ((date (ebp-org-ts-date ts)))
    (jetpacs-date-stamp :day (string-to-number (substring date 8 10))
                        :month-index (string-to-number (substring date 5 7))
                        :year (string-to-number (substring date 0 4))
                        :time (ebp-org-ts-time ts))))

(defun glasspane-ui--render-logbook-entry (entry)
  "One logbook ENTRY (a plist from `ebp-org-logbook-entries') as a row."
  (pcase (plist-get entry :type)
    ('clock
     (jetpacs-row
      (jetpacs-icon "timer" :color "primary")
      (jetpacs-column
       (jetpacs-text (if (plist-get entry :active)
                         (format "Started %s" (plist-get entry :start))
                       (ebp-org-format-clock-time (plist-get entry :start)
                                                  (plist-get entry :end)))
                     :style "body" :font-weight "bold")
       (jetpacs-text (or (plist-get entry :duration) "") :style "caption")
       :spacing 2)
      :spacing 12))
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

(defun glasspane-detail--logbook-section (entries key)
  "The Logbook collapsible for ENTRIES grouped by type, or nil."
  (when entries
    (let ((notes (seq-filter (lambda (e) (eq (plist-get e :type) 'note))
                             entries))
          (states (seq-filter (lambda (e) (eq (plist-get e :type) 'state))
                              entries))
          (clocks (seq-filter (lambda (e) (eq (plist-get e :type) 'clock))
                              entries)))
      (apply #'jetpacs-collapsible
             (jetpacs-wire-id "gp-detail-logbook" key)
             (jetpacs-text (format "Logbook (%d)" (length entries))
                           :style "label")
             (append
              (delq nil
                    (list
                     (glasspane-detail--logbook-group
                      "Notes" notes (concat key "/notes") nil)
                     (glasspane-detail--logbook-group
                      "State changes" states (concat key "/states") t)
                     (glasspane-detail--logbook-group
                      "Clocks" clocks (concat key "/clocks") t)))
              (list :collapsed t))))))

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

(defun glasspane-ui--properties-section (props token pos key &optional buf)
  "The Properties collapsible: KEY → VALUE rows plus an + Add button.
Always present (even with no properties yet) so + Add is reachable."
  (jetpacs-collapsible
   (jetpacs-wire-id "gp-detail-props" key)
   (jetpacs-text (if props (format "Properties (%d)" (length props))
                   "Properties")
                 :style "label")
   (delq nil
         (append
          (mapcar (lambda (kv)
                    (glasspane-ui--property-row
                     (car kv) (or (cdr kv) "") token pos
                     (and buf (glasspane-detail--allowed-values
                               buf pos (car kv)))))
                  props)
          (list
           (when props
             (jetpacs-text "Submit an empty value to remove a property."
                           :style "caption"))
           (jetpacs-row
            (jetpacs-spacer :weight 1)
            (jetpacs-button "+ Add property"
                            (jetpacs-action "heading.prop-add"
                                            :args (list :token token))
                            :variant "outlined")))))
   :collapsed t))

(defun glasspane-detail--scheduling-section (info main key)
  "The Scheduling collapsible — expanded when any date is set.
Direct arms only: quick chips and the date picker ride
`heading.schedule' with computed args; time, repeater and the whole
deadline edit delegate to the foundation timestamp dialog through
`detail.planning.edit' (the G4 dedup decision)."
  (let* ((scheduled (plist-get info :scheduled))
         (deadline (plist-get info :deadline))
         (sdate (ebp-org-ts-date scheduled))
         (ddate (ebp-org-ts-date deadline))
         (chip (lambda (label when)
                 (jetpacs-button label
                                 (jetpacs-action "heading.schedule"
                                                 :args (list :when when
                                                             :token main))
                                 :variant "text"))))
    (jetpacs-collapsible
     (jetpacs-wire-id "gp-detail-sched" key)
     (jetpacs-text "Scheduling" :style "label")
     (list
      (jetpacs-row
       (or (glasspane-detail--date-stamp scheduled)
           (jetpacs-spacer :width 0))
       (jetpacs-with-attrs
        (apply #'jetpacs-column
               (delq nil
                     (list
                      (jetpacs-text "Scheduled" :style "label")
                      (unless sdate
                        (jetpacs-text "Not scheduled" :style "caption"))
                      (when-let* ((rep (ebp-org-ts-repeater scheduled)))
                        (jetpacs-text (concat "Repeats " rep)
                                      :style "caption"))
                      (jetpacs-flow-row
                       (jetpacs-date-button "Set date"
                                            (jetpacs-action
                                             "heading.schedule"
                                             :args (list :token main))
                                            :value sdate)
                       (funcall chip "Today" "+0d")
                       (funcall chip "+1d" "+1d")
                       (funcall chip "+1w" "+1w")
                       (jetpacs-button "Clear"
                                       (jetpacs-action
                                        "heading.schedule"
                                        :args (list :clear t :token main))
                                       :variant "text")
                       (jetpacs-button "More…"
                                       (jetpacs-action
                                        "detail.planning.edit"
                                        :args (list :token main
                                                    :type "SCHEDULED"))
                                       :variant "text")))))
        :weight 1))
      (jetpacs-divider)
      (jetpacs-row
       (or (glasspane-detail--date-stamp deadline)
           (jetpacs-spacer :width 0))
       (jetpacs-with-attrs
        (apply #'jetpacs-column
               (delq nil
                     (list
                      (jetpacs-text "Deadline" :style "label")
                      (unless ddate
                        (jetpacs-text "No deadline" :style "caption"))
                      (when-let* ((rep (ebp-org-ts-repeater deadline)))
                        (jetpacs-text (concat "Repeats " rep)
                                      :style "caption"))
                      (jetpacs-flow-row
                       (jetpacs-button "Edit…"
                                       (jetpacs-action
                                        "detail.planning.edit"
                                        :args (list :token main
                                                    :type "DEADLINE"))
                                       :variant "text")))))
        :weight 1)))
     :collapsed (jetpacs-bool (not (or sdate ddate))))))

(defun glasspane-detail--tags-section (info main key)
  "The Tags collapsible: the editable enum plus the inherited chips."
  (let* ((tags (plist-get info :tags))
         (local (cl-remove-duplicates (or (plist-get info :local-tags) tags)
                                      :test #'equal :from-end t))
         (inherited (seq-difference tags local))
         (available (cl-remove-duplicates
                     (append local (jetpacs-org-settings-tag-options))
                     :test #'equal :from-end t)))
    (jetpacs-collapsible
     (jetpacs-wire-id "gp-detail-tags-fold" key)
     (jetpacs-text (if tags (format "Tags (%d)" (length tags)) "Tags")
                   :style "label")
     (delq nil
           (list
            (jetpacs-enum-list (jetpacs-wire-id "gp-detail-tags" key)
                               (mapcar (lambda (tg)
                                         (jetpacs-enum-option tg tg))
                                       available)
                               :value local :multi-select t :allow-add t
                               :on-change (jetpacs-action
                                           "heading.tags"
                                           :args (list :token main)))
            (when inherited
              (jetpacs-column
               (jetpacs-text "Inherited" :style "caption")
               (apply #'jetpacs-flow-row
                      (mapcar #'jetpacs-assist-chip inherited))
               :spacing 4))))
     :collapsed (jetpacs-bool (null tags)))))

(defun glasspane-detail--breadcrumbs (info tokens)
  "The breadcrumb rail: the file, then each ancestor heading.
Every chip taps up to that level, so climbing out of a deep subtree
never detours through the file picker."
  (let ((file (plist-get info :file)))
    (apply #'jetpacs-row
           (append
            (list (if file
                      (jetpacs-assist-chip
                       (file-name-nondirectory file)
                       :icon "description"
                       :on-tap (jetpacs-action "jetpacs.files.open"
                                               :args (list :path file)))
                    (jetpacs-text "?" :style "caption")))
            (cl-mapcan (lambda (anc tok)
                         (list (jetpacs-icon "chevron_right" :size 16)
                               (jetpacs-assist-chip
                                (car anc)
                                :on-tap (and tok
                                             (jetpacs-action
                                              "heading.tap"
                                              :args (list :token tok))))))
                       (plist-get info :ancestors)
                       (plist-get tokens :ancestors))
            (list :scroll t :align "center" :spacing 4)))))

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
                   ;; the moment a second caller exists.
                   (glasspane-org-reader-subtree file pos t "detail-subtree"))
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

(defun glasspane-ui--detail-body (info tokens)
  "The detail body: reader metadata + foldable children, or the editor."
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
      (apply #'jetpacs-lazy-column
             (append
              (delq nil
                    (list
                     (glasspane-detail--breadcrumbs info tokens)
                     (jetpacs-text (or (plist-get info :headline) "")
                                   :style "title")
                     (glasspane-ui--todo-chips (plist-get info :todo)
                                               (plist-get info :keywords)
                                               main)
                     (glasspane-ui--priority-chips (plist-get info :priority)
                                                   main)
                     (jetpacs-divider)
                     (glasspane-detail--scheduling-section info main key)
                     (glasspane-detail--tags-section info main key)
                     (glasspane-detail--logbook-section
                      (plist-get info :logbook) key)
                     (glasspane-ui--properties-section
                      (plist-get info :props) main pos key buf)
                     (jetpacs-divider)))
              ;; Reader: body and child headings.  Properties are shown
              ;; above (and for sub-headings through the overflow menu's
              ;; dialog), so no inline drawers here.
              (glasspane-detail--reader-nodes info)
              (list :spacing 8))))))

(defun glasspane-ui--detail-body-with-notes (info tokens)
  "The detail body plus every registered app layer's sections.
The sections splice INTO the lazy_column body (nesting another scroll
container would break Compose) and wrap otherwise."
  (let ((body (glasspane-ui--detail-body info tokens))
        (extras (cl-loop for fn in glasspane-ui-detail-nodes-functions
                         append (condition-case nil
                                    (funcall fn (plist-get info :ref))
                                  (error nil)))))
    (cond
     ((null extras) body)
     ((equal (plist-get body :t) "lazy_column")
      (let ((copy (copy-sequence body)))
        (plist-put copy :children
                   (vconcat (plist-get body :children) extras))))
     (t (apply #'jetpacs-column body extras)))))

(defun glasspane-detail--top-actions (info tokens)
  "The detail top-bar actions: clock toggle, read/edit, file properties."
  (let ((file (plist-get info :file)))
    (delq nil
          (list
           (if (plist-get info :clocked-in)
               (jetpacs-icon-button "timer_off"
                                    (jetpacs-action "org.clock.out")
                                    :content-description "Clock out")
             (jetpacs-icon-button "timer"
                                  (jetpacs-action
                                   "heading.clock-in"
                                   :args (list :token
                                               (plist-get tokens :main)))
                                  :content-description "Clock in"))
           (jetpacs-icon-button
            (if glasspane-ui--detail-read-mode "edit" "visibility")
            (jetpacs-action "detail.toggle-read")
            :content-description
            (if glasspane-ui--detail-read-mode "Edit" "Read"))
           (when (glasspane-detail--org-file-p file)
             (jetpacs-icon-button "tune"
                                  (jetpacs-action
                                   "files.properties.show"
                                   :args (list :file file))
                                  :content-description "File properties"))))))

(defun glasspane-detail--bottom-bar (tokens)
  "Prev/Log-note/Next.  Prev and Next flank the bar and appear only
when a same-level sibling exists."
  (let ((main (plist-get tokens :main))
        (prev (plist-get tokens :prev))
        (next (plist-get tokens :next)))
    (apply #'jetpacs-row
           (append
            (delq nil
                  (list
                   (when prev
                     (jetpacs-button "Prev"
                                     (jetpacs-action "heading.tap"
                                                     :args (list :token prev))
                                     :icon "chevron_left" :variant "text"))
                   (jetpacs-button "Log note"
                                   (jetpacs-action "heading.add-note"
                                                   :args (list :token main))
                                   :icon "edit_note" :variant "text")
                   (when next
                     (jetpacs-button "Next"
                                     (jetpacs-action "heading.tap"
                                                     :args (list :token next))
                                     :icon "chevron_right" :variant "text"))))
            (list :arrange "space_between" :align "center")))))

(defun glasspane-detail--floating-toolbar (info tokens)
  "The curated heading actions rail, plus app-layer extras."
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
                      :icon "archive" :variant "text"))
                   (glasspane-ui--detail-copy-link-item ref)
                   (glasspane-ui--detail-copy-text-item ref)
                   (glasspane-ui--detail-share-item ref)
                   ;; Delete is unrecoverable — Archive is the kept
                   ;; path — so the device confirm gates it (14.1).
                   (jetpacs-button
                    "Delete"
                    (jetpacs-action "heading.delete"
                                    :args (list :token main)
                                    :confirm "Delete this heading and its subtree?")
                    :icon "delete" :variant "text")))
            (glasspane-ui--detail-toolbar-extras ref)
            (list :scroll t)))))

(defun glasspane-detail--screen (ref back)
  "The pushed detail screen for REF.
A ref that stopped resolving degrades to a go-back placeholder — the
builder runs on every stack rebuild, long after the heading may have
moved (SPEC 14.5: re-present, never guess)."
  (condition-case err
      (let* ((info (glasspane-ui--detail-meta ref))
             (tokens (glasspane-detail--tokens info)))
        (jetpacs-chrome-screen
         "Detail"
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
          (setq glasspane-ui--detail-read-mode t)
          (glasspane-detail--push-screen
           (or (plist-get params :surface)
               (jetpacs-shell-surface-for "glasspane"))
           ref)
          'accepted)))))

(defun glasspane-detail--on-toggle-read (_args params)
  "Flip the reader/editor mode; the builder re-reads the flag."
  (setq glasspane-ui--detail-read-mode (not glasspane-ui--detail-read-mode))
  (jetpacs-app-defer-refresh params)
  'accepted)

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
  "Schedule the heading: `:when' relative, `:value' from the picker,
or `:clear'.  No prompting arm — the empty-args tap is a build-time
bug, not a user path (the picker flows are the foundation dialog's)."
  (let ((clearp (let ((c (plist-get args :clear)))
                  (and c (not (eq c :json-false)))))
        (date (or (plist-get args :when) (plist-get args :value))))
    (cond
     (clearp
      (let ((status (glasspane-ui-at-ref
                     args (lambda () (org-schedule '(4))) t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify "Schedule cleared"
                                (plist-get params :surface))
          (jetpacs-app-defer-refresh params))
        status))
     ((and (stringp date) (not (string-empty-p date)))
      (let ((status (glasspane-ui-at-ref
                     args (lambda () (org-schedule nil date)) t)))
        (when (eq status 'accepted)
          (jetpacs-shell-notify (format "Scheduled %s" date)
                                (plist-get params :surface))
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
                   (list :scroll t :spacing 8)))
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
          :scroll t :spacing 8)
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
    "detail.toggle-read"
    "detail.save"
    "detail.planning.edit"
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
    (jetpacs-defaction "detail.toggle-read"
                       #'glasspane-detail--on-toggle-read
                       :doc "Flip the detail reader/editor mode")
    (jetpacs-defaction "detail.save" #'glasspane-detail--on-save
                       :doc "Replace the subtree with the editor value")
    (jetpacs-defaction "detail.planning.edit"
                       #'glasspane-detail--on-planning-edit
                       :doc "Open the foundation SCHEDULED/DEADLINE editor")
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
