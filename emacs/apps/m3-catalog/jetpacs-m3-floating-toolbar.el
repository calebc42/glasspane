;;; jetpacs-m3-floating-toolbar.el --- Catalog component: Floating Toolbar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `FloatingToolbars' + Examples.kt
;; `FloatingToolbarsExamples' (11 examples),
;; samples/FloatingToolbarSamples.kt.
;;
;; M3's `FloatingToolbar' is not a node type: the `scaffold' carries one
;; as a slot with six §17.6 members.  `floating_toolbar_orientation'
;; turns that slot from the full-width band above the bottom bar into
;; M3's REAL pill, floating over the body, and
;; `floating_toolbar_expanded', `_placement', `_fab', `_scroll' and
;; `_exit_direction' vary it.  That is most of what these eleven samples
;; exist to show, and all six are reachable now: `jetpacs-m3-example'
;; takes them as first-class keywords and forwards them on BOTH screen
;; paths, so an example that claims only the `:floating-toolbar' slot
;; gets them through `jetpacs-chrome-screen' -- and keeps that screen's
;; standard chrome (back, pin, theme, more) instead of authoring a bar
;; of its own, which is why the horizontal recreation no longer does.
;;
;; RECREATED (6):
;;
;;   * ExpandableHorizontal... -- leadingContent Check and Edit, a
;;     64dp-wide filled Add, trailingContent Download and Favorite --
;;     drawn as the bottom-center pill it is upstream.  Only the collapse
;;     motion it is named for is missing (below).
;;   * both Scrollable samples: that same cluster at bottom_center and,
;;     turned on its side, at center_end, each with
;;     `floating_toolbar_scroll' and the `_exit_direction' of upstream's
;;     exitAlwaysScrollBehavior(Bottom) / (End), over the LazyColumn of
;;     0..75 whose scroll drives it.  The list is not decoration: that
;;     behavior only shows itself over content that actually scrolls.
;;   * both Centered...WithFab samples: Person, Edit, Favorite and
;;     MoreVert, always expanded, `floating_toolbar_fab' for the FAB
;;     fused to the pill's end, and the same scroll behavior hiding the
;;     two together, over upstream's LoremIpsum body.
;;   * HorizontalFloatingToolbarAsScaffoldFab..., whose subject is the
;;     HOSTING, and which stays in this screen's fab slot -- see
;;     `jetpacs-m3-floating-toolbar--as-scaffold-fab' for the re-check
;;     against `floating_toolbar_placement' and `floating_toolbar_fab'.
;;
;; One thing none of the six can ask for is `colors'.  Five of the
;; eleven -- three of them recreated -- pass
;; FloatingToolbarDefaults.vibrantFloatingToolbarColors()
;; -- FloatingToolbarTokens.VibrantContainerColor is primaryContainer
;; and its fabContainerColor is tertiaryContainer -- and the scaffold has
;; no colors member, so a rendered pill is always M3's standard palette
;; (surfaceContainer, with a primaryContainer FAB).
;;
;; The two Overflowing samples ride the `app_bar_row'/`app_bar_column'
;; nodes now: the five actions measure INSIDE the pill and fold into
;; the more_vert menu at layout time, in either orientation.
;;
;; STILL GENUINELY MISSING (3):
;;
;;   * floatingToolbarVerticalNestedScroll -- `floating_toolbar_scroll' is
;;     exitAlwaysScrollBehavior, which SLIDES the pill off an edge.  The
;;     Expandable samples show the other motion: a collapse to the leading
;;     content and back as the list scrolls.  No member carries it, and
;;     `floating_toolbar_expanded' is a static value.
;;   * a BINDING for `floating_toolbar_expanded' -- it has no on-change
;;     descriptor, so the FAB that toggles it in the two *WithFab samples
;;     has nothing to drive.
;;
;; The two Expandable samples are triaged apart, and the split is a
;; judgment about what each one shows rather than about the wire: the
;; motion is equally missing from both, and the horizontal one is kept
;; recreated because its static cluster is the whole content of
;; `HorizontalFloatingToolbar'.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-floating-toolbar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/FloatingToolbarSamples.kt"
  "Upstream FloatingToolbarsExampleSourceUrl.")

(defconst jetpacs-m3-floating-toolbar--item-count 76
  "How many rows the Scrollable samples scroll under the pill: (0..75).")

