;;; jetpacs-m3-card.el --- Catalog component: Card -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Card' + Examples.kt
;; `CardExamples' (6 examples).
;;
;; The six samples are one matrix: three M3 container styles (Card,
;; ElevatedCard, OutlinedCard) crossed with the plain and the onClick
;; overload.  Both axes are now on the wire -- the `card' node carries
;; `variant' (filled, elevated, outlined) and `on_tap' -- so all six
;; land, and the module is one 180x100 helper called six times.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-card--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/CardSamples.kt"
  "Upstream CardExampleSourceUrl.")

(defconst jetpacs-m3-card--width 180
  "The dp width upstream gives every card sample (Modifier.size).")

(defconst jetpacs-m3-card--height 100
  "The dp height upstream gives every card sample (Modifier.size).")

(defconst jetpacs-m3-card--content-pad 16
  "The dp a rendered card pads its content by (LayoutNodes.kt RenderCard).")

(defun jetpacs-m3-card--sized (text &rest opts)
  "A 180x100 card centering TEXT, built with OPTS passed to `jetpacs-card'.
Upstream sizes the card itself and centers the label with a
Box(Modifier.fillMaxSize).  The wire has no fill-height attribute, so
the box is given the content area the card's own padding leaves."
  (jetpacs-with-attrs
   (apply #'jetpacs-card
          (jetpacs-with-attrs
           (jetpacs-box (jetpacs-text text) :alignment "center")
           :fill_fraction 1.0
           :height (- jetpacs-m3-card--height
                      (* 2 jetpacs-m3-card--content-pad)))
          opts)
   :width jetpacs-m3-card--width
   :height jetpacs-m3-card--height))

(defun jetpacs-m3-card--filled ()
  "Upstream CardSample: a filled 180x100 Card reading \"Card content\"."
  (jetpacs-m3-card--sized "Card content" :variant "filled"))

(defun jetpacs-m3-card--clickable-filled ()
  "Upstream ClickableCardSample: the same filled Card, reading \"Clickable\".
Its onClick is an empty lambda upstream; here the tap reports itself."
  (jetpacs-m3-card--sized "Clickable"
                          :variant "filled"
                          :on-tap (jetpacs-m3-demo "Clickable")))

(defun jetpacs-m3-card--elevated ()
  "Upstream ElevatedCardSample: an elevated 180x100 card, \"Card content\"."
  (jetpacs-m3-card--sized "Card content" :variant "elevated"))

(defun jetpacs-m3-card--clickable-elevated ()
  "Upstream ClickableElevatedCardSample: the same card, reading \"Clickable\".
Its onClick is an empty lambda upstream; here the tap reports itself."
  (jetpacs-m3-card--sized "Clickable"
                          :variant "elevated"
                          :on-tap (jetpacs-m3-demo "Clickable")))

(defun jetpacs-m3-card--outlined ()
  "Upstream OutlinedCardSample: an outlined 180x100 card, \"Card content\"."
  (jetpacs-m3-card--sized "Card content" :variant "outlined"))

(defun jetpacs-m3-card--clickable-outlined ()
  "Upstream ClickableOutlinedCardSample: the same outlined card, \"Clickable\".
Its onClick is an empty lambda upstream; here the tap reports itself."
  (jetpacs-m3-card--sized "Clickable"
                          :variant "outlined"
                          :on-tap (jetpacs-m3-demo "Clickable")))

(jetpacs-m3-defcomponent "card"
  :builders (list #'jetpacs-card)
  :name "Card"
  :description
  "Cards contain content and actions that relate information about a subject."
  :guidelines "https://m3.material.io/styles/cards"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#card"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Card.kt"
  :examples
  (list
   (jetpacs-m3-example
    "CardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :build #'jetpacs-m3-card--filled)
   (jetpacs-m3-example
    "ClickableCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :build #'jetpacs-m3-card--clickable-filled)
   (jetpacs-m3-example
    "ElevatedCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :build #'jetpacs-m3-card--elevated)
   (jetpacs-m3-example
    "ClickableElevatedCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :build #'jetpacs-m3-card--clickable-elevated)
   (jetpacs-m3-example
    "OutlinedCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :build #'jetpacs-m3-card--outlined)
   (jetpacs-m3-example
    "ClickableOutlinedCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :build #'jetpacs-m3-card--clickable-outlined)
   ))

(provide 'jetpacs-m3-card)
;;; jetpacs-m3-card.el ends here
