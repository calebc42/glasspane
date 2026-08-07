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
;; The recreation rides `surface.shape', whose enum carries the whole
;; MaterialShapes vocabulary by wire name (arch, ghostish, heart, ...);
;; the Companion resolves each name to the real RoundedPolygon via
;; MaterialShapes.<Name>.toShape(), so the corner rounding is androidx's
;; own, not a polyline lookalike.  One seam: upstream clips a Spacer and
;; paints primary through the clip, while here the shape belongs to a
;; surface node -- same pixels, different owner.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-material-shapes--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/MaterialShapesSamples.kt"
  "Upstream MaterialShapesExample sourceUrl.")

(defconst jetpacs-m3-material-shapes--names
  '(("circle" . "Circle") ("square" . "Square") ("slanted" . "Slanted")
    ("arch" . "Arch") ("fan" . "Fan") ("arrow" . "Arrow")
    ("semi_circle" . "SemiCircle") ("oval" . "Oval") ("pill" . "Pill")
    ("triangle" . "Triangle") ("diamond" . "Diamond")
    ("clam_shell" . "ClamShell") ("pentagon" . "Pentagon") ("gem" . "Gem")
    ("sunny" . "Sunny") ("very_sunny" . "VerySunny")
    ("cookie_4_sided" . "Cookie4Sided") ("cookie_6_sided" . "Cookie6Sided")
    ("cookie_7_sided" . "Cookie7Sided") ("cookie_9_sided" . "Cookie9Sided")
    ("cookie_12_sided" . "Cookie12Sided") ("ghostish" . "Ghostish")
    ("clover_4_leaf" . "Clover4Leaf") ("clover_8_leaf" . "Clover8Leaf")
    ("burst" . "Burst") ("soft_burst" . "SoftBurst") ("boom" . "Boom")
    ("soft_boom" . "SoftBoom") ("flower" . "Flower") ("puffy" . "Puffy")
    ("puffy_diamond" . "PuffyDiamond") ("pixel_circle" . "PixelCircle")
    ("pixel_triangle" . "PixelTriangle") ("bun" . "Bun")
    ("heart" . "Heart"))
  "The 35 named MaterialShapes: (wire-name . upstream label), grid order.")

(defun jetpacs-m3-material-shapes--cell (pair)
  "One grid cell for PAIR: the upstream label above a 56dp shaped swatch."
  (jetpacs-column
   (jetpacs-text (cdr pair) :style "body")
   (jetpacs-surface
    (jetpacs-with-attrs (jetpacs-spacer) :width 56 :height 56)
    :shape (car pair) :color "primary")
   :align "center" :spacing 8))

(defun jetpacs-m3-material-shapes--all-shapes ()
  "Upstream ShapesSample, the `AllShapes' grid: the whole shape set.
A four-column `lazy_grid' over the 35 named MaterialShapes, each cell a
label above a 56dp swatch.  The swatch is a `surface' whose `shape'
names the shape by wire name, which the Companion resolves through
MaterialShapes.<Name>.toShape() -- so every corner is androidx polygon
rounding, not a lookalike.  Upstream clips a Spacer and paints primary
through the clip; same pixels, different owner."
  (apply #'jetpacs-lazy-grid
         (append
          (mapcar #'jetpacs-m3-material-shapes--cell
                  jetpacs-m3-material-shapes--names)
          (list :columns 4 :spacing 4))))

(jetpacs-m3-defcomponent "material-shapes"
  :builders (list #'jetpacs-surface #'jetpacs-lazy-grid)
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
    :build #'jetpacs-m3-material-shapes--all-shapes)
   ))

(provide 'jetpacs-m3-material-shapes)
;;; jetpacs-m3-material-shapes.el ends here
