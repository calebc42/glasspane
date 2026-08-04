;;; jetpacs-m3-carousel.el --- Catalog component: Carousel -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Carousel' + Examples.kt
;; `CarouselExamples' (6 examples), samples/CarouselSamples.kt.
;;
;; Four of the six recreate on the `carousel' node -- the 49th type,
;; which exists because of this module.  The node is the M3 keyline
;; carousel whole: `:strategy' picks multi_browse, uncontained or
;; centered_hero, `:item-width' is the multi_browse preferredItemWidth
;; or the uncontained itemWidth, and `:item-corner' is the maskClip
;; radius applied to the item's LIVE mask rect, so the clip breathes
;; with the keylines.  Every keyline decision is the Companion's;
;; Emacs supplies content and never learns the width.
;;
;; One stand-in stated: upstream's items are five bundled drawables
;; (carousel_image_1..5), and no drawable crosses the wire -- each item
;; here is a tonal box carrying its number, which keeps the keylines,
;; the mask and the parallax visible without pretending to be a photo.
;; The upstream tap (animateScrollToItem to focus the tapped item) is
;; Companion-side animation with no member; the boxes are inert.
;;
;; The two that remain each need something beyond the node:
;; FadingHorizontalMultiBrowseCarouselSample drives per-item ALPHA from
;; the live mask coverage (graphicsLayer { alpha = lerp(...) } inside
;; the item lambda) -- declarable intent Emacs could never compute,
;; since no message reports per-frame geometry; and
;; MultiAspectCarouselLazyRowSample is the LazyRow-based multi-aspect
;; form, a different composable whose per-item aspect strategy the node
;; does not carry.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-carousel--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/CarouselSamples.kt"
  "Upstream CarouselExampleSourceUrl.")

(defconst jetpacs-m3-carousel--tones
  '("primary_container" "secondary_container" "tertiary_container"
    "surface_variant" "primary_container")
  "One tonal container per item — the stand-in for the five drawables.")

(defun jetpacs-m3-carousel--items ()
  "The five items every sample shares, as tonal boxes with a number.
Upstream's five carousel_image drawables are not on the wire; a box at
the sample's 205dp item height keeps the keylines and mask visible."
  (cl-loop for tone in jetpacs-m3-carousel--tones
           for i from 1
           collect (jetpacs-with-attrs
                    (jetpacs-box
                     (jetpacs-text (format "Item %d" i) :style "title")
                     :alignment "center")
                    :bg tone :height 205 :fill_fraction 1.0)))

(defun jetpacs-m3-carousel--multi-browse ()
  "Upstream HorizontalMultiBrowseCarouselSample.
preferredItemWidth 186, itemSpacing 8, contentPadding 16 horizontal,
items mask-clipped extraLarge (28dp) -- each a member, verbatim."
  (jetpacs-with-attrs
   (apply #'jetpacs-carousel
          (append (jetpacs-m3-carousel--items)
                  (list :item-width 186 :item-spacing 8
                        :content-padding 16 :item-corner 28)))
   :height 221))

(defun jetpacs-m3-carousel--uncontained ()
  "Upstream HorizontalUncontainedCarouselSample: fixed 186dp items."
  (jetpacs-with-attrs
   (apply #'jetpacs-carousel
          (append (jetpacs-m3-carousel--items)
                  (list :strategy "uncontained"
                        :item-width 186 :item-spacing 8
                        :content-padding 16 :item-corner 28)))
   :height 221))

(defun jetpacs-m3-carousel--centered-hero ()
  "Upstream HorizontalCenteredHeroCarouselSample: the self-sizing hero."
  (jetpacs-with-attrs
   (apply #'jetpacs-carousel
          (append (jetpacs-m3-carousel--items)
                  (list :strategy "centered_hero"
                        :item-spacing 8 :content-padding 16
                        :item-corner 28)))
   :height 221))

(defun jetpacs-m3-carousel--show-all ()
  "Upstream CarouselWithShowAllButtonSample: a header, then the carousel.
The \"Show all\" TextButton swaps the carousel for a two-column grid
upstream; that swap is screen navigation a real app drives from its own
verb, so here the button reports through the demo verb -- the carousel
under a titled header is what the sample composes."
  (jetpacs-column
   (jetpacs-row
    (jetpacs-with-attrs
     (jetpacs-text "Recently played" :style "title")
     :weight 1)
    (jetpacs-button "Show all" (jetpacs-m3-demo "Show all")
                    :variant "text")
    :align "center" :fill t)
   (jetpacs-m3-carousel--multi-browse)
   :spacing 8 :fill t))

(defconst jetpacs-m3-carousel--multi-aspect-widths '(305 205 275 350 100)
  "MultiAspectCarouselLazyRowSample's five mainAxisSize values.")

(defun jetpacs-m3-carousel--multi-aspect ()
  "Upstream MultiAspectCarouselLazyRowSample: five widths, one height.
Upstream is a plain LazyRow, not a keyline carousel, so the recreation
is the composed row it actually is: scroll with :content-padding 16
(inside the viewport, scrolling under it, exactly LazyRow's
contentPadding), spacing 8, each item a 205dp-tall clipped tonal box at
its own width.  Stated seam: upstream's maskClip(extraLarge, drawInfo)
re-masks each item from its live draw geometry as it scrolls; the wire
clips statically at the same extraLarge corner."
  (jetpacs-with-attrs
   (apply #'jetpacs-row
          (append
           (cl-loop
            for w in jetpacs-m3-carousel--multi-aspect-widths
            for tone in jetpacs-m3-carousel--tones
            for i from 1
            collect (jetpacs-with-attrs
                     (jetpacs-box
                      (jetpacs-text (format "Item %d" i) :style "title")
                      :alignment "center")
                     :bg tone :width w :height 205 :corner 28 :clip t))
           (list :scroll t :content-padding 16 :spacing 8)))
   :height 221))

(jetpacs-m3-defcomponent "carousel"
  :name "Carousel"
  :description
  "Carousels contain a collection of items that move horizontally or vertically."
  :guidelines "https://m3.material.io/components/carousel"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/carousel/package-summary"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/carousel/Carousel.kt"
  :examples
  (list
   (jetpacs-m3-example
    "HorizontalMultiBrowseCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :expressive t
    :build #'jetpacs-m3-carousel--multi-browse)
   (jetpacs-m3-example
    "HorizontalUncontainedCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :expressive t
    :build #'jetpacs-m3-carousel--uncontained)
   (jetpacs-m3-example
    "HorizontalCenteredHeroCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :expressive t
    :build #'jetpacs-m3-carousel--centered-hero)
   (jetpacs-m3-example
    "FadingHorizontalMultiBrowseCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :expressive t
    :unsupported
    "The carousel node carries the keylines now, but this sample drives each item's ALPHA from its live mask coverage -- graphicsLayer { alpha = lerp(...) } inside the item lambda -- and that is per-frame geometry no wire member declares and no message reports, so Emacs could state the intent but never compute it.")
   (jetpacs-m3-example
    "CarouselWithShowAllButtonSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :expressive t
    :build #'jetpacs-m3-carousel--show-all)
   (jetpacs-m3-example
    "MultiAspectCarouselLazyRowSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :expressive t
    :build #'jetpacs-m3-carousel--multi-aspect)
   ))

(provide 'jetpacs-m3-carousel)
;;; jetpacs-m3-carousel.el ends here
