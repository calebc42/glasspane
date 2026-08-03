;;; jetpacs-m3-core.el --- M3 Expressive Catalog: model + chrome -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Tier-1 skeleton of the Compose Material 3 Expressive Catalog
;; recreated in Elisp: the component registry, the three screens, and
;; the verbs.  Component content lives in the sibling
;; `jetpacs-m3-<slug>.el' modules, one per catalog component, each
;; calling `jetpacs-m3-defcomponent'.
;;
;; The upstream app is
;; resources/android/Compose-Material-3-Expressive-Catalog.  Its
;; navigation is three deep — Home (a grid of components) → Component
;; (icon, description, a list of examples) → Example (one sample,
;; centered) — which is exactly `jetpacs-chrome-max-screens' (3), so
;; the stack never evicts on the main path.
;;
;; FIDELITY RULE.  Every component and every example of the upstream
;; catalog is listed, in upstream order, with its upstream name and
;; description.  An example whose sample cannot be expressed in the EBP
;; node vocabulary is declared `:unsupported REASON' and drills into a
;; "Not supported" screen carrying that reason — the catalog stays a
;; complete index of M3, and the gaps are visible instead of missing.
;; docs/lookup-tables/M3-COMPONENT-LOOKUP.org is the map of which M3
;; components Jetpacs wraps.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
;; `jetpacs-theme-mode' backs the ThemePicker's System/Light/Dark row.
(require 'jetpacs-theme)

(defconst jetpacs-m3-owner "m3catalog"
  "The D1 owner whose surface hosts the catalog.
Not under `jetpacs-reserved-owner-prefix': the catalog is a Tier-1
application, not base chrome.")

(defconst jetpacs-m3-title "Compose Material 3"
  "The Home top-bar title (upstream R.string.compose_material_3).")

(defconst jetpacs-m3-component-icon "widgets"
  "The icon every component card shows.
Upstream ships ONE generic `ic_component' drawable and every Component
comments \"No <x> icon\" — a single icon is the faithful reading, not a
shortcut.")

;;;; Preferences (upstream Theme, the parts that have a meaning here)

(defcustom jetpacs-m3-mark-expressive t
  "Mark components and examples that upstream flags expressive.
Upstream `Theme.markExpressiveComponents', default true — it draws a
corner banner reading \"Expr\"; here it is a trailing badge."
  :type 'boolean :group 'jetpacs)

