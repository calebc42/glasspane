;;; jetpacs-m3-floating-toolbar.el --- Catalog component: Floating Toolbar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `FloatingToolbars' + Examples.kt
;; `FloatingToolbarsExamples' (11 examples),
;; samples/FloatingToolbarSamples.kt.
;;
;; M3's `FloatingToolbar' composable is not in the Companion's material3
;; at all (1.4.0; it arrives in 1.5+, per M3-COMPONENT-LOOKUP).  What the
;; wire has is the `scaffold.floating_toolbar' slot -- CHROME-VOCABULARY's
;; "Toolbar -- floating", a persistent cluster of contextual actions the
;; renderer draws as a full-width elevated Surface above the bottom bar --
;; and `scaffold.fab', which places one node exactly where M3 puts a FAB.
;; Between them they carry a toolbar's ACTIONS and their order, and
;; nothing else: no `expanded', no orientation, no Alignment or
;; ScreenOffset, no scrollBehavior, no AppBarRow overflow.
;;
;; Every one of the eleven samples is that cluster plus ONE of those
;; absent axes -- upstream ships no plain FloatingToolbar sample, because
;; `expanded' is a required parameter.  So the two whose subject the
;; scaffold does carry are recreated: the KDoc sample of
;; `HorizontalFloatingToolbar' itself, whose leading/content/trailing
;; actions are the band the slot draws, and the one that hands a whole
;; toolbar to `Scaffold(floatingActionButton =)', which is this screen's
;; own fab slot.  The other nine name the axis they exist to show -- a
;; vertical rail, an overflow menu, a scroll-driven exit, an
;; overlay placement, a FAB-toggled collapse -- none of which has a
;; member on the wire.
;;
;; The horizontal recreation also authors its own top bar: with no
;; floating-toolbar keyword on `jetpacs-chrome-screen', the slot is
;; reachable only through the scaffold the `:top-bar' path builds, so
;; that sample supplies the back arrow and the title itself.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-floating-toolbar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingToolbarSamples.kt"
  "Upstream FloatingToolbarsExampleSourceUrl.")

