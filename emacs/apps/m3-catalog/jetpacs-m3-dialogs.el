;;; jetpacs-m3-dialogs.el --- Catalog component: Dialogs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Dialogs' + Examples.kt
;; `DialogExamples' (3 examples), samples/AlertDialogSamples.kt.
;;
;; All three samples are one shape: an "Open dialog" Button, and a modal
;; raised over the whole app while `openDialog' is true.  The wire has no
;; node for that.  `jetpacs-app-node-types' advertises 39 node types and
;; none of them is a dialog, and M3-COMPONENT-LOOKUP.org lists
;; AlertDialog as wrapped with wire type `N/A (dialog chrome)' behind
;; `ebp-client-dialog-show' -- a SPEC 18.1 `dialog.show' REQUEST that
;; Emacs sends with its own SurfaceSpec, concluded by the `dialog.submit'
;; and `dialog.dismiss' builtins.  A sample builder returns ONE node for
;; the screen body; it cannot make a request, and `jetpacs-m3-slot-keys'
;; (fab, bottom-bar, drawer, floating-toolbar, on-refresh, snackbar) has
;; no dialog slot for it to claim either.  So this component is
;; unsupported end to end.
;;
;; The temptation to resist: `confirm' on a SPEC 14.1 action descriptor
;; IS a real M3 AlertDialog raised declaratively from the node tree --
;; ConfirmHost in MainActivity.kt draws one.  But it carries a single
;; prompt string, and the Companion fixes everything else: no title slot,
;; no icon slot, and TextButtons reading "OK" and "Cancel" rather than
;; this sample's "Confirm" and "Dismiss".  Of the four content slots
;; AlertDialogSample exists to show it can carry one, and it would draw
;; AlertDialogSample and AlertDialogWithIconSample identically, the icon
;; being the only thing that separates them upstream.  That is a
;; lookalike, not a recreation, so it is not here -- but each reason
;; names it, because a reader deserves to know how near the wire gets.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-dialogs--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/AlertDialogSamples.kt"
  "Upstream DialogExampleSourceUrl.")

(defconst jetpacs-m3-dialogs--no-node-note
  "There is no dialog node type: the app profile advertises 39 and none of them is a dialog, and M3-COMPONENT-LOOKUP records AlertDialog as dialog chrome behind ebp-client-dialog-show rather than as a wire type."
  "The sentence every AlertDialog sample fails on first.")

(defun jetpacs-m3-dialogs--note (tail)
  "The Dialogs unsupported reason: the shared first sentence, then TAIL."
  (concat jetpacs-m3-dialogs--no-node-note " " tail))

(jetpacs-m3-defcomponent "dialogs"
  :name "Dialogs"
  :description
  "Dialogs provide important prompts in a user flow. They can require an action, communicate information, or help users accomplish a task."
  :guidelines "https://m3.material.io/components/dialogs"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#alertdialog"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/AlertDialog.kt"
  :examples
  (list
   (jetpacs-m3-example
    "AlertDialogSample"
    "Dialog examples"
    :source jetpacs-m3-dialogs--source
    :unsupported
    (jetpacs-m3-dialogs--note
     "The nearest thing a node tree can raise is confirm on a SPEC 14.1 action descriptor, which is one prompt string the Companion draws with fixed OK and Cancel buttons, so of the four slots this sample fills only text survives: the title \"Title\" and the \"Confirm\" and \"Dismiss\" button labels have no member to carry them."))
   (jetpacs-m3-example
    "AlertDialogWithIconSample"
    "Dialog examples"
    :source jetpacs-m3-dialogs--source
    :unsupported
    (jetpacs-m3-dialogs--note
     "This sample differs from AlertDialogSample by exactly one thing, the AlertDialog icon slot holding Icons.Filled.Favorite, and the SPEC 14.1 confirm prompt that stands nearest to a dialog is a bare string with no icon member and no title member at all."))
   (jetpacs-m3-example
    "BasicAlertDialogSample"
    "Dialog examples"
    :source jetpacs-m3-dialogs--source
    :unsupported
    "BasicAlertDialog is the unstyled dialog window whose whole content the caller supplies, and on the wire that is the SPEC 18.1 dialog.show request Emacs sends with its own SurfaceSpec, not a node type: a sample builder returns one node for the screen body, and jetpacs-m3-slot-keys has no dialog slot to claim, so nothing in the node vocabulary can put this Surface, its tonal elevation and its trailing Confirm TextButton on screen.")
   ))

(provide 'jetpacs-m3-dialogs)
;;; jetpacs-m3-dialogs.el ends here
