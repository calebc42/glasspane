;;; jetpacs-m3-navigation-suite-scaffold.el --- Catalog component: Navigation Suite Scaffold -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `NavigationSuiteScaffold' + Examples.kt
;; `NavigationSuiteScaffoldExamples' (2 examples).
;;
;; Both samples come from the material3-adaptive-navigation-suite
;; artifact, which M3-COMPONENT-LOOKUP does not list among the thirty
;; wrapped components -- NavigationBar and NavigationRail are both
;; "available, unwrapped", and `ShortNavigationBar' / `WideNavigationRail'
;; sit in its explicitly-unwrapped tail as "adaptive navigation
;; variants".
;;
;; What a NavigationSuiteScaffold IS, is the CHOICE between them.  Both
;; samples list the same three items (Songs, Artists, Playlists) and
;; then hand them to `NavigationSuiteScaffoldDefaults.navigationSuiteType
;; (currentWindowAdaptiveInfo())', which places them as a bottom
;; navigation bar on a phone and as a wide navigation rail on a wide
;; window; the body prints the type it resolved to, and the component's
;; own upstream description says the sample "is better experienced in a
;; resizable emulator or foldable device".
;;
;; Neither half of that is on the wire, and it is the same floor
;; `jetpacs-m3-adaptive' stands on.  The `scaffold' node (SPEC §17.6)
;; has exactly top_bar, body, bottom_bar, fab, floating_toolbar, drawer,
;; snackbar, snackbar_action and on_refresh -- fixed chrome slots, with
;; no navigation-suite slot, no suite type and no rail.  And nothing
;; ever tells Emacs the window size class: a Node tree is built with no
;; idea how wide the window it lands in is, so there is nothing for a
;; suite type to be computed FROM either.
;;
;; A row of three favorite icon buttons in this screen's `:bottom-bar'
;; slot would render, and would be exactly the lookalike the fidelity
;; rule forbids: it is what `jetpacs-m3-navigation-bar' already is, it
;; can never become the rail, and it would demonstrate none of the
;; adapting that is the entire subject here.  Two for two unsupported.
;;
;; The samples share a second miss past that floor.  Both hold a
;; `rememberNavigationSuiteScaffoldState' and offer a "Hide/show
;; navigation component" button calling `state.toggle()'; the scaffold
;; node has no visibility member for any of its slots, so a slot is
;; either authored into the tree or it is not there.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-navigation-suite-scaffold--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3-adaptive-navigation-suitesamples/src/main/java/androidx/compose/material3-adaptive-navigation-suite/samples/NavigationSuiteScaffoldSamples.kt"
  "Upstream NavigationSuiteScaffoldExampleSourceUrl.")

(jetpacs-m3-defcomponent "navigation-suite-scaffold"
  :name "Navigation Suite Scaffold"
  :description
  "The Navigation Suite Scaffold wraps the provided content and places the adequate provided navigation component on the screen according to the current NavigationSuiteType. \n\nNote: this sample is better experienced in a resizable emulator or foldable device."
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3-adaptive-navigation-suite/src/commonMain/kotlin/androidx/compose/material3/adaptive/navigation-suite/NavigationSuiteScaffold.kt"
  :examples
  (list
   (jetpacs-m3-example
    "NavigationSuiteScaffoldSample"
    "Navigation suite scaffold examples"
    :source jetpacs-m3-navigation-suite-scaffold--source
    :expressive t
    :unsupported
    "There is no navigation-suite node and no window-size-class message: the scaffold node's slots are the fixed top_bar, body, bottom_bar, fab, floating_toolbar and drawer, with no suite type and no navigation rail, and nothing on the wire ever tells Emacs how wide the window is, so the automatic swap between a bottom navigation bar and a wide navigation rail that this sample exists to demonstrate cannot be asked for.")
   (jetpacs-m3-example
    "NavigationSuiteScaffoldCustomConfigSample"
    "Navigation suite scaffold examples"
    :source jetpacs-m3-navigation-suite-scaffold--source
    :expressive t
    :unsupported
    "Neither half is on the wire: no message carries WindowWidthSizeClass or WindowHeightSizeClass to Emacs for this sample to branch on, and there is no navigation-suite node whose type it could then set to WideNavigationRailCollapsed, ShortNavigationBarMedium or WideNavigationRailExpanded, nor any member for the navigationItemVerticalArrangement that centers the items down the rail.")
   ))

(provide 'jetpacs-m3-navigation-suite-scaffold)
;;; jetpacs-m3-navigation-suite-scaffold.el ends here
