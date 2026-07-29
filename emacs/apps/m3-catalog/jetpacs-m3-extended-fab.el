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
;; cannot nest a scaffold, so the two default-size samples claim THIS
;; Example screen's own fab slot -- which is where upstream's animated
;; sibling puts its own FAB too.  The slot takes any node; a `button'
;; node carries the label and the leading icon, which is the whole of
;; what these two overloads differ by.  What the slot cannot promise is
;; the container itself: the Companion renders the node it is given, so
;; the M3 extended-FAB elevation and corner size are its business, not
;; the wire's.
;;
;; The other ten exist to demonstrate a SIZE
;; (Small/Medium/LargeExtendedFloatingActionButton, with their matching
;; FloatingActionButtonDefaults.MediumIconSize and LargeIconSize) or the
;; EXPANDED state derived from scroll position, and the wire has a
;; member for neither.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-extended-fab--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
  "Upstream ExtendedFABExampleSourceUrl.")

(defconst jetpacs-m3-extended-fab--size-note
  "The button node has no size member: the M3 extended-FAB size scale (SmallExtendedFloatingActionButton through LargeExtendedFloatingActionButton, each with its own container height, corner size and FloatingActionButtonDefaults icon size) cannot be asked for from Emacs."
  "Why every Small/Medium/Large extended-FAB sample is unsupported.")

(defconst jetpacs-m3-extended-fab--expanded-note
  "No node placed in the scaffold fab slot has an expanded member, and nothing on the wire reports a list's scroll position back to Emacs: the collapse to an icon-only FAB once the first visible item scrolls past is state this sample derives on the device."
  "Why every animated extended-FAB sample is unsupported.")

(defconst jetpacs-m3-extended-fab--animated-size-note
  "Neither half is on the wire: no fab-slot node has an expanded member and scroll position never reaches Emacs, and the button node has no size member for the Small/Medium/Large extended-FAB scale."
  "Why the sized animated extended-FAB samples are unsupported.")

(defun jetpacs-m3-extended-fab--icon-and-text ()
  "Upstream ExtendedFloatingActionButtonSample, as this screen's FAB.
The icon-and-text overload: Icons.Filled.Add beside the text
\"Extended FAB\".  The icon's \"Localized description\" has nowhere to
go -- a button node has no content_description member and is named on
screen by its own label."
  (jetpacs-button "Extended FAB" (jetpacs-m3-demo "Extended FAB")
                  :icon "add" :variant "filled"))

(defun jetpacs-m3-extended-fab--text ()
  "Upstream ExtendedFloatingActionButtonTextSample, as this screen's FAB.
The text-only overload: one Text child reading \"Extended FAB\", and no
icon slot at all."
  (jetpacs-button "Extended FAB" (jetpacs-m3-demo "Extended FAB")
                  :variant "filled"))

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
    :unsupported jetpacs-m3-extended-fab--size-note)
   (jetpacs-m3-example
    "MediumExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--size-note)
   (jetpacs-m3-example
    "LargeExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--size-note)
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
    :unsupported jetpacs-m3-extended-fab--size-note)
   (jetpacs-m3-example
    "MediumExtendedFloatingActionButtonTextSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--size-note)
   (jetpacs-m3-example
    "LargeExtendedFloatingActionButtonTextSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--size-note)
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
    :unsupported jetpacs-m3-extended-fab--animated-size-note)
   (jetpacs-m3-example
    "MediumAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--animated-size-note)
   (jetpacs-m3-example
    "LargeAnimatedExtendedFloatingActionButtonSample"
    "Extended FAB examples"
    :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
    :expressive t
    :unsupported jetpacs-m3-extended-fab--animated-size-note)
   ))

(provide 'jetpacs-m3-extended-fab)
;;; jetpacs-m3-extended-fab.el ends here
