;;; jetpacs-m3-tooltips.el --- Catalog component: Tooltips -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Tooltips' + Examples.kt
;; `TooltipsExamples' (13 examples), samples/TooltipSamples.kt.
;;
;; All thirteen samples are one composable: `TooltipBox'.  A TooltipBox
;; is a transient surface anchored to a widget, raised by long-press or
;; by `TooltipState.show()', placed by a `TooltipAnchorPosition' and
;; optionally pointed back at its anchor by a caret.  Every sample
;; varies exactly one of those axes -- plain vs rich content, the
;; anchor position (Above/Below/Left/Right/Start/End), the caret and
;; its DpSize, manual invocation -- over the same Favorite / AddCircle
;; / Info IconButton anchor.
;;
;; docs/lookup-tables/M3-COMPONENT-LOOKUP.org lists Tooltip as
;; available-but-unwrapped, and it is unwrapped the whole way down:
;; there is no tooltip node in the Core Node Set, no anchored-popup
;; member on any node, no caret or anchor-position member anywhere, no
;; `tooltip' in `jetpacs-universal-attributes' (the lookup table
;; PROPOSES one as a future universal attribute, which is not the same
;; as having one), and no action descriptor that asks the Companion to
;; raise or dismiss a popup.  So the component is unsupported end to
;; end, and each reason names the axis its own sample was varying.
;;
;; The temptation to resist: the scaffold `snackbar' slot is the wire's
;; one transient surface, and `card'/`collapsible' carry `on_long_tap'.
;; Together they could pop "Add to favorites" on a long press -- and
;; demonstrate none of it.  A snackbar is a screen-level message with
;; no anchor, no position, no caret, and it cannot be a rich tooltip's
;; persistent title/text/action panel either.  That is a lookalike, not
;; a recreation, so it is not here.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-tooltips--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TooltipSamples.kt"
  "Upstream TooltipsExampleSourceUrl.")

(defconst jetpacs-m3-tooltips--plain-note
  "There is no tooltip node type and no tooltip universal attribute: a PlainTooltip is a transient surface anchored to a widget and raised by long-press, and the wire has no member that attaches one to a node."
  "Why the bare PlainTooltip sample is unsupported.")

(defconst jetpacs-m3-tooltips--rich-note
  "There is no rich tooltip node: RichTooltip is a persistent anchored panel carrying a title, supporting text and an action button, and the wire's only transient surface is the scaffold snackbar slot, which is a screen-level message with no anchor and no action button."
  "Why the bare RichTooltip sample is unsupported.")

(defun jetpacs-m3-tooltips--caret-note (placement)
  "Why the caret sample that places its tooltip PLACEMENT is unsupported.
PLACEMENT is the phrase naming this sample's TooltipAnchorPosition,
e.g. \"below the anchor\"."
  (concat "There is no tooltip node, so there is nothing for a caret to "
          "point from: this sample exists to put TooltipDefaults.caretShape() "
          placement
          ", and the wire has neither an anchored-popup member nor an "
          "anchor-position member to carry that."))

(jetpacs-m3-defcomponent "tooltips"
  :name "Tooltips"
  :description
  "Tooltips call user attention to an anchor component."
  :guidelines "https://m3.material.io/components/tooltips"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#tooltip"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Tooltip.kt"
  :examples
  (list
   (jetpacs-m3-example
    "PlainTooltipSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported jetpacs-m3-tooltips--plain-note)
   (jetpacs-m3-example
    "PlainTooltipWithManualInvocationSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    "Neither half is on the wire: there is no tooltip node, and no action descriptor asks the Companion to show a popup, which is the whole point of the \"Display tooltip\" button calling TooltipState.show() here.")
   (jetpacs-m3-example
    "PlainTooltipWithCaret"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported (jetpacs-m3-tooltips--caret-note "above the anchor"))
   (jetpacs-m3-example
    "PlainTooltipWithCaretBelowAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported (jetpacs-m3-tooltips--caret-note "below the anchor"))
   (jetpacs-m3-example
    "PlainTooltipWithCaretLeftOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    (jetpacs-m3-tooltips--caret-note "to the left of the anchor"))
   (jetpacs-m3-example
    "PlainTooltipWithCaretRightOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    (jetpacs-m3-tooltips--caret-note "to the right of the anchor"))
   (jetpacs-m3-example
    "PlainTooltipWithCaretStartOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    (jetpacs-m3-tooltips--caret-note
     "at the layout-direction start of the anchor"))
   (jetpacs-m3-example
    "PlainTooltipWithCaretEndOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    (jetpacs-m3-tooltips--caret-note
     "at the layout-direction end of the anchor"))
   (jetpacs-m3-example
    "PlainTooltipWithCustomCaret"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    "The subject here is a caret resized to DpSize(24.dp, 12.dp), and the wire has no tooltip node to hang a caret on, let alone a caret-size member: node geometry stops at the universal width and height attributes, which size the node itself.")
   (jetpacs-m3-example
    "RichTooltipSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported jetpacs-m3-tooltips--rich-note)
   (jetpacs-m3-example
    "RichTooltipWithManualInvocationSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    "Neither half is on the wire: there is no rich tooltip node, and no action descriptor shows or dismisses a popup, which is what the \"Display tooltip\" button and the tooltip's own action button do here.")
   (jetpacs-m3-example
    "RichTooltipWithCaretSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    "There is no rich tooltip node and no caret member: this sample adds TooltipDefaults.caretShape() to the persistent title/text/action panel, and the wire cannot describe the panel, its anchor or the caret joining them.")
   (jetpacs-m3-example
    "RichTooltipWithCustomCaretSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :unsupported
    "There is no rich tooltip node and no caret-size member: a caret of DpSize(32.dp, 16.dp) on an anchored persistent panel is Companion-side geometry the wire has no way to ask for.")
   ))

(provide 'jetpacs-m3-tooltips)
;;; jetpacs-m3-tooltips.el ends here
