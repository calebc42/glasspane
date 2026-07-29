;;; jetpacs-m3-chips.el --- Catalog component: Chips -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Chips' + Examples.kt
;; `ChipsExamples' (13 examples), samples/ChipSamples.kt.
;;
;; M3 ships five chips; the wire wraps TWO of them.  `chip' IS
;; FilterChip (label, on_tap, selected, icon, enabled) and `assist_chip'
;; IS AssistChip (label, on_tap, icon, enabled) -- the Chip row of
;; M3-COMPONENT-LOOKUP says so, and InputNodes.kt renders exactly those
;; two composables.  So the plain assist chip, the plain filter chip,
;; the with-leading-icon filter chip and both chip-GROUP layout samples
;; recreate; InputChip and SuggestionChip have no node of their own, and
;; drawing an AssistChip under a SuggestionChip's label would be a
;; lookalike rather than a recreation.
;;
;; The remaining gaps are per-member.  Neither chip node has a variant
;; or an elevation member, so the three Elevated* samples cannot say the
;; one thing they exist to say.  `icon' is the LEADING icon in both
;; renderers (`leadingIcon = ...' in InputNodes.kt), so a trailing
;; ArrowDropDown has nowhere to go.  And a chip has no arrangement
;; member, so the spacing INSIDE its content row is not askable.
;;
;; `selected' is authored presentation state -- the Companion draws the
;; snapshot Emacs sent, and the tap dispatches -- so a filter chip
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

(defconst jetpacs-m3-chips--elevated-note
  "Neither chip node has a variant or an elevation member: the raised container that makes an M3 Elevated chip elevated is a Companion-side visual the wire cannot ask for."
  "Why every Elevated chip sample is unsupported.")

(defconst jetpacs-m3-chips--input-note
  "There is no input_chip node type: the wire wraps FilterChip as chip and AssistChip as assist_chip, and M3 InputChip -- with its own container, shape, avatar and trailing-dismiss slots -- is neither of them."
  "Why every InputChip sample is unsupported.")

(defconst jetpacs-m3-chips--suggestion-note
  "There is no suggestion_chip node type: the wire wraps only FilterChip and AssistChip, so standing an assist_chip in for M3 SuggestionChip would draw a different component under this sample's own label."
  "Why every SuggestionChip sample is unsupported.")

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

(defun jetpacs-m3-chips--filter ()
  "Upstream FilterChipSample: FilterChip over `mutableStateOf(false)'.
Its leadingIcon is the Done check ONLY while selected, so the state the
sample starts in is a bare chip -- the tap is what would select it."
  (jetpacs-chip "Filter chip" :on-tap (jetpacs-m3-demo "Filter chip")))

(defun jetpacs-m3-chips--filter-with-leading-icon ()
  "Upstream FilterChipWithLeadingIconSample.
This one carries a leading icon in BOTH states -- Done when selected,
Home when not -- so the unselected snapshot keeps the Home icon, which
is what the sample exists to show."
  (jetpacs-chip "Filter chip"
                :on-tap (jetpacs-m3-demo "Filter chip")
                :icon "home"))

(defun jetpacs-m3-chips--group-single-line ()
  "Upstream ChipGroupSingleLineSample: nine chips on one scrolling line.
The sample's own comment names the subject: when a chip list overruns
the width, put a control at the head of the line that opens a menu of
every option.  Both halves are nodes -- a row with `scroll', and `menu',
which IS DropdownMenu.  A menu anchors on an icon button, so the \"Show
All\" AssistChip becomes its Tune icon, and the per-chip trailing
ArrowDropDown is dropped rather than moved to the leading slot."
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
    :unsupported jetpacs-m3-chips--elevated-note)
   (jetpacs-m3-example
    "FilterChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--filter)
   (jetpacs-m3-example
    "ElevatedFilterChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported jetpacs-m3-chips--elevated-note)
   (jetpacs-m3-example
    "FilterChipWithLeadingIconSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :build #'jetpacs-m3-chips--filter-with-leading-icon)
   (jetpacs-m3-example
    "FilterChipWithTrailingIconSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported
    "The chip node has one icon member and the renderer spends it on leadingIcon: there is no trailing_icon member, so the ArrowDropDown this sample exists to show cannot be put on the wire.")
   (jetpacs-m3-example
    "FilterChipWithCustomSpacingSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported
    "The chip node has no horizontal_arrangement member: FilterChipDefaults.horizontalArrangement(4.dp) spaces the icon and label INSIDE the chip's own content row, which no universal attribute reaches.")
   (jetpacs-m3-example
    "InputChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported jetpacs-m3-chips--input-note)
   (jetpacs-m3-example
    "InputChipWithAvatarSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported
    "Neither half is on the wire: there is no input_chip node type, and no chip node has an avatar slot for the InputChipDefaults.AvatarSize Person this sample exists to show.")
   (jetpacs-m3-example
    "SuggestionChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported jetpacs-m3-chips--suggestion-note)
   (jetpacs-m3-example
    "ElevatedSuggestionChipSample"
    "Chips examples"
    :source jetpacs-m3-chips--source
    :unsupported
    "Neither half is on the wire: there is no suggestion_chip node type, and no chip node has a variant or elevation member for the raised container.")
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
