;;; jetpacs-m3-text-fields.el --- Catalog component: Text fields -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `TextFields' + Examples.kt
;; `TextFieldsExamples' (14 examples), samples/TextFieldSamples.kt.
;;
;; The `text_input' node carries id, value, hint, label, on_change,
;; on_submit, single_line, min_lines, max_lines, monospace, syntax,
;; password, keyboard, autofocus, clear_on_submit, enabled -- and now
;; variant, is_error, supporting_text, prefix, suffix, leading_icon,
;; trailing_icon and max_length.  `variant' picks the container:
;; "filled" renders an M3 `TextField', anything else (the default) an
;; `OutlinedTextField', so the pair of samples whose whole point is
;; that contrast now recreate as a pair.  `hint' is the M3 placeholder
;; -- it was on the wire but dead until 1917fff, and this module said
;; so; it renders now.  Nine of the fourteen examples build.
;;
;; Two limits shape what is drawn below.  The icon slots render a bare
;; `Icon', not an `IconButton': the wire can put a glyph in the slot but
;; cannot hang a tap on it.  And `max_length' is a hard cap -- the
;; Companion refuses committed text past N, paste and IME included --
;; where upstream's `maxTextLength' is only an accessibility semantic
;; that announces a limit the user is still free to exceed.  The two are
;; not the same member wearing different names, so the error sample does
;; not reach for it.
;;
;; The second member wave finished the module: `selection' seeds the
;; initial TextRange, `mask'+`filter' are the output and input
;; transformations (formatting and digit-guarding happen locally, per
;; keystroke, and the literals never enter the value), `content_padding'
;; reaches the interior padding through the DecorationBox overload, and
;; `hide_keyboard_on_submit' restores the hide-on-Done that supplying a
;; submit handler suppresses.  All fourteen build.
;;
;; Two dense-field seams stated: `content_padding' is one dp on all four
;; sides where upstream splits 4dp vertical from 12dp horizontal, and
;; upstream's onKeyboardAction ONLY hides -- here the demo verb also
;; reports the submit, since a dead handler would read as a broken one.
;;
;; No recreated field authors `on_change'.  Upstream every one of these
;; handlers is `rememberTextFieldState' -- "hold what was typed" --
;; which the wire does by giving the node an id; a snackbar per
;; keystroke would be noise the samples never show.

;;; Code:

(require 'jetpacs-widgets)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-text-fields--source
  "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TextFieldSamples.kt"
  "Upstream TextFieldsExampleSourceUrl.")

(defconst jetpacs-m3-text-fields--lorem
  (concat "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do "
          "eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut "
          "enim ad minim veniam, quisque nostrud exercitation ullamco "
          "laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure "
          "dolor in reprehenderit in voluptate velit esse cillum dolore eu "
          "fugiat nulla pariatur. Excepteur sint occaecat cupidatat non  "
          "proident, sunt in culpa qui officia deserunt mollit anim id est "
          "laborum.")
  "The paragraph upstream `TextArea' seeds its state with, verbatim.")

(defun jetpacs-m3-text-fields--selection (id variant)
  "The InitialValueAndSelection pair: \"Initial text\" selected whole.
`:selection (0 12)' is rememberTextFieldState's TextRange(0, 12) -- it
seeds the initial cursor/selection only, re-seeded on an input reset
exactly like the value.  VARIANT separates the twins."
  (jetpacs-text-input id
                      :variant variant
                      :value "Initial text"
                      :selection (list 0 12)
                      :label "Label"
                      :single-line t))

(defun jetpacs-m3-text-fields--transformations ()
  "Upstream TextFieldWithTransformations: the phone-number field.
`:mask' is the output transformation -- (###) ###-#### redraws the
stored digits with literal filler that never enters the value -- and
`:filter \"digits\"' is the input transformation's digits-only revert,
applied locally at the keystroke, paste included.  `:max-length' and the
number keyboard carry the rest, as before."
  (jetpacs-text-input "text-fields-transformations"
                      :label "Phone number"
                      :single-line t
                      :keyboard "number"
                      :max-length 10
                      :filter "digits"
                      :mask "(###) ###-####"))

(defun jetpacs-m3-text-fields--dense ()
  "Upstream DenseTextFieldContentPadding: the interior padding, shrunk.
`:content-padding 4' rides the DecorationBox overload -- the only seam
that owns the field's interior -- and `:min_height 48' is the sample's
own heightIn floor under the default 56dp."
  (jetpacs-with-attrs
   (jetpacs-text-input "text-fields-dense"
                       :variant "filled"
                       :label "Label"
                       :single-line t
                       :content-padding 4)
   :min_height 48))

