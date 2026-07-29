;;; jetpacs-m3-radio-buttons.el --- Catalog component: Radio buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `RadioButtons' + Examples.kt
;; `RadioButtonsExamples' (2 examples), samples/RadioButtonSamples.kt.
;;
;; RadioButton is an M3 component Jetpacs does not wrap
;; (docs/lookup-tables/M3-COMPONENT-LOOKUP.org lists it "Available", with
;; a `radio_group' wire type as future work), and both samples exist to
;; demonstrate the radio target itself: the selected/unselected circle,
;; and the `Modifier.selectableGroup' / `Role.RadioButton' semantics that
;; make a set of them one exclusive choice.
;;
;; The nearest wrapped node is `enum_list' with multi_select false, which
;; really does carry "one value out of an authored set".  It is NOT a
;; recreation of these samples: the renderer draws it as a FlowRow of
;; FilterChips (InputNodes.kt RenderEnumList), so it would substitute the
;; Chips component -- which the catalog already lists -- for the very
;; control this component is about.  Both examples say so instead.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-radio-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/RadioButtonSamples.kt"
  "Upstream RadioButtonsExampleSourceUrl.")

(defconst jetpacs-m3-radio-buttons--no-node-note
  "There is no radio button or radio group node type: the selected/unselected radio target this sample exists to show has no wire representation, and enum_list with multi_select false -- the only single-choice node -- renders as a FlowRow of FilterChips, a different control."
  "Why every RadioButton sample is unsupported.")

(jetpacs-m3-defcomponent "radio-buttons"
  :name "Radio buttons"
  :description
  "Radio buttons allow the user to select one option from a set."
  :guidelines "https://m3.material.io/components/radio-buttons"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#radiobutton"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/RadioButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "RadioButtonSample"
    "Radio buttons examples"
    :source jetpacs-m3-radio-buttons--source
    :unsupported jetpacs-m3-radio-buttons--no-node-note)
   (jetpacs-m3-example
    "RadioGroupSample"
    "Radio buttons examples"
    :source jetpacs-m3-radio-buttons--source
    :unsupported
    "Neither half is on the wire: there is no radio button node for the \"Calls\"/\"Missed\"/\"Friends\" rows to carry, and no semantics member for the Modifier.selectable(role = Role.RadioButton) hoisting, with onClick = null on the button, that this sample exists to teach.")
   ))

(provide 'jetpacs-m3-radio-buttons)
;;; jetpacs-m3-radio-buttons.el ends here
