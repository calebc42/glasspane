;;; jetpacs-m3-date-pickers.el --- Catalog component: Date pickers -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `DatePickers' + Examples.kt
;; `DatePickerExamples' (5 examples), samples/DatePickerSamples.kt.
;;
;; Two date shapes reach the wire.  `date_button' IS M3's
;; DatePickerDialog: the Companion draws a button that opens
;; DatePickerDialog { DatePicker(state) } with OK and Cancel and hands
;; the confirmed day back as an ISO date, so DatePickerDialogSample
;; recreates exactly.  `month_grid' is the inline calendar -- a month
;; header with previous/next navigation, a weekday row, and a day grid
;; carrying one selected day and a day-tap handler -- which is what
;; DatePickerSample puts on screen with its pre-selection.
;;
;; `date_button' also carries `:mode' now, and `input' IS
;; DisplayMode.Input -- the typed date-entry field with M3's own mask
;; and validation -- so DateInputSample recreates.  One seam stated:
;; upstream shows the input field INLINE and the wire's only door to a
;; DatePickerState is the dialog behind `date_button', so the field
;; appears on tap rather than standing in the body (`month_grid', the
;; inline node, draws a calendar only).
;;
;; The day-level bounds close the last two.  `date_button' takes
;; `:min-date'/`:max-date'/`:disabled-weekdays' — the SelectableDates
;; predicate in its only wire-carryable form, a declaration — and
;; `month_grid' takes the same bounds plus `:range-start'/`:range-end',
;; the two-ended selection shaded as one span with rounded caps.  The
;; range sample's live flow is ordinary EBP (each on_day_tap dispatch
;; lets Emacs rebuild the range); the demo verb stands in here.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-date-pickers--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/DatePickerSamples.kt"
  "Upstream DatePickersExampleSourceUrl.")

(defun jetpacs-m3-date-pickers--inline ()
  "Upstream DatePickerSample: an inline DatePicker pre-selecting Jan 4, 2020.
The sample sets initialSelectedDateMillis = 1578096000000 and prints
the selection under the calendar.  The `month_grid' node carries all
three parts the sample uses: the month shown, the pre-selected day, and
a day tap that reports the ISO date it was given."
  (jetpacs-column
   (jetpacs-with-attrs
    (jetpacs-month-grid "2020-01"
                        :selected "2020-01-04"
                        :on-day-tap (jetpacs-m3-demo
                                     "Selected date timestamp"))
    :padding 16)
   (jetpacs-with-attrs
    (jetpacs-text "Selected date timestamp: 1578096000000")
    :align_self "center")
   :spacing 8 :fill t))

(defun jetpacs-m3-date-pickers--dialog ()
  "Upstream DatePickerDialogSample: a DatePickerDialog with OK and Cancel.
The `date_button' node IS that dialog: the Companion opens
DatePickerDialog { DatePicker(state) } behind the button, draws the
sample's own OK and Cancel text buttons, and dispatches the confirmed
date -- which is where the sample's snackbar message comes from.  The
state is `rememberDatePickerState()' with no pre-selection, so no
`:value'."
  (jetpacs-date-button "Select date"
                       (jetpacs-m3-demo "Selected date timestamp")))

(defun jetpacs-m3-date-pickers--selectable-dates ()
  "Upstream DatePickerWithDateSelectableDatesSample: the SelectableDates object.
Upstream hands `rememberDatePickerState' a SelectableDates whose
`isSelectableDate' blocks Sunday and Saturday and whose
`isSelectableYear' allows only year > 2022.  A predicate cannot cross
the wire, so `date_button' takes that pair as a DECLARATION instead --
`:disabled-weekdays' (0 = Sunday, 6 = Saturday) and `:min-date' -- and
the dialog greys and refuses them itself.  The bounds live on a
DatePickerState and the wire's only door to one is the dialog behind
`date_button', the same seam DateInputSample states."
  (jetpacs-date-button "Select date"
                       (jetpacs-m3-demo "Selected date timestamp")
                       :min-date "2023-01-01"
                       :disabled-weekdays (list 0 6)))

(defun jetpacs-m3-date-pickers--input ()
  "Upstream DateInputSample: DisplayMode.Input, the typed date-entry field.
`:mode \"input\"' seeds the dialog's DatePickerState with it, so the tap
lands on M3's own masked MM/DD/YYYY field rather than the calendar; the
dialog keeps its built-in toggle between the two, as the state does
upstream.  The caption is the sample's own selection readout."
  (jetpacs-column
   (jetpacs-date-button "Select date"
                        (jetpacs-m3-demo "Entered date timestamp")
                        :mode "input")
   (jetpacs-with-attrs
    (jetpacs-text "Entered date timestamp: no input")
    :align_self "center")
   :spacing 8 :fill t))

(defun jetpacs-m3-date-pickers--range ()
  "Upstream DateRangePickerSample: the two-ended selection, Jan 4 to Jan 10.
DateRangePicker is not a node type; `month_grid' carries
`:range-start' and `:range-end', which shade the inclusive span as one
run with rounded caps -- the part of the sample there is to see.  The
live flow is ordinary EBP: on_day_tap dispatches each tapped day and
Emacs rebuilds the range on the next push, so the demo verb stands in
for that here.  The caption is upstream's own \"Saved range
\(timestamps)\" snackbar, which its Save button raises once both ends
are set."
  (jetpacs-column
   (jetpacs-with-attrs
    (jetpacs-month-grid "2020-01"
                        :range-start "2020-01-04"
                        :range-end "2020-01-10"
                        :on-day-tap (jetpacs-m3-demo
                                     "Saved range (timestamps)"))
    :padding 16)
   (jetpacs-with-attrs
    (jetpacs-text "Saved range (timestamps): 1578096000000..1578614400000")
    :align_self "center")
   :spacing 8 :fill t))

(jetpacs-m3-defcomponent "date-pickers"
  :builders (list #'jetpacs-date-button)
  :name "Date pickers"
  :description
  "Date pickers let users select a date or range of dates."
  :guidelines "https://m3.material.io/components/datepicker"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#datepicker"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/DatePicker.kt"
  :examples
  (list
   (jetpacs-m3-example
    "DatePickerSample"
    "Date picker examples"
    :source jetpacs-m3-date-pickers--source
    :build #'jetpacs-m3-date-pickers--inline)
   (jetpacs-m3-example
    "DatePickerDialogSample"
    "Date picker examples"
    :source jetpacs-m3-date-pickers--source
    :build #'jetpacs-m3-date-pickers--dialog)
   (jetpacs-m3-example
    "DatePickerWithDateSelectableDatesSample"
    "Date picker examples"
    :source jetpacs-m3-date-pickers--source
    :build #'jetpacs-m3-date-pickers--selectable-dates)
   (jetpacs-m3-example
    "DateInputSample"
    "Date picker examples"
    :source jetpacs-m3-date-pickers--source
    :build #'jetpacs-m3-date-pickers--input)
   (jetpacs-m3-example
    "DateRangePickerSample"
    "Date picker examples"
    :source jetpacs-m3-date-pickers--source
    :build #'jetpacs-m3-date-pickers--range)
   ))

(provide 'jetpacs-m3-date-pickers)
;;; jetpacs-m3-date-pickers.el ends here
