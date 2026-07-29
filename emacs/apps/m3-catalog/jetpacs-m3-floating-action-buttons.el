;;; jetpacs-m3-floating-action-buttons.el --- Catalog component: Floating action buttons -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `FloatingActionButtons' + Examples.kt
;; `FloatingActionButtonsExamples' (5 examples),
;; samples/FloatingActionButtonSamples.kt.
;;
;; The five are one composable at four sizes plus an animated one.  Each
;; holds exactly the same child -- Icon(Icons.Filled.Add, "Localized
;; description") -- so the ONLY thing four of them demonstrate is the
;; container: SmallFloatingActionButton, the default, then the
;; expressive MediumFloatingActionButton and LargeFloatingActionButton,
;; each with its own container size, corner size and matching
;; FloatingActionButtonDefaults icon size.
;;
;; A FAB is screen chrome: the wire spells it `scaffold.fab' (§17.6, and
;; the FloatingActionButton row of M3-COMPONENT-LOOKUP), and a Node tree
;; cannot nest a scaffold, so the default-size sample claims THIS
;; Example screen's own fab slot rather than drawing a nested scaffold in
;; the body -- see `jetpacs-m3-slot-keys'.  The slot takes any node, and
;; `icon_button' carries the icon and its accessible name, which is the
;; whole of that sample.  What the slot cannot promise is the container:
;; `RenderScaffold' hands the fab node straight to `RenderNode', so the
;; M3 FAB elevation and corner size are the Companion's business.
;;
;; The other four ask for something with no wire member: a SIZE (three
;; of them), or the scroll-driven SHOW AND HIDE of
;; `Modifier.animateFloatingActionButton', whose `visible' argument is
;; derived from a LazyColumn's `firstVisibleItemIndex' on the device.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-floating-action-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
  "Upstream FloatingActionButtonsExampleSourceUrl.")

(defconst jetpacs-m3-floating-action-buttons--size-note
  "The icon_button node has no size member: the M3 FAB size scale (SmallFloatingActionButton through LargeFloatingActionButton, each with its own container size, corner size and FloatingActionButtonDefaults icon size) cannot be asked for from Emacs, and that scale is this sample's whole difference from FloatingActionButtonSample."
  "Why every sized FAB sample is unsupported.")

(defun jetpacs-m3-floating-action-buttons--default ()
  "Upstream FloatingActionButtonSample, as this screen\\='s FAB.
FloatingActionButton(onClick) wrapping one child,
Icon(Icons.Filled.Add, \"Localized description\").  The icon and that
accessible name are the whole sample; on the wire the name is the
content_description member, where a screen reader looks."
  (jetpacs-icon-button "add" (jetpacs-m3-demo "Localized description")
                       :content-description "Localized description"))

(jetpacs-m3-defcomponent "floating-action-buttons"
  :name "Floating action buttons"
  :description
  "The FAB represents the most important action on a screen. It puts key actions within reach."
  :guidelines "https://m3.material.io/components/floating-action-button"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#floatingactionbutton"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/FloatingActionButton.kt"
  :examples
  (list
   (jetpacs-m3-example
    "FloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :slots (list :fab #'jetpacs-m3-floating-action-buttons--default))
   (jetpacs-m3-example
    "LargeFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :unsupported jetpacs-m3-floating-action-buttons--size-note)
   (jetpacs-m3-example
    "AnimatedFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :expressive t
    :unsupported
    "Neither half is on the wire: no node placed in the scaffold fab slot has a visible member for animateFloatingActionButton, and nothing reports a LazyColumn's firstVisibleItemIndex back to Emacs, so the FAB scaling away as the list scrolls past its first item is state the device derives on its own; icon_button also has no size member for the medium FAB container and its MediumIconSize.")
   (jetpacs-m3-example
    "MediumFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :expressive t
    :unsupported jetpacs-m3-floating-action-buttons--size-note)
   (jetpacs-m3-example
    "SmallFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :unsupported jetpacs-m3-floating-action-buttons--size-note)
   ))

(provide 'jetpacs-m3-floating-action-buttons)
;;; jetpacs-m3-floating-action-buttons.el ends here
