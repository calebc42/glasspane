;;; jetpacs-m3-radio-buttons.el --- Catalog component: Radio buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `RadioButtons' + Examples.kt
;; `RadioButtonsExamples' (2 examples), samples/RadioButtonSamples.kt.
;;
;; Both recreate on `enum_list' `:variant \"radio\"': the same
;; id/options/value/on_change state path the chips form has always
;; carried, rendered as M3 RadioButton targets inside a
;; selectableGroup with the whole row selectable and `onClick = null'
;; on the button -- exactly the semantics hoisting RadioGroupSample
;; exists to teach, done once in the renderer instead of once per app.
;;
;; One seam stated on the pair sample: upstream's two RadioButtons are
;; BARE -- no labels, named only by contentDescription \"Selected\" and
;; \"Unselected\" -- while an enum_list option always carries its
;; label, so the accessible names here are also visible ones.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-radio-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/RadioButtonSamples.kt"
  "Upstream RadioButtonsExampleSourceUrl.")

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
    :build (lambda ()
             ;; Upstream: two bare RadioButtons in one selectableGroup,
             ;; one selected — the Commentary records the label seam.
             (jetpacs-enum-list
              "radio-buttons-pair"
              (list (jetpacs-enum-option "Selected" "selected")
                    (jetpacs-enum-option "Unselected" "unselected"))
              :variant "radio"
              :value "selected"
              :on-change (jetpacs-m3-demo "Radio button"))))
   (jetpacs-m3-example
    "RadioGroupSample"
    "Radio buttons examples"
    :source jetpacs-m3-radio-buttons--source
    :build (lambda ()
             ;; radioOptions = listOf("Calls", "Missed", "Friends"),
             ;; the first selected.
             (jetpacs-enum-list
              "radio-buttons-group"
              (list (jetpacs-enum-option "Calls" "calls")
                    (jetpacs-enum-option "Missed" "missed")
                    (jetpacs-enum-option "Friends" "friends"))
              :variant "radio"
              :value "calls"
              :on-change (jetpacs-m3-demo "Radio group"))))
   ))

(provide 'jetpacs-m3-radio-buttons)
;;; jetpacs-m3-radio-buttons.el ends here
