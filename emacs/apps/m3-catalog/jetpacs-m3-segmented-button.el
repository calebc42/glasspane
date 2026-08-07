;;; jetpacs-m3-segmented-button.el --- Catalog component: Segmented Button -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SegmentedButtons' + Examples.kt
;; `SegmentedButtonExamples' (2 examples),
;; samples/SegmentedButtonSamples.kt.
;;
;; Both samples recreate on the `segmented_button' node -- the 46th
;; type, which exists because of this module.  The node owns everything
;; the component is: per-segment `SegmentedButtonDefaults.itemShape(index,
;; count)' -- the start/middle/end shape math that fuses the options
;; into one connected track -- the fused seam itself, the checked
;; crossfade, and the selection semantics.  Its value schema mirrors
;; enum_list exactly (one option value, or an array under multi_select),
;; and the state is device-held keyed on `:id'.
;;
;; The node exists because no neighbour could be squeezed into a track:
;; `enum_list' renders FlowRow(FilterChip) -- the Chips page -- `tabs'
;; draws a TabRow with a pager, and `chip :selected' is authored with no
;; id, so a tap could never move the selection.
;;
;; The multi sample's icons ride the option records: an option `:icon'
;; renders under `SegmentedButtonDefaults.Icon(active =)', which
;; crossfades it into the checkmark as it is checked -- exactly
;; upstream's slot.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-segmented-button--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SegmentedButtonSamples.kt"
  "Upstream SegmentedButtonExampleSourceUrl.")

(defun jetpacs-m3-segmented-button--single-select ()
  "Upstream SegmentedButtonSingleSelectSample: Day/Month/Week, one chosen.
Upstream starts at selectedIndex 0 -- \"Day\" -- so `:value' does.  What
the sample spells out per option and the node owns instead is
`SegmentedButtonDefaults.itemShape(index, count)': the start/middle/end
corner math that fuses three buttons into one track.  Here that leaves
only what varies -- the id the selection is held on, the three options,
and which starts selected."
  (jetpacs-segmented-button
   "segmented-button-single"
   (list (jetpacs-enum-option "Day" "day")
         (jetpacs-enum-option "Month" "month")
         (jetpacs-enum-option "Week" "week"))
   :value "day"
   :on-change (jetpacs-m3-demo "Segmented button")))

(defun jetpacs-m3-segmented-button--multi-select ()
  "Upstream SegmentedButtonMultiSelectSample: any number of the three checked.
`:multi-select t' is upstream's MultiChoiceSegmentedButtonRow, and it is
the whole difference: the value becomes an array rather than one option
value, and with no `:value' it starts empty, as upstream's empty
checkedList does.  The icons ride the option records -- an option
`:icon' renders under `SegmentedButtonDefaults.Icon(active =)', which
crossfades it into the checkmark as that option is checked, exactly
upstream's icon slot."
  (jetpacs-segmented-button
   "segmented-button-multi"
   (list (jetpacs-enum-option "Favorites" "favorites"
                              :icon "star_border")
         (jetpacs-enum-option "Trending" "trending"
                              :icon "trending_up")
         (jetpacs-enum-option "Saved" "saved"
                              :icon "bookmark_border"))
   :multi-select t
   :on-change (jetpacs-m3-demo "Segmented button")))

(jetpacs-m3-defcomponent "segmented-button"
  :builders (list #'jetpacs-segmented-button #'jetpacs-enum-option)
  :name "Segmented Button"
  :description
  "Segmented buttons help people select options, switch views, or sort elements."
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/SegmentedButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SegmentedButtonSingleSelectSample"
    "Segmented Button examples"
    :source jetpacs-m3-segmented-button--source
    :build #'jetpacs-m3-segmented-button--single-select)
   (jetpacs-m3-example
    "SegmentedButtonMultiSelectSample"
    "Segmented Button examples"
    :source jetpacs-m3-segmented-button--source
    :build #'jetpacs-m3-segmented-button--multi-select)
   ))

(provide 'jetpacs-m3-segmented-button)
;;; jetpacs-m3-segmented-button.el ends here
