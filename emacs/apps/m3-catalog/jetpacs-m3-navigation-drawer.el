;;; jetpacs-m3-navigation-drawer.el --- Catalog component: Navigation drawer -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `NavigationDrawer' + Examples.kt
;; `NavigationDrawerExamples' (3 examples), samples/DrawerSamples.kt.
;;
;; All three samples build the SAME sheet -- a scrolling column of 18
;; NavigationDrawerItems, one per Icons.Default destination, the first
;; selected -- and differ only in which drawer HOSTS it.  That host is
;; the whole subject of each, so the triage is decided by it alone.
;;
;; M3-COMPONENT-LOOKUP lists NavigationDrawer as wrapped, and the
;; scaffold `drawer' member is exactly ModalNavigationDrawer +
;; ModalDrawerSheet (SPEC §17.6): a sheet over a scrim, opened by a
;; hamburger and closed by tapping the scrim.  So the modal sample
;; claims this Example screen's own `drawer' slot -- a Node tree cannot
;; nest a scaffold -- and gets its sheet back verbatim.
;;
;; The PERMANENT sample needs no drawer slot at all, which is what this
;; module first got wrong.  `PermanentNavigationDrawer' holds no
;; `DrawerState', draws no scrim and offers no hamburger: it IS a Row of
;; (240dp sheet, content).  A `row' of a `surface' and a weighted
;; `column' is that, exactly, out of nodes the wire already carries.
;;
;; The DISMISSIBLE sample still cannot be asked for: its sheet shoves
;; the body sideways and leaves it live and scrimless, driven by a
;; `DrawerState' the wire has no member for, and the one `drawer' member
;; names ONE drawer with no flavor to select.
;;
;; NavigationDrawerItem is not a node type, but nothing in it is missing
;; from the sheet's node content: it is an icon beside a label in a
;; tappable pill, and the M3 selected item IS a `secondaryContainer'
;; fill on that pill, which `:bg' and `:corner' put on the wire.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-navigation-drawer--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/DrawerSamples.kt"
  "Upstream NavigationDrawerExampleSourceUrl.")

(defconst jetpacs-m3-navigation-drawer--items
  '(("account_circle" . "AccountCircle")
    ("bookmarks" . "Bookmarks")
    ("calendar_month" . "CalendarMonth")
    ("dashboard" . "Dashboard")
    ("email" . "Email")
    ("favorite" . "Favorite")
    ("group" . "Group")
    ("headphones" . "Headphones")
    ("image" . "Image")
    ("join_full" . "JoinFull")
    ("keyboard" . "Keyboard")
    ("laptop" . "Laptop")
    ("map" . "Map")
    ("navigation" . "Navigation")
    ("outbox" . "Outbox")
    ("push_pin" . "PushPin")
    ("qr_code" . "QrCode")
    ("radio" . "Radio"))
  "The 18 drawer destinations every sample in DrawerSamples.kt lists.
