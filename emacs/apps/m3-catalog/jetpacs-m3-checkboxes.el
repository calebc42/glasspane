;;; jetpacs-m3-checkboxes.el --- Catalog component: Checkboxes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Checkboxes' + Examples.kt
;; `CheckboxesExamples' (5 examples), samples/CheckboxSamples.kt.
;;
;; The `checkbox' node carries id, checked, label, on_change, enabled --
;; and now `state' and `stroke'.  `checked' is a plain boolean and the
;; renderer draws a label as Row(Checkbox, Text), so the bare sample and
;; the with-text sample recreate exactly.  `:state' is the tri-state form
;; (TriStateCheckbox over off/on/indeterminate, a different §13.6 value
;; schema, which is why it is not a widened boolean), and `:stroke'
;; reaches the checkmarkStroke/outlineStroke pair, so the other three
;; recreate too.
;;
;; One seam stated for the two TriState samples: upstream DERIVES the
;; parent's state from its two children per frame and a parent click
;; writes both children.  On the wire each of the three boxes holds its
;; own state on the device, and nothing links them — the linkage would
;; be an Emacs round trip re-pushing with reset epochs, which is
;; ordinary EBP but not what these samples demonstrate.  What they
;; demonstrate — the third state, and the rounded strokes — rides.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-checkboxes--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/CheckboxSamples.kt"
  "Upstream CheckboxesExampleSourceUrl.")

(defconst jetpacs-m3-checkboxes--rounded-stroke
  (list :cap "round" :join "round")
  "Upstream's checkmark stroke: CheckboxDefaults.StrokeWidth, Round/Round.
The width key is omitted -- the renderer's default IS StrokeWidth.")

(defun jetpacs-m3-checkboxes--tri-family (suffix &optional stroke)
  "The shared body of both TriState samples, ids suffixed with SUFFIX.
The parent \"Receive Emails\" tri-state box over the \"Daily\" and
\"Weekly\" children, both starting checked -- so the parent starts on,
exactly as upstream's derivation does.  STROKE dresses all three."
  (jetpacs-column
   (jetpacs-checkbox (concat "checkboxes-parent-" suffix)
                     :state "on"
                     :stroke stroke
                     :label "Receive Emails"
                     :on-change (jetpacs-m3-demo "Receive Emails"))
   (jetpacs-with-attrs
    (jetpacs-column
     (jetpacs-checkbox (concat "checkboxes-daily-" suffix)
                       :checked t
                       :stroke stroke
                       :label "Daily"
                       :on-change (jetpacs-m3-demo "Daily"))
     (jetpacs-checkbox (concat "checkboxes-weekly-" suffix)
                       :checked t
                       :stroke stroke
                       :label "Weekly"
                       :on-change (jetpacs-m3-demo "Weekly"))
     :spacing 4)
    :pad (list :start 24))
   :spacing 12))

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

(defun jetpacs-m3-checkboxes--rounded-strokes ()
  "Upstream CheckboxRoundedStrokesSample: CheckboxSample, rounded.
The one thing that differs from the bare sample is the stroke pair --
Round cap and Round join, on the checkmark and on the outline both --
which is what `:stroke' reaches.  The width is left out on purpose: the
renderer's own default already IS CheckboxDefaults.StrokeWidth."
  (jetpacs-checkbox "checkboxes-rounded"
                    :checked t
                    :stroke jetpacs-m3-checkboxes--rounded-stroke
                    :on-change (jetpacs-m3-demo "Checkbox")))

(defun jetpacs-m3-checkboxes--tri-state ()
  "Upstream TriStateCheckboxSample: the parent box over Daily and Weekly.
`:state' is the third value -- off/on/indeterminate, a schema of its own
rather than a widened boolean -- and the \"Receive Emails\" parent is the
box that wears it.  That third state is what rides; what does not is
upstream's per-frame derivation of the parent from its two children,
the seam stated in this module's Commentary."
  (jetpacs-m3-checkboxes--tri-family "plain"))

(defun jetpacs-m3-checkboxes--tri-state-rounded-strokes ()
  "Upstream TriStateCheckboxRoundedStrokesSample: that family, rounded.
Nothing changes but the stroke pair, and it dresses all three boxes,
the tri-state parent included.  The ids carry a \"rounded\" suffix so
this family's boxes stay distinct on the wire from the plain family's
-- each box holds its own state on the device."
  (jetpacs-m3-checkboxes--tri-family
   "rounded" jetpacs-m3-checkboxes--rounded-stroke))

(jetpacs-m3-defcomponent "checkboxes"
  :builders (list #'jetpacs-checkbox)
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
    :build #'jetpacs-m3-checkboxes--rounded-strokes)
   (jetpacs-m3-example
    "TriStateCheckboxSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :build #'jetpacs-m3-checkboxes--tri-state)
   (jetpacs-m3-example
    "TriStateCheckboxRoundedStrokesSample"
    "Checkboxes examples"
    :source jetpacs-m3-checkboxes--source
    :build #'jetpacs-m3-checkboxes--tri-state-rounded-strokes)
   ))

(provide 'jetpacs-m3-checkboxes)
;;; jetpacs-m3-checkboxes.el ends here
