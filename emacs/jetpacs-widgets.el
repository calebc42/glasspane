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

;;;; Catalogs (mirrors of ebp/contract.json, for gating and coverage tests)

(defconst jetpacs-node-types
  '("text" "rich_text" "icon" "image" "date_stamp" "section_header"
    "empty_state" "progress" "badge" "row" "column" "flow_row" "box"
    "surface" "lazy_column" "spacer" "divider" "card" "collapsible"
    "reorderable_list" "tabs" "table" "button" "icon_button" "chip"
    "assist_chip" "menu" "text_input" "editor" "checkbox" "switch"
    "enum_list" "date_button" "time_button" "slider" "chart" "canvas"
    "month_grid" "scaffold")
  "The 39 EBP node types (contract.json `node_types').")

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

(defun jetpacs--children-and-opts (args)
  "Split container ARGS into (CHILDREN . OPTS) at the first keyword.
Child nodes are plists; the first bare keyword in ARGS marks the start of
the trailing options plist.  Lets a `&rest'-children constructor take
options: `(jetpacs-row a b :spacing 8)' separates cleanly."
  (let ((i (cl-position-if #'keywordp args)))
    (if i (cons (cl-subseq args 0 i) (cl-subseq args i))
      (cons args nil))))

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
      (unless (and (stringp confirm) (not (string-empty-p confirm)))
        (error "jetpacs-action: :confirm must be a non-empty string (SPEC 14.1), got %S" confirm)))
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

(cl-defun jetpacs-progress (&key variant value)
  "A progress node (SPEC §17.2).
VARIANT is circular (default) or linear; VALUE a number 0..1 (omit for
indeterminate)."
  (when variant (setq variant (jetpacs--check-enum variant '("circular" "linear") ":variant")))
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
  (let* ((split (jetpacs--children-and-opts args))
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
  (let* ((split (jetpacs--children-and-opts args))
         (opts (cdr split))
         (spacing (plist-get opts :spacing))
         (align (plist-get opts :align))
         (arrange (plist-get opts :arrange))
         (scroll (plist-get opts :scroll))
         (fill (plist-get opts :fill)))
    (when spacing (jetpacs--check-number spacing ":spacing" 0 nil))
    (when align (setq align (jetpacs--check-enum align jetpacs--column-aligns ":align")))
    (when arrange (setq arrange (jetpacs--check-enum arrange jetpacs--arranges ":arrange")))
    (when scroll (jetpacs--check-bool scroll ":scroll"))
    (when fill (jetpacs--check-bool fill ":fill"))
    (jetpacs--node "column"
                   :children (jetpacs--as-children (car split))
                   :spacing spacing :align align :arrange arrange
                   :scroll scroll :fill fill)))

(defun jetpacs-flow-row (&rest args)
  "A flow row whose children wrap to later runs (SPEC §17.3).
Trailing options: :spacing, :run-spacing (dp), :align (top/center/bottom),
:arrange."
  (let* ((split (jetpacs--children-and-opts args))
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
  (let* ((split (jetpacs--children-and-opts args))
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
Options: :color, :shape (rounded/rounded_small/circle), :elevation (a dp)."
  (let* ((split (jetpacs--children-and-opts args))
         (opts (cdr split))
         (color (plist-get opts :color))
         (shape (plist-get opts :shape))
         (elevation (plist-get opts :elevation)))
    (when color (jetpacs--check-color color))
    (when shape (setq shape (jetpacs--check-enum shape jetpacs--surface-shapes ":shape")))
    (when elevation (jetpacs--check-number elevation ":elevation" 0 nil))
    (jetpacs--node "surface"
                   :children (jetpacs--as-children (car split))
                   :color color :shape shape :elevation elevation)))

(defun jetpacs-lazy-column (&rest args)
  "A lazily-composed vertical list preserving array order (SPEC §17.3).
Trailing options: :spacing (dp), :content-padding (dp)."
  (let* ((split (jetpacs--children-and-opts args))
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

(defun jetpacs-card (&rest args)
  "A card container of child nodes (SPEC §17.3).
Trailing options: :on-tap, :on-long-tap (ActionDescriptors); :swipe-start,
:swipe-end (from `jetpacs-swipe')."
  (let* ((split (jetpacs--children-and-opts args))
         (opts (cdr split))
         (on-tap (plist-get opts :on-tap))
         (on-long-tap (plist-get opts :on-long-tap))
         (swipe-start (plist-get opts :swipe-start))
         (swipe-end (plist-get opts :swipe-end)))
    (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
    (when on-long-tap (jetpacs--check-descriptor on-long-tap ":on-long-tap"))
    (when swipe-start (jetpacs--check-swipe swipe-start ":swipe-start"))
    (when swipe-end (jetpacs--check-swipe swipe-end ":swipe-end"))
    (jetpacs--node "card"
                   :children (jetpacs--as-children (car split))
                   :on_tap on-tap
                   :on_long_tap on-long-tap
                   :swipe_start swipe-start
                   :swipe_end swipe-end)))

(cl-defun jetpacs-collapsible (id header &rest args)
  "A collapsible section with required ID and HEADER node, plus children (§17.3).
Trailing options: :collapsed (t or :json-false), :on-long-tap, :swipe-start,
:swipe-end."
  (jetpacs--check-identifier id ":id")
  (unless (jetpacs--node-p header)
    (error "jetpacs-collapsible: HEADER must be a node, got %S" header))
  (let* ((split (jetpacs--children-and-opts args))
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

(cl-defun jetpacs-tab-item (label &key icon)
  "A TabItem {label, icon?} for `jetpacs-tabs' (SPEC §17.3)."
  (jetpacs--require-string label ":label")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (jetpacs--node nil :label label :icon icon))

(cl-defun jetpacs-tabs (items children &key initial scrollable pager-only
                              on-change id)
  "A tab strip: parallel ITEMS (TabItems) and CHILDREN (Nodes) (SPEC §17.3).
The two lists MUST have equal non-zero length.  INITIAL is a 0-based index
below the count; SCROLLABLE/PAGER-ONLY are booleans (t or :json-false);
ON-CHANGE an ActionDescriptor; ID a §4.4 identifier."
  (let ((ni (length items)) (nc (length children)))
    (when (or (zerop ni) (/= ni nc))
      (error "jetpacs-tabs: items and children must be equal non-zero length (SPEC 17.3): %d vs %d"
             ni nc))
    (when initial (jetpacs--check-integer initial ":initial" 0 (1- ni)))
    (when scrollable (jetpacs--check-bool scrollable ":scrollable"))
    (when pager-only (jetpacs--check-bool pager-only ":pager-only"))
    (when id (jetpacs--check-identifier id ":id"))
    (when on-change (jetpacs--check-descriptor on-change ":on-change"))
    (jetpacs--node "tabs"
                   :items (vconcat items)
                   :children (vconcat children)
                   :initial initial
                   :scrollable scrollable
                   :pager_only pager-only
                   :on_change on-change
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

(defconst jetpacs--button-variants '("filled" "tonal" "outlined" "text"))
(defconst jetpacs--keyboards '("text" "number" "decimal" "email" "phone" "uri"))

(cl-defun jetpacs-button (label on-tap &key icon variant enabled)
  "A button labeled LABEL dispatching ON-TAP (SPEC §17.4).
ICON a §4.4 identifier; VARIANT filled(default)/tonal/outlined/text; ENABLED
a boolean (t or :json-false; default true)."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when variant (setq variant (jetpacs--check-enum variant jetpacs--button-variants ":variant")))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "button" :label label :on_tap on-tap
                 :icon icon :variant variant :enabled enabled))

(cl-defun jetpacs-icon-button (icon on-tap &key content-description badge enabled)
  "An icon button showing ICON dispatching ON-TAP (SPEC §17.4).
ICON is a §4.4 identifier (§17.1); BADGE a string or number."
  (jetpacs--check-identifier icon ":icon")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when content-description (jetpacs--require-string content-description ":content_description"))
  (when badge (jetpacs--check-badge badge))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "icon_button" :icon icon :on_tap on-tap
                 :content_description content-description :badge badge :enabled enabled))

(cl-defun jetpacs-chip (label &key on-tap selected icon enabled)
  "A chip labeled LABEL (SPEC §17.4).
ON-TAP an ActionDescriptor; SELECTED/ENABLED booleans; ICON an identifier."
  (jetpacs--require-string label ":label")
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (when selected (jetpacs--check-bool selected ":selected"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "chip" :label label :on_tap on-tap
                 :selected selected :icon icon :enabled enabled))

(cl-defun jetpacs-assist-chip (label &key on-tap icon enabled)
  "An assist chip labeled LABEL (SPEC §17.4)."
  (jetpacs--require-string label ":label")
  (when on-tap (jetpacs--check-descriptor on-tap ":on-tap"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "assist_chip" :label label :on_tap on-tap :icon icon :enabled enabled))

(cl-defun jetpacs-menu-item (label on-tap &key icon enabled)
  "A MenuItem {label, on_tap, icon?, enabled?} for `jetpacs-menu' (SPEC §17.4)."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-tap ":on-tap")
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node nil :label label :on_tap on-tap :icon icon :enabled enabled))

(cl-defun jetpacs-menu (items &key icon enabled)
  "A menu of ITEMS (from `jetpacs-menu-item') (SPEC §17.4)."
  (when icon (jetpacs--check-identifier icon ":icon"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "menu" :items (vconcat items) :icon icon :enabled enabled))

(cl-defun jetpacs-text-input (id &key value hint label on-change on-submit
                                 single-line min-lines max-lines monospace syntax
                                 password keyboard autofocus clear-on-submit enabled)
  "A text input identified by ID (SPEC §17.4).
Booleans (SINGLE-LINE, MONOSPACE, PASSWORD, AUTOFOCUS, CLEAR-ON-SUBMIT,
ENABLED) take t or :json-false.  Enforces the §17.4 line-count, single-line
no-newline, and password constraints at build time."
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
                 :clear_on_submit clear-on-submit :enabled enabled))

(cl-defun jetpacs-checkbox (id &key checked label on-change enabled)
  "A checkbox identified by ID (SPEC §17.4).
CHECKED/ENABLED booleans (t or :json-false); ON-CHANGE an ActionDescriptor."
  (jetpacs--check-identifier id ":id")
  (when checked (jetpacs--check-bool checked ":checked"))
  (when label (jetpacs--require-string label ":label"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "checkbox" :id id :checked checked :label label
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-switch (id &key checked label on-change enabled)
  "A switch identified by ID (SPEC §17.4).
CHECKED/ENABLED booleans (t or :json-false); ON-CHANGE an ActionDescriptor."
  (jetpacs--check-identifier id ":id")
  (when checked (jetpacs--check-bool checked ":checked"))
  (when label (jetpacs--require-string label ":label"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "switch" :id id :checked checked :label label
                 :on_change on-change :enabled enabled))

(defun jetpacs-enum-option (label value)
  "An EnumOption {label, value} for `jetpacs-enum-list' (SPEC §17.4).
VALUE is a string, number, or boolean (t or :json-false)."
  (jetpacs--require-string label ":label")
  (unless (or (stringp value) (numberp value) (memq value '(t :json-false)))
    (error "jetpacs-enum-option: value must be a string, number, or boolean, got %S" value))
  (jetpacs--node nil :label label :value value))

(cl-defun jetpacs-enum-list (id options &key value multi-select allow-add
                                on-change enabled)
  "A single/multi-select list identified by ID over OPTIONS (SPEC §17.4).
OPTIONS is a list from `jetpacs-enum-option'.  VALUE is one option value, or
\(with MULTI-SELECT) a list/vector of distinct option values.  Unless
ALLOW-ADD, every selected value MUST appear in OPTIONS.  No implicit selection."
  (jetpacs--check-identifier id ":id")
  (when multi-select (jetpacs--check-bool multi-select ":multi-select"))
  (when allow-add (jetpacs--check-bool allow-add ":allow-add"))
  (when on-change (jetpacs--check-descriptor on-change ":on-change"))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
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
                 :on_change on-change :enabled enabled))

(cl-defun jetpacs-date-button (label on-pick &key value enabled)
  "A date-picker button labeled LABEL dispatching ON-PICK (SPEC §17.4).
VALUE is a YYYY-MM-DD string."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-pick ":on-pick")
  (when value (jetpacs--check-date value))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "date_button" :label label :on_pick on-pick :value value :enabled enabled))

(cl-defun jetpacs-time-button (label on-pick &key value enabled)
  "A time-picker button labeled LABEL dispatching ON-PICK (SPEC §17.4).
VALUE is an HH:MM string in local civil time."
  (jetpacs--require-string label ":label")
  (jetpacs--check-descriptor on-pick ":on-pick")
  (when value (jetpacs--check-time value))
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (jetpacs--node "time_button" :label label :on_pick on-pick :value value :enabled enabled))

(cl-defun jetpacs-slider (id on-change &key value min max values enabled)
  "A slider identified by ID dispatching ON-CHANGE (SPEC §17.4).
Continuous: :min (default 0) < :max (default 1), :value in [min,max].
Discrete: :values is 2+ strictly-increasing distinct numbers, MUST omit
:min/:max, and :value must equal a listed number."
  (jetpacs--check-identifier id ":id")
  (jetpacs--check-descriptor on-change ":on-change")
  (when enabled (jetpacs--check-bool enabled ":enabled"))
  (cond
   (values
    (when (or min max)
      (error "jetpacs-slider: a discrete slider must omit :min/:max (SPEC 17.4)"))
    (unless (and (>= (length values) 2)
                 (cl-every #'jetpacs--finite-number-p values)
                 (apply #'< values))
      (error "jetpacs-slider: :values must be 2+ strictly-increasing finite numbers (SPEC 17.4)"))
    (when (and value (not (cl-member value values :test #'jetpacs--json-equal)))
      (error "jetpacs-slider: discrete :value must equal a listed number under SPEC 4.3 (17.4)")))
   (t
    (when min (jetpacs--check-number min ":min" nil nil))
    (when max (jetpacs--check-number max ":max" nil nil))
    (when value (jetpacs--check-number value ":value" nil nil))
    (let ((lo (or min 0)) (hi (or max 1)))
      (unless (< lo hi)
        (error "jetpacs-slider: :min must be less than :max (SPEC 17.4)"))
      (when (and value (not (<= lo value hi)))
        (error "jetpacs-slider: :value must be within [min,max] (SPEC 17.4)")))))
  (jetpacs--node "slider"
                 :id id :on_change on-change :value value
                 :min min :max max :values (and values (vconcat values))
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

(cl-defun jetpacs-scaffold (&key top-bar body bottom-bar fab floating-toolbar
                                 drawer snackbar snackbar-action on-refresh)
  "A scaffold (application chrome) node (SPEC §17.6).
TOP-BAR/BODY/BOTTOM-BAR/FAB/FLOATING-TOOLBAR/DRAWER are Nodes; SNACKBAR a
string; SNACKBAR-ACTION a `jetpacs-snackbar-action'; ON-REFRESH a descriptor."
  (dolist (pair (list (cons ":top-bar" top-bar) (cons ":body" body)
                      (cons ":bottom-bar" bottom-bar) (cons ":fab" fab)
                      (cons ":floating-toolbar" floating-toolbar)
                      (cons ":drawer" drawer)))
    (when (and (cdr pair) (not (jetpacs--root-node-p (cdr pair))))
      (error "jetpacs-scaffold: %s must be a node, got %S" (car pair) (cdr pair))))
  (when snackbar (jetpacs--require-string snackbar ":snackbar"))
  (when snackbar-action (jetpacs--check-snackbar-action snackbar-action))
  (when on-refresh (jetpacs--check-descriptor on-refresh ":on-refresh"))
  (jetpacs--node "scaffold"
                 :top_bar top-bar :body body :bottom_bar bottom-bar
                 :fab fab :floating_toolbar floating-toolbar :drawer drawer
                 :snackbar snackbar :snackbar_action snackbar-action
                 :on_refresh on-refresh))

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
    "progress" "date_stamp")
  "The §17.2 content node types shared by the reference app and dialog profiles.")

(defconst jetpacs-input-node-types
  '("icon_button" "chip" "assist_chip" "menu" "checkbox" "switch"
    "enum_list" "slider" "date_button" "time_button")
  "The §17.4 input node types shared by the reference app and dialog profiles.")

(defconst jetpacs-layout-node-types
  '("flow_row" "surface" "lazy_column" "card" "collapsible"
    "reorderable_list" "tabs" "table")
  "The §17.3 non-core layout node types (reference app profile).")

(defconst jetpacs-viz-node-types '("chart" "canvas" "month_grid")
  "The §17.5 visualization node types (reference app profile).")

(defconst jetpacs-app-node-types
  (append '("text" "row" "column" "box" "spacer" "divider" "button"
            "text_input" "scaffold" "editor")
          jetpacs-content-node-types jetpacs-input-node-types
          jetpacs-layout-node-types jetpacs-viz-node-types)
  "The reference companion's advertised `app' node_types (all 39; §10.2/§16.2).
The AUTHORITATIVE set for a connection is its welcome `surface_profiles'.")

(defconst jetpacs-dialog-node-types
  (append '("text" "row" "column" "box" "spacer" "divider" "button" "text_input")
          jetpacs-content-node-types jetpacs-input-node-types)
  "The reference companion's advertised `dialog' node_types (26; no editor/
scaffold/layout/viz).")

(defconst jetpacs-notification-node-types
  '("text" "row" "column" "box" "spacer" "divider")
  "The reference companion's advertised `notification' node_types (6).")

(defconst jetpacs--opaque-members '(:args :meta :value)
  "Members carrying opaque JSON data, whose object keys are application data
and NOT node-type discriminators: §14.1 action `args', §17.5 chart-point
`meta', and a `dialog.submit' `value'.  These never contain nodes, so the
node-type scan does not descend into them.")

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
