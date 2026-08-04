;;; jetpacs-widgets.el --- EBP node-vocabulary builders -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Emacs-side builders for the EBP widget vocabulary (SPEC §16 node
;; model + §16.6 colors + §17 families).  This is the *application* layer
;; in the ebp.el/jetpacs split (docs/REWRITE-PLAN.md "The ebp.el
;; boundary"): it constructs SurfaceSpec node trees and hands them to the
;; endpoint via `ebp-client-surface-update'.  It is an INDEPENDENT
;; implementation of the same `ebp/' spec as the Kotlin companion's W9
;; renderer -- verified against `ebp/goldens/', not ported from Kotlin.
;;
;; Rung JW-0 of docs/PLAN-jetpacs-widgets.md: the foundation the rest
;; tests against -- the node funnel, the canonical serializer, the
;; universal-attribute rider, the color helper, and the ActionDescriptor
;; and builtin constructors.  The 39 node-type constructors land in
;; JW-1..JW-6.
;;
;; Build-time validation policy: the device is the authoritative gate
;; (it returns applied/stale), but constructors fail fast on the
;; STATICALLY checkable spec constraints -- §4.4 identifiers, §4.2 finite
;; numbers and declared ranges, §14.1 descriptor rules -- so a malformed
;; call errors here instead of surfacing as a rejected device push.
;;
;; Representation: a node is a PLIST keyed by `:t' (type string) plus
;; keyword members; children are VECTORS of node plists; nested
;; descriptors (`:on_tap' ...) are plists.  JSON true is elisp `t', JSON
;; false is `:json-false', and an absent member is simply OMITTED.  This
;; is exactly what `ebp-client-surface-update' expects; on the live push
;; path jsonrpc.el serializes it (`:false-object :json-false').  For
;; golden byte-parity the test path uses `jetpacs-node->canonical-json'.

;;; Code:

(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-vocabulary)

;;;; Catalogs (mirrors of ebp/contract.json, for gating and coverage tests)

(defconst jetpacs-node-types
  '("text" "rich_text" "icon" "image" "date_stamp" "section_header"
    "empty_state" "progress" "badge" "row" "column" "flow_row" "box"
    "surface" "lazy_column" "spacer" "divider" "card" "collapsible"
    "reorderable_list" "tabs" "table" "button" "icon_button" "chip"
    "assist_chip" "menu" "text_input" "editor" "checkbox" "switch"
    "enum_list" "date_button" "time_button" "slider" "chart" "canvas"
    "month_grid" "scaffold" "tooltip" "split_button" "pane_scaffold"
    "navigation_rail" "search_bar" "dropdown" "segmented_button"
    "app_bar_row" "app_bar_column" "carousel" "fab_menu" "button_group"
    "lazy_grid")
  "The 52 EBP node types (contract.json `node_types').")

(defconst jetpacs-core-node-set
  '("text" "row" "column" "box" "spacer" "divider" "button" "text_input")
  "The mandatory Core Node Set (SPEC §16.2).")

(defconst jetpacs-universal-attributes
  '(:key :id :scroll_here :padding :pad :width :height :min_width :max_width
    :min_height :max_height :fill_fraction :aspect_ratio :weight :bg :corner
    :border :alpha :clip :align_self)
  "The universal node attributes legal on any node.
These are §16.5 plus `id', which §16.1 establishes as the document-unique
identity member permitted on any node (see the amendment adding the `id'
row to the §16.5 table).")

(defconst jetpacs-theme-roles
  '("primary" "on_primary" "primary_container" "on_primary_container"
    "secondary" "on_secondary" "secondary_container" "on_secondary_container"
    "tertiary" "on_tertiary" "tertiary_container" "on_tertiary_container"
    "error" "on_error" "error_container" "on_error_container"
    "background" "on_background" "surface" "on_surface"
    "surface_variant" "on_surface_variant" "outline" "success" "warning")
  "The theme-role color tokens (contract.json `theme_roles'; §18.4).")

(defconst jetpacs-syntax-roles
  '("comment" "string" "keyword" "function" "constant" "variable" "type"
    "number" "operator" "preprocessor" "heading" "link" "todo" "done" "tag")
  "The syntax-role tokens (contract.json `syntax_roles'; §18.4).")

;;;; Validation helpers (SPEC §4.4 identifiers, §4.2 numbers, §16.5 attrs)

(defconst jetpacs--identifier-re
  (rx bos (any "A-Za-z0-9") (** 0 127 (any "A-Za-z0-9" "._:/-")) eos)
  "A SPEC §4.4 identifier: 1-128 ASCII, begins letter/digit, [A-Za-z0-9._:/-].")

(defun jetpacs--identifier-p (s)
  "Non-nil when S is a valid SPEC §4.4 identifier."
  (and (stringp s) (string-match-p jetpacs--identifier-re s)))

(defun jetpacs--check-identifier (s what)
  "Signal an error unless S is a §4.4 identifier; WHAT names the field.
Returns S."
  (unless (jetpacs--identifier-p s)
    (error "jetpacs: %s %S is not a valid identifier (SPEC 4.4)" what s))
  s)