(defconst jetpacs-m3-floating-toolbar--lorem
  (concat "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
          "Integer sodales laoreet commodo. "
          "Phasellus a purus eu risus elementum consequat. "
          "Aenean eu elit ut nunc convallis laoreet non ut libero. "
          "Suspendisse interdum placerat risus vel ornare. "
          "Donec vehicula, turpis sed consectetur ullamcorper, "
          "ante nunc egestas quam, ultricies adipiscing velit enim at nunc. "
          "Aenean id diam neque. "
          "Praesent ut lacus sed justo viverra fermentum et ut sem. "
          "Fusce convallis gravida lacinia. "
          "Integer semper dolor ut elit sagittis lacinia. "
          "Praesent sodales scelerisque eros at rhoncus. "
          "Duis posuere sapien vel ipsum ornare interdum at eu quam. "
          "Vestibulum vel massa erat. Aenean quis sagittis purus. "
          "Phasellus arcu purus, rutrum id consectetur non, bibendum at nibh. "
          "\n\n"
          "Duis nec erat dolor. Nulla vitae consectetur ligula. "
          "Quisque nec mi est. "
          "Ut quam ante, rutrum at pellentesque gravida, pretium in dui. "
          "Cras eget sapien velit. "
          "Suspendisse ut sem nec tellus vehicula eleifend sit amet quis velit. "
          "Phasellus quis suscipit nisi. Nam elementum malesuada tincidunt. "
          "Curabitur iaculis pretium eros, malesuada faucibus leo eleifend a. "
          "Curabitur congue orci in neque euismod a blandit libero vehicula.")
  "LOREM_IPSUM_SOURCE from ui-tooling-preview's LoremIpsum.kt, verbatim.")

(defconst jetpacs-m3-floating-toolbar--prose
  (mapconcat #'identity
             (make-list 3 jetpacs-m3-floating-toolbar--lorem) " ")
  "What `LoremIpsum().values.first()' yields, near enough.
`LoremIpsum()' takes 500 words and its source is 174 of them, cycled --
so upstream's string is that source just under three times over.  This is
three times over.")

(defun jetpacs-m3-floating-toolbar--list-content ()
  "The Scaffold content both Scrollable samples share.
A LazyColumn of the numbers 0 to 75, 8dp apart, each 16dp in from the
edges.  It is a plain column here because the Example screen body is
already a scrolling column, and a lazily-composed list has no bounded
height to compose against inside one.

It is authored at all because `floating_toolbar_scroll' is a nested-scroll
behavior: the pill slides off its edge only over a body that scrolls, so
without upstream's list the member would have nothing to react to."
  (apply #'jetpacs-column
         (append (cl-loop for i from 0 below
                          jetpacs-m3-floating-toolbar--item-count
                          collect (jetpacs-with-attrs
                                   (jetpacs-text (number-to-string i))
                                   :pad (list :horizontal 16)))
                 (list :spacing 8 :fill t))))

(defun jetpacs-m3-floating-toolbar--prose-content ()
  "The Scaffold content both Centered...WithFab samples share.
Upstream is a Column, 16dp in from the edges, holding the one string
`remember { LoremIpsum().values.first() }' and scrolling vertically --
the scroll being what the exitAlwaysScrollBehavior hides the toolbar on.
The Example screen body is already that scrolling column, so this is the
text and its padding."
  (jetpacs-with-attrs
   (jetpacs-text jetpacs-m3-floating-toolbar--prose)
   :pad (list :horizontal 16)))

(defun jetpacs-m3-floating-toolbar--action (icon message)
  "One toolbar IconButton showing ICON and reporting MESSAGE on tap.
Every icon in these samples carries the same upstream
`contentDescription', \"Localized description\", over an empty
onClick -- so the description is upstream's literal and the tap says
which of the identically-described actions was hit."
  (jetpacs-icon-button icon (jetpacs-m3-demo message)
                       :content-description "Localized description"))

