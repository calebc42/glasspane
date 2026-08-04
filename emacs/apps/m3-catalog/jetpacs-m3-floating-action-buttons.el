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
;; That container is now composable end to end.  `surface' carries
;; `:shadow-elevation', which `RenderSurfaceNode' spends on Compose's
;; real `shadowElevation' -- so the thing this module used to call
;; unreachable, the CAST SHADOW that makes a FAB float, is a wire member
;; today.  Put it with the §16.5 universal `:width', `:height' and a
;; numeric `:corner' (which `RenderSurfaceNode' honours over its own
;; shape enum) around a `box' that centers an `icon' of the matching
;; `:size', and each size step is the M3 token set exactly:
;;
;;   small    40dp   corner 12   icon 24    (FabSmallTokens)
;;   default  56dp   corner 16   icon 24    (FabBaselineTokens)
;;   medium   80dp   corner 20   icon 28    (FabMediumTokens, LargeIncreased)
;;   large    96dp   corner 28   icon 36    (FabLargeTokens; the icon is
;;                                           FloatingActionButtonDefaults.
;;                                           LargeIconSize, which overrides
;;                                           its own token)
;;
;; on `primary_container' at 6dp of shadow -- FabPrimaryContainerTokens'
;; ContainerColor and its Level3 ContainerElevation.  The `box' takes the
;; tap because `surface' has no on_tap member; Surface propagates its min
;; constraints to its content, so the box fills the whole container and
;; the ripple is clipped to the corner.
;;
;; A FAB is also screen chrome: the wire spells it `scaffold.fab' (§17.6,
;; and the FloatingActionButton row of M3-COMPONENT-LOOKUP), and a Node
;; tree cannot nest a scaffold, so all four sized samples claim THIS
;; Example screen's own fab slot rather than drawing a nested scaffold in
;; the body -- see `jetpacs-m3-slot-keys'.  `RenderScaffold' hands the fab
;; node straight to `RenderNode', so the slot renders whatever it is
;; given: the composed container, pinned where a FAB belongs.
;;
;; Only the fifth is still out of reach, and for a reason that has
;; nothing to do with the container: it adds the scroll-driven SHOW AND
;; HIDE of `Modifier.animateFloatingActionButton'.  `scaffold' has no
;; visibility member (its optional set ends at `on_refresh') and
;; `:fab-hide-on-scroll' is that request now: the scaffold wraps the
;; slot's occupant in Modifier.animateFloatingActionButton driven by
;; the body's own scroll signal, so the FAB scales away as the list
;; leaves its start and returns with it -- the derived form, computed
;; on the device exactly as upstream computes it.  All five samples
;; build.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-floating-action-buttons--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonSamples.kt"
  "Upstream FloatingActionButtonsExampleSourceUrl.")

(defun jetpacs-m3-floating-action-buttons--fab (size corner icon-size)
  "A composed FAB: a SIZE-dp CORNER-cornered container over an ICON-SIZE icon.
The container is a `surface' at `primary_container' with 6dp of
`:shadow-elevation' (FabPrimaryContainerTokens' ContainerColor and its
Level3 ContainerElevation), and its child is the one thing every upstream
FAB sample holds: Icon(Icons.Filled.Add, \"Localized description\").  The
tap lives on the `box' because `surface' has no on_tap member; Surface
propagates its min constraints, so the box fills the container and the
ripple clips to the corner."
  (jetpacs-with-attrs
   (jetpacs-surface
    (jetpacs-box (jetpacs-icon "add" :size icon-size
                               :color "on_primary_container"
                               :content-description "Localized description")
                 :alignment "center"
                 :on-tap (jetpacs-m3-demo "Localized description"))
    :color "primary_container" :shadow-elevation 6)
   :width size :height size :corner corner))

(defun jetpacs-m3-floating-action-buttons--default ()
  "Upstream FloatingActionButtonSample, as this screen\\='s FAB.
FloatingActionButton(onClick) wrapping one child,
Icon(Icons.Filled.Add, \"Localized description\").  The baseline container
is FabBaselineTokens: 56dp square, CornerLarge (16dp), a 24dp icon."
  (jetpacs-m3-floating-action-buttons--fab 56 16 24))

(defun jetpacs-m3-floating-action-buttons--small ()
  "Upstream SmallFloatingActionButtonSample, as this screen\\='s FAB.
SmallFloatingActionButton(onClick) over Icon(Icons.Filled.Add,
contentDescription = \"Localized description\").  FabSmallTokens: 40dp
square, CornerMedium (12dp), and the baseline 24dp icon -- the sample
passes no Modifier.size, because small shares the default icon size."
  (jetpacs-m3-floating-action-buttons--fab 40 12 24))

(defun jetpacs-m3-floating-action-buttons--medium ()
  "Upstream MediumFloatingActionButtonSample, as this screen\\='s FAB.
MediumFloatingActionButton(onClick) over an Icon sized
FloatingActionButtonDefaults.MediumIconSize.  FabMediumTokens: 80dp
square and a 28dp icon, with FloatingActionButtonDefaults.mediumShape
(ShapeDefaults.LargeIncreased, 20dp)."
  (jetpacs-m3-floating-action-buttons--fab 80 20 28))

(defun jetpacs-m3-floating-action-buttons--large ()
  "Upstream LargeFloatingActionButtonSample, as this screen\\='s FAB.
LargeFloatingActionButton(onClick) over an Icon sized
FloatingActionButtonDefaults.LargeIconSize.  FabLargeTokens: 96dp square
and CornerExtraLarge (28dp); the icon is 36dp, which is the constant
LargeIconSize, not FabLargeTokens.IconSize -- upstream overrides its own
token there."
  (jetpacs-m3-floating-action-buttons--fab 96 28 36))

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
    :slots (list :fab #'jetpacs-m3-floating-action-buttons--large))
   (jetpacs-m3-example
    "AnimatedFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :expressive t
    ;; :fab-hide-on-scroll IS Modifier.animateFloatingActionButton on the
    ;; slot's occupant, driven by the body's own scroll signal — the FAB
    ;; scales away as the list leaves its start and returns with it, the
    ;; derived form upstream also computes on the device.
    :build (lambda ()
             (apply #'jetpacs-column
                    (append
                     (cl-loop for i from 0 below 100
                              collect (jetpacs-with-attrs
                                       (jetpacs-text (format "Item %d" i))
                                       :pad (list :horizontal 16)))
                     (list :spacing 8 :fill t))))
    :slots (list :fab #'jetpacs-m3-floating-action-buttons--medium)
    :scaffold (list :fab-hide-on-scroll t))
   (jetpacs-m3-example
    "MediumFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :expressive t
    :slots (list :fab #'jetpacs-m3-floating-action-buttons--medium))
   (jetpacs-m3-example
    "SmallFloatingActionButtonSample"
    "Floating action button examples"
    :source jetpacs-m3-floating-action-buttons--source
    :slots (list :fab #'jetpacs-m3-floating-action-buttons--small))
   ))

(provide 'jetpacs-m3-floating-action-buttons)
;;; jetpacs-m3-floating-action-buttons.el ends here
