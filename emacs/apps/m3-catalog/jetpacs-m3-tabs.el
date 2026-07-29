;;; jetpacs-m3-tabs.el --- Catalog component: Tabs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Tabs' + Examples.kt
;; `TabsExamples' (12 examples), samples/TabSamples.kt.
;;
;; The `tabs' node carries items (each a {label, icon?}), a parallel
;; children array, initial, scrollable, pager_only, on_change and id.
;; The Companion renders it as TabRow or ScrollableTabRow above a
;; HorizontalPager, giving every Tab `text = Text(label)' and, when the
;; item names one, an icon.
;;
;; Three facts decide the triage.  (1) There is no tab-style member:
;; TabRow draws the full-width SecondaryIndicator -- the SECONDARY
;; style -- so the Secondary* samples recreate and their Primary*
;; twins, which exist beside them precisely to show PrimaryTabRow's
;; content-width indicator, cannot.  (2) The label always renders, so
;; an icon-only tab cannot be asked for.  (3) An item is a label and an
;; icon NAME, not a node, and there is no indicator member, so the four
;; Fancy* samples have nowhere to put the custom Tab content and custom
;; indicators they exist to demonstrate.
;;
;; TextAndIconTabs is the one sample that uses PrimaryTabRow and still
;; recreates: it is alone in the set in demonstrating a tab that
;; carries BOTH a title and an icon, and that pairing IS a tab_item.
;;
;; Upstream shows the selection as one Text below the row ("Secondary
;; tab 2 selected").  Here the selection lives in the pager, so each
;; index's sentence becomes that index's page.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-tabs--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TabSamples.kt"
  "Upstream TabsExampleSourceUrl.")

(defconst jetpacs-m3-tabs--primary-note
  "The tabs node has no tab-style member: scrollable picks TabRow or ScrollableTabRow and both draw the full-width secondary indicator, so PrimaryTabRow's content-width primary indicator cannot be requested from Emacs."
  "Why a Primary* sample whose Secondary* twin recreates is unsupported.")

(defconst jetpacs-m3-tabs--icon-only-note
  "A tab_item is {label, icon} and the Companion always renders the label in the Tab's text slot, so an icon-only tab is not expressible -- nor is the PlainTooltip that upstream needs to name it, TooltipBox being no node type."
  "Why the icon-only tab samples are unsupported.")

(defconst jetpacs-m3-tabs--indicator-note
  "The tabs node has no indicator member: a custom indicator drawn through Modifier.tabIndicatorOffset or tabIndicatorLayout is Compose drawing code, and the wire can only name the tab strip, never paint it."
  "Why every Fancy indicator sample is unsupported.")

(defconst jetpacs-m3-tabs--titles
  '("Tab 1" "Tab 2" "Tab 3 with lots of text")
  "The three titles upstream gives each non-scrolling text sample.")

(defconst jetpacs-m3-tabs--scrolling-titles
  '("Tab 1" "Tab 2" "Tab 3 with lots of text" "Tab 4" "Tab 5"
    "Tab 6 with lots of text" "Tab 7" "Tab 8" "Tab 9 with lots of text"
    "Tab 10")
  "The ten titles upstream gives each scrolling sample.")

(defun jetpacs-m3-tabs--page (text)
  "One pager page carrying TEXT, centered as upstream centers it."
  (jetpacs-with-attrs
   (jetpacs-column (jetpacs-text text :style "body") :align "center" :fill t)
   :padding 16))

(defun jetpacs-m3-tabs--pages (template count)
  "COUNT pages, page N reading TEMPLATE filled with N, counting from 1."
  (mapcar (lambda (n) (jetpacs-m3-tabs--page (format template n)))
          (number-sequence 1 count)))

(defun jetpacs-m3-tabs--secondary-text ()
  "Upstream SecondaryTextTabs: three text tabs in a SecondaryTabRow."
  (jetpacs-tabs
   (mapcar #'jetpacs-tab-item jetpacs-m3-tabs--titles)
   (jetpacs-m3-tabs--pages "Secondary tab %d selected"
                           (length jetpacs-m3-tabs--titles))
   :id "tabs-secondary-text"
   :on-change (jetpacs-m3-demo "Secondary tab selected")))

(defun jetpacs-m3-tabs--text-and-icon ()
  "Upstream TextAndIconTabs: each tab pairs a Favorite icon with a title."
  (jetpacs-tabs
   (mapcar (lambda (title) (jetpacs-tab-item title :icon "favorite"))
           jetpacs-m3-tabs--titles)
   (jetpacs-m3-tabs--pages "Text and icon tab %d selected"
                           (length jetpacs-m3-tabs--titles))
   :id "tabs-text-and-icon"
   :on-change (jetpacs-m3-demo "Text and icon tab selected")))

(defun jetpacs-m3-tabs--scrolling-secondary ()
  "Upstream ScrollingSecondaryTextTabs: ten tabs that scroll.
`scrollable' IS SecondaryScrollableTabRow: the Companion hands the
strip to ScrollableTabRow, which is what the sample is about."
  (jetpacs-tabs
   (mapcar #'jetpacs-tab-item jetpacs-m3-tabs--scrolling-titles)
   (jetpacs-m3-tabs--pages "Scrolling secondary tab %d selected"
                           (length jetpacs-m3-tabs--scrolling-titles))
   :scrollable t
   :id "tabs-scrolling-secondary"
   :on-change (jetpacs-m3-demo "Scrolling secondary tab selected")))