(defun jetpacs-m3-text-fields--hide-keyboard ()
  "Upstream TextFieldWithHideKeyboardOnImeAction.
`:hide-keyboard-on-submit' dismisses the IME after the Done action --
the default Compose behaviour that authoring any submit handler
suppresses, which is exactly why it must be a member."
  (jetpacs-text-input "text-fields-hide-keyboard"
                      :variant "filled"
                      :label "Label"
                      :on-submit (jetpacs-m3-demo "Done")
                      :hide-keyboard-on-submit t))

(defun jetpacs-m3-text-fields--filled ()
  "Upstream SimpleTextFieldSample: TextField, single line, label \"Label\".
The variant member asks for the filled container, which is the only
thing this sample says beyond its outlined twin; the id is the sample's
`rememberTextFieldState'."
  (jetpacs-text-input "text-fields-filled"
                      :variant "filled"
                      :label "Label"
                      :single-line t))

(defun jetpacs-m3-text-fields--filled-selection ()
  "Upstream TextFieldWithInitialValueAndSelection: the filled half of the pair.
`jetpacs-m3-text-fields--selection' is the shared body -- \"Initial
text\" with `:selection (0 12)', rememberTextFieldState's TextRange(0,
12), so the field opens with the whole value already selected.  This
half asks for the filled container; its own id keeps the twins distinct
on the wire."
  (jetpacs-m3-text-fields--selection "text-fields-selection"
                                     "filled"))

(defun jetpacs-m3-text-fields--outlined ()
  "Upstream SimpleOutlinedTextFieldSample: OutlinedTextField, label \"Label\".
Outlined is also the default variant, but this sample exists to be the
other half of the pair, so it names it."
  (jetpacs-text-input "text-fields-outlined"
                      :variant "outlined"
                      :label "Label"
                      :single-line t))

(defun jetpacs-m3-text-fields--outlined-selection ()
  "Upstream OutlinedTextFieldWithInitialValueAndSelection: the outlined half.
The same seeded \"Initial text\" and TextRange(0, 12) as
`jetpacs-m3-text-fields--filled-selection' -- the container is the only
thing the two samples differ in, which is why one
`jetpacs-m3-text-fields--selection' serves both."
  (jetpacs-m3-text-fields--selection "text-fields-outlined-selection"
                                     "outlined"))

(defun jetpacs-m3-text-fields--icons ()
  "Upstream TextFieldWithIcons: Favorite leading, Clear trailing, label \"Label\".
Both decoration slots are on the wire, and the icon slots are what the
sample is named for.  What does not carry is the tap: the Companion
fills the slot with an `Icon', where upstream's trailing slot holds an
`IconButton' that calls `state.clearText()' inside a `TooltipBox'.  So
the Clear glyph sits in its M3 position and does not empty the field."
  (jetpacs-text-input "text-fields-icons"
                      :variant "filled"
                      :label "Label"
                      :single-line t
                      :leading-icon "favorite"
                      :trailing-icon "clear"))

(defun jetpacs-m3-text-fields--placeholder ()
  "Upstream TextFieldWithPlaceholder: label \"Email\" over a placeholder.
The hint member is the M3 placeholder, which is what the sample is
named for.  Upstream also hangs a checkbox above the field toggling
TextFieldLabelPosition.Attached(alwaysMinimize) -- whether the
placeholder shows while the field is unfocused.  There is no
label_position member on the wire, so that knob is left out rather than
drawn as a control that cannot move anything."
  (jetpacs-text-input "text-fields-placeholder"
                      :variant "filled"
                      :label "Email"
                      :hint "example@gmail.com"
                      :single-line t))

(defun jetpacs-m3-text-fields--prefix-suffix ()
  "Upstream TextFieldWithPrefixAndSuffix: \"www.\" and \".com\" around \"google\".
The prefix and suffix members put both affixes inside the container,
around the value and beside the placeholder, which is the sample.  Its
alwaysMinimize checkbox is left out for the same reason as in
`jetpacs-m3-text-fields--placeholder'."
  (jetpacs-text-input "text-fields-prefix-suffix"
                      :variant "filled"
                      :label "Label"
                      :hint "google"
                      :prefix "www."
                      :suffix ".com"
                      :single-line t))