(defcustom jetpacs-m3-show-only-expressive nil
  "Show only expressive components and examples.
Upstream `Theme.showOnlyExpressiveComponents', default false."
  :type 'boolean :group 'jetpacs)

(defvar jetpacs-m3-favorite nil
  "The pinned screen id, or nil (upstream `favoriteRoute').
`jetpacs-m3-catalog' opens it instead of Home.")

;;;; External links (upstream library/util/Url.kt)

(defconst jetpacs-m3-issue-url
  "https://issuetracker.google.com/issues/new?component=742043"
  "Upstream IssueUrl.")

(defconst jetpacs-m3-terms-url "https://policies.google.com/terms"
  "Upstream TermsUrl.")

(defconst jetpacs-m3-privacy-url "https://policies.google.com/privacy"
  "Upstream PrivacyUrl.")

(defconst jetpacs-m3-licenses-url
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:LICENSE.txt"
  "Upstream LicensesUrl.")

;;;; The registry

(defvar jetpacs-m3-components nil
  "Catalog components, upstream order.  See `jetpacs-m3-defcomponent'.")

(defvar jetpacs-m3--by-id (make-hash-table :test #'equal)
  "Component id -> the component plist in `jetpacs-m3-components'.")

(defconst jetpacs-m3-slot-keys
  '(:fab :bottom-bar :drawer :floating-toolbar :on-refresh :snackbar)
  "Scaffold slots an example may claim on its own Example screen.
Upstream shows a bottom app bar, a FAB, a drawer, a snackbar or a
pull-to-refresh by putting a whole `Scaffold' inside the example's
content.  A Node tree cannot nest a scaffold inside a scaffold, so here
the example claims the slot of the screen that hosts it — which is what
the sample was demonstrating in the first place.")

(cl-defun jetpacs-m3-example (name description &key source expressive
                                   build slots top-bar unsupported
                                   scaffold
                                   top-bar-style top-bar-subtitle
                                   scroll-behavior
                                   floating-toolbar-orientation
                                   floating-toolbar-expanded
                                   floating-toolbar-placement
                                   floating-toolbar-fab
                                   floating-toolbar-scroll
                                   floating-toolbar-exit-direction)
  "Describe one catalog example; returns the plist the registry stores.
NAME and DESCRIPTION are upstream's; SOURCE is its sourceUrl; EXPRESSIVE
mirrors `isExpressive'.

An example is either RECREATED or UNSUPPORTED, never both.  A recreated
one gives at least one of:

  BUILD     a nullary function returning the Node shown in the body;
  SLOTS     a plist of `jetpacs-m3-slot-keys' -> nullary function (or,
            for :snackbar, a string), claiming the Example screen's own
            scaffold slots;
  TOP-BAR   a function of one argument BACK (a `view.switch' descriptor,
            nil at the stack bottom) returning the screen's whole top
            bar.  It MUST offer a way back — use `jetpacs-m3-back-button'.

SCAFFOLD is a plist of §17.6 members appended verbatim to this screen's own
scaffold — the general door for anything that is NOT a builder, so a sample
whose subject is a scaffold member the harness has never heard of can ask
for it WITHOUT a change here.  `jetpacs-scaffold' validates it, so a
misspelled member is an error there rather than a silent drop.

    :slots (list :floating-toolbar #\='my-toolbar)
    :scaffold (list :floating-toolbar-orientation \"horizontal\"
                    :floating-toolbar-placement \"bottom_end\")

The named TOP-BAR-* / SCROLL-BEHAVIOR / FLOATING-TOOLBAR-* keywords are
sugar over the same plist, kept because modules already read that way.  Two
rules they carry: a styled top bar puts TOP-BAR's node in the real bar's
TITLE slot and has no actions slot, so a sample's actions and its way back
both live inside that node; and SCROLL-BEHAVIOR needs TOP-BAR-STYLE, which
`jetpacs-scaffold' enforces.

UNSUPPORTED is a sentence naming the wire member or node type the
sample would need; the example then drills into \"Not supported\"."
  (jetpacs--require-string name "example name")
  (jetpacs--require-string description "example description")
  (let ((recreated (or build slots top-bar)))
    (unless (or (and recreated (not unsupported))
                (and unsupported (not recreated)))
      (error "jetpacs-m3: example %S needs a recreation or :unsupported"
             name)))
  (dolist (fn (list build top-bar))
    (when (and fn (not (functionp fn)))
      (error "jetpacs-m3: example %S builder must be a function" name)))
  (let ((tail slots))
    (while tail
      (let ((key (pop tail)) (value (pop tail)))
        (unless (memq key jetpacs-m3-slot-keys)
          (error "jetpacs-m3: example %S has unknown slot %S" name key))
        ;; Two slots are VALUES, not node builders: :snackbar is the
        ;; message string and :on-refresh the action DESCRIPTOR
        ;; `jetpacs-scaffold' expects — running either through the node
        ;; guard could only ever degrade it to an error card.
        (unless (pcase key
                  (:snackbar (stringp value))
                  (:on-refresh (and (consp value) (keywordp (car value))))
                  (_ (functionp value)))
          (error "jetpacs-m3: example %S slot %S has the wrong type"
                 name key)))))
  (when unsupported
    (jetpacs--require-string unsupported ":unsupported"))
  (when top-bar-style (jetpacs--require-string top-bar-style ":top-bar-style"))
  (when top-bar-subtitle
    (jetpacs--require-string top-bar-subtitle ":top-bar-subtitle"))
  (when scroll-behavior (jetpacs--require-string scroll-behavior ":scroll-behavior"))
  ;; The guard covers BOTH doors: the sugar keyword and the generic plist.
  (when (and (or floating-toolbar-orientation
                 (plist-member scaffold :floating-toolbar-orientation))
             (not (plist-member slots :floating-toolbar)))
    (error "jetpacs-m3: example %S styles a floating toolbar it does not author"
           name))
  (when (and (or top-bar-style (plist-member scaffold :top-bar-style))
             (not top-bar))
    (error "jetpacs-m3: example %S styles a top bar it does not author" name))
  (list :name name :description description :source source
        :expressive (and expressive t)
        :build build :slots slots :top-bar top-bar
        :top-bar-style top-bar-style :top-bar-subtitle top-bar-subtitle
        :scroll-behavior scroll-behavior
        ;; Booleans ride as a two-element cell so an explicit :json-false
        ;; survives — `plist-get' cannot tell "false" from "absent", and
        ;; `floating-toolbar-expanded' has a meaningful false.
        ;; One plist reaches the scaffold.  The named keywords fold in
        ;; here, so the screen builder has a single thing to forward and a
        ;; future §17.6 member needs no change in this file at all.
        :scaffold
        (append
         scaffold
         (when top-bar-style (list :top-bar-style top-bar-style))
         (when top-bar-subtitle (list :top-bar-subtitle top-bar-subtitle))
         (when scroll-behavior (list :scroll-behavior scroll-behavior))
         (when floating-toolbar-orientation
           (list :floating-toolbar-orientation floating-toolbar-orientation))
         ;; `plist-member', not a truth test: :expanded and :scroll have a
         ;; meaningful :json-false that a truth test would drop.
         (when floating-toolbar-expanded
           (list :floating-toolbar-expanded floating-toolbar-expanded))
         (when floating-toolbar-placement
           (list :floating-toolbar-placement floating-toolbar-placement))
         (when floating-toolbar-fab
           (list :floating-toolbar-fab floating-toolbar-fab))
         (when floating-toolbar-scroll
           (list :floating-toolbar-scroll floating-toolbar-scroll))
         (when floating-toolbar-exit-direction
           (list :floating-toolbar-exit-direction floating-toolbar-exit-direction)))
        :unsupported unsupported))

(cl-defun jetpacs-m3-defcomponent (id &key name description guidelines docs
                                      source additional-info examples)
  "Register catalog component ID (a §4.4 identifier used in screen ids).
NAME, DESCRIPTION, GUIDELINES, DOCS, SOURCE and ADDITIONAL-INFO are
upstream's `Component' fields; EXAMPLES is a list of `jetpacs-m3-example'
plists in upstream order.  Re-registering an id REPLACES it in place, so
a module can be re-evaluated live without duplicating or reordering."
  (jetpacs--check-identifier id "component id")
  (jetpacs--require-string name "component name")
  (jetpacs--require-string description "component description")
  (let ((component (list :id id :name name :description description
                         :guidelines guidelines :docs docs :source source
                         :additional-info additional-info
                         :examples examples)))
    (if-let* ((prior (gethash id jetpacs-m3--by-id)))
        (setq jetpacs-m3-components
              (cl-substitute component prior jetpacs-m3-components :count 1))
      (setq jetpacs-m3-components
            (append jetpacs-m3-components (list component))))
    (puthash id component jetpacs-m3--by-id)
    id))

(defun jetpacs-m3-component (id)
  "The registered component ID, or nil."
  (gethash id jetpacs-m3--by-id))

(defun jetpacs-m3-expressive-p (component)
  "Non-nil when COMPONENT has any expressive example (upstream
`hasExpressiveExamples')."
  (cl-some (lambda (e) (plist-get e :expressive))
           (plist-get component :examples)))

(defun jetpacs-m3-visible-components ()
  "The components Home lists, honoring `jetpacs-m3-show-only-expressive'."
  (if jetpacs-m3-show-only-expressive
      (cl-remove-if-not #'jetpacs-m3-expressive-p jetpacs-m3-components)
    jetpacs-m3-components))

(defun jetpacs-m3-visible-examples (component)
  "COMPONENT's examples, honoring `jetpacs-m3-show-only-expressive'.
Returns (INDEX . EXAMPLE) cells: the index is the upstream position and
stays stable under filtering, because it addresses the example on the
wire."
  (let ((cells (cl-loop for e in (plist-get component :examples)
                        for i from 0 collect (cons i e))))
    (if jetpacs-m3-show-only-expressive
        (cl-remove-if-not (lambda (c) (plist-get (cdr c) :expressive)) cells)
      cells)))

;;;; Screen ids

(defun jetpacs-m3-component-screen-id (id)
  "The chrome screen id of component ID."
  (concat "c-" id))

(defun jetpacs-m3-example-screen-id (id index)
  "The chrome screen id of component ID's example INDEX."
  (format "e-%s-%d" id index))

;;;; Verbs authored into the tree

(defun jetpacs-m3-demo (message)
  "A descriptor for the demo verb: taps report MESSAGE as a snackbar.
Every recreated sample whose upstream handler only mutates local state
uses this, so a tap is visibly live instead of silently inert.

A real `scaffold.snackbar\=', as of the `jetpacs-shell--inject-snackbar\='
fix.  It was a toast for as long as this app existed, and the cause was
never the catalog: the injection tested the ROOT spec\='s `:t\=', and a
`jetpacs-chrome\=' app is a `multi_view\=' whose VIEWS are the scaffolds,
so no chrome app in the product ever found its own slot."
  (jetpacs-action "m3catalog.demo" :args (list :message message)))

(defun jetpacs-m3--open (id)
  (jetpacs-action "m3catalog.open" :args (list :component id)))

(defun jetpacs-m3--open-example (id index)
  (jetpacs-action "m3catalog.example"
                  :args (list :component id :index index)))

(defun jetpacs-m3--link (url)
  "A descriptor sharing URL, or nil when there is no url.
EBP has no open-in-browser builtin; `share.send' is the nearest verb
that reaches a browser, and it is companion-local."
  (when (and (stringp url) (not (string-empty-p url)))
    (jetpacs-share url)))

;;;; Chrome shared by the three screens

(defun jetpacs-m3--menu-item (label url)
  "A more-menu row sharing URL, disabled when there is no url."
  (if-let* ((link (jetpacs-m3--link url)))
      (jetpacs-menu-item label link)
    (jetpacs-menu-item label (jetpacs-m3-demo "No link for this component")
                       :enabled :json-false)))

(defun jetpacs-m3--more-menu (guidelines docs source)
  "The upstream MoreMenu: three component links plus the four fixed ones."
  (jetpacs-menu
   (list (jetpacs-m3--menu-item "View design guidelines" guidelines)
         (jetpacs-m3--menu-item "View developer docs" docs)
         (jetpacs-m3--menu-item "View source code" source)
         (jetpacs-m3--menu-item "Report an issue" jetpacs-m3-issue-url)
         (jetpacs-m3--menu-item "Terms of service" jetpacs-m3-terms-url)
         (jetpacs-m3--menu-item "Privacy policy" jetpacs-m3-privacy-url)
         (jetpacs-m3--menu-item "Open source licenses"
                                jetpacs-m3-licenses-url))
   :icon "more_vert"))

(defun jetpacs-m3--actions (screen-id &optional guidelines docs source)
  "The top-bar trailing actions: pin, theme, more.
SCREEN-ID is what the pin pins (upstream pins a nav route)."
  (list (let ((pinned (equal jetpacs-m3-favorite screen-id)))
          (jetpacs-icon-button
           "push_pin"
           (jetpacs-action "m3catalog.pin" :args (list :screen screen-id))
           :content-description (if pinned "Unpin screen" "Pin screen")
           ;; Upstream swaps Filled/Outlined PushPin and the wire has ONE
           ;; `push_pin' name, so the pinned state rides a badge.  It must
           ;; carry a LABEL: `icon_button' guards its BadgedBox on
           ;; `badge.isNotEmpty()' (InputNodes.kt), so an empty string
           ;; renders a bare icon — the bare-dot form is `badge' the NODE
           ;; (RenderBadge), which is not tappable and so cannot serve here.
           :badge (and pinned "•")))
        (jetpacs-icon-button
         "palette" (jetpacs-action "m3catalog.theme")
         :content-description "Change theme")
        (jetpacs-m3--more-menu guidelines docs source)))

(defun jetpacs-m3--expr-badge ()
  "The \"Expr\" marker upstream draws as a corner banner."
  (jetpacs-badge "Expr" :color "secondary_container"))

;;;; Home

(defun jetpacs-m3--home-card (component)
  "One component tile for the Home grid."
  (let* ((id (plist-get component :id))
         (info (plist-get component :additional-info))
         (mark (and jetpacs-m3-mark-expressive
                    (jetpacs-m3-expressive-p component))))
    (jetpacs-with-attrs
     (jetpacs-card
      (jetpacs-column
       ;; A weighted spacer, not :arrange "end": the Companion's
       ;; `horizontalArrange' reads `spacing' ONLY in its else branch
       ;; (LayoutNodes.kt), so any explicit arrange silently discards it
       ;; and the two badges would render flush.
       (apply #'jetpacs-row
              (append (list (jetpacs-with-attrs (jetpacs-spacer) :weight 1))
                      (when info
                        (list (jetpacs-badge info :color "error")))
                      (when mark (list (jetpacs-m3--expr-badge)))
                      (list :spacing 4 :fill t)))
       (jetpacs-with-attrs
        (jetpacs-icon jetpacs-m3-component-icon :size 56)
        :align_self "center" :weight 1)
       (jetpacs-text (plist-get component :name) :style "caption"
                     :max-lines 2)
       :spacing 8)
      :on-tap (jetpacs-m3--open id))
     :key (concat "home-" id) :padding 12 :height 156 :weight 1)))

