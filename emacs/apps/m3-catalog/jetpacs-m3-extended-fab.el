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
;; The remaining four are the animated ones, whose subject is the
;; EXPANDED state derived from a LazyColumn's scroll position, and the
;; wire has no member for it.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-extended-fab--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
  "Upstream ExtendedFABExampleSourceUrl.")

(defconst jetpacs-m3-extended-fab--expanded-note
  "No node placed in the scaffold fab slot has an expanded member, and nothing on the wire reports a list's scroll position back to Emacs: the collapse to an icon-only FAB once the first visible item scrolls past is state this sample derives on the device."
  "Why every animated extended-FAB sample is unsupported.")

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

(jetpacs-m3-defcomponent "extended-fab"
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
    :unsupported jetpacs-m3-extended-fab--expanded-note)
   (jetpacs-m3-example
    "SmallAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--expanded-note)
   (jetpacs-m3-example
    "MediumAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--expanded-note)
   (jetpacs-m3-example
    "LargeAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--expanded-note)
   ))

(provide 'jetpacs-m3-extended-fab)
;;; jetpacs-m3-extended-fab.el ends here
