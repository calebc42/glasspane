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
    ("row" ("children") ("align" "arrange" "content_padding" "fill" "overlap" "scroll" "spacing"))
    ("column" ("children") ("align" "arrange" "fill" "overlap" "reverse_scroll" "scroll" "spacing"))
    ("flow_row" ("children") ("align" "arrange" "run_spacing" "spacing"))
    ("box" ("children") ("alignment" "on_long_tap" "on_tap"))
    ("surface" ("children") ("color" "elevation" "shadow_elevation" "shape"))
    ("lazy_column" ("children") ("content_padding" "spacing"))
    ("spacer" () ())
    ("divider" () ("color" "thickness"))
    ("card" ("children") ("on_long_tap" "on_tap" "swipe_end" "swipe_start" "variant"))
    ("collapsible" ("children" "header" "id") ("collapsed" "on_long_tap" "swipe_end" "swipe_start"))
    ("reorderable_list" ("items") ("on_reorder"))
    ("tabs" ("children" "items") ("id" "initial" "on_change" "pager_only" "scrollable" "style"))
    ("table" ("rows") ("aligns" "on_add_col" "on_add_row"))
    ("button" ("label" "on_tap") ("animate_shape" "checked" "checked_icon" "checked_shape" "enabled" "expanded" "icon" "on_change" "shape" "shape_role" "size" "variant"))
    ("icon_button" ("icon" "on_tap") ("badge" "checked" "checked_icon" "color" "content_description" "enabled" "on_change" "shape" "size" "variant" "width_mode"))
    ("chip" ("label") ("avatar" "content_spacing" "enabled" "icon" "on_tap" "selected" "trailing_icon" "variant"))
    ("assist_chip" ("label") ("enabled" "icon" "on_tap" "variant"))
    ("menu" () ("enabled" "footer" "groups" "icon" "initial_scroll" "items"))
    ("text_input" ("id") ("autofocus" "clear_on_submit" "content_padding" "enabled" "filter" "hide_keyboard_on_submit" "hint" "is_error" "keyboard" "label" "leading_icon" "mask" "max_length" "max_lines" "min_lines" "monospace" "on_change" "on_submit" "password" "prefix" "selection" "single_line" "suffix" "supporting_text" "syntax" "trailing_icon" "value" "variant"))
    ("editor" ("id") ("autofocus" "chromeless" "complete" "document" "enabled" "line_numbers" "on_enter" "on_save" "publish_state" "read_only" "syntax" "toolbar" "value"))
    ("checkbox" ("id") ("checked" "enabled" "label" "on_change" "state" "stroke"))
    ("switch" ("id") ("checked" "enabled" "label" "on_change" "thumb_icon"))
    ("enum_list" ("id" "options") ("allow_add" "children" "enabled" "multi_select" "on_change" "value" "variant"))
    ("date_button" ("label" "on_pick") ("disabled_weekdays" "enabled" "max_date" "min_date" "mode" "value"))
    ("time_button" ("label" "on_pick") ("display_mode" "enabled" "value"))
    ("slider" ("id" "on_change") ("color" "color_end" "enabled" "max" "min" "orientation" "thumb_icon" "track" "track_icon_end" "track_icon_start" "value" "value_end" "value_label" "values"))
    ("chart" ("series") ("children" "height" "kind" "on_point_tap" "summary" "y_range"))
    ("canvas" ("height" "ops" "width") ("children"))
    ("month_grid" ("month") ("children" "disabled_weekdays" "marks" "max_date" "max_month" "min_date" "min_month" "on_day_tap" "on_month_change" "range_end" "range_start" "selected"))
    ("scaffold" () ("body" "bottom_bar" "bottom_bar_behavior" "drawer" "drawer_variant" "fab" "fab_hide_on_scroll" "fab_position" "floating_toolbar" "floating_toolbar_exit_direction" "floating_toolbar_expanded" "floating_toolbar_fab" "floating_toolbar_orientation" "floating_toolbar_placement" "floating_toolbar_scroll" "is_refreshing" "on_refresh" "on_sheet_change" "refresh_indicator" "scroll_behavior" "sheet" "sheet_peek_height" "sheet_state" "snackbar" "snackbar_action" "snackbar_dismiss" "snackbar_duration" "snackbar_max_lines" "top_bar" "top_bar_centered" "top_bar_collapsed_height" "top_bar_expanded" "top_bar_expanded_height" "top_bar_style" "top_bar_subtitle"))
    ("tooltip" ("children" "text") ("action_label" "caret" "caret_height" "caret_width" "on_action" "position" "rich" "shown" "title"))
    ("split_button" ("on_tap") ("checked" "enabled" "icon" "items" "label" "on_change" "on_trailing_tap" "size" "trailing_description" "trailing_icon" "trailing_label" "variant"))
    ("pane_scaffold" ("detail" "list") ("extra" "variant"))
    ("navigation_rail" ("items") ("arrangement" "expanded" "header" "hide_on_collapse" "on_expand_change" "variant"))
    ("search_bar" ("id") ("children" "enabled" "hint" "leading_icon" "on_change" "on_search" "trailing_icon" "value" "variant"))
    ("dropdown" ("id" "options") ("editable" "enabled" "hint" "label" "on_change" "value"))
    ("segmented_button" ("id" "options") ("enabled" "multi_select" "on_change" "value"))
    ("app_bar_row" ("items") ("max_items" "overflow_icon"))
    ("app_bar_column" ("items") ("max_items" "overflow_icon"))
    ("carousel" ("children") ("content_padding" "item_corner" "item_spacing" "item_width" "strategy"))
    ("fab_menu" ("items") ("close_icon" "icon"))
    ("button_group" ("items") ("overflow_icon"))
    ("lazy_grid" ("children") ("columns" "content_padding" "min_item_width" "reverse" "spacing")))
  "Contract members per node type: (TYPE (REQUIRED...) (OPTIONAL...)).
WIRE names, so the table compares directly against contract.json.  The
constructors spell a multi-word member with a hyphen (`:content-padding'
for `content_padding'); `jetpacs--wire-name' is the map between them.")

(provide 'jetpacs-vocabulary)
;;; jetpacs-vocabulary.el ends here
