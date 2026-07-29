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
;; The permanent and dismissible samples do not, because that one wire
;; member names ONE drawer: there is no flavor member on the scaffold,
;; and neither a sheet standing open beside the body forever nor a sheet
;; that shoves the body sideways with no scrim can be asked for.
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

(defun jetpacs-m3-navigation-drawer--item (icon label selected)
  "One NavigationDrawerItem: ICON beside LABEL, filled when SELECTED.
There is no drawer-item node, and none is needed: the item is an icon
and a text in a tappable full-height pill, and its selected container is
`secondaryContainer' in M3, which is the `:bg' universal attribute on
the pill.  Tapping selects upstream (and closes the drawer); here it
reports, like every other recreated handler."
  (jetpacs-with-attrs
   (jetpacs-box
    (jetpacs-with-attrs
     (jetpacs-row (jetpacs-icon icon)
                  (jetpacs-text label)
                  :spacing 12 :align "center" :fill t)
     :pad (list :horizontal 16 :vertical 12))
    :on-tap (jetpacs-m3-demo label))
   :key (concat "navigation-drawer-" icon)
   :bg (and selected "secondary_container")
   :corner 28))

(defun jetpacs-m3-navigation-drawer--sheet ()
  "The ModalDrawerSheet of upstream ModalNavigationDrawerSample.
A vertically scrolling Column, a 12dp Spacer, then the 18 items, the
first (`items[0]', AccountCircle) selected."
  (let ((selected (cdr (car jetpacs-m3-navigation-drawer--items))))
    (apply #'jetpacs-column
           (append
            (list (jetpacs-with-attrs (jetpacs-spacer) :height 12))
            (mapcar (lambda (cell)
                      (jetpacs-m3-navigation-drawer--item
                       (car cell) (cdr cell) (equal (cdr cell) selected)))
                    jetpacs-m3-navigation-drawer--items)
            (list :spacing 4 :scroll t)))))

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
    :unsupported
    "The scaffold drawer member is a ModalNavigationDrawer with a scrim and nothing else: there is no variant member asking for a PermanentDrawerSheet, the 240dp column that stands open beside the body with no drawer state at all, which is the only thing this sample adds to the modal one.")
   (jetpacs-m3-example
    "DismissibleNavigationDrawerSample"
    "Navigation drawer examples"
    :source jetpacs-m3-navigation-drawer--source
    :unsupported
    "The scaffold drawer member is a ModalNavigationDrawer with a scrim and nothing else: a DismissibleDrawerSheet instead pushes the body aside and leaves it live and scrimless, and no wire member selects that drawer.")
   ))

(provide 'jetpacs-m3-navigation-drawer)
;;; jetpacs-m3-navigation-drawer.el ends here
