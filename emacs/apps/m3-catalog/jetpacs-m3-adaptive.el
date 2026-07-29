;;; jetpacs-m3-adaptive.el --- Catalog component: Adaptive -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Adaptive' + Examples.kt
;; `AdaptiveExamples' (7 examples), samples/ThreePaneScaffoldSample.kt.
;;
;; All seven samples are `ListDetailPaneScaffold' or
;; `SupportingPaneScaffold' -- the material3-adaptive artifact, which
;; M3-COMPONENT-LOOKUP does not list among the thirty wrapped
;; components.  Every one of them is driven by
;; `calculatePaneScaffoldDirective(currentWindowAdaptiveInfo())': the
;; panes sit side by side on an expanded window and collapse to one
;; pane, with a navigator, on a phone.  That adaptation IS the subject
;; -- the component's own upstream description says the sample "is
;; better experienced in a resizable emulator or foldable device".
;;
;; Two separate wire members would be needed and neither exists.  The
;; `scaffold' node (§17.6) has exactly top_bar, body, bottom_bar, fab,
;; floating_toolbar, drawer, snackbar and on_refresh -- named chrome
;; slots, no pane roles, no directive, no adapt strategy.  And nothing
;; ever tells Emacs the window size class: ADAPTIVE-REFERENCE.org
;; describes a `device_state_update' payload and a `jetpacs-responsive'
;; constructor, but both are written there as PROPOSALS, and neither
;; the contract nor `jetpacs-widgets' has them.  A Node tree is built
;; in Emacs with no idea how wide the window it lands in is.
;;
;; So a row of two columns would render, and would be exactly the
;; lookalike the fidelity rule forbids: it would show the arrangement
;; these samples adapt AWAY from, and demonstrate none of the adapting.
;; Seven for seven unsupported, each naming what it would take.
;;
;; The reasons differ past that shared floor: the samples pile pane
;; expansion anchors with a draggable handle, `AdaptStrategy.Levitate'
;; as a scrimmed dialog, Levitate as a drag-to-resize bottom sheet,
;; `BackNavigationBehavior' over the scaffold's own history, and a
;; Navigation 3 `ListDetailSceneStrategy' on top of it.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-adaptive--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3-adaptive/samples/src/main/java/androidx/compose/material3/samples/ThreePaneScaffoldSamples.kt"
  "Upstream AdaptiveExampleSourceUrl.")

(defconst jetpacs-m3-adaptive--pane-note
  "There is no pane-scaffold node: the scaffold node's slots are top_bar, body, bottom_bar, fab, floating_toolbar, drawer, snackbar and on_refresh, with no pane roles, and no wire message reports the window size class to Emacs, so the automatic two- or three-pane adaptation this sample exists to demonstrate cannot be asked for."
  "Why a bare ThreePaneScaffold sample is unsupported.")

(jetpacs-m3-defcomponent "adaptive"
  :name "Adaptive"
  :description
  "Adaptive scaffolds provides automatic layout adjustment on different window size classes and postures.\n\nNote: this sample is better experienced in a resizable emulator or foldable device."
  :guidelines "https://m3.material.io/foundations/layout/understanding-layout/overview"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/adaptive"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3-adaptive/src/commonMain/kotlin/androidx/compose/material3/adaptive/ThreePaneScaffold.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ListDetailPaneScaffoldSample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported jetpacs-m3-adaptive--pane-note)
   (jetpacs-m3-example
    "ListDetailPaneScaffoldSampleWithExtraPane"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "Neither half is on the wire: there is no pane-scaffold node carrying the list, detail and extra roles, and no pane-expansion member for the PaneExpansionAnchor list and the VerticalDragHandle the user drags to re-split the panes.")
   (jetpacs-m3-example
    "ListDetailPaneScaffoldSampleWithExtraPaneLevitatedAsDialog"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "There is no pane-scaffold node and no dialog node: AdaptStrategy.Levitate floating the extra pane centered behind a dismissing LevitatedPaneScrim is Companion-side layout, and a dialog reaches the screen through the ebp-client-dialog-show verb, never as a node a tree can place.")
   (jetpacs-m3-example
    "SupportingPaneScaffoldSample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported jetpacs-m3-adaptive--pane-note)
   (jetpacs-m3-example
    "SupportingPaneScaffoldSampleWithExtraPaneLevitatedAsBottomSheet"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "There is no pane-scaffold node and no bottom-sheet node: BottomSheetScaffold is available-but-unwrapped, so the extra pane levitating to DockedEdge.Bottom with a DragToResizeState handle has nothing on the wire to carry it.")
   (jetpacs-m3-example
    "ListDetailWithNavigation2Sample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "There is no pane-scaffold node and no pane back stack: BackNavigationBehavior picks how far one back press rewinds the scaffold's own pane history, and EBP back pops whole screens off the chrome stack, so the four behaviors this sample exists to compare have nothing to act on.")
   (jetpacs-m3-example
    "ListDetailWithNavigation3Sample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "There is no pane-scaffold node and no scene strategy: ListDetailSceneStrategy is what places Navigation 3 back-stack entries into the list, detail and extra panes of one window, and the wire offers only a linear stack of whole screens.")
   ))

(provide 'jetpacs-m3-adaptive)
;;; jetpacs-m3-adaptive.el ends here
