;;; jetpacs-m3-navigation-rail.el --- Catalog component: Navigation rail -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `NavigationRail' + Examples.kt
;; `NavigationRailExamples' (8 examples), samples/NavigationRailSamples.kt.
;;
;; M3-COMPONENT-LOOKUP lists NavigationRail as available-but-unwrapped:
;; there is no `navigation_rail' node, and the scaffold's navigation
;; slots are `top_bar', `bottom_bar' and `drawer' -- none of them a
;; full-height column of destinations at the leading edge, which is the
;; one thing every sample in this file exists to show.  Three draw that
;; column (NavigationRail, WideNavigationRail collapsed, and expanded),
;; three drive its `WideNavigationRailState' from a header toggle
;; (responsive, modal, arrangements), one bottom-aligns it with a
;; weighted Spacer, and one hides it on collapse.  All eight are
;; unsupported.
;;
;; None of them is screen chrome in the scaffold-slot sense either.  A
;; rail is not a bottom bar -- these samples print their own note saying
;; to use a Navigation Bar instead when the screen is compact, so the
;; rail IS the not-a-bottom-bar case -- and the `drawer' slot is a
;; ModalNavigationDrawer sheet opened by the Companion-local hamburger
;; and closed by its scrim, with no wire member to expand or collapse
;; it, which is precisely what the two modal samples drive from a body
;; button and an item tap.  Nor can a rail item be faked: `selected'
;; exists on `chip' and `month_grid' only, so a column of icon buttons
;; would drop the active indicator and the filled/outlined icon swap
;; that carry the selection in all eight.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-navigation-rail--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/NavigationRailSamples.kt"
  "Upstream NavigationRailExampleSourceUrl.")

(defconst jetpacs-m3-navigation-rail--wide-note
  "There is no navigation_rail node type on the wire: WideNavigationRail has no wire equivalent, and no node carries a WideNavigationRailItem's selected state or the active indicator its railExpanded form draws around the icon and label."
  "Why the plain collapsed and expanded wide-rail samples are unsupported.")

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
    "There is no navigation_rail node and no rail state on the wire: this sample exists to show WideNavigationRailState responding to a header toggle, down to the isAnimating flag it prints beside the rail, and no node member expands or collapses anything.")
   (jetpacs-m3-example
    "ModalWideNavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported
    "The scaffold drawer slot is a ModalNavigationDrawer sheet, not a modal rail: ModalWideNavigationRail stays on screen as a narrow icon rail when collapsed and takes an expandedHeaderTopPadding, and neither has a wire member.")
   (jetpacs-m3-example
    "DismissibleModalWideNavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported
    "The scaffold drawer opens only from the Companion-local hamburger and closes only by its scrim: this sample's subject is a hideOnCollapse rail that a body button expands and an item tap collapses, and no wire member drives that open state.")
   (jetpacs-m3-example
    "WideNavigationRailCollapsedSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported jetpacs-m3-navigation-rail--wide-note)
   (jetpacs-m3-example
    "WideNavigationRailExpandedSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported jetpacs-m3-navigation-rail--wide-note)
   (jetpacs-m3-example
    "WideNavigationRailArrangementsSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :expressive t
    :unsupported
    "There is no navigation_rail node and so no arrangement member: swapping the rail's vertical Arrangement between Center and Bottom is the whole subject of this sample, and a column's arrange member positions body content, not rail destinations.")
   (jetpacs-m3-example
    "NavigationRailSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :unsupported
    "There is no navigation_rail node type on the wire: a full-height column of destinations at the leading edge is not one of the scaffold slots (top_bar, bottom_bar, fab, floating_toolbar, drawer), and icon_button has no selected member for a NavigationRailItem's active indicator.")
   (jetpacs-m3-example
    "NavigationRailBottomAlignSample"
    "Navigation rail examples"
    :source jetpacs-m3-navigation-rail--source
    :unsupported
    "There is no navigation_rail node type for the Spacer to push against: the weighted spacer is the only half of this sample on the wire, and bottom-aligning items inside a rail that cannot be drawn demonstrates nothing.")
   ))

(provide 'jetpacs-m3-navigation-rail)
;;; jetpacs-m3-navigation-rail.el ends here
