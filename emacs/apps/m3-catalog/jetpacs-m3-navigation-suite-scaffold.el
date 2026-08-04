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
;; Both halves are on the wire now, and the recreation is the honest
;; shape of the thing: the CHOICE lives in Emacs.  SPEC 20.1.1's
;; `window.changed' reports {width_dp, height_dp, width_class,
;; height_class} — sent once after auth, again on rotation/fold/resize,
;; and mirrored in the welcome so the FIRST snapshot is already right —
;; and the `scaffold' node grew a `rail' slot on the start edge beside
;; the body.  Emacs reads the class, fills `bottom_bar' or `rail' from
;; the same three items, and re-pushes when the geometry changes (the
;; core's `jetpacs-m3--on-window-changed' hook), which is precisely the
;; swap NavigationSuiteScaffold performs on-device.  The rail slot
;; hosts the ordinary `navigation_rail' node, so the collapsed, the
;; expanded and the items-centered forms are its own variant, expanded
;; and arrangement members — no suite type ever crosses the wire.
;;
;; Live state: the shared selectedIndex rides the fn verb (tapping
;; Artists re-authors all three items in whichever container is up),
;; and the Hide-navigation toggle is a sample flag that simply omits
;; both slots.  Stated seams: upstream\='s ShortNavigationBarMedium is
;; recreated as the composed bottom bar (no navigation_bar node
;; exists, and its "medium" tallness is not carried), and the bar\='s
;; items swap favorite/favorite_border by hand where a real
;; NavigationBarItem would animate.
;;
;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-navigation-suite-scaffold--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3-adaptive-navigation-suitesamples/src/main/java/androidx/compose/material3-adaptive-navigation-suite/samples/NavigationSuiteScaffoldSamples.kt"
  "Upstream NavigationSuiteScaffoldExampleSourceUrl.")

(defconst jetpacs-m3-nav-suite--items '("Songs" "Artists" "Playlists")
  "Upstream's three destinations; every item wears the favorite heart.")

(jetpacs-m3-defselection jetpacs-m3-nav-suite--selected
    "nav-suite-select" 3
  "The shared selectedIndex, upstream verbatim.")

(defun jetpacs-m3-nav-suite--rail (expanded arrangement)
  "The rail form of the three destinations, selection live on the fn verb."
  (jetpacs-navigation-rail
   (cl-loop for label in jetpacs-m3-nav-suite--items
            for i from 0
            collect (jetpacs-rail-item
                     label "favorite"
                     (jetpacs-m3-selection-action "nav-suite-select" i)
                     :selected (jetpacs-bool
                                (= i jetpacs-m3-nav-suite--selected))))
   :variant "wide"
   :expanded (jetpacs-bool expanded)
   :arrangement arrangement))

(defun jetpacs-m3-nav-suite--bar ()
  "The bottom-bar form: three tappable icon+label columns, evenly spread."
  (apply #'jetpacs-row
         (append
          (cl-loop
           for label in jetpacs-m3-nav-suite--items
           for i from 0
           collect (jetpacs-box
                    (jetpacs-column
                     (jetpacs-icon (if (= i jetpacs-m3-nav-suite--selected)
                                       "favorite" "favorite_border")
                                   :color (if (= i jetpacs-m3-nav-suite--selected)
                                              "primary" "on_surface_variant"))
                     (jetpacs-text label :style "caption")
                     :align "center" :spacing 2)
                    :on-tap (jetpacs-m3-selection-action
                             "nav-suite-select" i)))
          (list :arrange "space_evenly" :align "center" :fill t))))

(defun jetpacs-m3-nav-suite--body (type)
  "Upstream's body: the current suite TYPE, visibility, and the toggle."
  (lambda ()
    (jetpacs-column
     (jetpacs-text (format "Current NavigationSuiteType: %s" type))
     (jetpacs-text (format "Navigation visible: %s"
                           (if (jetpacs-m3-flag "nav-suite-hidden") "no" "yes")))
     (jetpacs-button (if (jetpacs-m3-flag "nav-suite-hidden")
                         "Show navigation" "Hide navigation")
                     (jetpacs-m3-flag-action "nav-suite-hidden"))
     :align "center" :spacing 12)))

(defun jetpacs-m3-nav-suite--scaffold (type)
  "The suite slots for TYPE, honoring the hide toggle.
bar -> the bottom_bar slot; rail/rail_expanded -> the rail slot; the
centered variant carries arrangement center down the rail."
  (unless (jetpacs-m3-flag "nav-suite-hidden")
    (pcase type
      ("bar" (list :bottom-bar (jetpacs-m3-nav-suite--bar)))
      ("rail" (list :rail (jetpacs-m3-nav-suite--rail nil "top")))
      ("rail_expanded"
       (list :rail (jetpacs-m3-nav-suite--rail t "center")))
      ("rail_centered"
       (list :rail (jetpacs-m3-nav-suite--rail nil "center"))))))

(defun jetpacs-m3-nav-suite--auto-type ()
  "NavigationSuiteScaffoldDefaults.navigationSuiteType, on our classes:
compact width is the navigation bar, anything wider the collapsed rail."
  (if (equal (jetpacs-m3-window-class :width) "compact") "bar" "rail"))

(defun jetpacs-m3-nav-suite--custom-type ()
  "The custom sample's own branching, quoted from upstream: a compact
HEIGHT takes the medium bar, an expanded width the expanded rail, and
compact/medium widths the collapsed rail — items centered down it."
  (cond ((equal (jetpacs-m3-window-class :height) "compact") "bar")
        ((equal (jetpacs-m3-window-class :width) "expanded") "rail_expanded")
        (t "rail_centered")))

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
    :build (lambda ()
             (funcall (jetpacs-m3-nav-suite--body
                       (jetpacs-m3-nav-suite--auto-type))))
    :scaffold (lambda ()
                (jetpacs-m3-nav-suite--scaffold
                 (jetpacs-m3-nav-suite--auto-type))))
   (jetpacs-m3-example
    "NavigationSuiteScaffoldCustomConfigSample"
    "Navigation suite scaffold examples"
    :source jetpacs-m3-navigation-suite-scaffold--source
    :expressive t
    :build (lambda ()
             (funcall (jetpacs-m3-nav-suite--body
                       (jetpacs-m3-nav-suite--custom-type))))
    :scaffold (lambda ()
                (jetpacs-m3-nav-suite--scaffold
                 (jetpacs-m3-nav-suite--custom-type))))
   ))

(provide 'jetpacs-m3-navigation-suite-scaffold)
;;; jetpacs-m3-navigation-suite-scaffold.el ends here
