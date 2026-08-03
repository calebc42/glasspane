;;; jetpacs-m3-floating-toolbar.el --- Catalog component: Floating Toolbar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `FloatingToolbars' + Examples.kt
;; `FloatingToolbarsExamples' (11 examples),
;; samples/FloatingToolbarSamples.kt.
;;
;; M3's `FloatingToolbar' is not a node type, but the `scaffold' now
;; carries one as a slot with six §17.6 members:
;; `floating_toolbar_orientation' turns the slot from the full-width band
;; above the bottom bar into M3's REAL pill, floating over the body, and
;; `floating_toolbar_expanded', `_placement', `_fab', `_scroll' and
;; `_exit_direction' vary it.  That is most of what these eleven samples
;; exist to show.
;;
;; NONE OF IT IS REACHABLE FROM A COMPONENT MODULE.  `jetpacs-m3-example'
;; offers `:build', `:top-bar', the three top-bar keywords, and `:slots' --
;; a CLOSED key list whose values must be NULLARY BUILDERS.  The six new
;; members are strings, a boolean and a node, so they fit neither door: no
;; example can put them on the Example screen's own scaffold.  This is the
;; same harness gap the top-app-bar module hit before `jetpacs-m3-example'
;; grew `:top-bar-style', and the fix has the same shape -- six more
;; first-class keywords passed straight through in
;; `jetpacs-m3-example-screen' -- but it lives in jetpacs-m3-core.el.
;;
;; So the reasons below separate two kinds of missing, and say which.
;;
;; HARNESS ONLY (4): both Scrollable samples and both Centered-with-FAB
;; samples.  Every member their subject needs is on the wire and correct;
;; they build the day the example carries those keywords.
;;
;; STILL GENUINELY MISSING (5):
;;
;;   * AppBarRow / AppBarColumn -- no node measures a row or a column and
;;     moves what does not fit into an overflow menu (the two Overflowing
;;     samples).
;;   * floatingToolbarVerticalNestedScroll -- `floating_toolbar_scroll' is
;;     exitAlwaysScrollBehavior, which SLIDES the pill off an edge.  The
;;     Expandable samples show the other motion: a collapse to the leading
;;     content and back as the list scrolls.  No member carries it, and
;;     `floating_toolbar_expanded' is a static value.
;;   * a BINDING for `floating_toolbar_expanded' -- it has no on-change
;;     descriptor, so the FAB that toggles it in the two *WithFab samples
;;     has nothing to drive.
;;
;; Two are recreated, and neither needs the pill: the KDoc sample of
;; `HorizontalFloatingToolbar', whose leading/content/trailing actions are
;; the cluster the UNSTYLED band draws (orientation absent keeps that
;; rendering exactly), and the one that hands a whole toolbar to
;; `Scaffold(floatingActionButton =)', which is this screen's own fab slot.
;;
;; The horizontal recreation also authors its own top bar:
;; `jetpacs-chrome-screen' has no floating-toolbar keyword, so the slot is
;; reachable only through the scaffold the `:top-bar' path builds, and that
;; sample supplies the back arrow and the title itself.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-floating-toolbar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingToolbarSamples.kt"
  "Upstream FloatingToolbarsExampleSourceUrl.")

(defconst jetpacs-m3-floating-toolbar--harness-note
  "No catalog example can ask for those members yet: jetpacs-m3-example takes a scaffold slot only as a nullary builder under a closed key list, and the six floating_toolbar members are strings, a boolean and a node, so reaching them needs first-class keywords on the example the way top_bar_style already has them."
  "The harness half of every reason in this module.
The §17.6 members landed on `jetpacs-scaffold', not on
`jetpacs-m3-example': `jetpacs-m3--example-slots' filters `:slots'
through `jetpacs-m3-slot-keys' and demands a function for every value,
so no component module can put a string, a boolean or a bare node on
the Example screen's scaffold.  Appended to the reasons whose sample
the WIRE can already carry, and kept out of the ones a real wire gap
settles first.")

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
trailingContent is Download and Favorite.  That cluster, in that order,
is what the slot draws.

It draws it as the full-width BAND, not as M3's pill.
`floating_toolbar_orientation' would make it a pill, and
`jetpacs-m3-example' has no keyword that reaches that member --
see `jetpacs-m3-floating-toolbar--harness-note'.  The sample's other
half fails for a second and independent reason: the collapse to the
leading content that `floatingToolbarVerticalNestedScroll' drives is
NOT `floating_toolbar_scroll' (that is exitAlwaysScrollBehavior, which
slides the whole pill off an edge), and no member carries it."
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
hosting, and this screen hosts it the same way.

