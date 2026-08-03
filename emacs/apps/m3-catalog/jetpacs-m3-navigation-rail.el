;;; jetpacs-m3-navigation-rail.el --- Catalog component: Navigation rail -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `NavigationRail' + Examples.kt
;; `NavigationRailExamples' (8 examples), samples/NavigationRailSamples.kt.
;;
;; The `navigation_rail' node (SPEC §17.4) IS the rail: `items' of label,
;; icon and selected; `variant' standard or wide; `expanded' (wide only,
;; the labels beside the icons rather than under them); `arrangement';
;; and a `header' node above the destinations.  Five of the eight samples
;; vary exactly one of those members and nothing else -- the plain rail,
;; the bottom-aligned one, the wide rail collapsed, the wide rail
;; expanded, and the arrangements demo -- so all five are recreated.
;;
;; All eight list the SAME three destinations: "Home", "Search" and
;; "Settings", against Filled/Outlined Home, Favorite and Star glyphs
;; that upstream never bothers to match to those labels, with
;; selectedItem = 0.  Two upstream details survive only in the state the
;; samples open in.  Selection never moves, because every handler here is
;; `jetpacs-m3-demo' and no component module registers actions.  And
;; Filled.Home and Outlined.Home are one `home' name on the wire -- a
;; collapse that only shows in a state these samples never reach, since
;; Favorite/FavoriteBorder and Star/StarBorder each have their own name
;; and the two unselected destinations keep their outlined glyphs.
;;
;; Three stay unsupported, and none of them for want of a rail.
;; `expanded' is the value a rail is BUILT at, not a state: there is no
;; hook beside it to expand or collapse a rail already on screen, and
;; nothing comes back saying what one is doing, which is the whole of
;; WideNavigationRailResponsiveSample -- it exists to animate between the
;; two values from a header tap and print `isAnimating' and the current
;; value beside the rail.  And `variant' is standard or wide only:
;; ModalWideNavigationRail is a third rail, scrimmed and elevated over
;; the app's content, which the other two samples drive open and shut
;; from a header tap, a body button and a destination tap.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-navigation-rail--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/NavigationRailSamples.kt"
  "Upstream NavigationRailExampleSourceUrl.")

(defconst jetpacs-m3-navigation-rail--items
  '(("Home" "home" "home")
    ("Search" "favorite" "favorite_border")
    ("Settings" "star" "star_border"))
  "The three destinations every sample in NavigationRailSamples.kt lists.
Each entry is (LABEL SELECTED-ICON UNSELECTED-ICON): upstream `items'
against `selectedIcons' (Filled Home, Favorite, Star) and
`unselectedIcons' (Outlined Home, FavoriteBorder, StarBorder) -- glyphs
upstream never matches to the labels beside them.  The wire has one
`home' name, so Home reads the same in either state.")

(defconst jetpacs-m3-navigation-rail--selected 0
  "The destination the samples open on: upstream selectedItem = 0, Home.
Tapping selects upstream; here every handler is `jetpacs-m3-demo', so
the selection stays where the sample put it.")

(defconst jetpacs-m3-navigation-rail--height 360
  "The height in dp every rail in this module is given.
Upstream a rail fills the screen height it is the leading edge of.  The
Example screen centers its sample inside a scrolling column, which
leaves a rail's height unbounded -- and an unbounded rail wraps its
destinations, leaving `arrangement' nothing to arrange them within,
which is the entire subject of two of these samples.")

(defun jetpacs-m3-navigation-rail--destinations ()
  "The three destinations as `jetpacs-rail-item's, the first one selected.
Upstream\\='s `items.forEachIndexed { index, item -> ... }' with its
`selected = selectedItem == index' and the filled/outlined glyph swap
that follows from it."
  (let ((index -1))
    (mapcar (lambda (spec)
              (setq index (1+ index))
              (let ((selected (= index jetpacs-m3-navigation-rail--selected)))
                (jetpacs-rail-item (nth 0 spec)
                                   (if selected (nth 1 spec) (nth 2 spec))
                                   (jetpacs-m3-demo (nth 0 spec))
                                   :selected (and selected t))))
            jetpacs-m3-navigation-rail--items)))

(defun jetpacs-m3-navigation-rail--rail (&rest options)
  "The three destinations as one rail node, taking rail OPTIONS.
OPTIONS go to `jetpacs-navigation-rail'; the height is
`jetpacs-m3-navigation-rail--height' for every sample here."
  (jetpacs-with-attrs
   (apply #'jetpacs-navigation-rail
          (jetpacs-m3-navigation-rail--destinations) options)
   :height jetpacs-m3-navigation-rail--height))

(defun jetpacs-m3-navigation-rail--standard ()
  "Upstream NavigationRailSample.
A NavigationRail of three NavigationRailItems with Home selected -- the
standard variant, which is the node\\='s default, so the destinations are
the whole sample.  Upstream gives each icon its own destination label as
its contentDescription; `jetpacs-rail-item' has no content-description
member, and the label the item already carries is what is announced."
  (jetpacs-m3-navigation-rail--rail))

