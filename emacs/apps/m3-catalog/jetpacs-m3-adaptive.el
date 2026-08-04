;;; jetpacs-m3-adaptive.el --- Catalog component: Adaptive -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Adaptive' + Examples.kt
;; `AdaptiveExamples' (7 examples), samples/ThreePaneScaffoldSample.kt.
;;
;; The seven samples are `ListDetailPaneScaffold' or
;; `SupportingPaneScaffold', and as of the `pane_scaffold' node the
;; layout engine under both of them IS on the wire:
;;
;;   (jetpacs-pane-scaffold LIST DETAIL :extra NODE :variant V)
;;
;; The Companion holds the navigator, derives the scaffold directive
;; from its own window and places the panes BY WINDOW SIZE -- side by
;; side where there is room, one at a time where there is not.  That is
;; what these samples exist to demonstrate, and it is why a `row' of two
;; columns was never a substitute: a row is the wide layout ALWAYS, on
;; every screen.  `variant' picks the pane ROLE assignment
;; (list_detail vs supporting), not a different engine.
;;
;; Two build, and they are exactly the two androidx cites as the basic
;; usage of each scaffold -- ListDetailPaneScaffold.kt and
;; SupportingPaneScaffold.kt both introduce theirs with "a basic usage
;; sample, which demonstrates how a layout can change from single pane
;; to dual pane under different window configurations".
;;
;; The other five each miss a member `pane_scaffold' does not have, and
;; the missing member is the sample's own subject:
;;
;;   WithExtraPane          the PaneExpansionAnchor list and the
;;                          VerticalDragHandle -- androidx's own KDoc
;;                          calls this the sample for "an extra pane AND
;;                          pane expansion functionality that allows
;;                          users to drag to change layout split", and
;;                          the node carries the first half only.
;;   ...LevitatedAsDialog   AdaptStrategy.Levitate + LevitatedPaneScrim.
;;   ...LevitatedAsBottomSheet  Levitate to DockedEdge.Bottom with a
;;                          DragToResizeState handle.
;;   ...WithNavigation2     BackNavigationBehavior over the scaffold's
;;                          own pane history.
;;   ...WithNavigation3     ListDetailSceneStrategy placing Navigation 3
;;                          back-stack entries into the panes.
;;
;; One consequence shapes both recreations.  The navigator is
;; Companion-internal and no verb reaches it, so Emacs cannot say "show
;; the detail pane for item N": each recreation is upstream's FIRST
;; frame (the detail pane in its "No item selected" state), and every
;; card and button reports itself as a snackbar the way the rest of the
;; catalog does.  A pane's own `BasicScreen' is flattened to a title
;; over a card, because a Node tree cannot nest a `scaffold'.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-adaptive--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3-adaptive/samples/src/main/java/androidx/compose/material3/samples/ThreePaneScaffoldSamples.kt"
  "Upstream AdaptiveExampleSourceUrl.")

(defconst jetpacs-m3-adaptive--items '("Item 1" "Item 2" "Item 3")
  "Upstream's list-pane items, shared by both recreated samples.")

(defconst jetpacs-m3-adaptive--card-height 80
  "The dp height upstream gives every ListCard (Modifier.height).")

(defconst jetpacs-m3-adaptive--height 420
  "The dp height the pane scaffold is given on the Example screen.
The screen's body is a scrolling column, which offers a child an
unbounded height; a pane scaffold partitions the height it is handed, so
it is given a definite one here.")

(defun jetpacs-m3-adaptive--list-card (title)
  "One upstream ListCard: an outlined card of a CheckCircle and TITLE.
Upstream flips the icon to Icons.Filled.CheckCircle and the container to
primaryContainer when the card is the navigator's selected item; no verb
reaches that navigator, so every card is drawn unselected, which is the
state upstream itself starts in."
  (jetpacs-with-attrs
   (jetpacs-card
    (jetpacs-row (jetpacs-icon "check_circle")
                 (jetpacs-text title :style "headline")
                 :spacing 12 :align "center")
    :variant "outlined"
    :on-tap (jetpacs-m3-demo title))
   :fill_fraction 1.0
   :height jetpacs-m3-adaptive--card-height))

(defun jetpacs-m3-adaptive--list-pane ()
  "Upstream ListPaneContent: the three ListCards, spaced by 8dp."
  (jetpacs-column (mapcar #'jetpacs-m3-adaptive--list-card
                          jetpacs-m3-adaptive--items)
                  :spacing 8))

(defun jetpacs-m3-adaptive--basic-screen (title &rest children)
  "Upstream BasicScreen: TITLE over a card of CHILDREN, spaced by 12dp.
Upstream is a Scaffold whose TopAppBar holds TITLE and whose body is one
filled Card.  A Node tree cannot nest a `scaffold' inside the Example
screen's own, so the top bar flattens to the title text above the card."
  (jetpacs-column
   (jetpacs-text title :style "title")
   (jetpacs-with-attrs
    (jetpacs-card (jetpacs-column children :spacing 12) :variant "filled")
    :fill_fraction 1.0)
   :spacing 12))

(defun jetpacs-m3-adaptive--detail-pane ()
  "Upstream DetailPaneContent with no item selected.
`selectedItem' is `scaffoldNavigator.currentDestination?.contentKey',
null until the navigator moves; that null branch is upstream's title and
description verbatim, and it is what the sample shows on first frame."
  (jetpacs-m3-adaptive--basic-screen
   "No item selected"
   (jetpacs-text "Select an item from the list.")))