(defconst jetpacs-m3-floating-toolbar--vertical-note
  "There is one floating_toolbar slot and the Companion draws it as a full-width band above the bottom bar: no orientation or alignment member stands a VerticalFloatingToolbar rail at the center end of the screen."
  "Why every VerticalFloatingToolbar sample is unsupported.
The orientation settles it before the sample's second axis does.")

(defun jetpacs-m3-floating-toolbar--action (icon message)
  "One toolbar IconButton showing ICON and reporting MESSAGE on tap.
Every icon in these samples carries the same upstream
`contentDescription', \"Localized description\", over an empty
onClick -- so the description is upstream's literal and the tap says
which of the identically-described actions was hit."
  (jetpacs-icon-button icon (jetpacs-m3-demo message)
                       :content-description "Localized description"))

(defun jetpacs-m3-floating-toolbar--primary (icon message width)
  "ICON as the toolbar's primary action, WIDTH dp wide, reporting MESSAGE.
`icon_button' has no filled variant, so the FilledIconButton container
of the samples is composed: a `surface' in the primary role, circle
shape (M3's CircleShape is a 50% corner, i.e. the pill a 64dp-wide
filled icon button already is)."
  (jetpacs-with-attrs
   (jetpacs-surface (jetpacs-m3-floating-toolbar--action icon message)
                    :color "primary" :shape "circle")
   :width width))

(defun jetpacs-m3-floating-toolbar--expandable-horizontal ()
  "Upstream ExpandableHorizontalFloatingToolbarSample, as the toolbar slot.
The KDoc sample of HorizontalFloatingToolbar: leadingContent is Check
and Edit, content is a 64dp-wide FilledIconButton with Add, and
trailingContent is Download and Favorite.  The slot draws that cluster
persistently, which is the toolbar's `expanded = true' state -- the
collapse driven by floatingToolbarVerticalNestedScroll is Companion-side
motion with no wire member, which is why the Scrollable sample below,
whose whole subject is that motion, is unsupported."
  (jetpacs-row
   (jetpacs-m3-floating-toolbar--action "check" "Check")
   (jetpacs-m3-floating-toolbar--action "edit" "Edit")
   (jetpacs-m3-floating-toolbar--primary "add" "Add" 64)
   (jetpacs-m3-floating-toolbar--action "download" "Download")
   (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
   :spacing 8 :align "center" :arrange "center" :fill t))

(defun jetpacs-m3-floating-toolbar--expandable-top-bar (back)
  "The Example screen's own top bar for the sample above.
`jetpacs-chrome-screen' has no floating-toolbar keyword: that slot is
reachable only on the scaffold the `:top-bar' path builds, so the
sample authors the bar -- BACK first, as the contract requires."
  (apply #'jetpacs-row
         (append
          (when back (list (jetpacs-m3-back-button back)))
          (list (jetpacs-with-attrs
                 (jetpacs-text "ExpandableHorizontalFloatingToolbarSample"
                               :style "title" :max-lines 2)
                 :weight 1))
          (list :align "center" :spacing 4))))

(defun jetpacs-m3-floating-toolbar--as-scaffold-fab ()
  "Upstream HorizontalFloatingToolbarAsScaffoldFabSample, in the fab slot.
Upstream hands the whole toolbar to `Scaffold(floatingActionButton =)'
with `FabPosition.End'; the wire's fab slot places one node in exactly
that spot, so the toolbar goes there -- the sample's subject is the
hosting, and this screen hosts it the same way.  The four IconButtons
\(Person, Edit, Favorite, MoreVert) and the Add FAB share one `surface'
because a floating toolbar IS that cluster; primary_container is the
role the wire can name for vibrantFloatingToolbarColors."
  (jetpacs-surface
   (jetpacs-with-attrs
    (jetpacs-row
     (jetpacs-m3-floating-toolbar--action "person" "Person")
     (jetpacs-m3-floating-toolbar--action "edit" "Edit")
     (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
     (jetpacs-m3-floating-toolbar--action "more_vert" "MoreVert")
     (jetpacs-m3-floating-toolbar--primary "add" "Add" 56)
     :spacing 4 :align "center")
    :padding 8)
   :color "primary_container" :shape "circle" :elevation 6))

(jetpacs-m3-defcomponent "floating-toolbar"
  :name "Floating Toolbar"
  :description
  "A floating toolbar displays key actions above the content."
  :guidelines "https://m3.material.io/components/floating-toolbars"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#floatingtoolbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/FloatingToolbar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ExpandableHorizontalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :top-bar #'jetpacs-m3-floating-toolbar--expandable-top-bar
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--expandable-horizontal))
   (jetpacs-m3-example
    "OverflowingHorizontalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "There is no AppBarRow node: a row cannot measure its children and move the ones that do not fit into a more_vert overflow menu, and that automatic overflow of Download, Favorite, Add, Person and ArrowUpward is this sample's whole subject.")
   (jetpacs-m3-example
    "ScrollableHorizontalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "Neither the scaffold nor its floating_toolbar has a scroll-behavior member, and the wire carries no scroll signal at all: FloatingToolbarDefaults.exitAlwaysScrollBehavior, which slides the toolbar off the bottom edge as the body scrolls, cannot be asked for from Emacs.")
   (jetpacs-m3-example
    "ExpandableVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported jetpacs-m3-floating-toolbar--vertical-note)
   (jetpacs-m3-example
    "OverflowingVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "Neither half is on the wire: the floating_toolbar slot has no orientation member for a vertical rail, and there is no AppBarColumn node that moves the actions which do not fit into an overflow menu.")
   (jetpacs-m3-example
    "ScrollableVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "Neither half is on the wire: the floating_toolbar slot has no orientation member for a vertical rail, and no scroll-behavior member for the exitAlwaysScrollBehavior that hides it toward the end edge.")
   (jetpacs-m3-example
    "HorizontalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "The wire puts chrome in fixed scaffold slots: no alignment or ScreenOffset member floats a toolbar over the body at BottomEnd, and the floating_toolbar slot holds a node and never state, so the expanded flag this sample's FAB toggles has nothing to ride on.")
   (jetpacs-m3-example
    "CenteredHorizontalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "The floating_toolbar band is drawn full width above the bottom bar, with no member for the bottom-centered ScreenOffset placement, and no scroll-behavior member for the exitAlwaysScrollBehavior that hides the toolbar and its FAB together.")
   (jetpacs-m3-example
    "HorizontalFloatingToolbarAsScaffoldFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :slots (list :fab #'jetpacs-m3-floating-toolbar--as-scaffold-fab))
   (jetpacs-m3-example
    "VerticalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported jetpacs-m3-floating-toolbar--vertical-note)
   (jetpacs-m3-example
    "CenteredVerticalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported jetpacs-m3-floating-toolbar--vertical-note)
   ))

(provide 'jetpacs-m3-floating-toolbar)
;;; jetpacs-m3-floating-toolbar.el ends here
