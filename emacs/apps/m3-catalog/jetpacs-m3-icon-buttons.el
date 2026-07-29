;;; jetpacs-m3-icon-buttons.el --- Catalog component: Icon buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `IconButtons' + Examples.kt
;; `IconButtonExamples' (12 examples), samples/IconButtonSamples.kt.
;;
;; The `icon_button' node carries icon, on_tap, content_description,
;; badge and enabled -- and nothing else.  `RenderIconButton'
;; (InputNodes.kt:96) always calls the plain M3 `IconButton', so the
;; standard sample recreates exactly and every other one of the twelve
;; asks for something that has no wire member: a CONTAINER
;; (FilledIconButton, FilledTonalIconButton, OutlinedIconButton -- the
;; variant enum lives on `button', not on `icon_button'), a CHECKED
;; state (IconToggleButton and its three variants, which swap
;; Icons.Outlined.Lock for Icons.Filled.Lock), a TINT
;; (Icon(tint = Color.Red)) or a SIZE and SHAPE (the expressive
;; extraSmall/medium/large container scale with its Narrow/Uniform/Wide
;; width options and square/round shapes).
;;
;; Every sample in the upstream file wraps its button in a `TooltipBox'
;; carrying "Localized description", with the comment "Icon button
;; should have a tooltip associated with it for a11y".  That accessible
;; name is the `content_description' member here; Tooltip itself is not
;; a node type.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-icon-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/IconButtonSamples.kt"
  "Upstream IconButtonsExampleSourceUrl.")

(defconst jetpacs-m3-icon-buttons--variant-note
  "The icon_button node has no variant member: it always renders the standard M3 IconButton, so the filled, tonal or outlined container this sample exists to show cannot be asked for from Emacs."
  "Why every container-variant icon-button sample is unsupported.")

(defconst jetpacs-m3-icon-buttons--toggle-note
  "There is no icon toggle button node, and icon_button has no checked member: the two-state button that swaps Icons.Outlined.Lock for Icons.Filled.Lock cannot be put on the wire."
  "Why the plain IconToggleButton sample is unsupported.")

(defconst jetpacs-m3-icon-buttons--variant-toggle-note
  "Neither half is on the wire: icon_button has no checked member for the toggle state, and no variant member for the filled, tonal or outlined container."
  "Why every variant IconToggleButton sample is unsupported.")

(defconst jetpacs-m3-icon-buttons--size-note
  "The icon_button node has no size or shape member: the M3 expressive container-size scale (extraSmall through large), its Narrow/Uniform/Wide width options and the matching square and round shapes cannot be expressed on the wire."
  "Why every expressive size-and-shape sample is unsupported.")

(defun jetpacs-m3-icon-buttons--standard ()
  "Upstream IconButtonSample: IconButton showing Icons.Filled.Lock.
Upstream wraps it in a TooltipBox whose PlainTooltip repeats
\"Localized description\" for a11y; on the wire that accessible name is
the content_description member, which is what the tooltip supplies."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"))

(jetpacs-m3-defcomponent "icon-buttons"
  :name "Icon buttons"
  :description
  "Icon buttons allow users to take actions and make choices with a single tap."
  :guidelines "https://m3.material.io/components/icon-button"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#iconbutton"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/IconButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "IconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--standard)
   (jetpacs-m3-example
    "TintedIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported
    "The icon_button node draws its own Icon and has no tint or color member: Icon(tint = Color.Red), the one thing this sample adds to IconButtonSample, cannot be requested from Emacs.")
   (jetpacs-m3-example
    "IconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--toggle-note)
   (jetpacs-m3-example
    "FilledIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--variant-note)
   (jetpacs-m3-example
    "FilledIconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--variant-toggle-note)
   (jetpacs-m3-example
    "FilledTonalIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--variant-note)
   (jetpacs-m3-example
    "FilledTonalIconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--variant-toggle-note)
   (jetpacs-m3-example
    "OutlinedIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--variant-note)
   (jetpacs-m3-example
    "OutlinedIconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :unsupported jetpacs-m3-icon-buttons--variant-toggle-note)
   (jetpacs-m3-example
    "XSmallNarrowSquareIconButtonsSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :expressive t
    :unsupported
    "Neither half is on the wire: icon_button has no size or shape member for extraSmallContainerSize(Narrow) with extraSmallSquareShape, and no variant member for the filled container.")
   (jetpacs-m3-example
    "MediumRoundWideIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :expressive t
    :unsupported jetpacs-m3-icon-buttons--size-note)
   (jetpacs-m3-example
    "LargeRoundUniformOutlinedIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :expressive t
    :unsupported
    "Neither half is on the wire: icon_button has no size or shape member for largeContainerSize() with largeRoundShape, and no variant member for the outlined container.")
   ))

(provide 'jetpacs-m3-icon-buttons)
;;; jetpacs-m3-icon-buttons.el ends here