(defun jetpacs-m3-adaptive--list-detail ()
  "Upstream ListDetailPaneScaffoldSample: a list pane beside a detail pane.
The androidx KDoc introduces this one as the basic usage sample showing
\"how a layout can change from single pane to dual pane under different
window configurations\", which is precisely what `pane_scaffold' asks
the Companion for."
  (jetpacs-with-attrs
   (jetpacs-pane-scaffold (jetpacs-m3-adaptive--list-pane)
                          (jetpacs-m3-adaptive--detail-pane)
                          :variant "list_detail")
   :fill_fraction 1.0
   :height jetpacs-m3-adaptive--height))

(defun jetpacs-m3-adaptive--main-pane ()
  "Upstream MainPaneContent: \"My content\", its lorem ipsum, \"Show extra\"."
  (jetpacs-m3-adaptive--basic-screen
   "My content"
   (jetpacs-text
    (concat "lorem ipsum lorem ipsum lorem ipsum lorem ipsum lorem ipsum"
            " lorem ipsum lorem ipsum lorem ipsum lorem ipsum lorem ipsum"
            " lorem ipsum lorem ipsum lorem ipsum "))
   (jetpacs-button "Show extra" (jetpacs-m3-demo "Show extra"))))

(defun jetpacs-m3-adaptive--extra-pane ()
  "Upstream ExtraPaneContent for the supporting sample's one extra item.
`extraItems' is (\"Extra content\") and `selectedItem' is
NavItemData(0, showExtra = true), so upstream's item resolves to
\"Extra content\" and its body to the interpolated sentence below."
  (jetpacs-m3-adaptive--basic-screen
   "Extra content"
   (jetpacs-text "This is extra content about Extra content.")))

(defun jetpacs-m3-adaptive--supporting ()
  "Upstream SupportingPaneScaffoldSample: main, supporting and extra panes.
`:variant \"supporting\"' is M3's other pane ROLE assignment, which is
the whole difference from the list-detail sample; the androidx KDoc
introduces this one, too, as the basic usage sample for the single- to
dual-pane change.  Its pane expansion drag handle is a separate upstream
sample (PaneExpansionDragHandleSample) and is not on the wire."
  (jetpacs-with-attrs
   (jetpacs-pane-scaffold (jetpacs-m3-adaptive--main-pane)
                          (jetpacs-m3-adaptive--list-pane)
                          :extra (jetpacs-m3-adaptive--extra-pane)
                          :variant "supporting")
   :fill_fraction 1.0
   :height jetpacs-m3-adaptive--height))

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
    :build #'jetpacs-m3-adaptive--list-detail)
   (jetpacs-m3-example
    "ListDetailPaneScaffoldSampleWithExtraPane"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "The pane_scaffold node has no pane-expansion member: it carries list, detail, extra and variant, so the third pane lands, but the PaneExpansionAnchor list (proportion 0, 240dp from the start, proportion 0.5, 240dp from the end, proportion 1) and the VerticalDragHandle the user drags between those anchors have nothing to ride on, and androidx's own reference calls this the sample for an extra pane AND the pane expansion that lets users drag to change the layout split.")
   (jetpacs-m3-example
    "ListDetailPaneScaffoldSampleWithExtraPaneLevitatedAsDialog"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "The pane_scaffold node has no adapt-strategy member: it says which nodes are the panes and nothing about how a pane behaves when it does not fit, so AdaptStrategy.Levitate floating the extra pane centered over the scaffold behind a LevitatedPaneScrim that dismisses it, and only when the window is single-pane, cannot be asked for.")
   (jetpacs-m3-example
    "SupportingPaneScaffoldSample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :build #'jetpacs-m3-adaptive--supporting)
   (jetpacs-m3-example
    "SupportingPaneScaffoldSampleWithExtraPaneLevitatedAsBottomSheet"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "The pane_scaffold node has no adapt-strategy member: the supporting variant places the three panes, but AdaptStrategy.Levitate with Alignment.BottomCenter and a rememberDragToResizeState(DockedEdge.Bottom) -- the extra pane docking to the bottom edge as a sheet the user drags to resize, under a BottomSheetDefaults.DragHandle -- has no pane member to land on. The scaffold sheet slot does exist now, but it belongs to the CHROME, not to a pane: nothing lets a pane_scaffold hand its extra pane to the host scaffold, and the drag-to-resize state would still have no member.")
   (jetpacs-m3-example
    "ListDetailWithNavigation2Sample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "There is no pane back stack on the wire: the Companion holds the scaffold navigator internally and pane_scaffold carries no back-behavior member, so the four BackNavigationBehaviors this sample exists to compare -- PopUntilScaffoldValueChange, PopUntilCurrentDestinationChange, PopUntilContentChange and PopLatest -- have no pane history to rewind, EBP back popping whole screens off the chrome stack instead.")
   (jetpacs-m3-example
    "ListDetailWithNavigation3Sample"
    "Adaptive examples"
    :source jetpacs-m3-adaptive--source
    :unsupported
    "There is no scene strategy and no pane navigator verb: ListDetailSceneStrategy is what maps Navigation 3 back-stack entries onto the list, detail and extra panes of one window, and pane_scaffold takes all of its panes in a single snapshot with the navigator held Companion-side, so Emacs can neither move a back-stack entry between panes nor supply the detail placeholder a list-only stack shows.")
   ))

(provide 'jetpacs-m3-adaptive)
;;; jetpacs-m3-adaptive.el ends here
