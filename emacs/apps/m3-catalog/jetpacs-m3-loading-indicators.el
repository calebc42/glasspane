;;; jetpacs-m3-loading-indicators.el --- Catalog component: Loading indicators -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `LoadingIndicators' + Examples.kt
;; `LoadingIndicatorsExamples' (5 examples),
;; samples/LoadingIndicatorSamples.kt.
;;
;; All five samples are the M3 Expressive `LoadingIndicator' -- a new
;; component, not a new option on an old one.  Its whole identity is a
;; rotating sequence of morphing MaterialShapes polygons; the contained
;; flavour seats that morph on a shaped container, and the determinate
;; flavour advances the morph with progress instead of with time.
;;
;; The `progress' node now names it directly: variant `loading' IS
;; `LoadingIndicator' and variant `contained_loading' IS
;; `ContainedLoadingIndicator', and the node's existing `value' member
;; decides determinate vs indeterminate for those two exactly as it does
;; for the circular and linear tracks.  So the four Column samples
;; recreate exactly -- bare and contained, indeterminate and
;; determinate.
;;
;; The pull-to-refresh sample rides the scaffold now: `on_refresh' says
;; WHAT to run and `refresh_indicator "loading"' says which indicator
;; the Companion draws while it runs --
;; PullToRefreshDefaults.LoadingIndicator, the canned form of exactly
;; the composable this sample hand-places.  The per-frame pull scaling
;; stays the Companion's own, as it is in the canned indicator itself;
;; no distanceFraction ever crosses the wire.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-loading-indicators--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
  "Upstream LoadingIndicatorsExampleSourceUrl.")

(defun jetpacs-m3-loading-indicators--determinate (variant id)
  "A determinate VARIANT loading indicator over a slider identified by ID.
Both determinate samples upstream are the same Column: the indicator
driven by animatedProgress, a 30dp spacer, the text \"Set loading
progress:\", and a 300dp-wide Slider over 0f..1f writing the float
back.  The initial 0f rides the value member -- a value member present
at all is what determinate means on the wire -- and the writeback only
mutates local state upstream, so here the slider reports through the
demo verb."
  (jetpacs-column
   (jetpacs-progress :variant variant :value 0.0)
   (jetpacs-with-attrs (jetpacs-spacer) :height 30)
   (jetpacs-text "Set loading progress:")
   (jetpacs-with-attrs
    (jetpacs-slider id (jetpacs-m3-demo "Set loading progress:") :value 0.0)
    :width 300)
   :align "center"))

(defun jetpacs-m3-loading-indicators--loading ()
  "Upstream LoadingIndicatorSample.
A bare LoadingIndicator() centered in a Column: the progress node with
variant loading and NO value member, which is how the node spells
indeterminate."
  (jetpacs-column
   (jetpacs-progress :variant "loading")
   :align "center"))

(defun jetpacs-m3-loading-indicators--contained ()
  "Upstream ContainedLoadingIndicatorSample.
The same centered Column with variant contained_loading, which is the
indicator seated on its shaped, filled container."
  (jetpacs-column
   (jetpacs-progress :variant "contained_loading")
   :align "center"))

(defun jetpacs-m3-loading-indicators--determinate-loading ()
  "Upstream DeterminateLoadingIndicatorSample.
LoadingIndicator(progress = {animatedProgress}) is the progress node
with variant loading and a value."
  (jetpacs-m3-loading-indicators--determinate
   "loading" "loading-indicators-determinate"))

(defun jetpacs-m3-loading-indicators--determinate-contained ()
  "Upstream DeterminateContainedLoadingIndicatorSample.
The same Column as the determinate sample, with the contained variant."
  (jetpacs-m3-loading-indicators--determinate
   "contained_loading" "loading-indicators-determinate-contained"))

(defun jetpacs-m3-loading-indicators--pull-to-refresh ()
  "Upstream LoadingIndicatorPullToRefreshSample: the list under the pull.
Only the scrollable body is authored here.  The gesture is the scaffold
`on_refresh' slot and the thing drawn while it runs is
`refresh_indicator \"loading\"' -- PullToRefreshDefaults.LoadingIndicator,
the canned form of the composable upstream hand-places over the list.
Upstream grows the list by five per refresh; here the fifteen keyed
items stand still, because no distanceFraction and no item count ever
cross the wire."
  (apply #'jetpacs-lazy-column
         (append
          (mapcar (lambda (n)
                    (jetpacs-with-attrs
                     (jetpacs-text (format "Item %d" n))
                     :key (format "loading-ptr-item-%d" n)))
                  (number-sequence 1 15))
          (list :spacing 8 :content-padding 8))))

(jetpacs-m3-defcomponent "loading-indicators"
  :builders (list #'jetpacs-progress)
  :name "Loading indicators"
  :description
  "Loading indicators express an unspecified wait time or display the length of a loading process."
  :guidelines "https://m3.material.io/components/loading-indicators"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#loadingindicator"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/LoadingIndicator.kt"
  :examples
  (list
   (jetpacs-m3-example
    "LoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :build #'jetpacs-m3-loading-indicators--loading)
   (jetpacs-m3-example
    "ContainedLoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :build #'jetpacs-m3-loading-indicators--contained)
   (jetpacs-m3-example
    "DeterminateLoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :build #'jetpacs-m3-loading-indicators--determinate-loading)
   (jetpacs-m3-example
    "DeterminateContainedLoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :build #'jetpacs-m3-loading-indicators--determinate-contained)
   (jetpacs-m3-example
    "LoadingIndicatorPullToRefreshSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :slots (list :on-refresh (jetpacs-m3-demo "Refreshed"))
    ;; PullToRefreshDefaults.LoadingIndicator in the indicator slot.
    :scaffold (list :refresh-indicator "loading")
    :build #'jetpacs-m3-loading-indicators--pull-to-refresh)
   ))

(provide 'jetpacs-m3-loading-indicators)
;;; jetpacs-m3-loading-indicators.el ends here
