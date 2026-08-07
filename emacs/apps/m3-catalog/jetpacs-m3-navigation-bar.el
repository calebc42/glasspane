;;; jetpacs-m3-navigation-bar.el --- Catalog component: Navigation bar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `NavigationBar' + Examples.kt
;; `NavigationBarExamples' (3 examples), samples/NavigationBarSamples.kt.
;;
;; All three samples list the SAME three destinations -- Songs, Artists
;; and Playlists, with selectedItem starting at 0 -- and differ only in
;; the bar that hosts them.  A navigation bar IS screen chrome, so each
;; claims this Example screen's own `bottom_bar' slot rather than
;; nesting a scaffold inside the body (see `jetpacs-m3-slot-keys' and
;; the README section "Samples that ARE screen chrome", which names the
;; navigation bar as a bottom bar of items).
;;
;; The slot takes an ordinary node, and a NavigationBarItem composes
;; entirely out of wrapped ones: the icon-above-label stack is a
;; `column', the equal-weight distribution is `:weight 1' inside a
;; filled `row', the active indicator is the `secondaryContainer' pill
;; that `:bg' and `:corner' put on the wire, and the icon and label
;; colors are the NavigationBarItemDefaults roles.  The one member a
;; bar node would add is the container HEIGHT -- and that is the
;; universal `height' attribute, which is exactly the difference
;; between the expressive ShortNavigationBar (64dp) and NavigationBar
;; (80dp).  So neither of those two stands in for the other; both are
;; recreated, and the horizontal-items sample recreates its
;; NavigationItemIconPosition.Start as a `row' per item and its
;; ShortNavigationBarArrangement.Centered as the bar row's `arrange'.
;;
;; Two upstream details survive only in the state the samples open in.
;; Selection never moves, because every handler here is
;; `jetpacs-m3-demo' and no component module registers actions.  And
;; Icons.Filled.Home and Icons.Outlined.Home are one `home' name on the
;; wire -- a collapse that only shows in a state these samples never
;; reach, since Favorite/FavoriteBorder and Star/StarBorder each have
;; their own name and the two unselected destinations keep their
;; outlined glyphs.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-navigation-bar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/NavigationBarSamples.kt"
  "Upstream NavigationBarExampleSourceUrl.")

(defconst jetpacs-m3-navigation-bar--items
  '(("Songs" "home" "home")
    ("Artists" "favorite" "favorite_border")
    ("Playlists" "star" "star_border"))
  "The three destinations every sample in NavigationBarSamples.kt lists.
Each entry is (LABEL SELECTED-ICON UNSELECTED-ICON): upstream `items'
against `selectedIcons' (Filled Home, Favorite, Star) and
`unselectedIcons' (Outlined Home, FavoriteBorder, StarBorder).  The
wire has one `home' name, so Home reads the same in either state.")

(defconst jetpacs-m3-navigation-bar--selected 0
  "The destination the samples open on: upstream selectedItem = 0, Songs.
Tapping selects upstream; here every handler is `jetpacs-m3-demo', so
the selection stays where the sample put it.")

(defun jetpacs-m3-navigation-bar--destinations (builder)
  "Every destination of `jetpacs-m3-navigation-bar--items', built by BUILDER.
BUILDER takes an item entry and whether it is the selected one, which
is upstream\\='s `items.forEachIndexed { index, item -> ... }' with its
`selected = selectedItem == index'."
  (let ((index -1))
    (mapcar (lambda (spec)
              (setq index (1+ index))
              (funcall builder spec
                       (= index jetpacs-m3-navigation-bar--selected)))
            jetpacs-m3-navigation-bar--items)))

(defun jetpacs-m3-navigation-bar--glyph (spec selected describe)
  "The icon of destination SPEC in its SELECTED or unselected form.
DESCRIBE non-nil gives the icon the destination label as its content
description, which NavigationBarSample passes and the two
ShortNavigationBar samples leave null.  The colors are
NavigationBarItemDefaults: `on_secondary_container' against the active
indicator, `on_surface_variant' outside it."
  (jetpacs-icon (if selected (nth 1 spec) (nth 2 spec))
                :color (if selected "on_secondary_container"
                         "on_surface_variant")
                :content-description (and describe (nth 0 spec))))

(defun jetpacs-m3-navigation-bar--label (spec selected)
  "The label of destination SPEC, colored for its SELECTED state.
NavigationBarItemDefaults gives the selected label `on_surface' and the
unselected one `on_surface_variant'; the M3 item label is labelMedium,
which is the `label' text style."
  (jetpacs-text (nth 0 spec) :style "label"
                :color (if selected "on_surface" "on_surface_variant")))

