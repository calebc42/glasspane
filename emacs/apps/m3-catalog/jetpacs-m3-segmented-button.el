;;; jetpacs-m3-segmented-button.el --- Catalog component: Segmented Button -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SegmentedButtons' + Examples.kt
;; `SegmentedButtonExamples' (2 examples),
;; samples/SegmentedButtonSamples.kt.
;;
;; SegmentedButton is one of the M3 components Jetpacs does not wrap
;; (docs/lookup-tables/M3-COMPONENT-LOOKUP.org lists it Available, and
;; names a `segmented_button' wire type as the thing that would be
;; needed).  Both samples are that missing node and nothing else: each
;; is a bare `SingleChoiceSegmentedButtonRow' /
;; `MultiChoiceSegmentedButtonRow' whose every child passes
;; `SegmentedButtonDefaults.itemShape(index, count)' -- the start /
;; middle / end shape math that fuses the options into one connected
;; track.  That fusing IS the control; without it there is no segmented
;; button, only a set of separate options.
;;
;; The neighbours one could reach for all draw a different M3 component
;; and would demonstrate it rather than this one.  `enum_list' does
;; hold single- and multi-select state Companion-side, but it renders
;; FlowRow(FilterChip) -- loose, wrapping, individually rounded chips,
;; which is the Chips page.  `tabs' is the closest semantic match, yet
;; it draws a TabRow with a sliding indicator and owns a pager, which
;; is the Tabs page.  `chip :selected' is authored from Emacs and has
;; no id, so a tap could never move the selection at all.  None of them
;; can be squeezed into a track: the only shape member on the wire is
;; surface's rounded/rounded_small/circle enum, which has no start,
;; middle or end form.
;;
;; So both are unsupported, and each reason names what its sample adds
;; on top of the missing node: mutually exclusive selection over one
;; connected row (example 1), and the checked-driven icon slot of
;; `SegmentedButtonDefaults.Icon(active =)' (example 2).

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
    :unsupported
    "There is no segmented_button node type, and no node carries a selected-segment state: the connected Day/Month/Week track that SegmentedButtonDefaults.itemShape(index, count) builds from start, middle and end shapes cannot be asked for from Emacs, and enum_list would answer with a FlowRow of separate FilterChips instead.")
   (jetpacs-m3-example
    "SegmentedButtonMultiSelectSample"
    "Segmented Button examples"
    :source jetpacs-m3-segmented-button--source
    :unsupported
    "Neither half is on the wire: there is no segmented_button node type for the connected multi-choice track, and no node carries a per-option icon slot, so SegmentedButtonDefaults.Icon(active = index in checkedList) crossfading each option's own icon into a checkmark has nothing to ride on.")
   ))

(provide 'jetpacs-m3-segmented-button)
;;; jetpacs-m3-segmented-button.el ends here
