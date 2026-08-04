;;; jetpacs-m3-button-groups.el --- Catalog component: Button Groups -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `ButtonGroups' + Examples.kt
;; `ButtonGroupsExamples' (4 examples), samples/ButtonGroupSamples.kt.
;;
;; The component's own description is the whole triage: "a container for
;; material components that adds an animation on press".  What a button
;; group contributes over the buttons inside it is CONTAINER BEHAVIOUR —
;; the neighbour-squeeze animation, the measure-time overflow into a
;; menu, and the connected leading/middle/trailing corner shapes that
;; make the members read as one control.
;;
;; The plain sample recreates on the `button_group' node — the 51st
;; type — which owns the first two halves outright: M3's ButtonGroup
;; couples the press animation across its clickableItems and moves what
;; does not fit into the overflow menu at MEASURE time, a width Emacs
;; never sees.  The three CONNECTED samples remain out: their items are
;; toggles with a shared selection and the morphing connected shapes,
;; not clickableItems, and neither half is on the wire yet.
;;
;; Three of the four samples are built from `ToggleButton', and half of
;; that pair HAS now landed: `button' takes :checked and :on-change, and
;; the Companion holds the flipped value on the device.  It is still not
;; enough for any of the three, for two different reasons.
;;
;; Two of them — SingleSelect… and Vertical… — want ONE selection across
;; the group (upstream says so out loud: `Role.RadioButton', a single
;; `selectedIndex').  Nothing on the wire binds toggles together; each
;; `button' holds its own device-side value, so checking Work cannot
;; clear the other four, and the mutual exclusion IS the sample.
;;
;; The third — MultiSelect… — wants exactly five independent booleans,
;; which is precisely what :checked carries, so the state model does
;; survive.  What does not survive is every way the user would SEE it: a
;; checked `button' used to draw exactly like an unchecked one; now the
;; connected family is on the wire and all three connected samples are
;; live.  `shape_role' (leading/middle/trailing across, top/bottom down)
;; selects the M3 connected shape set with its caps and its press and
;; checked morphs; `checked_icon' with the `_filled' icon-name suffix
;; carries the Outlined-at-rest/Filled-while-checked glyph swap; and
;; `column.overlap' is the -6dp interlock the vertical group needs,
;; SPEC 16.5 keeping `spacing' itself non-negative.
;;
;; The two selection models split exactly along the state's OWNER.
;; Multi-select is five independent device-held booleans -- authored
;; `:checked :json-false' once, flipped on the device, upstream's
;; mutableStateListOf.  Single-select is upstream's ONE selectedIndex,
;; and one value fanned across five nodes can only live in Emacs: each
;; toggle authors `:checked' FROM module state and dispatches the fn
;; verb, whose mutation sets the index and re-pushes -- checking Work
;; really does clear the other four, one gesture, one round trip.
;; Role.RadioButton semantics stay a stated seam: the wire has no
;; member for a11y roles on a toggle.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-button-groups--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ButtonGroupSamples.kt"
  "Upstream ButtonGroupsExampleSourceUrl.")

(defconst jetpacs-m3-button-groups--options
  '(("Work" . "work") ("Restaurant" . "restaurant") ("Coffee" . "coffee")
    ("Search" . "search") ("Home" . "home"))
  "The five connected options: (label . icon), upstream order.")

(defvar jetpacs-m3-button-groups--selected 0
  "SingleSelectConnected\='s one selectedIndex, upstream verbatim.")

(dotimes (i 5)
  (puthash (format "button-groups-single-%d" i)
           (let ((i i))
             (lambda () (setq jetpacs-m3-button-groups--selected i)))
           jetpacs-m3-fn-registry))

(defvar jetpacs-m3-button-groups--vertical-selected 0
  "VerticalButtonGroupSample\='s selectedIndex.")

(dotimes (i 5)
  (puthash (format "button-groups-vertical-%d" i)
           (let ((i i))
             (lambda () (setq jetpacs-m3-button-groups--vertical-selected i)))
           jetpacs-m3-fn-registry))

