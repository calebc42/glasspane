;;; jetpacs-m3-icon-buttons.el --- Catalog component: Icon buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `IconButtons' + Examples.kt
;; `IconButtonExamples' (12 examples), samples/IconButtonSamples.kt.
;;
;; The `icon_button' node carries icon, on_tap, content_description,
;; badge, variant, enabled -- and now checked, checked_icon, on_change,
;; size, shape and width_mode.  The variant enum (filled/tonal/
;; outlined) recreates the four CONTAINER samples, the checked member
;; the four TOGGLE samples, and the size/shape/width_mode trio the
;; three EXPRESSIVE geometry samples: the Companion derives the whole
;; coordinated set from one size step -- container via
;; IconButtonDefaults.<step>ContainerSize(width), the step's square or
;; round shape, and the matching <step>IconSize on the inner glyph.
;; The `:color' member then closed the last gap -- Icon(tint =
;; Color.Red), which no universal attribute could reach because the
;; node draws its own Icon.  All twelve build.
;;
;; Two honest limits on the toggles, both worth stating because they
;; are what the recreation does NOT reproduce.
;;
;; First the glyphs.  Every upstream toggle swaps Icons.Outlined.Lock
;; for Icons.Filled.Lock, one glyph in two weights -- and those are ONE
;; `lock' name here, because IconMap resolves Icons.Outlined first and
;; reaches Icons.Filled only for names Outlined lacks.  A wire toggle
;; distinguishes its two states by NAME, through checked_icon, so the
;; unchecked state takes `lock_open' and the checked state takes `lock'.
;; Naming two glyphs is as close as identifiers get to one glyph in two
;; weights; the checked state is upstream's, the unchecked one is a
;; stand-in.
;;
;; Second the containers.  There is no *IconToggleButton on the wire,
;; only `icon_button' with a checked member: the Companion draws the
;; variant's own container and swaps the glyph under it, so the M3
;; checked/unchecked container pair (surfaceVariant -> primary on a
;; FilledIconToggleButton) is not what a tap changes here.  `checked'
;; reaches the eye as the glyph alone.
;;
;; A tap on a toggle dispatches on_change and then on_tap, which here
;; would report the same one string twice, so the toggles carry
;; `jetpacs-m3-demo' on on_tap alone.  Nothing is lost: upstream's
;; `onCheckedChange = { checked = it }' only writes the state the
;; Companion already holds on the device, keyed on the node's id.
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

(defun jetpacs-m3-icon-buttons--standard ()
  "Upstream IconButtonSample: IconButton showing Icons.Filled.Lock.
Upstream wraps it in a TooltipBox whose PlainTooltip repeats
\"Localized description\" for a11y; on the wire that accessible name is
the content_description member, which is what the tooltip supplies."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"))

(defun jetpacs-m3-icon-buttons--filled ()
  "Upstream FilledIconButtonSample: FilledIconButton showing Icons.Filled.Lock.
The filled container is the variant member; the a11y name upstream
supplies through its TooltipBox is content_description."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"
                       :variant "filled"))

(defun jetpacs-m3-icon-buttons--filled-tonal ()
  "Upstream FilledTonalIconButtonSample: FilledTonalIconButton, Icons.Filled.Lock.
The tonal container is the variant member; the a11y name upstream
supplies through its TooltipBox is content_description."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"
                       :variant "tonal"))

(defun jetpacs-m3-icon-buttons--outlined ()
  "Upstream OutlinedIconButtonSample: OutlinedIconButton, Icons.Filled.Lock.
The outlined container is the variant member; the a11y name upstream
supplies through its TooltipBox is content_description."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"
                       :variant "outlined"))

(defun jetpacs-m3-icon-buttons--lock-toggle (id variant)
  "The lock toggle every *IconToggleButtonSample is, as node ID.
VARIANT is the container (nil for the plain, container-less one).
Upstream opens on `checked = false' and flips it in onCheckedChange; on
the wire `checked' opens :json-false, the tap flips it on the device
and §16.1 keys that state on ID, which is why every toggle here needs
one and the four plain icon buttons above need none.  `checked_icon'
is the whole two-state display: see the Commentary for why the pair is
`lock_open' and `lock' rather than the one Lock in two weights."
  (jetpacs-with-attrs
   (jetpacs-icon-button "lock_open" (jetpacs-m3-demo "Localized description")
                        :content-description "Localized description"
                        :checked :json-false
                        :checked-icon "lock"
                        :variant variant)
   :id id))

