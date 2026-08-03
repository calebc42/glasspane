;;; jetpacs-m3-split-button.el --- Catalog component: Split Button -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SplitButtons' + Examples.kt
;; `SplitButtonExamples' (12 examples), samples/SplitButtonSamples.kt.
;;
;; All twelve samples are one composable, `SplitButtonLayout': a leading
;; action button and a trailing button FUSED into a single container --
;; SplitButtonDefaults gives the outer corners a full radius, the inner
;; corners a small one and the seam a 2dp gap, and the trailing half is
;; usually `checked'/`onCheckedChange', morphing its shape while its
;; KeyboardArrowDown rotates through 180 degrees.
;;
;; That component is the `split_button' node, so the fusion, the checked
;; trailing half and its rotation are asked for by name instead of drawn
;; as a lookalike row of two buttons.  Each sample is ONE node: the
;; label and `:icon' are the leading content, `:variant' and `:size'
;; apply to BOTH halves (and `elevated' is a variant here, unlike
;; `button'), and the trailing half is whichever of the three forms the
;; sample uses -- `:checked' with `:on-change' for the nine toggles,
;; `:on-trailing-tap' for the uncheckable one, `:items' for the one that
;; opens a DropdownMenu.
;;
;; Upstream wraps every icon-only half in a TooltipBox for one reason,
;; stated in its own comment: the icon needs an accessible name.
;; `:trailing-description' is that name on the wire -- upstream's
;; `contentDescription = description' on the trailing semantics -- so no
;; `tooltip' node wraps these.  One that did would anchor to the whole
;; split button and so describe the leading half too, which is not what
;; upstream anchors it to.
;;
;; The label became optional for SplitButtonWithIconSample's sake -- a
;; leading half may be a label, an icon, or both, never neither -- so
;; the icon-only form recreates and all twelve build.  Label-less, the
;; icon identifier is the accessible fallback name; upstream's tooltip
;; naming it "Button" cannot ride (the icon slot takes an identifier,
;; not a node), which parallels the tabs' tooltip seam, closed there by
;; tab_item.tooltip and still open here.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-split-button--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SplitButtonSamples.kt"
  "Upstream SplitButtonExampleSourceUrl.")

(defun jetpacs-m3-split-button--toggle (id label &rest options)
  "A `split_button' labeled LABEL whose trailing half toggles, keyed on ID.
OPTIONS are extra `jetpacs-split-button' keywords.  Every sample here but
two starts at `mutableStateOf(false)' and flips it from the trailing
half's `onCheckedChange': `:checked :json-false' is that state and is
what makes the trailing half a toggle at all, ID is the §16.1 address it
is published on, and `:on-change' receives the flipped boolean.  The
KeyboardArrowDown and its 180-degree rotation are the node's own -- the
arrow is the default trailing icon and the check is what turns it.

`:trailing-description' is upstream's `contentDescription = description'
on the trailing semantics.  What that semantics block also sets and the
wire does not carry is `stateDescription', the \"Expanded\"/\"Collapsed\"
a screen reader would announce alongside the name."
  (jetpacs-with-attrs
   (apply #'jetpacs-split-button label (jetpacs-m3-demo label)
          :trailing-description "Toggle Button"
          :checked :json-false
          :on-change (jetpacs-m3-demo "Toggle Button")
          options)
   :id id))

(defun jetpacs-m3-split-button--filled ()
  "Upstream FilledSplitButtonSample: the plain SplitButtonDefaults halves."
  (jetpacs-m3-split-button--toggle "split-button-filled" "My Button"
                                   :icon "edit" :variant "filled"))

(defun jetpacs-m3-split-button--uncheckable ()
  "Upstream SplitButtonWithUnCheckableTrailingButtonSample.
The one sample whose trailing half is a plain `onClick' TrailingButton
rather than a toggle: no `:checked', so the node is stateless and takes
no `:id', and `:on-trailing-tap' is the third of the trailing forms."
  (jetpacs-split-button "My Button" (jetpacs-m3-demo "My Button")
                        :icon "edit" :variant "filled"
                        :trailing-description "Toggle Button"
                        :on-trailing-tap (jetpacs-m3-demo "Toggle Button")))

