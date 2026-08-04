;;; jetpacs-m3-snackbars.el --- Catalog component: Snackbars -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `Snackbars' + Examples.kt
;; `SnackbarsExamples' (5 examples), samples/ScaffoldSamples.kt.
;;
;; All five are the same Scaffold: a SnackbarHost, an extended FAB
;; reading "Show snackbar", and one line of body text.  A snackbar is
;; screen chrome -- the wire spells it `scaffold.snackbar' (SPEC 17.6,
;; and the Snackbar/SnackbarHost rows of M3-COMPONENT-LOOKUP) -- and a
;; Node tree cannot nest a scaffold, so the FAB claims THIS Example
;; screen's own fab slot.
;;
;; The snackbar itself is not authored into the tree: the FAB's tap
;; descriptor reaches Emacs and `jetpacs-m3-demo' hands the message to
;; `jetpacs-shell-notify', which queues it, latest wins.
;;
;; That message really does arrive as `scaffold.snackbar' now, and for
;; a while it did not.  `jetpacs-shell-notify' injected the queued
;; string only when the pushed spec's `:t' was "scaffold", and a
;; `jetpacs-chrome' app is a `multi_view' whose VIEWS are the scaffolds
;; -- so no chrome app in the product ever found its own slot and every
;; snackbar in Jetpacs degraded to a toast.  The injection now targets
;; the view being shown, so ScaffoldWithSimpleSnackbar draws the
;; SnackbarHost it exists to show.
;;
;; The other four are that sample plus one twist.  Two of the twists
;; are members now: `snackbar_duration' (indefinite implies the
;; trailing dismiss X -- such a snackbar must always leave the user an
;; exit) and `snackbar_max_lines' (the visible clamp; Text semantics
;; keep the whole string for a screen reader).  Both are STATIC members
;; of the view's scaffold, so the Example screen's own `:scaffold'
;; plist carries them and the notify-injected message wears them when
;; it lands.
;;
;; The custom-host sample is a member now too: `snackbar_content' is a
;; node drawn in place of the whole Snackbar face while the HOST keeps
;; M3's animation, timing and dismissal, and `button.color' recolors the
;; text action.  The per-raise error alternation is module state on the
;; fn verb: each FAB tap increments the count in Emacs and the next
;; snapshot re-authors both the message and the face, odd raises styled
;; as errors exactly like upstream's isError.  Two seams stated on the
;; builder: the error action's errorContainer FILL is not carried
;; (color recolors content only), and the face replaces M3's Snackbar
;; container, so the recreation draws its own inverse_surface pill.
;;
;; The one still out of reach needs a channel, not a member: a
;; SnackbarResult reported back for the coroutines sample.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-snackbars--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/ScaffoldSamples.kt"
  "Upstream SnackbarsExampleSourceUrl.")

(defvar jetpacs-m3-snackbars--custom-count 0
  "ScaffoldWithCustomSnackbar's clickCount: odd raises are errors.")

(puthash "snackbars-custom-show"
         (lambda () (cl-incf jetpacs-m3-snackbars--custom-count))
         jetpacs-m3-fn-registry)