(defun jetpacs-m3--home-rows (components)
  "COMPONENTS as rows of two tiles — the upstream adaptive grid on a phone."
  (let (rows)
    (while components
      (let ((left (pop components))
            (right (pop components)))
        (push (jetpacs-row
               (jetpacs-m3--home-card left)
               (if right
                   (jetpacs-m3--home-card right)
                 (jetpacs-with-attrs (jetpacs-spacer) :weight 1))
               :spacing 8 :fill t :align "top")
              rows)))
    (nreverse rows)))

(defun jetpacs-m3-home-screen (back)
  "The catalog root screen: every component as a tile."
  (jetpacs-chrome-screen
   jetpacs-m3-title
   (apply #'jetpacs-lazy-column
          (append (jetpacs-m3--home-rows (jetpacs-m3-visible-components))
                  (list :spacing 8 :content-padding 12)))
   :back back
   :actions (jetpacs-m3--actions "home")))

;;;; Component

(defun jetpacs-m3--example-row (component cell)
  "One ExampleItem row for CELL, an (INDEX . EXAMPLE) of COMPONENT."
  (let* ((id (plist-get component :id))
         (index (car cell))
         (example (cdr cell))
         (mark (and jetpacs-m3-mark-expressive
                    (plist-get example :expressive))))
    (jetpacs-chrome-row
     (plist-get example :name)
     :subtitle (plist-get example :description)
     :trailing (append (when mark (list (jetpacs-m3--expr-badge)))
                       (list (jetpacs-icon "keyboard_arrow_right")))
     :on-tap (jetpacs-m3--open-example id index)
     :key (format "ex-%s-%d" id index))))

