;;; jetpacs-m3-bottom-sheet.el --- Catalog component: Bottom Sheet -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `BottomSheets' + Examples.kt
;; `BottomSheetExamples' (3 examples), samples/BottomSheetSamples.kt.
;;
;; All three samples exist to demonstrate the sheet itself: a surface
;; anchored to the bottom of the window that the user drags between
;; SheetValue states (Hidden / PartiallyExpanded / Expanded), over a
;; scrim for `ModalBottomSheet' or peeking above the content for
;; `BottomSheetScaffold'.  M3-COMPONENT-LOOKUP lists both as
;; available-but-unwrapped: there is no `bottom_sheet' node type, and
;; the `scaffold' node's slots are top_bar, body, bottom_bar, fab,
;; floating_toolbar, drawer, snackbar and on_refresh -- no sheet, and no
;; sheetPeekHeight to go with one.  The Example screen's scaffold slots
;; (`jetpacs-m3-slot-keys') cannot stand in either, because none of them
;; is a sheet; a `collapsible' would draw something that expands, but
;; inline in the body, which is not what any of these samples is about.
;; So all three are unsupported, and the two BottomSheetScaffold ones
;; name the missing scaffold member rather than the missing node.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-bottom-sheet--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/BottomSheetSamples.kt"
  "Upstream BottomSheetExampleSourceUrl.")

(defconst jetpacs-m3-bottom-sheet--scaffold-note
  "The scaffold node's slots are top_bar, body, bottom_bar, fab, floating_toolbar, drawer, snackbar and on_refresh: it has no sheet slot and no sheetPeekHeight, so the peeking, swipe-to-expand sheet of BottomSheetScaffold has nothing on the wire to carry it."
  "Why every BottomSheetScaffold sample is unsupported.")

(jetpacs-m3-defcomponent "bottom-sheet"
  :name "Bottom Sheet"
  :description
  "Bottom sheets are surfaces containing supplementary content, anchored to the bottom of the screen."
  :guidelines "https://m3.material.io/components/bottom-sheets"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#bottomsheet"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ModalBottomSheet.android.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ModalBottomSheetSample"
    "Bottom Sheet examples"
    :source jetpacs-m3-bottom-sheet--source
    :unsupported
    "There is no bottom-sheet node: ModalBottomSheet is available-but-unwrapped, so the scrimmed sheet this sample raises over the app content, its SheetState and its skipPartiallyExpanded flag cannot be requested from Emacs.")
   (jetpacs-m3-example
    "SimpleBottomSheetScaffoldSample"
    "Bottom Sheet examples"
    :source jetpacs-m3-bottom-sheet--source
    :unsupported jetpacs-m3-bottom-sheet--scaffold-note)
   (jetpacs-m3-example
    "BottomSheetScaffoldNestedScrollSample"
    "Bottom Sheet examples"
    :source jetpacs-m3-bottom-sheet--source
    :unsupported
    "Neither half is on the wire: the scaffold node has no sheet slot for BottomSheetScaffold, and there is no nested-scroll member to hand a fling from the sheet's list to the sheet's own drag or to a pinned top bar.")
   ))

(provide 'jetpacs-m3-bottom-sheet)
;;; jetpacs-m3-bottom-sheet.el ends here
