;;; jetpacs-m3-swipe-to-dismiss.el --- Catalog component: Swipe to Dismiss -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SwipeToDismiss' + Examples.kt
;; `SwipeToDismissExamples' (1 examples).
;;
;; This is one of the few M3 gestures the wire carries outright: the
;; card node has `swipe_start' and `swipe_end' members, each a swipe
;; side {label, icon?, color?, on_trigger}, and the Companion renders
;; them with the very composable the sample demonstrates -- a
;; `SwipeToDismissBox' over `rememberSwipeToDismissBoxState', with a
;; direction-dependent colored background.  So the one example
;; recreates: an outlined-card list row that is swipeable both ways,
;; green forward and red back.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-swipe-to-dismiss--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SwipeToDismissSamples.kt"
  "Upstream SwipeToDismissExampleSourceUrl.")

(defun jetpacs-m3-swipe-to-dismiss--list-items ()
  "Upstream SwipeToDismissListItems: one swipeable \"Cupcake\" row.
The sample wraps an OutlinedCard/ListItem in a SwipeToDismissBox whose
backgroundContent is Green for StartToEnd and Red for EndToStart, and
whose onDismiss hides the item on EndToStart and calls
`dismissState.reset' on StartToEnd.  The card node carries that as
:swipe-start and :swipe-end; the two colors ride as the `success' and
`error' roles, which is what Green and Red mean here.

Per SPEC §17.3 a swiped item never settles dismissed on the Companion
-- it returns to rest and the server's list decides -- so removal is
the catalog's demo verb reporting the direction, as everywhere else."
  (jetpacs-card
   (jetpacs-column
    (jetpacs-text "Cupcake")
    (jetpacs-text "Swipe me left or right!"
                  :style "caption" :color "on_surface_variant")
    :spacing 4)
   :swipe-start (jetpacs-swipe "Reset"
                               :icon "refresh"
                               :color "success"
                               :on-trigger (jetpacs-m3-demo "Reset"))
   :swipe-end (jetpacs-swipe "Dismiss"
                             :icon "close"
                             :color "error"
                             :on-trigger (jetpacs-m3-demo "Dismissed Cupcake"))))

(jetpacs-m3-defcomponent "swipe-to-dismiss"
  :name "Swipe to Dismiss"
  :description
  "Swipe to dismiss is a gesture used to dismiss items in a list."
  :guidelines "https://m3.material.io/components/material-shapes"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#shapes"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Shapes.kt"
  :additional-info "Unofficial"
  :examples
  (list
   (jetpacs-m3-example
    "SwipeToDismiss"
    "Swipe to dismiss examples"
    :source jetpacs-m3-swipe-to-dismiss--source
    :expressive t
    :build #'jetpacs-m3-swipe-to-dismiss--list-items)
   ))

(provide 'jetpacs-m3-swipe-to-dismiss)
;;; jetpacs-m3-swipe-to-dismiss.el ends here