(jetpacs-m3-defcomponent "tabs"
  :name "Tabs"
  :description
  "Tabs organize content across different screens, data sets, and other interactions."
  :guidelines "https://m3.material.io/components/tabs"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#tab"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Tab.kt"
  :examples
  (list
   (jetpacs-m3-example
    "PrimaryTextTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported jetpacs-m3-tabs--primary-note)
   (jetpacs-m3-example
    "PrimaryIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported
    "Neither half is on the wire: a tab_item always renders its label, so there is no icon-only tab, and no member selects PrimaryTabRow's indicator.")
   (jetpacs-m3-example
    "SecondaryTextTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--secondary-text)
   (jetpacs-m3-example
    "SecondaryIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported jetpacs-m3-tabs--icon-only-note)
   (jetpacs-m3-example
    "TextAndIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--text-and-icon)
   (jetpacs-m3-example
    "LeadingIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported
    "There is no LeadingIconTab on the wire: a tab_item's icon always renders above its label, never leading it, and the item has no badge member for the \"999+\" BadgedBox this sample hangs on the title.")
   (jetpacs-m3-example
    "ScrollingPrimaryTextTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported jetpacs-m3-tabs--primary-note)
   (jetpacs-m3-example
    "ScrollingSecondaryTextTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--scrolling-secondary)
   (jetpacs-m3-example
    "FancyTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported
    "A tab_item is a label and an icon name, not a node: the custom Tab content this sample exists to show -- a Column holding a 10.dp colored Box above the title -- has nowhere on the wire to go.")
   (jetpacs-m3-example
    "FancyIndicatorTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported jetpacs-m3-tabs--indicator-note)
   (jetpacs-m3-example
    "FancyIndicatorContainerTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported
    "The tabs node has no indicator member, and nothing on the wire drives an Animatable: this sample is an indicator whose two edges spring to the selected tab at different stiffnesses.")
   (jetpacs-m3-example
    "ScrollingFancyIndicatorContainerTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :unsupported
    "Scrollable is on the wire and the animated custom indicator is not: the tabs node has no indicator member, so the only thing this sample adds to a scrolling row cannot be asked for.")
   ))

(provide 'jetpacs-m3-tabs)
;;; jetpacs-m3-tabs.el ends here
