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
;; The `tooltip' node now carries that: it wraps its ANCHOR children
;; the way `badge' wraps its own, the anchor keeps its own `on_tap'
;; (a tooltip is raised by long press, not by consuming the tap), and
;; `position' spells all six anchor positions -- with `left'/`right'
;; kept ABSOLUTE and therefore distinct from the direction-relative
;; `start'/`end', which is exactly the distinction four of these
;; samples exist to draw.  `caret' grows the pointer aimed back at the
;; anchor; `rich' selects M3's RichTooltip with its `title' and its
;; `action_label'/`on_action' button; `shown' asks the Companion to
;; display without the long press.  Eleven samples are recreated on it.
;;
;; The two that are not are the CUSTOM-caret pair.  `caret' is a
;; boolean -- TooltipDefaults.caretShape() or nothing -- and those two
;; samples exist for the argument to it, DpSize(24.dp, 12.dp) and
;; DpSize(32.dp, 16.dp).  A default caret renders in their place, so
;; the temptation is to call them done; but a resized caret is the only
;; thing either one was demonstrating, which is the
;; `ButtonWithAnimatedShapeSample' rule.
;;
;; What the manual-invocation pair keeps and what it drops is spelled
;; out on `jetpacs-m3-tooltips--display-button'.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-tooltips--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TooltipSamples.kt"
  "Upstream TooltipsExampleSourceUrl.")

(defconst jetpacs-m3-tooltips--subhead "Permissions"
  "Upstream `richTooltipSubheadText'.")

(defconst jetpacs-m3-tooltips--text
  "Configure permissions for selected service accounts. You can add and remove service account members and assign roles to them. Visit go/permissions for details"
  "Upstream `richTooltipText'.")

(defconst jetpacs-m3-tooltips--action-text "Request Access"
  "Upstream `richTooltipActionText'.")

(defun jetpacs-m3-tooltips--anchor (icon)
  "The IconButton every sample anchors its tooltip to, drawn with ICON.
Upstream's `onClick' is the comment \"Icon button's click event\": the
anchor keeps a tap of its own precisely because the tooltip is raised by
the long press instead of by it."
  (jetpacs-icon-button icon (jetpacs-m3-demo "Icon button's click event")
                       :content-description "Localized Description"))

(defun jetpacs-m3-tooltips--plain-caret (position)
  "A caret tooltip \"Add to favorites\" placed at POSITION over a Favorite icon.
The six `PlainTooltipWithCaret*' samples differ in nothing else: each is
`TooltipDefaults.rememberTooltipPositionProvider' handed one
TooltipAnchorPosition, over `PlainTooltip(caretShape =
TooltipDefaults.caretShape())'."
  (jetpacs-tooltip "Add to favorites"
                   (jetpacs-m3-tooltips--anchor "favorite")
                   :position position :caret t))

(defun jetpacs-m3-tooltips--rich (&rest args)
  "The RichTooltip the Rich samples share, over an Info icon.
ARGS are the extra tooltip options a given sample varies, e.g. :caret.

Upstream's action button dismisses the tooltip; the Companion dismisses
after dispatching `on_action', so the descriptor here reports the label
and the dismissal is the renderer's."
  (apply #'jetpacs-tooltip jetpacs-m3-tooltips--text
         (jetpacs-m3-tooltips--anchor "info")
         :rich t
         :title jetpacs-m3-tooltips--subhead
         :action-label jetpacs-m3-tooltips--action-text
         :on-action (jetpacs-m3-demo jetpacs-m3-tooltips--action-text)
         args))

