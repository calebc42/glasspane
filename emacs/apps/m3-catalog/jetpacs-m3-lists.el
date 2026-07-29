;;; jetpacs-m3-lists.el --- Catalog component: Lists -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Lists' + Examples.kt
;; `ListsExamples' (12 examples), samples/ListSamples.kt.
;;
;; There is no `list_item' node.  M3-COMPONENT-LOOKUP records the
;; ratified position -- "Jetpacs currently achieves this with manual
;; row/column composition inside card", which is exactly what
;; `jetpacs-chrome-row' is -- so the ANATOMY every ListItem sample
;; exists to show (leading content, an overline/headline/supporting text
;; column, trailing content, `HorizontalDivider's between rows) survives
;; composition from wrapped nodes, and is authored here.
;;
;; TRIAGE.  Two things upstream demonstrates have no wire member:
;;
;; * SELECTION.  `ListItem(selected =, onClick =)' makes a whole row one
;;   exclusive choice with a `RadioButton' as its indicator.  No
;;   container node carries a `selected' member and there is no
;;   `radio_button' node type; `enum_list' is the only single-selection
;;   stateful node and it renders as a `FlowRow' of `FilterChip's, not
;;   as list rows.  Both SingleSelection samples are unsupported.
;;   MULTI-selection is a different story: `checkbox' IS a node with its
;;   own live state, so both MultiSelection samples compose around a
;;   real checkbox and are authored.
;;
;; * MODE CHANGE.  `ListItemWithModeChangeOnLongClickSample' flips every
;;   row at once, on a long press, between a counting click target and a
;;   checkbox target.  Each stateful node on the wire owns only its own
;;   value, and no member lets a gesture on one node rewrite its
;;   siblings.
;;
;; `SegmentedListItem' needs no special pleading:
;; `ListItemDefaults.segmentedShapes(index, count)' rounds the outer
;; corners of the first and last row of a group and nearly squares the
;; inner ones, and the universal `corner' attribute takes exactly those
;; four radii over a `bg' -- so the segmented grouping is authored, as
;; is the last sample's expansion, which is what a `collapsible' is.
;;
;; One detail is lost throughout: upstream taps increment a
;; `rememberSaveable' counter.  The catalog's one handler is
;; `jetpacs-m3-demo', so a tap reports as a snackbar and a trailing
;; count stays at the 0 it starts at.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-lists--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ListSamples.kt"
  "Upstream ListsExampleSourceUrl.")

(defconst jetpacs-m3-lists--single-selection-note
  "There is no radio_button node type and no container node carries a selected member: this sample exists to make a whole list row one exclusive choice that recolors when it wins, and enum_list, the only single-selection stateful node, renders as a FlowRow of filter chips rather than as list rows."
  "Why both SingleSelection samples are unsupported.")

