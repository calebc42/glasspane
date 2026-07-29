;;; jetpacs-m3-split-button.el --- Catalog component: Split Button -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SplitButtons' + Examples.kt
;; `SplitButtonExamples' (12 examples), samples/SplitButtonSamples.kt.
;;
;; All twelve samples are one composable, `SplitButtonLayout': a leading
;; action button and a trailing toggle FUSED into a single container --
;; SplitButtonDefaults gives the outer corners a full radius, the inner
;; corners a small one and the seam a 2dp gap, and the trailing half is
;; `checked'/`onCheckedChange', morphing its shape while its
;; KeyboardArrowDown rotates through 180 degrees.  That fusion, and the
;; checked trailing half, are the whole subject; the leading content
;; (icon+text, text only, icon only), the color variant and the
;; container-height scale are just what each sample varies.
;;
;; M3-COMPONENT-LOOKUP puts SplitButton among the components Jetpacs
;; does not wrap.  The wire has `button' (label, on_tap, icon, variant,
;; enabled) and `icon_button' -- two independent containers with NO
;; CHECKED STATE, so for every sample whose trailing half is checkable
;; the shape morph and the 180-degree arrow rotation that the check
;; drives cannot be asked for, and a row of buttons would be a
;; lookalike rather than the component.
;;
;; The FUSED GEOMETRY itself does compose, though: `:corner' takes a
;; per-corner object on any node (`jetpacs--corner-keys') and `row'
;; takes `:spacing' -- which is how `jetpacs-m3-lists.el' builds
;; `ListItemDefaults.segmentedShapes'.  So the ONE sample with no
;; checked state anywhere, SplitButtonWithUnCheckableTrailingButtonSample,
;; whose whole subject IS that fusion, is recreated; the other eleven
;; are unsupported on the checked state each of them needs.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-split-button--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SplitButtonSamples.kt"
  "Upstream SplitButtonExampleSourceUrl.")

(defconst jetpacs-m3-split-button--layout-note
  "There is no split_button node, and no wire member holds the checked state of its trailing half: the shape morph and the 180-degree arrow rotation that SplitButtonLayout drives from onCheckedChange are what this sample exists to show."
  "Why a sample that varies only the leading content is unsupported.")

(defconst jetpacs-m3-split-button--fused-corner 20
  "The outer corner radius of a fused SplitButtonLayout half.
SplitButtonDefaults gives the outer corners a full radius and the
inner ones a small one; 20/4 over a 40dp-tall half reads as that.")

(defun jetpacs-m3-split-button--half (node leading)
  "NODE as one fused half: LEADING picks which corners are rounded."
  (jetpacs-with-attrs
   node
   :corner (if leading
               (list :top_start jetpacs-m3-split-button--fused-corner
                     :bottom_start jetpacs-m3-split-button--fused-corner
                     :top_end 4 :bottom_end 4)
             (list :top_end jetpacs-m3-split-button--fused-corner
                   :bottom_end jetpacs-m3-split-button--fused-corner
                   :top_start 4 :bottom_start 4))
   :bg "primary" :clip t))

(defun jetpacs-m3-split-button--uncheckable ()
  "Upstream SplitButtonWithUnCheckableTrailingButtonSample.
The one sample with no checked state anywhere, so its whole subject is
the fusion: two halves seamed 2dp apart, outer corners full radius and
inner corners small.  `:corner' takes exactly that per-corner object,
the same composition `jetpacs-m3-lists.el' uses for
`ListItemDefaults.segmentedShapes'."
  (jetpacs-row
   (jetpacs-m3-split-button--half
    (jetpacs-button "My Button" (jetpacs-m3-demo "My Button")
                    :icon "edit" :variant "filled")
    t)
   (jetpacs-m3-split-button--half
    (jetpacs-icon-button "keyboard_arrow_down"
                         (jetpacs-m3-demo "Toggle Button")
                         :content-description "Toggle Button")
    nil)
   :spacing 2 :align "center"))

(defconst jetpacs-m3-split-button--size-note
  "Two things are missing: there is no split_button node to fuse the two halves, and no size member for the SplitButtonDefaults container-height scale (ExtraSmall through ExtraLarge) with the shapes, content padding, icon sizes and text style it selects."
  "Why every container-height sample is unsupported.")

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
    :unsupported jetpacs-m3-split-button--layout-note)
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
    :unsupported
    "There is no split_button node, and the menu node carries its own icon trigger, so a DropdownMenu cannot be anchored to a split button's checkable trailing half; a menu item also has no divider and no trailing shortcut label for \"F11\".")
   (jetpacs-m3-example
    "TonalSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported
    "The button node does have a tonal variant, but there is no split_button node to fuse a TonalLeadingButton and a checkable TonalTrailingButton into the single container this sample exists to show.")
   (jetpacs-m3-example
    "ElevatedSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported
    "Neither half is on the wire: the button variant enum is filled/tonal/outlined/text with no elevated member, and there is no split_button node to fuse the two halves into one container.")
   (jetpacs-m3-example
    "OutlinedSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported
    "The button node does have an outlined variant, but there is no split_button node, so the shared outline that runs around both halves and turns inward at the seam cannot be asked for from Emacs.")
   (jetpacs-m3-example
    "SplitButtonWithTextSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported jetpacs-m3-split-button--layout-note)
   (jetpacs-m3-example
    "SplitButtonWithIconSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported
    "There is no split_button node, and the button node requires a label, so the icon-only LeadingButton this sample pairs with the checkable trailing half has no wire form of its own either.")
   (jetpacs-m3-example
    "XSmallFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported jetpacs-m3-split-button--size-note)
   (jetpacs-m3-example
    "MediumFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported jetpacs-m3-split-button--size-note)
   (jetpacs-m3-example
    "LargeFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported jetpacs-m3-split-button--size-note)
   (jetpacs-m3-example
    "ExtraLargeFilledSplitButtonSample"
    "Split Button examples"
    :source jetpacs-m3-split-button--source
    :expressive t
    :unsupported jetpacs-m3-split-button--size-note)
   ))

(provide 'jetpacs-m3-split-button)
;;; jetpacs-m3-split-button.el ends here