(defun jetpacs-m3-tooltips--index (name)
  "The upstream position of this component's example called NAME.
Looked up rather than written down, because the number is an address on
the wire: a stale literal would send \"Display tooltip\" to a different
sample's screen with nothing to say so."
  (or (cl-position name
                   (plist-get (jetpacs-m3-component "tooltips") :examples)
                   :key (lambda (e) (plist-get e :name)) :test #'equal)
      (error "jetpacs-m3-tooltips: no example named %s" name)))

(defun jetpacs-m3-tooltips--display-button (name)
  "Upstream's \"Display tooltip\" OutlinedButton, for the example NAME.

Upstream it calls `TooltipState.show()'.  On the wire that is
`tooltip.shown' -- authored presentation state, not a verb -- so the
tooltip enters the screen already displayed, which is the axis the
sample varies: raised without the long press.  The button then re-asks
for this same Example screen through `m3catalog.example', the catalog's
existing re-push (an id already on the chrome stack truncates to itself,
so this is re-entrant navigation, not a fourth screen), and the snapshot
it re-sends carries :shown t.

What is NOT here is a per-example toggle: a component module registers
no actions, so the button re-asserts the shown state rather than
flipping it off and on."
  (jetpacs-button "Display tooltip"
                  (jetpacs-action "m3catalog.example"
                                  :args (list :component "tooltips"
                                              :index (jetpacs-m3-tooltips--index
                                                      name)))
                  :variant "outlined"))

(defun jetpacs-m3-tooltips--manual (tooltip name)
  "Upstream's manual-invocation Column: TOOLTIP, a 30dp Spacer, the button.
NAME is the sample's own upstream name, which
`jetpacs-m3-tooltips--display-button' turns back into its screen."
  (jetpacs-column tooltip
                  (jetpacs-with-attrs (jetpacs-spacer) :height 30)
                  (jetpacs-m3-tooltips--display-button name)
                  :align "center"))

(defun jetpacs-m3-tooltips--plain ()
  "Upstream PlainTooltipSample."
  (jetpacs-tooltip "Add to favorites"
                   (jetpacs-m3-tooltips--anchor "favorite")))

(defun jetpacs-m3-tooltips--plain-manual ()
  "Upstream PlainTooltipWithManualInvocationSample."
  (jetpacs-m3-tooltips--manual
   (jetpacs-tooltip "Add to list"
                    (jetpacs-m3-tooltips--anchor "add_circle")
                    :shown t)
   "PlainTooltipWithManualInvocationSample"))

(defun jetpacs-m3-tooltips--caret-above ()
  "Upstream PlainTooltipWithCaret (TooltipAnchorPosition.Above)."
  (jetpacs-m3-tooltips--plain-caret "above"))

(defun jetpacs-m3-tooltips--caret-below ()
  "Upstream PlainTooltipWithCaretBelowAnchor (TooltipAnchorPosition.Below)."
  (jetpacs-m3-tooltips--plain-caret "below"))

(defun jetpacs-m3-tooltips--caret-left ()
  "Upstream PlainTooltipWithCaretLeftOfAnchor (TooltipAnchorPosition.Left)."
  (jetpacs-m3-tooltips--plain-caret "left"))

(defun jetpacs-m3-tooltips--caret-right ()
  "Upstream PlainTooltipWithCaretRightOfAnchor (TooltipAnchorPosition.Right)."
  (jetpacs-m3-tooltips--plain-caret "right"))

(defun jetpacs-m3-tooltips--caret-start ()
  "Upstream PlainTooltipWithCaretStartOfAnchor (TooltipAnchorPosition.Start)."
  (jetpacs-m3-tooltips--plain-caret "start"))

(defun jetpacs-m3-tooltips--caret-end ()
  "Upstream PlainTooltipWithCaretEndOfAnchor (TooltipAnchorPosition.End)."
  (jetpacs-m3-tooltips--plain-caret "end"))

(defun jetpacs-m3-tooltips--custom-caret ()
  "Upstream PlainTooltipWithCustomCaret: caretShape(DpSize(24.dp, 12.dp)).
\"Add to favorites\" over the Favorite anchor, like the six positional
caret samples, because the ARGUMENT to `caretShape' is the only axis
this one varies.  `:caret-width' and `:caret-height' are that argument:
they come as a pair and only beside `:caret t', the default-shaped
pointer they resize."
  ;; The sample IS the argument to caretShape: DpSize(24.dp, 12.dp).
  (jetpacs-tooltip "Add to favorites"
                   (jetpacs-m3-tooltips--anchor "favorite")
                   :caret t :caret-width 24 :caret-height 12))

(defun jetpacs-m3-tooltips--rich-plain ()
  "Upstream RichTooltipSample."
  (jetpacs-m3-tooltips--rich))

(defun jetpacs-m3-tooltips--rich-manual ()
  "Upstream RichTooltipWithManualInvocationSample."
  (jetpacs-m3-tooltips--manual (jetpacs-m3-tooltips--rich :shown t)
                               "RichTooltipWithManualInvocationSample"))

(defun jetpacs-m3-tooltips--rich-caret ()
  "Upstream RichTooltipWithCaretSample."
  (jetpacs-m3-tooltips--rich :caret t))

(defun jetpacs-m3-tooltips--rich-custom-caret ()
  "Upstream RichTooltipWithCustomCaretSample: caretShape(DpSize(32.dp, 16.dp)).
The rich twin of `jetpacs-m3-tooltips--custom-caret': the shared
RichTooltip of `jetpacs-m3-tooltips--rich' -- Permissions subhead, body
and Request Access button over the Info anchor -- with its caret sized
by the sample's own DpSize rather than left at the default."
  ;; The rich twin: caretShape(DpSize(32.dp, 16.dp)).
  (jetpacs-m3-tooltips--rich :caret t
                             :caret-width 32 :caret-height 16))

(jetpacs-m3-defcomponent "tooltips"
  :builders (list #'jetpacs-tooltip)
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
    :build #'jetpacs-m3-tooltips--plain)
   (jetpacs-m3-example
    "PlainTooltipWithManualInvocationSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--plain-manual)
   (jetpacs-m3-example
    "PlainTooltipWithCaret"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--caret-above)
   (jetpacs-m3-example
    "PlainTooltipWithCaretBelowAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--caret-below)
   (jetpacs-m3-example
    "PlainTooltipWithCaretLeftOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--caret-left)
   (jetpacs-m3-example
    "PlainTooltipWithCaretRightOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--caret-right)
   (jetpacs-m3-example
    "PlainTooltipWithCaretStartOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--caret-start)
   (jetpacs-m3-example
    "PlainTooltipWithCaretEndOfAnchor"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--caret-end)
   (jetpacs-m3-example
    "PlainTooltipWithCustomCaret"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--custom-caret)
   (jetpacs-m3-example
    "RichTooltipSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--rich-plain)
   (jetpacs-m3-example
    "RichTooltipWithManualInvocationSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--rich-manual)
   (jetpacs-m3-example
    "RichTooltipWithCaretSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--rich-caret)
   (jetpacs-m3-example
    "RichTooltipWithCustomCaretSample"
    "Tooltips examples"
    :source jetpacs-m3-tooltips--source
    :build #'jetpacs-m3-tooltips--rich-custom-caret)
   ))

(provide 'jetpacs-m3-tooltips)
;;; jetpacs-m3-tooltips.el ends here
