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
;; The other eleven are not layout.  Ten turn on a
;; TopAppBarScrollBehavior -- pinned (recolor the container once the
;; content under it moves), enterAlways (hide going up, return going
;; down), exitUntilCollapsed (fold a Medium, Large or TwoRows bar down to
;; one row).  The eleventh, the adaptive actions sample, needs the window
;; size class, and no wire message reports that to Emacs; there is no
;; `app_bar_row' node for its overflow either.
;;
;; THE WIRE HAS THE BEHAVIORS; THIS MODULE CANNOT REACH THEM.  `scaffold'
;; gained `top_bar_style' (small, center, medium, large),
;; `top_bar_subtitle' and `scroll_behavior' (pinned, enter_always,
;; exit_until_collapsed): a present style routes the authored `top_bar'
;; node into a REAL M3 TopAppBar's title slot and puts
;; Modifier.nestedScroll on the Scaffold, so the bar genuinely collapses.
;; None of it is reachable from a catalog example.  `jetpacs-m3-example'
;; hands `:top-bar' one argument, BACK, and takes back one NODE; the only
;; other scaffold members an example may set are `jetpacs-m3-slot-keys'
;; -- :fab, :bottom-bar, :drawer, :floating-toolbar, :on-refresh,
;; :snackbar -- so `jetpacs-m3-example-screen' always calls
;; `jetpacs-scaffold' with no style, and a scroll behavior without a
;; style is an error by construction.  Closing this is a `jetpacs-m3-core'
;; change (an example needs a way to name a bar style, a subtitle and a
;; scroll behavior for its own screen's scaffold), not a change here.  So
;; all ten stay unsupported, and for four of them -- PinnedTopAppBar,
;; EnterAlwaysTopAppBar and the two plain ExitUntilCollapsed bars -- the
;; HARNESS is the only thing left in the way, which is what their reasons
;; now say instead of the wire.
;;
;; The other six would still not build if the harness carried the style,
;; and their reasons say so too: a lazy list opened at item 30, an
;; adaptive reversed grid plus the custom isScrollingContentAtStart the
;; `scroll_behavior' enum has no room for, a reverse-scrolling column,
;; the two Flexible bars (only the SMALL style takes `top_bar_subtitle',
;; and no style carries a title alignment -- the asymmetry is AppBar.kt's
;; own), and TwoRowsTopAppBar, for which there is no node at all and no
;; collapse fraction reported back to Emacs to author its title swap
;; against.
;;
;; Upstream wraps every IconButton in a TooltipBox with a PlainTooltip
;; repeating its label, anchored TooltipAnchorPosition.Above.  That is the
;; `tooltip' node's own default, so the four recreations author it --
;; `jetpacs-m3-top-app-bar--tipped' -- and the label rides
;; `:content-description' as well, where a screen reader looks.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-top-app-bar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/AppBarSamples.kt"
  "Upstream TopAppBarExampleSourceUrl.")

(defconst jetpacs-m3-top-app-bar--harness-note
  "The wire carries this now: the scaffold node's top_bar_style asks for a real M3 TopAppBar and its scroll_behavior wires pinned, enter_always or exit_until_collapsed to that bar and to the body's nested scroll.  The catalog harness is what cannot reach it -- an example's :top-bar is a function returning the top_bar node alone, and the slots an example may claim are :fab, :bottom-bar, :drawer, :floating-toolbar, :on-refresh and :snackbar, with no bar style or scroll behavior among them, so this screen's own scaffold is always built without a style."
  "Why the scroll-behavior samples are unsupported: the harness, not the wire.")

(defconst jetpacs-m3-top-app-bar--flexible-note
  "The centered title and the subtitle are already recreated by the two Simple samples; what is left is the flexible bar folding from its expanded height down to one row while a centered subtitle stays under the centered title.  The wire's bar styles do not reach that: only the small style takes top_bar_subtitle -- \"medium\" and \"large\" ignore it, which is the asymmetry AppBar.kt itself has -- and no style carries a title-alignment member, so a medium or large bar draws a plain start-aligned title and no second line.  The catalog harness cannot ask an example for a bar style in the first place."
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

(defun jetpacs-m3-top-app-bar--tipped (icon label)
  "ICON as an IconButton described by LABEL, under LABEL's plain tooltip.
Upstream wraps every one of these bars' IconButtons in a TooltipBox whose
PlainTooltip repeats the contentDescription, anchored
TooltipAnchorPosition.Above -- which is the `tooltip' node's own default."
  (jetpacs-tooltip label
                   (jetpacs-icon-button icon (jetpacs-m3-demo label)
                                        :content-description label)))

(defun jetpacs-m3-top-app-bar--nav-icon ()
  "The navigationIcon every sample shares: a Menu IconButton."
  (jetpacs-m3-top-app-bar--tipped "menu" "Menu"))

(defun jetpacs-m3-top-app-bar--favorite ()
  "The actions slot the recreated samples share: Add to favorites."
  (jetpacs-m3-top-app-bar--tipped "favorite" "Add to favorites"))

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
    (concat
     "pinnedScrollBehavior recolors the bar's container as soon as the content under it is scrolled, and that recoloring is this sample's whole difference from SimpleTopAppBar.  "
     jetpacs-m3-top-app-bar--harness-note))
   (jetpacs-m3-example
    "PinnedTopAppBarWithPreScrolledLazyColumn"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    (concat
     "No list node takes an initial index, so rememberLazyListState(initialFirstVisibleItemIndex = 30) -- the pre-scrolled state this sample hands the behavior so the bar starts out already recolored -- cannot be asked for at all.  The pinning is a second, separate gap.  "
     jetpacs-m3-top-app-bar--harness-note))
   (jetpacs-m3-example
    "PinnedTopAppBarWithReversedLazyGrid"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "There is no lazy-grid node -- nothing carries LazyVerticalGrid, GridCells.Adaptive or reverseLayout -- and the scaffold node's scroll_behavior is a bare enum (pinned, enter_always, exit_until_collapsed) with no place for the custom isScrollingContentAtStart a reversed grid needs to keep the bar's color correct, which is the very thing this sample exists to show.")
   (jetpacs-m3-example
    "EnterAlwaysTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported
    (concat
     "enterAlwaysScrollBehavior slides the top bar away as the content scrolls up and brings it straight back on the way down, and that motion is this sample's whole subject.  "
     jetpacs-m3-top-app-bar--harness-note))
   (jetpacs-m3-example
    "EnterAlwaysTopAppBarWithReverseScrolling"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported
    (concat
     "The column node's scroll member is a plain boolean with no reverse-scrolling flag, so the bottom-anchored, reverse-scrolled content this sample pairs the behavior with cannot be built at all.  The enterAlways half is a second, separate gap.  "
     jetpacs-m3-top-app-bar--harness-note))
   (jetpacs-m3-example
    "ExitUntilCollapsedMediumTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    (concat
     "A MediumTopAppBar folding from two rows to one as the content scrolls up is exactly what exitUntilCollapsedScrollBehavior drives, and it is all this sample adds.  "
     jetpacs-m3-top-app-bar--harness-note))
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
    (concat
     "A LargeTopAppBar folding from its tall two-row form down to one row is what exitUntilCollapsedScrollBehavior drives, and it is all this sample adds.  "
     jetpacs-m3-top-app-bar--harness-note))
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
