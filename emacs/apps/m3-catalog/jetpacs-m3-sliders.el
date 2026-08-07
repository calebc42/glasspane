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
;; The second member wave finished the module: `value_end' makes the
;; node a RangeSlider (state.changed becomes a two-number array, and
;; with `values' each thumb snaps to the nearest authored number on
;; commit), `orientation' renders M3's VerticalSlider against the
;; authored universal height, `value_label' floats each thumb's own
;; Label/PlainTooltip printing the in-flight position, `color_end'
;; tints the end thumb alone, and `track_icon_start'/`track_icon_end'
;; reproduce the MusicNote/MusicOff DrawScope recipe from two icon
;; names.  All eleven recreate.
;;
;; Two seams stated.  Upstream prints "%.2f".format(value) above the
;; track and recomposes it on every drag; the wire slider dispatches
;; once on gesture commit, so the readout above a track is authored at
;; the starting value — the LIVE readout is `value_label', on the thumb,
;; where M3 puts it.  And `color' is the thumbColor+activeTrackColor
;; PAIR, so RangeSliderWithCustomComponents' blue start thumb over a red
;; track collapses to one color for both; its green end thumb is
;; `color_end', exactly.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-sliders--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
  "Upstream SlidersExampleSourceUrl.")

(defconst jetpacs-m3-sliders--steps-values
  (list 0 10 20 30 40 50 60 70 80 90 100)
  "Nine steps over 0..100, excluding the endpoints: the multiples of ten.")

(defun jetpacs-m3-sliders--track-icons ()
  "Upstream SliderWithTrackIconsSample: MusicNote/MusicOff on each segment.
`:track-icon-start'/`:track-icon-end' are that DrawScope recipe by NAME:
the Companion draws each icon at the leading and trailing edge of both
the active and the inactive segment, tinted the segment's tick colour,
and suppresses a pair when its segment is narrower than the icon."
  (jetpacs-column
   (jetpacs-text "0.00")
   (jetpacs-slider "sliders-track-icons"
                   (jetpacs-m3-demo "Slider with track icons")
                   :value 0 :min 0 :max 100
                   :track-icon-start "music_note"
                   :track-icon-end "music_off")
   :spacing 8 :fill t))

(defun jetpacs-m3-sliders--vertical ()
  "Upstream VerticalSliderSample: nine steps over 0..100, stood on end.
`:orientation \"vertical\"' is M3's VerticalSlider; the universal
:height is the rail's length -- a vertical slider has no width to fill,
which is why the node deliberately does not fillMaxWidth here."
  (jetpacs-column
   (jetpacs-with-attrs (jetpacs-text "0.00") :align_self "center")
   (jetpacs-with-attrs
    (jetpacs-slider "sliders-vertical" (jetpacs-m3-demo "Vertical slider")
                    :value 0
                    :values jetpacs-m3-sliders--steps-values
                    :orientation "vertical")
    :height 300 :align_self "center")
   :spacing 16 :fill t))

(defun jetpacs-m3-sliders--vertical-centered ()
  "Upstream VerticalCenteredSliderSample: the centred track, vertical.
Both members compose: `:track \"centered\"' grows the active track out
from the middle of -50..50, and `:orientation' stands it on end."
  (jetpacs-column
   (jetpacs-with-attrs (jetpacs-text "0.00") :align_self "center")
   (jetpacs-with-attrs
    (jetpacs-slider "sliders-vertical-centered"
                    (jetpacs-m3-demo "Vertical centered slider")
                    :value 0 :min -50 :max 50
                    :orientation "vertical"
                    :track "centered")
    :height 300 :align_self "center")
   :spacing 16 :fill t))

(defun jetpacs-m3-sliders--range ()
  "Upstream RangeSliderSample: two thumbs over 0f..100f.
`:value-end' IS the second thumb: its presence renders RangeSlider and
the committed value becomes the [start, end] pair."
  (jetpacs-column
   (jetpacs-text "0.00 .. 100.00")
   (jetpacs-slider "sliders-range" (jetpacs-m3-demo "Range slider")
                   :value 0 :value-end 100 :min 0 :max 100)
   :spacing 8 :fill t))

(defun jetpacs-m3-sliders--step-range ()
  "Upstream StepRangeSliderSample: the same two thumbs over nine steps.
With `:values' each thumb SNAPS to the nearest authored number on
commit, so the pair reported is always two listed numbers -- the
discrete rule survives the range."
  (jetpacs-column
   (jetpacs-text "0.00 .. 100.00")
   (jetpacs-slider "sliders-step-range" (jetpacs-m3-demo "Step range slider")
                   :value 0 :value-end 100
                   :values jetpacs-m3-sliders--steps-values)
   :spacing 8 :fill t))

(defun jetpacs-m3-sliders--range-custom ()
  "Upstream RangeSliderWithCustomComponents: dressed thumbs with labels.
`:value-label' floats each thumb's own Label bubble printing its end of
the range in flight; `:color-end' is the green end thumb exactly.  The
one collapse the Commentary records: `:color' tints the start thumb AND
the active track as a pair, where upstream splits them blue and red."
  (jetpacs-column
   (jetpacs-slider "sliders-range-custom"
                   (jetpacs-m3-demo "Range slider with custom components")
                   :value 0 :value-end 100 :min 0 :max 100
                   :color "#FF0000"
                   :color-end "#00A000"
                   :value-label t)
   :spacing 8 :fill t))

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
  :builders (list #'jetpacs-slider)
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
    :build #'jetpacs-m3-sliders--track-icons)
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
    :build #'jetpacs-m3-sliders--vertical)
   (jetpacs-m3-example
    "VerticalCenteredSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :expressive t
    :build #'jetpacs-m3-sliders--vertical-centered)
   (jetpacs-m3-example
    "RangeSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :build #'jetpacs-m3-sliders--range)
   (jetpacs-m3-example
    "StepRangeSliderSample"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :build #'jetpacs-m3-sliders--step-range)
   (jetpacs-m3-example
    "RangeSliderWithCustomComponents"
    "Sliders examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SliderSamples.kt"
    :build #'jetpacs-m3-sliders--range-custom)
   ))

(provide 'jetpacs-m3-sliders)
;;; jetpacs-m3-sliders.el ends here
