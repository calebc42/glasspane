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
;; carry only spacing/align/arrange (plus scroll/fill), and the `button'
;; node's :shape is the two-value round/square enum — no per-corner
;; CornerSize, and the universal :corner attribute decorates the
;; modifier outside minimumInteractiveComponentSize, i.e. the 48dp touch
;; box rather than the button's own container.
;;
;; Three of the four samples are built from `ToggleButton', and half of
;; that pair HAS now landed: `button' takes :checked and :on-change, and
;; the Companion holds the flipped value on the device.  It is still not
;; enough for any of the three, for two different reasons.
;;
;; Two of them — SingleSelect… and Vertical… — want ONE selection across
;; the group (upstream says so out loud: `Role.RadioButton', a single
;; `selectedIndex').  Nothing on the wire binds toggles together; each
;; `button' holds its own device-side value, so checking Work cannot
;; clear the other four, and the mutual exclusion IS the sample.
;;
;; The third — MultiSelect… — wants exactly five independent booleans,
;; which is precisely what :checked carries, so the state model does
;; survive.  What does not survive is every way the user would SEE it: a
;; checked `button' draws exactly like an unchecked one, `button' has no
;; :checked-icon member (only `icon_button' does), and IconMap resolves
;; every wire icon name through `Icons.Outlined.<Name>', so the
;; Outlined-to-Filled glyph swap all three samples drive from checked
;; has no filled name to swap to.  Five buttons that pop a toast and
;; never change appearance demonstrate neither the multi-select nor the
;; group — a lookalike, not a recreation.
;;
;; So all four examples still say what is missing; three of the four
;; reasons had to be rewritten, because "no wire member holds the
;; checked state" is no longer true.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-button-groups--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ButtonGroupSamples.kt"
  "Upstream ButtonGroupsExampleSourceUrl.")

(defconst jetpacs-m3-button-groups--connected-shape-note
  "The connected look has no member either: button.shape is the two-value round/square enum, nothing carries ButtonGroupDefaults.connectedLeadingButtonShapes, connectedMiddleButtonShapes or connectedTrailingButtonShapes, and the per-corner :corner attribute decorates the 48dp touch box rather than the button's own container, so the members cannot be made to read as one control."
  "The half of the triage both connected samples share.")

(defconst jetpacs-m3-button-groups--single-note
  (concat
   "The button node now carries checked and on_change, so each of the five options holds its own state on the device — but nothing groups them: there is no button_group node and no wire member that makes several toggles one selection, so checking Work cannot clear the other four, and that mutual exclusion (upstream marks every button Role.RadioButton, driven from one selectedIndex) is the single-select this sample exists to demonstrate. "
   jetpacs-m3-button-groups--connected-shape-note
   " Nor would the selection be visible: a checked button draws exactly like an unchecked one, the button node has no checked_icon member (only icon_button has one), and IconMap resolves every wire icon name through Icons.Outlined, so the Outlined-to-Filled swap each option makes when checked has no filled glyph to name.")
  "Why SingleSelectConnectedButtonGroupWithFlowLayoutSample is unsupported.")

(defconst jetpacs-m3-button-groups--multi-note
  (concat
   "This sample's selection model is five independent booleans, and the button node's new checked and on_change members carry exactly that, so the state survives — what does not survive is every way the user would see it. A checked button draws exactly like an unchecked one, the button node has no checked_icon member (only icon_button has one), and IconMap resolves every wire icon name through Icons.Outlined.<Name>, so the Outlined-to-Filled swap each option makes when checked has no filled glyph to name. "
   jetpacs-m3-button-groups--connected-shape-note
   " Five buttons that pop a toast and never change appearance would demonstrate neither the multi-select nor the group.")
  "Why MultiSelectConnectedButtonGroupWithFlowLayoutSample is unsupported.")

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
    :unsupported jetpacs-m3-button-groups--single-note)
   (jetpacs-m3-example
    "MultiSelectConnectedButtonGroupWithFlowLayoutSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :unsupported jetpacs-m3-button-groups--multi-note)
   (jetpacs-m3-example
    "VerticalButtonGroupSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :unsupported
    "The button node now carries checked and on_change, but the vertical group needs the rest, and none of it is on the wire: nothing binds several toggles into one selection, so the single selectedIndex this sample drives cannot be expressed; no member takes a RoundedCornerShape whose top or bottom corners are copied to CornerSize(100) for the end caps, nor ButtonGroupDefaults.connectedButtonCheckedShape (button.shape is the two-value round/square enum, and the per-corner :corner attribute decorates the 48dp touch box rather than the button's own container); and the column node's spacing member is validated as a non-negative dp, so the Arrangement.spacedBy((-6).dp) overlap that visually connects the five buttons cannot be asked for.")
   ))

(provide 'jetpacs-m3-button-groups)
;;; jetpacs-m3-button-groups.el ends here