(defun jetpacs-m3-snackbars--custom-fab ()
  "The custom sample's FAB: each tap counts a raise through the fn verb.
Upstream keeps clickCount in `remember\\='; here the count is module
state, so the alternating error styling is Emacs re-authoring the face."
  (jetpacs-button "Show snackbar"
                  (jetpacs-m3-fn-action "snackbars-custom-show")
                  :variant "filled"))

(defun jetpacs-m3-snackbars--custom-scaffold ()
  "The custom sample's LIVE scaffold: message + authored snackbar face.
Nothing before the first tap; after it, the bordered face upstream draws
in its SnackbarHost lambda -- the 2dp secondary border, 12dp gap, the
inverse_surface pill, and the text action colored error on odd raises
(upstream's isError) or inverse_primary otherwise.  Seams: the error
action's errorContainer FILL is not carried (button color recolors
content only), and the authored face replaces M3's Snackbar chrome, so
the pill here is its own surface."
  (let ((n jetpacs-m3-snackbars--custom-count))
    (when (> n 0)
      (let* ((error-p (= 1 (% n 2)))
             (msg (format "Snackbar # %d" n)))
        (list
         :snackbar msg
         :snackbar-content
         (jetpacs-with-attrs
          (jetpacs-surface
           (jetpacs-with-attrs
            (jetpacs-row
             (jetpacs-with-attrs
              (jetpacs-text msg :color "inverse_on_surface")
              :weight 1)
             (jetpacs-button "Action" (jetpacs-m3-demo "Action")
                             :variant "text"
                             :color (if error-p "error" "inverse_primary"))
             :align "center" :spacing 8)
            :padding 12)
           :color "inverse_surface" :shape "rounded_small")
          :border (list :width 2 :color "secondary") :pad 12))))))

(defun jetpacs-m3-snackbars--simple-fab ()
  "Upstream ScaffoldWithSimpleSnackbar's FAB, as this screen's FAB.
The text-only ExtendedFloatingActionButton reading \"Show snackbar\".
Its tap reaches Emacs, which queues the message; the next push carries
it as the scaffold snackbar member of the view being shown, which is the
SnackbarHost this sample exists to show.  The click count upstream keeps
in `remember\=' has no wire state to live in, so the message stays
\"Snackbar # 1\"."
  (jetpacs-button "Show snackbar" (jetpacs-m3-demo "Snackbar # 1")
                  :variant "filled"))

(defun jetpacs-m3-snackbars--long-fab ()
  "The Multiline sample's FAB: its message is upstream's longMessage.
The clamp is the scaffold's `:snackbar-max-lines', not the string."
  (jetpacs-button "Show snackbar"
                  (jetpacs-m3-demo
                   (concat "very very very very very very very very very "
                           "very long message"))
                  :variant "filled"))

(defun jetpacs-m3-snackbars--simple-body ()
  "Upstream ScaffoldWithSimpleSnackbar's content: \"Body content\".
The Example screen already centers its body, which is what the
fillMaxSize/wrapContentSize modifier pair does upstream."
  (jetpacs-text "Body content"))

(jetpacs-m3-defcomponent "snackbars"
  :name "Snackbars"
  :description
  "Snackbars provide brief messages about app processes at the bottom of the screen."
  :guidelines "https://m3.material.io/components/snackbars"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#snackbar"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Snackbar.kt"
  :examples
  (list
   (jetpacs-m3-example
    "ScaffoldWithSimpleSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--simple-fab))
   (jetpacs-m3-example
    "ScaffoldWithIndefiniteSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--simple-fab)
    ;; SnackbarDuration.Indefinite; the implied dismiss X is the user's
    ;; exit, exactly upstream's withDismissAction = true.
    :scaffold (list :snackbar-duration "indefinite"))
   (jetpacs-m3-example
    "ScaffoldWithCustomSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--custom-fab)
    :scaffold #'jetpacs-m3-snackbars--custom-scaffold)
   (jetpacs-m3-example
    "ScaffoldWithCoroutinesSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :unsupported
    "This sample exists to route a snackbar through a business-logic layer and then branch on its SnackbarResult, and the wire reports no such result: nothing signals SnackbarResult.Dismissed, and the scaffold snackbar_action that would carry \"Action on 1\" is a static member of the pushed tree, never something the tap that raises a snackbar can attach to it.")
   (jetpacs-m3-example
    "ScaffoldWithMultilineSnackbar"
    "Snackbars examples"
    :source jetpacs-m3-snackbars--source
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--long-fab)
    ;; The two lines the Material spec recommends; the ellipsis is
    ;; visual only, the accessible value stays whole.
    :scaffold (list :snackbar-max-lines 2))
   ))

(provide 'jetpacs-m3-snackbars)
;;; jetpacs-m3-snackbars.el ends here
