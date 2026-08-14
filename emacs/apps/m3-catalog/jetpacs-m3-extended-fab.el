;;; jetpacs-m3-extended-fab.el --- Catalog component: Extended FAB -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `ExtendedFloatingActionButton' + Examples.kt
;; `ExtendedFABExamples' (12 examples),
;; samples/FloatingActionButtonSamples.kt.
;;
;; The twelve are one composable in three shapes across four sizes: the
;; icon-and-text overload, the text-only overload, and the animated one
;; whose `expanded' argument tracks a LazyColumn's
;; `firstVisibleItemIndex' so the FAB collapses to its icon as the list
;; scrolls.
;;
;; A FAB is screen chrome: the wire spells it `scaffold.fab' (§17.6, and
;; the FloatingActionButton row of M3-COMPONENT-LOOKUP), and a Node tree
;; cannot nest a scaffold, so each of the eight non-animated samples
;; claims THIS Example screen's own fab slot -- which is where upstream's
;; animated sibling puts its own FAB too.  The slot takes any node; a
;; `button' node carries the label, the leading icon and now the size
;; step, which is the whole of what those eight overloads differ by.
;; What the slot cannot promise is the container itself: the Companion
;; renders the node it is given, so the M3 extended-FAB elevation and
;; corner size are its business, not the wire's.
;;
;; `button.size' is the M3 BUTTON container scale, resolved once on the
;; Companion into height, content padding, icon size, icon spacing and
;; label typography -- so the small/medium/large steps also carry what
;; upstream spells as FloatingActionButtonDefaults.MediumIconSize and
;; LargeIconSize.  Its steps are not the ExtendedFab*Tokens heights;
;; picking a step is asking for that step of the scale, and which dp the
;; Companion resolves it to stays the Companion's business, exactly as
;; the container already is.
;;
;; The animated four ride `:expanded "auto"': the Companion derives
;; the expanded state from the scaffold body's OWN scroll — expanded
;; while it rests at its start, collapsing to the icon as it moves —
;; which is exactly upstream's firstVisibleItemIndex derivation, done
;; device-locally so no per-scroll traffic ever crosses the wire.  All
;; twelve build.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-extended-fab--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
  "Upstream ExtendedFABExampleSourceUrl.")

(defun jetpacs-m3-extended-fab--animated (label size)
  "An Animated sample's FAB: LABEL at SIZE, collapsing on scroll.
`:expanded \"auto\"' derives from the body's own scroll — icon+label at
the top, icon-only once it moves."
  (jetpacs-button label (jetpacs-m3-demo label)
                  :icon "add" :variant "filled" :size size
                  :expanded "auto"))

(defun jetpacs-m3-extended-fab--content ()
  "The list the Animated samples scroll under their collapsing FAB."
  (apply #'jetpacs-column
         (append (cl-loop for i from 0 below 100
                          collect (jetpacs-with-attrs
                                   (jetpacs-text (format "Item %d" i))
                                   :pad (list :horizontal 16)))
                 (list :spacing 8 :fill t))))

(defun jetpacs-m3-extended-fab--icon-and-text ()
  "Upstream ExtendedFloatingActionButtonSample, as this screen's FAB.
The icon-and-text overload: Icons.Filled.Add beside the text
\"Extended FAB\".  The icon's \"Localized description\" has nowhere to
go -- a button node has no content_description member and is named on
screen by its own label."
  (jetpacs-button "Extended FAB" (jetpacs-m3-demo "Extended FAB")
                  :icon "add" :variant "filled"))

(defun jetpacs-m3-extended-fab--small-icon-and-text ()
  "Upstream SmallExtendedFloatingActionButtonSample, as this screen's FAB.
The small step of the scale, Icons.Filled.Add beside \"Small Extended
FAB\".  `:size' asks for that step, which resolves the icon size along
with the container."
  (jetpacs-button "Small Extended FAB" (jetpacs-m3-demo "Small Extended FAB")
                  :icon "add" :variant "filled" :size "small"))

(defun jetpacs-m3-extended-fab--medium-icon-and-text ()
  "Upstream MediumExtendedFloatingActionButtonSample, as this screen's FAB.
The medium step, Icons.Filled.Add beside \"Medium Extended FAB\".
Upstream sizes the icon itself with
FloatingActionButtonDefaults.MediumIconSize; here the step carries it,
the scale being resolved whole on the Companion."
  (jetpacs-button "Medium Extended FAB" (jetpacs-m3-demo "Medium Extended FAB")
                  :icon "add" :variant "filled" :size "medium"))

(defun jetpacs-m3-extended-fab--large-icon-and-text ()
  "Upstream LargeExtendedFloatingActionButtonSample, as this screen's FAB.
The large step, Icons.Filled.Add beside \"Large Extended FAB\".
Upstream sizes the icon itself with
FloatingActionButtonDefaults.LargeIconSize; here the step carries it."
  (jetpacs-button "Large Extended FAB" (jetpacs-m3-demo "Large Extended FAB")
                  :icon "add" :variant "filled" :size "large"))

(defun jetpacs-m3-extended-fab--text ()
  "Upstream ExtendedFloatingActionButtonTextSample, as this screen's FAB.
The text-only overload: one Text child reading \"Extended FAB\", and no
icon slot at all."
  (jetpacs-button "Extended FAB" (jetpacs-m3-demo "Extended FAB")
                  :variant "filled"))

(defun jetpacs-m3-extended-fab--small-text ()
  "Upstream SmallExtendedFloatingActionButtonTextSample, this screen's FAB.
The text-only overload at the small step: \"Small Extended FAB\", no
icon slot."
  (jetpacs-button "Small Extended FAB" (jetpacs-m3-demo "Small Extended FAB")
                  :variant "filled" :size "small"))

