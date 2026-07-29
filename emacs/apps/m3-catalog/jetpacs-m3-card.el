;;; jetpacs-m3-card.el --- Catalog component: Card -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Card' + Examples.kt
;; `CardExamples' (6 examples).
;;
;; The six samples are one matrix: three M3 container styles (Card,
;; ElevatedCard, OutlinedCard) crossed with the plain and the onClick
;; overload.  The `card' node carries children, on_tap, on_long_tap and
;; the two swipe sides -- and no variant, colors, elevation or border
;; member.  The Companion renders EVERY card node as an M3 `ElevatedCard'
;; (WIDGET-REFERENCE `card' -> ElevatedCard, LayoutNodes.kt RenderCard),
;; so the wire has exactly ONE of the three styles, and it is the
;; elevated one.
;;
;; That makes the elevated column of the matrix exact -- with and
;; without the click, because on_tap is on the wire -- and leaves the
;; filled and outlined columns with nothing to select them.  Drawing
;; them anyway (a `surface' node with a hand-picked color, or a
;; universal `border' stroked over an always-elevated card) would put a
;; lookalike where the sample's whole subject is the container style, so
;; those four say what is missing instead.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-card--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/CardSamples.kt"
  "Upstream CardExampleSourceUrl.")

(defconst jetpacs-m3-card--filled-note
  "The card node has no variant, colors or elevation member, and the Companion renders every card as an M3 ElevatedCard: the filled Card container this sample exists to contrast with the elevated one cannot be asked for from Emacs."
  "Why the two plain-Card samples are unsupported.")

(defconst jetpacs-m3-card--outlined-note
  "The card node has no variant, colors or border member: OutlinedCard is a flat container with a 1dp outline stroke, and the wire can neither drop the card's elevation nor ask for that outline."
  "Why the two OutlinedCard samples are unsupported.")

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

(defun jetpacs-m3-card--elevated ()
  "Upstream ElevatedCardSample: a 180x100 card reading \"Card content\".
The card node IS an ElevatedCard on the Companion, so this one lands
exactly as upstream draws it."
  (jetpacs-m3-card--sized "Card content"))

(defun jetpacs-m3-card--clickable-elevated ()
  "Upstream ClickableElevatedCardSample: the same card, reading \"Clickable\".
Its onClick is an empty lambda upstream; here the tap reports itself."
  (jetpacs-m3-card--sized "Clickable"
                          :on-tap (jetpacs-m3-demo "Clickable")))

(jetpacs-m3-defcomponent "card"
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
    :unsupported jetpacs-m3-card--filled-note)
   (jetpacs-m3-example
    "ClickableCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :unsupported
    "Only half of this one is on the wire: the card node carries on_tap, but not the filled Card container style that separates it from ClickableElevatedCardSample.")
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
    :unsupported jetpacs-m3-card--outlined-note)
   (jetpacs-m3-example
    "ClickableOutlinedCardSample"
    "Cards examples"
    :source jetpacs-m3-card--source
    :unsupported
    "Only half of this one is on the wire: the card node carries on_tap, but has no border or colors member for OutlinedCard's flat outlined container.")
   ))

(provide 'jetpacs-m3-card)
;;; jetpacs-m3-card.el ends here
