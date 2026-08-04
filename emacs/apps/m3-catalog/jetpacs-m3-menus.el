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
;; MultiAutocomplete — the last one out — rides SPEC 14.6.1 now: the
;; editable dropdown authored with `report_caret' reports value + caret
;; (caret-only moves included), Emacs computes the comma-separated token
;; around the caret and re-authors the OPTIONS filtered for it, and a
;; pick arrives as a unary fn mutation that splices the completed token
;; and re-authors the value.  The component is complete.

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
         :checked (jetpacs-bool (jetpacs-m3-flag flag))
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

(defvar jetpacs-m3-menus--auto-authored ""
  "The :value Emacs authors for the completion field; changes on PICK only.
Re-authoring it per keystroke would bump the value epoch and fight the
keyboard — the live draft stays device-held and arrives as reports.")

(defvar jetpacs-m3-menus--auto-text ""
  "The live field text, from SPEC 14.6.1 reports.")

(defvar jetpacs-m3-menus--auto-caret 0
  "The live caret index, from SPEC 14.6.1 reports.")

(defvar jetpacs-m3-menus--auto-timer nil
  "Debounce for the re-push while typing.")

(defun jetpacs-m3-menus--auto-token ()
  "The comma-separated token surrounding the caret: (START END . TEXT).
Upstream\='s arithmetic exactly: the span between the commas around the
caret, trimmed."
  (let* ((text jetpacs-m3-menus--auto-text)
         (caret (min jetpacs-m3-menus--auto-caret (length text)))
         (start (if-let* ((comma (cl-position ?, text :end caret :from-end t)))
                    (1+ comma) 0))
         (end (or (cl-position ?, text :start caret) (length text))))
    (cons start (cons end (string-trim (substring text start end))))))

(defun jetpacs-m3-menus--auto-options ()
  "The dessert options filtered by the caret token, upstream\='s filter."
  (let ((token (cddr (jetpacs-m3-menus--auto-token))))
    (if (string-empty-p token)
        jetpacs-m3-menus--desserts
      (cl-remove-if-not
       (lambda (option)
         (string-match-p (regexp-quote (downcase token))
                         (downcase (plist-get option :label))))
       jetpacs-m3-menus--desserts))))

;; The read side: every report (typing OR a bare caret move) lands here;
;; the debounced re-push re-authors the filtered options.
(puthash "menus-multiauto"
         (lambda (value caret)
           (when (stringp value) (setq jetpacs-m3-menus--auto-text value))
           (when (integerp caret) (setq jetpacs-m3-menus--auto-caret caret))
           (when (timerp jetpacs-m3-menus--auto-timer)
             (cancel-timer jetpacs-m3-menus--auto-timer))
           (setq jetpacs-m3-menus--auto-timer
                 (run-at-time
                  0.15 nil
                  (lambda ()
                    (setq jetpacs-m3-menus--auto-timer nil)
                    (condition-case err
                        (jetpacs-shell-push jetpacs-m3-owner)
                      (error (message "jetpacs-m3: autocomplete refresh failed: %s"
                                      (jetpacs--error-label err))))))))
         jetpacs-m3-state-watchers)

;; The pick: a UNARY fn mutation receiving the picked label — splice it
;; over the caret token and re-author the value (SPEC 14.6.1).
(puthash "menus-auto-pick"
         (lambda (picked)
           (when (stringp picked)
             (pcase-let* ((`(,start ,end . ,_) (jetpacs-m3-menus--auto-token))
                          (text jetpacs-m3-menus--auto-text)
                          (suffix (substring text end)))
               (setq jetpacs-m3-menus--auto-authored
                     (concat (substring text 0 start)
                             (when (> start 0) " ")
                             picked
                             (if (string-empty-p (string-trim suffix))
                                 ", " suffix))
                     jetpacs-m3-menus--auto-text
                     jetpacs-m3-menus--auto-authored
                     jetpacs-m3-menus--auto-caret
                     (length jetpacs-m3-menus--auto-authored)))))
         jetpacs-m3-fn-registry)

(defun jetpacs-m3-menus--multi-autocomplete ()
  "Upstream MultiAutocompleteExposedDropdownMenuSample, live on the caret.
The field reports value + caret (SPEC 14.6.1); Emacs computes the
comma-separated token around the caret and re-authors the OPTIONS
filtered for it; a pick splices the completed token and re-authors the
value.  Stated seam: the re-seeded field places its caret at the end,
where upstream restores it after the completed token — identical when
completing the last token, visible when completing a middle one."
  (jetpacs-dropdown "menus-multiauto" (jetpacs-m3-menus--auto-options)
                    :editable t :report-caret t
                    :value jetpacs-m3-menus--auto-authored
                    :label "Flavors"
                    :hint "cupcake, donut, ..."
                    :on-change (jetpacs-m3-fn-action "menus-auto-pick")))

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
    :build #'jetpacs-m3-menus--multi-autocomplete)
   ))

(provide 'jetpacs-m3-menus)
;;; jetpacs-m3-menus.el ends here
