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

(jetpacs-m3-defcomponent "segmented-button"
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
    :build (lambda ()
             ;; Upstream starts at selectedIndex 0 — "Day" selected.
             (jetpacs-segmented-button
              "segmented-single"
              (list (jetpacs-enum-option "Day" "day")
                    (jetpacs-enum-option "Month" "month")
                    (jetpacs-enum-option "Week" "week"))
              :value "day"
              :on-change (jetpacs-m3-demo "Segmented button"))))
   (jetpacs-m3-example
    "SegmentedButtonMultiSelectSample"
    "Segmented Button examples"
    :source jetpacs-m3-segmented-button--source
    :build (lambda ()
             ;; Upstream starts with nothing checked; each option's icon
             ;; crossfades into the checkmark as it is checked.
             (jetpacs-segmented-button
              "segmented-multi"
              (list (jetpacs-enum-option "Favorites" "favorites"
                                         :icon "star_border")
                    (jetpacs-enum-option "Trending" "trending"
                                         :icon "trending_up")
                    (jetpacs-enum-option "Saved" "saved"
                                         :icon "bookmark_border"))
              :multi-select t
              :on-change (jetpacs-m3-demo "Segmented button"))))
   ))

(provide 'jetpacs-m3-segmented-button)
;;; jetpacs-m3-segmented-button.el ends here
