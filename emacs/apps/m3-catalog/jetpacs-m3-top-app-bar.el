;;; jetpacs-m3-top-app-bar.el --- Catalog component: Top app bar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `TopAppBar' + Examples.kt
;; `TopAppBarExamples' (15 examples), samples/AppBarSamples.kt.
;;
;; A top app bar IS screen chrome, so the recreated samples claim the
;; Example screen's own `:top-bar' slot instead of nesting a second
;; scaffold in the body -- see `jetpacs-m3-slot-keys'.  `:build' carries
;; what upstream scrolls under every one of these bars: the numbers 0 to
;; 75.
;;
;; EVERY BAR HERE IS A REAL M3 TopAppBar.  `:top-bar-style' (small,
;; center, medium, large) makes the Example screen's scaffold render an
;; actual TopAppBar / CenterAlignedTopAppBar / MediumTopAppBar /
;; LargeTopAppBar instead of the plain status-bar-padded Row it draws
;; without one, `:top-bar-subtitle' is the second line M3 puts under the
;; title, and `:scroll-behavior' (pinned, enter_always,
;; exit_until_collapsed) also puts Modifier.nestedScroll on the Scaffold,
;; so the bar genuinely recolors, hides or folds as the body scrolls.
;;
;; What that bar does NOT have is an actions slot, and its navigationIcon
;; is the Companion's own drawer hamburger, which the Example screen has
;; no drawer for.  So the node a `:top-bar' function returns is the TITLE
;; slot's content and carries everything else: the way back first (a
;; `:top-bar' replaces the screen's whole bar, so the arrow has nowhere
;; else to live), then the sample's Menu navigationIcon, the title, and
;; the actions.  For the `center' style that node must also SPAN the bar
;; -- CenterAlignedTopAppBar centers the title composable, so a composable
;; narrower than the bar would centre nothing -- which is why
;; `jetpacs-m3-top-app-bar--centered-bar' is a full-width `box' with the
;; icon row behind a centered title.
;;
;; TRIAGE.  Nine of the fifteen are recreated: the four Simple bars
;; (title, subtitle, centered, centered with subtitle), the four whose
;; subject is a scroll behavior the wire spells exactly -- PinnedTopAppBar
;; (pinned), EnterAlwaysTopAppBar (enter_always) and the Medium and Large
;; ExitUntilCollapsed bars (exit_until_collapsed on the medium and large
;; styles) -- and SimpleTopAppBarWithAdaptiveActions on the `app_bar_row'
;; node, which folds the actions that do not fit into the more_vert menu
;; at measure time (upstream's ADDITIONAL window-class cap stays a stated
;; seam: no wire message reports a size class to cap by).
;;
;; The remaining six are not layout and not a bare behavior:
;; * PinnedTopAppBarWithPreScrolledLazyColumn and
;;   EnterAlwaysTopAppBarWithReverseScrolling are both about ARGUMENTS to
;;   the behavior -- a lazyListState, a scrollState with reverseScrolling
;;   -- and `scroll_behavior' is a bare enum, so the Companion always
;;   constructs the behavior with none.  The first also wants a list node
;;   opened at item 30, which nothing carries.
;; * PinnedTopAppBarWithReversedLazyGrid wants a lazy-grid node that does
;;   not exist, and a custom isScrollingContentAtStart the enum has no
;;   room for.
;; * The two Flexible bars want a subtitle and a centered title on a
;;   medium/large bar: only the SMALL style takes `top_bar_subtitle' and
;;   no style carries a title alignment -- the asymmetry is AppBar.kt's
;;   own.
;; * CustomTwoRowsTopAppBar has no node at all, and no collapse fraction
;;   is reported back to Emacs to author its title swap against.
;;
;; Upstream wraps every IconButton in a TooltipBox with a PlainTooltip
;; repeating its label, anchored TooltipAnchorPosition.Above.  That is the
;; `tooltip' node's own default, so the recreations author it --
;; `jetpacs-m3-top-app-bar--tipped' -- and the label rides
;; `:content-description' as well, where a screen reader looks.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-top-app-bar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/AppBarSamples.kt"
  "Upstream TopAppBarExampleSourceUrl.")

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

