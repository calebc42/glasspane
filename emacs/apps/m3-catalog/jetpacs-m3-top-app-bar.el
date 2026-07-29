;;; jetpacs-m3-top-app-bar.el --- Catalog component: Top app bar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `TopAppBar' + Examples.kt
;; `TopAppBarExamples' (15 examples), samples/AppBarSamples.kt.
;;
;; A top app bar IS screen chrome, so the recreated samples claim the
;; Example screen's own `:top-bar' slot instead of nesting a second
;; scaffold in the body -- see `jetpacs-m3-slot-keys'.  The slot takes an
;; ordinary node, which the Companion draws in a full-width, vertically
;; centered Row, so a small top app bar is authored end to end: the
;; Example screen's back arrow first (a `:top-bar' REPLACES the screen's
;; whole bar, so the arrow has nowhere else to live), then the sample's
;; Menu navigationIcon, its title, and its actions.  `:build' carries
;; what upstream scrolls under every one of these bars -- the numbers 0
;; to 75.
;;
;; TRIAGE.  Four of the fifteen are layout, and layout is on the wire: a
;; title, a title with a subtitle, and both of those centered.  `row',
;; `column' and `box' carry all of it, and a `box' with :alignment
;; "center" is how CenterAlignedTopAppBar centers a title over the BAR
;; rather than over the gap between the navigation icon and the actions.
;;
;; The other eleven are not layout.  Ten exist to demonstrate a
;; TopAppBarScrollBehavior -- pinned (recolor the container once the
;; content under it moves), enterAlways (hide going up, return going
;; down), exitUntilCollapsed (fold a Medium, Large or TwoRows bar down to
;; one row) -- and `scaffold' has no scroll-behavior member, its top_bar
;; has no collapsed- or expanded-height member, and nothing ever hands a
;; node a collapse fraction to author against.  Two of those ten also
;; want a list node the wire does not have: a lazy list opened at item
;; 30, and a reversed adaptive grid.  The eleventh, the adaptive actions
;; sample, needs the window size class, and no wire message reports that
;; to Emacs.
;;
;; Upstream wraps every IconButton in a TooltipBox with a PlainTooltip
;; repeating its label; there is no tooltip node, and the label already
;; rides `:content-description', where a screen reader looks.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-top-app-bar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/AppBarSamples.kt"
  "Upstream TopAppBarExampleSourceUrl.")

(defconst jetpacs-m3-top-app-bar--flexible-note
  "The centered title and the subtitle are already recreated by the two Simple samples; what is left is the flexible bar folding from its expanded height down to one row, and the scaffold node has no scroll-behavior member and its top_bar has no expanded-height member to ask for that."
  "Why both ExitUntilCollapsed...Flexible... samples are unsupported.")

(defconst jetpacs-m3-top-app-bar--item-count 76
  "How many rows upstream scrolls under every bar: (0..75).")

(defun jetpacs-m3-top-app-bar--content ()
  "The Scaffold content every sample in AppBarSamples.kt shares.
A LazyColumn of the numbers 0 to 75, 8dp apart, each 16dp in from the
edges.  It is a plain column here because the Example screen body is
already a scrolling column, and a lazily-composed list has no bounded
height to compose against inside one."
  (apply #'jetpacs-column
         (append (cl-loop for i from 0 below jetpacs-m3-top-app-bar--item-count
                          collect (jetpacs-with-attrs
                                   (jetpacs-text (number-to-string i))
                                   :pad (list :horizontal 16)))
                 (list :spacing 8 :fill t))))

(defun jetpacs-m3-top-app-bar--nav-icon ()
  "The navigationIcon every sample shares: a Menu IconButton."
  (jetpacs-icon-button "menu" (jetpacs-m3-demo "Menu")
                       :content-description "Menu"))

(defun jetpacs-m3-top-app-bar--favorite ()
  "The actions slot the recreated samples share: Add to favorites."
  (jetpacs-icon-button "favorite" (jetpacs-m3-demo "Add to favorites")
                       :content-description "Add to favorites"))