(defun jetpacs-m3-button-groups--connected (n i label icon &rest opts)
  "Connected toggle I of N: LABEL, ICON, the positional shape role.
OPTS carry the sample\='s own :checked / :on-change / :id."
  (apply #'jetpacs-button label (jetpacs-m3-demo label)
         :icon icon
         :checked-icon (concat icon "_filled")
         :shape-role (cond ((= i 0) "leading")
                           ((= i (1- n)) "trailing")
                           (t "middle"))
         opts))

(defun jetpacs-m3-button-groups--single ()
  "Upstream SingleSelectConnectedButtonGroupWithFlowLayoutSample.
One selectedIndex in module state; every tap runs the fn verb and the
next snapshot re-authors all five checked values, so checking Work
really does clear the other four."
  (jetpacs-flow-row
   (cl-loop
    for (label . icon) in jetpacs-m3-button-groups--options
    for i from 0
    collect (jetpacs-with-attrs
             (jetpacs-m3-button-groups--connected
              5 i label icon
              :checked (if (= i jetpacs-m3-button-groups--selected)
                           t :json-false)
              :on-change (jetpacs-m3-fn-action
                          (format "button-groups-single-%d" i)))
             :id (format "button-groups-single-%d" i)))
   :spacing 2 :run-spacing 2))

(defun jetpacs-m3-button-groups--multi ()
  "Upstream MultiSelectConnectedButtonGroupWithFlowLayoutSample.
Five INDEPENDENT device-held booleans -- authored unchecked once and
flipped on the device, which is exactly upstream\='s mutableStateListOf."
  (jetpacs-flow-row
   (cl-loop
    for (label . icon) in jetpacs-m3-button-groups--options
    for i from 0
    collect (jetpacs-with-attrs
             (jetpacs-m3-button-groups--connected
              5 i label icon
              :checked :json-false
              :on-change (jetpacs-m3-demo label))
             :id (format "button-groups-multi-%d" i)))
   :spacing 2 :run-spacing 2))

(defun jetpacs-m3-button-groups--vertical ()
  "Upstream VerticalButtonGroupSample: five toggles interlocked by -6dp.
shape_role top/middle/bottom carries the vertical caps; the single
selectedIndex lives in module state on the fn verb, like the
single-select row."
  (apply #'jetpacs-column
         (append
          (cl-loop
           for i from 0 below 5
           collect (jetpacs-with-attrs
                    (jetpacs-button
                     (format "Button %d" (1+ i))
                     (jetpacs-m3-demo (format "Button %d" (1+ i)))
                     :checked (if (= i jetpacs-m3-button-groups--vertical-selected)
                                  t :json-false)
                     :on-change (jetpacs-m3-fn-action
                                 (format "button-groups-vertical-%d" i))
                     :shape-role (cond ((= i 0) "top")
                                       ((= i 4) "bottom")
                                       (t "middle")))
                    :id (format "button-groups-vertical-%d" i)))
          (list :overlap 6))))

(jetpacs-m3-defcomponent "button-groups"
  :name "Button Groups"
  :description
  "button groups is a container for material components that adds an animation on press"
  :guidelines "https://m3.material.io/components/button-groups"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#buttongroups"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ButtonGroup.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ButtonGroupSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :build (lambda ()
             ;; Ten numbered clickableItems: the press animation couples
             ;; neighbours and the overflow fold happens at measure time.
             (jetpacs-button-group
              (cl-loop for i from 0 below 10
                       collect (jetpacs-button-group-item
                                (number-to-string i)
                                (jetpacs-m3-demo (format "Button %d" i)))))))
   (jetpacs-m3-example
    "SingleSelectConnectedButtonGroupWithFlowLayoutSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :build #'jetpacs-m3-button-groups--single)
   (jetpacs-m3-example
    "MultiSelectConnectedButtonGroupWithFlowLayoutSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :build #'jetpacs-m3-button-groups--multi)
   (jetpacs-m3-example
    "VerticalButtonGroupSample"
    "ButtonGroup examples"
    :source jetpacs-m3-button-groups--source
    :expressive t
    :build #'jetpacs-m3-button-groups--vertical)
   ))

(provide 'jetpacs-m3-button-groups)
;;; jetpacs-m3-button-groups.el ends here