(defun jetpacs-m3-navigation-bar--item (spec selected describe)
  "Destination SPEC as a vertical item: the icon above the label.
SELECTED fills the 64x32 active indicator behind the icon; DESCRIBE is
passed to `jetpacs-m3-navigation-bar--glyph'.  The weight is
ShortNavigationBarArrangement.EqualWeight, the default of both bars."
  (jetpacs-with-attrs
   (jetpacs-box
    (jetpacs-column
     (jetpacs-with-attrs
      (jetpacs-box (jetpacs-m3-navigation-bar--glyph spec selected describe)
                   :alignment "center")
      :width 64 :height 32 :corner 16
      :bg (and selected "secondary_container"))
     (jetpacs-m3-navigation-bar--label spec selected)
     :spacing 4 :align "center")
    :alignment "center"
    :on-tap (jetpacs-m3-demo (nth 0 spec)))
   :weight 1))

(defun jetpacs-m3-navigation-bar--horizontal-item (spec selected)
  "Destination SPEC as a horizontal item: the icon beside the label.
Upstream NavigationItemIconPosition.Start.  In that position the M3
active indicator wraps icon AND label, so the padded row is what
carries the SELECTED container instead of a box around the icon alone,
and the item sizes to its content rather than taking a weight."
  (jetpacs-box
   (jetpacs-with-attrs
    (jetpacs-row (jetpacs-m3-navigation-bar--glyph spec selected nil)
                 (jetpacs-m3-navigation-bar--label spec selected)
                 :spacing 8 :align "center")
    :pad (list :horizontal 16 :vertical 8) :corner 20
    :bg (and selected "secondary_container"))
   :alignment "center"
   :on-tap (jetpacs-m3-demo (nth 0 spec))))

(defun jetpacs-m3-navigation-bar--bar (items height &rest options)
  "ITEMS as one navigation bar HEIGHT dp tall, taking row OPTIONS.
HEIGHT is the container height the bar composable owns upstream -- 64dp
for ShortNavigationBar, 80dp for NavigationBar -- which here is the
universal `height' attribute on the node the `bottom_bar' slot takes."
  (jetpacs-with-attrs
   (apply #'jetpacs-row
          (append items options (list :align "center" :fill t)))
   :height height))

(defun jetpacs-m3-navigation-bar--short ()
  "Upstream ShortNavigationBarSample, as this screen\\='s bottom bar.
Three ShortNavigationBarItems in the default EqualWeight arrangement,
Songs selected, each icon\\='s contentDescription null."
  (jetpacs-m3-navigation-bar--bar
   (jetpacs-m3-navigation-bar--destinations
    (lambda (spec selected)
      (jetpacs-m3-navigation-bar--item spec selected nil)))
   64))

(defun jetpacs-m3-navigation-bar--short-horizontal ()
  "The bar of upstream ShortNavigationBarWithHorizontalItemsSample.
ShortNavigationBarArrangement.Centered is the row `arrange', and the
items sit beside their labels rather than above them."
  (jetpacs-m3-navigation-bar--bar
   (jetpacs-m3-navigation-bar--destinations
    #'jetpacs-m3-navigation-bar--horizontal-item)
   64 :arrange "center" :spacing 4))

(defun jetpacs-m3-navigation-bar--horizontal-note ()
  "The body of upstream ShortNavigationBarWithHorizontalItemsSample.
The Column that sample builds is its note, a 32dp Spacer and the bar;
the bar has moved to the `bottom_bar' slot, which leaves the note --
verbatim, under its own 16dp padding.  The Spacer only held the two
apart, so it has nothing left to separate."
  (jetpacs-with-attrs
   (jetpacs-text
    "Note: this is configuration is better displayed in medium screen sizes.")
   :padding 16))

(defun jetpacs-m3-navigation-bar--classic ()
  "Upstream NavigationBarSample, as this screen\\='s bottom bar.
Three NavigationBarItems in an 80dp bar, Songs selected, each icon
taking its destination label as its contentDescription."
  (jetpacs-m3-navigation-bar--bar
   (jetpacs-m3-navigation-bar--destinations
    (lambda (spec selected)
      (jetpacs-m3-navigation-bar--item spec selected t)))
   80))

(jetpacs-m3-defcomponent "navigation-bar"
  :builders (list #'jetpacs-scaffold #'jetpacs-app-bar-item)
  :name "Navigation bar"
  :description
  "Navigation bars offer a persistent and convenient way to switch between primary destinations in an app."
  :guidelines "https://m3.material.io/components/navigation-bar"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#navigationbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/NavigationBar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ShortNavigationBarSample"
    "Navigation bar examples"
    :source jetpacs-m3-navigation-bar--source
    :expressive t
    :slots (list :bottom-bar #'jetpacs-m3-navigation-bar--short))
   (jetpacs-m3-example
    "ShortNavigationBarWithHorizontalItemsSample"
    "Navigation bar examples"
    :source jetpacs-m3-navigation-bar--source
    :expressive t
    :build #'jetpacs-m3-navigation-bar--horizontal-note
    :slots (list :bottom-bar #'jetpacs-m3-navigation-bar--short-horizontal))
   (jetpacs-m3-example
    "NavigationBarSample"
    "Navigation bar examples"
    :source jetpacs-m3-navigation-bar--source
    :slots (list :bottom-bar #'jetpacs-m3-navigation-bar--classic))
   ))

(provide 'jetpacs-m3-navigation-bar)
;;; jetpacs-m3-navigation-bar.el ends here
