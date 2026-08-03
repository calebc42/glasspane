;;; jetpacs-vocabulary.el --- the contract node schema -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; GENERATED from ebp/contract.json (format 6, spec
;; 2.0.0-draft) by tools/gen-jetpacs-vocabulary.py -- DO NOT EDIT.
;; `jetpacs-widgets/catalog-node-schema' re-reads the contract and fails on
;; any disagreement, exactly as the other `catalog-*' mirrors do.
;;
;; The sibling of the Companion's generated Vocabulary.kt, and for the same
;; reason: an amendment that adds a member must not have to be remembered in
;; three places.  Emacs cannot read contract.json at run time -- the device
;; load-path holds only the .el files device/install.sh pushes -- so the
;; contract is compiled to Elisp here and drift-tested off-device.
;;
;; This is what lets the container constructors REFUSE an unknown trailing
;; option instead of silently dropping it, which is how `:padding 8' on a
;; row used to vanish (it is a SPEC 16.5 universal attribute and belongs on
;; `jetpacs-with-attrs').

;;; Code:

(defconst jetpacs-contract-format 6
  "The `contract_format' this vocabulary was generated from.")

(defconst jetpacs-contract-spec-version "2.0.0-draft"
  "The SPEC version this vocabulary was generated from.")

(defconst jetpacs-node-schema
  '(
    ("text" ("text") ("color" "font_weight" "max_lines" "selectable" "style" "syntax"))
    ("rich_text" ("spans") ("style"))
    ("icon" ("name") ("badge" "color" "content_description" "size"))
    ("image" ("url") ("content_description" "content_scale"))
    ("date_stamp" () ("day" "month" "month_index" "time" "year"))
    ("section_header" ("title") ("trailing"))
    ("empty_state" () ("action_label" "caption" "icon" "on_tap" "title"))
    ("progress" () ("value" "variant"))
    ("badge" ("label") ("children" "color" "icon"))
    ("row" ("children") ("align" "arrange" "fill" "scroll" "spacing"))
    ("column" ("children") ("align" "arrange" "fill" "reverse_scroll" "scroll" "spacing"))
    ("flow_row" ("children") ("align" "arrange" "run_spacing" "spacing"))
    ("box" ("children") ("alignment" "on_tap"))
    ("surface" ("children") ("color" "elevation" "shadow_elevation" "shape"))
    ("lazy_column" ("children") ("content_padding" "spacing"))
    ("spacer" () ())
    ("divider" () ("color" "thickness"))
    ("card" ("children") ("on_long_tap" "on_tap" "swipe_end" "swipe_start" "variant"))
    ("collapsible" ("children" "header" "id") ("collapsed" "on_long_tap" "swipe_end" "swipe_start"))
    ("reorderable_list" ("items") ("on_reorder"))
    ("tabs" ("children" "items") ("id" "initial" "on_change" "pager_only" "scrollable"))
    ("table" ("rows") ("aligns" "on_add_col" "on_add_row"))
    ("button" ("label" "on_tap") ("animate_shape" "checked" "enabled" "icon" "on_change" "shape" "size" "variant"))
    ("icon_button" ("icon" "on_tap") ("badge" "checked" "checked_icon" "content_description" "enabled" "on_change" "variant"))
    ("chip" ("label") ("enabled" "icon" "on_tap" "selected" "trailing_icon" "variant"))
    ("assist_chip" ("label") ("enabled" "icon" "on_tap" "variant"))
    ("menu" ("items") ("enabled" "icon" "initial_scroll"))
    ("text_input" ("id") ("autofocus" "clear_on_submit" "enabled" "hint" "is_error" "keyboard" "label" "leading_icon" "max_length" "max_lines" "min_lines" "monospace" "on_change" "on_submit" "password" "prefix" "single_line" "suffix" "supporting_text" "syntax" "trailing_icon" "value" "variant"))
    ("editor" ("id") ("autofocus" "chromeless" "complete" "document" "enabled" "line_numbers" "on_enter" "on_save" "publish_state" "read_only" "syntax" "toolbar" "value"))
    ("checkbox" ("id") ("checked" "enabled" "label" "on_change"))
    ("switch" ("id") ("checked" "enabled" "label" "on_change" "thumb_icon"))
    ("enum_list" ("id" "options") ("allow_add" "enabled" "multi_select" "on_change" "value"))
    ("date_button" ("label" "on_pick") ("enabled" "mode" "value"))
    ("time_button" ("label" "on_pick") ("display_mode" "enabled" "value"))
    ("slider" ("id" "on_change") ("color" "enabled" "max" "min" "thumb_icon" "track" "value" "values"))
    ("chart" ("series") ("children" "height" "kind" "on_point_tap" "summary" "y_range"))
    ("canvas" ("height" "ops" "width") ("children"))
    ("month_grid" ("month") ("children" "marks" "max_month" "min_month" "on_day_tap" "on_month_change" "selected"))
    ("scaffold" () ("body" "bottom_bar" "drawer" "fab" "floating_toolbar" "on_refresh" "snackbar" "snackbar_action" "top_bar")))
  "Contract members per node type: (TYPE (REQUIRED...) (OPTIONAL...)).
WIRE names, so the table compares directly against contract.json.  The
constructors spell a multi-word member with a hyphen (`:content-padding'
for `content_padding'); `jetpacs--wire-name' is the map between them.")

(provide 'jetpacs-vocabulary)
;;; jetpacs-vocabulary.el ends here
