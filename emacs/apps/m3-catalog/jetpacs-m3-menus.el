;;; jetpacs-m3-menus.el --- Catalog component: Menus -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Menus' + Examples.kt
;; `MenusExamples' (6 examples), samples/MenuSamples.kt and
;; samples/ExposedDropdownMenuSamples.kt.
;;
;; The `menu' node is the whole of DropdownMenu on the wire: an anchor
;; icon, a flat list of MenuItem {label, on_tap, icon, enabled}, and
;; `initial_scroll'.  Two samples are exactly that.  `MenuSample' is an
;; icon button that opens a list of labelled, leading-icon rows.
;; `MenuWithScrollStateSample' is thirty such rows opened at their end,
;; which is the whole visible result of the scroll state it hoists.
;;
;; The other four demonstrate something the map has no room for.  One
;; wants more of DropdownMenu than the item record holds: GROUPS with
;; labels and shapes, per-item SUPPORTING TEXT, a per-item CHECKED
;; state with its checked leading icon, and TRAILING content.  Three
;; are ExposedDropdownMenu, which M3-COMPONENT-LOOKUP lists as
;; available-but-unwrapped: their whole subject is a menu ANCHORED TO A
;; TEXT FIELD, filtering and completing what is typed, and neither the
;; anchoring nor the caret arithmetic has a wire member.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-menus--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/MenuSamples.kt"
  "Upstream MenusExampleSourceUrl.")

(defconst jetpacs-m3-menus--exposed-note
  "There is no exposed_dropdown_menu node: the menu node hangs its popup off its own anchor icon, and the wire has no way to anchor one to a text_input, which is the entire subject of this sample."
  "Why every ExposedDropdownMenu sample is unsupported.")

(defun jetpacs-m3-menus--basic ()
  "Upstream MenuSample: a MoreVert IconButton opening a DropdownMenu.
The three items keep their upstream labels and their Outlined leading
icons.  What the item record cannot carry rides along as loss: the
HorizontalDivider above \"Send Feedback\" and that item's \"F11\"
trailing shortcut text.  The a11y TooltipBox around the anchor is the
`icon' member's own job here -- the renderer builds the IconButton."
  (jetpacs-menu
   (list (jetpacs-menu-item "Edit" (jetpacs-m3-demo "Edit")
                            :icon "edit")
         (jetpacs-menu-item "Settings" (jetpacs-m3-demo "Settings")
                            :icon "settings")
         (jetpacs-menu-item "Send Feedback" (jetpacs-m3-demo "Send Feedback")
                            :icon "email"))
   :icon "more_vert"))

(defun jetpacs-m3-menus--with-scroll-state ()
  "Upstream MenuWithScrollStateSample: thirty items, opened at the end.
Upstream hoists a `rememberScrollState' into DropdownMenu and, in a
LaunchedEffect on expand, scrolls it to `maxValue' -- \"Scroll to show
the bottom menu items.\"  The `menu' node holds no scroll state, but
`:initial-scroll \"end\"' is that effect's whole visible result: the
popup opens on \"Item 30\".  What is lost is the handle, not the
demonstration -- the position is chosen once, at open, and afterwards
the wire can neither read it nor drive it."
  (jetpacs-menu
   (mapcar (lambda (n)
             (let ((label (format "Item %d" n)))
               (jetpacs-menu-item label (jetpacs-m3-demo label) :icon "edit")))
           (number-sequence 1 30))
   :icon "more_vert"
   :initial-scroll "end"))

(jetpacs-m3-defcomponent "menus"
  :name "Menus"
  :description
  "Menus display a list of choices on temporary surfaces."
  :guidelines "https://m3.material.io/components/menus"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#dropdownmenu"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Menu.kt"
  :examples
  (list
   (jetpacs-m3-example
    "MenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :build #'jetpacs-m3-menus--basic)
   (jetpacs-m3-example
    "GroupedMenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :expressive t
    :unsupported
    "A MenuItem on the wire is {label, on_tap, icon, enabled} and the menu node has a flat items array: DropdownMenuGroup with its MenuDefaults.groupShape, the per-item supportingText, the checked state with its checkedLeadingIcon, and the trailing icons this sample toggles have no members to be sent in.")
   (jetpacs-m3-example
    "MenuWithScrollStateSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :build #'jetpacs-m3-menus--with-scroll-state)
   (jetpacs-m3-example
    "ExposedDropdownMenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :expressive t
    :unsupported jetpacs-m3-menus--exposed-note)
   (jetpacs-m3-example
    "EditableExposedDropdownMenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :unsupported
    (concat jetpacs-m3-menus--exposed-note
            "  The menu is also rebuilt on every keystroke from a subsequence match, with the matched letters underlined, and menu items carry a plain label string, not spans."))
   (jetpacs-m3-example
    "MultiAutocompleteExposedDropdownMenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :unsupported
    (concat jetpacs-m3-menus--exposed-note
            "  It also completes the comma-separated token around the caret, and the text_input node has no selection or cursor member for a TextRange to be read from or placed back into."))
   ))

(provide 'jetpacs-m3-menus)
;;; jetpacs-m3-menus.el ends here
