;;; jetpacs-m3-search-bars.el --- Catalog component: Search bars -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `SearchBars' + Examples.kt
;; `SearchBarExamples' (3 examples), samples/SearchBarSamples.kt.
;;
;; SearchBar is one of the M3 components Jetpacs does not wrap --
;; docs/lookup-tables/M3-COMPONENT-LOOKUP.org lists it Available, not
;; Wrapped, and sketches a future `search_bar' wire type with
;; `on_query_change' and `suggestions' children.  There is no such node
;; today, and the README names SearchBar outright in its list of things
;; that are not node types.
;;
;; All three samples are that one component seen three ways, and what
;; each exists to demonstrate is the piece that is missing:
;; `SearchBarState' -- a field that stays Collapsed until it is tapped
;; and then animates into an expanded results surface, full-screen
;; (`ExpandedFullScreenSearchBar') or docked
;; (`ExpandedDockedSearchBar'), over the ten "Suggestion N" rows of
;; `SampleSearchResults'.  `text_input' is a plain OutlinedTextField
;; with no expanded state and no results slot, so drawing one with a
;; "Search" hint would be the lookalike the README warns against rather
;; than the component.
;;
;; TWO OF THEM ARE SCAFFOLD SAMPLES, and a scaffold sample normally
;; claims this screen's own slot instead of nesting a scaffold (see
;; `jetpacs-m3-slot-keys').  That escape does not apply here.  The
;; `top_bar' slot does take any node, so the Menu and Account icon
;; buttons standing around the field would travel intact -- but the
;; field between them would not, and the field is the subject.  The
;; proof is that the two differ from each other ONLY in how the
;; expansion is presented, full-screen versus docked to the input
;; field's measured width: recreated as top bars they would be the same
;; row of icon buttons twice, having dropped precisely what makes them
;; two catalog entries.
;;
;; A third gap rides along in both scaffold samples:
;; `SearchBarDefaults.enterAlwaysSearchBarScrollBehavior' hides the bar
;; as the body scrolls, and `scaffold' has no scroll-behavior member.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-search-bars--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/SearchBarSamples.kt"
  "Upstream SearchBarsExampleSourceUrl.")

(defconst jetpacs-m3-search-bars--node-note
  "There is no search_bar node type: M3-COMPONENT-LOOKUP lists SearchBar available but unwrapped, and the text_input node is a plain OutlinedTextField with no collapsed-to-expanded state and no slot for search results."
  "The wire fact every Search bars sample runs into.
Each example appends the SearchBarState presentation it is named for.")

(defconst jetpacs-m3-search-bars--scroll-note
  "  The scaffold node also has no scroll-behavior member, so enterAlwaysSearchBarScrollBehavior, which hides the bar as the body scrolls, cannot be requested from Emacs."
  "The second gap, shared by the two scaffold samples.")

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
    :unsupported
    (concat jetpacs-m3-search-bars--node-note
            "  This sample IS that state: a bar placeholdered \"Search...\" whose leading icon swaps from Search to a Back arrow as it grows into a full-screen surface of ten \"Suggestion N\" results."))
   (jetpacs-m3-example
    "FullScreenSearchBarScaffoldSample"
    "Search bar examples"
    :source jetpacs-m3-search-bars--source
    :expressive t
    :unsupported
    (concat jetpacs-m3-search-bars--node-note
            jetpacs-m3-search-bars--scroll-note
            "  The top_bar slot would carry this sample's Menu and Account icon buttons, but AppBarWithSearch is the search field standing between them, and the ExpandedFullScreenSearchBar it grows into is what the sample is named for."))
   (jetpacs-m3-example
    "DockedSearchBarScaffoldSample"
    "Search bar examples"
    :source jetpacs-m3-search-bars--source
    :expressive t
    :unsupported
    (concat jetpacs-m3-search-bars--node-note
            jetpacs-m3-search-bars--scroll-note
            "  All that separates this sample from the full-screen one is ExpandedDockedSearchBar: a results surface measured to the input field's own width, which is a Companion-side layout no node member can ask for."))
   ))

(provide 'jetpacs-m3-search-bars)
;;; jetpacs-m3-search-bars.el ends here
