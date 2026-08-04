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
;;   stateful node -- M3-COMPONENT-LOOKUP records RadioButton as
;;   "currently achievable via enum_list with multi_select: false" -- and
;;   `RenderEnumList' lays it out as a `FlowRow' of `FilterChip's, not as
;;   list rows.  Both SingleSelection samples are unsupported.
;;   MULTI-selection is a different story: `checkbox' IS a node with its
;;   own live state, so both MultiSelection samples compose around a
;;   real checkbox and are authored.
;;
;; * MODE CHANGE.  `ListItemWithModeChangeOnLongClickSample' now builds:
;;   `box.on_long_tap' gives a composed row a long-press dispatch, and
;;   the whole-list mode flip lives where it always belonged -- in the
;;   app.  Each row is a box whose on_tap counts or toggles and whose
;;   on_long_tap runs a COMPOUND mutation (enter selection mode checking
;;   the pressed row; exit clearing every row) registered on the
;;   `m3catalog.fn' verb, so one gesture rewriting the siblings is just
;;   Emacs rewriting its own model and re-pushing.  The selection-mode
;;   checkbox is authored and inert, which is upstream verbatim: its
;;   Checkbox passes onCheckedChange = null and the row's own click
;;   does the toggling.
;;
;; The SELECTION gap was re-triaged against the members that landed
;; since.  `button' and `icon_button' now carry `checked'/`on_change'
;; (and `icon_button' a `checked_icon'), which is the nearest thing yet
;; to a radio indicator -- but a checked node holds only its OWN value
;; on the device, and nothing makes a group of them exclusive, which is
;; precisely what the SingleSelection samples exist to show.  So that
;; gap stands.  The rest of the session's vocabulary does not reach a
;; ListItem sample either: upstream draws no chip, no tooltip and no
;; elevated card here, and the segmented group keeps `bg' + `corner'
;; rather than a `surface', because `surface.shape' names whole shapes
;; and cannot spell the four distinct radii of `segmentedShapes'.
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

(defun jetpacs-m3-lists--selection-child (n)
  "Row body for single-selection option N: the ListItem text column.
The RadioButton leading slot is the radio variant's own, so the child
carries only what upstream's content/supportingContent slots held."
  (jetpacs-column
   (jetpacs-text (format "Item %d" n))
   (jetpacs-text "Additional info" :style "caption"
                 :color "on_surface_variant")
   :spacing 2))

(defun jetpacs-m3-lists--single-selection (id &optional segmented)
  "The SingleSelection pair: three whole-row exclusive choices, as ID.
`enum_list' `:variant \"radio\"' with `:children' makes each option one
selectable ROW — checking a row clears its siblings because the node
owns the exclusive choice, which no per-row checked member could.
SEGMENTED dresses each child with the group color and its own corners,
riding the children's universal attributes."
  (jetpacs-enum-list
   id
   (list (jetpacs-enum-option "Item 1" "item-1")
         (jetpacs-enum-option "Item 2" "item-2")
         (jetpacs-enum-option "Item 3" "item-3"))
   :variant "radio"
   :value "item-1"
   :children (cl-loop for n from 1 to 3
                      for child = (jetpacs-m3-lists--selection-child n)
                      collect (if segmented
                                  (jetpacs-m3-lists--segment (1- n) 3 child)
                                child))
   :on-change (jetpacs-m3-demo "Selection")))

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

(defvar jetpacs-m3-lists--mode-select nil
  "ListItemWithModeChangeOnLongClick: nil = click mode, t = selection mode.")
(defvar jetpacs-m3-lists--mode-counts (make-vector 3 0)
  "Per-row tap counts for the mode-change sample\='s click mode.")
(defvar jetpacs-m3-lists--mode-checked (make-vector 3 nil)
  "Per-row checked states for the mode-change sample\='s selection mode.")

;; The compound mutations, exactly upstream's handlers: a click counts or
;; toggles depending on the mode; a long press enters selection mode
;; checking the pressed row, or exits it clearing every row.
(dotimes (i 3)
  (puthash (format "lists-mode-tap-%d" i)
           (let ((i i))
             (lambda ()
               (if jetpacs-m3-lists--mode-select
                   (aset jetpacs-m3-lists--mode-checked i
                         (not (aref jetpacs-m3-lists--mode-checked i)))
                 (cl-incf (aref jetpacs-m3-lists--mode-counts i)))))
           jetpacs-m3-fn-registry)
  (puthash (format "lists-mode-long-%d" i)
           (let ((i i))
             (lambda ()
               (if jetpacs-m3-lists--mode-select
                   (progn (setq jetpacs-m3-lists--mode-select nil)
                          (fillarray jetpacs-m3-lists--mode-checked nil))
                 (setq jetpacs-m3-lists--mode-select t)
                 (aset jetpacs-m3-lists--mode-checked i t))))
           jetpacs-m3-fn-registry))

(defun jetpacs-m3-lists--mode-change-item (i)
  "Row I of the mode-change sample, in whichever mode the state says.
The row is a `box' -- on_tap counts or toggles, on_long_tap switches the
mode -- around the composed ListItem.  In selection mode the leading
checkbox is authored and INERT (no on-change), which is upstream
verbatim: its Checkbox passes onCheckedChange = null and the row's own
click does the toggling."
  (let ((select jetpacs-m3-lists--mode-select))
    (jetpacs-box
     (jetpacs-m3-lists--row
      (format "Item %d" (1+ i))
      :supporting "Long-click to change interaction mode."
      :leading (if select
                   (jetpacs-checkbox
                    (format "lists-mode-check-%d" i)
                    :checked (jetpacs-bool
                              (aref jetpacs-m3-lists--mode-checked i))
                    :enabled :json-false)
                 (jetpacs-icon "home"))
      :trailing (if select
                    (jetpacs-m3-lists--favorite)
                  (jetpacs-text
                   (number-to-string (aref jetpacs-m3-lists--mode-counts i)))))
     :on-tap (jetpacs-m3-fn-action (format "lists-mode-tap-%d" i))
     :on-long-tap (jetpacs-m3-fn-action (format "lists-mode-long-%d" i)))))

(defun jetpacs-m3-lists--mode-change ()
  "Upstream ListItemWithModeChangeOnLongClickSample, live on the fn verb.
Three rows that are counting click targets until a long press flips the
whole list into checkbox targets (checking the pressed row), and back
(clearing every row).  Every gesture is a real round trip: the compound
mutation runs in Emacs and the next snapshot re-authors all three rows."
  (jetpacs-m3-lists--divided
   (mapcar #'jetpacs-m3-lists--mode-change-item (number-sequence 0 2))))

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
    :build (lambda ()
             (jetpacs-m3-lists--single-selection "lists-single-selection")))
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
    :build #'jetpacs-m3-lists--mode-change)
   (jetpacs-m3-example
    "SingleSelectionSegmentedListItemSample"
    "List examples"
    :source jetpacs-m3-lists--source
    :expressive t
    :build (lambda ()
             (jetpacs-m3-lists--single-selection "lists-single-segmented" t)))
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
