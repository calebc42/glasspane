;;; glasspane-ui.el --- Glasspane settings, shared UI state, the at-ref funnel -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The keystone rung (docs/PLAN-glasspane-app.md, G3): the app's
;; settings surface, the shared view state the later rungs read, and
;; `glasspane-ui-at-ref' — the token→resolve→classify funnel every
;; heading mutation in G4+ rides.
;;
;; It also holds the authoritative PARA destination table and the capture FAB
;; descriptor PA-3a contributes to Jetpacs' app registry.  These live beside
;; shared state rather than in the entry so the entry keeps its single job —
;; identity and composition metadata.
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
;;   settings view is now a Settings hub entry plus a pushed
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
(require 'jetpacs-material3)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-settings)
(require 'jetpacs-org-settings)
(require 'jetpacs-dates)              ; locale-stable date arithmetic
(require 'glasspane-org)

;; v1 hard-required glasspane-magit (it lives outside the app
;; directory); its port is out of the plan's scope, so the require
;; goes soft — nothing in this file calls into it.
(require 'glasspane-magit nil t)

(defcustom glasspane-org-custom-agendas nil
  "Alist of saved searches (NAME . QUERY) in the ebp-org grammar."
  :type '(alist :key-type string :value-type string)
  :group 'jetpacs)

(defcustom glasspane-area-tag-group "Area"
  "Name of the non-exclusive Org tag group whose members are PARA Areas.
An Area is a tag, never a file: anything carrying a member tag locally,
by inheritance, or through `#+FILETAGS' belongs to that Area.  The group
is persisted in `org-tag-persistent-alist' by the Area Tags settings row
so a file's own `#+TAGS' line never hides it."
  :type 'string
  :group 'jetpacs)

