;;; jetpacs-m3-checkboxes.el --- Catalog component: Checkboxes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Checkboxes' + Examples.kt
;; `CheckboxesExamples' (5 examples), samples/CheckboxSamples.kt.
;;
;; The `checkbox' node carries id, checked, label, on_change and enabled
;; -- and nothing else.  `checked' is a plain boolean, and the renderer
;; draws a label as Row(Checkbox, Text), so the bare sample and the
;; with-text sample recreate exactly.  The other three exist to
;; demonstrate a THIRD toggle state (ToggleableState.Indeterminate, via
;; the separate TriStateCheckbox composable) or a STROKE
;; (checkmarkStroke/outlineStroke), and neither has a wire member to
;; carry it.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-checkboxes--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/CheckboxSamples.kt"
  "Upstream CheckboxesExampleSourceUrl.")

(defconst jetpacs-m3-checkboxes--stroke-note
  "The checkbox node has no stroke member: the checkmarkStroke and outlineStroke of CheckboxDefaults.StrokeWidth, with StrokeCap.Round and StrokeJoin.Round, are Companion-side drawing the wire cannot ask for."
  "Why every RoundedStrokes sample is unsupported.")

(defconst jetpacs-m3-checkboxes--tri-state-note
  "There is no tri-state checkbox node, and the checkbox checked member is a plain boolean: ToggleableState.Indeterminate, the parent state this sample exists to show, cannot be put on the wire."
  "Why every TriStateCheckbox sample is unsupported.")

(defun jetpacs-m3-checkboxes--basic ()
  "Upstream CheckboxSample: one Checkbox, remembered as checked."
  (jetpacs-checkbox "checkboxes-basic"
                    :checked t
                    :on-change (jetpacs-m3-demo "Checkbox")))

(defun jetpacs-m3-checkboxes--with-text ()
  "Upstream CheckboxWithTextSample: a Checkbox beside \"Option selection\".
The label member IS that pairing -- the renderer draws a labelled
checkbox as Row(Checkbox, Text), one node carrying one accessible name,
which is what the sample hoists its toggleable onto upstream."
  (jetpacs-checkbox "checkboxes-with-text"
                    :checked t
                    :label "Option selection"
                    :on-change (jetpacs-m3-demo "Option selection")))

(jetpacs-m3-defcomponent "checkboxes"
  :name "Checkboxes"
  :description
  "Checkboxes allow the user to select one or more items from a set or turn an option on or off."
  :guidelines "https://m3.material.io/components/checkboxes"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#checkbox"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Checkbox.kt"
  :examples
  (list
   (jetpacs-m3-example
    "CheckboxSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :build #'jetpacs-m3-checkboxes--basic)
   (jetpacs-m3-example
    "CheckboxWithTextSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :build #'jetpacs-m3-checkboxes--with-text)
   (jetpacs-m3-example
    "CheckboxRoundedStrokesSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :unsupported jetpacs-m3-checkboxes--stroke-note)
   (jetpacs-m3-example
    "TriStateCheckboxSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :unsupported jetpacs-m3-checkboxes--tri-state-note)
   (jetpacs-m3-example
    "TriStateCheckboxRoundedStrokesSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :unsupported
    "Neither half is on the wire: there is no tri-state checkbox node for ToggleableState.Indeterminate, and the checkbox node has no checkmarkStroke or outlineStroke member.")
   ))

(provide 'jetpacs-m3-checkboxes)
;;; jetpacs-m3-checkboxes.el ends here