(defun jetpacs-wire-id (prefix name)
  "A stable SPEC 4.4 identifier \"PREFIX-STEM-HASH\" for arbitrary NAME.
The B5 minter: buffer names, file paths, and host labels are routinely
INVALID identifiers (`*shell*', `*git-commit*', paths with spaces), and
a raw name signals inside a builder and takes the whole render down.
Out-of-charset chars collapse to `-', a leading alnum is guaranteed,
and a sha1 of the ORIGINAL name is appended because sanitizing is
lossy: `*shell*' and `-shell-' must not collide — a collision
cross-seeds SPEC 13.6 input drafts.  The readable stem keeps the id
debuggable; the result is always at most 128 chars.

STABLE across renders and sessions on purpose (draft preservation);
byte-identical to the JC-3c comint minter for PREFIX \"comint\", so live
comint drafts survive the promotion.  Callers: comint input rows, and
the coming files editor ids / witheditor state ids / hosts buffers."
  (jetpacs--check-identifier prefix "wire-id prefix")
  (when (> (length prefix) 100)
    (error "jetpacs: wire-id prefix longer than 100 chars"))
  (unless (stringp name)
    (error "jetpacs: wire-id NAME must be a string, got %S" name))
  (let* ((safe (replace-regexp-in-string "[^A-Za-z0-9._:/-]" "-" name))
         (head (if (string-match-p "\\`[A-Za-z0-9]" safe) safe
                 (concat "c" safe)))
         (hash (substring (sha1 name) 0 8))
         ;; 128-char ceiling with room for the prefix, two dashes, and
         ;; the hash: prefix + 1 + min(100, 118-prefix) + 1 + 8 <= 128.
         (stem (substring head 0 (min (length head) 100
                                      (max 0 (- 118 (length prefix)))))))
    (format "%s-%s-%s" prefix stem hash)))

(defun jetpacs--require-string (s what)
  "Signal an error unless S is a string; WHAT names the field.  Returns S."
  (unless (stringp s)
    (error "jetpacs: %s must be a string, got %S" what s))
  s)

(defun jetpacs--finite-number-p (v)
  "Non-nil when V is a finite (non-NaN, non-infinite) number (SPEC §4.2)."
  (and (numberp v)
       (or (integerp v)
           (and (= v v) (< (abs v) 1.0e+INF)))))

(defun jetpacs--check-number (v what min max &optional positive)
  "Signal an error unless V is a finite number within bounds; return V.
WHAT names the field.  MIN/MAX (nil = unbounded) are inclusive.  POSITIVE
non-nil additionally requires V > 0 (SPEC §16.5)."
  (unless (jetpacs--finite-number-p v)
    (error "jetpacs: %s must be a finite number (SPEC 4.2), got %S" what v))
  (when (and positive (<= v 0))
    (error "jetpacs: %s must be > 0 (SPEC 16.5), got %S" what v))
  (when (and min (< v min))
    (error "jetpacs: %s must be >= %s (SPEC 16.5), got %S" what min v))
  (when (and max (> v max))
    (error "jetpacs: %s must be <= %s (SPEC 16.5), got %S" what max v))
  v)

(defun jetpacs--check-bool (v what)
  "Signal an error unless V is `t' or `:json-false'; WHAT names the field."
  (unless (memq v '(t :json-false))
    (error "jetpacs: %s must be t or :json-false, got %S" what v))
  v)

(defconst jetpacs--hex-color-re
  (rx bos "#"
      (or (= 3 (any "0-9A-Fa-f")) (= 4 (any "0-9A-Fa-f"))
          (= 6 (any "0-9A-Fa-f")) (= 8 (any "0-9A-Fa-f")))
      eos)
  "A §16.6 hex color: #rgb, #rgba, #rrggbb, or #rrggbbaa (case-insensitive).")

(defun jetpacs--check-color (v)
  "Signal an error unless V is a §16.6 Color on the wire; return V.
Accepts a hex form or any §4.4 identifier (a theme role -- KNOWN or
unknown, since an unknown role is legal and the Companion falls back)."
  (unless (and (stringp v)
               (or (string-match-p jetpacs--hex-color-re v)
                   (jetpacs--identifier-p v)))
    (error "jetpacs: color %S must be a theme role or #hex (SPEC 16.6)" v))
  v)

(defun jetpacs--check-obj (plist allowed what val-fn)
  "Signal an error unless PLIST is a keyword plist with keys in ALLOWED.
Runs VAL-FN on each (KEY VALUE); WHAT names the field."
  (unless (and (consp plist) (keywordp (car plist)))
    (error "jetpacs: %s must be an object (SPEC 16.5), got %S" what plist))
  (let ((p plist))
    (while p
      (let ((k (pop p)) (val (pop p)))
        (unless (memq k allowed)
          (error "jetpacs: %s has unknown member %S (SPEC 16.5)" what k))
        (funcall val-fn k val)))))

(defconst jetpacs--corner-keys '(:top_start :top_end :bottom_start :bottom_end))
(defconst jetpacs--pad-keys '(:start :top :end :bottom :horizontal :vertical))

(defun jetpacs--check-attr (k v)
  "Validate universal attribute K's value V (SPEC §16.5); signal on invalid."
  (pcase k
    ((or :key :id) (jetpacs--check-identifier v k))
    ((or :scroll_here :clip) (jetpacs--check-bool v k))
    ((or :fill_fraction :alpha) (jetpacs--check-number v k 0 1))
    ((or :aspect_ratio :weight) (jetpacs--check-number v k nil nil t))
    ((or :padding :width :height :min_width :max_width :min_height :max_height)
     (jetpacs--check-number v k 0 nil))
    (:bg (jetpacs--check-color v))
    (:corner
     (if (numberp v) (jetpacs--check-number v k 0 nil)
       (jetpacs--check-obj v jetpacs--corner-keys k
                           (lambda (ck cv) (jetpacs--check-number cv ck 0 nil)))))
    (:pad (jetpacs--check-obj v jetpacs--pad-keys k
                              (lambda (pk pv) (jetpacs--check-number pv pk 0 nil))))
    (:border (jetpacs--check-obj v '(:width :color) k
                                 (lambda (bk bv)
                                   (pcase bk
                                     (:width (jetpacs--check-number bv bk 0 nil))
                                     (:color (jetpacs--check-color bv))))))
    (:align_self
     (unless (member v '("start" "center" "end" "stretch"))
       (error "jetpacs: :align_self must be start/center/end/stretch (SPEC 16.5), got %S" v)))
    (_ nil)))

(defun jetpacs--check-capture-fields (fields)
  "Signal an error unless FIELDS is a list of DISTINCT §4.4 identifiers (§14.1)."
  (unless (listp fields)
    (error "jetpacs: capture_fields must be a list of id strings (SPEC 14.1), got %S" fields))
  (dolist (f fields) (jetpacs--check-identifier f "capture field"))
  (unless (= (length fields) (length (delete-dups (copy-sequence fields))))
    (error "jetpacs: capture_fields must be distinct (SPEC 14.1), got %S" fields)))

(defun jetpacs--check-descriptor (v what)
  "Signal unless V is an ActionDescriptor: a plist carrying exactly one of
:action or :builtin (SPEC §14).  WHAT names the field.  Returns V."
  (unless (and (consp v) (keywordp (car v))
               (let ((a (plist-member v :action)) (b (plist-member v :builtin)))
                 (and (or a b) (not (and a b)))))
    (error "jetpacs: %s must be an action/builtin descriptor (SPEC 14), got %S" what v))
  v)

(defun jetpacs--check-swipe (v what)
  "Signal unless V is a swipe side: a plist with :label and :on_trigger (§17.3).
WHAT names the field.  Returns V."
  (unless (and (consp v) (keywordp (car v))
               (plist-member v :label) (plist-member v :on_trigger))
    (error "jetpacs: %s must be a swipe side with :label and :on_trigger (SPEC 17.3), got %S" what v))
  v)

(defun jetpacs--flag (x)
  "Return t when X is non-nil (JSON true), else nil (member omitted).
Use for a boolean member whose false form is its default and is left off
the wire; use `:json-false' directly for a member that MUST emit false."
  (and x t))

(defconst jetpacs--text-styles
  '("body" "title" "headline" "caption" "label" "mono")
  "The §17.2 text `style' vocabulary (unknown falls back to `body').")

(defun jetpacs--check-enum (v allowed what)
  "Signal unless V (symbol or string) names a member of ALLOWED; WHAT names
the field.  Returns the normalized string form."
  (let ((s (format "%s" v)))
    (unless (member s allowed)
      (error "jetpacs: %s must be one of %S, got %S" what allowed v))
    s))

(defconst jetpacs--max-safe-integer 9007199254740991
  "The §4.2 EBP integer ceiling (2^53 - 1); integers must lie in ±this.")

(defun jetpacs--check-integer (v what min max)
  "Signal unless V is an integer within inclusive [MIN,MAX] (nil = unbounded);
WHAT names the field.  The §4.2 ceiling (`jetpacs--max-safe-integer') is
always enforced regardless of MAX.  Returns V."
  (unless (integerp v)
    (error "jetpacs: %s must be an integer (SPEC 4.2), got %S" what v))
  (unless (<= (- jetpacs--max-safe-integer) v jetpacs--max-safe-integer)
    (error "jetpacs: %s exceeds the §4.2 integer range, got %S" what v))
  (when (and min (< v min)) (error "jetpacs: %s must be >= %s, got %S" what min v))
  (when (and max (> v max)) (error "jetpacs: %s must be <= %s, got %S" what max v))
  v)

(defun jetpacs--json-equal (a b)
  "SPEC §4.3 equality for scalar option/slider values.
Numbers compare by numeric value (so 1, 1.0, and 1e0 are equal and -0 equals
0); strings, booleans, and null compare by `equal'."
  (if (and (numberp a) (numberp b)) (= a b) (equal a b)))

(defun jetpacs--check-date (value)
  "Signal unless VALUE is a §17.4 date `YYYY-MM-DD' with in-range fields."
  (unless (and (stringp value)
               (string-match "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'" value))
    (error "jetpacs: date value must be YYYY-MM-DD (SPEC 17.4), got %S" value))
  (let ((mo (string-to-number (match-string 2 value)))
        (dy (string-to-number (match-string 3 value))))
    (unless (<= 1 mo 12) (error "jetpacs: date month must be 01-12, got %S" value))
    (unless (<= 1 dy 31) (error "jetpacs: date day must be 01-31, got %S" value)))
  value)

(defun jetpacs--check-time (value)
  "Signal unless VALUE is a §17.4 time `HH:MM' with in-range fields."
  (unless (and (stringp value)
               (string-match "\\`\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)\\'" value))
    (error "jetpacs: time value must be HH:MM (SPEC 17.4), got %S" value))
  (let ((hh (string-to-number (match-string 1 value)))
        (mm (string-to-number (match-string 2 value))))
    (unless (<= 0 hh 23) (error "jetpacs: time hour must be 00-23, got %S" value))
    (unless (<= 0 mm 59) (error "jetpacs: time minute must be 00-59, got %S" value)))
  value)

(defun jetpacs--check-font-weight (v)
  "Signal unless V is a §17.1 font weight: the string \"normal\" or \"bold\",
or an integer multiple of 100 from 100 through 900."
  (unless (or (member v '("normal" "bold"))
              (and (integerp v) (<= 100 v 900) (zerop (mod v 100))))
    (error "jetpacs: font_weight must be \"normal\"/\"bold\" or an integer multiple of 100 in 100..900, got %S" v))
  v)

(defun jetpacs--check-badge (v)
  "Signal unless V is a §17.2 badge value (a string or a number); return V."
  (unless (or (stringp v) (numberp v))
    (error "jetpacs: badge must be a string or number, got %S" v))
  v)

(defun jetpacs--check-image-url (url)
  "Signal unless URL is an advertised §17.2 image form: https or data:image.
Only the URI FORM is checked here; per-target feature advertisement is a
runtime concern (JW-7)."
  (unless (and (stringp url)
               (or (string-prefix-p "https://" url)
                   (string-prefix-p "data:image/" url)))
    (error "jetpacs: image url must be https:// or data:image/ (SPEC 17.2), got %S" url))
  (when (string-prefix-p "data:image/svg+xml" url)
    (error "jetpacs: data:image/svg+xml is an active format, rejected before decode (SPEC 17.2)"))
  url)

;;;; The node funnel

(defun jetpacs--node (type &rest kvs)
  "Build a node plist of TYPE from KVS, alternating KEYWORD VALUE pairs.
Pairs whose VALUE is nil are omitted, so optional members read as plain
keyword arguments at the call site.  Emit JSON false as the value
`:json-false' (it survives the nil-drop); leave an absent member out.
TYPE nil builds a bare plist with no `:t' discriminator, used by
sub-specs (action descriptors, spans, table cells) that carry no type."
  (let (body)
    (while kvs
      (let ((k (pop kvs)) (v (pop kvs)))
        (when v (push k body) (push v body))))
    (setq body (nreverse body))
    (if type (cons :t (cons type body)) body)))

(defun jetpacs--node-p (x)
  "Non-nil when X is a single node/sub-spec plist (car is a keyword).
A list *of* nodes has a cons as its car instead, which is what lets
`jetpacs--as-children' tell one node from a list of children."
  (and (consp x) (keywordp (car x))))

(defun jetpacs--root-node-p (x)
  "Non-nil when X is a typed Node: a plist whose head is `:t' (§16.1).
Stricter than `jetpacs--node-p', which also accepts `:t'-less sub-specs
\(action descriptors, spans, table cells).  Use where a root Node is required."
  (and (consp x) (eq (car x) :t)))

(defun jetpacs--wire-name (key)
  "The contract member name the option keyword KEY addresses.
A constructor spells a multi-word member with a hyphen (`:content-padding'
for `content_padding'); the §16.5 universal attributes keep the wire
spelling (`:scroll_here'), so mapping hyphen to underscore is correct for
both and lossless (no contract member name contains a hyphen)."
  (string-replace "-" "_" (substring (symbol-name key) 1)))

(defconst jetpacs--universal-wire-names
  (mapcar #'jetpacs--wire-name jetpacs-universal-attributes)
  "`jetpacs-universal-attributes' as contract member names.")

(defun jetpacs--check-options (type opts)
  "Signal unless every option keyword in OPTS is a member of node TYPE.
The `&rest'-children containers read their options with `plist-get', so
before this an unknown key was SILENTLY DROPPED — a typo (`:spacng') and,
far more often, a universal attribute passed where it does not belong
\(`(jetpacs-row … :padding 8)' emitted a row with no padding).  The
`cl-defun &key' constructors have always refused an unknown keyword; this
gives the containers the same guarantee, against the generated
`jetpacs-node-schema' so an amendment cannot leave it behind."
  (let* ((row (assoc type jetpacs-node-schema))
         (allowed (append (nth 1 row) (nth 2 row)))
         (p opts))
    (unless row
      (error "jetpacs: no contract schema for node type %S" type))
    (while p
      (let* ((key (pop p))
             (name (jetpacs--wire-name key)))
        (pop p)                         ; the value
        (unless (member name allowed)
          (if (member name jetpacs--universal-wire-names)
              (error "jetpacs-%s: %S is a universal attribute (SPEC 16.5), not a `%s' member; attach it with `jetpacs-with-attrs'"
                     type key type)
            (error "jetpacs-%s: %S is not a member of `%s' (SPEC 16.1); members are %S"
                   type key type allowed)))))))

(defun jetpacs--children-and-opts (args &optional type)
  "Split container ARGS into (CHILDREN . OPTS) at the first keyword.
Child nodes are plists; the first bare keyword in ARGS marks the start of
the trailing options plist.  Lets a `&rest'-children constructor take
options: `(jetpacs-row a b :spacing 8)' separates cleanly.  A single LIST
of children works too — `(jetpacs-row (list a b) :spacing 8)' — which is
what to reach for when the children are computed.

TYPE, when given, names the node type whose contract members the trailing
options are validated against (`jetpacs--check-options')."
  (let* ((i (cl-position-if #'keywordp args))
         (split (if i (cons (cl-subseq args 0 i) (cl-subseq args i))
                  (cons args nil))))
    (when type (jetpacs--check-options type (cdr split)))
    split))

(defun jetpacs--as-children (args)
  "Normalize container ARGS to a child VECTOR (a JSON array), dropping nils.
Accepts nodes as `&rest' -- (NODE NODE ...) -- or as a single list
argument -- ((NODE NODE ...)) or a lone nil -- so `(jetpacs-row (list a
b))' and `(jetpacs-row a b)' mean the same."
  (let ((kids (if (and (consp args) (null (cdr args))
                       (let ((only (car args)))
                         (or (null only)
                             (and (proper-list-p only)
                                  (cl-every #'jetpacs--node-p only)))))
                  (car args)
                args)))
    (vconcat (remq nil kids))))

;;;; Universal attributes (§16.5) and colors (§16.6)

(defun jetpacs-with-attrs (node &rest attrs)
  "Return NODE (a node plist) with universal ATTRS merged in.
ATTRS is a plist of universal attribute keywords; nil-valued members are
dropped, and a supplied attribute OVERRIDES an existing one of the same
name (last wins, no duplicate member).  Each value is validated against
its §16.5 grammar.  Signals an error on a non-universal key or an invalid
value.  NODE is not mutated."
  (let ((out (copy-sequence node)))
    (while attrs
      (let ((k (pop attrs)) (v (pop attrs)))
        (when v
          (unless (memq k jetpacs-universal-attributes)
            (error "jetpacs-with-attrs: %S is not a universal attribute" k))
          (jetpacs--check-attr k v)
          (setq out (plist-put out k v)))))
    out))

(defun jetpacs-color-valid-p (color)
  "Non-nil when COLOR is a KNOWN §16.6 color: a standard theme role or hex.
An unknown role is still legal on the wire (the Companion falls back to a
legible color); this predicate is a builder-side sanity check for standard
roles, not a gate.  Attribute validation uses the looser `jetpacs--check-color'
(any §4.4 identifier), which accepts unknown roles."
  (and (stringp color)
       (or (member color jetpacs-theme-roles)
           (string-match-p jetpacs--hex-color-re color))))

;;;; Canonical serialization
;;
;; Test / regeneration only -- NOT the live push path (that is jsonrpc.el
;; inside ebp.el).  Reproduces the goldens' own formula, `json.dumps(obj,
;; sort_keys=True, separators=(",",":"), ensure_ascii=False)'
;; (ebp/validate.py), so builder output can be compared byte-for-byte to
;; `ebp/goldens/'.  Emacs `json-serialize' is already compact and emits
;; raw UTF-8; the one thing it does not do is sort keys.

(defun jetpacs-node->canonical-json (value)
  "Serialize VALUE to canonical EBP JSON (keys sorted recursively, compact).
Objects are keyword-keyed plists; arrays are vectors; JSON true/false are
elisp `t'/`:json-false'; nil-valued object members are dropped; numbers
keep their elisp int/float type.  Leaf strings and numbers are escaped by
`json-serialize'."
  (cond
   ((eq value t) "true")
   ((eq value :json-false) "false")
   ((eq value :false) "false")           ; tolerate ebp.el's strict sentinel
   ((vectorp value)
    (concat "[" (mapconcat #'jetpacs-node->canonical-json value ",") "]"))
   ((hash-table-p value)                  ; a string-keyed JSON object (e.g. month_grid marks)
    (let (pairs)
      (maphash (lambda (k v) (push (cons k v) pairs)) value)
      (setq pairs (sort pairs (lambda (a b) (string< (car a) (car b)))))
      (concat "{"
              (mapconcat (lambda (p)
                           (concat (json-serialize (car p)) ":"
                                   (jetpacs-node->canonical-json (cdr p))))
                         pairs ",")
              "}")))
   ((and (consp value) (keywordp (car value)))
    (let (pairs (kvs value))
      (while kvs
        (let ((k (pop kvs)) (v (pop kvs)))
          (when v
            (push (cons (substring (symbol-name k) 1) v) pairs))))
      (setq pairs (sort pairs (lambda (a b) (string< (car a) (car b)))))
      (concat "{"
              (mapconcat (lambda (p)
                           (concat (json-serialize (car p)) ":"
                                   (jetpacs-node->canonical-json (cdr p))))
                         pairs ",")
              "}")))
   (t (json-serialize value))))

;;;; Action descriptors (§14)

(cl-defun jetpacs-action (name &key args when-offline dedupe ttl-s confirm
                               capture-fields)
  "Build a remote ActionDescriptor for action NAME (SPEC §14.1).
NAME MUST be a §4.4 namespaced identifier containing at least one dot.
WHEN-OFFLINE is `drop' (the default), `queue', or `wake' (symbol or
string); `queue'/`wake' require TTL-S to be an integer in 1..604800, and
`drop' forbids both TTL-S and DEDUPE.  DEDUPE is an identifier, CONFIRM a
non-empty string, ARGS a member plist, CAPTURE-FIELDS a list of distinct
field-id strings.  Statically invalid input signals an error at build time."
  (unless (and (jetpacs--identifier-p name) (string-search "." name))
    (error "jetpacs-action: action name %S must be a §4.4 namespaced identifier containing a dot (SPEC 14.1)" name))
  (let* ((policy (and when-offline (format "%s" when-offline)))
         (effective (or policy "drop")))
    (cond
     ((member effective '("queue" "wake"))
      (unless (and (integerp ttl-s) (<= 1 ttl-s 604800))
        (error "jetpacs-action: `%s' requires :ttl-s an integer 1..604800 (SPEC 14.1), got %S"
               effective ttl-s)))
     ((equal effective "drop")
      (when ttl-s (error "jetpacs-action: :ttl-s is invalid for `drop' (SPEC 14.1)"))
      (when dedupe (error "jetpacs-action: :dedupe is invalid for `drop' (SPEC 14.1)")))
     (t (error "jetpacs-action: unknown offline policy `%s' (SPEC 14.1)" effective)))
    (when dedupe (jetpacs--check-identifier dedupe ":dedupe"))
    (when confirm
      ;; §14.1: a bare string, or the object form
      ;; {:text REQ, :title, :icon, :confirm-label, :dismiss-label} — the
      ;; face of the AlertDialog the Companion parks the dispatch behind.
      (cond
       ((stringp confirm)
        (when (string-empty-p confirm)
          (error "jetpacs-action: :confirm must be a non-empty string (SPEC 14.1)")))
       ((and (consp confirm) (keywordp (car confirm)))
        (let ((text (plist-get confirm :text)))
          (unless (and (stringp text) (not (string-empty-p text)))
            (error "jetpacs-action: :confirm object needs a non-empty :text (SPEC 14.1)")))
        (cl-loop for (key value) on confirm by #'cddr
                 do (pcase key
                      (:text)
                      ((or :title :confirm-label :dismiss-label)
                       (jetpacs--require-string value (symbol-name key)))
                      (:icon (jetpacs--check-identifier value ":icon"))
                      (_ (error "jetpacs-action: unknown :confirm key %S (SPEC 14.1)" key))))
        (setq confirm (jetpacs--node nil
                                     :text (plist-get confirm :text)
                                     :title (plist-get confirm :title)
                                     :icon (plist-get confirm :icon)
                                     :confirm_label (plist-get confirm :confirm-label)
                                     :dismiss_label (plist-get confirm :dismiss-label))))
       (t (error "jetpacs-action: :confirm must be a string or a plist (SPEC 14.1), got %S" confirm))))
    (when capture-fields (jetpacs--check-capture-fields capture-fields))
    (when args
      (unless (and (consp args) (keywordp (car args)))
        (error "jetpacs-action: :args must be a member plist, got %S" args)))
    (jetpacs--node nil
                   :action name
                   :args args
                   :when_offline policy
                   :dedupe dedupe
                   :ttl_s ttl-s
                   :confirm confirm
                   :capture_fields (and capture-fields (vconcat capture-fields)))))

(defun jetpacs-view-switch (view)
  "A `view.switch' builtin action selecting multi-view VIEW (SPEC §14.2).
VIEW is a §4.4 identifier."
  (jetpacs--check-identifier view ":view")
  (jetpacs--node nil :builtin "view.switch" :view view))

(defun jetpacs-clipboard-copy (text)
  "A `clipboard.copy' builtin action copying string TEXT (SPEC §14.2)."
  (jetpacs--require-string text ":text")
  (jetpacs--node nil :builtin "clipboard.copy" :text text))

(cl-defun jetpacs-share (text &key title)
  "A `share.send' builtin action sharing string TEXT with optional TITLE (§14.2)."
  (jetpacs--require-string text ":text")
  (when title (jetpacs--require-string title ":title"))
  (jetpacs--node nil :builtin "share.send" :text text :title title))

(defun jetpacs-settings-open ()
  "A `companion.settings.open' builtin action (SPEC §14.2)."
  (jetpacs--node nil :builtin "companion.settings.open"))

(defun jetpacs-trigger-fire (id)
  "A `trigger.fire' builtin action firing the manual trigger ID (SPEC §14.2).
ID is a §4.4 identifier."
  (jetpacs--check-identifier id ":id")
  (jetpacs--node nil :builtin "trigger.fire" :id id))

(cl-defun jetpacs-dialog-submit (&key value capture-fields)
  "A `dialog.submit' builtin action (SPEC §14.2).
VALUE is the submitted scalar (any non-secret JSON value); CAPTURE-FIELDS a
list of distinct field ids to gather."
  (when capture-fields (jetpacs--check-capture-fields capture-fields))
  (jetpacs--node nil :builtin "dialog.submit"
                 :value value
                 :capture_fields (and capture-fields (vconcat capture-fields))))

(defun jetpacs-dialog-dismiss ()
  "A `dialog.dismiss' builtin action (SPEC §14.2)."
  (jetpacs--node nil :builtin "dialog.dismiss"))

;;;; Content nodes (§17.2)
;;
;; Type-specific members only.  Attach universal §16.5 attributes (key,
;; padding, width, ...) with `jetpacs-with-attrs'.

(cl-defun jetpacs-text (text &key style font-weight color selectable max-lines syntax)
  "A text node showing plain string TEXT (SPEC §17.2).
STYLE is body/title/headline/caption/label/mono; FONT-WEIGHT a weight name
or a number 100..900; COLOR a §16.6 color; SELECTABLE non-nil to allow
selection; MAX-LINES a positive-integer clamp; SYNTAX a §4.4 identifier
naming a highlighter."
  (jetpacs--require-string text ":text")
  (when style (setq style (jetpacs--check-enum style jetpacs--text-styles ":style")))
  (when font-weight (jetpacs--check-font-weight font-weight))
  (when color (jetpacs--check-color color))
  (when max-lines (jetpacs--check-integer max-lines ":max_lines" 1 nil))
  (when syntax (jetpacs--check-identifier syntax ":syntax"))
  (jetpacs--node "text"
                 :text text
                 :style style
                 :font_weight font-weight
                 :color color
                 :selectable (jetpacs--flag selectable)
                 :max_lines max-lines
                 :syntax syntax))

(cl-defun jetpacs-span (text &key font-weight italic underline color bg mono on-tap)
  "A styled text run for `jetpacs-rich-text' (SPEC §17.2 RichSpan).
Plain-text TEXT; FONT-WEIGHT a name or 100..900; ITALIC/UNDERLINE/MONO
non-nil to enable; COLOR/BG §16.6 colors; ON-TAP an ActionDescriptor that
makes the run a link."
  (jetpacs--require-string text ":text")
  (when font-weight (jetpacs--check-font-weight font-weight))
  (when color (jetpacs--check-color color))
  (when bg (jetpacs--check-color bg))
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (jetpacs--node nil
                 :text text
                 :font_weight font-weight
                 :italic (jetpacs--flag italic)
                 :underline (jetpacs--flag underline)
                 :color color
                 :bg bg
                 :mono (jetpacs--flag mono)
                 :on_tap on-tap))

(cl-defun jetpacs-rich-text (spans &key style)
  "A rich-text node rendering SPANS, a list from `jetpacs-span' (SPEC §17.2).
STYLE is the base text style."
  (when style (setq style (jetpacs--check-enum style jetpacs--text-styles ":style")))
  (jetpacs--node "rich_text" :spans (vconcat spans) :style style))

(cl-defun jetpacs-icon (name &key size color badge content-description)
  "An icon node named NAME, a string (SPEC §17.2; amendment 64).
An unresolved NAME renders a placeholder or nothing, so any string is
valid input.  SIZE a non-negative dp; COLOR a §16.6 color; BADGE a string
or number; CONTENT-DESCRIPTION an accessibility label."
  (jetpacs--require-string name ":name")
  (when size (jetpacs--check-number size ":size" 0 nil))
  (when color (jetpacs--check-color color))
  (when badge (jetpacs--check-badge badge))
  (when content-description (jetpacs--require-string content-description ":content_description"))
  (jetpacs--node "icon" :name name :size size :color color :badge badge
                 :content_description content-description))

(cl-defun jetpacs-image (url &key content-scale content-description)
  "An image node loading URL (SPEC §17.2).
URL MUST be an advertised form: an https URL or a data:image URI.
CONTENT-SCALE is fit/crop/fill; CONTENT-DESCRIPTION an accessibility label.
Size it with the universal `width'/`height'/`aspect_ratio' via
`jetpacs-with-attrs'."
  (jetpacs--check-image-url url)
  (when content-scale
    (setq content-scale (jetpacs--check-enum content-scale '("fit" "crop" "fill") ":content_scale")))
  (when content-description (jetpacs--require-string content-description ":content_description"))
  (jetpacs--node "image" :url url :content_scale content-scale
                 :content_description content-description))

(cl-defun jetpacs-date-stamp (&key day month month-index year time)
  "A date-stamp node (SPEC §17.2); at least one member SHOULD be present.
DAY is an integer 1..31, MONTH-INDEX 1..12, YEAR a non-negative integer;
MONTH and TIME are display strings."
  (when day (jetpacs--check-integer day ":day" 1 31))
  (when month (jetpacs--require-string month ":month"))
  (when month-index (jetpacs--check-integer month-index ":month_index" 1 12))
  (when year (jetpacs--check-integer year ":year" 0 nil))
  (when time (jetpacs--require-string time ":time"))
  (jetpacs--node "date_stamp" :day day :month month :month_index month-index
                 :year year :time time))

(cl-defun jetpacs-section-header (title &key trailing)
  "A section-header node titled TITLE (a string) (SPEC §17.2).
Optional TRAILING is a single node shown at the header's end."
  (jetpacs--require-string title ":title")
  (jetpacs--node "section_header" :title title :trailing trailing))

(cl-defun jetpacs-empty-state (&key icon title caption action-label on-tap)
  "An empty-state placeholder (SPEC §17.2).
ICON is a §4.4 identifier; TITLE/CAPTION/ACTION-LABEL are strings; ON-TAP
an ActionDescriptor.  ACTION-LABEL and ON-TAP are both-or-neither."
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when title (jetpacs--require-string title ":title"))
  (when caption (jetpacs--require-string caption ":caption"))
  (when action-label (jetpacs--require-string action-label ":action_label"))
  (unless (eq (null action-label) (null on-tap))
    (error "jetpacs-empty-state: :action-label and :on-tap are both-or-neither (SPEC 17.2)"))
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (jetpacs--node "empty_state" :icon icon :title title :caption caption
                 :action_label action-label :on_tap on-tap))

(defconst jetpacs--progress-variants
  '("circular" "linear" "linear_wavy" "circular_wavy"
    "loading" "contained_loading")
  "SPEC §17.2 `progress.variant'.  The four expressive members draw M3's
wavy indicators and its LoadingIndicator; `value' still decides
determinate vs indeterminate for every one of them, so no second member
is needed.")

(cl-defun jetpacs-progress (&key variant value)
  "A progress node (SPEC §17.2).
VARIANT is one of `jetpacs--progress-variants' (circular by default);
VALUE a number 0..1 (omit for indeterminate)."
  (when variant (setq variant (jetpacs--check-enum variant jetpacs--progress-variants ":variant")))
  (when value (jetpacs--check-number value ":value" 0 1))
  (jetpacs--node "progress" :variant variant :value value))

(cl-defun jetpacs-badge (label &key icon color children)
  "A badge node showing string LABEL (SPEC §17.2).
An empty LABEL renders an attention dot.  ICON is a §4.4 identifier; COLOR
a §16.6 color; CHILDREN a list of nodes the badge annotates."
  (jetpacs--require-string label ":label")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when color (jetpacs--check-color color))
  (jetpacs--node "badge" :label label :icon icon :color color
                 :children (and children (vconcat children))))

;;;; Layout nodes (§17.3)
;;
;; Containers take child nodes as `&rest' args followed by keyword options
;; (split by `jetpacs--children-and-opts').  Booleans that a golden emits
;; as explicit `false' (row/column `scroll', `tabs.pager_only') accept
;; `t' or `:json-false' and are validated by `jetpacs--check-bool'.

(defconst jetpacs--row-aligns '("top" "center" "bottom" "baseline"))
(defconst jetpacs--column-aligns '("start" "center" "end"))
(defconst jetpacs--flow-aligns '("top" "center" "bottom"))
(defconst jetpacs--arranges
  '("start" "center" "end" "space_between" "space_around" "space_evenly"))
(defconst jetpacs--box-alignments
  '("top_start" "top_center" "top_end" "center_start" "center" "center_end"
    "bottom_start" "bottom_center" "bottom_end"))
(defconst jetpacs--surface-shapes '("rounded" "rounded_small" "circle"))
(defconst jetpacs--table-aligns '("start" "center" "end"))

(defun jetpacs-row (&rest args)
  "A horizontal row of child nodes (SPEC §17.3).
Trailing options: :spacing (dp), :align (top/center/bottom/baseline),
:arrange (start/center/end/space_between/space_around/space_evenly),
:scroll, :fill (booleans t or :json-false)."
  (let* ((split (jetpacs--children-and-opts args "row"))
         (opts (cdr split))
         (spacing (plist-get opts :spacing))
         (align (plist-get opts :align))
         (arrange (plist-get opts :arrange))
         (scroll (plist-get opts :scroll))
         (fill (plist-get opts :fill)))
    (when spacing (jetpacs--check-number spacing ":spacing" 0 nil))
    (when align (setq align (jetpacs--check-enum align jetpacs--row-aligns ":align")))
    (when arrange (setq arrange (jetpacs--check-enum arrange jetpacs--arranges ":arrange")))
    (when scroll (jetpacs--check-bool scroll ":scroll"))
    (when fill (jetpacs--check-bool fill ":fill"))
    (jetpacs--node "row"
                   :children (jetpacs--as-children (car split))
                   :spacing spacing :align align :arrange arrange
                   :scroll scroll :fill fill)))

(defun jetpacs-column (&rest args)
  "A vertical column of child nodes (SPEC §17.3).
Trailing options: :spacing, :align (start/center/end), :arrange, :scroll,
:fill (booleans t or :json-false)."
  (let* ((split (jetpacs--children-and-opts args "column"))
         (opts (cdr split))
         (spacing (plist-get opts :spacing))
         (align (plist-get opts :align))
         (arrange (plist-get opts :arrange))
         (scroll (plist-get opts :scroll))
         (reverse-scroll (plist-get opts :reverse-scroll))
         (fill (plist-get opts :fill)))
    (when spacing (jetpacs--check-number spacing ":spacing" 0 nil))
    (when reverse-scroll (jetpacs--check-bool reverse-scroll ":reverse-scroll"))
    (when align (setq align (jetpacs--check-enum align jetpacs--column-aligns ":align")))
    (when arrange (setq arrange (jetpacs--check-enum arrange jetpacs--arranges ":arrange")))
    (when scroll (jetpacs--check-bool scroll ":scroll"))
    (when fill (jetpacs--check-bool fill ":fill"))
    (jetpacs--node "column"
                   :children (jetpacs--as-children (car split))
                   :reverse_scroll reverse-scroll
                   :spacing spacing :align align :arrange arrange
                   :scroll scroll :fill fill)))

(defun jetpacs-flow-row (&rest args)
  "A flow row whose children wrap to later runs (SPEC §17.3).
Trailing options: :spacing, :run-spacing (dp), :align (top/center/bottom),
:arrange."
  (let* ((split (jetpacs--children-and-opts args "flow_row"))
         (opts (cdr split))
         (spacing (plist-get opts :spacing))
         (run-spacing (plist-get opts :run-spacing))
         (align (plist-get opts :align))
         (arrange (plist-get opts :arrange)))
    (when spacing (jetpacs--check-number spacing ":spacing" 0 nil))
    (when run-spacing (jetpacs--check-number run-spacing ":run_spacing" 0 nil))
    (when align (setq align (jetpacs--check-enum align jetpacs--flow-aligns ":align")))
    (when arrange (setq arrange (jetpacs--check-enum arrange jetpacs--arranges ":arrange")))
    (jetpacs--node "flow_row"
                   :children (jetpacs--as-children (car split))
                   :spacing spacing :run_spacing run-spacing
                   :align align :arrange arrange)))

(defun jetpacs-box (&rest args)
  "A box (z-stack, back-to-front) of child nodes (SPEC §17.3).
Trailing options: :alignment (top_start..bottom_end), :on-tap."
  (let* ((split (jetpacs--children-and-opts args "box"))
         (opts (cdr split))
         (alignment (plist-get opts :alignment))
         (on-tap (plist-get opts :on-tap)))
    (when alignment
      (setq alignment (jetpacs--check-enum alignment jetpacs--box-alignments ":alignment")))
    (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
    (jetpacs--node "box"
                   :children (jetpacs--as-children (car split))
                   :alignment alignment
                   :on_tap on-tap)))

(defun jetpacs-surface (&rest args)
  "A visual surface container (SPEC §17.3; distinct from a protocol Surface).
Options: :color, :shape (rounded/rounded_small/circle), :elevation (a
dp of TONAL elevation) and :shadow-elevation (a dp of the cast shadow).
They are different things: M3 spends `elevation' on tonalElevation, which
recolors nothing unless the container is the surface role, so a floating
container needs :shadow-elevation to actually float."
  (let* ((split (jetpacs--children-and-opts args "surface"))
         (opts (cdr split))
         (color (plist-get opts :color))
         (shape (plist-get opts :shape))
         (elevation (plist-get opts :elevation))
         (shadow (plist-get opts :shadow-elevation)))
    (when color (jetpacs--check-color color))
    (when shape (setq shape (jetpacs--check-enum shape jetpacs--surface-shapes ":shape")))
    (when elevation (jetpacs--check-number elevation ":elevation" 0 nil))
    (when shadow (jetpacs--check-number shadow ":shadow_elevation" 0 nil))
    (jetpacs--node "surface"
                   :children (jetpacs--as-children (car split))
                   :color color :shape shape :elevation elevation
                   :shadow_elevation shadow)))

(defun jetpacs-lazy-column (&rest args)
  "A lazily-composed vertical list preserving array order (SPEC §17.3).
Trailing options: :spacing (dp), :content-padding (dp)."
  (let* ((split (jetpacs--children-and-opts args "lazy_column"))
         (opts (cdr split))
         (spacing (plist-get opts :spacing))
         (content-padding (plist-get opts :content-padding)))
    (when spacing (jetpacs--check-number spacing ":spacing" 0 nil))
    (when content-padding (jetpacs--check-number content-padding ":content_padding" 0 nil))
    (jetpacs--node "lazy_column"
                   :children (jetpacs--as-children (car split))
                   :spacing spacing :content_padding content-padding)))

(defun jetpacs-spacer ()
  "A spacer node (SPEC §17.3); size it with universal width/height/weight."
  (jetpacs--node "spacer"))

(cl-defun jetpacs-divider (&key color thickness)
  "A divider node (SPEC §17.3).
COLOR is a §16.6 color; THICKNESS a non-negative dp."
  (when color (jetpacs--check-color color))
  (when thickness (jetpacs--check-number thickness ":thickness" 0 nil))
  (jetpacs--node "divider" :color color :thickness thickness))

(cl-defun jetpacs-swipe (label &key icon color on-trigger)
  "A swipe side {label, icon?, color?, on_trigger} for card/collapsible (§17.3).
LABEL is a string; ICON a §4.4 identifier; COLOR a §16.6 color; ON-TRIGGER
an ActionDescriptor dispatched at most once per gesture."
  (jetpacs--require-string label ":label")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when color (jetpacs--check-color color))
  (jetpacs--check-descriptor on-trigger ":on-trigger")   ; required (§17.3)
  (jetpacs--node nil :label label :icon icon :color color :on_trigger on-trigger))

(defconst jetpacs--card-variants '("filled" "elevated" "outlined"))

(defconst jetpacs--pane-scaffold-variants '("list_detail" "supporting"))

(cl-defun jetpacs-pane-scaffold (list detail &key extra variant)
  "An adaptive two- or three-pane layout (SPEC §17.3).

LIST and DETAIL are the two panes; EXTRA is an optional third.  The
Companion places them BY WINDOW SIZE — side by side where there is room,
one at a time where there is not — which is the whole point of the node,
and the reason a `row' of two columns is not a substitute: a row is the
wide layout always, on every screen.

VARIANT is list_detail (default) or supporting, which is M3's other pane
ROLE assignment (a main pane with a supporting one), not a different
layout engine."
  (unless (jetpacs--root-node-p list)
    (error "jetpacs-pane-scaffold: LIST must be a node, got %S" list))
  (unless (jetpacs--root-node-p detail)
    (error "jetpacs-pane-scaffold: DETAIL must be a node, got %S" detail))
  (when (and extra (not (jetpacs--root-node-p extra)))
    (error "jetpacs-pane-scaffold: :extra must be a node, got %S" extra))
  (when variant
    (setq variant (jetpacs--check-enum variant jetpacs--pane-scaffold-variants
                                       ":variant")))
  (jetpacs--node "pane_scaffold" :list list :detail detail
                 :extra extra :variant variant))

(defun jetpacs-card (&rest args)
  "A card container of child nodes (SPEC §17.3).
Trailing options: :on-tap, :on-long-tap (ActionDescriptors); :swipe-start,
:swipe-end (from `jetpacs-swipe'); :variant, one of
`jetpacs--card-variants' (elevated by default, which is what the
Companion has always drawn)."
  (let* ((split (jetpacs--children-and-opts args "card"))
         (opts (cdr split))
         (on-tap (plist-get opts :on-tap))
         (on-long-tap (plist-get opts :on-long-tap))
         (swipe-start (plist-get opts :swipe-start))
         (swipe-end (plist-get opts :swipe-end))
         (variant (plist-get opts :variant)))
    (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
    (when on-long-tap (jetpacs--check-descriptor on-long-tap ":on-long-tap"))
    (when swipe-start (jetpacs--check-swipe swipe-start ":swipe-start"))
    (when swipe-end (jetpacs--check-swipe swipe-end ":swipe-end"))
    (when variant
      (setq variant (jetpacs--check-enum variant jetpacs--card-variants ":variant")))
    (jetpacs--node "card"
                   :children (jetpacs--as-children (car split))
                   :on_tap on-tap
                   :on_long_tap on-long-tap
                   :swipe_start swipe-start
                   :swipe_end swipe-end
                   :variant variant)))

(cl-defun jetpacs-collapsible (id header &rest args)
  "A collapsible section with required ID and HEADER node, plus children (§17.3).
Trailing options: :collapsed (t or :json-false), :on-long-tap, :swipe-start,
:swipe-end."
  (jetpacs--check-identifier id ":id")
  (unless (jetpacs--node-p header)
    (error "jetpacs-collapsible: HEADER must be a node, got %S" header))
  (let* ((split (jetpacs--children-and-opts args "collapsible"))
         (opts (cdr split))
         (collapsed (plist-get opts :collapsed))
         (on-long-tap (plist-get opts :on-long-tap))
         (swipe-start (plist-get opts :swipe-start))
         (swipe-end (plist-get opts :swipe-end)))
    (when collapsed (jetpacs--check-bool collapsed ":collapsed"))
    (when on-long-tap (jetpacs--check-descriptor on-long-tap ":on-long-tap"))
    (when swipe-start (jetpacs--check-swipe swipe-start ":swipe-start"))
    (when swipe-end (jetpacs--check-swipe swipe-end ":swipe-end"))
    (jetpacs--node "collapsible"
                   :id id :header header
                   :children (jetpacs--as-children (car split))
                   :collapsed collapsed
                   :on_long_tap on-long-tap
                   :swipe_start swipe-start
                   :swipe_end swipe-end)))

(cl-defun jetpacs-reorderable-list (items &key on-reorder)
  "A reorderable list of ITEMS (SPEC §17.3).
Every item MUST carry a unique `key' or `id'; ON-REORDER is an
ActionDescriptor.  ITEMS is a list of node plists."
  (let (seen)
    (dolist (it items)
      (let ((k (or (plist-get it :key) (plist-get it :id))))
        (unless k
          (error "jetpacs-reorderable-list: every item needs a :key or :id (SPEC 17.3)"))
        (when (member k seen)
          (error "jetpacs-reorderable-list: duplicate item key/id %S (SPEC 17.3)" k))
        (push k seen))))
  (when on-reorder (jetpacs--check-descriptor on-reorder ":on-reorder"))
  (jetpacs--node "reorderable_list"
                 :items (vconcat items)
                 :on_reorder on-reorder))

(defconst jetpacs--tab-icon-positions '("above" "leading"))

(cl-defun jetpacs-tab-item (&optional label &key icon icon-position badge
                                      tooltip)
  "A TabItem for `jetpacs-tabs' (SPEC §17.3).

LABEL may be omitted WHEN ICON is present, which is how M3 draws its
icon-only 48dp tab.  Passing the empty string is NOT the same thing: an
empty label still fills the text slot and forces the 72dp two-line tab
with a blank line in it.

ICON-POSITION is above (default) or leading — the latter is M3's
LeadingIconTab, a single row of icon then label.  BADGE is a string or
number drawn over the tab, empty meaning the bare attention dot.
TOOLTIP is the plain tooltip M3 wants over an icon-only tab, anchored
above; a screen reader hears the icon's fallback name either way, so
the tooltip is the SIGHTED user's label, not a replacement for one."
  (when label (jetpacs--require-string label ":label"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (unless (or label icon)
    (error "jetpacs-tab-item: a tab needs a :label, an :icon, or both (SPEC 17.3)"))
  (when icon-position
    (setq icon-position (jetpacs--check-enum icon-position
                                             jetpacs--tab-icon-positions
                                             ":icon-position"))
    (unless icon
      (error "jetpacs-tab-item: :icon-position needs an :icon (SPEC 17.3)")))
  (when badge (jetpacs--check-badge badge))
  (when tooltip (jetpacs--require-string tooltip ":tooltip"))
  (jetpacs--node nil :label label :icon icon
                 :icon_position icon-position :badge badge
                 :tooltip tooltip))

(defconst jetpacs--tab-styles '("primary" "secondary"))

(cl-defun jetpacs-tabs (items children &key initial scrollable pager-only
                              on-change id style)
  "A tab strip: parallel ITEMS (TabItems) and CHILDREN (Nodes) (SPEC §17.3).
The two lists MUST have equal non-zero length.  INITIAL is a 0-based index
below the count; SCROLLABLE/PAGER-ONLY are booleans (t or :json-false);
ON-CHANGE an ActionDescriptor; ID a §4.4 identifier.

STYLE is primary or secondary (default): M3's PrimaryTabRow draws the
content-width rounded indicator, SecondaryTabRow the full-width one the
Companion has always drawn."
  (let ((ni (length items)) (nc (length children)))
    (when (or (zerop ni) (/= ni nc))
      (error "jetpacs-tabs: items and children must be equal non-zero length (SPEC 17.3): %d vs %d"
             ni nc))
    (when initial (jetpacs--check-integer initial ":initial" 0 (1- ni)))
    (when scrollable (jetpacs--check-bool scrollable ":scrollable"))
    (when pager-only (jetpacs--check-bool pager-only ":pager-only"))
    (when id (jetpacs--check-identifier id ":id"))
    (when on-change (jetpacs--check-descriptor on-change ":on-change"))
    (when style (setq style (jetpacs--check-enum style jetpacs--tab-styles ":style")))
    (jetpacs--node "tabs"
                   :items (vconcat items)
                   :children (vconcat children)
                   :initial initial
                   :scrollable scrollable
                   :pager_only pager-only
                   :on_change on-change
                   :style style
                   :id id)))

(cl-defun jetpacs-table-cell (spans &key on-tap on-long-tap)
  "A table cell {spans, on_tap?, on_long_tap?} (SPEC §17.3).
SPANS is a list from `jetpacs-span'."
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (when on-long-tap (jetpacs--check-descriptor on-long-tap ":on-long-tap"))
  (jetpacs--node nil :spans (vconcat spans) :on_tap on-tap :on_long_tap on-long-tap))

(defun jetpacs-table-row (kind &rest cells)
  "A table row of KIND `data' or `header' with CELLS (SPEC §17.3).
CELLS are from `jetpacs-table-cell'.  For a rule row use `jetpacs-table-rule'."
  (jetpacs--node nil
                 :kind (jetpacs--check-enum kind '("data" "header") ":kind")
                 :cells (jetpacs--as-children cells)))

(defun jetpacs-table-rule ()
  "A table `rule' row, a horizontal separator with no cells (SPEC §17.3)."
  (jetpacs--node nil :kind "rule"))

(cl-defun jetpacs-table (rows &key aligns on-add-row on-add-col)
  "A table of ROWS (from `jetpacs-table-row'/`jetpacs-table-rule') (SPEC §17.3).
ALIGNS is a list of start/center/end (one per column); :on-add-row and
:on-add-col are ActionDescriptors."
  (when on-add-row (jetpacs--check-descriptor on-add-row ":on-add-row"))
  (when on-add-col (jetpacs--check-descriptor on-add-col ":on-add-col"))
  (jetpacs--node "table"
                 :rows (vconcat rows)
                 :aligns (and aligns
                              (vconcat (mapcar (lambda (a)
                                                 (jetpacs--check-enum a jetpacs--table-aligns ":aligns"))
                                               aligns)))
                 :on_add_row on-add-row
                 :on_add_col on-add-col))

;;;; Input nodes (§17.4)
;;
;; Every input has `enabled' (boolean, default true); pass `t' or
;; `:json-false' to emit it explicitly.  `on_*' fields are validated as
;; ActionDescriptors.  (The `editor' node lands with its toolbar in JW-4.)

(defconst jetpacs--button-variants
  '("filled" "tonal" "elevated" "outlined" "text"))
(defconst jetpacs--button-sizes
  '("xsmall" "small" "medium" "large" "xlarge")
  "The M3 button container scale.  A step is a COORDINATED token set —
container height, content padding, icon size, icon spacing and label
typography — never a height alone, so omitting it means the Companion's
unscaled default rather than any partial application.")
(defconst jetpacs--button-shapes '("round" "square"))
(defconst jetpacs--icon-button-variants '("filled" "tonal" "outlined"))
(defconst jetpacs--icon-button-sizes '("xsmall" "small" "medium" "large"))
(defconst jetpacs--icon-button-shapes '("round" "square"))
(defconst jetpacs--icon-button-width-modes '("narrow" "uniform" "wide")
  "How wide the container runs at a given size step: M3's
IconButtonWidthOption.  `uniform' is the default square-ish container;
`narrow' and `wide' change only the horizontal padding.")
(defconst jetpacs--chip-variants '("flat" "elevated" "input"))
(defconst jetpacs--assist-chip-variants
  '("flat" "elevated" "suggestion" "elevated_suggestion"))
(defconst jetpacs--keyboards '("text" "number" "decimal" "email" "phone" "uri"))

(cl-defun jetpacs-button (label on-tap &key icon variant size shape
                                animate-shape checked on-change enabled)
  "A button labeled LABEL dispatching ON-TAP (SPEC §17.4).
ICON a §4.4 identifier; VARIANT filled(default)/tonal/elevated/outlined/text;
SIZE one of `jetpacs--button-sizes' (omit for the unscaled default);
SHAPE round(default)/square; ANIMATE-SHAPE a boolean asking for the M3
press-state shape morph; ENABLED a boolean (t or :json-false; default true).

CHECKED makes this a TOGGLE button — the Companion holds the flipped
value on the device, keyed on the node's `:id', and ON-CHANGE receives
it.  A button carrying CHECKED is stateful and so REQUIRES an `:id'
unique across the document (§16.1); a plain button carries neither."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when variant (setq variant (jetpacs--check-enum variant jetpacs--button-variants ":variant")))
  (when size (setq size (jetpacs--check-enum size jetpacs--button-sizes ":size")))
  (when shape (setq shape (jetpacs--check-enum shape jetpacs--button-shapes ":shape")))
  (when animate-shape (jetpacs--check-bool animate-shape ":animate_shape"))
  (when checked (jetpacs--check-bool checked ":checked"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "button" :label label :on_tap on-tap
                 :icon icon :variant variant :size size :shape shape
                 :animate_shape animate-shape
                 :checked checked :on_change on-change :enabled enabled))

(cl-defun jetpacs-icon-button (icon on-tap &key content-description badge
                                    variant size shape width-mode
                                    checked checked-icon on-change
                                    color enabled)
  "An icon button showing ICON dispatching ON-TAP (SPEC §17.4).
ICON is a §4.4 identifier (§17.1); BADGE a string or number; VARIANT
filled/tonal/outlined (omit for the plain, container-less icon button).
COLOR is a §16.6 color tinting the glyph — the node draws its own Icon,
so no universal attribute could reach it.

CHECKED makes this a toggle (device-held, keyed on `:id', which such a
node then REQUIRES); CHECKED-ICON is the identifier drawn while checked,
and ON-CHANGE receives the flipped boolean."
  (jetpacs--check-identifier icon ":icon")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when content-description (jetpacs--require-string content-description ":content_description"))
  (when badge (jetpacs--check-badge badge))
  (when variant (setq variant (jetpacs--check-enum variant jetpacs--icon-button-variants ":variant")))
  (when size (setq size (jetpacs--check-enum size jetpacs--icon-button-sizes ":size")))
  (when shape (setq shape (jetpacs--check-enum shape jetpacs--icon-button-shapes ":shape")))
  (when width-mode
    (setq width-mode (jetpacs--check-enum width-mode
                                          jetpacs--icon-button-width-modes
                                          ":width-mode")))
  (when checked (jetpacs--check-bool checked ":checked"))
  (when checked-icon (jetpacs--check-identifier checked-icon ":checked_icon"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when color (jetpacs--check-color color))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "icon_button" :icon icon :on_tap on-tap
                 :content_description content-description :badge badge
                 :variant variant :size size :shape shape
                 :width_mode width-mode
                 :checked checked :checked_icon checked-icon
                 :on_change on-change :color color :enabled enabled))

(defconst jetpacs--search-bar-variants '("full_screen" "docked"))

(cl-defun jetpacs-search-bar (id &rest args)
  "A search bar identified by ID, with its results as children (§17.4).

The bar holds its QUERY on the device, keyed on ID, exactly as
`text_input' does — so ID is required and must be unique across the
document.  CHILDREN are what the bar reveals when it EXPANDS: the
suggestion list M3 shows over the screen, which is why they are the
node\='s children rather than a sibling the author places by hand.

Trailing options: :value (the seeded query), :hint (the placeholder),
:variant (full_screen, the default, or docked — the difference is where
the expanded results go, not what they are), :on-search (dispatched on
submit with the query injected), :on-change (per keystroke),
:leading-icon and :trailing-icon, :enabled."
  (jetpacs--check-identifier id ":id")
  (let* ((split (jetpacs--children-and-opts args "search_bar"))
         (opts (cdr split))
         (value (plist-get opts :value))
         (hint (plist-get opts :hint))
         (variant (plist-get opts :variant))
         (on-search (plist-get opts :on-search))
         (on-change (plist-get opts :on-change))
         (leading-icon (plist-get opts :leading-icon))
         (trailing-icon (plist-get opts :trailing-icon))
         (enabled (plist-get opts :enabled)))
    (when value (jetpacs--require-string value ":value"))
    (when hint (jetpacs--require-string hint ":hint"))
    (when variant
      (setq variant (jetpacs--check-enum variant jetpacs--search-bar-variants
                                         ":variant")))
    (when on-search (jetpacs--check-descriptor on-search ":on-search"))
    (when on-change (jetpacs--check-descriptor on-change ":on-change"))
    (when leading-icon (jetpacs--check-identifier leading-icon ":leading-icon"))
    (when trailing-icon (jetpacs--check-identifier trailing-icon ":trailing-icon"))
    (when enabled (jetpacs--check-bool enabled ":enabled"))
    (jetpacs--node "search_bar" :id id
                   :children (jetpacs--as-children (car split))
                   :value value :hint hint :variant variant
                   :on_search on-search :on_change on-change
                   :leading_icon leading-icon :trailing_icon trailing-icon
                   :enabled enabled)))

(cl-defun jetpacs-dropdown (id options &key value label hint editable
                               on-change enabled)
  "An exposed dropdown identified by ID over OPTIONS (SPEC §17.4).
M3's ExposedDropdownMenuBox: the popup anchored to a FIELD, which
`jetpacs-menu' (popup off its own icon) and `jetpacs-text-input' (no
menu anchor) cannot compose.  OPTIONS are from `jetpacs-enum-option'.

Plain (no EDITABLE): the field is read-only, shows the picked option's
label, and VALUE is an option value — enum_list's schema exactly.
EDITABLE: the field is a real text field whose TEXT is the value,
published per keystroke, and the popup filters the options to those
whose label contains it — locally, no round trip.  LABEL and HINT are
the field's own slots; ON-CHANGE dispatches on an option pick."
  (jetpacs--check-identifier id ":id")
  (when value
    (unless (or (stringp value) (numberp value) (memq value '(t :json-false)))
      (error "jetpacs-dropdown: :value must be a string, number, or boolean, got %S" value))
    (unless (or (eq editable t)
                (cl-member value
                           (mapcar (lambda (o) (plist-get o :value)) options)
                           :test #'jetpacs--json-equal))
      (error "jetpacs-dropdown: value %S is not among options (SPEC 17.4)" value)))
  (when label (jetpacs--require-string label ":label"))
  (when hint (jetpacs--require-string hint ":hint"))
  (when editable (jetpacs--check-bool editable ":editable"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "dropdown"
                 :id id :options (vconcat options) :value value
                 :label label :hint hint :editable editable
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-segmented-button (id options &key value multi-select
                                       on-change enabled)
  "A connected segmented track identified by ID over OPTIONS (SPEC §17.4).
M3's Single/MultiChoiceSegmentedButtonRow: per-segment
itemShape(index, count), the fused seam, and the checked crossfade are
the renderer's own, which is why this is a node and not a styling of
`jetpacs-enum-list'.  The value schema mirrors enum_list exactly: VALUE
is one option value, or (with MULTI-SELECT) a list/vector of distinct
option values.  An option's :icon draws before its label."
  (jetpacs--check-identifier id ":id")
  (when multi-select (jetpacs--check-bool multi-select ":multi-select"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (when (and (eq multi-select t) value)
    (cond ((listp value) (setq value (vconcat value)))
          ((vectorp value))
          (t (error "jetpacs-segmented-button: multi_select :value must be a list or vector, got %S" value)))
    (let ((elts (append value nil)))
      (unless (= (length elts)
                 (length (cl-remove-duplicates elts :test #'jetpacs--json-equal)))
        (error "jetpacs-segmented-button: multi_select :value must have distinct values (SPEC 17.4)"))))
  (let ((option-vals (mapcar (lambda (o) (plist-get o :value)) options)))
    (unless (= (length option-vals)
               (length (cl-remove-duplicates option-vals :test #'jetpacs--json-equal)))
      (error "jetpacs-segmented-button: option values must be distinct under SPEC 4.3 (17.4)"))
    (when value
      (dolist (s (if (vectorp value) (append value nil) (list value)))
        (unless (cl-member s option-vals :test #'jetpacs--json-equal)
          (error "jetpacs-segmented-button: value %S is not among options (SPEC 17.4)" s)))))
  (jetpacs--node "segmented_button"
                 :id id :options (vconcat options) :value value
                 :multi_select multi-select
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-app-bar-item (label icon on-tap &key enabled)
  "One item of an app-bar overflow strip (SPEC §17.3).
LABEL is required — it is the item's menu row when it overflows and its
accessible name inline; ICON is what renders while it fits."
  (jetpacs--require-string label ":label")
  (jetpacs--check-identifier icon ":icon")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node nil :label label :icon icon :on_tap on-tap :enabled enabled))

(defun jetpacs--app-bar-strip (type items opts)
  "The shared body of `jetpacs-app-bar-row'/`-column': TYPE over ITEMS."
  (let ((overflow-icon (plist-get opts :overflow-icon))
        (max-items (plist-get opts :max-items)))
    (unless items
      (error "jetpacs-%s: items must be non-empty (SPEC 17.3)"
             (string-replace "_" "-" type)))
    (when overflow-icon (jetpacs--check-identifier overflow-icon ":overflow-icon"))
    (when max-items (jetpacs--check-integer max-items ":max-items" 1 nil))
    (jetpacs--node type
                   :items (vconcat items)
                   :overflow_icon overflow-icon
                   :max_items max-items)))

(cl-defun jetpacs-fab-menu-item (label icon on-tap)
  "One item of a `jetpacs-fab-menu' (SPEC §17.3).
Both LABEL and ICON are required — an M3 FAB menu item always carries
the pair; ON-TAP is its ActionDescriptor."
  (jetpacs--require-string label ":label")
  (jetpacs--check-identifier icon ":icon")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (jetpacs--node nil :label label :icon icon :on_tap on-tap))

(cl-defun jetpacs-fab-menu (items &key icon close-icon)
  "M3's FloatingActionButtonMenu: a checkable FAB unfolding ITEMS above it.
ITEMS are from `jetpacs-fab-menu-item'.  The toggle FAB morphs between
ICON (add, by default) and CLOSE-ICON (close) driven by its own checked
progress, and the expansion is Companion-local presentation — a menu
that snapped shut on every re-push would be unusable.  Meant for the
scaffold's fab slot."
  (unless items
    (error "jetpacs-fab-menu: items must be non-empty (SPEC 17.3)"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when close-icon (jetpacs--check-identifier close-icon ":close-icon"))
  (jetpacs--node "fab_menu"
                 :items (vconcat items)
                 :icon icon :close_icon close-icon))

(cl-defun jetpacs-button-group-item (label on-tap &key icon enabled)
  "One item of a `jetpacs-button-group' (SPEC §17.3).
LABEL is required — it is the button's text inline and its menu row when
it overflows; ICON is optional, unlike an app-bar item's."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node nil :label label :on_tap on-tap :icon icon
                 :enabled enabled))

(cl-defun jetpacs-button-group (items &key overflow-icon)
  "M3's ButtonGroup over ITEMS from `jetpacs-button-group-item' (SPEC §17.3).
The press animation couples neighbours, and what does not fit moves
into an overflow menu at MEASURE time — the same never-ask-Emacs width
rule as `jetpacs-app-bar-row'.  OVERFLOW-ICON renames the indicator."
  (unless items
    (error "jetpacs-button-group: items must be non-empty (SPEC 17.3)"))
  (when overflow-icon (jetpacs--check-identifier overflow-icon ":overflow-icon"))
  (jetpacs--node "button_group"
                 :items (vconcat items)
                 :overflow_icon overflow-icon))

(cl-defun jetpacs-lazy-grid (&rest args)
  "A LazyVerticalGrid over its CHILDREN, order preserved (SPEC §17.3).
Trailing options: :min-item-width (GridCells.Adaptive — outranks
:columns), :columns (GridCells.Fixed, default 2), :reverse (t or
:json-false — reverseLayout, the grid growing from the bottom),
:spacing and :content-padding.  Like `jetpacs-lazy-column' it needs a
bounded height: the scaffold body, or an explicit universal :height
inside a scrolling column."
  (let* ((split (jetpacs--children-and-opts args "lazy_grid"))
         (opts (cdr split))
         (columns (plist-get opts :columns))
         (min-item-width (plist-get opts :min-item-width))
         (reverse (plist-get opts :reverse))
         (spacing (plist-get opts :spacing))
         (content-padding (plist-get opts :content-padding)))
    (when columns (jetpacs--check-integer columns ":columns" 1 nil))
    (when min-item-width
      (jetpacs--check-number min-item-width ":min-item-width" 1 nil))
    (when (and columns min-item-width)
      (error "jetpacs-lazy-grid: :columns and :min-item-width are mutually exclusive (SPEC 17.3)"))
    (when reverse (jetpacs--check-bool reverse ":reverse"))
    (when spacing (jetpacs--check-number spacing ":spacing" 0 nil))
    (when content-padding
      (jetpacs--check-number content-padding ":content-padding" 0 nil))
    (jetpacs--node "lazy_grid"
                   :children (jetpacs--as-children (car split))
                   :columns columns
                   :min_item_width min-item-width
                   :reverse reverse
                   :spacing spacing
                   :content_padding content-padding)))

(defconst jetpacs--carousel-strategies
  '("multi_browse" "uncontained" "centered_hero"))

(cl-defun jetpacs-carousel (&rest args)
  "An M3 keyline carousel over its item CHILDREN (SPEC §17.3).
The Companion runs all the keyline math and the per-frame item mask;
Emacs supplies content only and never learns the width — the same
device-owns-presentation split as tabs and collapsible.

Trailing options: :strategy (multi_browse, the default; uncontained;
centered_hero), :item-width (multi_browse's preferredItemWidth or
uncontained's itemWidth — centered_hero sizes itself), :item-spacing,
:content-padding (inside the scroll viewport), and :item-corner (the
maskClip radius, applied to the item's LIVE mask rect so the clip
breathes with the keylines)."
  (let* ((split (jetpacs--children-and-opts args "carousel"))
         (opts (cdr split))
         (strategy (plist-get opts :strategy))
         (item-width (plist-get opts :item-width))
         (item-spacing (plist-get opts :item-spacing))
         (content-padding (plist-get opts :content-padding))
         (item-corner (plist-get opts :item-corner)))
    (when strategy
      (setq strategy (jetpacs--check-enum strategy
                                          jetpacs--carousel-strategies
                                          ":strategy")))
    (when item-width (jetpacs--check-number item-width ":item-width" 0 nil))
    (when item-spacing (jetpacs--check-number item-spacing ":item-spacing" 0 nil))
    (when content-padding
      (jetpacs--check-number content-padding ":content-padding" 0 nil))
    (when item-corner (jetpacs--check-number item-corner ":item-corner" 0 nil))
    (jetpacs--node "carousel"
                   :children (jetpacs--as-children (car split))
                   :strategy strategy
                   :item_width item-width
                   :item_spacing item-spacing
                   :content_padding content-padding
                   :item_corner item-corner)))

(cl-defun jetpacs-app-bar-row (items &key overflow-icon max-items)
  "M3's AppBarRow: ITEMS inline while they fit, overflowed at MEASURE time.
ITEMS are from `jetpacs-app-bar-item'.  Which items fold into the
overflow menu is a width decision the device makes per layout pass —
Emacs never learns it, which is why a static row-plus-menu split could
never be this component.  OVERFLOW-ICON renames the more_vert
indicator; MAX-ITEMS caps the inline count below what would fit."
  (jetpacs--app-bar-strip "app_bar_row" items
                          (list :overflow-icon overflow-icon
                                :max-items max-items)))

(cl-defun jetpacs-app-bar-column (items &key overflow-icon max-items)
  "M3's AppBarColumn — `jetpacs-app-bar-row' stood on end (SPEC §17.3)."
  (jetpacs--app-bar-strip "app_bar_column" items
                          (list :overflow-icon overflow-icon
                                :max-items max-items)))

(defconst jetpacs--rail-variants '("standard" "wide"))
(defconst jetpacs--rail-arrangements '("top" "center" "bottom"))

(cl-defun jetpacs-rail-item (label icon on-tap &key selected badge enabled)
  "One destination of a `jetpacs-navigation-rail' (SPEC §17.4).
LABEL and ICON are required — a rail destination without both is not
navigable — and SELECTED marks the current one.  BADGE is a string or
number over the icon, empty meaning the bare attention dot."
  (jetpacs--require-string label ":label")
  (jetpacs--check-identifier icon ":icon")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when selected (jetpacs--check-bool selected ":selected"))
  (when badge (jetpacs--check-badge badge))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node nil :label label :icon icon :on_tap on-tap
                 :selected selected :badge badge :enabled enabled))

(cl-defun jetpacs-navigation-rail (items &key variant expanded arrangement
                                         header)
  "A vertical navigation rail of ITEMS (SPEC §17.4).

ITEMS come from `jetpacs-rail-item'.  VARIANT is standard (default) or
wide — M3's WideNavigationRail, the only one that can EXPAND to show its
labels beside the icons, which is what EXPANDED asks for.  ARRANGEMENT
(top by default, center, bottom) is where the destinations sit in the
rail's height, and HEADER is a node above them, canonically the menu
button that toggles a wide rail."
  (unless items (error "jetpacs-navigation-rail: ITEMS must be non-empty (SPEC 17.4)"))
  (when variant
    (setq variant (jetpacs--check-enum variant jetpacs--rail-variants ":variant")))
  (when expanded
    (jetpacs--check-bool expanded ":expanded")
    (unless (equal variant "wide")
      (error "jetpacs-navigation-rail: :expanded needs :variant \"wide\" (SPEC 17.4)")))
  (when arrangement
    (setq arrangement (jetpacs--check-enum arrangement jetpacs--rail-arrangements
                                           ":arrangement")))
  (when (and header (not (jetpacs--root-node-p header)))
    (error "jetpacs-navigation-rail: :header must be a node, got %S" header))
  (jetpacs--node "navigation_rail" :items (vconcat items)
                 :variant variant :expanded expanded
                 :arrangement arrangement :header header))

(defconst jetpacs--split-button-variants
  '("filled" "tonal" "elevated" "outlined"))
(defconst jetpacs--split-button-sizes
  '("xsmall" "small" "medium" "large" "xlarge"))

(cl-defun jetpacs-split-button (label on-tap
                                &key icon variant size
                                     trailing-icon trailing-label
                                     trailing-description
                                     checked on-change on-trailing-tap
                                     items enabled)
  "An M3 split button: LABEL/ON-TAP leading, a divided trailing half (§17.4).

The two halves are ONE component with a shared outline and a 2dp gap, not
a row of buttons — the outer corners are full and the inner ones are
small, and they morph together on press, which is the whole subject of
the upstream samples.

ICON is the leading identifier; VARIANT and SIZE apply to BOTH halves.
The trailing half is one of three things, in order of precedence:
ITEMS (a list of `jetpacs-menu-item') makes it open a dropdown;
CHECKED makes it a toggle whose arrow rotates 180 degrees, with ON-CHANGE
receiving the flipped boolean; otherwise ON-TRAILING-TAP fires plainly.
TRAILING-ICON overrides the default arrow, TRAILING-LABEL puts text there
instead, and TRAILING-DESCRIPTION is the accessible name an icon-only
trailing half needs.

A node carrying CHECKED is stateful and REQUIRES a unique `:id' (§16.1).

LABEL may be nil WHEN ICON is present — the icon-only LeadingButton form,
whose accessible name falls back to the icon identifier — but a leading
half with neither is refused."
  (if label (jetpacs--require-string label ":label")
    (unless icon
      (error "jetpacs-split-button: the leading half needs a :label, an icon, or both (SPEC 17.4)")))
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when variant
    (setq variant (jetpacs--check-enum variant jetpacs--split-button-variants ":variant")))
  (when size
    (setq size (jetpacs--check-enum size jetpacs--split-button-sizes ":size")))
  (when trailing-icon (jetpacs--check-identifier trailing-icon ":trailing-icon"))
  (when trailing-label (jetpacs--require-string trailing-label ":trailing-label"))
  (when trailing-description
    (jetpacs--require-string trailing-description ":trailing-description"))
  (when checked (jetpacs--check-bool checked ":checked"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when on-trailing-tap (jetpacs--check-descriptor on-trailing-tap ":on-trailing-tap"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "split_button" :label label :on_tap on-tap
                 :icon icon :variant variant :size size
                 :trailing_icon trailing-icon :trailing_label trailing-label
                 :trailing_description trailing-description
                 :checked checked :on_change on-change
                 :on_trailing_tap on-trailing-tap
                 :items (and items (vconcat items))
                 :enabled enabled))

(cl-defun jetpacs-chip (label &key on-tap selected icon trailing-icon
                              variant avatar content-spacing enabled)
  "A chip labeled LABEL (SPEC §17.4).
ON-TAP an ActionDescriptor; SELECTED/ENABLED booleans; ICON and
TRAILING-ICON identifiers occupying the leading and trailing slots;
VARIANT flat(default)/elevated/input.

AVATAR is InputChip's 24dp circular slot — distinct from the 18dp
leading ICON — and needs `:variant \"input\"'.  CONTENT-SPACING is the
gap between a FilterChip's own slots, the interior arrangement no
modifier-level attribute could reach."
  (jetpacs--require-string label ":label")
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (when selected (jetpacs--check-bool selected ":selected"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when trailing-icon (jetpacs--check-identifier trailing-icon ":trailing_icon"))
  (when variant (setq variant (jetpacs--check-enum variant jetpacs--chip-variants ":variant")))
  (when avatar
    (jetpacs--check-identifier avatar ":avatar")
    (unless (equal variant "input")
      (error "jetpacs-chip: :avatar needs :variant \"input\" (SPEC 17.4)")))
  (when content-spacing
    (jetpacs--check-number content-spacing ":content-spacing" 0 nil))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "chip" :label label :on_tap on-tap
                 :selected selected :icon icon :trailing_icon trailing-icon
                 :variant variant :avatar avatar
                 :content_spacing content-spacing :enabled enabled))

(cl-defun jetpacs-assist-chip (label &key on-tap icon variant enabled)
  "An assist chip labeled LABEL (SPEC §17.4).
VARIANT flat(default)/elevated/suggestion/elevated_suggestion."
  (jetpacs--require-string label ":label")
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when variant (setq variant (jetpacs--check-enum variant jetpacs--assist-chip-variants ":variant")))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "assist_chip" :label label :on_tap on-tap :icon icon
                 :variant variant :enabled enabled))

(defconst jetpacs--tooltip-positions
  '("above" "below" "left" "right" "start" "end")
  "SPEC §17.2 `tooltip.position'.  `left'/`right' are ABSOLUTE sides, which
is why they are distinct from the direction-relative `start'/`end' the
alignment enums use.")

(cl-defun jetpacs-tooltip (text &rest args)
  "A tooltip carrying TEXT over its ANCHOR children (SPEC §17.2).
CHILDREN are the anchor the tooltip describes, wrapped exactly as `badge'
wraps its own; the anchor keeps its own `on_tap'.

Trailing options: :position (one of `jetpacs--tooltip-positions', above
by default), :caret (a boolean asking for the pointer aimed back at the
anchor), :caret-width and :caret-height (both-or-neither dp resizing
that pointer, valid only with :caret), :rich (M3's RichTooltip rather
than the plain one), :title and :action-label/:on-action (rich only),
and :shown, which asks the Companion to display the tooltip without the
long press."
  (jetpacs--require-string text ":text")
  (let* ((split (jetpacs--children-and-opts args "tooltip"))
         (opts (cdr split))
         (position (plist-get opts :position))
         (caret (plist-get opts :caret))
         (caret-width (plist-get opts :caret-width))
         (caret-height (plist-get opts :caret-height))
         (rich (plist-get opts :rich))
         (title (plist-get opts :title))
         (action-label (plist-get opts :action-label))
         (on-action (plist-get opts :on-action))
         (shown (plist-get opts :shown)))
    (when position
      (setq position (jetpacs--check-enum position jetpacs--tooltip-positions
                                         ":position")))
    (when caret (jetpacs--check-bool caret ":caret"))
    (when (or caret-width caret-height)
      (unless (and caret-width caret-height)
        (error "jetpacs-tooltip: :caret-width and :caret-height come together (SPEC 17.2)"))
      (unless (eq caret t)
        (error "jetpacs-tooltip: caret sizes need :caret t (SPEC 17.2)"))
      (jetpacs--check-number caret-width ":caret-width" 0 nil)
      (jetpacs--check-number caret-height ":caret-height" 0 nil))
    (when rich (jetpacs--check-bool rich ":rich"))
    (when title (jetpacs--require-string title ":title"))
    (when action-label (jetpacs--require-string action-label ":action-label"))
    (when on-action (jetpacs--check-descriptor on-action ":on-action"))
    (when shown (jetpacs--check-bool shown ":shown"))
    (when (and action-label (not on-action))
      (error "jetpacs-tooltip: :action-label needs :on-action (SPEC 17.2)"))
    (jetpacs--node "tooltip"
                   :children (jetpacs--as-children (car split))
                   :text text :position position :caret caret
                   :caret_width caret-width :caret_height caret-height
                   :rich rich
                   :title title :action_label action-label
                   :on_action on-action :shown shown)))

(cl-defun jetpacs-menu-item (label on-tap &key icon enabled)
  "A MenuItem {label, on_tap, icon?, enabled?} for `jetpacs-menu' (SPEC §17.4)."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node nil :label label :on_tap on-tap :icon icon :enabled enabled))

(defconst jetpacs--menu-initial-scrolls '("start" "end"))

(cl-defun jetpacs-menu (items &key icon initial-scroll enabled)
  "A menu of ITEMS (from `jetpacs-menu-item') (SPEC §17.4).
INITIAL-SCROLL is start (default) or end: where the popup opens when the
item list is longer than the screen."
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when initial-scroll
    (setq initial-scroll (jetpacs--check-enum initial-scroll
                                              jetpacs--menu-initial-scrolls
                                              ":initial-scroll")))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "menu" :items (vconcat items) :icon icon
                 :initial_scroll initial-scroll :enabled enabled))

(defconst jetpacs--text-input-variants '("outlined" "filled"))

(defconst jetpacs--text-input-filters '("digits" "alnum"))

(cl-defun jetpacs-text-input (id &key value hint label on-change on-submit
                                 single-line min-lines max-lines monospace syntax
                                 password keyboard autofocus clear-on-submit
                                 variant is-error supporting-text prefix suffix
                                 leading-icon trailing-icon max-length
                                 selection hide-keyboard-on-submit
                                 content-padding mask filter enabled)
  "A text input identified by ID (SPEC §17.4).
Booleans (SINGLE-LINE, MONOSPACE, PASSWORD, AUTOFOCUS, CLEAR-ON-SUBMIT,
ENABLED) take t or :json-false.  Enforces the §17.4 line-count, single-line
no-newline, and password constraints at build time.

SELECTION is (START END), non-negative character offsets into VALUE with
START <= END <= its length — it seeds the initial cursor/selection only.
HIDE-KEYBOARD-ON-SUBMIT dismisses the IME after ON-SUBMIT (Compose's
default hide-on-Done is suppressed the moment a submit handler exists).
CONTENT-PADDING is the field's INTERIOR padding in dp — the dense form —
distinct from the universal padding, which is margin.  MASK is a display
template over the stored value (every `#' consumes one stored character,
everything else is literal filler that never enters the value); FILTER
reverts characters outside digits/alnum at the keystroke, locally."
  (jetpacs--check-identifier id ":id")
  (when value (jetpacs--require-string value ":value"))
  (when hint (jetpacs--require-string hint ":hint"))
  (when label (jetpacs--require-string label ":label"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when on-submit (jetpacs--check-descriptor on-submit ":on-submit"))
  (when single-line (jetpacs--check-bool single-line ":single-line"))
  (when min-lines (jetpacs--check-integer min-lines ":min_lines" 1 nil))
  (when max-lines (jetpacs--check-integer max-lines ":max_lines" 1 nil))
  (when (and min-lines max-lines (> min-lines max-lines))
    (error "jetpacs-text-input: :min-lines must not exceed :max-lines (SPEC 17.4)"))
  (when monospace (jetpacs--check-bool monospace ":monospace"))
  (when syntax (jetpacs--check-identifier syntax ":syntax"))
  (when password (jetpacs--check-bool password ":password"))
  (when keyboard (setq keyboard (jetpacs--check-enum keyboard jetpacs--keyboards ":keyboard")))
  (when autofocus (jetpacs--check-bool autofocus ":autofocus"))
  (when clear-on-submit (jetpacs--check-bool clear-on-submit ":clear-on-submit"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (when variant
    (setq variant (jetpacs--check-enum variant jetpacs--text-input-variants ":variant")))
  (when is-error (jetpacs--check-bool is-error ":is_error"))
  (when supporting-text (jetpacs--require-string supporting-text ":supporting_text"))
  (when prefix (jetpacs--require-string prefix ":prefix"))
  (when suffix (jetpacs--require-string suffix ":suffix"))
  (when leading-icon (jetpacs--check-identifier leading-icon ":leading_icon"))
  (when trailing-icon (jetpacs--check-identifier trailing-icon ":trailing_icon"))
  (when max-length (jetpacs--check-integer max-length ":max_length" 1 nil))
  (when selection
    (unless (and (listp selection) (= 2 (length selection)))
      (error "jetpacs-text-input: :selection must be (START END) (SPEC 17.4)"))
    (let ((start (nth 0 selection)) (end (nth 1 selection))
          (len (length (or value ""))))
      (jetpacs--check-integer start ":selection start" 0 nil)
      (jetpacs--check-integer end ":selection end" 0 nil)
      (unless (<= start end len)
        (error "jetpacs-text-input: :selection needs START <= END <= value length (SPEC 17.4)")))
    (setq selection (vconcat selection)))
  (when hide-keyboard-on-submit
    (jetpacs--check-bool hide-keyboard-on-submit ":hide-keyboard-on-submit")
    (unless on-submit
      (error "jetpacs-text-input: :hide-keyboard-on-submit needs :on-submit (SPEC 17.4)")))
  (when content-padding
    (jetpacs--check-number content-padding ":content-padding" 0 nil))
  (when mask
    (jetpacs--require-string mask ":mask")
    (unless (string-search "#" mask)
      (error "jetpacs-text-input: :mask needs at least one `#' slot (SPEC 17.4)"))
    (when (or (eq password t) syntax)
      (error "jetpacs-text-input: :mask is invalid with :password or :syntax (SPEC 17.4)")))
  (when filter
    (setq filter (jetpacs--check-enum filter jetpacs--text-input-filters ":filter")))
  (when (eq single-line t)
    (when (and min-lines (/= min-lines 1))
      (error "jetpacs-text-input: single_line requires :min-lines 1 (SPEC 17.4)"))
    (when (and max-lines (/= max-lines 1))
      (error "jetpacs-text-input: single_line requires :max-lines 1 (SPEC 17.4)"))
    (when (and value (string-search "\n" value))
      (error "jetpacs-text-input: single_line prohibits U+000A in :value (SPEC 17.4)")))
  (when (eq password t)
    (when (and value (not (string-empty-p value)))
      (error "jetpacs-text-input: password :value must be absent or empty (SPEC 17.4)"))
    (when on-change
      (error "jetpacs-text-input: password :on-change must be absent (SPEC 17.4)"))
    (when (eq clear-on-submit t)
      (error "jetpacs-text-input: password :clear-on-submit must be absent or false (SPEC 17.4)")))
  (when (and (eq clear-on-submit t) on-submit (plist-member on-submit :builtin))
    (error "jetpacs-text-input: :clear-on-submit is invalid when :on-submit is a builtin (SPEC 17.4)"))
  (jetpacs--node "text_input"
                 :id id :value value :hint hint :label label
                 :on_change on-change :on_submit on-submit
                 :single_line single-line :min_lines min-lines :max_lines max-lines
                 :monospace monospace :syntax syntax :password password
                 :keyboard keyboard :autofocus autofocus
                 :clear_on_submit clear-on-submit
                 :variant variant :is_error is-error
                 :supporting_text supporting-text :prefix prefix :suffix suffix
                 :leading_icon leading-icon :trailing_icon trailing-icon
                 :max_length max-length
                 :selection selection
                 :hide_keyboard_on_submit hide-keyboard-on-submit
                 :content_padding content-padding
                 :mask mask :filter filter
                 :enabled enabled))

(defconst jetpacs--checkbox-states '("off" "on" "indeterminate"))
(defconst jetpacs--stroke-caps '("butt" "round" "square"))
(defconst jetpacs--stroke-joins '("miter" "round" "bevel"))

(cl-defun jetpacs-checkbox (id &key checked state stroke label on-change enabled)
  "A checkbox identified by ID (SPEC §17.4).
CHECKED/ENABLED booleans (t or :json-false); ON-CHANGE an ActionDescriptor.

STATE makes it tri-state (off, on, indeterminate) and is mutually
exclusive with CHECKED — it changes what `state.changed' carries for ID
from a boolean to the enum string, which is a different value schema
under §13.6.  STROKE is a plist (:width DP :cap CAP :join JOIN), every
key optional, reaching M3's checkmarkStroke/outlineStroke pair."
  (jetpacs--check-identifier id ":id")
  (when checked (jetpacs--check-bool checked ":checked"))
  (when state
    (when checked
      (error "jetpacs-checkbox: :state and :checked are mutually exclusive (SPEC 17.4)"))
    (setq state (jetpacs--check-enum state jetpacs--checkbox-states ":state")))
  (when stroke
    (unless (and (listp stroke) (cl-evenp (length stroke)))
      (error "jetpacs-checkbox: :stroke must be a plist (SPEC 17.4)"))
    (cl-loop for (key value) on stroke by #'cddr
             do (pcase key
                  (:width (jetpacs--check-number value ":stroke :width" 0 nil))
                  (:cap (jetpacs--check-enum value jetpacs--stroke-caps
                                             ":stroke :cap"))
                  (:join (jetpacs--check-enum value jetpacs--stroke-joins
                                              ":stroke :join"))
                  (_ (error "jetpacs-checkbox: unknown :stroke key %S" key)))))
  (when label (jetpacs--require-string label ":label"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "checkbox" :id id :checked checked :state state
                 :stroke stroke :label label
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-switch (id &key checked label on-change thumb-icon enabled)
  "A switch identified by ID (SPEC §17.4).
CHECKED/ENABLED booleans (t or :json-false); ON-CHANGE an ActionDescriptor."
  (jetpacs--check-identifier id ":id")
  (when checked (jetpacs--check-bool checked ":checked"))
  (when label (jetpacs--require-string label ":label"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (when thumb-icon (jetpacs--check-identifier thumb-icon ":thumb_icon"))
  (jetpacs--node "switch" :id id :checked checked :label label
                 :thumb_icon thumb-icon
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-enum-option (label value &key icon)
  "An EnumOption {label, value} for the option-carrying inputs (SPEC §17.4).
VALUE is a string, number, or boolean (t or :json-false).  ICON is an
identifier a `jetpacs-segmented-button' segment draws before its label
under the checked crossfade; `enum_list' and `dropdown' ignore it."
  (jetpacs--require-string label ":label")
  (unless (or (stringp value) (numberp value) (memq value '(t :json-false)))
    (error "jetpacs-enum-option: value must be a string, number, or boolean, got %S" value))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (jetpacs--node nil :label label :value value :icon icon))

(defconst jetpacs--enum-list-variants '("chips" "radio"))

(cl-defun jetpacs-enum-list (id options &key value multi-select allow-add
                                on-change enabled variant children)
  "A single/multi-select list identified by ID over OPTIONS (SPEC §17.4).
OPTIONS is a list from `jetpacs-enum-option'.  VALUE is one option value, or
\(with MULTI-SELECT) a list/vector of distinct option values.  Unless
ALLOW-ADD, every selected value MUST appear in OPTIONS.  No implicit selection.

VARIANT chips (default) renders the FlowRow of FilterChips; radio
renders M3 RadioButton targets in a selectableGroup (Checkbox rows
under MULTI-SELECT), the same state path throughout.  CHILDREN is a
node list PARALLEL to OPTIONS: each option becomes one whole selectable
row with its child as the body — how a list row becomes one exclusive
choice.  ALLOW-ADD is a chips-only affordance and refuses both."
  (jetpacs--check-identifier id ":id")
  (when multi-select (jetpacs--check-bool multi-select ":multi-select"))
  (when allow-add (jetpacs--check-bool allow-add ":allow-add"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (when variant
    (setq variant (jetpacs--check-enum variant jetpacs--enum-list-variants
                                       ":variant")))
  (when children
    (unless (= (length children) (length options))
      (error "jetpacs-enum-list: :children must parallel :options, got %d for %d (SPEC 17.4)"
             (length children) (length options)))
    (dolist (child children)
      (unless (jetpacs--root-node-p child)
        (error "jetpacs-enum-list: every :children entry must be a node, got %S" child))))
  (when (and (eq allow-add t) (or (equal variant "radio") children))
    (error "jetpacs-enum-list: :allow-add is a chips-only affordance (SPEC 17.4)"))
  (when (and (eq multi-select t) value)
    (cond ((listp value) (setq value (vconcat value)))
          ((vectorp value))
          (t (error "jetpacs-enum-list: multi_select :value must be a list or vector, got %S" value)))
    (let ((elts (append value nil)))
      (unless (= (length elts) (length (cl-remove-duplicates elts :test #'jetpacs--json-equal)))
        (error "jetpacs-enum-list: multi_select :value must have distinct values (SPEC 17.4)"))))
  (let ((option-vals (mapcar (lambda (o) (plist-get o :value)) options)))
    (unless (= (length option-vals) (length (cl-remove-duplicates option-vals :test #'jetpacs--json-equal)))
      (error "jetpacs-enum-list: option values must be distinct under SPEC 4.3 (17.4)"))
    (when (and value (not (eq allow-add t)))
      (dolist (s (if (vectorp value) (append value nil) (list value)))
        (unless (cl-member s option-vals :test #'jetpacs--json-equal)
          (error "jetpacs-enum-list: value %S is not among options (SPEC 17.4)" s)))))
  (jetpacs--node "enum_list"
                 :id id :options (vconcat options) :value value
                 :multi_select multi-select :allow_add allow-add
                 :variant variant
                 :children (and children (vconcat children))
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-date-button (label on-pick &key value mode enabled)
  "A date-picker button labeled LABEL dispatching ON-PICK (SPEC §17.4).
VALUE is a YYYY-MM-DD string."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-pick ":on-pick")
  (when value (jetpacs--check-date value))
  (when mode (setq mode (jetpacs--check-enum mode '("calendar" "input") ":mode")))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "date_button" :label label :on_pick on-pick :value value
                 :mode mode :enabled enabled))

(cl-defun jetpacs-time-button (label on-pick &key value display-mode enabled)
  "A time-picker button labeled LABEL dispatching ON-PICK (SPEC §17.4).
VALUE is an HH:MM string in local civil time."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-pick ":on-pick")
  (when value (jetpacs--check-time value))
  (when display-mode
    (setq display-mode (jetpacs--check-enum display-mode
                                            '("picker" "input" "switchable")
                                            ":display-mode")))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "time_button" :label label :on_pick on-pick :value value
                 :display_mode display-mode :enabled enabled))

(defconst jetpacs--slider-tracks '("default" "centered"))
(defconst jetpacs--slider-orientations '("horizontal" "vertical"))

(cl-defun jetpacs-slider (id on-change &key value value-end min max values
                             track orientation color color-end thumb-icon
                             value-label track-icon-start track-icon-end
                             enabled)
  "A slider identified by ID dispatching ON-CHANGE (SPEC §17.4).
Continuous: :min (default 0) < :max (default 1), :value in [min,max].
Discrete: :values is 2+ strictly-increasing distinct numbers, MUST omit
:min/:max, and :value must equal a listed number.

VALUE-END makes it a RangeSlider: two thumbs, and `state.changed'
carries a two-number array — a different value schema under §13.6.
With :values, each thumb snaps to the nearest authored number on
commit.  ORIENTATION vertical renders M3's VerticalSlider; give it a
universal :height, since a vertical rail has no width to fill.
COLOR-END tints the end thumb alone (needs VALUE-END).  VALUE-LABEL
shows the in-flight position over the thumb — presentation only, the
dispatch still happens once on commit.  TRACK-ICON-START/END name icons
drawn at both edges of each track segment, active/inactive tinted."
  (jetpacs--check-identifier id ":id")
  (jetpacs--check-descriptor on-change ":on-change")
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (when track (setq track (jetpacs--check-enum track jetpacs--slider-tracks ":track")))
  (when orientation
    (setq orientation (jetpacs--check-enum orientation
                                           jetpacs--slider-orientations
                                           ":orientation")))
  (when color (jetpacs--check-color color))
  (when color-end
    (unless value-end
      (error "jetpacs-slider: :color-end needs :value-end (SPEC 17.4)"))
    (jetpacs--check-color color-end))
  (when value-label (jetpacs--check-bool value-label ":value-label"))
  (when thumb-icon (jetpacs--check-identifier thumb-icon ":thumb_icon"))
  (when track-icon-start
    (jetpacs--check-identifier track-icon-start ":track_icon_start"))
  (when track-icon-end
    (jetpacs--check-identifier track-icon-end ":track_icon_end"))
  (cond
   (values
    (when (or min max)
      (error "jetpacs-slider: a discrete slider must omit :min/:max (SPEC 17.4)"))
    (unless (and (>= (length values) 2)
                 (cl-every #'jetpacs--finite-number-p values)
                 (apply #'< values))
      (error "jetpacs-slider: :values must be 2+ strictly-increasing finite numbers (SPEC 17.4)"))
    (when (and value (not (cl-member value values :test #'jetpacs--json-equal)))
      (error "jetpacs-slider: discrete :value must equal a listed number under SPEC 4.3 (17.4)"))
    (when (and value-end
               (not (cl-member value-end values :test #'jetpacs--json-equal)))
      (error "jetpacs-slider: discrete :value-end must equal a listed number under SPEC 4.3 (17.4)")))
   (t
    (when min (jetpacs--check-number min ":min" nil nil))
    (when max (jetpacs--check-number max ":max" nil nil))
    (when value (jetpacs--check-number value ":value" nil nil))
    (when value-end (jetpacs--check-number value-end ":value-end" nil nil))
    (let ((lo (or min 0)) (hi (or max 1)))
      (unless (< lo hi)
        (error "jetpacs-slider: :min must be less than :max (SPEC 17.4)"))
      (when (and value (not (<= lo value hi)))
        (error "jetpacs-slider: :value must be within [min,max] (SPEC 17.4)"))
      (when (and value-end (not (<= lo value-end hi)))
        (error "jetpacs-slider: :value-end must be within [min,max] (SPEC 17.4)")))))
  (when (and value value-end (numberp value) (numberp value-end)
             (> value value-end))
    (error "jetpacs-slider: :value must not exceed :value-end (SPEC 17.4)"))
  (jetpacs--node "slider"
                 :id id :on_change on-change :value value :value_end value-end
                 :min min :max max :values (and values (vconcat values))
                 :track track :orientation orientation
                 :color color :color_end color-end
                 :thumb_icon thumb-icon :value_label value-label
                 :track_icon_start track-icon-start
                 :track_icon_end track-icon-end
                 :enabled enabled))

;;;; Editor + toolbar (§17.4 editor row, §17.7)

(defconst jetpacs--line-ops '("promote" "demote" "move-up" "move-down"))
(defconst jetpacs--placements '("cursor" "line-start" "block"))

(defun jetpacs--check-snippet (s)
  "Signal unless S is a valid §17.7 snippet string.
A snippet MUST contain at most one `${input:...}' token.  Only the 3-char
`$${' escapes the following `${', and a token's prompt body runs to its
closing `}' and is not rescanned."
  (jetpacs--require-string s ":snippet")
  (let ((i 0) (n (length s)) (count 0))
    (while (< i n)
      (cond
       ((and (<= (+ i 3) n) (= (aref s i) ?$) (= (aref s (1+ i)) ?$)
             (= (aref s (+ i 2)) ?\{))
        (setq i (+ i 3)))                                 ; $${ escape -> literal ${
       ((eq t (compare-strings "${input:" nil nil s i (min n (+ i 8))))
        (setq count (1+ count))
        (let ((close (cl-search "}" s :start2 (+ i 8))))
          (setq i (if close (1+ close) n))))              ; skip past the closing }
       (t (setq i (1+ i)))))
    (when (> count 1)
      (error "jetpacs: snippet must contain at most one ${input:...} token (SPEC 17.7)")))
  s)

(defun jetpacs--check-long-press (lp)
  "Signal unless LP is a §17.7 long_press: a plist with exactly one non-menu op."
  (unless (and (consp lp) (keywordp (car lp)))
    (error "jetpacs: :long-press must be an operation plist (SPEC 17.7), got %S" lp))
  (when (plist-member lp :menu)
    (error "jetpacs: :long-press must not contain a :menu op (SPEC 17.7)"))
  (let ((present (delq nil (list (and (plist-member lp :snippet) :snippet)
                                 (and (plist-member lp :on_tap) :on_tap)
                                 (and (plist-member lp :command) :command)
                                 (and (plist-member lp :line) :line)))))
    (unless (= (length present) 1)
      (error "jetpacs: :long-press must contain exactly one non-menu op (SPEC 17.7)"))
    (pcase (car present)
      (:snippet (jetpacs--check-snippet (plist-get lp :snippet)))
      (:on_tap (jetpacs--check-descriptor (plist-get lp :on_tap) ":on_tap"))
      (:command (jetpacs--check-identifier (plist-get lp :command) ":command"))
      (:line (jetpacs--check-enum (plist-get lp :line) jetpacs--line-ops ":line"))))
  lp)

(cl-defun jetpacs-toolbar-item (&key label icon snippet on-tap menu command line
                                     placement long-press)
  "A ToolbarItem for `jetpacs-editor' :toolbar (SPEC §17.7).
MUST have LABEL or ICON plus exactly one primary op: :snippet (a string),
:on-tap (an ActionDescriptor), :menu (a list of non-menu items), :command
\(an identifier), or :line (promote/demote/move-up/move-down).  Optional
:placement (cursor/line-start/block) and :long-press (one non-menu op plist)."
  (unless (or label icon)
    (error "jetpacs-toolbar-item: needs :label or :icon (SPEC 17.7)"))
  (when label (jetpacs--require-string label ":label"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (let ((ops (delq nil (list (and snippet :snippet) (and on-tap :on-tap)
                             (and menu :menu) (and command :command)
                             (and line :line)))))
    (unless (= (length ops) 1)
      (error "jetpacs-toolbar-item: needs exactly one primary op, got %S (SPEC 17.7)" ops)))
  (when snippet (jetpacs--check-snippet snippet))
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (when command (jetpacs--check-identifier command ":command"))
  (when line (setq line (jetpacs--check-enum line jetpacs--line-ops ":line")))
  (when placement (setq placement (jetpacs--check-enum placement jetpacs--placements ":placement")))
  (when menu
    (dolist (mi menu)
      (when (plist-member mi :menu)
        (error "jetpacs-toolbar-item: a :menu item must not itself contain :menu (SPEC 17.7)"))))
  (when long-press (jetpacs--check-long-press long-press))
  (jetpacs--node nil
                 :label label :icon icon
                 :snippet snippet :on_tap on-tap
                 :menu (and menu (vconcat menu))
                 :command command :line line
                 :placement placement :long_press long-press))

(defun jetpacs--toolbar-has-command-p (items)
  "Non-nil when any ToolbarItem in ITEMS carries a `command' op — at top
level, inside a `menu', or in a `long_press' (SPEC §17.7)."
  (cl-some (lambda (item)
             (or (plist-member item :command)
                 (let ((m (plist-get item :menu)))
                   (and m (jetpacs--toolbar-has-command-p (append m nil))))
                 (let ((lp (plist-get item :long_press)))
                   (and lp (plist-member lp :command)))))
           items))

(cl-defun jetpacs-editor (id &key document value on-save on-enter read-only syntax
                             line-numbers complete chromeless publish-state autofocus
                             toolbar enabled)
  "An editor identified by ID (SPEC §17.4 + §17.7).
Without DOCUMENT it is a local input node; with DOCUMENT it is a synchronized
editor (emit only when `editor.sync' is granted).  COMPLETE and a toolbar
`command' op each require DOCUMENT.  TOOLBAR is a registered identifier string
or a list of `jetpacs-toolbar-item's.  Booleans take t or :json-false."
  (jetpacs--check-identifier id ":id")
  (when document (jetpacs--check-identifier document ":document"))
  (when value (jetpacs--require-string value ":value"))
  (when on-save (jetpacs--check-descriptor on-save ":on-save"))
  (when on-enter (jetpacs--check-descriptor on-enter ":on-enter"))
  (when read-only (jetpacs--check-bool read-only ":read-only"))
  (when syntax (jetpacs--check-identifier syntax ":syntax"))
  (when line-numbers (jetpacs--check-bool line-numbers ":line-numbers"))
  (when complete (jetpacs--check-bool complete ":complete"))
  (when chromeless (jetpacs--check-bool chromeless ":chromeless"))
  (when publish-state (jetpacs--check-bool publish-state ":publish-state"))
  (when autofocus (jetpacs--check-bool autofocus ":autofocus"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (when (and (eq complete t) (not document))
    (error "jetpacs-editor: :complete requires :document (SPEC 17.4)"))
  (cond
   ((null toolbar))
   ((stringp toolbar) (jetpacs--check-identifier toolbar ":toolbar"))
   ((and (listp toolbar) (jetpacs--node-p (car toolbar)))
    (when (and (not document) (jetpacs--toolbar-has-command-p toolbar))
      (error "jetpacs-editor: a toolbar :command op requires :document (SPEC 17.4/17.7)"))
    (setq toolbar (vconcat toolbar)))
   (t (error "jetpacs-editor: :toolbar must be a registered id string or a list of toolbar items, got %S" toolbar)))
  (jetpacs--node "editor"
                 :id id :document document :value value
                 :on_save on-save :on_enter on-enter
                 :read_only read-only :syntax syntax :line_numbers line-numbers
                 :complete complete :chromeless chromeless
                 :publish_state publish-state :autofocus autofocus
                 :toolbar toolbar :enabled enabled))

;;;; Visualization nodes (§17.5)

(defconst jetpacs--chart-kinds '("line" "bar" "area" "sparkline"))

(cl-defun jetpacs-chart-point (x y &key meta)
  "A ChartPoint {x, y, meta?} for `jetpacs-chart-series' (SPEC §17.5).
X and Y are finite numbers; META is a JSON-data object (a plist)."
  (jetpacs--check-number x ":x" nil nil)
  (jetpacs--check-number y ":y" nil nil)
  (when (and meta (not (and (consp meta) (keywordp (car meta)))))
    (error "jetpacs-chart-point: :meta must be an object plist (SPEC 17.5), got %S" meta))
  (jetpacs--node nil :x x :y y :meta meta))

(cl-defun jetpacs-chart-series (points &key name color)
  "A ChartSeries {points, name?, color?} (SPEC §17.5).
POINTS is a list from `jetpacs-chart-point'."
  (when name (jetpacs--require-string name ":name"))
  (when color (jetpacs--check-color color))
  (jetpacs--node nil :points (vconcat points) :name name :color color))

(cl-defun jetpacs-chart (series &key kind height y-range summary on-point-tap
                                children)
  "A chart over SERIES, a list from `jetpacs-chart-series' (SPEC §17.5).
The x-axis is ORDINAL.  KIND is line(default)/bar/area/sparkline; HEIGHT a
positive dp; Y-RANGE a two-number list with min < max; SUMMARY an accessible
string; ON-POINT-TAP an ActionDescriptor; CHILDREN a fallback node list."
  (when kind (setq kind (jetpacs--check-enum kind jetpacs--chart-kinds ":kind")))
  (when height (jetpacs--check-number height ":height" nil nil t))
  (when y-range
    (unless (and (listp y-range) (= (length y-range) 2)
                 (jetpacs--finite-number-p (nth 0 y-range))
                 (jetpacs--finite-number-p (nth 1 y-range))
                 (< (nth 0 y-range) (nth 1 y-range)))
      (error "jetpacs-chart: :y-range must be [min max] with min < max (SPEC 17.5)")))
  (when summary (jetpacs--require-string summary ":summary"))
  (when on-point-tap (jetpacs--check-descriptor on-point-tap ":on-point-tap"))
  (jetpacs--node "chart"
                 :series (vconcat series) :kind kind :height height
                 :y_range (and y-range (vconcat y-range))
                 :summary summary :on_point_tap on-point-tap
                 :children (and children (vconcat children))))

(cl-defun jetpacs-canvas-line (x1 y1 x2 y2 &key color width)
  "A canvas `line' op (SPEC §17.5).  WIDTH is a non-negative stroke width."
  (dolist (c (list x1 y1 x2 y2)) (jetpacs--check-number c "line coordinate" nil nil))
  (when color (jetpacs--check-color color))
  (when width (jetpacs--check-number width ":width" 0 nil))
  (jetpacs--node nil :op "line" :x1 x1 :y1 y1 :x2 x2 :y2 y2 :color color :width width))

(cl-defun jetpacs-canvas-rect (x y width height &key color fill stroke-width)
  "A canvas `rect' op (SPEC §17.5).  WIDTH/HEIGHT non-negative; FILL a Color."
  (dolist (c (list x y)) (jetpacs--check-number c "rect coordinate" nil nil))
  (jetpacs--check-number width ":width" 0 nil)
  (jetpacs--check-number height ":height" 0 nil)
  (when color (jetpacs--check-color color))
  (when fill (jetpacs--check-color fill))
  (when stroke-width (jetpacs--check-number stroke-width ":stroke_width" 0 nil))
  (jetpacs--node nil :op "rect" :x x :y y :width width :height height
                 :color color :fill fill :stroke_width stroke-width))

(cl-defun jetpacs-canvas-circle (cx cy radius &key color fill stroke-width)
  "A canvas `circle' op (SPEC §17.5).  RADIUS non-negative; FILL a Color."
  (dolist (c (list cx cy)) (jetpacs--check-number c "circle coordinate" nil nil))
  (jetpacs--check-number radius ":radius" 0 nil)
  (when color (jetpacs--check-color color))
  (when fill (jetpacs--check-color fill))
  (when stroke-width (jetpacs--check-number stroke-width ":stroke_width" 0 nil))
  (jetpacs--node nil :op "circle" :cx cx :cy cy :radius radius
                 :color color :fill fill :stroke_width stroke-width))

(cl-defun jetpacs-canvas-point (x y)
  "A CanvasPoint {x, y} for `jetpacs-canvas-path' (SPEC §17.5)."
  (jetpacs--check-number x ":x" nil nil)
  (jetpacs--check-number y ":y" nil nil)
  (jetpacs--node nil :x x :y y))

(cl-defun jetpacs-canvas-path (points &key color fill stroke-width closed)
  "A canvas `path' op over POINTS (from `jetpacs-canvas-point') (SPEC §17.5)."
  (when color (jetpacs--check-color color))
  (when fill (jetpacs--check-color fill))
  (when stroke-width (jetpacs--check-number stroke-width ":stroke_width" 0 nil))
  (when closed (jetpacs--check-bool closed ":closed"))
  (jetpacs--node nil :op "path" :points (vconcat points)
                 :color color :fill fill :stroke_width stroke-width :closed closed))

(cl-defun jetpacs-canvas-text (x y text &key color size)
  "A canvas `text' op drawing TEXT at (X, Y) (SPEC §17.5)."
  (jetpacs--check-number x ":x" nil nil)
  (jetpacs--check-number y ":y" nil nil)
  (jetpacs--require-string text ":text")
  (when color (jetpacs--check-color color))
  (when size (jetpacs--check-number size ":size" 0 nil))
  (jetpacs--node nil :op "text" :x x :y y :text text :color color :size size))

(cl-defun jetpacs-canvas (width height ops &key children)
  "A canvas of WIDTH x HEIGHT drawing OPS (SPEC §17.5).
WIDTH and HEIGHT MUST be positive; OPS is a list of canvas ops
\(`jetpacs-canvas-line' etc.); CHILDREN is a fallback node list."
  (jetpacs--check-number width ":width" nil nil t)
  (jetpacs--check-number height ":height" nil nil t)
  (jetpacs--node "canvas" :width width :height height :ops (vconcat ops)
                 :children (and children (vconcat children))))

(defun jetpacs--check-year-month (value what)
  "Signal unless VALUE is a §17.5 `YYYY-MM' string with month 01-12."
  (unless (and (stringp value)
               (string-match "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)\\'" value))
    (error "jetpacs: %s must be YYYY-MM (SPEC 17.5), got %S" what value))
  (let ((mo (string-to-number (match-string 2 value))))
    (unless (<= 1 mo 12) (error "jetpacs: %s month must be 01-12, got %S" what value)))
  value)

(defun jetpacs--check-mark (mark)
  "Signal unless MARK is a valid month_grid mark plist {dots, color?} (§17.5).
DOTS is a required integer 0..3; COLOR an optional §16.6 color."
  (unless (and (consp mark) (keywordp (car mark)))
    (error "jetpacs-month-grid: a mark must be a plist (use jetpacs-month-mark), got %S" mark))
  (let ((p mark) (has-dots nil))
    (while p
      (let ((k (pop p)) (v (pop p)))
        (pcase k
          (:dots (setq has-dots t) (jetpacs--check-integer v ":dots" 0 3))
          (:color (jetpacs--check-color v))
          (_ (error "jetpacs-month-grid: unknown mark member %S (SPEC 17.5)" k)))))
    (unless has-dots
      (error "jetpacs-month-grid: a mark requires :dots (SPEC 17.5)")))
  mark)

(defun jetpacs--marks->map (marks)
  "Convert MARKS, an alist of (YYYY-MM-DD . mark), to a string-keyed hash-table.
Signals on an invalid or duplicate date key or an invalid mark value."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (cell marks)
      (let ((date (car cell)))
        (jetpacs--check-date date)
        (jetpacs--check-mark (cdr cell))
        (when (gethash date h)
          (error "jetpacs-month-grid: duplicate mark date %S (SPEC 17.5)" date))
        (puthash date (cdr cell) h)))
    h))

(cl-defun jetpacs-month-mark (dots &key color)
  "A month_grid mark {dots, color?} (SPEC §17.5).
DOTS is an integer 0..3; COLOR a §16.6 color."
  (jetpacs--check-integer dots ":dots" 0 3)
  (when color (jetpacs--check-color color))
  (jetpacs--node nil :dots dots :color color))

(cl-defun jetpacs-month-grid (month &key marks selected min-month max-month
                                    on-day-tap on-month-change children)
  "A month grid for MONTH, a `YYYY-MM' string (SPEC §17.5).
MARKS is an alist of (YYYY-MM-DD . mark) from `jetpacs-month-mark'; SELECTED
a YYYY-MM-DD date; MIN-MONTH/MAX-MONTH `YYYY-MM' bounds (min not after max)."
  (jetpacs--check-year-month month ":month")
  (when selected (jetpacs--check-date selected))
  (when min-month (jetpacs--check-year-month min-month ":min_month"))
  (when max-month (jetpacs--check-year-month max-month ":max_month"))
  (when (and min-month max-month (string> min-month max-month))
    (error "jetpacs-month-grid: :min-month must not follow :max-month (SPEC 17.5)"))
  (when on-day-tap (jetpacs--check-descriptor on-day-tap ":on-day-tap"))
  (when on-month-change (jetpacs--check-descriptor on-month-change ":on-month-change"))
  (jetpacs--node "month_grid"
                 :month month
                 :marks (and marks (jetpacs--marks->map marks))
                 :selected selected :min_month min-month :max_month max-month
                 :on_day_tap on-day-tap :on_month_change on-month-change
                 :children (and children (vconcat children))))

;;;; Scaffold + application chrome (§17.6)

(cl-defun jetpacs-snackbar-action (label on-tap)
  "A scaffold snackbar action {label, on_tap} (SPEC §17.6)."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (jetpacs--node nil :label label :on_tap on-tap))

(defun jetpacs--check-snackbar-action (v)
  "Signal unless V is a scaffold snackbar_action {label, on_tap} (§17.6)."
  (unless (and (consp v) (keywordp (car v))
               (stringp (plist-get v :label))
               (plist-member v :on_tap))
    (error "jetpacs-scaffold: :snackbar-action must be {label, on_tap} (use jetpacs-snackbar-action), got %S" v))
  (jetpacs--check-descriptor (plist-get v :on_tap) ":on_tap")
  v)

(defconst jetpacs--top-bar-styles '("small" "center" "medium" "large"))
(defconst jetpacs--toolbar-orientations '("horizontal" "vertical"))
(defconst jetpacs--toolbar-placements
  '("bottom_center" "bottom_start" "bottom_end" "center_start" "center_end"))
(defconst jetpacs--toolbar-exit-directions '("bottom" "top" "start" "end"))
(defconst jetpacs--scroll-behaviors
  '("pinned" "enter_always" "exit_until_collapsed"))
(defconst jetpacs--refresh-indicators '("default" "loading" "none"))
(defconst jetpacs--snackbar-durations '("short" "long" "indefinite"))

(cl-defun jetpacs-scaffold (&key top-bar body bottom-bar fab floating-toolbar
                                 drawer snackbar snackbar-action on-refresh
                                 top-bar-style top-bar-subtitle scroll-behavior
                                 floating-toolbar-orientation
                                 floating-toolbar-expanded
                                 floating-toolbar-placement
                                 floating-toolbar-fab
                                 floating-toolbar-scroll
                                 floating-toolbar-exit-direction
                                 refresh-indicator is-refreshing
                                 snackbar-duration snackbar-dismiss
                                 snackbar-max-lines
                                 sheet sheet-peek-height sheet-state
                                 on-sheet-change)
  "A scaffold (application chrome) node (SPEC §17.6).
TOP-BAR/BODY/BOTTOM-BAR/FAB/FLOATING-TOOLBAR/DRAWER are Nodes; SNACKBAR a
string; SNACKBAR-ACTION a `jetpacs-snackbar-action'; ON-REFRESH a descriptor.

REFRESH-INDICATOR (default, loading, none) fills the pull-to-refresh
indicator slot; IS-REFRESHING is the authored spinner state — Emacs as
the ViewModel — replacing the optimistic self-clearing local flag; both
need ON-REFRESH.  SNACKBAR-DURATION (short, long, indefinite) and
SNACKBAR-DISMISS (the trailing X, implied by indefinite) shape the
snackbar's stay; SNACKBAR-MAX-LINES clamps its visible message while a
screen reader still hears the whole string.

SHEET is the bottom-sheet slot, a Node.  With SHEET-PEEK-HEIGHT it is
the PERSISTENT BottomSheetScaffold form, resting at its peek over the
chrome; without, it is MODAL, shown while SHEET-STATE (hidden, partial,
expanded) says so.  SHEET-STATE is authored presentation state exactly
like a tooltip's :shown — a user dismissal dispatches ON-SHEET-CHANGE
with the new state and holds locally until the authored value changes,
so a re-push cannot slam the sheet back open under the finger.

TOP-BAR-STYLE asks for a REAL M3 TopAppBar around TOP-BAR — small,
center(-aligned), medium or large — instead of the plain status-bar-padded
row the Companion draws when it is absent.  Omitting it is exactly today's
rendering, which is why every existing caller is untouched.

SCROLL-BEHAVIOR (pinned, enter_always, exit_until_collapsed) needs
TOP-BAR-STYLE: it is the M3 behavior the bar and the body's nested scroll
share, and there is no bar to attach it to otherwise.  TOP-BAR-SUBTITLE is
the second line M3 draws under the title.

FLOATING-TOOLBAR-ORIENTATION turns the FLOATING-TOOLBAR slot into a REAL M3
floating toolbar — a rounded pill that floats OVER the body — instead of the
full-width band above the bottom bar the Companion draws when it is absent.
PLACEMENT positions that pill, EXPANDED (default true) collapses it to its
leading content, FAB is a node attached to the pill's end, and SCROLL with
EXIT-DIRECTION lets it slide away as the body scrolls."
  (dolist (pair (list (cons ":top-bar" top-bar) (cons ":body" body)
                      (cons ":bottom-bar" bottom-bar) (cons ":fab" fab)
                      (cons ":floating-toolbar" floating-toolbar)
                      (cons ":drawer" drawer)))
    (when (and (cdr pair) (not (jetpacs--root-node-p (cdr pair))))
      (error "jetpacs-scaffold: %s must be a node, got %S" (car pair) (cdr pair))))
  (when snackbar (jetpacs--require-string snackbar ":snackbar"))
  (when snackbar-action (jetpacs--check-snackbar-action snackbar-action))
  (when on-refresh (jetpacs--check-descriptor on-refresh ":on-refresh"))
  (when refresh-indicator
    (setq refresh-indicator (jetpacs--check-enum refresh-indicator
                                                 jetpacs--refresh-indicators
                                                 ":refresh-indicator"))
    (unless on-refresh
      (error "jetpacs-scaffold: :refresh-indicator needs :on-refresh (SPEC 17.6)")))
  (when is-refreshing
    (jetpacs--check-bool is-refreshing ":is-refreshing")
    (unless on-refresh
      (error "jetpacs-scaffold: :is-refreshing needs :on-refresh (SPEC 17.6)")))
  (when snackbar-duration
    (setq snackbar-duration (jetpacs--check-enum snackbar-duration
                                                 jetpacs--snackbar-durations
                                                 ":snackbar-duration")))
  (when snackbar-dismiss
    (jetpacs--check-bool snackbar-dismiss ":snackbar-dismiss"))
  (when snackbar-max-lines
    (jetpacs--check-integer snackbar-max-lines ":snackbar-max-lines" 1 nil))
  (when (and sheet (not (jetpacs--root-node-p sheet)))
    (error "jetpacs-scaffold: :sheet must be a node, got %S" sheet))
  (when sheet-peek-height
    (unless sheet
      (error "jetpacs-scaffold: :sheet-peek-height styles a sheet it does not author (SPEC 17.6)"))
    (jetpacs--check-number sheet-peek-height ":sheet-peek-height" 1 nil))
  (when sheet-state
    (unless sheet
      (error "jetpacs-scaffold: :sheet-state styles a sheet it does not author (SPEC 17.6)"))
    (setq sheet-state (jetpacs--check-enum sheet-state
                                           '("hidden" "partial" "expanded")
                                           ":sheet-state")))
  (when on-sheet-change
    (jetpacs--check-descriptor on-sheet-change ":on-sheet-change"))
  (when top-bar-style
    (setq top-bar-style (jetpacs--check-enum top-bar-style
                                             jetpacs--top-bar-styles
                                             ":top-bar-style")))
  (when top-bar-subtitle
    (jetpacs--require-string top-bar-subtitle ":top-bar-subtitle"))
  (when scroll-behavior
    (setq scroll-behavior (jetpacs--check-enum scroll-behavior
                                               jetpacs--scroll-behaviors
                                               ":scroll-behavior"))
    (unless top-bar-style
      (error "jetpacs-scaffold: :scroll-behavior needs :top-bar-style (SPEC 17.6)")))
  (when floating-toolbar-orientation
    (setq floating-toolbar-orientation
          (jetpacs--check-enum floating-toolbar-orientation
                               jetpacs--toolbar-orientations
                               ":floating-toolbar-orientation"))
    (unless floating-toolbar
      (error "jetpacs-scaffold: :floating-toolbar-orientation styles a toolbar it does not author (SPEC 17.6)")))
  (when floating-toolbar-expanded
    (jetpacs--check-bool floating-toolbar-expanded ":floating-toolbar-expanded"))
  (when floating-toolbar-placement
    (setq floating-toolbar-placement
          (jetpacs--check-enum floating-toolbar-placement
                               jetpacs--toolbar-placements
                               ":floating-toolbar-placement")))
  (when floating-toolbar-scroll
    (jetpacs--check-bool floating-toolbar-scroll ":floating-toolbar-scroll"))
  (when floating-toolbar-exit-direction
    (setq floating-toolbar-exit-direction
          (jetpacs--check-enum floating-toolbar-exit-direction
                               jetpacs--toolbar-exit-directions
                               ":floating-toolbar-exit-direction")))
  (when (and floating-toolbar-fab (not (jetpacs--root-node-p floating-toolbar-fab)))
    (error "jetpacs-scaffold: :floating-toolbar-fab must be a node, got %S"
           floating-toolbar-fab))
  (jetpacs--node "scaffold"
                 :floating_toolbar_orientation floating-toolbar-orientation
                 :floating_toolbar_expanded floating-toolbar-expanded
                 :floating_toolbar_placement floating-toolbar-placement
                 :floating_toolbar_fab floating-toolbar-fab
                 :floating_toolbar_scroll floating-toolbar-scroll
                 :floating_toolbar_exit_direction floating-toolbar-exit-direction
                 :top_bar top-bar :body body :bottom_bar bottom-bar
                 :fab fab :floating_toolbar floating-toolbar :drawer drawer
                 :snackbar snackbar :snackbar_action snackbar-action
                 :snackbar_duration snackbar-duration
                 :snackbar_dismiss snackbar-dismiss
                 :snackbar_max_lines snackbar-max-lines
                 :on_refresh on-refresh
                 :refresh_indicator refresh-indicator
                 :is_refreshing is-refreshing
                 :sheet sheet :sheet_peek_height sheet-peek-height
                 :sheet_state sheet-state :on_sheet_change on-sheet-change
                 :top_bar_style top-bar-style
                 :top_bar_subtitle top-bar-subtitle
                 :scroll_behavior scroll-behavior))

;;;; SurfaceSpec shapes (§13.4)
;;
;; These wrap a node tree into the SurfaceSpec a caller hands to
;; `ebp-client-surface-update'.  An `app:*' single-root surface is just the
;; root node itself; the wrappers cover multi-view app, notification, widget.

(defun jetpacs-multi-view (views initial-view)
  "An `app:*' multi-view SurfaceSpec {views, initial_view} (SPEC §13.4).
VIEWS is a non-empty alist of (VIEW-ID . root-node) with §4.4-identifier ids;
INITIAL-VIEW MUST name an existing view."
  (unless views (error "jetpacs-multi-view: views must be non-empty (SPEC 13.4)"))
  (jetpacs--check-identifier initial-view ":initial-view")
  (let ((h (make-hash-table :test 'equal)) (ids '()))
    (dolist (cell views)
      (let ((id (car cell)))
        (jetpacs--check-identifier id "view id")
        (unless (jetpacs--root-node-p (cdr cell))
          (error "jetpacs-multi-view: view %S value must be a root node" id))
        (when (gethash id h)
          (error "jetpacs-multi-view: duplicate view id %S" id))
        (puthash id (cdr cell) h)
        (push id ids)))
    (unless (member initial-view ids)
      (error "jetpacs-multi-view: initial_view %S names no existing view (SPEC 13.4)" initial-view))
    (jetpacs--node nil :views h :initial_view initial-view)))

(cl-defun jetpacs-notification-surface (body &key meta)
  "A `notification:*' SurfaceSpec {body, meta?} (SPEC §13.4; META is §18.5).
BODY is a Node."
  (unless (jetpacs--root-node-p body)
    (error "jetpacs-notification-surface: BODY must be a root node, got %S" body))
  (jetpacs--node nil :body body :meta meta))

(cl-defun jetpacs-widget-surface (title body &key empty header-action)
  "A `widget:*' SurfaceSpec {title, body, empty?, header_action?} (SPEC §13.4).
TITLE is a string; BODY and EMPTY are Nodes; HEADER-ACTION a descriptor."
  (jetpacs--require-string title ":title")
  (unless (jetpacs--root-node-p body)
    (error "jetpacs-widget-surface: BODY must be a root node, got %S" body))
  (when (and empty (not (jetpacs--root-node-p empty)))
    (error "jetpacs-widget-surface: :empty must be a root node, got %S" empty))
  (when header-action (jetpacs--check-descriptor header-action ":header-action"))
  (jetpacs--node nil :title title :body body :empty empty :header_action header-action))

;;;; Hypertext block sequences

(defun jetpacs-hypertext (&rest nodes)
  "A hypertext block sequence: a vector of root NODES.
Each element MUST be a root node (has `:t').  Accepts nodes as `&rest' or
as a single list."
  (let ((kids (jetpacs--as-children nodes)))
    (mapc (lambda (n)
            (unless (jetpacs--root-node-p n)
              (error "jetpacs-hypertext: each element must be a root node, got %S" n)))
          kids)
    kids))

;;;; Target-profile gating (§16.2 / §10.2)
;;
;; §16.2: Emacs MUST NOT emit a node type absent from the applicable
;; target's advertised `surface_profiles.<target>.node_types'.  The
;; AUTHORITATIVE set for a connection is its welcome; the defconsts below
;; are the reference companion's advertised sets, for offline building.

(defconst jetpacs-content-node-types
  '("rich_text" "icon" "badge" "image" "section_header" "empty_state"
    "progress" "date_stamp" "tooltip")
  "The §17.2 content node types shared by the reference app and dialog profiles.")

(defconst jetpacs-input-node-types
  '("icon_button" "chip" "assist_chip" "menu" "checkbox" "switch"
    "enum_list" "slider" "date_button" "time_button" "split_button"
    "navigation_rail" "search_bar" "dropdown" "segmented_button")
  "The §17.4 input node types shared by the reference app and dialog profiles.")

(defconst jetpacs-layout-node-types
  '("flow_row" "surface" "lazy_column" "card" "collapsible"
    "reorderable_list" "tabs" "table" "pane_scaffold"
    "app_bar_row" "app_bar_column" "carousel" "fab_menu" "button_group"
    "lazy_grid")
  "The §17.3 non-core layout node types (reference app profile).")

(defconst jetpacs-viz-node-types '("chart" "canvas" "month_grid")
  "The §17.5 visualization node types (reference app profile).")

(defconst jetpacs-app-node-types
  (append '("text" "row" "column" "box" "spacer" "divider" "button"
            "text_input" "scaffold" "editor")
          jetpacs-content-node-types jetpacs-input-node-types
          jetpacs-layout-node-types jetpacs-viz-node-types)
  "The reference companion's advertised `app' node_types (all 44; §10.2/§16.2).
The AUTHORITATIVE set for a connection is its welcome `surface_profiles'.")

(defconst jetpacs-dialog-node-types
  (append '("text" "row" "column" "box" "spacer" "divider" "button" "text_input"
            "editor" "surface")
          jetpacs-content-node-types jetpacs-input-node-types)
  "The reference companion's advertised `dialog' node_types (34).
`surface' is in the set because `shape' and `elevation' live on exactly
one node and BasicAlertDialog's whole subject is the CALLER-supplied
Surface — without it a dialog spec could never carry its own container.
`editor' is in the set because JC-4b added it to the Companion's
`DIALOG_NODE_TYPES' (NodeSupport.kt) so a dialog could host the capf
picker.  This constant is the REFERENCE union used by
`jetpacs-check-profile'; the runtime SPEC 16.2 gate reads the live
welcome instead (`jetpacs-node-advertised-p'), which is why the picker
worked on device while this constant disagreed.")

(defconst jetpacs-notification-node-types
  '("text" "row" "column" "box" "spacer" "divider")
  "The reference companion's advertised `notification' node_types (6).")

(defconst jetpacs--opaque-members '(:args :meta :value)
  "Members carrying opaque JSON data, whose object keys are application data
and NOT node-type discriminators: §14.1 action `args', §17.5 chart-point
`meta', and a `dialog.submit' `value'.  These never contain nodes, so the
node-type scan does not descend into them.")

(define-error 'jetpacs-duplicate-node-id
  "Duplicate node id in one document (SPEC 16.1)")

(defvar jetpacs-node-id-claims nil
  "Document-wide table of claimed node ids, or nil outside a document build.
SPEC 16.1 makes an authored node `id' unique across the COMPLETE surface
document, and `jetpacs-chrome--build' composes N independently-built
screen subtrees into ONE multi_view.  Whatever performs that composition
binds this (the shell binds it around every root build); minters call
`jetpacs-claim-node-id'.  Outside a binding the claim is the identity
function, so a single-subtree render emits byte-identical ids to before
— which is what keeps live SPEC 13.6 input drafts and device-local fold
state attached.")

(defun jetpacs--suffixed-id (base n)
  "BASE with suffix -N, truncated so the result is a SPEC 4.4 identifier.
`jetpacs-wire-id' can already return exactly 128 chars, so appending
without truncating would produce an id `jetpacs--check-identifier'
rejects — costing the screen at build time."
  (let ((suffix (format "-%d" n)))
    (concat (substring base 0 (min (length base) (- 128 (length suffix))))
            suffix)))

(defun jetpacs-claim-node-id (base)
  "Claim BASE as a node id in the current document; return the id to emit.
BASE when free, else BASE with the lowest free `-N' suffix.  The FIRST
claimant keeps the stable id — so its draft and fold state survive — and
only the DUPLICATE moves; SPEC 16.1 answers a duplicate with `1201' for
the entire update, so the alternative is losing the whole surface.
Identity outside a `jetpacs-node-id-claims' binding."
  (if (null jetpacs-node-id-claims)
      base
    (let ((n (gethash base jetpacs-node-id-claims)))
      (if (null n)
          (progn (puthash base 1 jetpacs-node-id-claims) base)
        ;; A SEEDED or synthesized name stores t, not a count; a real
        ;; base equal to one would otherwise reach
        ;; (format "%s-%d" base t) and signal.
        (let* ((n (if (integerp n) n 1))
               (try (jetpacs--suffixed-id base n)))
          (while (gethash try jetpacs-node-id-claims)
            (setq n (1+ n) try (jetpacs--suffixed-id base n)))
          (puthash base (1+ n) jetpacs-node-id-claims)
          (puthash try t jetpacs-node-id-claims)
          try)))))

(defun jetpacs-claimed-node-id (base)
  "The id BASE actually emitted under in this document, when knowable.
BASE itself when it was claimed (the first claimant keeps the stable
name) or when no document build is in flight; nil when BASE was never
claimed.  `:reset-input-ids' MUST be resolved through this — passing an
authored base the claim table suffixed would 1201 the push."
  (if (null jetpacs-node-id-claims)
      base
    (and (gethash base jetpacs-node-id-claims) base)))

(defun jetpacs--collect-node-ids (value acc)
  "Accumulate every TYPED node's `:id' in VALUE into ACC (a list).
Only plists carrying a string `:t' contribute: a `trigger.fire' builtin
descriptor also has an `:id' (`jetpacs-trigger-fire') and it is a
trigger identity, not a node identity — the Companion reads `id' only
inside its node walk, so collecting descriptor ids here would
false-positive.  Same `jetpacs--opaque-members' discipline as
`jetpacs--collect-node-types'; alist cells (a multi_view's views)
descend through their cdr."
  (cond
   ((vectorp value)
    (let ((a acc))
      (mapc (lambda (v) (setq a (jetpacs--collect-node-ids v a))) value) a))
   ((hash-table-p value)
    (let ((a acc))
      (maphash (lambda (_k v) (setq a (jetpacs--collect-node-ids v a)))
               value)
      a))
   ((and (consp value) (keywordp (car value)))
    (let ((p value) (a acc)
          (typed (stringp (plist-get value :t))))
      (while p
        (let ((k (pop p)) (v (pop p)))
          (when (and typed (eq k :id) (stringp v)) (push v a))
          (unless (memq k jetpacs--opaque-members)
            (setq a (jetpacs--collect-node-ids v a)))))
      a))
   ((consp value)
    (let ((a (jetpacs--collect-node-ids (car value) acc)))
      (jetpacs--collect-node-ids (cdr value) a)))
   (t acc)))

(defun jetpacs--collect-node-types (value acc)
  "Accumulate every node-type `:t' discriminator in VALUE into ACC (a list).
Descends into node/vector/hash/list structure but NOT into opaque data
members (`jetpacs--opaque-members'), so a data key literally named \"t\"
inside `args'/`meta'/`value' is never mistaken for a node type."
  (cond
   ((vectorp value)
    (let ((a acc))
      (mapc (lambda (v) (setq a (jetpacs--collect-node-types v a))) value) a))
   ((hash-table-p value)
    (let ((a acc))
      (maphash (lambda (_k v) (setq a (jetpacs--collect-node-types v a))) value) a))
   ((and (consp value) (keywordp (car value)))        ; a node / sub-spec plist
    (let ((p value) (a acc))
      (while p
        (let ((k (pop p)) (v (pop p)))
          (when (eq k :t) (push v a))
          (unless (memq k jetpacs--opaque-members)
            (setq a (jetpacs--collect-node-types v a)))))
      a))
   ((consp value)                                     ; a bare list of nodes
    (let ((a acc))
      (dolist (n value) (setq a (jetpacs--collect-node-types n a))) a))
   (t acc)))

(defun jetpacs-check-node-types (tree allowed &optional what)
  "Signal if TREE uses a node type not in ALLOWED (a list of type strings) (§16.2).
TREE is a node, a hypertext vector, or a SurfaceSpec; the whole subtree is
scanned.  WHAT names the target for the message.  Returns TREE.  For a live
connection, pass that connection's advertised
`surface_profiles.<target>.node_types' as ALLOWED."
  (dolist (ty (delete-dups (jetpacs--collect-node-types tree '())))
    (unless (member ty allowed)
      (error "jetpacs: node type %S is not advertised for %s (SPEC 16.2)"
             ty (or what "this target"))))
  tree)

(defun jetpacs-check-profile (tree profile)
  "Signal if TREE uses a type outside the reference PROFILE's node set (§16.2).
PROFILE is `app', `dialog', or `notification'.  For a specific connection,
prefer `jetpacs-check-node-types' with that connection's advertised set."
  (jetpacs-check-node-types
   tree
   (pcase profile
     ('app jetpacs-app-node-types)
     ('dialog jetpacs-dialog-node-types)
     ('notification jetpacs-notification-node-types)
     (_ (error "jetpacs-check-profile: unknown profile %S (want app/dialog/notification)" profile)))
   (symbol-name profile)))

(provide 'jetpacs-widgets)
;;; jetpacs-widgets.el ends here
