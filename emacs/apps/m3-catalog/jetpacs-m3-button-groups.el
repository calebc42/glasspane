;;; jetpacs-m3-button-groups.el --- Catalog component: Button Groups -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `ButtonGroups' + Examples.kt
;; `ButtonGroupsExamples' (4 examples), samples/ButtonGroupSamples.kt.
;;
;; The component's own description is the whole triage: "a container for
;; material components that adds an animation on press".  What a button
;; group contributes over the buttons inside it is CONTAINER BEHAVIOUR —
;; the neighbour-squeeze animation, the measure-time overflow into a
;; menu, and the connected leading/middle/trailing corner shapes that
;; make the members read as one control.  None of that is on the wire:
;; there is no `button_group' node type, `row', `column' and `flow_row'
;; carry only spacing/align/arrange, the `button' node has no shape
;; member, and the one shape member that does exist (`surface' :shape)
;; is the three-value enum rounded/rounded_small/circle, with no
;; per-corner CornerSize.
;;
;; Three of the four samples are also built from `ToggleButton', whose
;; checked/onCheckedChange pair has no wire member either (see
;; jetpacs-m3-togglebuttons.el).  An `enum_list' does draw a FlowRow of
;; selectable chips with its state held Companion-side, so the plain
;; single-select and multi-select behaviour would survive — but chips
;; are the subject of the Chips page, an `enum_option' carries only a
;; label and a value (no icon for the Outlined-to-Filled swap these
;; samples drive from checked), and nothing about a CONNECTED group
;; would be visible.  That is a lookalike, not a recreation, so all four
;; examples say what is missing instead.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-button-groups--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ButtonGroupSamples.kt"
  "Upstream ButtonGroupsExampleSourceUrl.")

(defconst jetpacs-m3-button-groups--connected-note
  "An enum_list would carry the selection itself, but not what makes this a connected button group: the per-corner :corner attribute gives radii but not the ButtonGroupDefaults.connectedLeadingButtonShapes, connectedMiddleButtonShapes and connectedTrailingButtonShapes those buttons animate between on press, there is no toggle_button node holding the checked state those shapes animate between, and an enum_option carries only a label and a value, so the Outlined-to-Filled icon swap per option has no wire member either."
  "Why both ConnectedButtonGroupWithFlowLayout samples are unsupported.")

(jetpacs-m3-defcomponent "button-groups"
  :name "Button Groups"
  :description
  "button groups is a container for material components that adds an animation on press"
  :guidelines "https://m3.material.io/components/button-groups"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#buttongroups"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ButtonGroup.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ButtonGroupSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :unsupported
    "There is no button_group node type: the row node carries only spacing, align, arrange, scroll and fill, so neither the press animation this container exists to add nor the measure-time move of the clickableItems that do not fit into a ButtonGroupDefaults.OverflowIndicator menu can be asked for from Emacs, and Emacs cannot compute that split because it never sees the available width.")
   (jetpacs-m3-example
    "SingleSelectConnectedButtonGroupWithFlowLayoutSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :unsupported jetpacs-m3-button-groups--connected-note)
   (jetpacs-m3-example
    "MultiSelectConnectedButtonGroupWithFlowLayoutSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :unsupported jetpacs-m3-button-groups--connected-note)
   (jetpacs-m3-example
    "VerticalButtonGroupSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :unsupported
    "Every part of the vertical group is off the wire: no node holds a ToggleButton checked state, no node takes a RoundedCornerShape whose top or bottom corners are copied to CornerSize(100) for the end caps, and the column node's spacing member is validated as a non-negative dp, so the Arrangement.spacedBy((-6).dp) overlap that visually connects the five buttons cannot be expressed.")
   ))

(provide 'jetpacs-m3-button-groups)
;;; jetpacs-m3-button-groups.el ends here
