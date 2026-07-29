;;; jetpacs-m3-pull-to-refresh-indicator.el --- Catalog component: Pull-to-Refresh Indicator -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `PullToRefreshIndicators' + Examples.kt
;; `PullToRefreshExamples' (6 examples), samples/PullToRefreshSamples.kt.
;;
;; All six samples are the SAME screen -- a top bar titled "Title" with
;; an accessible Refresh action, over a fifteen-row list you pull on --
;; and differ only in the indicator and in who owns the refresh state.
;; That is the whole triage, because `scaffold.on_refresh' is the whole
;; of pull-to-refresh on the wire: ONE action descriptor, dispatched
;; after the gesture crosses the threshold.  There is no indicator
;; member, no `is_refreshing' member, and no message reporting
;; `PullToRefreshState.distanceFraction' back to Emacs (the Companion's
;; spinner self-clears; SPEC §17.6 says so outright, "there is no
;; completion signal").  So the plain sample is the component, and the
;; five that exist to REPLACE the indicator (LoadingIndicator, a custom
;; IndicatorBox), to SCALE it from the pull distance, to supply a
;; custom `PullToRefreshState', or to gate the screen on a hoisted
;; `isRefreshing' have no member to carry what they demonstrate.
;;
;; HARNESS NOTE.  Pull-to-refresh IS screen chrome, so PullToRefreshSample
;; should claim this Example screen's `:on-refresh' slot.  It cannot
;; today: `jetpacs-m3--example-slots' runs every slot but `:snackbar'
;; through `jetpacs-m3--guard', which demands a ROOT NODE, while
;; `jetpacs-scaffold' demands an action DESCRIPTOR for `:on-refresh' --
;; so the slot always degrades to an "empty_state" node and then signals.
;; `:on-refresh' needs the same exemption `:snackbar' already has.  Until
;; then this module recreates the sample's top bar and list, and its
;; live affordance is the one upstream itself calls "an accessible
;; alternative to trigger refresh".

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-pull-to-refresh-indicator--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/PullToRefreshSamples.kt"
  "Upstream PullToRefreshExampleSourceUrl.")

(defconst jetpacs-m3-pull-to-refresh-indicator--indicator-note
  "The scaffold has no indicator member: on_refresh carries an action descriptor and nothing else, so the pull-to-refresh indicator is whichever one the Companion draws, and neither the composable that replaces it nor the progress that composable reads can be chosen from Emacs."
  "Why a sample passing PullToRefreshBox its own `indicator' is unsupported.")

(defun jetpacs-m3-pull-to-refresh-indicator--top-bar (back)
  "Upstream PullToRefreshSample's TopAppBar: \"Title\" and Trigger Refresh.
The Refresh IconButton is upstream's own comment -- \"Provide an
accessible alternative to trigger refresh\" -- so it belongs to the
sample, not to the catalog chrome.  The leading arrow keeps the screen
navigable, as a custom `:top-bar' must."
  (jetpacs-row
   (jetpacs-m3-back-button back)
   (jetpacs-with-attrs (jetpacs-text "Title" :style "title") :weight 1)
   (jetpacs-icon-button "refresh"
                        (jetpacs-m3-demo "Trigger Refresh")
                        :content-description "Trigger Refresh")
   :align "center" :spacing 4))

(defun jetpacs-m3-pull-to-refresh-indicator--items ()
  "Upstream PullToRefreshSample's content: the fifteen rows you pull on.
Upstream is `items(itemCount) { ListItem { Text(\"Item ${itemCount -
it}\") } }' with itemCount 15, so the rows count DOWN from Item 15.
ListItem is not a node type and is not the subject here -- the list is
only the scrollable the gesture happens over -- so each row is the
text ListItem would have held."
  (apply #'jetpacs-lazy-column
         (append
          (mapcar (lambda (n)
                    (jetpacs-with-attrs
                     (jetpacs-text (format "Item %d" n))
                     :key (format "pull-to-refresh-indicator-item-%d" n)))
                  (number-sequence 15 1 -1))
          (list :spacing 8 :content-padding 8))))

(jetpacs-m3-defcomponent "pull-to-refresh-indicator"
  :name "Pull-to-Refresh Indicator"
  :description
  "Pull to refresh is a swipe gesture available at the beginning of lists, grid lists, and card collections where the most recent content appears "
  :guidelines ""
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#pulltorefreshcontainer"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/PullToRefresh.kt"
  :examples
  (list
   (jetpacs-m3-example
    "PullToRefreshSample"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :top-bar #'jetpacs-m3-pull-to-refresh-indicator--top-bar
    :build #'jetpacs-m3-pull-to-refresh-indicator--items)
   (jetpacs-m3-example
    "PullToRefreshWithLoadingIndicatorSample"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :expressive t
    :unsupported jetpacs-m3-pull-to-refresh-indicator--indicator-note)
   (jetpacs-m3-example
    "PullToRefreshScalingSample"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :unsupported
    "No wire message reports PullToRefreshState.distanceFraction back to Emacs, and no universal attribute scales a node, so the indicator that grows with the pull -- the whole subject of this sample -- cannot be driven from here.")
   (jetpacs-m3-example
    "PullToRefreshSampleCustomState"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :unsupported
    "There is no pull-to-refresh state on the wire: scaffold.on_refresh is one descriptor the Companion fires after the gesture, and the custom PullToRefreshState this sample implements (distanceFraction, animateToThreshold, animateToHidden, snapTo) has no member to carry it.")
   (jetpacs-m3-example
    "PullToRefreshViewModelSample"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :unsupported
    "The scaffold has no is_refreshing member and the Companion's spinner self-clears with no completion signal, so the ViewModel-held isRefreshing that this sample gates its list and its Trigger Refresh button on never reaches the wire.")
   (jetpacs-m3-example
    "PullToRefreshCustomIndicatorWithDefaultTransform"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :unsupported jetpacs-m3-pull-to-refresh-indicator--indicator-note)
   ))

(provide 'jetpacs-m3-pull-to-refresh-indicator)
;;; jetpacs-m3-pull-to-refresh-indicator.el ends here