(defun jetpacs-m3-top-app-bar--title (title subtitle centered)
  "The title block: TITLE, with SUBTITLE under it when there is one.
Both lines are maxLines = 1 upstream.  CENTERED non-nil aligns the pair
on their shared center, which is what titleHorizontalAlignment does."
  (if subtitle
      (jetpacs-column (jetpacs-text title :style "title" :max-lines 1)
                      (jetpacs-text subtitle :style "caption" :max-lines 1)
                      :spacing 2 :align (if centered "center" "start"))
    (jetpacs-text title :style "title" :max-lines 1)))

(defun jetpacs-m3-top-app-bar--bar (back title &optional subtitle)
  "A start-aligned small top app bar titled TITLE, with SUBTITLE.
BACK leads the row, ahead of the Menu navigationIcon: this node is the
Example screen top bar, so the arrow has nowhere else to live.  The
weight-1 title is what keeps the trailing action at intrinsic width."
  (jetpacs-row
   (jetpacs-m3-back-button back)
   (jetpacs-m3-top-app-bar--nav-icon)
   (jetpacs-with-attrs (jetpacs-m3-top-app-bar--title title subtitle nil)
                       :weight 1)
   (jetpacs-m3-top-app-bar--favorite)
   :align "center" :spacing 4 :fill t))

(defun jetpacs-m3-top-app-bar--centered-bar (back title &optional subtitle)
  "A center-aligned small top app bar titled TITLE, with SUBTITLE.
CenterAlignedTopAppBar centers the title over the whole bar, not over
what is left between the navigation icon and the actions, so the title
sits in a `box' aligned center with the icon row filling that same box
behind it.  BACK leads the icon row, as in `jetpacs-m3-top-app-bar--bar'."
  (jetpacs-with-attrs
   (jetpacs-box
    (jetpacs-row (jetpacs-m3-back-button back)
                 (jetpacs-m3-top-app-bar--nav-icon)
                 (jetpacs-with-attrs (jetpacs-spacer) :weight 1)
                 (jetpacs-m3-top-app-bar--favorite)
                 :align "center" :spacing 4 :fill t)
    (jetpacs-m3-top-app-bar--title title subtitle t)
    :alignment "center")
   :fill_fraction 1.0))

(defun jetpacs-m3-top-app-bar--simple (back)
  "Upstream SimpleTopAppBar: Menu, the title, Add to favorites.
The one sample here that sets no scrollBehavior at all -- its own
KDoc says the bar does not react to scroll events under it."
  (jetpacs-m3-top-app-bar--bar back "Simple TopAppBar"))

(defun jetpacs-m3-top-app-bar--with-subtitle (back)
  "Upstream SimpleTopAppBarWithSubtitle: a \"Subtitle\" under the title.
The subtitle is the subject; the pinnedScrollBehavior it also installs
only recolors the container, which is the whole of PinnedTopAppBar."
  (jetpacs-m3-top-app-bar--bar back "Simple TopAppBar" "Subtitle"))

(defun jetpacs-m3-top-app-bar--centered (back)
  "Upstream SimpleCenterAlignedTopAppBar: \"Centered TopAppBar\"."
  (jetpacs-m3-top-app-bar--centered-bar back "Centered TopAppBar"))

(defun jetpacs-m3-top-app-bar--centered-with-subtitle (back)
  "Upstream SimpleCenterAlignedTopAppBarWithSubtitle.
Title and subtitle both centered by titleHorizontalAlignment; upstream
keeps the string \"Simple TopAppBar\" as the title of this one."
  (jetpacs-m3-top-app-bar--centered-bar back "Simple TopAppBar" "Subtitle"))

