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
;; The sample recreates on the `fab_menu' node -- the 50th type, which
;; exists because of this module -- placed in this Example screen's own
;; `:fab' slot (a FAB is screen chrome; see `jetpacs-m3-slot-keys').
;; The node IS the pair of composables: the toggle FAB morphs Add to
;; Close across its own checked progress, the six item pills unfold
;; above it, an item tap collapses the menu and dispatches, and the
;; expansion is Companion-local presentation -- the same split as
;; search_bar, since a menu that snapped shut on every re-push would be
;; unusable.
;;
;; One seam stated: upstream also scales the whole FAB away as the list
;; scrolls (animateFloatingActionButton over the LazyColumn's
;; firstVisibleItemIndex).  That hide-on-scroll half has no member yet
;; -- it is the same gap AnimatedFloatingActionButtonSample names on
;; the Floating action buttons page -- so this FAB stays put while the
;; body scrolls under it.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-fab-menu--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingActionButtonMenuSamples.kt"
  "Upstream FloatingActionButtonMenuExampleSourceUrl.")

(defun jetpacs-m3-fab-menu--fab ()
  "The sample's FAB menu: six mail actions above the Add/Close toggle."
  (jetpacs-fab-menu
   (list (jetpacs-fab-menu-item "Reply" "message" (jetpacs-m3-demo "Reply"))
         (jetpacs-fab-menu-item "Reply all" "people"
                                (jetpacs-m3-demo "Reply all"))
         (jetpacs-fab-menu-item "Forward" "contacts"
                                (jetpacs-m3-demo "Forward"))
         (jetpacs-fab-menu-item "Snooze" "snooze" (jetpacs-m3-demo "Snooze"))
         (jetpacs-fab-menu-item "Archive" "archive"
                                (jetpacs-m3-demo "Archive"))
         (jetpacs-fab-menu-item "Label" "label" (jetpacs-m3-demo "Label")))))

(defun jetpacs-m3-fab-menu--content ()
  "The list the menu floats over: upstream's \"List item - N\" rows."
  (apply #'jetpacs-lazy-column
         (append
          (cl-loop for i from 0 below 50
                   collect (jetpacs-with-attrs
                            (jetpacs-text (format "List item - %d" i))
                            :key (format "fab-menu-item-%d" i)
                            :pad (list :horizontal 16)))
          (list :spacing 8 :content-padding 8))))

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
    :build #'jetpacs-m3-fab-menu--content
    :slots (list :fab #'jetpacs-m3-fab-menu--fab))
   ))

(provide 'jetpacs-m3-fab-menu)
;;; jetpacs-m3-fab-menu.el ends here
