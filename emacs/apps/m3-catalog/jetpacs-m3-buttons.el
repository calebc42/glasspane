;;; jetpacs-m3-buttons.el --- Catalog component: Buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Buttons' + Examples.kt `ButtonsExamples'
;; (17 examples), samples/ButtonSamples.kt.
;;
;; The `button' node carries label, on_tap, icon, variant
;; (filled/tonal/outlined/text) and enabled -- and nothing else.  So the
;; four plain variants and the with-icon sample recreate exactly; the
;; twelve that exist upstream to demonstrate a SHAPE (squareShape,
;; ButtonDefaults.shapes press morph), an ELEVATION (ElevatedButton) or
;; a SIZE (XSmall through XLarge container heights) have no wire member
;; to carry the thing they demonstrate, and say so.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ButtonSamples.kt"
  "Upstream ButtonsExampleSourceUrl.")

(defconst jetpacs-m3-buttons--shape-note
  "The button node has no shape member: M3 shape morphing on press (ButtonDefaults.shapes) is a Companion-side visual the wire cannot ask for."
  "Why every WithAnimatedShape sample is unsupported.")

(defconst jetpacs-m3-buttons--size-note
  "The button node has no size member: the M3 container-height scale (XSmall through XLarge) and its matching content padding cannot be expressed on the wire."
  "Why every size-variant sample is unsupported.")

(defun jetpacs-m3-buttons--filled ()
  "Upstream ButtonSample: Button(onClick = {}) { Text(\"Button\") }."
  (jetpacs-button "Button" (jetpacs-m3-demo "Button") :variant "filled"))

(defun jetpacs-m3-buttons--tonal ()
  "Upstream FilledTonalButtonSample."
  (jetpacs-button "Filled Tonal Button" (jetpacs-m3-demo "Filled Tonal Button")
                  :variant "tonal"))

(defun jetpacs-m3-buttons--outlined ()
  "Upstream OutlinedButtonSample."
  (jetpacs-button "Outlined Button" (jetpacs-m3-demo "Outlined Button")
                  :variant "outlined"))

(defun jetpacs-m3-buttons--text ()
  "Upstream TextButtonSample."
  (jetpacs-button "Text Button" (jetpacs-m3-demo "Text Button")
                  :variant "text"))

(defun jetpacs-m3-buttons--with-icon ()
  "Upstream ButtonWithIconSample: a leading Favorite icon and \"Like\"."
  (jetpacs-button "Like" (jetpacs-m3-demo "Like")
                  :icon "favorite" :variant "filled"))

(jetpacs-m3-defcomponent "buttons"
  :name "Buttons"
  :description
  "Buttons help people initiate actions, from sending an email, to sharing a document, to liking a post."
  :guidelines "https://m3.material.io/components/buttons"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#button"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Button.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :build #'jetpacs-m3-buttons--filled)
   (jetpacs-m3-example
    "ButtonWithAnimatedShapeSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--shape-note)
   (jetpacs-m3-example
    "SquareButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported
    "The button node has no shape member, so ButtonDefaults.squareShape cannot be requested from Emacs.")
   (jetpacs-m3-example
    "SmallButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--size-note)
   (jetpacs-m3-example
    "ElevatedButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :unsupported
    "The button variant enum is filled/tonal/outlined/text; M3 ElevatedButton is not one of them.")
   (jetpacs-m3-example
    "ElevatedButtonWithAnimatedShapeSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported
    "Neither half is on the wire: button has no elevated variant and no shape member.")
   (jetpacs-m3-example
    "FilledTonalButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :build #'jetpacs-m3-buttons--tonal)
   (jetpacs-m3-example
    "FilledTonalButtonWithAnimatedShapeSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--shape-note)
   (jetpacs-m3-example
    "OutlinedButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :build #'jetpacs-m3-buttons--outlined)
   (jetpacs-m3-example
    "OutlinedButtonWithAnimatedShapeSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--shape-note)
   (jetpacs-m3-example
    "TextButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :build #'jetpacs-m3-buttons--text)
   (jetpacs-m3-example
    "TextButtonWithAnimatedShapeSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--shape-note)
   (jetpacs-m3-example
    "ButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :build #'jetpacs-m3-buttons--with-icon)
   (jetpacs-m3-example
    "XSmallButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--size-note)
   (jetpacs-m3-example
    "MediumButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--size-note)
   (jetpacs-m3-example
    "LargeButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--size-note)
   (jetpacs-m3-example
    "XLargeButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :unsupported jetpacs-m3-buttons--size-note)
   ))

(provide 'jetpacs-m3-buttons)
;;; jetpacs-m3-buttons.el ends here