(defun jetpacs-m3-component-screen (component back)
  "The Component screen: icon, description, and the example list."
  (let* ((id (plist-get component :id))
         (cells (jetpacs-m3-visible-examples component)))
    (jetpacs-chrome-screen
     (plist-get component :name)
     (apply #'jetpacs-lazy-column
            (append
             (list (jetpacs-with-attrs
                    (jetpacs-icon jetpacs-m3-component-icon :size 108)
                    :align_self "center" :padding 24)
                   (jetpacs-text "Description" :style "title")
                   (jetpacs-text (plist-get component :description))
                   (jetpacs-with-attrs (jetpacs-spacer) :height 16)
                   (jetpacs-text "Examples" :style "title"))
             (if cells
                 (mapcar (lambda (cell)
                           (jetpacs-m3--example-row component cell))
                         cells)
               (list (jetpacs-with-attrs
                      (jetpacs-text "No examples")
                      :align_self "center" :padding 24)))
             (list :spacing 8 :content-padding 16)))
     :back back
     :actions (jetpacs-m3--actions
               (jetpacs-m3-component-screen-id id)
               (plist-get component :guidelines)
               (plist-get component :docs)
               (plist-get component :source)))))

;;;; Example

(defun jetpacs-m3-unsupported-body (reason)
  "The \"Not supported\" body carrying REASON."
  (jetpacs-empty-state
   :icon "block"
   :title "Not supported"
   :caption reason))

