;;; jetpacs-m3-menus.el --- Catalog component: Menus -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Menus' + Examples.kt
;; `MenusExamples' (6 examples), samples/MenuSamples.kt and
;; samples/ExposedDropdownMenuSamples.kt.
;;
;; The `menu' node is the whole of DropdownMenu on the wire: an anchor
;; icon, MenuItems {label, on_tap, icon, enabled, supporting_text,
;; trailing_icon, checked, checked_icon} — flat under `items' or
;; sectioned under `groups' — an optional `footer' node inside the
;; popup, and `initial_scroll'.  Two samples are the flat form.
;; `MenuSample' is an icon button that opens a list of labelled,
;; leading-icon rows.  `MenuWithScrollStateSample' is thirty such rows
;; opened at their end, which is the whole visible result of the scroll
;; state it hoists.  `GroupedMenuSample' is the grouped form live on
;; sample flags: checked is authored presentation state, so each toggle
;; round-trips through Emacs, and the footer button row appears only
;; while the last item is checked — see the builder's own docstring for
;; the one icon seam.
;;
;; The `dropdown' node — the 45th type — is ExposedDropdownMenu on the
;; wire: the popup anchored to a FIELD, which this `menu' node (popup
;; off its own icon) could never compose.  The plain sample and the
;; editable sample recreate on it.  Two seams stated on the editable
;; one: the Companion filters by label CONTAINMENT where upstream
;; subsequence-matches, and the matched letters are not underlined —
;; option labels are plain strings, not spans.
;;
;; One remains out.  MultiAutocomplete completes the comma-separated
;; token AROUND THE CARET, and no wire message reports a text_input's
;; caret back to Emacs — the write-side `selection' member seeds it,
;; but the read side is the missing half.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-menus--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/MenuSamples.kt"
  "Upstream MenusExampleSourceUrl.")

(defconst jetpacs-m3-menus--desserts
  (list (jetpacs-enum-option "Android" "android")
        (jetpacs-enum-option "Base" "base")
        (jetpacs-enum-option "Cupcake" "cupcake")
        (jetpacs-enum-option "Donut" "donut")
        (jetpacs-enum-option "Eclair" "eclair"))
  "Upstream SampleData.take(5): the first five dessert releases.")

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

(defun jetpacs-m3-menus--grouped-item (flag label &rest opts)
  "A checkable MenuItem bound to sample FLAG: checked reads it, tap flips it."
  (apply #'jetpacs-menu-item label (jetpacs-m3-flag-action flag)
         :checked (if (jetpacs-m3-flag flag) t :json-false)
         opts))

(defun jetpacs-m3-menus--grouped ()
  "Upstream GroupedMenuSample: two labeled groups of checkable items over
dividers, and a footer button row that exists only while the last item
is checked.  Every checked flip is a REAL round trip: the tap flips a
sample flag in Emacs and the next snapshot re-authors checked and the
conditional footer — exactly the authored-presentation-state contract.
Seam: upstream swaps outlined icons for their Filled variants when
checked; the icon vocabulary has one spelling per name, so Home takes
the literal upstream Filled.Check via :checked-icon and the rest keep
their icon."
  (jetpacs-menu
   nil
   :groups
   (list
    (jetpacs-menu-group
     "Modification"
     (list
      (jetpacs-m3-menus--grouped-item
       "menus-grouped-edit" "Edit"
       :icon "edit" :checked-icon "edit" :supporting-text "Edit mode")
      (jetpacs-m3-menus--grouped-item
       "menus-grouped-settings" "Settings"
       :icon "settings" :checked-icon "settings")))
    (jetpacs-menu-group
     "Navigation"
     (list
      (jetpacs-m3-menus--grouped-item
       "menus-grouped-home" "Home"
       :checked-icon "check" :trailing-icon "home")
      (jetpacs-m3-menus--grouped-item
       "menus-grouped-more" "More Options"
       :icon "info" :checked-icon "info" :trailing-icon "more_vert"
       :supporting-text "Opens menu"))))
   :footer
   (when (jetpacs-m3-flag "menus-grouped-more")
     (jetpacs-row
      (jetpacs-icon-button "thumb_up" (jetpacs-m3-demo "Thumbs up")
                           :variant "filled")
      (jetpacs-icon-button "thumb_down" (jetpacs-m3-demo "Thumbs down")
                           :variant "filled")
      (jetpacs-icon-button "tag_faces" (jetpacs-m3-demo "Emotes")
                           :variant "filled")
      :spacing 8))))

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
    :build #'jetpacs-m3-menus--grouped)
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
    :build (lambda ()
             ;; Read-only field seeded with options[0]; the popup hangs off
             ;; the field, which is the node's whole reason to exist.
             (jetpacs-dropdown "menus-exposed" jetpacs-m3-menus--desserts
                               :value "android"
                               :label "Label"
                               :on-change (jetpacs-m3-demo "Picked"))))
   (jetpacs-m3-example
    "EditableExposedDropdownMenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :build (lambda ()
             ;; The TEXT is the value and the popup filters as you type —
             ;; by containment, the Commentary's stated seam.
             (jetpacs-dropdown "menus-editable" jetpacs-m3-menus--desserts
                               :editable t
                               :label "Label"
                               :on-change (jetpacs-m3-demo "Picked"))))
   (jetpacs-m3-example
    "MultiAutocompleteExposedDropdownMenuSample"
    "Menus examples"
    :source jetpacs-m3-menus--source
    :unsupported
    "The dropdown node carries the anchored popup now, but this sample completes the comma-separated token AROUND THE CARET, and no wire message reports a text_input caret back to Emacs: the selection member seeds the initial TextRange and nothing reads one back, so the token arithmetic this sample exists for has no input.")
   ))

(provide 'jetpacs-m3-menus)
;;; jetpacs-m3-menus.el ends here
