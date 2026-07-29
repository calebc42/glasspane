;;; jetpacs-m3-material-shapes.el --- Catalog component: Material Shapes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `MaterialShapes' + Examples.kt
;; `MaterialShapesExamples' (1 example), samples/MaterialShapesSamples.kt.
;;
;; The single sample, `AllShapes', is a four-column LazyVerticalGrid over
;; the 35 named MaterialShapes -- Circle, Square, Slanted, Arch, Fan,
;; Arrow, ... PixelTriangle, Bun, Heart -- each a label above a 56dp
;; Spacer clipped to `polygon.toShape()' and backed with the primary
;; color.  Its entire subject is that shape set.
;;
;; Nothing on the wire can name one of those shapes.  `surface' carries a
;; three-value shape enum (rounded/rounded_small/circle), and the
;; universal `:corner' attribute only sets four radii on a rectangle;
;; MaterialShapes.Arch or MaterialShapes.Ghostish has no spelling in
;; either.  The `canvas' node's `path' op does draw closed polylines, but
;; its vertices would be invented in this file rather than read from
;; androidx.graphics.shapes, and a polyline carries none of the corner
;; rounding that makes a RoundedPolygon a Material shape -- that is a
;; lookalike, not this sample.  So the one example is unsupported, and
;; says which member is missing.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-material-shapes--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/MaterialShapesSamples.kt"
  "Upstream MaterialShapesExample sourceUrl.")

(jetpacs-m3-defcomponent "material-shapes"
  :name "Material Shapes"
  :description
  "Material Shapes are used to define the shape of components."
  :guidelines "https://m3.material.io/components/material-shapes"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#shapes"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Shapes.kt"
  :additional-info "Unofficial"
  :examples
  (list
   (jetpacs-m3-example
    "ShapesSample"
    "Material shapes examples"
    :source jetpacs-m3-material-shapes--source
    :expressive t
    :unsupported
    "No wire member can name a MaterialShapes polygon: the surface node's shape enum is rounded/rounded_small/circle and the universal corner attribute only sets four radii, so the 35 named RoundedPolygon clips this sample exists to show (Arch, Fan, Ghostish, Puffy, Heart, ...) cannot be asked for from Emacs.")
   ))

(provide 'jetpacs-m3-material-shapes)
;;; jetpacs-m3-material-shapes.el ends here
