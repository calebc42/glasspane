;;; jetpacs-m3-sliders.el --- Catalog component: Sliders -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Sliders' + Examples.kt
;; `SlidersExamples' (11 examples), samples/SliderSamples.kt.
;;
;; The `slider' node carries id, on_change, value, min, max, values and
;; enabled -- and, since the presentation members landed, track, color
;; and thumb_icon as well.  Those three are exactly the three knobs
;; upstream reaches for: `color' is
;; SliderDefaults.colors(thumbColor = C, activeTrackColor = C), which is
;; the pair every recolouring sample here sets; `track' picks
;; SliderDefaults.CenteredTrack over SliderDefaults.Track; `thumb_icon'
;; names a vector for the thumb slot.
;;
;; So five of the eleven recreate: the two whose subject is the RANGE
;; (the default 0f..1f one, and steps = 9 over 0f..100f, which is
;; precisely the discrete `values' list), the two whose subject is a
;; recoloured or icon THUMB, and the centred track.
;;
;; The six that remain want something with no member at all: a DRAWING
;; hung on the track (the MusicNote/MusicOff DrawScope), an ORIENTATION
;; (VerticalSlider), or a SECOND THUMB (RangeSlider, whose state is an
;; activeRangeStart/activeRangeEnd pair and not one number).
;;
;; Two details of the recreations do not survive.  Upstream prints
;; "%.2f".format(value) above the track and recomposes it on every drag;
;; the wire slider dispatches on_change once on gesture commit, and a
;; catalog sample may only reach `jetpacs-m3-demo', so the readout is
;; authored at the starting value and the drag reports as a snackbar.
;; The same limit costs the Label/PlainTooltip that
;; SliderWithCustomThumbSample floats over its thumb while it is pressed:
;; thumb_icon is the icon, not a live bubble printing the position.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-sliders--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
  "Upstream SlidersExampleSourceUrl.")

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

(defun jetpacs-m3-sliders--custom-thumb ()
  "Upstream SliderWithCustomThumbSample: a Favorite icon in the thumb slot.
`:thumb-icon' is that slot: the Companion draws the named vector at
ButtonDefaults.IconSize instead of SliderDefaults.Thumb.  Upstream tints
the heart Color.Red, and the wire's one color member is
SliderDefaults.colors(thumbColor, activeTrackColor), so the active track
takes the red with it.  The sample's Column holds only the Slider -- its
value readout lives in the Label bubble, which is not on the wire."
  (jetpacs-column
   (jetpacs-slider "sliders-custom-thumb"
                   (jetpacs-m3-demo "Slider with custom thumb")
                   :value 0 :min 0 :max 100
                   :thumb-icon "favorite"
                   :color "#FF0000")
   :spacing 8 :fill t))

(defun jetpacs-m3-sliders--custom-track-and-thumb ()
  "Upstream SliderWithCustomTrackAndThumbSample: the defaults, recoloured.
Both slots this sample fills hold the stock composables --
SliderDefaults.Thumb and SliderDefaults.Track -- handed the one override
SliderDefaults.colors(thumbColor = Color.Red, activeTrackColor =
Color.Red).  That pair is exactly what the `:color' member sets, so the
node draws this sample rather than an approximation of it."
  (jetpacs-column
   (jetpacs-text "0.00")
   (jetpacs-slider "sliders-custom-track-and-thumb"
                   (jetpacs-m3-demo "Slider with custom track and thumb")
                   :value 0 :min 0 :max 100
                   :color "#FF0000")
   :spacing 8 :fill t))

(defun jetpacs-m3-sliders--centered ()
  "Upstream CenteredSliderSample: SliderDefaults.CenteredTrack over -50f..50f.
`:track \"centered\"' selects that track, and the value starts at
rememberSliderState's default of 0f -- the middle of the range, where the
active track has no width yet and grows out either way as it is dragged."
  (jetpacs-column
   (jetpacs-text "0.00")
   (jetpacs-slider "sliders-centered" (jetpacs-m3-demo "Centered slider")
                   :value 0 :min -50 :max 50
                   :track "centered")
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
    :build #'jetpacs-m3-sliders--custom-thumb)
   (jetpacs-m3-example
    "SliderWithCustomTrackAndThumbSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :build #'jetpacs-m3-sliders--custom-track-and-thumb)
   (jetpacs-m3-example
    "SliderWithTrackIconsSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "The slider track member chooses between M3's default and centered track and nothing else: the MusicNote and MusicOff icons this sample paints at both ends of the active and the inactive segment come from a DrawScope hung on the track composable, and the wire has no way to hand the Companion a drawing.")
   (jetpacs-m3-example
    "CenteredSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :build #'jetpacs-m3-sliders--centered)
   (jetpacs-m3-example
    "VerticalSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "There is no vertical slider node and no orientation member: steps = 9 over 0f..100f is the discrete values list, but the slider node always renders the horizontal M3 Slider, so VerticalSlider with reverseDirection cannot be asked for from Emacs.")
   (jetpacs-m3-example
    "VerticalCenteredSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :unsupported
    "Only the track half is on the wire: track \"centered\" is SliderDefaults.CenteredTrack exactly, but there is no vertical slider node and no orientation member, so this sample's subject -- that same track stood on end and reversed -- cannot be asked for.")
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
    "There is no range slider node for the two thumbs, and the one color member could not dress them anyway: it is a single thumb-and-active-track pair, while this sample gives the start thumb blue with a red active track, the end thumb green, and each its own Label printing that end of the range.")
   ))

(provide 'jetpacs-m3-sliders)
;;; jetpacs-m3-sliders.el ends here