(defun jetpacs-m3-split-button--with-dropdown-menu ()
  "Upstream SplitButtonWithDropdownMenuSample: the trailing half opens a menu.
`:items' is that DropdownMenu, and it takes precedence over `:checked' --
upstream's checked state exists only to be the menu's `expanded', so the
node holds no state of its own and takes no `:id'.  The three items keep
their upstream labels and Outlined leading icons; what the MenuItem
record cannot carry rides along as loss, exactly as in
`jetpacs-m3-menus.el': the HorizontalDivider above \"Send Feedback\" and
that item's \"F11\" trailing shortcut text."
  (jetpacs-split-button "My Button" (jetpacs-m3-demo "My Button")
                        :icon "edit" :variant "filled"
                        :trailing-description "Toggle Button"
                        :items
                        (list (jetpacs-menu-item "Edit" (jetpacs-m3-demo "Edit")
                                                 :icon "edit")
                              (jetpacs-menu-item "Settings"
                                                 (jetpacs-m3-demo "Settings")
                                                 :icon "settings")
                              (jetpacs-menu-item "Send Feedback"
                                                 (jetpacs-m3-demo "Send Feedback")
                                                 :icon "email"))))

(defun jetpacs-m3-split-button--tonal ()
  "Upstream TonalSplitButtonSample: TonalLeadingButton + TonalTrailingButton.
`:variant' applies to both halves, which is what the sample varies."
  (jetpacs-m3-split-button--toggle "split-button-tonal" "My Button"
                                   :icon "edit" :variant "tonal"))

(defun jetpacs-m3-split-button--elevated ()
  "Upstream ElevatedSplitButtonSample: the Elevated leading and trailing halves."
  (jetpacs-m3-split-button--toggle "split-button-elevated" "My Button"
                                   :icon "edit" :variant "elevated"))

(defun jetpacs-m3-split-button--outlined ()
  "Upstream OutlinedSplitButtonSample: the outline runs around both halves."
  (jetpacs-m3-split-button--toggle "split-button-outlined" "My Button"
                                   :icon "edit" :variant "outlined"))

(defun jetpacs-m3-split-button--with-text ()
  "Upstream SplitButtonWithTextSample: a LeadingButton of Text alone.
The only sample with no leading icon, so the node carries no `:icon'."
  (jetpacs-m3-split-button--toggle "split-button-with-text" "My Button"))

(defun jetpacs-m3-split-button--xsmall ()
  "Upstream XSmallFilledSplitButtonSample: ExtraSmallContainerHeight.
`:size' selects the SplitButtonDefaults scale for BOTH halves -- the
shapes, content padding, icon sizes and text style the sample threads
through `leadingButtonShapesFor(size)' and its siblings."
  (jetpacs-m3-split-button--toggle "split-button-xsmall" "My Button"
                                   :icon "edit" :size "xsmall"))

(defun jetpacs-m3-split-button--medium ()
  "Upstream MediumFilledSplitButtonSample: MediumContainerHeight."
  (jetpacs-m3-split-button--toggle "split-button-medium" "My Button"
                                   :icon "edit" :size "medium"))

(defun jetpacs-m3-split-button--large ()
  "Upstream LargeFilledSplitButtonSample: LargeContainerHeight."
  (jetpacs-m3-split-button--toggle "split-button-large" "My Button"
                                   :icon "edit" :size "large"))

(defun jetpacs-m3-split-button--xlarge ()
  "Upstream ExtraLargeFilledSplitButtonSample: ExtraLargeContainerHeight.
This is the one sample whose leading text is \"Button\", not \"My
Button\"."
  (jetpacs-m3-split-button--toggle "split-button-xlarge" "Button"
                                   :icon "edit" :size "xlarge"))

(jetpacs-m3-defcomponent "split-button"
  :name "Split Button"
  :description
  "Split buttons let user perform additional actions besides the main action"
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/SplitButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "FilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--filled)
   (jetpacs-m3-example
    "SplitButtonWithUnCheckableTrailingButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--uncheckable)
   (jetpacs-m3-example
    "SplitButtonWithDropdownMenuSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--with-dropdown-menu)
   (jetpacs-m3-example
    "TonalSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--tonal)
   (jetpacs-m3-example
    "ElevatedSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--elevated)
   (jetpacs-m3-example
    "OutlinedSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--outlined)
   (jetpacs-m3-example
    "SplitButtonWithTextSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--with-text)
   (jetpacs-m3-example
    "SplitButtonWithIconSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build (lambda ()
             ;; The leading half is Icons.Filled.Edit alone — the form the
             ;; label went optional for.
             (jetpacs-with-attrs
              (jetpacs-split-button nil (jetpacs-m3-demo "Button")
                                    :icon "edit"
                                    :trailing-description "Toggle Button"
                                    :checked :json-false
                                    :on-change (jetpacs-m3-demo "Toggle Button"))
              :id "split-button-with-icon")))
   (jetpacs-m3-example
    "XSmallFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--xsmall)
   (jetpacs-m3-example
    "MediumFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--medium)
   (jetpacs-m3-example
    "LargeFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--large)
   (jetpacs-m3-example
    "ExtraLargeFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :build #'jetpacs-m3-split-button--xlarge)
   ))

(provide 'jetpacs-m3-split-button)
;;; jetpacs-m3-split-button.el ends here
