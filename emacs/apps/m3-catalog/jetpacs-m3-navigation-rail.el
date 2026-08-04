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
;; The state loop closed the last three.  `:expanded' is SYNCED
;; authored state now -- a re-push whose value changed animates the
;; open rail, and a settle the author did not write reports back
;; through `:on-expand-change' -- so the Responsive sample's header
;; tap is a real Emacs round trip on the flag verb.  `:variant
;; \"modal\"' is ModalWideNavigationRail, scrimmed and elevated over
;; the content, and `:hide-on-collapse' is its dismissible form,
;; offscreen until a body button opens it.  All eight build.
;;
;; One seam stated on the Responsive sample: upstream also prints
;; WideNavigationRailState's `isAnimating' beside the rail, and the
;; animation internals stay Companion-local -- the two settled values
;; are what ride the wire.

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

(defun jetpacs-m3-navigation-rail--live-header (flag)
  "A rail header whose menu button flips sample FLAG — the live toggle.
The tooltip and the accessible name track the state, as upstream's
headerDescription does."
  (let ((label (if (jetpacs-m3-flag flag) "Collapse rail" "Expand rail")))
    (jetpacs-tooltip
     label
     (jetpacs-with-attrs
      (jetpacs-icon-button "menu" (jetpacs-m3-flag-action flag)
                           :content-description label)
      :pad (list :start 24)))))

(defun jetpacs-m3-navigation-rail--responsive ()
  "Upstream WideNavigationRailResponsiveSample: the header tap animates.
The header's menu button flips a flag, the verb re-pushes, and the
SYNCED `:expanded' animates the open rail between its two values —
the state loop this sample exists for, as a real Emacs round trip.
One seam stated: upstream also prints WideNavigationRailState's
isAnimating flag beside the rail, and the animation internals stay
Companion-local; the two settled values are what ride the wire."
  (let ((open (and (jetpacs-m3-flag "rail-open") t)))
    (jetpacs-m3-navigation-rail--rail
     :variant "wide"
     :expanded (if open t :json-false)
     :on-expand-change (jetpacs-m3-flag-action "rail-open")
     :header (jetpacs-m3-navigation-rail--live-header "rail-open"))))

(defun jetpacs-m3-navigation-rail--modal ()
  "Upstream ModalWideNavigationRailSample.
`:variant \"modal\"' stays a narrow icon rail when collapsed and
expands into a scrimmed panel elevated over the content; a scrim
dismissal reports through `:on-expand-change', which keeps the flag —
and so the next push — honest."
  (let ((open (and (jetpacs-m3-flag "modal-rail") t)))
    (jetpacs-m3-navigation-rail--rail
     :variant "modal"
     :expanded (if open t :json-false)
     :on-expand-change (jetpacs-m3-flag-action "modal-rail")
     :header (jetpacs-m3-navigation-rail--live-header "modal-rail"))))

(defun jetpacs-m3-navigation-rail--dismissible-modal ()
  "Upstream DismissibleModalWideNavigationRailSample.
`:hide-on-collapse' keeps the modal rail entirely offscreen until the
body's menu button expands it; collapsing — scrim or destination tap —
slides it away and reports back through `:on-expand-change'."
  (let ((open (and (jetpacs-m3-flag "dismissible-rail") t)))
    (jetpacs-row
     (jetpacs-navigation-rail
      (jetpacs-m3-navigation-rail--destinations)
      :variant "modal"
      :hide-on-collapse t
      :expanded (if open t :json-false)
      :on-expand-change (jetpacs-m3-flag-action "dismissible-rail"))
     (jetpacs-with-attrs
      (jetpacs-column
       (jetpacs-icon-button "menu"
                            (jetpacs-m3-flag-action "dismissible-rail")
                            :content-description "Open rail")
       (jetpacs-text "Tap the menu icon to open the rail")
       :spacing 8)
      :weight 1 :padding 16)
     :align "top" :fill t)))

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
    :build #'jetpacs-m3-navigation-rail--responsive)
   (jetpacs-m3-example
    "ModalWideNavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :build #'jetpacs-m3-navigation-rail--modal)
   (jetpacs-m3-example
    "DismissibleModalWideNavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :build #'jetpacs-m3-navigation-rail--dismissible-modal)
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