(jetpacs-m3-defcomponent "top-app-bar"
  :name "Top app bar"
  :description
  "Top app bars display information and actions at the top of a screen."
  :guidelines "https://m3.material.io/components/top-app-bar"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#smalltopappbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/AppBar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SimpleTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :top-bar #'jetpacs-m3-top-app-bar--simple
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleTopAppBarWithAdaptiveActions"
    "Top app bar examples"
    :source "Top app bar examples"
    :unsupported
    "There is no app-bar-row node and no wire message tells Emacs the window size class: AppBarRow showing three actions on a compact window and five on a wider one, with the rest folding into an overflow menu, is decided at measure time on the device and is this sample's whole subject.")
   (jetpacs-m3-example
    "SimpleTopAppBarWithSubtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :top-bar #'jetpacs-m3-top-app-bar--with-subtitle
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleCenterAlignedTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :top-bar #'jetpacs-m3-top-app-bar--centered
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleCenterAlignedTopAppBarWithSubtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :top-bar #'jetpacs-m3-top-app-bar--centered-with-subtitle
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "PinnedTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "The scaffold node has no scroll-behavior member: pinnedScrollBehavior recolors the bar's container as soon as the content under it is scrolled, and that recoloring is this sample's whole difference from SimpleTopAppBar.")
   (jetpacs-m3-example
    "PinnedTopAppBarWithPreScrolledLazyColumn"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "Neither half is on the wire: the scaffold node has no scroll-behavior member, and no list node takes an initial index for rememberLazyListState(initialFirstVisibleItemIndex = 30), which is the state this sample hands the behavior so the bar starts out already recolored.")
   (jetpacs-m3-example
    "PinnedTopAppBarWithReversedLazyGrid"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "There is no lazy-grid node -- nothing carries LazyVerticalGrid, GridCells.Adaptive or reverseLayout -- and the scaffold node has no scroll-behavior member to take the custom isScrollingContentAtStart that reversed grid exists to need.")
   (jetpacs-m3-example
    "EnterAlwaysTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported
    "The scaffold node has no scroll-behavior member: enterAlwaysScrollBehavior slides the top bar away as the content scrolls up and brings it straight back on the way down, and that motion is this sample's whole subject.")
   (jetpacs-m3-example
    "EnterAlwaysTopAppBarWithReverseScrolling"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported
    "Neither half is on the wire: the scaffold node has no scroll-behavior member, and the column node's scroll member is a plain boolean with no reverse-scrolling flag for the bottom-anchored content this sample pairs it with.")
   (jetpacs-m3-example
    "ExitUntilCollapsedMediumTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "The scaffold node has no scroll-behavior member and its top_bar has no collapsed- or expanded-height member: a MediumTopAppBar folding from two rows to one as the content scrolls up is exactly what exitUntilCollapsedScrollBehavior drives, and it is all this sample adds.")
   (jetpacs-m3-example
    "ExitUntilCollapsedCenterAlignedMediumFlexibleTopAppBar with subtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported jetpacs-m3-top-app-bar--flexible-note)
   (jetpacs-m3-example
    "ExitUntilCollapsedLargeTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "The scaffold node has no scroll-behavior member and its top_bar has no collapsed- or expanded-height member: a LargeTopAppBar folding from its tall two-row form down to one row is what exitUntilCollapsedScrollBehavior drives, and it is all this sample adds.")
   (jetpacs-m3-example
    "ExitUntilCollapsedCenterAlignedLargeFlexibleTopAppBar with subtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported jetpacs-m3-top-app-bar--flexible-note)
   (jetpacs-m3-example
    "CustomTwoRowsTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported
    "There is no two-rows top-bar node: TwoRowsTopAppBar takes a collapsedHeight and an expandedHeight and hands its title and subtitle an expanded flag, swapping \"Expanded TopAppBar\" for \"Collapsed TopAppBar\" as it folds, and no wire member reports a collapse fraction back to Emacs to author that swap against.")
   ))

(provide 'jetpacs-m3-top-app-bar)
;;; jetpacs-m3-top-app-bar.el ends here
