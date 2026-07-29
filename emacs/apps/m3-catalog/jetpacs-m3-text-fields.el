;;; jetpacs-m3-text-fields.el --- Catalog component: Text fields -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Upstream: Components.kt `TextFields' + Examples.kt
;; `TextFieldsExamples' (14 examples), samples/TextFieldSamples.kt.
;;
;; The `text_input' node carries id, value, hint, label, on_change,
;; on_submit, single_line, min_lines, max_lines, monospace, syntax,
;; password, keyboard, autofocus, clear_on_submit and enabled -- and
;; nothing else.  The Companion renders every one of them as an M3
;; `OutlinedTextField' (Renderer.kt:392; M3-COMPONENT-LOOKUP records
;; that the filled TextField is available but deliberately not
;; exposed), so the outlined sample recreates exactly while the filled
;; one has no variant member with which to ask for its container.
;;
;; The slots M3 hangs off a text field -- leadingIcon, trailingIcon,
;; prefix, suffix, supportingText, isError, contentPadding, the
;; input/output transformations and the initial TextRange -- have no
;; wire members at all, and each of those samples exists to show
;; exactly one of them, so they say so.  What IS on the wire is the
;; placeholder (`hint'), the obfuscation (`password'), the seeded value
;; and a height, and those are the three samples that recreate beside
;; the outlined one.
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

(defconst jetpacs-m3-text-fields--filled-note
  "The text_input node has no variant member: it always renders an M3 OutlinedTextField, so the filled TextField container this sample exists to contrast with the outlined one cannot be asked for from Emacs."
  "Why the filled-container samples are unsupported.")

(defconst jetpacs-m3-text-fields--selection-note
  "The text_input node has no selection member: its value member does seed \"Initial text\", but TextRange(0, 12), the initial selection this sample exists to show, cannot be put on the wire."
  "Why the InitialValueAndSelection samples are unsupported.")

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

(defun jetpacs-m3-text-fields--outlined ()
  "Upstream SimpleOutlinedTextFieldSample: OutlinedTextField, label \"Label\".
`text_input' IS an OutlinedTextField on this Companion, and the id is
the sample's `rememberTextFieldState': the typed value is held under
that id, which is the whole of what the sample hoists."
  (jetpacs-text-input "text-fields-outlined"
                      :label "Label"
                      :single-line t))

(defun jetpacs-m3-text-fields--placeholder ()
  "Upstream TextFieldWithPlaceholder: label \"Email\" over a placeholder.
The hint member is the M3 placeholder, which is what the sample is
named for.  Upstream also hangs a checkbox above the field toggling
TextFieldLabelPosition.Attached(alwaysMinimize) -- whether the
placeholder shows while the field is unfocused.  There is no
label_position member on the wire, so that knob is left out rather than
drawn as a control that cannot move anything."
  (jetpacs-text-input "text-fields-placeholder"
                      :label "Email"
                      :hint "example@gmail.com"
                      :single-line t))

(defun jetpacs-m3-text-fields--password ()
  "Upstream PasswordTextField: a SecureTextField, label \"Enter password\".
The password member is TextObfuscationMode on the wire, and SPEC 17.4
forbids a seeded value or an on_change beside it -- a secret may leave
only through on_submit.  Upstream's trailing Visibility/VisibilityOff
icon button, which flips obfuscation to Visible, has no trailing_icon
member to ride on, so the field obfuscates with no reveal toggle."
  (jetpacs-text-input "text-fields-password"
                      :label "Enter password"
                      :password t))

(defun jetpacs-m3-text-fields--text-area ()
  "Upstream TextArea: a 120dp-tall multi-line field seeded with a paragraph.
Upstream leaves lineLimits at the multi-line default and sizes the
field with Modifier.height(120.dp); the value member seeds the same
paragraph and :height is the SPEC 16.5 attribute carrying that size."
  (jetpacs-with-attrs
   (jetpacs-text-input "text-fields-text-area"
                       :value jetpacs-m3-text-fields--lorem
                       :label "Label")
   :height 120))

(jetpacs-m3-defcomponent "text-fields"
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
    :unsupported jetpacs-m3-text-fields--filled-note)
   (jetpacs-m3-example
    "TextFieldWithInitialValueAndSelection"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "Neither half is on the wire: text_input always renders an OutlinedTextField, so the filled container is not requestable, and it has no selection member for the TextRange(0, 12) that pre-selects \"Initial text\".")
   (jetpacs-m3-example
    "SimpleOutlinedTextFieldSample"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--outlined)
   (jetpacs-m3-example
    "OutlinedTextFieldWithInitialValueAndSelection"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported jetpacs-m3-text-fields--selection-note)
   (jetpacs-m3-example
    "TextFieldWithTransformations"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "The text_input node has no input_transformation or output_transformation member: the ten-digit InputTransformation.maxLength filter and the (XXX) XXX-XXXX formatting this sample exists to show cannot be put on the wire, which carries only the number keypad.")
   (jetpacs-m3-example
    "TextFieldWithIcons"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "The text_input node has no leading_icon or trailing_icon member: the Favorite icon inside the field and the Clear icon button that empties it are decoration slots of the M3 text field the wire cannot ask for.")
   (jetpacs-m3-example
    "TextFieldWithPlaceholder"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--placeholder)
   (jetpacs-m3-example
    "TextFieldWithPrefixAndSuffix"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "The text_input node has no prefix or suffix member: the \"www.\" and \".com\" affixes M3 draws inside the field, around the value and next to the placeholder, cannot be put on the wire.")
   (jetpacs-m3-example
    "TextFieldWithErrorState"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "The text_input node has no is_error or supporting_text member: the error colouring, the \"Text input too long\" message and the character counter that make this sample an error state cannot be put on the wire.")
   (jetpacs-m3-example
    "TextFieldWithSupportingText"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "The text_input node has no supporting_text member: the helper line M3 draws under the field, inside its container and in its own colour and typography, cannot be put on the wire.")
   (jetpacs-m3-example
    "DenseTextFieldContentPadding"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "The text_input node has no content_padding member: what makes this field dense is TextFieldDefaults' interior padding, and the universal padding attribute sits outside the field's container instead of inside it.")
   (jetpacs-m3-example
    "PasswordTextField"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--password)
   (jetpacs-m3-example
    "TextFieldWithHideKeyboardOnImeAction"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :unsupported
    "There is no keyboard-visibility member and no Companion-local builtin for one: authoring on_submit does raise the IME action to Done, but hiding the software keyboard from that handler, which is what this sample exists to show, cannot be asked for from Emacs.")
   (jetpacs-m3-example
    "TextArea"
    "Text fields examples"
    :source jetpacs-m3-text-fields--source
    :build #'jetpacs-m3-text-fields--text-area)
   ))

(provide 'jetpacs-m3-text-fields)
;;; jetpacs-m3-text-fields.el ends here
