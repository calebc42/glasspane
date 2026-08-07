;;; jetpacs-m3-badge.el --- Catalog component: Badge -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Badge' + Examples.kt
;; `BadgeExamples' (1 examples).
;;
;; The one sample puts a `BadgedBox' on each item of a `NavigationBar':
;; a bare dot, then "8", then "999+".  Both halves are on the wire.  The
;; badge itself is the `icon_button' `badge' member (§17.4, the
;; BadgedBox mapping in WIDGET-REFERENCE), and an empty label is the
;; attention dot; the NavigationBar host is a scaffold `bottom_bar' of
;; three icon buttons, which is what the README prescribes for a
;; navigation bar and what a three-destination bottom bar is for.  So
;; the sample claims this Example screen's own bottom-bar slot.
;;
;; One detail does NOT survive: upstream gives each Badge its own
;; `semantics { contentDescription }' ("New notification", "8 new
;; notifications") alongside the icon's own "Favorite".  An icon button
;; carries a single `content_description', so the icon keeps it and the
;; badge's sentence rides the tap instead.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-badge--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/BadgeSamples.kt"
  "Upstream BadgeExampleSourceUrl.")

(defun jetpacs-m3-badge--item (badge description)
  "One NavigationBarItem: a Star icon wearing BADGE.
DESCRIPTION is the badge's upstream semantics string, which the tap
reports because an icon button has only the icon's own
`content_description'.

Two constructions, because the renderers differ.  A LABELLED badge is
the `icon_button' `badge' member, which is a real BadgedBox
\(InputNodes.kt).  The BARE DOT is not: that member is guarded on
`badge.isNotEmpty()', so an empty string silently renders a plain star.
The dot lives on the `badge' NODE (RenderBadge draws an empty `Badge()'
over its children), which is not tappable — so it rides inside a `box'
that carries the tap."
  (if (string-empty-p badge)
      (jetpacs-box
       (jetpacs-badge badge
                      :children (list (jetpacs-icon
                                       "star"
                                       :content-description "Favorite")))
       :on-tap (jetpacs-m3-demo description))
    (jetpacs-icon-button "star" (jetpacs-m3-demo description)
                         :content-description "Favorite"
                         :badge badge)))

(defun jetpacs-m3-badge--navigation-bar ()
  "Upstream NavigationBarItemWithBadge, as this screen's bottom bar.
Three NavigationBarItems, each a BadgedBox around Icons.Filled.Star:
an empty Badge (the attention dot), then \"8\", then \"999+\"."
  (jetpacs-row
   (jetpacs-m3-badge--item "" "New notification")
   (jetpacs-m3-badge--item "8" "8 new notifications")
   (jetpacs-m3-badge--item "999+" "999+ new notifications")
   :arrange "space_evenly" :align "center" :fill t))

(jetpacs-m3-defcomponent "badge"
  :builders (list #'jetpacs-badge)
  :name "Badge"
  :description
  "A badge can contain dynamic information, such as the presence of a new notification or a number of pending requests. Badges can be icon only or contain a short text."
  :guidelines "https://m3.material.io/components/badge"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#badge"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Badge.kt"
  :examples
  (list
   (jetpacs-m3-example
    "NavigationBarItemWithBadge"
    "Badge examples"
    :source jetpacs-m3-badge--source
    :slots (list :bottom-bar #'jetpacs-m3-badge--navigation-bar))
   ))

(provide 'jetpacs-m3-badge)
;;; jetpacs-m3-badge.el ends here
