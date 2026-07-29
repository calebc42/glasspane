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
;; The nearest thing on the wire is the `progress' node, whose variant
;; enum is circular or linear -- and those two ARE
;; CircularProgressIndicator and LinearProgressIndicator, the separate
;; upstream component the sibling "Progress indicators" module already
;; recreates.  Drawing one of those here would put the OLD indicator on
;; screen under the NEW one's name, which is the lookalike the fidelity
;; rule forbids, so each example names the node the wire is missing.
;;
;; The pull-to-refresh sample is the same story told in the scaffold.
;; EBP does carry pull-to-refresh -- `scaffold.on_refresh' -- but that
;; member is a bare descriptor: the Companion owns whatever indicator
;; it draws, and this sample exists to put the LoadingIndicator THERE,
;; hand-scaled by the pull distance.  Its setting is expressible; its
;; subject is not.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-loading-indicators--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
  "Upstream LoadingIndicatorsExampleSourceUrl.")

(defconst jetpacs-m3-loading-indicators--indicator-note
  "There is no loading_indicator node: the progress node's variant enum is circular or linear, and those name CircularProgressIndicator and LinearProgressIndicator, not the rotating sequence of morphing MaterialShapes polygons an M3 Expressive LoadingIndicator is."
  "Why every plain LoadingIndicator sample is unsupported.")

(defconst jetpacs-m3-loading-indicators--contained-note
  "Neither half is on the wire: there is no loading_indicator node for the morphing MaterialShapes indicator, and no container member that would seat it on the shaped, filled background a ContainedLoadingIndicator adds."
  "Why every ContainedLoadingIndicator sample is unsupported.")

(jetpacs-m3-defcomponent "loading-indicators"
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
    :unsupported jetpacs-m3-loading-indicators--indicator-note)
   (jetpacs-m3-example
    "ContainedLoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-loading-indicators--contained-note)
   (jetpacs-m3-example
    "DeterminateLoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :unsupported
    "There is no loading_indicator node, so the progress node's value member cannot drive the one thing this sample shows: a determinate LoadingIndicator stepping through its MaterialShapes morph sequence rather than filling a circular or linear track.")
   (jetpacs-m3-example
    "DeterminateContainedLoadingIndicatorSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :unsupported
    "There is no loading_indicator node and no container member: neither the progress-driven MaterialShapes morph nor the shaped background it sits on can be asked for through the progress node's variant and value.")
   (jetpacs-m3-example
    "LoadingIndicatorPullToRefreshSample"
    "Loading indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/LoadingIndicatorSamples.kt"
    :expressive t
    :unsupported
    "The scaffold's on_refresh member is a bare action descriptor: it cannot name PullToRefreshDefaults.LoadingIndicator as the indicator the Companion draws, and it reports no distanceFraction for the scale this sample animates, so the loading indicator the sample is about never reaches the wire.")
   ))

(provide 'jetpacs-m3-loading-indicators)
;;; jetpacs-m3-loading-indicators.el ends here