(defun jetpacs-m3-top-app-bar--tipped (icon label &optional description)
  "ICON as an IconButton under LABEL's plain tooltip.
DESCRIPTION is its contentDescription, LABEL when omitted -- upstream's
Star action is the one whose tooltip (\"Add to starred\") and
contentDescription (\"Star\") are not the same string.

Upstream wraps every one of these bars' IconButtons in a TooltipBox with
a PlainTooltip anchored TooltipAnchorPosition.Above, which is the
`tooltip' node's own default."
  (jetpacs-tooltip label
                   (jetpacs-icon-button icon (jetpacs-m3-demo label)
                                        :content-description
                                        (or description label))))

(defun jetpacs-m3-top-app-bar--nav-icon ()
  "The navigationIcon every sample shares: a Menu IconButton."
  (jetpacs-m3-top-app-bar--tipped "menu" "Menu"))

(defun jetpacs-m3-top-app-bar--favorite ()
  "The action every sample but PinnedTopAppBar has alone: Add to favorites."
  (jetpacs-m3-top-app-bar--tipped "favorite" "Add to favorites"))

(defun jetpacs-m3-top-app-bar--star ()
  "PinnedTopAppBar's second action, the only one in the module."
  (jetpacs-m3-top-app-bar--tipped "star" "Add to starred" "Star"))

(defun jetpacs-m3-top-app-bar--bar (back title &rest actions)
  "The node a styled bar draws in its TITLE slot: BACK, Menu, TITLE, ACTIONS.
`:top-bar-style' gives the Example screen a real M3 TopAppBar, and that
bar has no actions slot at all -- its navigationIcon slot is the
Companion's own drawer hamburger, which this screen has no drawer for --
so the way back, the sample's Menu navigationIcon and its actions all
ride the one node the title slot takes.  The weight-1 title is what keeps
the trailing actions at intrinsic width.  The subtitle, where a sample
has one, is not here: it is `:top-bar-subtitle', drawn by the bar itself."
  (apply #'jetpacs-row
         (append (list (jetpacs-m3-back-button back)
                       (jetpacs-m3-top-app-bar--nav-icon)
                       (jetpacs-with-attrs
                        (jetpacs-text title :style "title" :max-lines 1)
                        :weight 1))
                 actions
                 (list :align "center" :spacing 4 :fill t))))

(defun jetpacs-m3-top-app-bar--centered-bar (back title &rest actions)
  "The node a `center' bar draws in its title slot, TITLE centered on it.
CenterAlignedTopAppBar centers the title COMPOSABLE, so that composable
has to span the bar for the centering to mean anything: here it is a
`box' filled by the icon row -- BACK, the Menu navigationIcon, then
ACTIONS -- with TITLE centered over it.  Spanning the bar is also what
puts `:top-bar-subtitle' under the centered title rather than under the
icons, since M3 stacks the two in one column."
  (jetpacs-with-attrs
   (jetpacs-box
    (apply #'jetpacs-row
           (append (list (jetpacs-m3-back-button back)
                         (jetpacs-m3-top-app-bar--nav-icon)
                         (jetpacs-with-attrs (jetpacs-spacer) :weight 1))
                   actions
                   (list :align "center" :spacing 4 :fill t)))
    (jetpacs-text title :style "title" :max-lines 1)
    :alignment "center")
   :fill_fraction 1.0))

(defun jetpacs-m3-top-app-bar--adaptive (back)
  "Upstream SimpleTopAppBarWithAdaptiveActions: an AppBarRow of five.
The `app_bar_row' node measures Attachment, Edit, Star, Snooze and
Mark unread against the bar's remaining width and folds the rest into
the more_vert menu — each folded item's label becoming its menu row."
  (jetpacs-row
   (jetpacs-m3-back-button back)
   (jetpacs-m3-top-app-bar--nav-icon)
   (jetpacs-with-attrs
    (jetpacs-text "Simple TopAppBar" :style "title" :max-lines 1)
    :weight 1)
   (jetpacs-app-bar-row
    (list (jetpacs-app-bar-item "Attachment" "attachment"
                                (jetpacs-m3-demo "Attachment"))
          (jetpacs-app-bar-item "Edit" "edit" (jetpacs-m3-demo "Edit"))
          (jetpacs-app-bar-item "Star" "star" (jetpacs-m3-demo "Star"))
          (jetpacs-app-bar-item "Snooze" "snooze" (jetpacs-m3-demo "Snooze"))
          (jetpacs-app-bar-item "Mark unread" "mark_email_unread"
                                (jetpacs-m3-demo "Mark unread"))))
   :align "center" :spacing 4 :fill t))

(defun jetpacs-m3-top-app-bar--simple (back)
  "Upstream SimpleTopAppBar: Menu, the title, Add to favorites.
The one sample here that sets no scrollBehavior at all -- its own
KDoc says the bar does not react to scroll events under it."
  (jetpacs-m3-top-app-bar--bar back "Simple TopAppBar"
                               (jetpacs-m3-top-app-bar--favorite)))

(defun jetpacs-m3-top-app-bar--with-subtitle (back)
  "Upstream SimpleTopAppBarWithSubtitle: a \"Subtitle\" under the title.
The subtitle is the subject; the pinnedScrollBehavior it also installs
only recolors the container, which is the whole of PinnedTopAppBar."
  (jetpacs-m3-top-app-bar--bar back "Simple TopAppBar"
                               (jetpacs-m3-top-app-bar--favorite)))

(defun jetpacs-m3-top-app-bar--centered (back)
  "Upstream SimpleCenterAlignedTopAppBar: \"Centered TopAppBar\"."
  (jetpacs-m3-top-app-bar--centered-bar back "Centered TopAppBar"
                                        (jetpacs-m3-top-app-bar--favorite)))

(defun jetpacs-m3-top-app-bar--centered-with-subtitle (back)
  "Upstream SimpleCenterAlignedTopAppBarWithSubtitle.
Not a CenterAlignedTopAppBar at all upstream: it is the small overload
carrying titleHorizontalAlignment = CenterHorizontally, which is exactly
what the `center' style plus a `:top-bar-subtitle' renders.  Upstream
keeps the string \"Simple TopAppBar\" as the title of this one."
  (jetpacs-m3-top-app-bar--centered-bar back "Simple TopAppBar"
                                        (jetpacs-m3-top-app-bar--favorite)))

(defun jetpacs-m3-top-app-bar--pinned (back)
  "Upstream PinnedTopAppBar: the bar that recolors under a scrolled body.
The only sample in the module with two actions, and the only place the
Star icon appears -- upstream's RowScope comment is about exactly that."
  (jetpacs-m3-top-app-bar--bar back "TopAppBar"
                               (jetpacs-m3-top-app-bar--favorite)
                               (jetpacs-m3-top-app-bar--star)))

(defun jetpacs-m3-top-app-bar--enter-always (back)
  "Upstream EnterAlwaysTopAppBar: the bar that hides going up.
Its \"Subtitle\" is `:top-bar-subtitle' on the example, not a node here."
  (jetpacs-m3-top-app-bar--bar back "TopAppBar"
                               (jetpacs-m3-top-app-bar--favorite)))

(defun jetpacs-m3-top-app-bar--medium (back)
  "Upstream ExitUntilCollapsedMediumTopAppBar's MediumTopAppBar."
  (jetpacs-m3-top-app-bar--bar back "Medium TopAppBar"
                               (jetpacs-m3-top-app-bar--favorite)))

(defun jetpacs-m3-top-app-bar--large (back)
  "Upstream ExitUntilCollapsedLargeTopAppBar's LargeTopAppBar."
  (jetpacs-m3-top-app-bar--bar back "Large TopAppBar"
                               (jetpacs-m3-top-app-bar--favorite)))

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
    :top-bar-style "small"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleTopAppBarWithAdaptiveActions"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    ;; The app_bar_row node measures the five actions in the bar and
    ;; folds what does not fit into the more_vert menu — the adaptation
    ;; happens at layout time on the device.  One seam: upstream
    ;; ADDITIONALLY caps the inline count from the window width class
    ;; (three on compact); here the fold is pure measurement, since no
    ;; wire message reports a size class to cap by.
    :top-bar #'jetpacs-m3-top-app-bar--adaptive
    :top-bar-style "small"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleTopAppBarWithSubtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :top-bar #'jetpacs-m3-top-app-bar--with-subtitle
    :top-bar-style "small"
    :top-bar-subtitle "Subtitle"
    :scroll-behavior "pinned"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleCenterAlignedTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :top-bar #'jetpacs-m3-top-app-bar--centered
    :top-bar-style "center"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "SimpleCenterAlignedTopAppBarWithSubtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :top-bar #'jetpacs-m3-top-app-bar--centered-with-subtitle
    :top-bar-style "center"
    :top-bar-subtitle "Subtitle"
    :scroll-behavior "pinned"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "PinnedTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :top-bar #'jetpacs-m3-top-app-bar--pinned
    :top-bar-style "small"
    :scroll-behavior "pinned"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "PinnedTopAppBarWithPreScrolledLazyColumn"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported
    "The pinning itself is now recreated by PinnedTopAppBar; what this sample adds is the pre-scrolled state, and no list node takes an initial index -- neither column nor lazy_column has a member for rememberLazyListState(initialFirstVisibleItemIndex = 30).  Nor can that state be handed to the behavior: scroll_behavior is a bare enum, so the Companion always calls pinnedScrollBehavior() with no lazyListState, which is the argument this sample exists to pass so the bar starts out already recolored.")
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
    :top-bar #'jetpacs-m3-top-app-bar--enter-always
    :top-bar-style "small"
    :top-bar-subtitle "Subtitle"
    :scroll-behavior "enter_always"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "EnterAlwaysTopAppBarWithReverseScrolling"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :expressive t
    :unsupported
    "The column node does carry reverse_scroll now, and the enterAlways bar is recreated by EnterAlwaysTopAppBar, but this sample is neither of those halves on its own: it is the PAIRING, and the pairing is what the wire drops.  Upstream hands enterAlwaysScrollBehavior the very scrollState its Column scrolls and reverseScrolling = true, and its own comment says those arguments are there so the bar's color updates correctly over reversed content.  scroll_behavior is a bare enum, so the Companion always calls enterAlwaysScrollBehavior() with neither, and the bar would be wrong in exactly the way the sample warns about.")
   (jetpacs-m3-example
    "ExitUntilCollapsedMediumTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :top-bar #'jetpacs-m3-top-app-bar--medium
    :top-bar-style "medium"
    :scroll-behavior "exit_until_collapsed"
    :build #'jetpacs-m3-top-app-bar--content)
   (jetpacs-m3-example
    "ExitUntilCollapsedCenterAlignedMediumFlexibleTopAppBar with subtitle"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :unsupported jetpacs-m3-top-app-bar--flexible-note)
   (jetpacs-m3-example
    "ExitUntilCollapsedLargeTopAppBar"
    "Top app bar examples"
    :source jetpacs-m3-top-app-bar--source
    :top-bar #'jetpacs-m3-top-app-bar--large
    :top-bar-style "large"
    :scroll-behavior "exit_until_collapsed"
    :build #'jetpacs-m3-top-app-bar--content)
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
