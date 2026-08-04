;;; jetpacs-m3-dialogs.el --- Catalog component: Dialogs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Dialogs' + Examples.kt
;; `DialogExamples' (3 examples), samples/AlertDialogSamples.kt.
;;
;; All three recreate, by two different doors.
;;
;; The two AlertDialog samples ride the §14.1 `confirm' OBJECT: their
;; whole upstream flow is a Button whose tap raises an AlertDialog with
;; a title, supporting text, an optional icon and Confirm/Dismiss
;; actions — and that is precisely what a confirm-gated descriptor IS.
;; The Companion parks the dispatch behind the authored face; Confirm
;; releases it (the demo verb reports), Dismiss and the scrim drop it.
;; No lookalike is drawn: the dialog is the ConfirmHost's own real
;; AlertDialog.
;;
;; BasicAlertDialogSample is the OTHER door: its subject is the
;; CALLER-supplied container — Surface(shape, tonalElevation) — inside
;; the bare dialog window, so it must be a §18.1 dialog spec, and
;; `surface' joined the dialog profile for exactly this.  The spec is
;; registered in `jetpacs-m3-dialog-registry' and the button's verb
;; raises it through `ebp-client-dialog-show' outside the dispatch
;; extent; its Confirm is `jetpacs-dialog-dismiss', as upstream's
;; onClick is onDismissRequest.
;;
;; One seam stated: upstream opens each dialog from `openDialog'
;; remember initialized TRUE, so the dialog is up on entry.  Here every
;; dialog opens from its button — a modal cannot be authored open by a
;; snapshot, which is §18.1's own design (dialogs are REQUESTS, not
;; tree state).

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-dialogs--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/AlertDialogSamples.kt"
  "Upstream DialogsExampleSourceUrl.")

(defconst jetpacs-m3-dialogs--icon-text
  "This area typically contains the supporting text which presents the details regarding the Dialog's purpose."
  "The supporting text the icon dialog and the basic dialog share.")

(defun jetpacs-m3-dialogs--alert ()
  "Upstream AlertDialogSample: the confirm-gated button.
Title \"Title\", text \"Turned on by default\", Confirm and Dismiss —
each a member of the confirm object, drawn by the ConfirmHost's real
AlertDialog."
  (jetpacs-with-attrs
   (jetpacs-button "Open dialog"
                   (jetpacs-action "m3catalog.demo"
                                   :args (list :message "Confirmed")
                                   :confirm (list :title "Title"
                                                  :text "Turned on by default"
                                                  :confirm-label "Confirm"
                                                  :dismiss-label "Dismiss")))
   :align_self "center"))

(defun jetpacs-m3-dialogs--alert-with-icon ()
  "Upstream AlertDialogWithIconSample: the same gate wearing an icon.
Icons.Filled.Favorite above a centered title — the icon member; the
wire name resolves through IconMap as every icon does."
  (jetpacs-with-attrs
   (jetpacs-button "Open dialog"
                   (jetpacs-action "m3catalog.demo"
                                   :args (list :message "Confirmed")
                                   :confirm (list :icon "favorite"
                                                  :title "Title"
                                                  :text jetpacs-m3-dialogs--icon-text
                                                  :confirm-label "Confirm"
                                                  :dismiss-label "Dismiss")))
   :align_self "center"))

(defun jetpacs-m3-dialogs--basic-spec ()
  "Upstream BasicAlertDialogSample's caller-supplied content.
A Surface (the dialog profile's one shaped, elevated container) holding
the supporting text and a Confirm that dismisses — upstream's onClick
IS onDismissRequest."
  (jetpacs-surface
   (jetpacs-with-attrs
    (jetpacs-column
     (jetpacs-text jetpacs-m3-dialogs--icon-text)
     (jetpacs-with-attrs
      (jetpacs-button "Confirm" (jetpacs-dialog-dismiss) :variant "text")
      :align_self "end")
     :spacing 24)
    :padding 16)
   :shape "rounded" :elevation 6))

(jetpacs-m3-defcomponent "dialogs"
  :name "Dialogs"
  :description
  "Dialogs provide important prompts in a user flow."
  :guidelines "https://m3.material.io/components/dialogs"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#alertdialog"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/AlertDialog.kt"
  :examples
  (list
   (jetpacs-m3-example
    "AlertDialogSample"
    "Dialog examples"
    :source jetpacs-m3-dialogs--source
    :build #'jetpacs-m3-dialogs--alert)
   (jetpacs-m3-example
    "AlertDialogWithIconSample"
    "Dialog examples"
    :source jetpacs-m3-dialogs--source
    :build #'jetpacs-m3-dialogs--alert-with-icon)
   (jetpacs-m3-example
    "BasicAlertDialogSample"
    "Dialog examples"
    :source jetpacs-m3-dialogs--source
    :build (lambda ()
             (puthash "basic" #'jetpacs-m3-dialogs--basic-spec
                      jetpacs-m3-dialog-registry)
             (jetpacs-with-attrs
              (jetpacs-button "Open dialog"
                              (jetpacs-m3-dialog-action "basic"))
              :align_self "center")))
   ))

(provide 'jetpacs-m3-dialogs)
;;; jetpacs-m3-dialogs.el ends here
