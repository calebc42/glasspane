;;; jetpacs-m3-bottom-sheet.el --- Catalog component: Bottom Sheet -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `BottomSheets' + Examples.kt
;; `BottomSheetExamples' (3 examples), samples/BottomSheetSamples.kt.
;;
;; All three recreate on the scaffold's `sheet' slot.  With
;; `:sheet-peek-height' the sheet is the PERSISTENT BottomSheetScaffold
;; form, resting at its peek over the chrome and dragging between peek
;; and expanded; without it the sheet is MODAL, shown while the
;; authored `:sheet-state' says so.  `:sheet-state' follows the
;; tooltip-`:shown' discipline: a scrim dismissal dispatches
;; `:on-sheet-change' with \"hidden\" and holds locally until the
;; authored value changes, so a re-push cannot slam the sheet back
;; open.
;;
;; The modal sample is the catalog's first LIVE-STATE recreation: the
;; \"Show bottom sheet\" button flips a `jetpacs-m3-flag', the verb
;; re-pushes, and the function-valued `:scaffold' reads the flag at
;; build time — the real Emacs-owns-the-model round trip upstream's
;; `openBottomSheet' remember is standing in for.  The sheet's own
;; \"Hide bottom sheet\" button and the scrim dismissal both ride the
;; same flag, so every exit keeps Emacs's model true.
;;
;; Two seams stated.  Upstream's modal sheet carries a \"Skip partially
;; expanded State\" switch whose value feeds rememberModalBottomSheetState;
;; the wire's modal form derives that from `:sheet-state' (\"expanded\"
;; skips the partial stop), so the switch here reports what it would do
;; rather than rewiring the open sheet.  And the persistent sample's
;; \"Click to collapse sheet\" button animates a state the Companion
;; owns; its tap reports through the demo verb, the drag being the way
;; the sheet actually moves.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-bottom-sheet--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/BottomSheetSamples.kt"
  "Upstream BottomSheetsExampleSourceUrl.")

(defun jetpacs-m3-bottom-sheet--modal-sheet ()
  "The modal sample's sheet content: the hide button over its rows.
Upstream's LazyColumn of ListItems becomes a plain column — the sheet
already scrolls its own content."
  (jetpacs-column
   (jetpacs-with-attrs
    (jetpacs-button "Hide bottom sheet"
                    (jetpacs-m3-flag-action "modal-sheet"))
    :align_self "center")
   (jetpacs-switch "bottom-sheet-skip-partial"
                   :label "Skip partially expanded State"
                   :on-change (jetpacs-m3-demo "Skip partially expanded State"))
   (apply #'jetpacs-column
          (append
           (cl-loop for i from 0 below 12
                    collect (jetpacs-text (format "Item %d" i)))
           (list :spacing 8)))
   :spacing 12 :fill t))

(defun jetpacs-m3-bottom-sheet--modal-scaffold ()
  "The modal sample's live scaffold members, read from the flag."
  (list :sheet (jetpacs-m3-bottom-sheet--modal-sheet)
        :sheet-state (if (jetpacs-m3-flag "modal-sheet") "partial" "hidden")
        :on-sheet-change (jetpacs-m3-flag-action "modal-sheet")))

(defun jetpacs-m3-bottom-sheet--modal-body ()
  "Upstream ModalBottomSheetSample's app content: the show button.
The tap flips the \"modal-sheet\" flag, the verb re-pushes, and the
function-valued `:scaffold' reads the flag back at build time — the
Emacs-owns-the-model round trip upstream's `openBottomSheet' remember
stands in for.  Every exit rides the same flag, so Emacs's model stays
true however the sheet closes."
  (jetpacs-with-attrs
   (jetpacs-button "Show bottom sheet"
                   (jetpacs-m3-flag-action "modal-sheet"))
   :align_self "center"))

(defun jetpacs-m3-bottom-sheet--persistent-sheet ()
  "Upstream's persistent sheet: the swipe hint over its content."
  (jetpacs-column
   (jetpacs-with-attrs
    (jetpacs-box (jetpacs-text "Swipe up to expand sheet")
                 :alignment "center")
    :height 128 :fill_fraction 1.0)
   (jetpacs-with-attrs (jetpacs-text "Sheet content") :align_self "center")
   (jetpacs-with-attrs
    (jetpacs-button "Click to collapse sheet"
                    (jetpacs-m3-demo "Click to collapse sheet"))
    :align_self "center")
   :spacing 12 :fill t))

(defun jetpacs-m3-bottom-sheet--persistent-body ()
  "Upstream SimpleBottomSheetScaffoldSample's body: \"Scaffold Content\".
The centered Text behind the sheet, which is all upstream puts there —
the 128dp peek is the sample, and the peek is what selects the
persistent BottomSheetScaffold form."
  (jetpacs-text "Scaffold Content"))

(defun jetpacs-m3-bottom-sheet--nested-sheet ()
  "The nested-scroll sample's sheet: fifty rows the sheet drag hands off.
A plain column inside the sheet's own scrollable — BottomSheetScaffold
owns the fling hand-off between content and sheet."
  (apply #'jetpacs-column
         (append
          (cl-loop for i from 0 below 50
                   collect (jetpacs-with-attrs
                            (jetpacs-text (format "Item %d" i))
                            :pad (list :horizontal 16)))
          (list :spacing 8))))

(defun jetpacs-m3-bottom-sheet--nested-body ()
  "Upstream BottomSheetScaffoldNestedScrollSample's body: the content.
Upstream scrolls a hundred colored boxes here so that the fling has
somewhere to start; the hand-off between body and sheet is
BottomSheetScaffold's own, so the body only has to be behind the
sheet, and \"Scaffold Content\" is."
  (jetpacs-text "Scaffold Content"))

(jetpacs-m3-defcomponent "bottom-sheet"
  :builders (list #'jetpacs-scaffold)
  :name "Bottom Sheet"
  :description
  "Bottom sheets are surfaces containing supplementary content, anchored to the bottom of the screen."
  :guidelines "https://m3.material.io/components/bottom-sheets"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#modalbottomsheet"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ModalBottomSheet.android.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ModalBottomSheetSample"
    "Bottom sheet examples"
    :source jetpacs-m3-bottom-sheet--source
    :build #'jetpacs-m3-bottom-sheet--modal-body
    :scaffold #'jetpacs-m3-bottom-sheet--modal-scaffold)
   (jetpacs-m3-example
    "SimpleBottomSheetScaffoldSample"
    "Bottom sheet examples"
    :source jetpacs-m3-bottom-sheet--source
    :build #'jetpacs-m3-bottom-sheet--persistent-body
    ;; sheetPeekHeight = 128.dp, verbatim; the peek selects the
    ;; persistent BottomSheetScaffold form.
    :scaffold (list :sheet (jetpacs-m3-bottom-sheet--persistent-sheet)
                    :sheet-peek-height 128
                    :on-sheet-change (jetpacs-m3-demo "Sheet moved")))
   (jetpacs-m3-example
    "BottomSheetScaffoldNestedScrollSample"
    "Bottom sheet examples"
    :source jetpacs-m3-bottom-sheet--source
    :build #'jetpacs-m3-bottom-sheet--nested-body
    :scaffold (list :sheet (jetpacs-m3-bottom-sheet--nested-sheet)
                    :sheet-peek-height 128
                    :on-sheet-change (jetpacs-m3-demo "Sheet moved")))
   ))

(provide 'jetpacs-m3-bottom-sheet)
;;; jetpacs-m3-bottom-sheet.el ends here
