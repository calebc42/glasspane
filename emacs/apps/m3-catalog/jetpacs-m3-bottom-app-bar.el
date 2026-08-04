;;; jetpacs-m3-bottom-app-bar.el --- Catalog component: Bottom App Bar -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `BottomAppBars' + Examples.kt
;; `BottomAppBarsExamples' (9 examples), samples/AppBarSamples.kt.
;;
;; A bottom app bar IS screen chrome, so every recreated sample here
;; claims the Example screen's own `:bottom-bar' slot (and, for
;; BottomAppBarWithFAB, its `:fab' slot) instead of drawing a nested
;; scaffold in the body -- see `jetpacs-m3-slot-keys'.  The slot takes
;; an ordinary node, so a bottom app bar is a `row' of icon buttons and
;; the samples' own icons and labels survive intact.
;;
;; TRIAGE.  Two things upstream demonstrates are not on the wire:
;;
;; * The exit-always SCROLL BEHAVIOR (the bar hiding as the body
;;   scrolls up, returning on the way down).  `scaffold' has no
;;   scroll-behavior member.  For ExitAlwaysBottomAppBar that behavior
;;   is the entire difference from BottomAppBarWithFAB, so nothing is
;;   left to recreate and it is unsupported.  For the four
;;   FlexibleBottomAppBar samples it is shared boilerplate: what makes
;;   them four separate catalog entries is the horizontalArrangement
;;   (SpaceAround / SpaceBetween / SpaceEvenly / the fixed one, plus a
;;   vibrant container color), and `row' carries exactly that in
;;   :arrange, :spacing and a `surface' color -- so those are
;;   recreated.
;;
;; * AppBarRow's OVERFLOW rides the `app_bar_row' node now: the six
;;   actions render inline while they fit and fold into the more_vert
;;   menu at MEASURE time -- a width decision the device makes per
;;   layout pass, which Emacs never sees and never needs to.
;;
;; Upstream wraps every action in a TooltipBox with a PlainTooltip
;; repeating its label; there is no tooltip node, and the label already
;; rides `:content-description', where a screen reader looks.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-bottom-app-bar--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/AppBarSamples.kt"
  "Upstream BottomAppBarsExampleSourceUrl.")

(defconst jetpacs-m3-bottom-app-bar--flexible-actions
  '(("arrow_back" "Back")
    ("arrow_forward" "Forward")
    ("add" "Add" filled)
    ("check" "Check")
    ("edit" "Edit"))
  "The five FlexibleBottomAppBar actions, upstream order.
Each entry is (ICON LABEL [FILLED]).  Upstream draws index 2, Add, as
a `FilledIconButton' 56dp wide and the rest as plain `IconButton's.")

(defun jetpacs-m3-bottom-app-bar--action (icon label &optional description)
  "One bottom-bar action: ICON, tapping which reports LABEL.
DESCRIPTION overrides LABEL as the content description, for the one
upstream action whose tooltip and contentDescription differ."
  (jetpacs-icon-button icon (jetpacs-m3-demo label)
                       :content-description (or description label)))

(defun jetpacs-m3-bottom-app-bar--filled-action (icon label)
  "Upstream\\='s FilledIconButton for ICON, reporting LABEL when tapped.
The `icon_button' node has no filled variant, but the container is not
what these samples demonstrate and it composes from wrapped nodes: a
`primary' surface clipped to a circle is the M3 filled container, and
Compose derives the icon\\='s `on_primary' color from it."
  (jetpacs-with-attrs
   (jetpacs-surface (jetpacs-m3-bottom-app-bar--action icon label)
                    :color "primary" :shape "circle")
   :width 56))

(cl-defun jetpacs-m3-bottom-app-bar--flexible-row (&key arrange spacing
                                                        centered)
  "The five FlexibleBottomAppBar actions as one row.
ARRANGE is the horizontalArrangement that is the only thing separating
the four Flexible samples.  CENTERED instead clusters the actions
between two weighted spacers — the ONLY way to get a fixed SPACING and
centering at once, because the Companion\\='s `horizontalArrange'
\(LayoutNodes.kt) reads `spacing' only when no `arrange' is set, so
naming both would silently discard the spacing."
  (let ((actions (mapcar
                  (lambda (spec)
                    (let ((icon (nth 0 spec))
                          (label (nth 1 spec)))
                      (if (nth 2 spec)
                          (jetpacs-m3-bottom-app-bar--filled-action icon label)
                        (jetpacs-m3-bottom-app-bar--action icon label))))
                  jetpacs-m3-bottom-app-bar--flexible-actions))
        (pad (lambda () (jetpacs-with-attrs (jetpacs-spacer) :weight 1))))
    (jetpacs-with-attrs
     (apply #'jetpacs-row
            (append (when centered (list (funcall pad)))
                    actions
                    (when centered (list (funcall pad)))
                    (list :arrange arrange :spacing spacing
                          :align "center" :fill t)))
     :padding 8)))

(defun jetpacs-m3-bottom-app-bar--simple ()
  "Upstream SimpleBottomAppBar: a bar of one Menu action."
  (jetpacs-with-attrs
   (jetpacs-row (jetpacs-m3-bottom-app-bar--action "menu" "Menu" "Menu button")
                :align "center")
   :padding 8))

(defun jetpacs-m3-bottom-app-bar--with-fab-actions ()
  "Upstream BottomAppBarWithFAB\\='s actions slot: Check and Edit."
  (jetpacs-with-attrs
   (jetpacs-row (jetpacs-m3-bottom-app-bar--action "check" "Check")
                (jetpacs-m3-bottom-app-bar--action "edit" "Edit")
                :align "center" :spacing 4)
   :padding 8))

(defun jetpacs-m3-bottom-app-bar--fab ()
  "Upstream BottomAppBarWithFAB\\='s floatingActionButton slot: Add."
  (jetpacs-m3-bottom-app-bar--action "add" "Add"))

(defun jetpacs-m3-bottom-app-bar--spaced-around ()
  "Upstream ExitAlwaysBottomAppBarSpacedAround: Arrangement.SpaceAround."
  (jetpacs-m3-bottom-app-bar--flexible-row :arrange "space_around"))

(defun jetpacs-m3-bottom-app-bar--spaced-between ()
  "Upstream ExitAlwaysBottomAppBarSpacedBetween: Arrangement.SpaceBetween."
  (jetpacs-m3-bottom-app-bar--flexible-row :arrange "space_between"))

(defun jetpacs-m3-bottom-app-bar--spaced-evenly ()
  "Upstream ExitAlwaysBottomAppBarSpacedEvenly: Arrangement.SpaceEvenly."
  (jetpacs-m3-bottom-app-bar--flexible-row :arrange "space_evenly"))

(defun jetpacs-m3-bottom-app-bar--fixed ()
  "Upstream ExitAlwaysBottomAppBarFixed.
BottomAppBarDefaults.FlexibleFixedHorizontalArrangement is a fixed
spacing, centered, rather than one distributed across the width."
  (jetpacs-m3-bottom-app-bar--flexible-row :centered t :spacing 8))

(defun jetpacs-m3-bottom-app-bar--fixed-vibrant ()
  "Upstream ExitAlwaysBottomAppBarFixedVibrant.
The fixed arrangement again, over the primaryContainer color the
sample sets as the bar\\='s containerColor."
  (jetpacs-surface (jetpacs-m3-bottom-app-bar--fixed)
                   :color "primary_container"))

(jetpacs-m3-defcomponent "bottom-app-bar"
  :name "Bottom App Bar"
  :description
  "A bottom app bar displays navigation and key actions at the bottom of mobile screens."
  :guidelines "https://m3.material.io/components/bottom-app-bars"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#bottomappbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/AppBar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SimpleBottomAppBar"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--simple))
   (jetpacs-m3-example
    "BottomAppBarWithFAB"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--with-fab-actions
                 :fab #'jetpacs-m3-bottom-app-bar--fab))
   (jetpacs-m3-example
    "BottomAppBarWithOverflow"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    ;; The app_bar_row node IS AppBarRow: inline while they fit, folded
    ;; into the more_vert menu at measure time.
    :slots (list :bottom-bar
                 (lambda ()
                   (jetpacs-app-bar-row
                    (list (jetpacs-app-bar-item "Back" "arrow_back"
                                                (jetpacs-m3-demo "Back"))
                          (jetpacs-app-bar-item "Forward" "arrow_forward"
                                                (jetpacs-m3-demo "Forward"))
                          (jetpacs-app-bar-item "Add" "add"
                                                (jetpacs-m3-demo "Add"))
                          (jetpacs-app-bar-item "Check" "check"
                                                (jetpacs-m3-demo "Check"))
                          (jetpacs-app-bar-item "Edit" "edit"
                                                (jetpacs-m3-demo "Edit"))
                          (jetpacs-app-bar-item "Favorite" "favorite"
                                                (jetpacs-m3-demo "Favorite")))))))
   (jetpacs-m3-example
    "ExitAlwaysBottomAppBar"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    ;; :bottom-bar-behavior "exit_always" IS exitAlwaysScrollBehavior —
    ;; the bar hides going up and returns coming down, riding a real M3
    ;; BottomAppBar — and :fab-position "end_overlay" rides the Add FAB
    ;; OVER it, the pairing this sample exists for.
    :build (lambda ()
             (apply #'jetpacs-column
                    (append
                     (cl-loop for i from 0 below 100
                              collect (jetpacs-with-attrs
                                       (jetpacs-text (format "Item %d" i))
                                       :pad (list :horizontal 16)))
                     (list :spacing 8 :fill t))))
    :slots (list :bottom-bar
                 (lambda ()
                   (jetpacs-row
                    (jetpacs-m3-bottom-app-bar--action "check" "Check")
                    (jetpacs-m3-bottom-app-bar--action "edit" "Edit")
                    :spacing 4))
                 :fab
                 (lambda ()
                   (jetpacs-button "Add" (jetpacs-m3-demo "Add")
                                   :icon "add" :variant "filled")))
    :scaffold (list :bottom-bar-behavior "exit_always"
                    :fab-position "end_overlay"))
   (jetpacs-m3-example
    "ExitAlwaysBottomAppBarSpacedAround"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--spaced-around))
   (jetpacs-m3-example
    "ExitAlwaysBottomAppBarSpacedBetween"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--spaced-between))
   (jetpacs-m3-example
    "ExitAlwaysBottomAppBarSpacedEvenly"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--spaced-evenly))
   (jetpacs-m3-example
    "ExitAlwaysBottomAppBarFixed"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--fixed))
   (jetpacs-m3-example
    "ExitAlwaysBottomAppBarFixedVibrant"
    "Bottom app bar examples"
    :source jetpacs-m3-bottom-app-bar--source
    :expressive t
    :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--fixed-vibrant))
   ))

(provide 'jetpacs-m3-bottom-app-bar)
;;; jetpacs-m3-bottom-app-bar.el ends here
