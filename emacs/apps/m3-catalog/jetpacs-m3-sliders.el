;;; jetpacs-m3-sliders.el --- Catalog component: Sliders -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Sliders' + Examples.kt
;; `SlidersExamples' (11 examples), samples/SliderSamples.kt.
;;
;; The `slider' node carries id, on_change, value, min, max, values and
;; enabled -- and nothing else.  That is the whole horizontal M3
;; `Slider' with a scalar position, so the two samples whose subject is
;; the RANGE (the default 0f..1f one, and steps = 9 over 0f..100f, which
;; is precisely the discrete `values' list) recreate exactly.
;;
;; The other nine exist to demonstrate something the node has no member
;; for: a THUMB or a TRACK composable (SliderDefaults.Thumb, .Track,
;; .CenteredTrack, .colors, icons drawn into the track by a DrawScope),
;; an ORIENTATION (VerticalSlider), or a SECOND THUMB (RangeSlider, whose
;; state is an activeRangeStart/activeRangeEnd pair and not one number).
;;
;; One detail of the two recreations does not survive: upstream prints
;; "%.2f".format(value) above the track and recomposes it on every drag.
;; The wire slider dispatches on_change once on gesture commit, and a
;; catalog sample may only reach `jetpacs-m3-demo', so the readout is
;; authored at the starting value and the drag reports as a snackbar.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-sliders--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
  "Upstream SlidersExampleSourceUrl.")

(defconst jetpacs-m3-sliders--thumb-note
  "The slider node has no thumb member: id, on_change, value, min, max, values and enabled are the whole node, so the Label-and-Icon thumb this sample hands to the thumb slot is Companion-side drawing the wire cannot ask for."
  "Why the custom-thumb sample is unsupported.")

(defconst jetpacs-m3-sliders--track-note
  "The slider node has no thumb, track or colors member: id, on_change, value, min, max, values and enabled are the whole node, so a SliderDefaults.Thumb or .Track slot and its color overrides are Companion-side drawing the wire cannot ask for."
  "Why every custom-track sample is unsupported.")

(defconst jetpacs-m3-sliders--range-note
  "There is no range slider node, and the slider value member is a single scalar: the two thumbs of RangeSlider, activeRangeStart and activeRangeEnd, cannot be put on the wire as one node."
  "Why every RangeSlider sample is unsupported.")

(defun jetpacs-m3-sliders--basic ()
  "Upstream SliderSample: a Slider over the default 0f..1f range.
Omitting min and max is that default exactly.  The Text above the track
is the sample printing \"%.2f\".format(sliderPosition) at its remembered
starting value of 0f."
  (jetpacs-column
   (jetpacs-text "0.00")
   (jetpacs-slider "sliders-basic" (jetpacs-m3-demo "Slider")
                   :value 0)
   :spacing 8 :fill t))

(defun jetpacs-m3-sliders--steps ()
  "Upstream StepsSliderSample: steps = 9 over the 0f..100f range.
Nine steps excluding the endpoints is the eleven multiples of ten, and
that list IS the discrete slider: the Companion draws the Slider with
steps = length - 2 and returns the exact authored number, never step
arithmetic of its own."
  (jetpacs-column
   (jetpacs-text "0.00")
   (jetpacs-slider "sliders-steps" (jetpacs-m3-demo "Steps slider")
                   :value 0
                   :values (list 0 10 20 30 40 50 60 70 80 90 100))
   :spacing 8 :fill t))

(jetpacs-m3-defcomponent "sliders"
  :name "Sliders"
  :description
  "Sliders allow users to make selections from a range of values."
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Slider.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :build #'jetpacs-m3-sliders--basic)
   (jetpacs-m3-example
    "StepsSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :build #'jetpacs-m3-sliders--steps)
   (jetpacs-m3-example
    "SliderWithCustomThumbSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :unsupported jetpacs-m3-sliders--thumb-note)
   (jetpacs-m3-example
    "SliderWithCustomTrackAndThumbSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :unsupported jetpacs-m3-sliders--track-note)
   (jetpacs-m3-example
    "SliderWithTrackIconsSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "The slider node has no track member: the MusicNote and MusicOff icons this sample paints into the active and inactive track come from a DrawScope hung on the track composable, and the wire has no way to hand the Companion a drawing.")
   (jetpacs-m3-example
    "CenteredSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "The slider node has no track member: SliderDefaults.CenteredTrack, an active track that grows out from the middle of the range instead of from the start, is the whole point of this sample and only min, max and value are on the wire.")
   (jetpacs-m3-example
    "VerticalSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "There is no vertical slider node and no orientation member: the slider node always renders the horizontal M3 Slider, so VerticalSlider with reverseDirection cannot be asked for from Emacs.")
   (jetpacs-m3-example
    "VerticalCenteredSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "Neither half is on the wire: there is no vertical slider node or orientation member for VerticalSlider, and no track member for SliderDefaults.CenteredTrack.")
   (jetpacs-m3-example
    "RangeSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :unsupported jetpacs-m3-sliders--range-note)
   (jetpacs-m3-example
    "StepRangeSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :unsupported
    "Only half of this one is on the wire: steps = 9 is the discrete slider values list, but there is no range slider node, and the slider value member is one scalar rather than an activeRangeStart and activeRangeEnd pair.")
   (jetpacs-m3-example
    "RangeSliderWithCustomComponents"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :unsupported
    "Nothing in this one is on the wire: there is no range slider node for the two thumbs, and the slider node has no thumb, track or colors member for the labelled blue and green thumbs or the red active track.")
   ))

(provide 'jetpacs-m3-sliders)
;;; jetpacs-m3-sliders.el ends here
