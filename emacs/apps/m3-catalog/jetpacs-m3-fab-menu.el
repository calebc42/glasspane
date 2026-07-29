;;; jetpacs-m3-fab-menu.el --- Catalog component: FAB Menu -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `FloatingActionButtonMenu' + Examples.kt
;; `FloatingActionButtonMenuExamples' (1 example),
;; samples/FloatingActionButtonMenuSamples.kt.
;;
;; The one sample IS the FloatingActionButtonMenu composable: a
;; ToggleFloatingActionButton whose icon animates from Add to Close as
;; `checkedProgress' crosses 0.5 and, while it is checked, six
;; FloatingActionButtonMenuItem pills -- Reply, Reply all, Forward,
;; Snooze, Archive, Label -- unfolding above it, over a 100-item
;; LazyColumn whose scroll position drives
;; `Modifier.animateFloatingActionButton' to scale the whole thing away.
;;
;; A FAB is screen chrome and this Example screen's `:fab' slot is right
;; there (see `jetpacs-m3-slot-keys') -- it is how
;; FloatingActionButtonSample and the two default-size Extended FAB
;; samples are recreated.  But that slot holds ONE node and has no
;; expanded member, and the wire has no fab-menu node type at all:
;; M3-COMPONENT-LOOKUP wraps FloatingActionButton as `scaffold.fab' and
;; DropdownMenu as `menu', and neither is this.  A `menu' in the fab
;; slot would be a popup hung off an icon button -- a different
;; composable wearing this sample's actions -- and a `column' of six
;; buttons would be the menu permanently expanded, with no toggle left
;; to demonstrate.  Both are lookalikes, so the example is unsupported
;; and says which members are missing.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-fab-menu--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonMenuSamples.kt"
  "Upstream FloatingActionButtonMenuExampleSourceUrl.")

(jetpacs-m3-defcomponent "fab-menu"
  :name "FAB Menu"
  :description
  "The FAB Menu displays additional key actions on click of a FAB."
  :guidelines "https://m3.material.io/components/fab-menu"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#floatingactionbuttonmenu"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/FloatingActionButtonMenu.kt"
  :examples
  (list
   (jetpacs-m3-example
    "FloatingActionButtonMenuSample"
    "FAB Menu examples"
    :source jetpacs-m3-fab-menu--source
    :expressive t
    :unsupported
    "There is no fab-menu node type and no toggle-FAB node: the scaffold fab slot takes ONE node with no expanded or checked member, so the wire cannot ask for six FloatingActionButtonMenuItem pills unfolding above a ToggleFloatingActionButton whose icon animates from Add to Close across checkedProgress.  The menu node is a DropdownMenu popup anchored to its own icon, which is a different composable, and animateFloatingActionButton hides the FAB from the LazyColumn's firstVisibleItemIndex, a scroll position that never reaches Emacs.")
   ))

(provide 'jetpacs-m3-fab-menu)
;;; jetpacs-m3-fab-menu.el ends here