(defun jetpacs-m3-icon-buttons--xsmall-narrow-square ()
  "Upstream ExtraSmallNarrowSquareIconButtonsSample (the catalog's XSmall).
A FilledIconButton at extraSmallContainerSize(Narrow) wearing
extraSmallSquareShape, its Lock glyph at extraSmallIconSize -- one size
step, three coordinated tokens, all derived from :size on the device."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"
                       :variant "filled"
                       :size "xsmall" :width-mode "narrow" :shape "square"))

(defun jetpacs-m3-icon-buttons--medium-round-wide ()
  "Upstream MediumRoundWideIconButtonSample: the plain container, sized.
An IconButton at mediumContainerSize(Wide) wearing mediumRoundShape,
the glyph at mediumIconSize.  No :variant -- upstream uses the
standard, container-less IconButton."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"
                       :size "medium" :width-mode "wide" :shape "round"))

(defun jetpacs-m3-icon-buttons--large-round-outlined ()
  "Upstream LargeRoundUniformOutlinedIconButtonSample.
An OutlinedIconButton at largeContainerSize() -- Uniform width, the
default, so no :width-mode -- wearing largeRoundShape, the glyph at
largeIconSize."
  (jetpacs-icon-button "lock" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"
                       :variant "outlined"
                       :size "large" :shape "round"))

(defun jetpacs-m3-icon-buttons--toggle ()
  "Upstream IconToggleButtonSample: the plain, container-less IconToggleButton."
  (jetpacs-m3-icon-buttons--lock-toggle "icon-buttons-toggle" nil))

(defun jetpacs-m3-icon-buttons--filled-toggle ()
  "Upstream FilledIconToggleButtonSample: the toggle in the filled container.
The container is the variant member; it does not itself change with
`checked', which is the limit the Commentary records."
  (jetpacs-m3-icon-buttons--lock-toggle "icon-buttons-filled-toggle" "filled"))

(defun jetpacs-m3-icon-buttons--filled-tonal-toggle ()
  "Upstream FilledTonalIconToggleButtonSample: the toggle, tonal container.
The container is the variant member; it does not itself change with
`checked', which is the limit the Commentary records."
  (jetpacs-m3-icon-buttons--lock-toggle "icon-buttons-tonal-toggle" "tonal"))

(defun jetpacs-m3-icon-buttons--outlined-toggle ()
  "Upstream OutlinedIconToggleButtonSample: the toggle, outlined container.
The container is the variant member; it does not itself change with
`checked', which is the limit the Commentary records."
  (jetpacs-m3-icon-buttons--lock-toggle "icon-buttons-outlined-toggle"
                                        "outlined"))

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
    :build (lambda ()
             ;; Icon(tint = Color.Red) — the one thing this sample adds to
             ;; IconButtonSample, now the :color member.
             (jetpacs-icon-button "lock"
                                  (jetpacs-m3-demo "Localized description")
                                  :content-description "Localized description"
                                  :color "#FF0000")))
   (jetpacs-m3-example
    "IconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--toggle)
   (jetpacs-m3-example
    "FilledIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--filled)
   (jetpacs-m3-example
    "FilledIconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--filled-toggle)
   (jetpacs-m3-example
    "FilledTonalIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--filled-tonal)
   (jetpacs-m3-example
    "FilledTonalIconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--filled-tonal-toggle)
   (jetpacs-m3-example
    "OutlinedIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--outlined)
   (jetpacs-m3-example
    "OutlinedIconToggleButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :build #'jetpacs-m3-icon-buttons--outlined-toggle)
   (jetpacs-m3-example
    "XSmallNarrowSquareIconButtonsSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :expressive t
    :build #'jetpacs-m3-icon-buttons--xsmall-narrow-square)
   (jetpacs-m3-example
    "MediumRoundWideIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :expressive t
    :build #'jetpacs-m3-icon-buttons--medium-round-wide)
   (jetpacs-m3-example
    "LargeRoundUniformOutlinedIconButtonSample"
    "Icon button examples"
    :source jetpacs-m3-icon-buttons--source
    :expressive t
    :build #'jetpacs-m3-icon-buttons--large-round-outlined)
   ))

(provide 'jetpacs-m3-icon-buttons)
;;; jetpacs-m3-icon-buttons.el ends here
