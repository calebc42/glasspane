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
;; Picker sample recreates exactly.  But the node's members are label,
;; on_pick, value and enabled -- there is no display-mode member and no
;; slot in that Companion-built dialog, so the `TimeInput' variant and
;; the mode-toggling variant have nothing on the wire to carry the one
;; thing each exists to demonstrate.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-time-picker--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TimePicker.kt"
  "Upstream TimePickerExampleSourceUrl.")

(defconst jetpacs-m3-time-picker--input-note
  "The time_button node has no display-mode member: the Companion always fills its picker dialog with an M3 TimePicker clock dial, so TimePickerDisplayMode.Input -- the TimeInput hour and minute text fields this sample exists to show -- cannot be asked for from Emacs."
  "Why TimeInputSample is unsupported.")

(defconst jetpacs-m3-time-picker--toggle-note
  "The time_button node has no display-mode member and its dialog is built entirely by the Companion, so neither the TimePickerDisplayMode this sample flips nor the TimePickerDialogDefaults.DisplayModeToggle button it puts in the dialog can be put on the wire."
  "Why TimePickerSwitchableSample is unsupported.")

(defun jetpacs-m3-time-picker--picker ()
  "Upstream TimePickerSample: a \"Set Time\" button opening the clock dial.
The time_button node IS the whole sample -- the Companion opens an
AlertDialog holding an M3 TimePicker with OK and Cancel and hands the
picked \"HH:MM\" to on_pick, which upstream reports as the
\"Entered time\" snackbar.  Upstream leaves rememberTimePickerState at
its default, so no :value is sent."
  (jetpacs-time-button "Set Time" (jetpacs-m3-demo "Entered time")))

(jetpacs-m3-defcomponent "time-picker"
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
    :unsupported jetpacs-m3-time-picker--input-note)
   (jetpacs-m3-example
    "TimePickerSwitchableSample"
    "Time Picker examples"
    :source jetpacs-m3-time-picker--source
    :unsupported jetpacs-m3-time-picker--toggle-note)
   ))

(provide 'jetpacs-m3-time-picker)
;;; jetpacs-m3-time-picker.el ends here
