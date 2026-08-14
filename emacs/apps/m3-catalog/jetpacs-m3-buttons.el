;;; jetpacs-m3-buttons.el --- Catalog component: Buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Buttons' + Examples.kt `ButtonsExamples'
;; (17 examples), samples/ButtonSamples.kt.
;;
;; The `button' node carries label, on_tap, icon, enabled, variant
;; (filled/tonal/elevated/outlined/text), size (xsmall..xlarge), shape
;; (round/square) and animate_shape -- which is the whole of what this
;; sample file demonstrates, so all seventeen examples build.  The five
;; variants map one-to-one onto Button/FilledTonalButton/ElevatedButton/
;; OutlinedButton/TextButton; `animate_shape' is the ButtonDefaults.shapes()
;; press morph; `shape' is ButtonDefaults.squareShape; and a `size' step is
;; the coordinated ButtonDefaults token set (container height, content
;; padding, icon size, icon spacing, label typography) the WithIcon size
;; samples spell out by hand.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ButtonSamples.kt"
  "Upstream ButtonsExampleSourceUrl.")

(defun jetpacs-m3-buttons--filled ()
  "Upstream ButtonSample: Button(onClick = {}) { Text(\"Button\") }."
  (jetpacs-button "Button" (jetpacs-m3-demo "Button") :variant "filled"))

(defun jetpacs-m3-buttons--animated-shape ()
  "Upstream ButtonWithAnimatedShapeSample: shapes = ButtonDefaults.shapes()."
  (jetpacs-button "Button" (jetpacs-m3-demo "Button")
                  :variant "filled" :animate-shape t))

(defun jetpacs-m3-buttons--square ()
  "Upstream SquareButtonSample: shape = ButtonDefaults.squareShape."
  (jetpacs-button "Button" (jetpacs-m3-demo "Button")
                  :variant "filled" :shape "square"))

(defun jetpacs-m3-buttons--small ()
  "Upstream SmallButtonSample: contentPadding = ButtonDefaults.SmallContentPadding."
  (jetpacs-button "Button" (jetpacs-m3-demo "Button")
                  :variant "filled" :size "small"))

(defun jetpacs-m3-buttons--elevated ()
  "Upstream ElevatedButtonSample."
  (jetpacs-button "Elevated Button" (jetpacs-m3-demo "Elevated Button")
                  :variant "elevated"))

(defun jetpacs-m3-buttons--elevated-animated-shape ()
  "Upstream ElevatedButtonWithAnimatedShapeSample."
  (jetpacs-button "Elevated Button" (jetpacs-m3-demo "Elevated Button")
                  :variant "elevated" :animate-shape t))

(defun jetpacs-m3-buttons--tonal ()
  "Upstream FilledTonalButtonSample."
  (jetpacs-button "Filled Tonal Button" (jetpacs-m3-demo "Filled Tonal Button")
                  :variant "tonal"))

(defun jetpacs-m3-buttons--tonal-animated-shape ()
  "Upstream FilledTonalButtonWithAnimatedShapeSample."
  (jetpacs-button "Filled Tonal Button" (jetpacs-m3-demo "Filled Tonal Button")
                  :variant "tonal" :animate-shape t))

(defun jetpacs-m3-buttons--outlined ()
  "Upstream OutlinedButtonSample."
  (jetpacs-button "Outlined Button" (jetpacs-m3-demo "Outlined Button")
                  :variant "outlined"))

(defun jetpacs-m3-buttons--outlined-animated-shape ()
  "Upstream OutlinedButtonWithAnimatedShapeSample."
  (jetpacs-button "Outlined Button" (jetpacs-m3-demo "Outlined Button")
                  :variant "outlined" :animate-shape t))

(defun jetpacs-m3-buttons--text ()
  "Upstream TextButtonSample."
  (jetpacs-button "Text Button" (jetpacs-m3-demo "Text Button")
                  :variant "text"))

(defun jetpacs-m3-buttons--text-animated-shape ()
  "Upstream TextButtonWithAnimatedShapeSample."
  (jetpacs-button "Text Button" (jetpacs-m3-demo "Text Button")
                  :variant "text" :animate-shape t))

(defun jetpacs-m3-buttons--with-icon ()
  "Upstream ButtonWithIconSample: a leading Favorite icon and \"Like\"."
  (jetpacs-button "Like" (jetpacs-m3-demo "Like")
                  :icon "favorite" :variant "filled"))

(defun jetpacs-m3-buttons--xsmall-with-icon ()
  "Upstream XSmallButtonWithIconSample: ExtraSmallContainerHeight."
  (jetpacs-button "Label" (jetpacs-m3-demo "Label")
                  :icon "edit" :variant "filled" :size "xsmall"))

(defun jetpacs-m3-buttons--medium-with-icon ()
  "Upstream MediumButtonWithIconSample: MediumContainerHeight."
  (jetpacs-button "Label" (jetpacs-m3-demo "Label")
                  :icon "edit" :variant "filled" :size "medium"))

(defun jetpacs-m3-buttons--large-with-icon ()
  "Upstream LargeButtonWithIconSample: LargeContainerHeight."
  (jetpacs-button "Label" (jetpacs-m3-demo "Label")
                  :icon "edit" :variant "filled" :size "large"))

(defun jetpacs-m3-buttons--xlarge-with-icon ()
  "Upstream XLargeButtonWithIconSample: ExtraLargeContainerHeight."
  (jetpacs-button "Label" (jetpacs-m3-demo "Label")
                  :icon "edit" :variant "filled" :size "xlarge"))

(jetpacs-m3-defcomponent "buttons"
  :builders (list #'jetpacs-button)
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
    :build #'jetpacs-m3-buttons--animated-shape)
   (jetpacs-m3-example
    "SquareButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :build #'jetpacs-m3-buttons--square)
   (jetpacs-m3-example
    "SmallButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :build #'jetpacs-m3-buttons--small)
   (jetpacs-m3-example
    "ElevatedButtonSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :build #'jetpacs-m3-buttons--elevated)
   (jetpacs-m3-example
    "ElevatedButtonWithAnimatedShapeSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :build #'jetpacs-m3-buttons--elevated-animated-shape)
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
    :build #'jetpacs-m3-buttons--tonal-animated-shape)
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
    :build #'jetpacs-m3-buttons--outlined-animated-shape)
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
    :build #'jetpacs-m3-buttons--text-animated-shape)
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
    :build #'jetpacs-m3-buttons--xsmall-with-icon)
   (jetpacs-m3-example
    "MediumButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :build #'jetpacs-m3-buttons--medium-with-icon)
   (jetpacs-m3-example
    "LargeButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :build #'jetpacs-m3-buttons--large-with-icon)
   (jetpacs-m3-example
    "XLargeButtonWithIconSample"
    "Button examples"
    :source jetpacs-m3-buttons--source
    :expressive t
    :build #'jetpacs-m3-buttons--xlarge-with-icon)
   ))

(provide 'jetpacs-m3-buttons)
;;; jetpacs-m3-buttons.el ends here