(defconst jetpacs-m3-lists--segmented-color "surface_variant"
  "The nearest §16.6 role to the samples\\=' surfaceContainer.
Upstream passes `ListItemDefaults.colors(containerColor =
MaterialTheme.colorScheme.surfaceContainer)'; the wire color vocabulary
has no surfaceContainer, and `surface_variant' is the tonal step it
names.")

(defconst jetpacs-m3-lists--segmented-gap 2
  "The dp gap upstream spells `ListItemDefaults.SegmentedGap'.")

(cl-defun jetpacs-m3-lists--row (headline &key overline supporting
                                          leading trailing align)
  "One ListItem, composed: LEADING, the text column, then TRAILING.
HEADLINE is the headline string; OVERLINE and SUPPORTING are the text
slots M3 draws above and below it; ALIGN is the row cross-alignment,
which M3 moves off center for the three-line variants."
  (jetpacs-with-attrs
   (apply #'jetpacs-row
          (append
           (when leading (list leading))
           (list (jetpacs-with-attrs
                  (apply #'jetpacs-column
                         (append
                          (when overline
                            (list (jetpacs-text overline :style "label"
                                                :color "on_surface_variant")))
                          (list (jetpacs-text headline))
                          (when supporting
                            (list (jetpacs-text supporting :style "caption"
                                                :color "on_surface_variant")))
                          (list :spacing 2)))
                  :weight 1))
           (when trailing (list trailing))
           (list :spacing 16 :align (or align "center"))))
   :pad (list :horizontal 16 :vertical 12)))

(defun jetpacs-m3-lists--divided (items)
  "ITEMS as a full-width column fenced by dividers.
Every plain ListItem sample is a Column that opens with a
`HorizontalDivider' and closes each row with another."
  (apply #'jetpacs-column
         (append (list (jetpacs-divider))
                 (mapcan (lambda (item) (list item (jetpacs-divider))) items)
                 (list :fill t))))

(defun jetpacs-m3-lists--segmented (items)
  "ITEMS as a segmented group: full width, one SegmentedGap apart."
  (apply #'jetpacs-column
         (append items
                 (list :spacing jetpacs-m3-lists--segmented-gap :fill t))))

(defun jetpacs-m3-lists--segment-corner (index count)
  "The `corner' attribute of segment INDEX of COUNT.
`ListItemDefaults.segmentedShapes' rounds the outer corners of the first
and last row of the group and leaves the inner ones nearly square."
  (let ((top (if (= index 0) 16 4))
        (bottom (if (= index (1- count)) 16 4)))
    (list :top_start top :top_end top
          :bottom_start bottom :bottom_end bottom)))

(defun jetpacs-m3-lists--segment (index count row)
  "ROW as segment INDEX of COUNT: the group color and its own corners."
  (jetpacs-with-attrs row
                      :bg jetpacs-m3-lists--segmented-color
                      :corner (jetpacs-m3-lists--segment-corner index count)
                      :clip t))

(defun jetpacs-m3-lists--favorite (&optional description)
  "The Icons.Filled.Favorite every sample leads or trails with.
DESCRIPTION is its contentDescription, absent where upstream passes nil."
  (jetpacs-icon "favorite" :content-description description))

(defun jetpacs-m3-lists--one-line ()
  "Upstream OneLineListItem: a headline and a 24x24 leading icon."
  (jetpacs-m3-lists--divided
   (list (jetpacs-m3-lists--row
          "One line list item with 24x24 icon"
          :leading (jetpacs-icon "favorite" :size 24
                                 :content-description
                                 "Localized description")))))

(defun jetpacs-m3-lists--two-line ()
  "Upstream TwoLineListItem: supporting text and a \"meta\" trailing."
  (jetpacs-m3-lists--divided
   (list (jetpacs-m3-lists--row
          "Two line list item with trailing"
          :supporting "Secondary text"
          :trailing (jetpacs-text "meta" :style "label"
                                  :color "on_surface_variant")
          :leading (jetpacs-m3-lists--favorite "Localized description")))))

(defun jetpacs-m3-lists--three-line-overline ()
  "Upstream ThreeLineListItemWithOverlineAndSupporting.
The third line is an OVERLINE above the headline; M3 aligns the leading
and trailing content to the top once a row is three lines tall."
  (jetpacs-m3-lists--divided
   (list (jetpacs-m3-lists--row
          "Three line list item"
          :overline "OVERLINE"
          :supporting "Secondary text"
          :trailing (jetpacs-text "meta" :style "label"
                                  :color "on_surface_variant")
          :leading (jetpacs-m3-lists--favorite "Localized description")
          :align "top"))))

(defun jetpacs-m3-lists--three-line-extended ()
  "Upstream ThreeLineListItemWithExtendedSupporting.
Here the third line comes from supporting text that wraps over two
lines, so the row is three lines tall with no overline."
  (jetpacs-m3-lists--divided
   (list (jetpacs-m3-lists--row
          "Three line list item"
          :supporting "Secondary text that\nspans multiple lines"
          :trailing (jetpacs-text "meta" :style "label"
                                  :color "on_surface_variant")
          :leading (jetpacs-m3-lists--favorite "Localized description")
          :align "top"))))

(defun jetpacs-m3-lists--clickable-item (n)
  "Item N of ClickableListItemSample: a whole row that is one tap target.
A `box' with an `on_tap' is the clickable ListItem: the tap covers the
row and, unlike a `card', draws no container of its own."
  (jetpacs-box
   (jetpacs-m3-lists--row (format "Item %d" n)
                          :supporting "Additional info"
                          :leading (jetpacs-icon "home")
                          :trailing (jetpacs-text "0"))
   :on-tap (jetpacs-m3-demo (format "Item %d" n))))

(defun jetpacs-m3-lists--clickable ()
  "Upstream ClickableListItemSample: three rows, each one tap target.
Upstream every tap increments that row\\='s own counter; the catalog
handler reports the row instead, so the trailing count stays at 0."
  (jetpacs-m3-lists--divided
   (mapcar #'jetpacs-m3-lists--clickable-item (number-sequence 1 3))))

(defun jetpacs-m3-lists--clickable-child-item (n)
  "Item N of ClickableListItemWithClickableChildSample.
The row is a tap target and the trailing `icon_button' is another,
nested inside it with a handler of its own -- which is the whole point
of the sample and composes exactly."
  (jetpacs-box
   (jetpacs-m3-lists--row
    (format "Item %d" n)
    :supporting "The trailing icon has a separate click action"
    :leading (jetpacs-icon "home")
    :trailing (jetpacs-icon-button
               "favorite" (jetpacs-m3-demo "Child onClick callback")
               :content-description "Localized description"))
   :on-tap (jetpacs-m3-demo "ListItem onClick callback")))

(defun jetpacs-m3-lists--clickable-child ()
  "Upstream ClickableListItemWithClickableChildSample: three such rows."
  (jetpacs-m3-lists--divided
   (mapcar #'jetpacs-m3-lists--clickable-child-item (number-sequence 1 3))))

(defun jetpacs-m3-lists--multi-item (n)
  "Item N of MultiSelectionListItemSample, around a live `checkbox'.
Upstream hoists the toggle onto the ListItem and leaves its leading
Checkbox inert (onCheckedChange = null).  Here the checkbox node IS the
toggle -- it is the one node that owns a checked state -- so the hit
target is the checkbox itself rather than the whole row."
  (jetpacs-m3-lists--row
   (format "Item %d" n)
   :supporting "Additional info"
   :leading (jetpacs-checkbox
             (format "lists-multi-%d" n)
             :on-change (jetpacs-m3-demo (format "Item %d" n)))
   :trailing (jetpacs-m3-lists--favorite)))

(defun jetpacs-m3-lists--multi ()
  "Upstream MultiSelectionListItemSample: three checkable rows."
  (jetpacs-m3-lists--divided
   (mapcar #'jetpacs-m3-lists--multi-item (number-sequence 1 3))))

(defun jetpacs-m3-lists--segmented-multi-item (index count)
  "Item INDEX of COUNT of MultiSelectionSegmentedListItemSample."
  (let ((n (1+ index)))
    (jetpacs-m3-lists--segment
     index count
     (jetpacs-m3-lists--row
      (format "Item %d" n)
      :supporting "Additional info"
      :leading (jetpacs-checkbox
                (format "lists-segmented-multi-%d" n)
                :on-change (jetpacs-m3-demo (format "Item %d" n)))
      :trailing (jetpacs-m3-lists--favorite)))))

(defun jetpacs-m3-lists--segmented-multi ()
  "Upstream MultiSelectionSegmentedListItemSample: four segmented rows.
What separates it from MultiSelectionListItemSample is the grouping --
one container color, a SegmentedGap between rows, and the outer corners
of the group rounded -- and `bg', `corner' and column `spacing' are
that grouping."
  (let ((count 4))
    (jetpacs-m3-lists--segmented
     (mapcar (lambda (index)
               (jetpacs-m3-lists--segmented-multi-item index count))
             (number-sequence 0 (1- count))))))

(defun jetpacs-m3-lists--expansion-child (index count)
  "Child INDEX of COUNT of SegmentedListItemWithExpansionSample.
The header is segment 0, so child INDEX and the number it shows agree."
  (jetpacs-m3-lists--segment
   index count
   (jetpacs-m3-lists--row
    (format "Child %d" index)
    :leading (jetpacs-m3-lists--favorite)
    :trailing (jetpacs-checkbox
               (format "lists-expansion-child-%d" index)
               :on-change (jetpacs-m3-demo (format "Child %d" index))))))

(defun jetpacs-m3-lists--expansion ()
  "Upstream SegmentedListItemWithExpansionSample.
A `collapsible' is this sample: an id that owns the expansion state, a
header row that toggles it, and children revealed underneath.  The
renderer supplies the header chevron upstream swaps between ExpandMore
and ExpandLess, and the group is four segments tall while open, so the
header takes segment 0 of 4 and the three children the rest."
  (let ((count 4))
    (jetpacs-collapsible
     "lists-expansion"
     (jetpacs-m3-lists--segment
      0 count
      (jetpacs-m3-lists--row "Click to expand/collapse"
                             :leading (jetpacs-m3-lists--favorite)))
     ;; One column, so the revealed children keep the SegmentedGap: a
     ;; `collapsible' lays its children out itself and has no spacing.
     (jetpacs-m3-lists--segmented
      (mapcar (lambda (index)
                (jetpacs-m3-lists--expansion-child index count))
              (number-sequence 1 (1- count))))
     :collapsed t)))

(jetpacs-m3-defcomponent "lists"
  :name "Lists"
  :description
  "Lists are continuous, vertical indexes of text or images."
  :guidelines "https://m3.material.io/components/list-item"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#listitem"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ListItem.kt"
  :examples
  (list
   (jetpacs-m3-example
    "OneLineListItem"
    "List examples"
    :source jetpacs-m3-lists--source
    :build #'jetpacs-m3-lists--one-line)
   (jetpacs-m3-example
    "TwoLineListItem"
    "List examples"
    :source jetpacs-m3-lists--source
    :build #'jetpacs-m3-lists--two-line)
   (jetpacs-m3-example
    "ThreeLineListItemWithOverlineAndSupporting"
    "List examples"
    :source jetpacs-m3-lists--source
    :build #'jetpacs-m3-lists--three-line-overline)
   (jetpacs-m3-example
    "ThreeLineListItemWithExtendedSupporting"
    "List examples"
    :source jetpacs-m3-lists--source
    :build #'jetpacs-m3-lists--three-line-extended)
   (jetpacs-m3-example
    "ClickableListItemSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :build #'jetpacs-m3-lists--clickable)
   (jetpacs-m3-example
    "ClickableListItemWithClickableChildSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :build #'jetpacs-m3-lists--clickable-child)
   (jetpacs-m3-example
    "SingleSelectionListItemSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :unsupported jetpacs-m3-lists--single-selection-note)
   (jetpacs-m3-example
    "MultiSelectionListItemSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :build #'jetpacs-m3-lists--multi)
   (jetpacs-m3-example
    "ListItemWithModeChangeOnLongClickSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :unsupported
    "No node can change another node's interaction mode: one long press here turns every row at once from a counting click target into a checkbox target, and each stateful node on the wire owns only its own value, with no member a gesture on one row can use to rewrite its siblings.")
   (jetpacs-m3-example
    "SingleSelectionSegmentedListItemSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :unsupported jetpacs-m3-lists--single-selection-note)
   (jetpacs-m3-example
    "MultiSelectionSegmentedListItemSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :build #'jetpacs-m3-lists--segmented-multi)
   (jetpacs-m3-example
    "SegmentedListItemWithExpansionSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :build #'jetpacs-m3-lists--expansion)
   ))

(provide 'jetpacs-m3-lists)
;;; jetpacs-m3-lists.el ends here