(defun jetpacs-m3-floating-toolbar--primary (icon message size &optional vertical)
  "ICON as the toolbar's primary action, SIZE dp long, reporting MESSAGE.
`icon_button' has no filled variant, so the FilledIconButton container
of the samples is composed: a `surface' in the primary role, circle
shape (M3's CircleShape is a 50% corner, i.e. the pill a 64dp-wide
filled icon button already is).

SIZE is the width, or the HEIGHT when VERTICAL is non-nil: upstream sizes
this button along the toolbar's own axis, `Modifier.width(64.dp)' in the
horizontal samples and `Modifier.height(64.dp)' in the vertical ones."
  (jetpacs-with-attrs
   (jetpacs-surface (jetpacs-m3-floating-toolbar--action icon message)
                    :color "primary" :shape "circle")
   (if vertical :height :width) size))

(defun jetpacs-m3-floating-toolbar--fused-fab (&optional on-tap)
  "The FAB fused to a pill's end, as the node `floating_toolbar_fab' takes.
Upstream is FloatingToolbarDefaults.VibrantFloatingActionButton over
Icon(Icons.Filled.Add, \"Localized description\"), and the toolbar
measures its FAB slot at a fixed size (FabSizeRange starts at
FabBaselineTokens.ContainerWidth, 56dp) -- which is why this node carries
no size of its own.  The container is composed the way a FAB is composed
everywhere in this catalog: a `surface' at 6dp of `:shadow-elevation'
with the tap on a centered `box', because `surface' has no on_tap.

Its role is primary_container, not the vibrant palette's
tertiaryContainer: the Companion's role table has no `tertiary_container'
and would fall back to on_surface.  primary_container is what a floating
toolbar's STANDARD colors give the FAB, and standard is what the pill
around it draws anyway -- `colors' is not a wire member."
  (jetpacs-with-attrs
   (jetpacs-surface
    (jetpacs-box (jetpacs-icon "add" :size 24 :color "on_primary_container"
                               :content-description "Localized description")
                 :alignment "center"
                 :on-tap (or on-tap (jetpacs-m3-demo "Add")))
    :color "primary_container" :shadow-elevation 6)
   :corner 16))

(defun jetpacs-m3-floating-toolbar--cluster-row ()
  "LeadingContent, content and TrailingContent in a row, as the toolbar slot.
The cluster ExpandableHorizontal... and ScrollableHorizontal... share:
leadingContent is Check and Edit, content is a 64dp-wide FilledIconButton
with Add, and trailingContent is Download and Favorite.

No `:fill' -- the slot is a pill now, not the full-width band, and a row
that filled its width would stretch the pill across the screen.  No
spacing either: upstream's HorizontalFloatingToolbar arranges its content
with Arrangement.Center and no spacedBy, each IconButton bringing its own
48dp target."
  (jetpacs-row
   (jetpacs-m3-floating-toolbar--action "check" "Check")
   (jetpacs-m3-floating-toolbar--action "edit" "Edit")
   (jetpacs-m3-floating-toolbar--primary "add" "Add" 64)
   (jetpacs-m3-floating-toolbar--action "download" "Download")
   (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
   :align "center"))

(defun jetpacs-m3-floating-toolbar--cluster-column ()
  "The same cluster stacked, as ScrollableVertical... draws it.
VerticalFloatingToolbar takes the identical leadingContent, content and
trailingContent; only the primary button turns, `Modifier.height(64.dp)'
where the horizontal samples pass a width."
  (jetpacs-column
   (jetpacs-m3-floating-toolbar--action "check" "Check")
   (jetpacs-m3-floating-toolbar--action "edit" "Edit")
   (jetpacs-m3-floating-toolbar--primary "add" "Add" 64 t)
   (jetpacs-m3-floating-toolbar--action "download" "Download")
   (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
   :align "center"))

(defun jetpacs-m3-floating-toolbar--with-fab-scaffold (flag orientation
                                                            placement exit)
  "The LIVE scaffold of a WithFab sample: the fused FAB is the toggle.
Upstream's FAB flips the toolbar's remembered expanded state; here its
tap flips sample FLAG and the next snapshot re-authors
floating_toolbar_expanded — authored presentation state, the rails'
discipline.  Expanded starts true (flag nil) exactly like upstream's
remember(true)."
  (lambda ()
    (list :floating-toolbar-orientation orientation
          :floating-toolbar-placement placement
          :floating-toolbar-expanded
          (jetpacs-bool (not (jetpacs-m3-flag flag)))
          :floating-toolbar-fab
          (jetpacs-m3-floating-toolbar--fused-fab
           (jetpacs-m3-flag-action flag))
          :floating-toolbar-scroll t
          :floating-toolbar-exit-direction exit)))

(defun jetpacs-m3-floating-toolbar--actions-row ()
  "The four IconButtons the *WithFab samples hold, in a row.
Person, Edit, Favorite, MoreVert -- upstream's whole `content' for
CenteredHorizontalFloatingToolbarWithFabSample.  The FAB is not here: it
is `floating_toolbar_fab', which the toolbar fuses to the pill's end.

The samples whose toolbar actually collapses wrap each of these buttons
in `Modifier.focusProperties { canFocus = expanded }', so a collapsed
toolbar's hidden buttons take no keyboard focus; this one does not, being
the always-expanded sample, and nothing on the wire spells it anyway."
  (jetpacs-row
   (jetpacs-m3-floating-toolbar--action "person" "Person")
   (jetpacs-m3-floating-toolbar--action "edit" "Edit")
   (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
   (jetpacs-m3-floating-toolbar--action "more_vert" "MoreVert")
   :align "center"))

(defun jetpacs-m3-floating-toolbar--actions-column ()
  "The same four IconButtons stacked, for CenteredVertical...WithFab.
VerticalFloatingToolbar's content, in upstream's order."
  (jetpacs-column
   (jetpacs-m3-floating-toolbar--action "person" "Person")
   (jetpacs-m3-floating-toolbar--action "edit" "Edit")
   (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
   (jetpacs-m3-floating-toolbar--action "more_vert" "MoreVert")
   :align "center"))

(defun jetpacs-m3-floating-toolbar--overflow-strip (vertical)
  "The Overflowing samples' five actions as a measuring overflow strip.
Download, Favorite, Add, Person and ArrowUpward render inline while
they fit inside the pill and fold into the more_vert menu at layout
time; VERTICAL picks `app_bar_column', the strip stood on end."
  (let ((items (list (jetpacs-app-bar-item "Download" "download"
                                           (jetpacs-m3-demo "Download"))
                     (jetpacs-app-bar-item "Favorite" "favorite"
                                           (jetpacs-m3-demo "Favorite"))
                     (jetpacs-app-bar-item "Add" "add"
                                           (jetpacs-m3-demo "Add"))
                     (jetpacs-app-bar-item "Person" "person"
                                           (jetpacs-m3-demo "Person"))
                     (jetpacs-app-bar-item "Upload" "arrow_upward"
                                           (jetpacs-m3-demo "Upload")))))
    (if vertical (jetpacs-app-bar-column items)
      (jetpacs-app-bar-row items))))

(defun jetpacs-m3-floating-toolbar--as-scaffold-fab ()
  "Upstream HorizontalFloatingToolbarAsScaffoldFabSample, in the fab slot.
Upstream hands the whole toolbar to `Scaffold(floatingActionButton =)'
with `FabPosition.End'; the wire's fab slot IS that parameter --
`RenderScaffold' passes the node straight to it and takes the End default
-- so the toolbar goes there.  The sample's subject is the hosting, and
this screen hosts it the same way.

The four IconButtons \(Person, Edit, Favorite, MoreVert) and the vibrant
Add FAB share one `surface': the fab slot takes ONE node and a scaffold
cannot nest inside a scaffold, so the pill and the FAB fused to its end
\(upstream's `floatingActionButton =') are composed here rather than asked
for.  primary_container is the role the wire can name for
vibrantFloatingToolbarColors.

Re-checked against the members that landed since: `floating_toolbar_fab'
at `floating_toolbar_placement' bottom_end would draw a REAL
HorizontalFloatingToolbar with a real fused FAB in about the same corner
-- but out of the fab slot this sample is named for, and still with no
way to ask for the vibrant palette, since the pill would then take M3's
standard colors that no member can override.  Trading the exact hosting
for an inexact one is not a win, so the composition stays."
  (jetpacs-surface
   (jetpacs-with-attrs
    (jetpacs-row
     (jetpacs-m3-floating-toolbar--action "person" "Person")
     (jetpacs-m3-floating-toolbar--action "edit" "Edit")
     (jetpacs-m3-floating-toolbar--action "favorite" "Favorite")
     (jetpacs-m3-floating-toolbar--action "more_vert" "MoreVert")
     (jetpacs-m3-floating-toolbar--primary "add" "Add" 56)
     :spacing 4 :align "center")
    :padding 8)
   :color "primary_container" :shape "circle" :elevation 6))

(jetpacs-m3-defcomponent "floating-toolbar"
  :name "Floating Toolbar"
  :description
  "A floating toolbar displays key actions above the content."
  :guidelines "https://m3.material.io/components/floating-toolbars"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#floatingtoolbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/FloatingToolbar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ExpandableHorizontalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--cluster-row)
    :floating-toolbar-orientation "horizontal"
    :floating-toolbar-placement "bottom_center"
    :floating-toolbar-expanded t)
   (jetpacs-m3-example
    "OverflowingHorizontalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--list-content
    :slots (list :floating-toolbar
                 (lambda () (jetpacs-m3-floating-toolbar--overflow-strip nil)))
    :floating-toolbar-orientation "horizontal")
   (jetpacs-m3-example
    "ScrollableHorizontalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--list-content
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--cluster-row)
    :floating-toolbar-orientation "horizontal"
    :floating-toolbar-placement "bottom_center"
    :floating-toolbar-expanded t
    :floating-toolbar-scroll t
    :floating-toolbar-exit-direction "bottom")
   (jetpacs-m3-example
    "ExpandableVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :unsupported
    "floating_toolbar_scroll is exitAlwaysScrollBehavior, which slides the whole pill off an edge; this sample shows the OTHER motion, the floatingToolbarVerticalNestedScroll that collapses the rail to its leading content as the list scrolls and expands it again. No member carries that, and floating_toolbar_expanded is a static value. The center-end vertical rail it collapses is authorable now, and ScrollableVerticalFloatingToolbarSample draws it; the collapse is the half that is missing.")
   (jetpacs-m3-example
    "OverflowingVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--list-content
    :slots (list :floating-toolbar
                 (lambda () (jetpacs-m3-floating-toolbar--overflow-strip t)))
    :floating-toolbar-orientation "vertical")
   (jetpacs-m3-example
    "ScrollableVerticalFloatingToolbarSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--list-content
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--cluster-column)
    :floating-toolbar-orientation "vertical"
    :floating-toolbar-placement "center_end"
    :floating-toolbar-expanded t
    :floating-toolbar-scroll t
    :floating-toolbar-exit-direction "end")
   (jetpacs-m3-example
    "HorizontalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--prose-content
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--actions-row)
    :scaffold (jetpacs-m3-floating-toolbar--with-fab-scaffold
               "floating-toolbar-h-collapsed"
               "horizontal" "bottom_end" "bottom"))
   (jetpacs-m3-example
    "CenteredHorizontalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--prose-content
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--actions-row)
    :floating-toolbar-orientation "horizontal"
    :floating-toolbar-placement "bottom_center"
    :floating-toolbar-expanded t
    :floating-toolbar-fab (jetpacs-m3-floating-toolbar--fused-fab)
    :floating-toolbar-scroll t
    :floating-toolbar-exit-direction "bottom")
   (jetpacs-m3-example
    "HorizontalFloatingToolbarAsScaffoldFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :slots (list :fab #'jetpacs-m3-floating-toolbar--as-scaffold-fab))
   (jetpacs-m3-example
    "VerticalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--prose-content
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--actions-column)
    :scaffold (jetpacs-m3-floating-toolbar--with-fab-scaffold
               "floating-toolbar-v-collapsed"
               "vertical" "bottom_end" "end"))
   (jetpacs-m3-example
    "CenteredVerticalFloatingToolbarWithFabSample"
    "Floating toolbar examples"
    :source jetpacs-m3-floating-toolbar--source
    :expressive t
    :build #'jetpacs-m3-floating-toolbar--prose-content
    :slots (list :floating-toolbar
                 #'jetpacs-m3-floating-toolbar--actions-column)
    :floating-toolbar-orientation "vertical"
    :floating-toolbar-placement "center_end"
    :floating-toolbar-expanded t
    :floating-toolbar-fab (jetpacs-m3-floating-toolbar--fused-fab)
    :floating-toolbar-scroll t
    :floating-toolbar-exit-direction "end")
   ))

(provide 'jetpacs-m3-floating-toolbar)
;;; jetpacs-m3-floating-toolbar.el ends here