(defun jetpacs-m3-text-fields--error ()
  "Upstream TextFieldWithErrorState: the error container, label \"Username*\".
The is_error and supporting_text members carry the M3 error state --
error colouring on container, label and helper line, and the \"Text
input too long\" message under the field.  Two things do not.  The
error is authored here, where upstream flips it from a snapshotFlow
over the text: the wire has no validation loop, so the field opens in
the state the sample exists to show instead of arriving there.  And
upstream's supporting slot is a Row -- the message, a weighted spacer,
then a live \"Limit: N/10\" counter -- while supporting_text is one
string, so the counter, which has nothing to count without that loop,
is left out.  max_length is deliberately not authored: it is a hard
cap that refuses the eleventh character, which would make the
over-limit state unreachable, where upstream's maxTextLength only
announces the limit."
  (jetpacs-text-input "text-fields-error"
                      :variant "filled"
                      :label "Username*"
                      :is-error t
                      :supporting-text "Text input too long"
                      :single-line t))

(defun jetpacs-m3-text-fields--supporting-text ()
  "Upstream TextFieldWithSupportingText: the helper line under the field.
supporting_text is that slot: M3 measures it to the field's own width
and tints it from the field's state, which is why the sample is not a
`text' node underneath."
  (jetpacs-text-input "text-fields-supporting"
                      :variant "filled"
                      :label "Label"
                      :supporting-text
                      "Supporting text that is long and perhaps goes onto another line."
                      :single-line t))

(defun jetpacs-m3-text-fields--password ()
  "Upstream PasswordTextField: a SecureTextField, label \"Enter password\".
The password member is TextObfuscationMode on the wire, and SPEC 17.4
forbids a seeded value or an on_change beside it -- a secret may leave
only through on_submit.  Upstream's trailing Visibility/VisibilityOff
icon button flips obfuscation to Visible; trailing_icon would draw that
glyph, but the slot renders an `Icon' and not an `IconButton', so the
toggle could not toggle.  A reveal control that never reveals is worse
than none, so the field obfuscates with an empty trailing slot."
  (jetpacs-text-input "text-fields-password"
                      :label "Enter password"
                      :password t))

(defun jetpacs-m3-text-fields--text-area ()
  "Upstream TextArea: a 120dp-tall multi-line field seeded with a paragraph.
Upstream leaves lineLimits at the multi-line default, uses the filled
container and sizes the field with Modifier.height(120.dp); the value
member seeds the same paragraph and :height is the SPEC 16.5 attribute
carrying that size."
  (jetpacs-with-attrs
   (jetpacs-text-input "text-fields-text-area"
                       :variant "filled"
                       :value jetpacs-m3-text-fields--lorem
                       :label "Label")
   :height 120))

(jetpacs-m3-defcomponent "text-fields"
  :builders (list #'jetpacs-text-input)
  :name "Text fields"
  :description
  "Text fields let users enter and edit text."
  :guidelines "https://m3.material.io/components/text-fields"
  :docs "https://developer.android.com/reference/kotlin/androidx/compose/material3#textfield"
  :source "https://cs.android.com/androidx/platform/frameworks/support/+/androidx-main:compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/TextField.kt"
  :examples
  (list
   (jetpacs-m3-example
    "SimpleTextFieldSample"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--filled)
   (jetpacs-m3-example
    "TextFieldWithInitialValueAndSelection"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--filled-selection)
   (jetpacs-m3-example
    "SimpleOutlinedTextFieldSample"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--outlined)
   (jetpacs-m3-example
    "OutlinedTextFieldWithInitialValueAndSelection"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--outlined-selection)
   (jetpacs-m3-example
    "TextFieldWithTransformations"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--transformations)
   (jetpacs-m3-example
    "TextFieldWithIcons"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--icons)
   (jetpacs-m3-example
    "TextFieldWithPlaceholder"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--placeholder)
   (jetpacs-m3-example
    "TextFieldWithPrefixAndSuffix"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--prefix-suffix)
   (jetpacs-m3-example
    "TextFieldWithErrorState"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--error)
   (jetpacs-m3-example
    "TextFieldWithSupportingText"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--supporting-text)
   (jetpacs-m3-example
    "DenseTextFieldContentPadding"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--dense)
   (jetpacs-m3-example
    "PasswordTextField"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--password)
   (jetpacs-m3-example
    "TextFieldWithHideKeyboardOnImeAction"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--hide-keyboard)
   (jetpacs-m3-example
    "TextArea"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--text-area)
   ))

(provide 'jetpacs-m3-text-fields)
;;; jetpacs-m3-text-fields.el ends here