Each cell is (ICON . LABEL).  Upstream holds a list of `ImageVector's
and labels each item `item.name.substringAfterLast(\".\")', so the label
is the icon's own CamelCase name -- reproduced here literally, beside
the snake_case wire name of the same icon.")

(defun jetpacs-m3-navigation-drawer--item (prefix icon label selected)
  "One NavigationDrawerItem: ICON beside LABEL, filled when SELECTED.
There is no drawer-item node, and none is needed: the item is an icon
and a text in a tappable full-height pill, and its selected container is
`secondaryContainer' in M3, which is the `:bg' universal attribute on
the pill.  Tapping selects upstream (and closes the drawer); here it
reports, like every other recreated handler.

PREFIX namespaces the `:key'.  A §16.1 `key' is presentation identity
scoped to its parent, not a document-unique `id' (only `:id' is
collected by `jetpacs--collect-node-ids'), so two sheets could legally
share one -- but the modal and permanent sheets are different parents on
different screens, and distinct prefixes keep them independently
reconcilable."
  (jetpacs-with-attrs
   (jetpacs-box
    (jetpacs-with-attrs
     (jetpacs-row (jetpacs-icon icon)
                  (jetpacs-text label)
                  :spacing 12 :align "center" :fill t)
     :pad (list :horizontal 16 :vertical 12))
    :on-tap (jetpacs-m3-demo label))
   :key (concat prefix "-" icon)
   :bg (and selected "secondary_container")
   :corner 28))

(defun jetpacs-m3-navigation-drawer--items-column (prefix &rest options)
  "The 12dp Spacer then the 18 items, the first selected, keyed by PREFIX.
OPTIONS are appended to the `jetpacs-column' call.  Every sample in
DrawerSamples.kt builds this same column; only its host differs."
  (let ((selected (cdr (car jetpacs-m3-navigation-drawer--items))))
    (apply #'jetpacs-column
           (append
            (list (jetpacs-with-attrs (jetpacs-spacer) :height 12))
            (mapcar (lambda (cell)
                      (jetpacs-m3-navigation-drawer--item
                       prefix (car cell) (cdr cell)
                       (equal (cdr cell) selected)))
                    jetpacs-m3-navigation-drawer--items)
            options))))

(defun jetpacs-m3-navigation-drawer--sheet ()
  "The ModalDrawerSheet of upstream ModalNavigationDrawerSample.
A vertically scrolling Column, a 12dp Spacer, then the 18 items, the
first (`items[0]', AccountCircle) selected."
  (jetpacs-m3-navigation-drawer--items-column
   "navigation-drawer-modal" :spacing 4 :scroll t))

(defun jetpacs-m3-navigation-drawer--dismissible-sheet ()
  "The DismissibleDrawerSheet of the Dismissible sample — same 18 items."
  (jetpacs-m3-navigation-drawer--items-column
   "navigation-drawer-dismissible" :spacing 4 :scroll t))

(defun jetpacs-m3-navigation-drawer--permanent ()
  "Upstream PermanentNavigationDrawerSample.
`PermanentNavigationDrawer' IS a Row of (sheet, content) with no
`DrawerState', no scrim and no hamburger -- so unlike its two siblings
this sample never wanted the scaffold's `drawer' slot, and every piece
of it is on the wire: a `row', a `surface' whose omitted shape is the
RectangleShape `PermanentDrawerSheet' draws, `:width 240', and
`:weight 1' for the content beside it.

The sheet column deliberately does NOT carry `:scroll t'.  The Example
screen already wraps the body in a scrolling column, and a
`verticalScroll' inside a `verticalScroll' is measured with an infinite
maximum height and throws, blanking the surface; the outer scroll
already carries the 18 items."
  (jetpacs-row
   (jetpacs-with-attrs
    (jetpacs-surface
     (jetpacs-m3-navigation-drawer--items-column
      "navigation-drawer-permanent" :spacing 4)
     :color "surface")
    :width 240)
   (jetpacs-with-attrs
    (jetpacs-column (jetpacs-text "Application content")
                    :align "center" :fill t)
    :weight 1 :padding 16)
   :align "top" :fill t))

(jetpacs-m3-defcomponent "navigation-drawer"
  :name "Navigation drawer"
  :description
  "Navigation drawers provide ergonomic access to destinations in an app."
  :guidelines "https://m3.material.io/components/navigation-drawer"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#navigationdrawer"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/NavigationDrawer.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ModalNavigationDrawerSample"
    "Navigation drawer examples"
    :source jetpacs-m3-navigation-drawer--source
    :slots (list :drawer #'jetpacs-m3-navigation-drawer--sheet))
   (jetpacs-m3-example
    "PermanentNavigationDrawerSample"
    "Navigation drawer examples"
    :source jetpacs-m3-navigation-drawer--source
    :build #'jetpacs-m3-navigation-drawer--permanent)
   (jetpacs-m3-example
    "DismissibleNavigationDrawerSample"
    "Navigation drawer examples"
    :source jetpacs-m3-navigation-drawer--source
    ;; :drawer-variant "dismissible" selects DismissibleNavigationDrawer
    ;; around the SAME drawer node: it pushes the body aside and leaves
    ;; it live and scrimless, which is the whole delta from the modal
    ;; sample.  The hamburger the Companion synthesizes is the way in.
    :build (lambda ()
             (jetpacs-column
              (jetpacs-text "Swipe from the edge or tap the menu icon")
              :align "center" :fill t))
    :slots (list :drawer #'jetpacs-m3-navigation-drawer--dismissible-sheet)
    :scaffold (list :drawer-variant "dismissible"))
   ))

(provide 'jetpacs-m3-navigation-drawer)
;;; jetpacs-m3-navigation-drawer.el ends here
