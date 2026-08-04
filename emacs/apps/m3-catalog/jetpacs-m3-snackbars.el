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
;; `jetpacs-shell-notify', which RAISES it through `snackbar.show'
;; (SPEC 18.2.1) -- the message shows immediately in this screen's own
;; SnackbarHost, no re-push involved.  (An ungranted session falls back
;; to the queued next-push member, latest wins.)
;;
;; The other four are that sample plus one twist, and the twists ride
;; two different channels.  Duration is a property of the RAISE: the
;; indefinite sample's demo descriptor carries :duration "indefinite",
;; which is also what implies the trailing dismiss X -- such a snackbar
;; must always leave the user an exit.  The visible clamp is a property
;; of the HOST: `snackbar_max_lines' is a static member of the view's
;; scaffold and the host applies it to EVERY snackbar it shows, raised
;; or authored, so the multiline sample keeps its `:scaffold' plist
;; (Text semantics keep the whole string for a screen reader).
;; `snackbar_duration' remains the static twin for tree-authored
;; snackbars -- the custom sample's channel, covered by the goldens.
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
;; The coroutines sample rides the channel it was waiting for:
;; `snackbar.show' (SPEC 18.2.1) is a REQUEST whose reply carries how
;; the snackbar concluded, so each FAB tap counts a raise in Emacs,
;; shows "Snackbar # N" with "Action on N" in this screen's own host,
;; and the reply branches exactly like upstream's when(result) — the
;; component is complete.

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

(defvar jetpacs-m3-snackbars--coroutines-count 0
  "ScaffoldWithCoroutinesSnackbar's message counter.")

(puthash "snackbars-coroutines-show"
         (lambda ()
           (cl-incf jetpacs-m3-snackbars--coroutines-count)
           (let ((n jetpacs-m3-snackbars--coroutines-count))
             ;; The raise runs OUTSIDE the mutation's re-push: the request
             ;; completes when the snackbar leaves the screen, and the
             ;; branch on its result is exactly upstream's when(result).
             (run-at-time
              0 nil
              (lambda ()
                (condition-case err
                    (ebp-client-snackbar-show
                     (jetpacs-client-or-error)
                     (format "Snackbar # %d" n)
                     :action-label (format "Action on %d" n)
                     :callback
                     (lambda (result error)
                       (jetpacs-shell-notify
                        (cond (error "Snackbar failed")
                              ((equal result "action")
                               (format "Action on %d performed" n))
                              (t (format "Snackbar # %d dismissed" n)))
                        jetpacs-m3-owner)))
                  (error (message "jetpacs-m3: snackbar raise failed: %s"
                                  (jetpacs--error-label err))))))))
         jetpacs-m3-fn-registry)

(defun jetpacs-m3-snackbars--coroutines-fab ()
  "The coroutines sample's FAB: each tap raises through snackbar.show.
Upstream launches a coroutine, shows the snackbar, and branches on its
SnackbarResult; here the fn verb counts the raise and the reply drives
the same branch — a REAL result round trip, not a demo toast."
  (jetpacs-button "Show snackbar"
                  (jetpacs-m3-fn-action "snackbars-coroutines-show")
                  :variant "filled"))

(defun jetpacs-m3-snackbars--simple-fab ()
  "Upstream ScaffoldWithSimpleSnackbar's FAB, as this screen's FAB.
The text-only ExtendedFloatingActionButton reading \"Show snackbar\".
Its tap reaches Emacs and the message raises straight back through
`snackbar.show\' into the SnackbarHost this sample exists to show.
The click count upstream keeps in `remember\=' has no wire state to
live in, so the message stays \"Snackbar # 1\"."
  (jetpacs-button "Show snackbar" (jetpacs-m3-demo "Snackbar # 1")
                  :variant "filled"))

(defun jetpacs-m3-snackbars--indefinite-fab ()
  "The Indefinite sample's FAB: the raise carries the duration.
Upstream passes SnackbarDuration.Indefinite to showSnackbar; here the
demo descriptor carries :duration \"indefinite\" onto `snackbar.show\',
and the implied trailing dismiss X is the user's exit, exactly
upstream's withDismissAction = true."
  (jetpacs-button "Show snackbar"
                  (jetpacs-m3-demo "Snackbar # 1" "indefinite")
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
    :slots (list :fab #'jetpacs-m3-snackbars--indefinite-fab))
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
    :build #'jetpacs-m3-snackbars--simple-body
    :slots (list :fab #'jetpacs-m3-snackbars--coroutines-fab))
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
