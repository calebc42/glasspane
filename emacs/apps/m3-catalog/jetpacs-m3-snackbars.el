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
;; That message really does arrive as `scaffold.snackbar' now, and for
;; a while it did not.  `jetpacs-shell-notify' injected the queued
;; string only when the pushed spec's `:t' was "scaffold", and a
;; `jetpacs-chrome' app is a `multi_view' whose VIEWS are the scaffolds
;; -- so no chrome app in the product ever found its own slot and every
;; snackbar in Jetpacs degraded to a toast.  The injection now targets
;; the view being shown, so ScaffoldWithSimpleSnackbar draws the
;; SnackbarHost it exists to show.
;;
;; The other four are that sample plus one twist.  Two of the twists
;; are members now: `snackbar_duration' (indefinite implies the
;; trailing dismiss X -- such a snackbar must always leave the user an
;; exit) and `snackbar_max_lines' (the visible clamp; Text semantics
;; keep the whole string for a screen reader).  Both are STATIC members
;; of the view's scaffold, so the Example screen's own `:scaffold'
;; plist carries them and the notify-injected message wears them when
;; it lands.
;;
;; The two still out of reach both need a channel, not a member: a
;; SnackbarResult reported back for the coroutines sample, and a
;; SnackbarHost content lambda -- a bordered container with a colored
;; action -- for the custom one.

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
Its tap reaches Emacs, which queues the message; the next push carries
it as the scaffold snackbar member of the view being shown, which is the
SnackbarHost this sample exists to show.  The click count upstream keeps
in `remember\=' has no wire state to live in, so the message stays
\"Snackbar # 1\"."
  (jetpacs-button "Show snackbar" (jetpacs-m3-demo "Snackbar # 1")
                  :variant "filled"))

(defun jetpacs-m3-snackbars--long-fab ()
  "The Multiline sample's FAB: its message is upstream's longMessage.
The clamp is the scaffold's `:snackbar-max-lines', not the string."
  (jetpacs-button "Show snackbar"
                  (jetpacs-m3-demo
                   (concat "very very very very very very very very very "
                           "very long message"))
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
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--simple-fab)
    ;; SnackbarDuration.Indefinite; the implied dismiss X is the user's
    ;; exit, exactly upstream's withDismissAction = true.
    :scaffold (list :snackbar-duration "indefinite"))
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
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--long-fab)
    ;; The two lines the Material spec recommends; the ellipsis is
    ;; visual only, the accessible value stays whole.
    :scaffold (list :snackbar-max-lines 2))
   ))

(provide 'jetpacs-m3-snackbars)
;;; jetpacs-m3-snackbars.el ends here
