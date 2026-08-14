;;; jetpacs-m3-switches.el --- Catalog component: Switches -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Switches' + Examples.kt
;; `SwitchExamples' (2 examples), samples/SwitchSamples.kt.
;;
;; The `switch' node carries id, checked, label, on_change, enabled and
;; thumb_icon.  Both upstream samples are the SAME remembered boolean
;; Switch; they differ only in `thumbContent', a composable slot drawn
;; INSIDE the thumb.  `thumb_icon' names a vector for that slot, drawn
;; at SwitchDefaults.IconSize and only while checked is live-true --
;; which is exactly the upstream lambda.  So both samples recreate.

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

(defun jetpacs-m3-switches--thumb-icon ()
  "Upstream SwitchWithThumbIconSample: a Switch with a check in its thumb.
Upstream draws Icons.Filled.Check inside the thumb at
SwitchDefaults.IconSize while checked; `:thumb-icon' is that slot, and
the Companion draws it under the same condition.  Upstream hangs
contentDescription \"Demo with icon\" on the switch through semantics;
the switch node has no content_description member, so it survives here
as the message the toggle reports."
  (jetpacs-switch "switches-thumb-icon"
                  :checked t
                  :thumb-icon "check"
                  :on-change (jetpacs-m3-demo "Demo with icon")))

(jetpacs-m3-defcomponent "switches"
  :builders (list #'jetpacs-switch)
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
    :build #'jetpacs-m3-switches--thumb-icon)
   ))

(provide 'jetpacs-m3-switches)
;;; jetpacs-m3-switches.el ends here
