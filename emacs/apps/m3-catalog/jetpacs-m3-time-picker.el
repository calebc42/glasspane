;;; jetpacs-m3-time-picker.el --- Catalog component: Time Picker -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `TimePickers' + Examples.kt
;; `TimePickerExamples' (3 examples), samples/TimePickerSamples.kt.
;;
;; All three samples draw the same screen -- a centered "Set Time"
;; button that opens a `TimePickerDialog' with Ok and Cancel and
;; snackbars the time that came back -- and differ ONLY in the dialog's
;; `TimePickerDisplayMode'.
;;
;; The `time_button' node is that screen: the Companion renders it as an
;; OutlinedButton that opens an AlertDialog around an M3 `TimePicker'
;; with OK and Cancel, handing the chosen "HH:MM" to on_pick.  So the
;; Picker sample recreates exactly.
;;
;; The node's `display_mode' member selects what fills that dialog: the
;; clock dial (`picker'), M3 `TimeInput' -- the keyboard-first HH/MM
;; fields (`input') -- or `switchable', M3's own TimePickerDialog
;; carrying TimePickerDialogDefaults.DisplayModeToggle so the user
;; flips between the two mid-dialog.  All three samples recreate, each
;; naming the mode upstream names.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-time-picker--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TimePicker.kt"
  "Upstream TimePickerExampleSourceUrl.")

(defun jetpacs-m3-time-picker--picker ()
  "Upstream TimePickerSample: a \"Set Time\" button opening the clock dial.
The time_button node IS the whole sample -- the Companion opens an
AlertDialog holding an M3 TimePicker with OK and Cancel and hands the
picked \"HH:MM\" to on_pick, which upstream reports as the
\"Entered time\" snackbar.  Upstream passes TimePickerDisplayMode.Picker
explicitly, so :display-mode says \"picker\" -- the clock dial the
Companion draws.  Upstream leaves rememberTimePickerState at its
default, so no :value is sent."
  (jetpacs-time-button "Set Time" (jetpacs-m3-demo "Entered time")
                       :display-mode "picker"))

(defun jetpacs-m3-time-picker--input ()
  "Upstream TimeInputSample: the same screen with TimeInput in the dialog.
`:display-mode \"input\"' fills the dialog with M3's keyboard-first HH
and MM fields instead of the dial -- TimePickerDisplayMode.Input, the
one thing that separates this sample from TimePickerSample."
  (jetpacs-time-button "Set Time" (jetpacs-m3-demo "Entered time")
                       :display-mode "input"))

(defun jetpacs-m3-time-picker--switchable ()
  "Upstream TimePickerSwitchableSample: the same screen, the dialog toggling.
Upstream assembles TimePickerDialog by hand with `modeToggleButton =
TimePickerDialogDefaults.DisplayModeToggle' and swaps TimePicker for
TimeInput as its own `displayMode' flips.  `:display-mode
\"switchable\"' is that whole arrangement as one enum value: the
Companion raises M3's TimePickerDialog carrying the toggle, and the
mid-dialog flip between dial and typed input is its own.  Everything
else is TimePickerSample -- the centered \"Set Time\" button, Ok and
Cancel, and the \"Entered time\" report on the way back."
  (jetpacs-time-button "Set Time" (jetpacs-m3-demo "Entered time")
                       :display-mode "switchable"))

(jetpacs-m3-defcomponent "time-picker"
  :builders (list #'jetpacs-time-button)
  :name "Time Picker"
  :description
  "Time picker allows the user to choose time of day."
  :guidelines "https://m3.material.io/components/time-picker"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#time-pickers"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/TimePicker.kt"
  :examples
  (list
   (jetpacs-m3-example
    "TimePickerSample"
    "Time Picker examples"
    :source jetpacs-m3-time-picker--source
    :build #'jetpacs-m3-time-picker--picker)
   (jetpacs-m3-example
    "TimeInputSample"
    "Time Picker examples"
    :source jetpacs-m3-time-picker--source
    :build #'jetpacs-m3-time-picker--input)
   (jetpacs-m3-example
    "TimePickerSwitchableSample"
    "Time Picker examples"
    :source jetpacs-m3-time-picker--source
    :build #'jetpacs-m3-time-picker--switchable)
   ))

(provide 'jetpacs-m3-time-picker)
;;; jetpacs-m3-time-picker.el ends here
