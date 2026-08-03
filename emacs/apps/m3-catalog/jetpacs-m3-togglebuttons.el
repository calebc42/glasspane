;;; jetpacs-m3-togglebuttons.el --- Catalog component: ToggleButtons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `ToggleButtons' + Examples.kt
;; `ToggleButtonsExamples' (10 examples), samples/ToggleButtonSamples.kt.
;;
;; All ten samples are one composable holding one piece of state: `var
;; checked by remember { mutableStateOf(false) }' driven into M3's
;; `ToggleButton' (or its Elevated/Tonal/Outlined siblings) through
;; `checked' and `onCheckedChange'.  That pair IS the subject -- the
;; component's own description says so: "a selectable button that
;; animates on press".
;;
;; Nothing on the wire holds it.  There is no `toggle_button' node
;; type, and the `button' node -- which now carries label, on_tap,
;; icon, variant (filled/tonal/elevated/outlined/text), size (xsmall
;; through xlarge), shape (round/square), animate_shape and enabled --
;; still has no checked member and no on_change.  The neighbours one
;; could reach for are worse rather than better: `chip' (M3 FilterChip,
;; and already the subject of the Chips page) has a `selected' member
;; but no id, so its state is authored from Emacs and a tap can never
;; flip it; `switch' and `checkbox' do hold state Companion-side, but
;; they draw a switch and a checkbox, each the subject of its own
;; catalog component.  A plain `button' would render and would
;; demonstrate nothing the Buttons page does not already show.
;;
;; So all ten are still unsupported -- but on one missing thing rather
;; than several.  The container each sample dresses its ToggleButton in
;; IS now expressible: the elevated variant (3 and 6), the square
;; resting shape and press morph (2), the container-height scale (7
;; through 10).  What no example survives is the toggling, and the
;; reasons say only that, plus the two places where a second detail --
;; ToggleButtonShapes' checkedShape (2) and the Filled/Outlined Edit
;; swap (6 through 10) -- is itself keyed to the missing checked state.
;; One upstream oddity is preserved as data: the example named
;; "RoundToggleButtonSample" invokes `SquareToggleButtonSample'.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-togglebuttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ToggleButtonSamples.kt"
  "Upstream ToggleButtonsExampleSourceUrl.")

(defconst jetpacs-m3-togglebuttons--checked-note
  "There is no toggle_button node type, and the button node -- label, on_tap, icon, variant, size, shape, animate_shape, enabled -- holds no checked state and dispatches no onCheckedChange, which is the pair this sample exists to demonstrate."
  "Why the plain ToggleButton sample is unsupported.")

(defconst jetpacs-m3-togglebuttons--size-note
  "The button node now has a :size member, so this step of the M3 container-height scale, with its matching shapesFor and contentPaddingFor, can be asked for from Emacs. The toggling cannot: no wire member holds the checked state, and the Filled/Outlined Edit swap is driven from that same missing state."
  "Why every size-variant ToggleButton sample is unsupported.")

(jetpacs-m3-defcomponent "togglebuttons"
  :name "ToggleButtons"
  :description
  "Toggle buttons provide a selectable button that animates on press."
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ToggleButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported jetpacs-m3-togglebuttons--checked-note)
   (jetpacs-m3-example
    "RoundToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported
    "The button node now carries :shape \"square\" and :animate-shape, so two thirds of ToggleButtonShapes(squareShape, pressedShape, roundShape) can be asked for. The third is checkedShape, and no wire member holds the checked state that selects it -- so the square-becomes-round morph this sample exists to demonstrate cannot be expressed.")
   (jetpacs-m3-example
    "ElevatedToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported
    "The button node does have :variant \"elevated\", so ElevatedToggleButton's container is on the wire, but it has no checked member and no on_change, so the toggling that ElevatedToggleButton exists to show cannot be put on the wire.")
   (jetpacs-m3-example
    "TonalToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported
    "The button node does have :variant \"tonal\", but it has no checked member and no on_change, so the toggling that TonalToggleButton exists to show cannot be put on the wire.")
   (jetpacs-m3-example
    "OutlinedToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported
    "The button node does have :variant \"outlined\", but it has no checked member and no on_change, so the toggling that OutlinedToggleButton exists to show cannot be put on the wire.")
   (jetpacs-m3-example
    "ToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported
    "The button node does have :variant \"elevated\" and a leading :icon, so the container and the Edit icon render. It carries one fixed icon name and no checked state, so neither the toggling nor the Filled/Outlined Edit swap this sample drives from checked can be expressed.")
   (jetpacs-m3-example
    "XSmallToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported jetpacs-m3-togglebuttons--size-note)
   (jetpacs-m3-example
    "MediumToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported jetpacs-m3-togglebuttons--size-note)
   (jetpacs-m3-example
    "LargeToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported jetpacs-m3-togglebuttons--size-note)
   (jetpacs-m3-example
    "XLargeToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported jetpacs-m3-togglebuttons--size-note)
   ))

(provide 'jetpacs-m3-togglebuttons)
;;; jetpacs-m3-togglebuttons.el ends here
