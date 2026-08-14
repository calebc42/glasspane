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
;; The wire now holds it.  `button' carries `checked' and `on_change':
;; a button carrying `checked' is a toggle, the Companion holds the
;; flipped boolean on the device keyed by the node's `id', publishes
;; `state.changed' before the action, and hands the new boolean to
;; `on_change' in `args.value'.  So each of these builders authors
;; `:checked :json-false' -- upstream's `mutableStateOf(false)', the
;; initial value, not a default worth omitting: a `button' WITHOUT
;; `checked' is not a toggle at all -- plus the `:id' (§16.1) the state
;; is keyed on.  `on_tap' stays required by the node and carries the
;; same demo message, since a toggle dispatches `on_change' instead of
;; it.
;;
;; The containers each sample dresses its ToggleButton in were already
;; expressible and now travel with the state: the elevated variant (3
;; and 6), the tonal (4), the outlined (5), and the container-height
;; scale (7 through 10).  Nine of ten recreate.
;;
;; No builder here asks for `animate_shape'.  Every ToggleButton has a
;; press morph from its own defaults -- `ToggleButtonDefaults.shapes()',
;; and `shapesFor(size)' at a size step, which is what samples 7 through
;; 10 spell out by hand -- so it belongs to the component the Companion
;; draws, not to a member Emacs asks for; `animate_shape' exists because
;; a plain `Button' has no morph unless one is passed.
;;
;; The bespoke shape set rides two members now: on a toggle, `:shape'
;; names the RESTING shape and `:checked-shape' the one it morphs to
;; while checked, so the inverted square-at-rest/round-checked set —
;; ToggleButtonShapes(squareShape, pressedShape, roundShape) — is asked
;; for by saying each half once.  All ten build.  (Preserved as data:
;; the example named "RoundToggleButtonSample" invokes
;; `SquareToggleButtonSample'.)
;;
;; Two details of ToggleButtonWithIconSample and its four sized
;; siblings survive as notes rather than nodes: upstream swaps
;; Icons.Filled.Edit for Icons.Outlined.Edit while checked, and
;; `checked_icon' is an `icon_button' member, not a `button' one -- and
;; even there the icon vocabulary is one name per glyph, resolved
;; outlined-first, so no wire string names the filled Edit.  `edit'
;; draws the outlined vector, which is the unchecked state upstream
;; starts in.  The samples' subject -- a toggle whose content is an
;; icon and a label, at a container-height step -- is on the wire, so
;; they build.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-togglebuttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ToggleButtonSamples.kt"
  "Upstream ToggleButtonsExampleSourceUrl.")

(defun jetpacs-m3-togglebuttons--toggle (id label &rest options)
  "A toggle `button' labeled LABEL, keyed on ID, starting unchecked.
OPTIONS are extra `jetpacs-button' keywords.  `:checked :json-false' is
upstream's `mutableStateOf(false)' and is what makes the node a toggle
at all; ID is the §16.1 address its device-held state is published on.
`on_change' receives the flipped boolean; the required `on_tap' carries
the same message, because a toggle dispatches `on_change' in its place."
  (jetpacs-with-attrs
   (apply #'jetpacs-button label (jetpacs-m3-demo label)
          :checked :json-false
          :on-change (jetpacs-m3-demo label)
          options)
   :id id))

(defun jetpacs-m3-togglebuttons--basic ()
  "Upstream ToggleButtonSample: ToggleButton(checked, onCheckedChange)."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-basic" "Button"))

(defun jetpacs-m3-togglebuttons--round ()
  "Upstream RoundToggleButtonSample: the inverted set, one member per shape.
`:shape' names the resting square and `:checked-shape' the round it
morphs to while checked -- ToggleButtonShapes(squareShape, pressedShape,
roundShape) asked for by saying each half once.  Node
\"togglebuttons-round\" is where the device holds the flipped boolean,
starting from upstream's false.  (The catalog names this example
RoundToggleButtonSample while invoking `SquareToggleButtonSample';
preserved as data.)"
  (jetpacs-with-attrs
   (jetpacs-button "Round Toggle Button"
                   (jetpacs-m3-demo "Round Toggle Button")
                   :checked :json-false
                   :on-change (jetpacs-m3-demo "Round Toggle Button")
                   :shape "square"
                   :checked-shape "round")
   :id "togglebuttons-round"))

(defun jetpacs-m3-togglebuttons--elevated ()
  "Upstream ElevatedToggleButtonSample: ElevatedToggleButton."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-elevated" "Elevated Button"
                                    :variant "elevated"))

(defun jetpacs-m3-togglebuttons--tonal ()
  "Upstream TonalToggleButtonSample: TonalToggleButton."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-tonal" "Tonal Button"
                                    :variant "tonal"))

(defun jetpacs-m3-togglebuttons--outlined ()
  "Upstream OutlinedToggleButtonSample: OutlinedToggleButton."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-outlined" "Outlined Button"
                                    :variant "outlined"))

(defun jetpacs-m3-togglebuttons--with-icon ()
  "Upstream ToggleButtonWithIconSample: an ElevatedToggleButton, Edit icon.
Upstream draws Icons.Filled.Edit while checked and Icons.Outlined.Edit
otherwise; `edit' is the outlined vector, the state it starts in."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-with-icon" "Edit"
                                    :variant "elevated" :icon "edit"))

(defun jetpacs-m3-togglebuttons--xsmall-with-icon ()
  "Upstream XSmallToggleButtonWithIconSample: ExtraSmallContainerHeight."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-xsmall" "Label"
                                    :icon "edit" :size "xsmall"))

(defun jetpacs-m3-togglebuttons--medium-with-icon ()
  "Upstream MediumToggleButtonWithIconSample: MediumContainerHeight."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-medium" "Label"
                                    :icon "edit" :size "medium"))

(defun jetpacs-m3-togglebuttons--large-with-icon ()
  "Upstream LargeToggleButtonWithIconSample: LargeContainerHeight."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-large" "Label"
                                    :icon "edit" :size "large"))

(defun jetpacs-m3-togglebuttons--xlarge-with-icon ()
  "Upstream XLargeToggleButtonWithIconSample: ExtraLargeContainerHeight."
  (jetpacs-m3-togglebuttons--toggle "togglebuttons-xlarge" "Label"
                                    :icon "edit" :size "xlarge"))

(jetpacs-m3-defcomponent "togglebuttons"
  :builders (list #'jetpacs-button)
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
    :build #'jetpacs-m3-togglebuttons--basic)
   (jetpacs-m3-example
    "RoundToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--round)
   (jetpacs-m3-example
    "ElevatedToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--elevated)
   (jetpacs-m3-example
    "TonalToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--tonal)
   (jetpacs-m3-example
    "OutlinedToggleButtonSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--outlined)
   (jetpacs-m3-example
    "ToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--with-icon)
   (jetpacs-m3-example
    "XSmallToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--xsmall-with-icon)
   (jetpacs-m3-example
    "MediumToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--medium-with-icon)
   (jetpacs-m3-example
    "LargeToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--large-with-icon)
   (jetpacs-m3-example
    "XLargeToggleButtonWithIconSample"
    "ToggleButton examples"
    :source jetpacs-m3-togglebuttons--source
    :expressive t
    :build #'jetpacs-m3-togglebuttons--xlarge-with-icon)
   ))

(provide 'jetpacs-m3-togglebuttons)
;;; jetpacs-m3-togglebuttons.el ends here
