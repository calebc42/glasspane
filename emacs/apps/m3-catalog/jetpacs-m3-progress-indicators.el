;;; jetpacs-m3-progress-indicators.el --- Catalog component: Progress indicators -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `ProgressIndicators' + Examples.kt
;; `ProgressIndicatorsExamples' (8 examples),
;; samples/ProgressIndicatorSamples.kt.
;;
;; The `progress' node carries exactly two members: variant
;; (circular/linear) and value.  That is the whole of the classic M3
;; ProgressIndicator API the catalog shows here -- a value member is a
;; determinate indicator, an omitted one is indeterminate -- so the four
;; non-wavy samples recreate exactly, two determinate and two
;; indeterminate.
;;
;; The other four are the paired Expressive samples, and every one of
;; them exists to demonstrate the WAVY track (LinearWavyProgressIndicator
;; / CircularWavyProgressIndicator, with their amplitude, wavelength and
;; wave speed).  `variant' is a two-value enum with no wavy member, so
;; the wire cannot ask for the one thing those samples are about.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-progress-indicators--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
  "Upstream ProgressIndicatorsExampleSourceUrl.")

(defconst jetpacs-m3-progress-indicators--wavy-note
  "The progress node's variant enum is circular or linear only: there is no wavy member, so the undulating track a WavyProgressIndicator exists to demonstrate -- its amplitude, wavelength and wave speed -- cannot be asked for from Emacs."
  "Why every Wavy sample is unsupported.")

(defun jetpacs-m3-progress-indicators--determinate (variant id)
  "A determinate VARIANT indicator over a slider identified by ID.
Every determinate sample upstream is the same Column: the indicator
driven by animatedProgress, a 30dp spacer, the text \"Set progress:\",
and a 300dp-wide Slider over 0f..1f writing the float back.  The
initial 0.1f rides the value member; the writeback only mutates local
state upstream, so here the slider reports through the demo verb."
  (jetpacs-column
   (jetpacs-progress :variant variant :value 0.1)
   (jetpacs-with-attrs (jetpacs-spacer) :height 30)
   (jetpacs-text "Set progress:")
   (jetpacs-with-attrs
    (jetpacs-slider id (jetpacs-m3-demo "Set progress:") :value 0.1)
    :width 300)
   :align "center"))

(defun jetpacs-m3-progress-indicators--linear ()
  "Upstream LinearProgressIndicatorSample.
LinearProgressIndicator(progress = {animatedProgress}) is the progress
node with variant linear and a value, which is what determinate means
on the wire."
  (jetpacs-m3-progress-indicators--determinate
   "linear" "progress-indicators-linear"))

(defun jetpacs-m3-progress-indicators--indeterminate-linear ()
  "Upstream IndeterminateLinearProgressIndicatorSample.
A bare LinearProgressIndicator() centered in a Column: on the wire that
is the progress node with variant linear and NO value member, which is
how the node spells indeterminate."
  (jetpacs-column
   (jetpacs-progress :variant "linear")
   :align "center"))

(defun jetpacs-m3-progress-indicators--circular ()
  "Upstream CircularProgressIndicatorSample.
The same Column as the linear sample, with the circular variant."
  (jetpacs-m3-progress-indicators--determinate
   "circular" "progress-indicators-circular"))

(defun jetpacs-m3-progress-indicators--indeterminate-circular ()
  "Upstream IndeterminateCircularProgressIndicatorSample.
A bare CircularProgressIndicator() centered in a Column: the progress
node with variant circular and no value."
  (jetpacs-column
   (jetpacs-progress :variant "circular")
   :align "center"))

(jetpacs-m3-defcomponent "progress-indicators"
  :name "Progress indicators"
  :description
  "Progress indicators express an unspecified wait time or display the length of a process."
  :guidelines "https://m3.material.io/components/progress-indicators"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#circularprogressindicator"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ProgressIndicator.kt"
  :examples
  (list
   (jetpacs-m3-example
    "LinearProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :build #'jetpacs-m3-progress-indicators--linear)
   (jetpacs-m3-example
    "LinearWavyProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-progress-indicators--wavy-note)
   (jetpacs-m3-example
    "IndeterminateLinearProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :build #'jetpacs-m3-progress-indicators--indeterminate-linear)
   (jetpacs-m3-example
    "IndeterminateLinearWavyProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-progress-indicators--wavy-note)
   (jetpacs-m3-example
    "CircularProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :build #'jetpacs-m3-progress-indicators--circular)
   (jetpacs-m3-example
    "CircularWavyProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-progress-indicators--wavy-note)
   (jetpacs-m3-example
    "IndeterminateCircularProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :build #'jetpacs-m3-progress-indicators--indeterminate-circular)
   (jetpacs-m3-example
    "IndeterminateCircularWavyProgressIndicatorSample"
    "Progress indicators examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ProgressIndicatorSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-progress-indicators--wavy-note)
   ))

(provide 'jetpacs-m3-progress-indicators)
;;; jetpacs-m3-progress-indicators.el ends here
