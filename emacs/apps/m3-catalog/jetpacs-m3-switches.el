;;; jetpacs-m3-switches.el --- Catalog component: Switches -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Switches' + Examples.kt
;; `SwitchExamples' (2 examples), samples/SwitchSamples.kt.
;;
;; The `switch' node carries id, checked, label, on_change and enabled
;; -- and nothing else.  Both upstream samples are the SAME remembered
;; boolean Switch; they differ only in `thumbContent', a composable slot
;; drawn INSIDE the thumb.  So the bare one recreates exactly, and the
;; thumb-icon one has no wire member to carry the one thing it exists to
;; demonstrate.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-switches--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SwitchSamples.kt"
  "Upstream SwitchExampleSourceUrl.")

(defun jetpacs-m3-switches--basic ()
  "Upstream SwitchSample: one Switch, remembered as checked.
Upstream hangs contentDescription \"Demo\" on it through semantics; the
switch node has no content_description member, so \"Demo\" survives here
as the message the toggle reports."
  (jetpacs-switch "switches-basic"
                  :checked t
                  :on-change (jetpacs-m3-demo "Demo")))

(jetpacs-m3-defcomponent "switches"
  :name "Switches"
  :description
  "Switches toggle the state of a single setting on or off."
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Switch.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SwitchSample"
    "Switch examples"
    :source jetpacs-m3-switches--source
    :build #'jetpacs-m3-switches--basic)
   (jetpacs-m3-example
    "SwitchWithThumbIconSample"
    "Switch examples"
    :source jetpacs-m3-switches--source
    :unsupported
    "The switch node has no thumb_content member: the Icons.Filled.Check that this sample draws inside the thumb at SwitchDefaults.IconSize is a composable slot, and the wire cannot nest a node inside a switch.")
   ))

(provide 'jetpacs-m3-switches)
;;; jetpacs-m3-switches.el ends here
