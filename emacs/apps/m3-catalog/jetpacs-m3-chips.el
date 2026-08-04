;;; jetpacs-m3-chips.el --- Catalog component: Chips -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Chips' + Examples.kt
;; `ChipsExamples' (13 examples), samples/ChipSamples.kt.
;;
;; M3 has four chip types -- assist, filter, input, suggestion -- which
;; Chip.kt ships as SEVEN composables (every type but input also comes
;; elevated).  With `variant' on both chip nodes the wire reaches all
;; seven: `chip' is FilterChip (flat, the default), ElevatedFilterChip
;; (`elevated') and InputChip (`input'); `assist_chip' is AssistChip
;; (flat), ElevatedAssistChip (`elevated'), SuggestionChip
;; (`suggestion') and ElevatedSuggestionChip (`elevated_suggestion') --
;; RenderChip and RenderAssistChip in InputNodes.kt dispatch exactly
;; those seven.  `chip' also carries `trailing_icon', `avatar' (the
;; InputChip 24dp circular slot, distinct from the 18dp leadingIcon)
;; and `content_spacing' (FilterChipDefaults.horizontalArrangement, the
;; gap INSIDE the chip's own content row) -- so all thirteen samples
;; recreate.  One gap costs no example outright: `assist_chip' has no
;; `trailing_icon', which is why ChipGroupSingleLineSample drops the
;; per-chip ArrowDropDown.
;;
;; The `checked'/`on_change' toggle pair landed on `button' and
;; `icon_button', NOT on either chip node, so `selected' is still
;; authored presentation state -- the Companion draws the snapshot
;; Emacs sent, and the tap only dispatches -- and a filter chip
;; recreates as ONE state of the upstream toggle.  Each sample keeps the
;; state it remembers (`mutableStateOf(false)'), except
;; ChipGroupReflowSample, where false is precisely the state a flow_row
;; cannot draw.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-chips--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ChipSamples.kt"
  "Upstream ChipsExampleSourceUrl.")

(defconst jetpacs-m3-chips--group-labels
  '("Chip 0" "Chip 1" "Chip 2" "Chip 3" "Chip 4"
    "Chip 5" "Chip 6" "Chip 7" "Chip 8")
  "Upstream ChipGroupSingleLineSample chipData: List(9) { \"Chip $index\" }.")

(defconst jetpacs-m3-chips--reflow-labels
  '("Blue 0" "Yellow 1" "Red 2" "Orange 3" "Black 4"
    "Green 5" "White 6" "Magenta 7" "Gray 8" "Transparent 9")
  "Upstream ChipGroupReflowSample labels: \"$element $index\" over colorNames.")

(defun jetpacs-m3-chips--assist ()
  "Upstream AssistChipSample: \"Assist Chip\" with a leading Settings icon."
  (jetpacs-assist-chip "Assist Chip"
                       :on-tap (jetpacs-m3-demo "Assist Chip")
                       :icon "settings"))

(defun jetpacs-m3-chips--elevated-assist ()
  "Upstream ElevatedAssistChipSample: the same chip, elevated.
Identical to AssistChipSample but for the composable, so the variant IS
the sample."
  (jetpacs-assist-chip "Assist Chip"
                       :on-tap (jetpacs-m3-demo "Assist Chip")
                       :icon "settings"
                       :variant "elevated"))

(defun jetpacs-m3-chips--filter ()
  "Upstream FilterChipSample: FilterChip over `mutableStateOf(false)'.
Its leadingIcon is the Done check ONLY while selected, so the state the
sample starts in is a bare chip -- the tap is what would select it."
  (jetpacs-chip "Filter chip" :on-tap (jetpacs-m3-demo "Filter chip")))

(defun jetpacs-m3-chips--elevated-filter ()
  "Upstream ElevatedFilterChipSample: FilterChipSample, elevated.
Same unselected snapshot, and therefore the same absent Done icon."
  (jetpacs-chip "Filter chip"
                :on-tap (jetpacs-m3-demo "Filter chip")
                :variant "elevated"))

(defun jetpacs-m3-chips--filter-with-leading-icon ()
  "Upstream FilterChipWithLeadingIconSample.
This one carries a leading icon in BOTH states -- Done when selected,
Home when not -- so the unselected snapshot keeps the Home icon, which
is what the sample exists to show."
  (jetpacs-chip "Filter chip"
                :on-tap (jetpacs-m3-demo "Filter chip")
                :icon "home"))

(defun jetpacs-m3-chips--filter-with-trailing-icon ()
  "Upstream FilterChipWithTrailingIconSample.
The trailingIcon is an ArrowDropDown in BOTH states; the leadingIcon is
the Done check only while selected.  So the unselected snapshot is the
label plus the trailing arrow, which is the pair the sample is about."
  (jetpacs-chip "Filter chip"
                :on-tap (jetpacs-m3-demo "Filter chip")
                :trailing-icon "arrow_drop_down"))

(defun jetpacs-m3-chips--input ()
  "Upstream InputChipSample: an InputChip over `mutableStateOf(false)'.
Bare label, no avatar and no trailing dismiss -- `chip' with
`:variant \"input\"' renders M3 InputChip itself."
  (jetpacs-chip "Input Chip"
                :on-tap (jetpacs-m3-demo "Input Chip")
                :variant "input"))

(defun jetpacs-m3-chips--suggestion ()
  "Upstream SuggestionChipSample: a bare SuggestionChip, no graphic."
  (jetpacs-assist-chip "Suggestion Chip"
                       :on-tap (jetpacs-m3-demo "Suggestion Chip")
                       :variant "suggestion"))

(defun jetpacs-m3-chips--elevated-suggestion ()
  "Upstream ElevatedSuggestionChipSample: SuggestionChipSample, elevated."
  (jetpacs-assist-chip "Suggestion Chip"
                       :on-tap (jetpacs-m3-demo "Suggestion Chip")
                       :variant "elevated_suggestion"))

(defun jetpacs-m3-chips--group-single-line ()
  "Upstream ChipGroupSingleLineSample: nine chips on one scrolling line.
The sample's own comment names the subject: when a chip list overruns
the width, put a control at the head of the line that opens a menu of
every option.  Both halves are nodes -- a row with `scroll', and `menu',
which IS DropdownMenu.  A menu anchors on an icon button, so the \"Show
All\" AssistChip becomes its Tune icon.  `trailing_icon' is a `chip'
member only, so the per-chip trailing ArrowDropDown is dropped rather
than moved to these assist chips' leading slot; a MenuItem's `icon' is
likewise the leading slot alone, so each item's trailing ArrowRight is
dropped rather than moved in front of its label."
  (jetpacs-column
   (apply #'jetpacs-row
          (append
           (list (jetpacs-menu
                  (mapcar (lambda (label)
                            (jetpacs-menu-item label (jetpacs-m3-demo label)))
                          jetpacs-m3-chips--group-labels)
                  :icon "tune"))
           (mapcar (lambda (label)
                     (jetpacs-assist-chip label
                                          :on-tap (jetpacs-m3-demo label)))
                   jetpacs-m3-chips--group-labels)
           ;; Modifier.padding(horizontal = 4.dp) on each chip.
           (list :spacing 8 :align "center" :scroll t)))
   :align "center"))

(defun jetpacs-m3-chips--group-reflow ()
  "Upstream ChipGroupReflowSample: a leading chip and ten that reflow.
`flow_row' IS FlowRow, so the reflow the sample is named for is on the
wire.  What is not is the collapse: upstream the \"Show All\" FilterChip
switches maxLines between 1 and unbounded, and flow_row has no max_lines
member -- so the wire draws the unbounded run, which is the state
upstream reaches with that chip SELECTED, and it is drawn selected.  The
VerticalDivider is dropped: the divider node is HorizontalDivider."
  (jetpacs-with-attrs
   (apply #'jetpacs-flow-row
          (append
           (list (jetpacs-chip "Show All"
                               :on-tap (jetpacs-m3-demo "Show All")
                               :selected t
                               :icon "tune"))
           (mapcar (lambda (label)
                     (jetpacs-assist-chip label
                                          :on-tap (jetpacs-m3-demo label)))
                   jetpacs-m3-chips--reflow-labels)
           ;; Modifier.padding(horizontal = 4.dp), Arrangement.Start,
           ;; Alignment.CenterVertically.
           (list :spacing 8 :run-spacing 8 :align "center"
                 :arrange "start")))
   ;; Modifier.fillMaxWidth(1f)
   :fill_fraction 1.0))

(jetpacs-m3-defcomponent "chips"
  :name "Chips"
  :description
  "Chips allow users to enter information, make selections, filter content, or trigger actions."
  :guidelines "https://m3.material.io/components/chips"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#chips"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Chip.kt"
  :examples
  (list
   (jetpacs-m3-example
    "AssistChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--assist)
   (jetpacs-m3-example
    "ElevatedAssistChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--elevated-assist)
   (jetpacs-m3-example
    "FilterChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--filter)
   (jetpacs-m3-example
    "ElevatedFilterChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--elevated-filter)
   (jetpacs-m3-example
    "FilterChipWithLeadingIconSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--filter-with-leading-icon)
   (jetpacs-m3-example
    "FilterChipWithTrailingIconSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--filter-with-trailing-icon)
   (jetpacs-m3-example
    "FilterChipWithCustomSpacingSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build (lambda ()
             ;; FilterChipDefaults.horizontalArrangement(4.dp), verbatim.
             ;; The authoring caveat the audit flagged: upstream's leading
             ;; icon exists only while selected, so the sample seeds both
             ;; :selected and :icon or the member would render invisibly.
             (jetpacs-chip "Filter chip"
                           :on-tap (jetpacs-m3-demo "Filter chip")
                           :selected t
                           :icon "done"
                           :content-spacing 4)))
   (jetpacs-m3-example
    "InputChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--input)
   (jetpacs-m3-example
    "InputChipWithAvatarSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build (lambda ()
             ;; The circular InputChipDefaults.AvatarSize Person — the one
             ;; thing separating this from InputChipSample.
             (jetpacs-chip "Input chip"
                           :on-tap (jetpacs-m3-demo "Input chip")
                           :variant "input"
                           :avatar "person")))
   (jetpacs-m3-example
    "SuggestionChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--suggestion)
   (jetpacs-m3-example
    "ElevatedSuggestionChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--elevated-suggestion)
   (jetpacs-m3-example
    "ChipGroupSingleLineSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--group-single-line)
   (jetpacs-m3-example
    "ChipGroupReflowSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--group-reflow)
   ))

(provide 'jetpacs-m3-chips)
;;; jetpacs-m3-chips.el ends here