(defun jetpacs-m3-back-button (back)
  "The leading arrow a custom `:top-bar' must include, or nil at the root."
  (when back
    (jetpacs-icon-button "arrow_back" back :content-description "back")))

(defun jetpacs-m3--guard (label thunk)
  "Run THUNK, degrading a signal to an `error' card naming LABEL.
A sample that signals costs its own screen body and nothing else: the
catalog must stay navigable when one recreation is wrong."
  (condition-case err
      (let ((node (funcall thunk)))
        (unless (jetpacs--root-node-p node)
          (error "sample builder returned %S" node))
        node)
    (error
     (message "jetpacs-m3: sample %s failed: %s"
              label (jetpacs--error-label err))
     (jetpacs-empty-state
      :icon "error"
      :title "Sample failed to build"
      :caption (jetpacs--error-label err)))))

(defun jetpacs-m3--slot-hint (slots)
  "A caption naming the SLOTS an example claims, for a body-less sample."
  (jetpacs-text
   (format "This sample renders in the screen chrome: %s."
           (mapconcat (lambda (key)
                        (string-replace "-" " " (substring (symbol-name key) 1)))
                      (cl-loop for (key _value) on slots by #'cddr collect key)
                      ", "))
   :style "caption"))

(defun jetpacs-m3--example-body (example)
  "EXAMPLE's recreated sample, its Not-supported card, or a build error."
  (let ((reason (plist-get example :unsupported))
        (build (plist-get example :build))
        (slots (plist-get example :slots)))
    (cond
     (reason (jetpacs-m3-unsupported-body reason))
     (build (jetpacs-m3--guard (plist-get example :name) build))
     (slots (jetpacs-m3--slot-hint slots))
     (t (jetpacs-m3--slot-hint nil)))))

(defun jetpacs-m3--example-slots (example)
  "EXAMPLE's scaffold slots as a `jetpacs-scaffold' keyword plist."
  (let ((label (plist-get example :name))
        (out nil))
    (cl-loop
     for (key value) on (plist-get example :slots) by #'cddr
     do (push key out)
        ;; :snackbar (a string) and :on-refresh (a descriptor) pass
        ;; through raw; every other slot is a builder run under guard.
        (push (if (memq key '(:snackbar :on-refresh))
                  value
                (jetpacs-m3--guard label value))
              out))
    (nreverse out)))

(defun jetpacs-m3-example-screen (component index back)
  "The Example screen for COMPONENT's example INDEX.
Upstream centers the sample in the content area; a sample that IS
screen chrome (a bottom app bar, a FAB, a drawer, a snackbar,
pull-to-refresh, a top bar) claims this screen's own scaffold slot
instead, because a Node tree cannot nest a scaffold."
  (let* ((example (nth index (plist-get component :examples)))
         (id (jetpacs-m3-example-screen-id (plist-get component :id) index))
         (actions (jetpacs-m3--actions id
                                       (plist-get component :guidelines)
                                       (plist-get component :docs)
                                       (plist-get example :source)))
         (top-bar (plist-get example :top-bar))
         (body (jetpacs-with-attrs
                (jetpacs-column (jetpacs-m3--example-body example)
                                :scroll t :align "center" :spacing 16 :fill t)
                :padding 16))
         (slots (jetpacs-m3--example-slots example)))
    (if top-bar
        (apply #'jetpacs-scaffold
               :top-bar (jetpacs-m3--guard
                         (plist-get example :name)
                         (lambda () (funcall top-bar back)))
               :body body
               ;; §17.6 top-bar members ride the same scaffold; nil values are
               ;; dropped by `jetpacs--node', so an unstyled example is
               ;; byte-identical to before.
               (append (plist-get example :scaffold) slots))
      (apply #'jetpacs-chrome-screen (plist-get example :name) body
             :back back :actions actions
             :scaffold (plist-get example :scaffold)
             slots))))

;;;; Theme

(defun jetpacs-m3--toggle-row (key label value)
  "A switch row for preference KEY, labelled LABEL, currently VALUE."
  (jetpacs-switch (concat "m3-pref-" key)
                  :checked (and value t)
                  :label label
                  :on-change (jetpacs-action "m3catalog.pref"
                                             :args (list :key key))))

(defun jetpacs-m3--polarity-row ()
  "Upstream ThemePicker's Theme section: System / Light / Dark.
Not a Companion-owned setting Emacs can only mirror -- the direction of
control runs the other way.  `theme.set' carries an OPTIONAL `dark'
sent BY Emacs, and amendment #36 exists precisely to spell the
three-way choice: a real boolean forces the polarity and only its
ABSENCE falls through to the device's own setting.  `jetpacs-theme-mode'
already names those three, and its `:set' pushes on the live
connection.

`:value' must name an authored option, so the two modes upstream does
not offer (`mirror', `off') select nothing rather than pass a value the
list does not carry."
  (let ((mode (symbol-name jetpacs-theme-mode)))
    (jetpacs-enum-list
     "m3-pref-polarity"
     (list (jetpacs-enum-option "System" "system")
           (jetpacs-enum-option "Light" "light")
           (jetpacs-enum-option "Dark" "dark"))
     :value (car (member mode '("system" "light" "dark")))
     :on-change (jetpacs-action "m3catalog.pref"
                                :args (list :key "polarity")))))

(defun jetpacs-m3--unsupported-row (label reason)
  "A theme row for an upstream setting with no EBP equivalent."
  (jetpacs-chrome-row label :subtitle reason :icon "block"
                      :on-tap (jetpacs-m3-demo "Not supported")
                      :key (jetpacs-wire-id "m3pref" label)))

(defun jetpacs-m3-theme-screen (back)
  "The theme screen — upstream's ThemePicker bottom sheet, as a screen."
  (jetpacs-chrome-screen
   "Change theme"
   (jetpacs-lazy-column
    (jetpacs-text "Expressive" :style "title")
    (jetpacs-m3--toggle-row "mark" "Mark expressive components"
                            jetpacs-m3-mark-expressive)
    (jetpacs-m3--toggle-row "only" "Show only expressive components"
                            jetpacs-m3-show-only-expressive)
    (jetpacs-divider)
    (jetpacs-text "Theme" :style "title")
    (jetpacs-m3--unsupported-row
     "Color mode"
     "Baseline/Custom/Dynamic — the Companion owns the color scheme")
    (jetpacs-m3--polarity-row)
    (jetpacs-m3--unsupported-row
     "Font scale" "No text-scale member in the EBP node vocabulary")
    (jetpacs-m3--unsupported-row
     "Text direction" "No layout-direction member in the wire format")
    :spacing 12 :content-padding 16)
   :back back
   :actions (jetpacs-m3--actions "theme")))

;;;; Navigation

(defun jetpacs-m3--push (surface id builder)
  "Push screen ID onto SURFACE, logging a refused push instead of dying.
`jetpacs-chrome-push-screen' re-signals a gate failure, and this runs
from `jetpacs-flow-continue' — a signal in a timer is a backtrace with
no user in front of it."
  (condition-case err
      (jetpacs-chrome-push-screen surface id builder)
    (error (message "jetpacs-m3: push of %s failed: %s"
                    id (jetpacs--error-label err))
           (jetpacs-shell-notify "That screen could not be shown" surface))))

(defun jetpacs-m3-show-component (id &optional surface)
  "Push component ID's screen onto SURFACE."
  (when-let* ((component (jetpacs-m3-component id)))
    (jetpacs-m3--push (or surface jetpacs-m3-owner)
                      (jetpacs-m3-component-screen-id id)
                      (lambda (back)
                        (jetpacs-m3-component-screen component back)))))

(defun jetpacs-m3-show-example (id index &optional surface)
  "Push component ID's example INDEX onto SURFACE."
  (when-let* ((component (jetpacs-m3-component id)))
    (when (and (integerp index)
               (< -1 index (length (plist-get component :examples))))
      (jetpacs-m3--push (or surface jetpacs-m3-owner)
                        (jetpacs-m3-example-screen-id id index)
                        (lambda (back)
                          (jetpacs-m3-example-screen component index back))))))

(defun jetpacs-m3-show-theme (&optional surface)
  "Push the theme screen onto SURFACE."
  (jetpacs-m3--push (or surface jetpacs-m3-owner) "theme"
                    #'jetpacs-m3-theme-screen))

;;;; The verbs

(defun jetpacs-m3--on-open (args params)
  "Drill into a component (upstream onComponentClick)."
  (let ((id (plist-get args :component))
        (surface (plist-get params :surface)))
    (cond
     ((not (stringp id)) 'rejected)
     ((null (jetpacs-m3-component id)) 'stale)
     (t (jetpacs-flow-continue
         (lambda () (jetpacs-m3-show-component id surface)))
        'accepted))))

(defun jetpacs-m3--on-example (args params)
  "Drill into an example (upstream onExampleClick)."
  (let ((id (plist-get args :component))
        (index (plist-get args :index))
        (surface (plist-get params :surface)))
    (cond
     ((not (and (stringp id) (integerp index))) 'rejected)
     ((null (jetpacs-m3-component id)) 'stale)
     (t (jetpacs-flow-continue
         (lambda () (jetpacs-m3-show-example id index surface)))
        'accepted))))

(defun jetpacs-m3--on-theme (_args params)
  "Open the theme screen (upstream onThemeClick)."
  (let ((surface (plist-get params :surface)))
    (jetpacs-flow-continue (lambda () (jetpacs-m3-show-theme surface)))
    'accepted))

(defun jetpacs-m3--on-pref (args params)
  "Toggle a catalog preference and re-render."
  (let ((key (plist-get args :key))
        (surface (plist-get params :surface)))
    (pcase key
      ("mark" (setopt jetpacs-m3-mark-expressive
                      (not jetpacs-m3-mark-expressive)))
      ("only" (setopt jetpacs-m3-show-only-expressive
                      (not jetpacs-m3-show-only-expressive)))
      ;; §14.3 injects the picked option's value; `setopt' runs
      ;; `jetpacs-theme-mode's :set, which pushes theme.set itself.
      ("polarity"
       (let ((value (plist-get args :value)))
         (if (member value '("system" "light" "dark"))
             (setopt jetpacs-theme-mode (intern value))
           (setq key nil))))
      (_ (setq key nil)))
    (if (null key)
        'rejected
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (jetpacs-shell-push (or surface jetpacs-m3-owner))
           (error (message "jetpacs-m3: refresh failed: %s"
                           (jetpacs--error-label err))))))
      'accepted)))

(defun jetpacs-m3--on-pin (args params)
  "Pin or unpin a screen (upstream onFavoriteClick)."
  (let ((screen (plist-get args :screen))
        (surface (plist-get params :surface)))
    (if (not (stringp screen))
        'rejected
      (setq jetpacs-m3-favorite
            (unless (equal jetpacs-m3-favorite screen) screen))
      (jetpacs-shell-notify (if jetpacs-m3-favorite "Pinned" "Unpinned")
                            surface)
      'accepted)))

(defun jetpacs-m3--on-demo (args params)
  "The sample verb: report the message, mutate nothing."
  (let ((text (plist-get args :message)))
    (if (not (stringp text))
        'rejected
      (jetpacs-shell-notify text (plist-get params :surface))
      'accepted)))

(defun jetpacs-m3--on-home (_args params)
  "Return to Home (the drawer's home row)."
  (let ((surface (plist-get params :surface)))
    (jetpacs-flow-continue
     (lambda ()
       (jetpacs-chrome-reset-screens (or surface jetpacs-m3-owner))))
    'accepted))

(defun jetpacs-m3-register ()
  "Register the catalog's owner, verbs and root screen.
Idempotent: re-evaluation replaces the handlers and RESETS the screen
stack to Home, which is the documented live-reload path."
  (with-jetpacs-owner jetpacs-m3-owner
    (jetpacs-defaction "m3catalog.open" #'jetpacs-m3--on-open)
    (jetpacs-defaction "m3catalog.example" #'jetpacs-m3--on-example)
    (jetpacs-defaction "m3catalog.theme" #'jetpacs-m3--on-theme)
    (jetpacs-defaction "m3catalog.pref" #'jetpacs-m3--on-pref)
    (jetpacs-defaction "m3catalog.pin" #'jetpacs-m3--on-pin)
    (jetpacs-defaction "m3catalog.demo" #'jetpacs-m3--on-demo)
    (jetpacs-defaction "m3catalog.home" #'jetpacs-m3--on-home)
    (jetpacs-chrome-define-root jetpacs-m3-owner "home"
                                #'jetpacs-m3-home-screen)))

(defun jetpacs-m3-unregister ()
  "Deregister the catalog verbs and its chrome root."
  (dolist (verb '("m3catalog.open" "m3catalog.example" "m3catalog.theme"
                  "m3catalog.pref" "m3catalog.pin" "m3catalog.demo"
                  "m3catalog.home"))
    (jetpacs-undefaction verb))
  (jetpacs-chrome-remove jetpacs-m3-owner))

(provide 'jetpacs-m3-core)
;;; jetpacs-m3-core.el ends here
