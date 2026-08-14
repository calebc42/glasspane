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
;; The `:on-refresh' slot passes the descriptor through raw now (it
;; used to fall into the node guard and die), so the gesture itself is
;; live on every recreated screen here.
;;
;; `refresh_indicator' fills the box's indicator slot (M3's spinner,
;; its LoadingIndicator sibling, or none), and `is_refreshing' is the
;; authored spinner state -- Emacs as the ViewModel, replacing the
;; optimistic self-clearing local flag.  One seam on the ViewModel
;; recreation: the demo verb cannot flip authored state, so its spinner
;; is authored off and what the member demonstrates here is WHO owns it
;; -- a real app's on_refresh handler re-pushes with t and clears it on
;; the data's arrival.
;;
;; The three still unsupported each need a channel, not a member: the
;; scaling indicator wants per-frame distanceFraction, the custom-state
;; sample implements the PullToRefreshState INTERFACE in Kotlin, and
;; the custom IndicatorBox is a composable the wire cannot carry.

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
  :builders (list #'jetpacs-scaffold)
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
    :slots (list :on-refresh (jetpacs-m3-demo "Trigger Refresh"))
    :build #'jetpacs-m3-pull-to-refresh-indicator--items)
   (jetpacs-m3-example
    "PullToRefreshWithLoadingIndicatorSample"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :expressive t
    :top-bar #'jetpacs-m3-pull-to-refresh-indicator--top-bar
    :slots (list :on-refresh (jetpacs-m3-demo "Trigger Refresh"))
    ;; PullToRefreshDefaults.LoadingIndicator in the indicator slot —
    ;; the one thing this sample adds to PullToRefreshSample.
    :scaffold (list :refresh-indicator "loading")
    :build #'jetpacs-m3-pull-to-refresh-indicator--items)
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
    :top-bar #'jetpacs-m3-pull-to-refresh-indicator--top-bar
    :slots (list :on-refresh (jetpacs-m3-demo "Trigger Refresh"))
    ;; Emacs IS the ViewModel: the authored flag replaces the
    ;; self-clearing local one.  The Commentary records the seam — the
    ;; demo verb cannot flip it, a real handler re-pushes with t.
    :scaffold (list :is-refreshing :json-false)
    :build #'jetpacs-m3-pull-to-refresh-indicator--items)
   (jetpacs-m3-example
    "PullToRefreshCustomIndicatorWithDefaultTransform"
    "Pull-to-refresh examples"
    :source jetpacs-m3-pull-to-refresh-indicator--source
    :unsupported jetpacs-m3-pull-to-refresh-indicator--indicator-note)
   ))

(provide 'jetpacs-m3-pull-to-refresh-indicator)
;;; jetpacs-m3-pull-to-refresh-indicator.el ends here
