;;; jetpacs-m3-search-bars.el --- Catalog component: Search bars -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SearchBars' + Examples.kt
;; `SearchBarExamples' (3 examples), samples/SearchBarSamples.kt.
;;
;; All three are recreated on the `search_bar' node -- the 44th type,
;; which exists because of this module.  The node splits its state the
;; way the component does: the QUERY is device-held keyed on `:id'
;; (text_input's machinery, reported in state.changed), while the
;; Collapsed/Expanded state is Companion-local presentation with no wire
;; member at all, so a re-push cannot slam the bar shut under the user's
;; finger.  The `:variant' names where the expanded results surface goes
;; -- full_screen or docked to the field's own measured width -- which
;; is exactly what separated the two scaffold samples from each other.
;;
;; The results under every sample are SampleSearchResults: ten
;; "Suggestion N" ListItems, a Star leading, "Additional info"
;; supporting.  They ride as the node's CHILDREN, revealed only while
;; the bar is expanded.  Upstream's result tap writes the suggestion
;; back into the field and collapses the bar; the wire's query is
;; device-held and nothing short of an input reset writes it from
;; Emacs, so the tap here reports through the demo verb instead -- the
;; row is live, and what it cannot do is said rather than faked.
;;
;; The two scaffold samples put upstream's AppBarWithSearch in the
;; Example screen's own `:top-bar' slot (see `jetpacs-m3-slot-keys'):
;; the Menu and Account icon buttons stand around the field, each under
;; the plain tooltip upstream gives it, and the field between them is
;; the `search_bar' node at weight 1.
;; `SearchBarDefaults.enterAlwaysSearchBarScrollBehavior' -- the bar
;; hiding as the body scrolls -- maps to the scaffold's own
;; `:scroll-behavior "enter_always"' on the styled small bar.
;;
;; Two seams the recreation does not cross.  The renderer draws the
;; authored `:leading-icon' in BOTH states, so the Search glyph does not
;; swap to a Back arrow while expanded the way SampleLeadingIcon's does
;; -- collapse rides submit and the system back instead.  And upstream's
;; Menu/Account buttons slide away as the contained bar expands
;; (AnimatedVisibility on the SearchBarState); here the full-screen
;; expansion covers them, which reads the same but is not an animation
;; the wire can name.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-search-bars--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SearchBarSamples.kt"
  "Upstream SearchBarsExampleSourceUrl.")

(defun jetpacs-m3-search-bars--result (index)
  "Suggestion INDEX of upstream SampleSearchResults, as a tappable row.
A ListItem: Star leading, \"Suggestion INDEX\", \"Additional info\"
supporting.  Upstream's tap writes the suggestion into the field and
collapses the bar; the query is device-held, so the tap reports through
the demo verb instead."
  (let ((label (format "Suggestion %d" index)))
    (jetpacs-box
     (jetpacs-with-attrs
      (jetpacs-row
       (jetpacs-icon "star")
       (jetpacs-with-attrs
        (jetpacs-column
         (jetpacs-text label)
         (jetpacs-text "Additional info" :style "caption"
                       :color "on_surface_variant")
         :spacing 2)
        :weight 1)
       :spacing 16 :align "center")
      :pad (list :horizontal 16 :vertical 4))
     :on-tap (jetpacs-m3-demo label))))

(defun jetpacs-m3-search-bars--bar (id &optional variant)
  "The shared input field over its ten results, as node ID.
Hint \"Search\", a Search leading icon, upstream's tooltipped Mic as the
trailing icon name (the icon slot takes an identifier, not a node, so
the tooltip stays on the two buttons outside the bar).  VARIANT is where
the expansion goes; nil is the node's full_screen default."
  (apply #'jetpacs-search-bar id
         (append
          (cl-loop for i from 0 below 10
                   collect (jetpacs-m3-search-bars--result i))
          (list :hint "Search"
                :leading-icon "search"
                :trailing-icon "mic"
                :variant variant
                :on-search (jetpacs-m3-demo "Search submitted")))))

(defun jetpacs-m3-search-bars--simple ()
  "Upstream SimpleSearchBarSample: the bar alone, centered in the body.
Its expansion is ExpandedFullScreenSearchBar, the node's default."
  (jetpacs-m3-search-bars--bar "sb-simple"))

(defun jetpacs-m3-search-bars--tipped (icon label)
  "ICON as an IconButton under LABEL's plain tooltip.
Upstream wraps the Menu and Account buttons in a TooltipBox anchored
Above, the `tooltip' node's own default."
  (jetpacs-tooltip label
                   (jetpacs-icon-button icon (jetpacs-m3-demo label)
                                        :content-description label)))

(defun jetpacs-m3-search-bars--app-bar (id variant back)
  "Upstream AppBarWithSearch: Menu, the search field, Account.
The field is the `search_bar' node ID at weight 1, expanding as
VARIANT; BACK is the way off this screen, which a claimed `:top-bar'
must carry itself."
  (jetpacs-row
   (jetpacs-m3-back-button back)
   (jetpacs-m3-search-bars--tipped "menu" "Menu")
   (jetpacs-with-attrs (jetpacs-m3-search-bars--bar id variant) :weight 1)
   (jetpacs-m3-search-bars--tipped "account_circle" "Account")
   :align "center" :spacing 4 :fill t))

(defun jetpacs-m3-search-bars--content ()
  "The Scaffold content both scaffold samples share: \"Text 0\"..\"Text 99\".
A plain column: the Example screen body is already a scrolling column,
and a lazily-composed list has no bounded height inside one."
  (apply #'jetpacs-column
         (append (cl-loop for i from 0 below 100
                          collect (jetpacs-with-attrs
                                   (jetpacs-text (format "Text %d" i))
                                   :pad (list :horizontal 16)))
                 (list :spacing 8 :fill t))))

(jetpacs-m3-defcomponent "search-bars"
  :name "Search bars"
  :description
  "Search bars allow users to enter a keyword or phrase and get relevant information."
  :guidelines ""
  :docs ""
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/SearchBar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SimpleSearchBarSample"
    "Search bar examples"
    :source jetpacs-m3-search-bars--source
    :build #'jetpacs-m3-search-bars--simple)
   (jetpacs-m3-example
    "FullScreenSearchBarScaffoldSample"
    "Search bar examples"
    :source jetpacs-m3-search-bars--source
    :expressive t
    :top-bar (lambda (back)
               (jetpacs-m3-search-bars--app-bar "sb-full" "full_screen" back))
    :top-bar-style "small"
    :scroll-behavior "enter_always"
    :build #'jetpacs-m3-search-bars--content)
   (jetpacs-m3-example
    "DockedSearchBarScaffoldSample"
    "Search bar examples"
    :source jetpacs-m3-search-bars--source
    :expressive t
    :top-bar (lambda (back)
               (jetpacs-m3-search-bars--app-bar "sb-docked" "docked" back))
    :top-bar-style "small"
    :scroll-behavior "enter_always"
    :build #'jetpacs-m3-search-bars--content)
   ))

(provide 'jetpacs-m3-search-bars)
;;; jetpacs-m3-search-bars.el ends here
