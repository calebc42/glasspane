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
;; type, and the `button' node carries label, on_tap, icon, variant and
;; enabled -- no checked member, no on_change.  The neighbours one
;; could reach for are worse rather than better: `chip' (M3 FilterChip,
;; and already the subject of the Chips page) has a `selected' member
;; but no id, so its state is authored from Emacs and a tap can never
;; flip it; `switch' and `checkbox' do hold state Companion-side, but
;; they draw a switch and a checkbox, each the subject of its own
;; catalog component.  A plain `button' would render and would
;; demonstrate nothing the Buttons page does not already show.
;;
;; So all ten are unsupported, and each reason names what its sample
;; adds on top of the missing checked state: a ToggleButtonShapes
;; (example 2), an elevated container (3 and 6), the checked-driven
;; icon swap (6), or the container-height scale (7 through 10).  One
;; upstream oddity is preserved as data: the example named
;; "RoundToggleButtonSample" invokes `SquareToggleButtonSample'.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-togglebuttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ToggleButtonSamples.kt"
  "Upstream ToggleButtonsExampleSourceUrl.")

(defconst jetpacs-m3-togglebuttons--checked-note
  "There is no toggle_button node type, and the button node carries only label, on_tap, icon, variant and enabled: no wire member holds the checked state, and none dispatches the onCheckedChange this sample exists to demonstrate."
  "Why the plain ToggleButton sample is unsupported.")

(defconst jetpacs-m3-togglebuttons--size-note
  "Two members are missing at once: the button node has no checked state for onCheckedChange, and it has no size member, so the M3 container-height scale (ButtonDefaults.ExtraSmallContainerHeight through ExtraLargeContainerHeight) with its matching shapesFor and contentPaddingFor cannot be asked for from Emacs."
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
    "Neither half is on the wire: no node holds a ToggleButton checked state, and the only shape member on the wire is surface's whole-shape enum (rounded/rounded_small/circle), so ToggleButtonShapes(squareShape, pressedShape, roundShape) cannot be requested from Emacs.")
   (jetpacs-m3-example
    "ElevatedToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :unsupported
    "Neither half is on the wire: the button node has no checked member, and its variant enum is filled/tonal/outlined/text, so ElevatedToggleButton is not one of them.")
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
    "Three members are missing: the button node has no checked state, no elevated variant, and one fixed icon name, so the Filled/Outlined Edit swap this sample drives from checked cannot be expressed.")
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