(defun jetpacs-m3-extended-fab--medium-text ()
  "Upstream MediumExtendedFloatingActionButtonTextSample, this screen's FAB.
The text-only overload at the medium step: \"Medium Extended FAB\", no
icon slot."
  (jetpacs-button "Medium Extended FAB" (jetpacs-m3-demo "Medium Extended FAB")
                  :variant "filled" :size "medium"))

(defun jetpacs-m3-extended-fab--large-text ()
  "Upstream LargeExtendedFloatingActionButtonTextSample, this screen's FAB.
The text-only overload at the large step: \"Large Extended FAB\", no
icon slot."
  (jetpacs-button "Large Extended FAB" (jetpacs-m3-demo "Large Extended FAB")
                  :variant "filled" :size "large"))

(defun jetpacs-m3-extended-fab--animated-fab ()
  "Upstream AnimatedExtendedFloatingActionButtonSample, as this screen's FAB.
The icon-and-text overload with `expanded' bound to state: upstream
remembers a LazyListState and reads expanded off
firstVisibleItemIndex == 0.  `:expanded \"auto\"' asks the Companion for
that same derivation from the scaffold body's own scroll, so \"Extended
FAB\" carries icon and label while the list rests at its start and
collapses to the icon as it moves -- device-locally, with no per-scroll
traffic on the wire.  The body is the hundred items of
`jetpacs-m3-extended-fab--content'."
  (jetpacs-m3-extended-fab--animated "Extended FAB" nil))

(defun jetpacs-m3-extended-fab--small-animated-fab ()
  "Upstream SmallAnimatedExtendedFloatingActionButtonSample, this screen's FAB.
The same scroll-driven collapse at the small step of the scale: \"Small
Extended FAB\" beside Icons.Filled.Add, with `:size' asking for that
step -- container, content padding and icon size resolved together on
the Companion -- and `:expanded \"auto\"' standing in for upstream's
firstVisibleItemIndex derivation."
  (jetpacs-m3-extended-fab--animated "Small Extended FAB" "small"))

(defun jetpacs-m3-extended-fab--medium-animated-fab ()
  "Upstream MediumAnimatedExtendedFloatingActionButtonSample, this screen's FAB.
The medium step, collapsing on scroll: \"Medium Extended FAB\" beside
Icons.Filled.Add.  Upstream sizes the icon itself with
FloatingActionButtonDefaults.MediumIconSize; here the step carries it,
and `:expanded \"auto\"' carries the collapse."
  (jetpacs-m3-extended-fab--animated "Medium Extended FAB" "medium"))

(defun jetpacs-m3-extended-fab--large-animated-fab ()
  "Upstream LargeAnimatedExtendedFloatingActionButtonSample, this screen's FAB.
The large step, collapsing on scroll: \"Large Extended FAB\" beside
Icons.Filled.Add.  Upstream sizes the icon itself with
FloatingActionButtonDefaults.LargeIconSize; here the step carries it,
and `:expanded \"auto\"' drops the label as the hundred items move."
  (jetpacs-m3-extended-fab--animated "Large Extended FAB" "large"))

(jetpacs-m3-defcomponent "extended-fab"
  :builders (list #'jetpacs-scaffold #'jetpacs-button)
  :name "Extended FAB"
  :description
  "Extended FABs help people take primary actions. They're wider than FABs to accommodate a text label and larger target area."
  :guidelines "https://m3.material.io/components/extended-fab"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#extendedfloatingactionbutton"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/FloatingActionButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :slots (list :fab #'jetpacs-m3-extended-fab--icon-and-text))
   (jetpacs-m3-example
    "SmallExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :slots (list :fab #'jetpacs-m3-extended-fab--small-icon-and-text))
   (jetpacs-m3-example
    "MediumExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :slots (list :fab #'jetpacs-m3-extended-fab--medium-icon-and-text))
   (jetpacs-m3-example
    "LargeExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :slots (list :fab #'jetpacs-m3-extended-fab--large-icon-and-text))
   (jetpacs-m3-example
    "ExtendedFloatingActionButtonTextSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :slots (list :fab #'jetpacs-m3-extended-fab--text))
   (jetpacs-m3-example
    "SmallExtendedFloatingActionButtonTextSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :slots (list :fab #'jetpacs-m3-extended-fab--small-text))
   (jetpacs-m3-example
    "MediumExtendedFloatingActionButtonTextSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :slots (list :fab #'jetpacs-m3-extended-fab--medium-text))
   (jetpacs-m3-example
    "LargeExtendedFloatingActionButtonTextSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :slots (list :fab #'jetpacs-m3-extended-fab--large-text))
   (jetpacs-m3-example
    "AnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :build #'jetpacs-m3-extended-fab--content
    :slots (list :fab #'jetpacs-m3-extended-fab--animated-fab))
   (jetpacs-m3-example
    "SmallAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :build #'jetpacs-m3-extended-fab--content
    :slots (list :fab #'jetpacs-m3-extended-fab--small-animated-fab))
   (jetpacs-m3-example
    "MediumAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :build #'jetpacs-m3-extended-fab--content
    :slots (list :fab #'jetpacs-m3-extended-fab--medium-animated-fab))
   (jetpacs-m3-example
    "LargeAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :build #'jetpacs-m3-extended-fab--content
    :slots (list :fab #'jetpacs-m3-extended-fab--large-animated-fab))
   ))

(provide 'jetpacs-m3-extended-fab)
;;; jetpacs-m3-extended-fab.el ends here
