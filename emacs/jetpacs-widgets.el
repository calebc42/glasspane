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

(provide 'jetpacs-widgets)
;;; jetpacs-widgets.el ends here