(defun jetpacs-m3-navigation-rail--bottom-align ()
  "Upstream NavigationRailBottomAlignSample.
The sample is one line -- a `Spacer(Modifier.weight(1f))' as the rail\\='s
first child, pushing the destinations to its bottom -- and that is
`:arrangement \"bottom\"', the member the Companion resolves to the very
`Arrangement.Bottom' the weighted spacer stands in for."
  (jetpacs-m3-navigation-rail--rail :arrangement "bottom"))

(defun jetpacs-m3-navigation-rail--wide-collapsed ()
  "Upstream WideNavigationRailCollapsedSample.
A WideNavigationRail whose items are railExpanded = false: collapsed is
the node\\='s default too, so the wide variant is the whole sample -- the
same three destinations drawn icon-above-label in a rail wider than the
standard one."
  (jetpacs-m3-navigation-rail--rail :variant "wide"))

(defun jetpacs-m3-navigation-rail--wide-expanded ()
  "Upstream WideNavigationRailExpandedSample.
The same rail built at WideNavigationRailValue.Expanded, which is
`:expanded t' -- a member the constructor accepts only on the wide
variant, because only that rail can open out and set the labels beside
the icons instead of under them."
  (jetpacs-m3-navigation-rail--rail :variant "wide" :expanded t))

(defun jetpacs-m3-navigation-rail--header ()
  "The rail header of upstream WideNavigationRailArrangementsSample.
A menu IconButton 24dp in from the start edge, inside a TooltipBox whose
PlainTooltip carries `headerDescription' -- \"Expand rail\", because the
rail starts collapsed, which is also why the glyph is Filled.Menu rather
than MenuOpen.  Upstream additionally announces the rail\\='s own state
from this button (`stateDescription' \"Collapsed\"); an icon_button
carries one content_description and no state description."
  (jetpacs-tooltip
   "Expand rail"
   (jetpacs-with-attrs
    (jetpacs-icon-button "menu" (jetpacs-m3-demo "Expand rail")
                         :content-description "Expand rail")
    :pad (list :start 24))))

(defun jetpacs-m3-navigation-rail--arrangements ()
  "Upstream WideNavigationRailArrangementsSample.
A wide rail at `Arrangement.Center' -- the arrangement the sample opens
on -- with its header menu button, beside the weighted Column that names
the arrangement to change to.  The Button reads \"Bottom\" for the same
reason: `changeToString' is the arrangement it would move to, and the
move does not happen here, exactly as the selection does not."
  (jetpacs-row
   (jetpacs-m3-navigation-rail--rail
    :variant "wide" :arrangement "center"
    :header (jetpacs-m3-navigation-rail--header))
   (jetpacs-with-attrs
    (jetpacs-column
     (jetpacs-with-attrs (jetpacs-text "Change arrangement to:") :padding 16)
     (jetpacs-with-attrs (jetpacs-button "Bottom" (jetpacs-m3-demo "Bottom"))
                         :padding 4)
     (jetpacs-with-attrs
      (jetpacs-text
       "Note: This demo is best shown in portrait mode, as landscape mode may result in a compact height in certain devices. For any compact screen dimensions, use a Navigation Bar instead.")
      :padding 16)
     :align "center")
    :weight 1)
   :fill t))

(jetpacs-m3-defcomponent "navigation-rail"
  :name "Navigation rail"
  :description
  "Navigation rails provide access to primary destinations in apps when using tablet and desktop screens."
  :guidelines "https://m3.material.io/components/navigation-rail"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#navigationrail"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/NavigationRail.kt"
  :examples
  (list
   (jetpacs-m3-example
    "WideNavigationRailResponsiveSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported
    "The navigation_rail node has no rail state: expanded is the value a rail is built at, there is no hook beside it to expand or collapse one already on screen, and nothing is reported back -- while this sample exists to animate WideNavigationRailState between the two values from a header tap and print its isAnimating flag and current value beside the rail.")
   (jetpacs-m3-example
    "ModalWideNavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported
    "navigation_rail.variant is standard or wide only: ModalWideNavigationRail is the third rail, the one that stays a narrow icon rail when collapsed and expands into a scrimmed panel elevated over the app's content, and neither that variant nor the expandedHeaderTopPadding that aligns its header across the animation is on the wire.")
   (jetpacs-m3-example
    "DismissibleModalWideNavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported
    "navigation_rail.variant has no modal value and the node has no open state: this sample's subject is a hideOnCollapse modal rail that is entirely offscreen until a body button expands it and slides away again when a destination tap collapses it, and the wire can ask for neither the modal variant nor the expansion that button drives.")
   (jetpacs-m3-example
    "WideNavigationRailCollapsedSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :build #'jetpacs-m3-navigation-rail--wide-collapsed)
   (jetpacs-m3-example
    "WideNavigationRailExpandedSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :build #'jetpacs-m3-navigation-rail--wide-expanded)
   (jetpacs-m3-example
    "WideNavigationRailArrangementsSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :build #'jetpacs-m3-navigation-rail--arrangements)
   (jetpacs-m3-example
    "NavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :build #'jetpacs-m3-navigation-rail--standard)
   (jetpacs-m3-example
    "NavigationRailBottomAlignSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :build #'jetpacs-m3-navigation-rail--bottom-align)
   ))

(provide 'jetpacs-m3-navigation-rail)
;;; jetpacs-m3-navigation-rail.el ends here
