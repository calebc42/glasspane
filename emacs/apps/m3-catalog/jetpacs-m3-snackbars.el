;;; jetpacs-m3-snackbars.el --- Catalog component: Snackbars -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Snackbars' + Examples.kt
;; `SnackbarsExamples' (5 examples), samples/ScaffoldSamples.kt.
;;
;; All five are the same Scaffold: a SnackbarHost, an extended FAB
;; reading "Show snackbar", and one line of body text.  A snackbar is
;; screen chrome -- the wire spells it `scaffold.snackbar' (SPEC 17.6,
;; and the Snackbar/SnackbarHost rows of M3-COMPONENT-LOOKUP) -- and a
;; Node tree cannot nest a scaffold, so the FAB claims THIS Example
;; screen's own fab slot.
;;
;; The snackbar itself is not authored into the tree: the FAB's tap
;; descriptor reaches Emacs and `jetpacs-m3-demo' hands the message to
;; `jetpacs-shell-notify', which queues it, latest wins.
;;
;; What arrives on device is a TOAST, not the scaffold snackbar this
;; module first claimed.  `jetpacs-shell-notify' injects the queued
;; message as `scaffold.snackbar' only when the pushed spec's `:t' IS
;; "scaffold"; this app's root is a `multi_view' (`jetpacs-chrome'
;; stacks screens as views), so the message takes the documented
;; fallback and is toasted instead.  ScaffoldWithSimpleSnackbar
;; therefore shows its message, in the wrong container -- honest
;; feedback, but not the SnackbarHost the sample exists to show.  The
;; audit tracks the event-driven raise as G-76.
;;
;; The other four are that sample plus one twist, and every twist is a
;; member the wire does not have.  `scaffold.snackbar' is ONE STRING,
;; not a node: it carries no duration and no dismiss affordance, it
;; reports no SnackbarResult back, and it cannot be given a maxLines
;; clamp or a border, because the SnackbarHost content lambda -- where
;; upstream draws all three of those -- has no form on the wire at all.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-snackbars--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ScaffoldSamples.kt"
  "Upstream SnackbarsExampleSourceUrl.")

(defconst jetpacs-m3-snackbars--host-note
  "The scaffold snackbar member is one message string and there is no snackbar node to author, so the SnackbarHost content lambda this sample replaces -- the only place a bordered container, a colored TextButton action or a per-message SnackbarVisuals can be drawn -- has no form on the wire."
  "Why every custom-SnackbarHost sample is unsupported.")

(defun jetpacs-m3-snackbars--simple-fab ()
  "Upstream ScaffoldWithSimpleSnackbar's FAB, as this screen's FAB.
The text-only ExtendedFloatingActionButton reading \"Show snackbar\".
Its tap reaches Emacs, which queues the message -- and on this surface
presents it as a TOAST, not the scaffold snackbar (see the Commentary:
the catalog root is a `multi_view', so `jetpacs-shell-notify' takes its
non-scaffold fallback).  The SnackbarHost the sample exists to show is
therefore still ahead of us.  The click count upstream keeps in
`remember' has no wire state to live in either, so the message stays
\"Snackbar # 1\"."
  (jetpacs-button "Show snackbar" (jetpacs-m3-demo "Snackbar # 1")
                  :variant "filled"))

(defun jetpacs-m3-snackbars--simple-body ()
  "Upstream ScaffoldWithSimpleSnackbar's content: \"Body content\".
The Example screen already centers its body, which is what the
fillMaxSize/wrapContentSize modifier pair does upstream."
  (jetpacs-text "Body content"))

(jetpacs-m3-defcomponent "snackbars"
  :name "Snackbars"
  :description
  "Snackbars provide brief messages about app processes at the bottom of the screen."
  :guidelines "https://m3.material.io/components/snackbars"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#snackbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Snackbar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ScaffoldWithSimpleSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--simple-fab))
   (jetpacs-m3-example
    "ScaffoldWithIndefiniteSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :unsupported
    "The scaffold snackbar member is a bare message string: it has no duration member for SnackbarDuration.Indefinite and no with_dismiss_action member for the trailing dismiss button, so the snackbar that stays until the user clears it -- the whole delta from ScaffoldWithSimpleSnackbar -- cannot be asked for from Emacs.")
   (jetpacs-m3-example
    "ScaffoldWithCustomSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :unsupported jetpacs-m3-snackbars--host-note)
   (jetpacs-m3-example
    "ScaffoldWithCoroutinesSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :unsupported
    "This sample exists to route a snackbar through a business-logic layer and then branch on its SnackbarResult, and the wire reports no such result: nothing signals SnackbarResult.Dismissed, and the scaffold snackbar_action that would carry \"Action on 1\" is a static member of the pushed tree, never something the tap that raises a snackbar can attach to it.")
   (jetpacs-m3-example
    "ScaffoldWithMultilineSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :unsupported
    "Clamping a long message to the two lines the Material spec recommends means replacing the SnackbarHost content, and the scaffold snackbar member is a plain string with no max_lines or overflow member of its own.")
   ))

(provide 'jetpacs-m3-snackbars)
;;; jetpacs-m3-snackbars.el ends here