The four IconButtons \(Person, Edit, Favorite, MoreVert) and the vibrant
Add FAB share one `surface': the fab slot takes ONE node and a scaffold
cannot nest inside a scaffold, so the pill and the FAB fused to its end
\(upstream's `floatingActionButton =', the wire's `floating_toolbar_fab')
are composed here rather than asked for.  primary_container is the role
the wire can name for vibrantFloatingToolbarColors."
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
    (concat
     "The scaffold now carries every member this sample varies: a horizontal pill at floating_toolbar_placement bottom_center, expanded, with floating_toolbar_scroll and floating_toolbar_exit_direction \"bottom\" building the FloatingToolbarDefaults.exitAlwaysScrollBehavior(Bottom) that slides it off the bottom edge as the body scrolls and brings it back. "
     jetpacs-m3-floating-toolbar--harness-note))
   (jetpacs-m3-example
    "ExpandableVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    (concat
     "floating_toolbar_scroll is exitAlwaysScrollBehavior, which slides the whole pill off an edge; this sample shows the OTHER motion, the floatingToolbarVerticalNestedScroll that collapses the rail to its leading content as the list scrolls and expands it again. No member carries that, and floating_toolbar_expanded is a static value. The center-end vertical rail it collapses is on the wire. "
     jetpacs-m3-floating-toolbar--harness-note))
   (jetpacs-m3-example
    "OverflowingVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "There is no AppBarColumn node: a column cannot measure its children and move the ones that do not fit into an overflow menu, and that automatic overflow of Download, Favorite, Add, Person and ArrowUpward is this sample's whole subject. The vertical rail it overflows inside is now a scaffold member (floating_toolbar_orientation); the overflow is not on the wire at all.")
   (jetpacs-m3-example
    "ScrollableVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    (concat
     "The scaffold now carries every member this sample varies: floating_toolbar_orientation \"vertical\" at floating_toolbar_placement \"center_end\" for the rail, and floating_toolbar_scroll with floating_toolbar_exit_direction \"end\" for the exitAlwaysScrollBehavior(End) that hides it toward the end edge. "
     jetpacs-m3-floating-toolbar--harness-note))
   (jetpacs-m3-example
    "HorizontalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    (concat
     "floating_toolbar_expanded is a value with no on-change descriptor, so the FAB that toggles this toolbar's expanded state -- the sample's whole subject -- has nothing to drive, and its tap could only report. The bottom-end pill and the vibrant FAB fused to its end are otherwise on the wire. "
     jetpacs-m3-floating-toolbar--harness-note))
   (jetpacs-m3-example
    "CenteredHorizontalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    (concat
     "The scaffold now carries every member this sample varies: floating_toolbar_placement \"bottom_center\", always expanded, floating_toolbar_fab for the vibrant FAB fused to the pill's end, and floating_toolbar_scroll with floating_toolbar_exit_direction \"bottom\" for the scroll behavior that hides the toolbar and its FAB together. "
     jetpacs-m3-floating-toolbar--harness-note))
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
    :unsupported
    (concat
     "floating_toolbar_expanded is a value with no on-change descriptor, so the FAB that toggles this rail's expanded state -- the sample's whole subject -- has nothing to drive. The vertical pill at floating_toolbar_placement \"bottom_end\" and the vibrant FAB fused to its end are otherwise on the wire. "
     jetpacs-m3-floating-toolbar--harness-note))
   (jetpacs-m3-example
    "CenteredVerticalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    (concat
     "The scaffold now carries every member this sample varies: floating_toolbar_orientation \"vertical\" at floating_toolbar_placement \"center_end\", always expanded, floating_toolbar_fab for the fused vibrant FAB, and floating_toolbar_scroll with floating_toolbar_exit_direction \"end\" to hide the rail and its FAB together. "
     jetpacs-m3-floating-toolbar--harness-note))
   ))

(provide 'jetpacs-m3-floating-toolbar)
;;; jetpacs-m3-floating-toolbar.el ends here
