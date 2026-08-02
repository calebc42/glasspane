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
;; The other four ask for something with no wire member -- but not the
;; one this module first blamed.  The size scale IS expressible: a
;; `surface' carrying `:width', `:height' and a numeric `:corner' around
;; an `icon' of the matching `:size' composes every step, and the
;; Companion consumes all four.  What no member reaches is the SHADOW:
;; `RenderSurfaceNode' spends `elevation' on `tonalElevation' alone,
;; which is inert for every container color but the surface role, so a
;; composed FAB sits flat.  The fifth adds the scroll-driven SHOW AND
;; HIDE of `Modifier.animateFloatingActionButton', whose `visible'
;; argument is derived from a LazyColumn's `firstVisibleItemIndex' on
;; the device and never crosses the wire.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-floating-action-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
  "Upstream FloatingActionButtonsExampleSourceUrl.")

(defconst jetpacs-m3-floating-action-buttons--size-note
  "The surface node's elevation member is a tonal elevation only, so nothing on the wire can make a FAB cast a shadow. The size scale itself IS expressible — a surface carrying :width, :height and a numeric :corner around an icon of the matching :size composes each step exactly — but M3 renders that surface with tonalElevation, which recolors nothing unless the container is the surface role, and leaves shadowElevation at zero. A container that sits flat on the background is not a floating action button, so the sample's subject survives only in outline."
  "Why every sized FAB sample is unsupported.

An earlier revision of this string claimed the container size, corner size
and icon size could not be asked for from Emacs.  That was false three
times over: `:width'/`:height' and a numeric `:corner' are §16.5 universal
attributes the Companion applies in `Attributes.kt', `RenderSurfaceNode'
explicitly honours a numeric corner over its own shape enum, and
`RenderIcon' consumes `:size'.  The sample also never needed `icon_button',
whose missing size member the old string blamed.  What is really absent is
the shadow.")

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
    "Neither half is on the wire: no node placed in the scaffold fab slot has a visible member for animateFloatingActionButton, and nothing reports a LazyColumn's firstVisibleItemIndex back to Emacs, so the FAB scaling away as the list scrolls past its first item is state the device derives on its own. The medium container this one wears is separately blocked by the missing shadow elevation.")
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