(defcustom glasspane-area-icons nil
  "Alist mapping PARA Area tag names to Material icon identifiers.
Keys are the exact members of `glasspane-area-tag-group'.  Values use the
bundled Material icon names in snake_case, such as \"directions_car\" or
\"health_and_safety\"; a trailing \"_filled\" requests the filled variant.
Missing, empty, or malformed values render the safe \"category\" default.
An identifier absent from the Companion's bundled Material catalog renders
its harmless help-outline placeholder.  This is presentation metadata only:
it never changes Org tags, Area membership, or a vault file."
  :type '(alist :key-type (string :tag "Area tag")
                :value-type (string :tag "Material icon"))
  :group 'jetpacs)

(defconst glasspane-ui--default-area-icon "category"
  "Material icon used when an Area has no valid explicit preference.")

(defconst glasspane-ui--area-icon-suggestions
  '(("Home" . "home")
    ("Work" . "work")
    ("Health" . "health_and_safety")
    ("Learning" . "school")
    ("Travel" . "flight")
    ("Money" . "payments")
    ("Car" . "directions_car")
    ("Digital" . "devices"))
  "Curated Material icon choices shown before the free-form editor.")

(defun glasspane-ui--normalize-material-icon-name (value)
  "Return VALUE in the Material renderer's canonical snake_case spelling.
Leading/trailing whitespace is dropped, ASCII case is folded, and internal
spaces or hyphens become underscores.  Non-string values return nil."
  (when (stringp value)
    (replace-regexp-in-string
     "[-[:space:]]+" "_" (downcase (string-trim value)))))

(defun glasspane-ui--material-icon-name-p (value)
  "Return non-nil when VALUE is a safe Material icon identifier.
This proves wire shape, not catalog membership; an unavailable but valid name
is deliberately left for the Companion's harmless placeholder behavior."
  (and (stringp value)
       (<= (length value) 128)
       (jetpacs-identifier-p value)
       (string-match-p "\\`[a-z][a-z0-9_]*\\'" value)))

(defun glasspane-ui--configured-area-icon (area)
  "Return AREA's normalized, valid configured icon, or nil."
  (let ((icon (glasspane-ui--normalize-material-icon-name
               (alist-get area glasspane-area-icons nil nil #'equal))))
    (and (glasspane-ui--material-icon-name-p icon) icon)))

(defun glasspane-area-icon (area)
  "Return AREA's configured Material icon or the safe category default.
AREA is an exact native Org tag-group member.  Invalid direct Custom values
degrade locally rather than making an Areas, Projects, or Archive builder fail."
  (or (and (stringp area) (glasspane-ui--configured-area-icon area))
      glasspane-ui--default-area-icon))

(defun glasspane-ui-tag-chips (tags &optional areas arrange)
  "Build wrapping TAGS, or nil when there are none.
With AREAS, elevate the chips and add Area icons.  ARRANGE is the flow
row's arrangement; Area chips default to \"end\" so they hug the trailing
edge beside a headline, and a caller stacking them under the headline
passes \"start\"."
  (when tags
    (apply #'jetpacs-flow-row
           (append
            (mapcar
             (lambda (tag)
               (jetpacs-material3-assist-chip
                tag :icon (and areas (glasspane-area-icon tag))
                :variant (and areas "elevated")
                :on-tap (jetpacs-action
                         "search.by-tag" :args (list :tag tag))))
             tags)
            (when (or arrange areas)
              (list :arrange (or arrange "end")))))))

(defun glasspane-ui-card-meta (item today &optional done)
  "ITEM's one-line caption as a rich text: state, dates in words, file.
Scheduled and deadline stamps read through `glasspane-ui-human-date' and
carry its urgency color; DONE mutes them.  TODAY is the only clock.
Nil when there is nothing to say."
  (let* ((todo (alist-get 'todo item))
         (file (alist-get 'file item))
         (dates
          (or
           (delq nil
                 (mapcar
                  (lambda (spec)
                    (when-let* ((stamp (alist-get (car spec) item))
                                (h (glasspane-ui-human-date
                                    stamp today :done done :kind (cdr spec))))
                      (jetpacs-span (plist-get h :label)
                                    :color (plist-get h :color))))
                  '((scheduled . scheduled) (deadline . deadline))))
           ;; An agenda item carries no stamps, only the agenda's type,
           ;; stamp date and time: say the same thing from those.
           (when-let* ((date (alist-get 'date item))
                       ((jetpacs-dates-valid-p date))
                       (type (or (alist-get 'type item) "")))
             (let* ((hm (jetpacs-org-reminders-item-hm (alist-get 'time item)))
                    (stamp (format "<%s%s>" date
                                   (if (and (stringp hm) (not (string-empty-p hm)))
                                       (concat " " hm)
                                     "")))
                    (kind (cond ((string-match-p "deadline" type) 'deadline)
                                ((string-match-p "scheduled" type) 'scheduled)))
                    (h (and kind (glasspane-ui-human-date
                                  stamp today :done done :kind kind))))
               (cond
                (h (list (jetpacs-span (plist-get h :label)
                                       :color (plist-get h :color))))
                ((glasspane-ui-day-words date today)
                 (list (jetpacs-span (glasspane-ui-day-words date today)
                                     :color "outline"))))))))
         (groups
          (append
           (when (and (stringp todo) (not (string-empty-p todo)))
             (list (list (jetpacs-span todo :font-weight "bold"
                                       :color (if done "outline" "primary")))))
           (mapcar #'list dates)
           (when (stringp file)
             (list (list (jetpacs-span (file-name-nondirectory file)
                                       :color "outline")))))))
    (glasspane-ui-meta-line groups)))

(defun glasspane-ui-chip-line (areas tags &optional arrange)
  "One wrapping chip row: AREAS elevated with their icons, then TAGS flat.
Every chip searches by its tag.  ARRANGE defaults to \"start\".  Nil when
both are empty.  The elevated/flat contrast is what tells an Area from an
ordinary Org tag."
  (let ((chips
         (append
          (mapcar (lambda (tag)
                    (jetpacs-material3-assist-chip
                     tag :icon (glasspane-area-icon tag) :variant "elevated"
                     :on-tap (jetpacs-action "search.by-tag"
                                             :args (list :tag tag))))
                  areas)
          (mapcar (lambda (tag)
                    (jetpacs-material3-assist-chip
                     tag :on-tap (jetpacs-action "search.by-tag"
                                                 :args (list :tag tag))))
                  tags))))
    (when chips
      (apply #'jetpacs-flow-row
             (append chips (list :spacing 4 :run-spacing 4
                                 :arrange (or arrange "start")))))))

(defun glasspane-ui-meta-line (groups &optional style)
  "One caption line of GROUPS, each a list of spans, joined by dots.
Empty groups drop out; nil when nothing is left.  STYLE defaults to
\"caption\"."
  (let ((groups (delq nil groups))
        joined)
    (dolist (group groups)
      (when joined (push (jetpacs-span "  ·  " :color "outline") joined))
      (dolist (span group) (push span joined)))
    (when joined
      (jetpacs-rich-text (nreverse joined) :style (or style "caption")))))

(defconst glasspane-ui-chip-rail-padding 12
  "Inset, in dp, drawn inside a chip rail's scroll viewport.
It matches the 12dp content padding of the card lists the rails sit above,
so the first chip lines up with the first card while later chips scroll
under the window edge.")

(defun glasspane-ui-chip-rail (chips)
  "Build CHIPS as one horizontally scrolling line, or nil when there are none.
A rail never wraps.  On a compact window a wrapping flow row of workflow
states or Areas stacks into several lines before any content appears; one
scrolling line costs the same fixed height on every window size and keeps
each chip at its intrinsic width."
  (when chips
    (apply #'jetpacs-row
           (append chips
                   (list :scroll t :spacing 4
                         :content-padding glasspane-ui-chip-rail-padding)))))

(defvar glasspane-ui-narrow-container nil
  "Non-nil while building content for a narrow container on a wide window.
The list beside a heading pane is phone-width, so it lays out as one.")

(defun glasspane-ui-compact-width-p ()
  "Non-nil when content lays out for a compact width (a phone, SPEC 20.1.1).
True too inside a narrow container (`glasspane-ui-narrow-container').
Before any geometry report the class defaults to compact, so a first paint
lands in the phone layout and chrome re-pushes on the real class."
  (or glasspane-ui-narrow-container
      (equal (jetpacs-window-class :width) "compact")))

(defun glasspane-ui-wide-p ()
  "Non-nil when the window's width class is medium or expanded."
  (not (glasspane-ui-compact-width-p)))

(defconst glasspane-ui-edge-gap 16
  "Dp between a wide window's list and the navigation rail beside it.
The rail is lifted off the page, so cards flush against it read as one
block; the pane scaffold already keeps a gap on the list's other side.")

(defconst glasspane-ui-card-gap 8
  "Dp below each list card.
The design baseline tints filled cards off the page instead of
outlining them, so a stack of cards needs space to read as separate.")

(define-obsolete-variable-alias 'glasspane-ui-measure-dp
  'jetpacs-measure-dp "polish-navigation")

(defun glasspane-ui-measure (node)
  "NODE centered at `jetpacs-measure-dp' on a wide window (`jetpacs-measure').
A compact window, or a narrow container (`glasspane-ui-narrow-container'),
gets NODE unchanged: it is already narrower."
  (if glasspane-ui-narrow-container
      node
    (jetpacs-measure node)))

;;;; Two-pane selection (lists beside the heading page on wide windows)

(defvar glasspane-ui--pane-selection (make-hash-table :test #'equal)
  "Screen id -> the ebp-org ref its heading pane shows.
Emacs-side only: refs never reach the wire.  Agenda, Projects and every
Area drill keep their own selection.")

(defvar glasspane-ui-pane-current nil
  "While a pane screen builds, the ref of the heading its pane shows.
Cards compare against it to mark the selection.")

(defun glasspane-ui-pane-screen-p (id)
  "Whether screen ID lays its list beside a heading pane on wide windows."
  (and (stringp id)
       (or (member id '("glasspane-agenda" "glasspane-projects"))
           (string-prefix-p "area-" id))))

(defun glasspane-ui-pane-capable-p ()
  "Whether this window and Companion can show a list beside its heading."
  (and (glasspane-ui-wide-p) (jetpacs-node-advertised-p "pane_scaffold")))

(defun glasspane-ui-pane-top (surface)
  "SURFACE's top screen id when it is a pane screen on a pane-capable window."
  (let ((top (car (ignore-errors (jetpacs-chrome-stack surface)))))
    (and (glasspane-ui-pane-capable-p)
         (glasspane-ui-pane-screen-p top)
         top)))

(defun glasspane-ui-pane-selection (id)
  "The ref screen ID's pane shows, or nil."
  (gethash id glasspane-ui--pane-selection))

(defun glasspane-ui-pane-select (id ref)
  "Show REF in screen ID's pane; nil REF closes the pane."
  (if ref
      (puthash id ref glasspane-ui--pane-selection)
    (remhash id glasspane-ui--pane-selection)))

(defun glasspane-ui-pane-selected-p (item)
  "Whether ITEM is the heading the screen being built shows in its pane.
The heading's Org ID decides when both carry one; otherwise the truename
and the heading start.  An agenda item's own `pos' is its agenda marker,
which can sit below the heading, so the item's ref position is preferred."
  (when-let* ((cur glasspane-ui-pane-current))
    (let* ((ref (alist-get 'ref item))
           (id (plist-get ref :id))
           (file (or (plist-get ref :file) (alist-get 'file item)))
           (pos (or (plist-get ref :pos) (alist-get 'pos item))))
      (if (and id (plist-get cur :id))
          (equal id (plist-get cur :id))
        (and (stringp file) (equal pos (plist-get cur :pos))
             (equal (condition-case nil (file-truename file) (error file))
                    (condition-case nil (file-truename (plist-get cur :file))
                      (error (plist-get cur :file)))))))))

(defun glasspane-ui--on-pane-close (_args params)
  "Close the heading pane of the screen PARAMS' surface shows."
  (let* ((surface (glasspane-ui-surface params))
         (top (car (ignore-errors (jetpacs-chrome-stack surface)))))
    (if (not (glasspane-ui-pane-screen-p top))
        'stale
      (glasspane-ui-pane-select top nil)
      (jetpacs-chrome-defer-current-view-refresh surface)
      'accepted)))

(defun glasspane-ui-pane-close-action ()
  "The descriptor closing the open pane; surface-opening so Back honours it."
  (glasspane-ui-reopen-action "glasspane.pane.close"))

(defun glasspane-ui-item-areas (item)
  "Return ITEM's Area-group memberships, resolved at its source position.
Any resolution error degrades to no Areas rather than failing a screen."
  (condition-case nil
      (glasspane-org-item-tag-group-members item glasspane-area-tag-group)
    (error nil)))

(defun glasspane-ui-area-names (items)
  "Return the distinct Area memberships represented by ITEMS, sorted."
  (let (names)
    (dolist (item items)
      (dolist (area (glasspane-ui-item-areas item))
        (when (and (stringp area) (not (string-empty-p area)))
          (cl-pushnew area names :test #'equal))))
    (sort names #'string-lessp)))

(defun glasspane-ui-headline-with-areas (headline areas &optional stack)
  "Arrange HEADLINE (a node) with its elevated AREAS chips, as a node list.
On medium and expanded windows the chips share the headline's row and hug
the trailing edge; on a compact window, or when STACK is non-nil (a
narrow container such as a board column), they wrap start-aligned on the
line beneath so the title keeps the full width.  Without AREAS the list
is just HEADLINE.  Every card shares this so a heading's Areas read the
same on Agenda, Projects, Views, and Search."
  (cond
   ((null areas) (list headline))
   ((or stack (glasspane-ui-compact-width-p))
    (list headline (glasspane-ui-tag-chips areas t "start")))
   (t (list (jetpacs-row
             (jetpacs-with-attrs headline :weight 1)
             (jetpacs-with-attrs (glasspane-ui-tag-chips areas t) :weight 1)
             :fill t :align "center" :spacing 8)))))

(defun glasspane-ui-area-filter-rail (names selected action)
  "Build the single-select Area rail over NAMES with SELECTED active.
The leading **All Areas** chip dispatches ACTION without arguments; each
Area chip dispatches ACTION with its name as `:area'.  A SELECTED name
missing from NAMES is still offered, so the active filter stays visible.
Projects and Agenda share this rail so Areas read the same everywhere."
  (let ((names (if (and selected (not (member selected names)))
                   (append names (list selected))
                 names)))
    (glasspane-ui-chip-rail
     (cons
      (jetpacs-chip "All Areas"
                    :icon "category"
                    :selected (jetpacs-bool (null selected))
                    :on-tap (jetpacs-action action))
      (mapcar
       (lambda (area)
         (jetpacs-chip
          area
          :icon (glasspane-area-icon area)
          :selected (jetpacs-bool (equal selected area))
          :on-tap (jetpacs-action action :args (list :area area))))
       names)))))

;;;; Human planning text (the detail's pills and rows; cards may adopt it)

(defconst glasspane-ui--repeat-units
  '((?h . "hour") (?d . "day") (?w . "week") (?m . "month") (?y . "year"))
  "Org repeater unit letters and their singular English nouns.")

(defun glasspane-ui-repeat-words (cookie)
  "English words for org repeater COOKIE, or nil without one.
\"+1w\" reads \"weekly\" and \"+2w\" \"every 2 weeks\"; a \".+\" cookie
appends \" from done\" and a \"++\" cookie \" catch-up\", the two
restart rules Org distinguishes.  An unparsed cookie is shown as is."
  (when (stringp cookie)
    (if (string-match
         "\\`\\(\\.\\+\\|\\+\\+\\|\\+\\)\\([0-9]+\\)\\([hdwmy]\\)\\'" cookie)
        (let* ((kind (match-string 1 cookie))
               (n (string-to-number (match-string 2 cookie)))
               (unit (cdr (assq (aref (match-string 3 cookie) 0)
                                glasspane-ui--repeat-units)))
               (base (if (= n 1)
                         (pcase unit
                           ("hour" "hourly") ("day" "daily") ("week" "weekly")
                           ("month" "monthly") (_ "yearly"))
                       (format "every %d %ss" n unit))))
          (concat base (pcase kind (".+" " from done") ("++" " catch-up")
                              (_ ""))))
      (concat "repeats " cookie))))

(defun glasspane-ui--date-words (date today)
  "Relative or short words for ISO DATE seen from ISO TODAY.
Today, Tomorrow and Yesterday by name; the coming week by weekday; any
other date as \"Mon, Sep 21\", with the year appended when it differs."
  (let* ((delta (jetpacs-dates-delta date today))
         (y (string-to-number (substring date 0 4)))
         (m (string-to-number (substring date 5 7)))
         (d (string-to-number (substring date 8 10)))
         (weekday (jetpacs-dates-weekday date)))
    (cond ((= delta 0) "Today")
          ((= delta 1) "Tomorrow")
          ((= delta -1) "Yesterday")
          ((<= 2 delta 6) weekday)
          ((equal (substring date 0 4) (substring today 0 4))
           (format "%s, %s %d" (jetpacs-dates-weekday date t)
                   (jetpacs-dates-month-abbrev m) d))
          (t (format "%s %d, %d" (jetpacs-dates-month-abbrev m) d y)))))

(defun glasspane-ui--span-words (days unit-word)
  "\"N days\" or \"N weeks\" for a DAYS count; UNIT-WORD trails it."
  (if (< days 14)
      (format "%d day%s %s" days (if (= days 1) "" "s") unit-word)
    (let ((weeks (/ days 7)))
      (format "%d week%s %s" weeks (if (= weeks 1) "" "s") unit-word))))

(cl-defun glasspane-ui-human-date (ts today &key done (kind 'scheduled)
                                      (warn-days 14))
  "Describe org timestamp TS for a reader, seen from ISO TODAY.
KIND is `scheduled' or `deadline'; DONE says the heading is closed, so
nothing reads as overdue; WARN-DAYS is the deadline lead time that turns
the warning color on.  Returns nil without a real date, else a plist:
:label the short pill text (\"Tomorrow · 09:00 · weekly\", \"Due Friday\",
\"3 days overdue\"); :long the full sentence for a row subtitle;
:color the theme role carrying urgency; :date, :time (Org's hyphen form),
:repeat (the cookie) and :delta (days from today) for callers that
lay out their own text.  Pure: TODAY is the only clock."
  (when-let* ((date (ebp-org-ts-date ts))
              (delta (jetpacs-dates-delta date today)))
    (let* ((time (jetpacs-org-ts-time-range ts))
           (shown-time (and time (string-replace "-" "–" time)))
           (cookie (ebp-org-ts-repeater ts))
           (repeat (and cookie (glasspane-ui-repeat-words cookie)))
           (deadline (eq kind 'deadline))
           (overdue (and (not done) (< delta 0)))
           (words (glasspane-ui--date-words date today))
           (day (cond ((and overdue deadline)
                       (glasspane-ui--span-words (- delta) "overdue"))
                      ((and overdue (< delta -1))
                       (glasspane-ui--span-words (- delta) "ago"))
                      ((and deadline (not done))
                       (concat "Due " (if (member words '("Today" "Tomorrow"))
                                          (downcase words)
                                        words)))
                      (t words)))
           (color (cond (done "outline")
                        (deadline (cond ((<= delta 0) "error")
                                        ((<= delta warn-days) "warning")
                                        (t "on_surface")))
                        ((< delta 0) "warning")
                        ((= delta 0) "primary")
                        (t "on_surface")))
           (y (string-to-number (substring date 0 4)))
           (m (string-to-number (substring date 5 7)))
           (d (string-to-number (substring date 8 10)))
           (long (concat
                  (jetpacs-dates-weekday date)
                  (format ", %s %d, %d" (jetpacs-dates-month-abbrev m) d y)
                  (when shown-time (concat " at " shown-time))
                  (when repeat (concat " · repeats " repeat)))))
      (list :label (concat day
                           (when shown-time (concat " · " shown-time))
                           (when repeat (concat " · " repeat)))
            :long long
            :color color
            :date date :time time :repeat cookie :delta delta))))

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

;;;; PARA destinations, navigation, and capture FAB

(defun glasspane-ui-capture-fab (&optional _surface)
  "Return Glasspane's app-default capture FAB.
SURFACE is accepted for the `jetpacs-defapp' FAB-builder contract and is
otherwise unused.  Jetpacs injects this node only onto Glasspane-owned
screens.  The coupling to the upstream `jetpacs-org-capture' owner is the
verb string alone — an early tap is rejected by the action shim, never a
signal."
  ;; `note_add', not `add': the FAB rides Glasspane's Files guest too,
  ;; where a plain plus beside Files' own "+" read as the same action.
  (jetpacs-icon-button "note_add" (jetpacs-action "org.capture.show")
                       :content-description "Capture"
                       :variant "filled" :size "large"))

(defun glasspane-ui-top-actions ()
  "Return Glasspane's destination-level top-bar actions.
Search is an app navigation opinion, so Glasspane authors its placement while
the shared chrome remains unaware of the downstream destination."
  (list (jetpacs-icon-button "search" (jetpacs-action "search.open")
                             :content-description "Search")))

(defconst glasspane-ui-destinations
  '((:key "agenda" :label "Agenda" :icon "event"
     :subtitle "Today's schedule, deadlines, and the month grid"
     :verb "agenda.open" :badge glasspane-agenda-dock-badge :bar t
     :screen-prefix "view-")
    (:key "projects" :label "Projects" :icon "task_alt"
     :subtitle "Every TODO heading, grouped by file or Area"
     :verb "projects.open" :bar t)
    (:key "areas" :label "Areas" :icon "category"
     :subtitle "Members of the Area tag group, with their open work"
     :verb "areas.open" :bar t :screen-prefix "area-")
    (:key "resources" :label "Resources" :icon "topic"
     :subtitle "Every live file in the vault, by title and Area"
     :verb "resources.open" :bar t)
    (:key "review" :label "Review" :icon "school"
     :subtitle "Flashcards due today, and notes gone stale"
     :verb "review.open" :bar t)
    (:key "archive" :label "Archive" :icon "archive"
     :subtitle "Sibling .org_archive files, filterable by Area"
     :verb "archive.open" :bar nil))
  "Glasspane's authoritative PARA destinations, in navigation order.
ONE table feeds the host destination registry, the five-item primary bar,
and the host drawer projection.  `:bar' nil makes Archive a deep-linkable
drawer destination without spending a bar slot.  Each `:verb' is registered
by the sibling module that owns the screen; the coupling is the wire string
alone, so an early tap is rejected by the action shim rather than signalling.

Subtitles are STATIC on purpose.  Chrome rebuilds every screen on the
stack for every push, so a live count here would re-extract org on
every frame the user is anywhere in the app; the Agenda and Review
screens carry their own in-screen counts instead (FOUNDATION-GAPS #5).

No Notes row: glasspane-notes owns no screen of its own — its surfaces
are the detail view's backlinks/mentions sections and the Review
screen's stale-files half, both reached from rows that ARE here.")

(defun glasspane-ui-open-destination (route id builder &optional params)
  "Open Glasspane destination ROUTE as peer screen ID via BUILDER.
PARAMS is the originating action event.  Delegates to the generic
`jetpacs-app-open-destination' foundation helper."
  (jetpacs-app-open-destination "glasspane" route id builder params))

(defconst glasspane-ui-root-screen "glasspane-agenda"
  "The pinned root screen id: Agenda, the app's home destination.")

(defun glasspane-ui-destination-screen (route)
  "Return the peer screen id the destination ROUTE presents."
  (concat "glasspane-" route))

(defun glasspane-ui-surface (&optional params)
  "Return the surface PARAMS' event was tapped on, else the app's own."
  (or (plist-get params :surface) (jetpacs-shell-surface-for "glasspane")))

(defun glasspane-ui-push-child (params id builder)
  "Push drill screen ID via BUILDER above whatever PARAMS' surface shows.
A drill keeps its parent beneath it, unlike a destination switch, which
abandons the previous destination.  Deferred past the dispatch extent;
answers `accepted'."
  (jetpacs-chrome-push-screen-later (glasspane-ui-surface params) id builder)
  'accepted)

(defun glasspane-ui-peer-on-back ()
  "The system back gesture of a peer destination: return to the Agenda root.
A peer draws no arrow, and a scaffold with neither arrow nor `on_back'
lets the Companion finish the Activity, so every peer declares this."
  (jetpacs-view-switch glasspane-ui-root-screen))

(defun glasspane-ui-reopen-action (verb)
  "The Back descriptor that re-presents a screen through VERB on this surface.
The Companion's back gesture mirrors the arrow only for a view switch or a
remote action that opens a surface (ChromeBack.kt); a bare remote action
falls through to the system default and leaves the app.  So a reopen names
Glasspane's own surface, which also keeps it an explicit presentation."
  (jetpacs-shell-action-opening-surface
   verb (jetpacs-shell-surface-for "glasspane")))

(defun glasspane-ui-parent-back (back parent-id reopen)
  "BACK when it switches to PARENT-ID, else the REOPEN action.
Chrome hands a builder the switch to the screen directly beneath it, and a
bounded stack evicts the screen above the root once a drill goes a level
deeper.  A child whose parent was evicted would otherwise land on the root;
REOPEN (built with `glasspane-ui-reopen-action') re-presents the parent
instead, at the cost of one round trip."
  (if (and back (equal (plist-get back :view) parent-id)) back reopen))

(defun glasspane-ui-current-route ()
  "The destination key the app currently has selected, defaulting to agenda."
  (let ((route (bound-and-true-p jetpacs-apps--current-route)))
    (if (and (stringp route)
             (cl-find route glasspane-ui-destinations
                      :key (lambda (d) (plist-get d :key)) :test #'equal))
        route
      "agenda")))

(defun glasspane-ui-route-back (back)
  "BACK unless it skips the selected destination, then that destination.
A transient screen (Search, detail) is pushed above whatever destination
or drill was showing.  When the screen beneath it is the root while a
non-root destination is selected, the destination was evicted by the
stack bound and BACK would skip it; reopen it through its own verb."
  (let* ((route (glasspane-ui-current-route))
         (dest (cl-find route glasspane-ui-destinations
                        :key (lambda (d) (plist-get d :key)) :test #'equal)))
    (if (and back dest
             (not (equal route "agenda"))
             (equal (plist-get back :view) glasspane-ui-root-screen))
        (glasspane-ui-reopen-action (plist-get dest :verb))
      back)))

(defun glasspane-ui-refresh-action ()
  "The pull-to-refresh descriptor every destination screen carries."
  (jetpacs-action "glasspane.refresh"))

(defun glasspane-ui--on-refresh (_args params)
  "Pull-to-refresh: drop every Org memo, then re-render PARAMS' surface."
  (ebp-org-cache-invalidate)
  (jetpacs-app-defer-refresh params)
  'accepted)

(defun glasspane-ui-item-key (item &optional group)
  "A stable list key for heading ITEM, or nil when it has no identity.
Built from the file, position, agenda type, agenda day and stamp date,
so a heading the agenda lists twice (scheduled and due the same day), a
repeating task on several days, and a Project under two Areas (GROUP
names the bucket) keep distinct keys while the key survives a re-mint of
the item's token.  The Companion restores a lazy column's scroll
position by its children's keys.  Lists still pass their cards through
`glasspane-ui-dedupe-keys': a duplicate sibling key refuses the whole
surface update, and no extraction quirk may cost the app its root."
  (let ((file (alist-get 'file item))
        (pos (alist-get 'pos item))
        (token (alist-get 'token item)))
    ;; Opaque: a wire id keeps a readable stem, and a path must not reach
    ;; the device (SPEC 23.3).
    (cond
     ((and (stringp file) (integerp pos))
      (jetpacs-opaque-id "gp-item-"
                         (list group file pos (alist-get 'type item)
                               (alist-get 'day item) (alist-get 'date item))
                         16))
     ((stringp token)
      (jetpacs-opaque-id "gp-item-" (list group token) 16)))))

(defun glasspane-ui-day-words (date &optional today)
  "ISO DATE as a list heading: \"Today · Tue 28 Oct\", else \"Thu 30 Oct\".
Yesterday and Tomorrow are named too.  TODAY defaults to the current
date.  An invalid DATE returns nil."
  (when (jetpacs-dates-valid-p date)
    (let* ((today (or today (format-time-string "%Y-%m-%d")))
           (delta (jetpacs-dates-delta date today))
           (day (format "%s %s" (jetpacs-dates-weekday date t)
                        (string-trim-left (jetpacs-dates-format date "%e %b"))))
           (word (pcase delta (0 "Today") (1 "Tomorrow") (-1 "Yesterday"))))
      (if word (format "%s · %s" word day) day))))

(defun glasspane-ui-dedupe-keys (nodes)
  "Return NODES with any repeated sibling `:key' made unique in place.
The second and later holders of a key get an ordinal suffix; nodes
without a key pass through.  Order is preserved, so a repeat's suffix
is stable across renders of the same list."
  (let ((seen (make-hash-table :test #'equal)))
    (mapcar
     (lambda (node)
       (let ((key (and (consp node) (plist-get node :key))))
         (if (not (stringp key))
             node
           (let ((n (1+ (gethash key seen 0))))
             (puthash key n seen)
             (if (= n 1)
                 node
               (jetpacs-with-attrs node :key (format "%s-%d" key n)))))))
     nodes)))

(defun glasspane-ui-age-words (time &optional now)
  "TIME as a short relative phrase such as \"Edited 3 days ago\", or nil.
NOW defaults to the current time.  Under a minute reads \"Edited just now\"."
  (when time
    (let* ((seconds (max 0 (floor (- (float-time (or now (current-time)))
                                     (float-time time)))))
           (minutes (floor seconds 60))
           (hours (floor seconds 3600))
           (days (floor seconds 86400)))
      (cond
       ((< minutes 1) "Edited just now")
       ((< minutes 60) (format "Edited %d min ago" minutes))
       ((< hours 24) (format "Edited %d hour%s ago" hours
                             (if (= hours 1) "" "s")))
       ((= days 1) "Edited yesterday")
       ((< days 30) (format "Edited %d days ago" days))
       ((< days 365) (format "Edited %d month%s ago" (floor days 30)
                             (if (< days 60) "" "s")))
       (t (format "Edited %d year%s ago" (floor days 365)
                  (if (< days 730) "" "s")))))))

;;;; The at-ref funnel (S4/S5 — the classifier every later rung copies)

(defun glasspane-ui-at-ref (args fn &optional save)
  "Resolve ARGS' `:token' to its heading and run FN with point there.
Returns the SPEC 14.4 status the calling handler answers with — the
foundation's `jetpacs-org-heading-at-ref' classification (no/unknown
token -> `stale', `ebp-org-refused' -> `rejected', `ebp-org-unresolved'
-> `stale', any other signal -> `rejected', FN returned -> `accepted').
Glasspane owns only the token scope and, with SAVE non-nil, its save
funnel `glasspane-org-save-and-invalidate' (refresh suppression and the
optional vulpea row); save timing is app policy, resolution and cache
discipline are the foundation's."
  (jetpacs-org-heading-at-ref
   (ebp-org-token-ref (plist-get args :token) :owner "glasspane")
   fn
   (and save #'glasspane-org-save-and-invalidate)))

;;;; Token minting (S5 — the mint side of the funnel above)

(defun glasspane-ui-tokenize-tap (items set)
  "ITEMS with a `token' cell attached, minted as one bulk SET (S5).
Tap tokens only: cards built from these carry no swipe arms.  The
minting, filtering and replace sweep are the foundation's
`jetpacs-org-tokenize'; one screen at a time may use a given SET."
  (jetpacs-org-tokenize items set :owner "glasspane"))

;;;; Settings nodes
;;
;; The TODO-sequence and flat tag editors left with §3 step 2: they manage
;; org's own state and live in jetpacs-org-settings.el now, behind the
;; foundation's "Org workflow" satellite.  Choosing which native tag group
;; means PARA Areas remains Glasspane opinion, alongside saved searches.

(defun glasspane-ui--area-tags-enum ()
  "Build the editable global members of `glasspane-area-tag-group'."
  (let ((areas (jetpacs-org-settings-tag-group-members
                glasspane-area-tag-group)))
    (jetpacs-enum-list
     "glasspane-area-tags"
     (mapcar (lambda (area) (jetpacs-enum-option area area)) areas)
     :value areas
     :multi-select t
     :allow-add t
     :on-change (jetpacs-action "settings.areas.save"))))

(defun glasspane-ui--area-icon-row (area)
  "Build AREA's Material icon preview and editor row."
  (let* ((entry (assoc area glasspane-area-icons))
         (configured (glasspane-ui--configured-area-icon area))
         (icon (or configured glasspane-ui--default-area-icon))
         (subtitle
          (cond
           (configured (format "Material icon · %s" configured))
           ((and entry
                 (or (not (stringp (cdr entry)))
                     (not (string-empty-p (string-trim (cdr entry))))))
            "Invalid icon setting · using category")
           (t "Default · category"))))
    (jetpacs-chrome-row
     area
     :subtitle subtitle
     :icon icon
     :trailing (jetpacs-icon "edit"
                             :content-description
                             (format "Edit %s Area icon" area))
     :on-tap (jetpacs-action "settings.area-icon.edit"
                             :args (list :area area))
     :key (jetpacs-wire-id "area-icon" area))))

(defun glasspane-ui--area-icons-list ()
  "Build icon-editor rows for the globally declared Areas."
  (let ((areas (jetpacs-org-settings-tag-group-members
                glasspane-area-tag-group)))
    (if areas
        (apply #'jetpacs-column
               (append (mapcar #'glasspane-ui--area-icon-row areas)
                       (list :spacing 4)))
      (jetpacs-text "Add an Area tag above before choosing its icon."
                    :style "caption"))))

(defun glasspane-ui--demo-section ()
  "The collapsed Demo Content section: generators a daily driver rarely needs."
  (jetpacs-collapsible
   "glasspane-settings-demo"
   (jetpacs-text "Demo Content" :style "title")
   (jetpacs-column
    (jetpacs-text
     "Generate a resettable sample vault or editor tour. Only Glasspane's namespaced demo files are replaced."
     :style "caption")
    (jetpacs-button
                 "Generate Org Demo Content"
                 (jetpacs-action
                  "demo.setup-org"
                  :confirm
                  (list
                   :title "Regenerate Org demo?"
                   :text "Replace the glasspane-demo-* files in the first Org root? Other vault files are untouched."
                   :icon "science"
                   :confirm-label "Generate"
                   :dismiss-label "Cancel"))
                 :icon "science"
                 :variant "outlined")
                (jetpacs-button
                 "Generate Editor Tour Files"
                 (jetpacs-action
                  "demo.setup"
                  :confirm
                  (list
                   :title "Regenerate editor tour?"
                   :text "Replace Glasspane's isolated editor-tour files?"
                   :icon "code"
                   :confirm-label "Generate"
                   :dismiss-label "Cancel"))
                 :icon "code"
                 :variant "outlined")
    :spacing 8)
   :collapsed t))

(defun glasspane-ui--settings-body ()
  "The app settings screen body: Area tags and icons, then demo content.
Saved searches are managed where they are used, on Agenda's Saved tab.
The org/calendar schema sections live on the Settings ROOT with the
foundation that registers them, and the TODO-sequence/tags editors
behind its \"Org workflow\" satellite (jetpacs-org-settings.el, §3
steps 1-2) — this screen holds only the app's own managed opinions.
lazy_column, not column: the scaffold body has no scroll container on
the client."
  (jetpacs-lazy-column
   (jetpacs-section-header "Area Tags")
   (jetpacs-text
    "Members of the non-exclusive Org tag group “Area”: each is a PARA Area.  Persisted in org-tag-persistent-alist so a file's own #+TAGS line never hides it."
    :style "caption")
   (glasspane-ui--area-tags-enum)
   (jetpacs-divider)
   (jetpacs-section-header "Area Icons")
   (jetpacs-text
    "Choose presentation-only Material icons for each Area. Area membership remains ordinary Org tag data."
    :style "caption")
   (glasspane-ui--area-icons-list)
   (jetpacs-divider)
   (glasspane-ui--demo-section)))

(defun glasspane-ui--settings-screen (back)
  "The pushed Glasspane settings screen."
  (jetpacs-chrome-screen "Glasspane" (glasspane-ui--settings-body)
                         :back back))



;;;; Dialogs (S3 — one shape: ebp-client-dialog-show + captured fields)
;;
;; The one-live-dialog slot is the FOUNDATION's now
;; (jetpacs-settings-show-dialog, §3 step 2): the app's saved-search
;; editors share it with the org-workflow editors that moved out, and
;; the agenda writers stopped reaching across modules into a private
;; slot for their origin params.

(defun glasspane-ui--area-icon-suggestion-chip
    (area label icon configured &optional save-icon)
  "Build AREA's LABEL/ICON suggestion chip against CONFIGURED.
SAVE-ICON overrides the value persisted when tapped; the Default chip uses an
empty value to remove the mapping while still drawing the category glyph.
Choosing a suggestion is itself the durable save conclusion; the free-form
field below remains available for every other bundled Material icon."
  (jetpacs-chip
   label
   :icon icon
   :selected (jetpacs-bool (equal configured icon))
   :on-tap (jetpacs-action "settings.area-icon.save"
                           :args (list :area area
                                       :icon (if (null save-icon)
                                                 icon
                                               save-icon)))))

(defun glasspane-ui--show-area-icon-dialog (area params)
  "Show AREA's curated and free-form Material icon editor.
PARAMS are the opening event and preserve the Settings dialog context."
  (let* ((configured (glasspane-ui--configured-area-icon area))
         (effective (or configured glasspane-ui--default-area-icon))
         (save-action
          (jetpacs-action "settings.area-icon.save"
                          :args (list :area area)
                          :capture-fields '("area-icon-name"))))
    (jetpacs-settings-show-dialog
     "glasspane-area-icon-edit"
     (jetpacs-column
      (jetpacs-text (format "Icon for %s" area) :style "title")
      (jetpacs-chrome-row
       area
       :subtitle (if configured
                     (format "Current · %s" configured)
                   "Default · category")
       :icon effective)
      (jetpacs-text
       "Suggestions save immediately. Or enter any bundled Material icon name below."
       :style "caption")
      (apply
       #'jetpacs-flow-row
       (append
        (list
         (glasspane-ui--area-icon-suggestion-chip
          area "Default" glasspane-ui--default-area-icon
          effective ""))
        (mapcar
         (lambda (choice)
           (glasspane-ui--area-icon-suggestion-chip
            area (car choice) (cdr choice) configured))
         glasspane-ui--area-icon-suggestions)
        (list :spacing 4 :run-spacing 4)))
      (jetpacs-text-input
       "area-icon-name"
       :label "Custom Material icon"
       :value (or configured "")
       :single-line t
       :leading-icon effective
       :max-length 128
       :supporting-text
       "Use snake_case, for example health_and_safety. Blank restores category; unavailable names show a help icon."
       :on-submit save-action
       :hide-keyboard-on-submit t)
      (jetpacs-row
       (jetpacs-spacer :weight 1)
       (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
       (jetpacs-spacer :width 8)
       (jetpacs-button "Save" save-action))
      :spacing 8)
     :params params)))

(defun glasspane-ui--persist-area-icon (area icon)
  "Persist AREA's normalized ICON, or remove its mapping when ICON is nil.
The alist is key-sorted before Customize writes it because its order has no
semantics and must not depend on the sequence in which Areas were edited."
  (let ((next (cl-remove area glasspane-area-icons
                         :key #'car-safe :test #'equal)))
    (when icon (push (cons area icon) next))
    (setq next
          (sort next
                (lambda (a b)
                  (string-lessp (format "%s" (car-safe a))
                                (format "%s" (car-safe b))))))
    (setq glasspane-area-icons next)
    (jetpacs-settings-save-variable 'glasspane-area-icons next)))

(defun glasspane-ui--area-member-p (area)
  "Return non-nil when AREA is a current global Area-group member."
  (and (stringp area)
       (member area
               (jetpacs-org-settings-tag-group-members
                glasspane-area-tag-group))))

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

(defun glasspane-ui--on-area-icon-edit (args params)
  "Open the Material icon editor for ARGS' current `:area'.
PARAMS preserve the originating Settings surface for the deferred dialog."
  (let ((area (plist-get args :area)))
    (cond
     ((not (and (stringp area) (not (string-empty-p area)))) 'rejected)
     ((not (glasspane-ui--area-member-p area)) 'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-ui--show-area-icon-dialog area params)))
      'accepted))))

(defun glasspane-ui--on-area-icon-save (args params)
  "Persist ARGS' Area icon or the custom field captured in PARAMS.
An explicit `:icon' comes from a curated chip; otherwise `:area-icon-name'
comes from the free-form field.  Blank removes the preference."
  (let* ((area (plist-get args :area))
         (fields (plist-get params :fields))
         (raw (if (plist-member args :icon)
                  (plist-get args :icon)
                (plist-get fields :area-icon-name))))
    (cond
     ((not (and (stringp area) (not (string-empty-p area)))) 'rejected)
     ((not (glasspane-ui--area-member-p area))
      (jetpacs-settings-dialog-close)
      (jetpacs-settings-refresh)
      'stale)
     ((not (stringp raw)) 'rejected)
     (t
      (let ((icon (glasspane-ui--normalize-material-icon-name raw)))
        (cond
         ((string-empty-p icon)
          (glasspane-ui--persist-area-icon area nil)
          (jetpacs-settings-dialog-close)
          (jetpacs-shell-notify (format "Reset Area icon: %s" area))
          (jetpacs-settings-refresh)
          'accepted)
         ((not (glasspane-ui--material-icon-name-p icon))
          (jetpacs-toast "Use a snake_case Material icon name")
          'rejected)
         (t
          (glasspane-ui--persist-area-icon area icon)
          (jetpacs-settings-dialog-close)
          (jetpacs-shell-notify (format "Saved Area icon: %s" area))
          (jetpacs-settings-refresh)
          'accepted)))))))

(defun glasspane-ui--on-area-tags-save (args _params)
  "Persist ARGS' `:value' as the global Area tag-group members."
  (let ((value (plist-get args :value)))
    (if (not (and (plist-member args :value)
                  (or (vectorp value) (proper-list-p value))))
        'rejected
      (let ((raw (append value nil)))
        (if (not
             (cl-every
              (lambda (area)
                (and (stringp area)
                     (let ((clean (string-trim area)))
                       (and (not (string-empty-p clean))
                            (string-match-p
                             (concat "\\`" org-tag-re "\\'") clean)))))
              raw))
            'rejected
          (let ((areas (delete-dups (mapcar #'string-trim raw))))
            (jetpacs-org-settings-set-tag-group-members
             glasspane-area-tag-group areas 'org-tag-persistent-alist)
            (jetpacs-shell-notify
             (if areas "Area tags saved" "Area tag group cleared"))
            (jetpacs-settings-refresh)
            'accepted))))))

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
      ;; A dialog event has no :surface; this editor is reached from the
      ;; Settings hub, so use the foundation's canonical refresh target.
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
handlers, so the push takes the D2 seam (the `jetpacs-org-clock--soon'
shape): deferred past the dispatch extent when inside one, immediate
for a desktop M-x."
  (when (jetpacs-connected-p)
    (ebp-org-cache-invalidate)
    (let ((push (lambda () (jetpacs-shell-push "glasspane"))))
      (if (jetpacs-in-action-p)
          (jetpacs-flow-continue push)
        (funcall push)))))

(defun glasspane-ui-remove-hooks ()
  "Detach everything `glasspane-ui-register' hooked."
  (jetpacs-remove-hook 'jetpacs-shell-refresh-hook
                       #'glasspane-ui--refresh-invalidate)
  (jetpacs-remove-hook 'org-clock-in-hook #'glasspane-ui--refresh-if-connected)
  (jetpacs-remove-hook 'org-clock-out-hook
                       #'glasspane-ui--refresh-if-connected))

;;;; Registration

(defconst glasspane-ui--verbs
  '("glasspane.settings.open"
    "settings.area-icon.edit"
    "settings.area-icon.save"
    "settings.areas.save"
    "settings.agenda.edit"
    "settings.agenda.delete"
    "settings.agenda.save"
    "agenda.save-custom"
    "agenda.today"
    "agenda.select-date"
    "agenda.set-month"
    "glasspane.refresh"
    "glasspane.pane.close")
  "The verbs this rung owns, for the register/unregister sweep.
The TODO-sequence/tags verbs left with §3 step 2 (they are the
foundation's ownerless jetpacs.org.* family now);
search.clear-filters lives with the filter state it clears (G6),
files.filter and files.toggle-refile with the reader adapter (G4/GR-2).")

(defun glasspane-ui-register ()
  "Register the UI verbs, settings section/hub entry, and hooks.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers and
registry entries in place, and the keyed hub entry is replaced."
  ;; :any-surface — ONLY the opener now.  The Settings hub entry draws on
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
    (jetpacs-defaction
     "settings.area-icon.edit" #'glasspane-ui--on-area-icon-edit
     :doc "Open one Area's Material icon editor"
     :strict t
     :args '((:name area :type "text" :required t)))
    (jetpacs-defaction
     "settings.area-icon.save" #'glasspane-ui--on-area-icon-save
     :doc "Persist or reset one Area's Material icon preference"
     :strict t
     :args '((:name area :type "text" :required t)
             (:name icon :type "text")))
    (jetpacs-defaction "settings.areas.save"
                       #'glasspane-ui--on-area-tags-save
                       :doc "Save the global Area tag-group members")
    (jetpacs-defaction "settings.agenda.edit"
                       #'glasspane-ui--on-agenda-edit
                       :doc "Open the saved-agenda search editor")
    (jetpacs-defaction "settings.agenda.delete"
                       #'glasspane-ui--on-agenda-delete
                       :doc "Delete a named saved-agenda search")
    (jetpacs-defaction "settings.agenda.save"
                       #'glasspane-ui--on-agenda-save
                       :doc "Persist fields from the saved-agenda editor")
    (jetpacs-defaction "agenda.save-custom"
                       #'glasspane-ui--on-agenda-save-custom
                       :doc "Name and save the agenda's current custom query")
    (jetpacs-defaction "agenda.today" #'glasspane-ui--on-agenda-today
                       :doc "Reset the agenda calendar selection to today")
    (jetpacs-defaction "agenda.select-date"
                       #'glasspane-ui--on-agenda-select-date
                       :doc "Select a day in the agenda calendar")
    (jetpacs-defaction "agenda.set-month"
                       #'glasspane-ui--on-agenda-set-month
                       :doc "Set the agenda calendar's displayed month")
    (jetpacs-defaction "glasspane.refresh" #'glasspane-ui--on-refresh
                       :doc "Pull-to-refresh: recompute every Org extraction")
    (jetpacs-defaction "glasspane.pane.close" #'glasspane-ui--on-pane-close
                       :doc "Close the heading pane beside a list")
    ;; The app's own section — the one Glasspane-opinion row left: the
    ;; Packages auto-install switch (the Babel timeout followed the
    ;; table/Babel verbs into the foundation's Org Editing & Display
    ;; section).  The defcustom stays where it lives; this is the single
    ;; registration site, so glasspane-packages no longer registers a
    ;; section of its own.  Plain: it feeds no memoised extraction.
    (jetpacs-settings-register-section
     "Glasspane"
     (list (list 'glasspane-packages-auto-install
                 :label "Auto-install packages (org-ql, vulpea, org-srs, ef-themes)")))
    (jetpacs-settings-remove-hub-entry "glasspane")
    (jetpacs-settings-register-hub-entry
     "glasspane" :order 40 :icon "menu_book"
     :title "Glasspane"
     :subtitle "Area tags and icons, and demo content"
     :on-tap (jetpacs-action "glasspane.settings.open"))
    ;; Ledgered, so the app's teardown detaches them.
    (jetpacs-add-hook 'jetpacs-shell-refresh-hook
                      #'glasspane-ui--refresh-invalidate)
    ;; Depth 90: after jetpacs-org-clock's assert/retire on the same
    ;; hooks, so the repush renders the notification state they set.
    (jetpacs-add-hook 'org-clock-in-hook #'glasspane-ui--refresh-if-connected 90)
    (jetpacs-add-hook 'org-clock-out-hook
                      #'glasspane-ui--refresh-if-connected 90)))

(defun glasspane-ui-unregister ()
  "Drop the UI verbs, settings section/hub entry, and hooks."
  (dolist (name glasspane-ui--verbs)
    (jetpacs-undefaction name))
  (jetpacs-settings-remove-section "Glasspane")
  (jetpacs-settings-remove-hub-entry "glasspane")
  (jetpacs-settings-dialog-close)
  (glasspane-ui-remove-hooks))

(defun glasspane-ui-clock-entry (entry)
  "Render parsed Org clock ENTRY with a time range and duration or status.
ENTRY comes from `ebp-org-parse-logbook'.  Running clocks use source state;
rendering never reads wall time or updates the clock."
  (jetpacs-row
   (jetpacs-icon "timer" :size 18 :color "outline")
   (jetpacs-column
    (jetpacs-text
     (if (plist-get entry :active)
         (format "Started %s" (plist-get entry :start))
       (ebp-org-format-clock-time (plist-get entry :start)
                                 (plist-get entry :end)))
     :style "body")
    (jetpacs-text
     (if (plist-get entry :active) "Running"
       (format "Duration · %s" (or (plist-get entry :duration) "")))
     :style "caption" :color "outline")
    :spacing 2)
   :spacing 8))

(provide 'glasspane-ui)
;;; glasspane-ui.el ends here
