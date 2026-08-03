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
;; The wire now carries the whole non-Fancy set: `style' picks
;; PrimaryTabRow's content-width indicator over the secondary
;; full-width one, an ABSENT label is the icon-only 48dp tab, a
;; `tab_item' takes `icon_position' leading (M3's LeadingIconTab, whose
;; `badge' then hangs on the TITLE, as upstream's own sample does) and
;; `tooltip' — the PlainTooltip M3 wants naming an icon-only tab for
;; sighted users; a screen reader hears the icon's fallback name either
;; way.  Eight of the twelve build.
;;
;; What remains is the Fancy* four: an item is a label and an icon
;; NAME, not a node, and there is no indicator member, so custom Tab
;; content and custom indicators have nowhere on the wire to go — two
;; of them further drive per-edge Animatables at differential spring
;; stiffnesses, which no declarative member could name.
;;
;; Upstream shows the selection as one Text below the row ("Secondary
;; tab 2 selected").  Here the selection lives in the pager, so each
;; index's sentence becomes that index's page.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-tabs--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TabSamples.kt"
  "Upstream TabsExampleSourceUrl.")

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

(defun jetpacs-m3-tabs--primary-text ()
  "Upstream PrimaryTextTabs: the same three titles under the primary style.
`:style \"primary\"' is PrimaryTabRow -- the content-width rounded
indicator that is the only thing separating this from its Secondary
twin."
  (jetpacs-tabs
   (mapcar #'jetpacs-tab-item jetpacs-m3-tabs--titles)
   (jetpacs-m3-tabs--pages "Primary tab %d selected"
                           (length jetpacs-m3-tabs--titles))
   :style "primary"
   :id "tabs-primary-text"
   :on-change (jetpacs-m3-demo "Primary tab selected")))

(defun jetpacs-m3-tabs--icon-only (id style)
  "The icon-only pair: three Favorite tabs under STYLE, as strip ID.
An ABSENT label is the 48dp icon-only tab (`label \"\"' would still fill
the text slot), and `:tooltip' is the PlainTooltip upstream anchors
above every one, reading \"Favorite\"."
  (jetpacs-tabs
   (cl-loop repeat 3
            collect (jetpacs-tab-item nil :icon "favorite"
                                      :tooltip "Favorite"))
   (jetpacs-m3-tabs--pages "Icon tab %d selected" 3)
   :style style
   :id id
   :on-change (jetpacs-m3-demo "Icon tab selected")))

(defun jetpacs-m3-tabs--leading-icon ()
  "Upstream LeadingIconTabs: icon before label, a 999+ badge on the title.
`:icon-position \"leading\"' is M3's LeadingIconTab, and its `:badge'
hangs on the TITLE -- upstream's own BadgedBox placement -- not on the
glyph, where the above-position tabs wear theirs."
  (jetpacs-tabs
   (mapcar (lambda (title)
             (jetpacs-tab-item title :icon "favorite"
                               :icon-position "leading"
                               :badge "999+"))
           jetpacs-m3-tabs--titles)
   (jetpacs-m3-tabs--pages "Leading icon tab %d selected"
                           (length jetpacs-m3-tabs--titles))
   :style "primary"
   :id "tabs-leading-icon"
   :on-change (jetpacs-m3-demo "Leading icon tab selected")))

(defun jetpacs-m3-tabs--scrolling-primary ()
  "Upstream ScrollingPrimaryTextTabs: ten tabs, primary indicator.
`:scrollable' is PrimaryScrollableTabRow once `:style' names primary."
  (jetpacs-tabs
   (mapcar #'jetpacs-tab-item jetpacs-m3-tabs--scrolling-titles)
   (jetpacs-m3-tabs--pages "Scrolling primary tab %d selected"
                           (length jetpacs-m3-tabs--scrolling-titles))
   :scrollable t
   :style "primary"
   :id "tabs-scrolling-primary"
   :on-change (jetpacs-m3-demo "Scrolling primary tab selected")))

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
    :build #'jetpacs-m3-tabs--primary-text)
   (jetpacs-m3-example
    "PrimaryIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build (lambda () (jetpacs-m3-tabs--icon-only "tabs-primary-icon"
                                                  "primary")))
   (jetpacs-m3-example
    "SecondaryTextTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--secondary-text)
   (jetpacs-m3-example
    "SecondaryIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build (lambda () (jetpacs-m3-tabs--icon-only "tabs-secondary-icon"
                                                  "secondary")))
   (jetpacs-m3-example
    "TextAndIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--text-and-icon)
   (jetpacs-m3-example
    "LeadingIconTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--leading-icon)
   (jetpacs-m3-example
    "ScrollingPrimaryTextTabs"
    "Tabs examples"
    :source jetpacs-m3-tabs--source
    :build #'jetpacs-m3-tabs--scrolling-primary)
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
