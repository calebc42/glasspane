;;; jetpacs-m3-carousel.el --- Catalog component: Carousel -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Carousel' + Examples.kt
;; `CarouselExamples' (6 examples), samples/CarouselSamples.kt.
;;
;; Carousel is one of the M3 components Jetpacs does not wrap --
;; docs/lookup-tables/M3-COMPONENT-LOOKUP.org lists it Available, not
;; Wrapped, and sketches a future `carousel' wire type with `items'
;; children.  There is no such node today, and there is no `lazy_row'
;; either: the one horizontally scrolling container on the wire is
;; `row' with `scroll'.
;;
;; That is fatal for all six samples, because every one of them exists
;; to demonstrate a carousel STRATEGY -- multi-browse, uncontained,
;; centered-hero, multi-aspect -- which is precisely the keyline
;; masking a plain scrolling row does not do.  All six draw the SAME
;; five pictures at 205dp; what differs between them, and what each is
;; named for, is how wide each item is measured and how its mask
;; resizes as it crosses a keyline.  A `row' of five `image' nodes
;; would render five pictures of one fixed size and no mask -- the
;; lookalike the README warns against, not the component.
;;
;; Two of the six add a second, independent gap: the `image' node has
;; no mask member for `maskClip'/`maskBorder', and nothing on the wire
;; reports `carouselItemDrawInfo' (the per-item mask rectangle a scroll
;; frame produces), which is what their custom item content is drawn
;; against.
;;
;; The pictures are a third gap, smaller and shared: upstream paints
;; R.drawable.carousel_image_1..5, app resources, and `jetpacs-image'
;; accepts only an https URL or a data:image URI.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-carousel--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/CarouselSamples.kt"
  "Upstream CarouselExampleSourceUrl.")

(defconst jetpacs-m3-carousel--node-note
  "There is no carousel node type: the EBP layout vocabulary is row, column, flow_row, box, lazy_column and the rest, and none of them snaps a child to a keyline or resizes an item's mask as it scrolls."
  "The wire fact every Carousel sample runs into.
Each example appends the strategy it exists to demonstrate.")

(defconst jetpacs-m3-carousel--mask-note
  "  The image node also has no mask member, so maskClip and maskBorder cannot be requested from Emacs."
  "The second gap, for the two samples that mask their own item content.")

(jetpacs-m3-defcomponent "carousel"
  :name "Carousel"
  :description
  "Carousels are stylized versions of lists that provide a unique viewing and behavior that suit large imagery and other visually rich content."
  :guidelines "https://m3.material.io/styles/carousel"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#carousel"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Carousel.kt"
  :examples
  (list
   (jetpacs-m3-example
    "HorizontalMultiBrowseCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :unsupported
    (concat jetpacs-m3-carousel--node-note
            "  This sample IS the multi-browse strategy: a preferred 186dp item measured large, then medium, then small toward each edge, remeasured on every scroll frame."))
   (jetpacs-m3-example
    "HorizontalUncontainedCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :unsupported
    (concat jetpacs-m3-carousel--node-note
            "  This sample IS the uncontained strategy: items held at exactly 186dp that scroll past the edge unmasked, and a scrolling row has no item width and no snap position."))
   (jetpacs-m3-example
    "HorizontalCenteredHeroCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :unsupported
    (concat jetpacs-m3-carousel--node-note
            "  This sample IS the centered-hero strategy: one large item held in the center with a small one peeking at each edge, which no row arrangement can express."))
   (jetpacs-m3-example
    "FadingHorizontalMultiBrowseCarouselSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :unsupported
    (concat jetpacs-m3-carousel--node-note
            jetpacs-m3-carousel--mask-note
            "  The fade this sample is named for reads carouselItemDrawInfo.size and maskRect per scroll frame to alpha and translate a chip, and no node member reports that."))
   (jetpacs-m3-example
    "CarouselWithShowAllButtonSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :unsupported
    (concat jetpacs-m3-carousel--node-note
            "  This sample pairs a multi-browse carousel with a \"Show all\" overflow into a two-column grid, and with no carousel node there is nothing for the button to overflow from."))
   (jetpacs-m3-example
    "MultiAspectCarouselLazyRowSample"
    "Carousel examples"
    :source jetpacs-m3-carousel--source
    :unsupported
    (concat jetpacs-m3-carousel--node-note
            jetpacs-m3-carousel--mask-note
            "  This sample is MultiAspectCarouselScope over a lazy row of items 305, 205, 275, 350 and 100dp wide, each masked through its own MultiAspectCarouselItemDrawInfo."))
   ))

(provide 'jetpacs-m3-carousel)
;;; jetpacs-m3-carousel.el ends here
