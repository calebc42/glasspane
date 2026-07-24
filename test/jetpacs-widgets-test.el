;;; jetpacs-widgets-test.el --- ERT for the EBP widget builders -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Byte-parity ERT for `jetpacs-widgets.el' (rung JW-0 of
;; docs/PLAN-jetpacs-widgets.md).  For each relevant `ebp/goldens/'
;; vector, a builder call whose canonical serialization must be
;; byte-identical to the golden line -- offline, deterministic, no device.
;; JW-0 covers the ActionDescriptor / builtin vectors (widgets.golden
;; 61-71) plus the canonical-serializer, funnel, universal-rider, color,
;; and action-validation invariants.  Node-type vectors (00-60) land with
;; their rungs.  Contract-sync tests guard the catalogs against drift and
;; seed the 39-type coverage floor.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-widgets)

(defvar jetpacs-test--dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory holding this test file (repo `test/').")

(defun jetpacs-test--golden-map (name)
  "Return a hash of INDEX-STRING -> RAW-JSON from `ebp/goldens/NAME.golden'."
  (let ((h (make-hash-table :test 'equal)))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name (format "../ebp/goldens/%s.golden" name)
                         jetpacs-test--dir))
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (when (string-match "\\`\\([0-9]+\\) \\(.*\\)\\'" line)
            (puthash (match-string 1 line) (match-string 2 line) h)))
        (forward-line 1)))
    h))

(defun jetpacs-test--contract ()
  "Parse `ebp/contract.json' as an alist (symbol keys, list arrays)."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "../ebp/contract.json" jetpacs-test--dir))
    (json-parse-buffer :object-type 'alist :array-type 'list)))

;;;; Byte-parity: ActionDescriptor / builtin vectors (widgets.golden 61-71)

(ert-deftest jetpacs-widgets/action-goldens ()
  "Every action/builtin vector in widgets.golden builds byte-identically."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "61" (jetpacs-action "demo.min"))
      (chk "62" (jetpacs-action "demo.full"
                                :args '(:k "v")
                                :capture-fields '("title")
                                :confirm "Really?"
                                :dedupe "demo:full"
                                :ttl-s 86400
                                :when-offline 'queue))
      (chk "63" (jetpacs-action "demo.wake" :ttl-s 3600 :when-offline 'wake))
      (chk "64" (jetpacs-view-switch "detail"))
      (chk "65" (jetpacs-clipboard-copy "copied"))
      (chk "66" (jetpacs-share "shared" :title "Share note"))
      (chk "67" (jetpacs-settings-open))
      (chk "68" (jetpacs-trigger-fire "manual-sync"))
      (chk "69" (jetpacs-dialog-submit :value "ok"))
      (chk "70" (jetpacs-dialog-submit :capture-fields '("name")))
      (chk "71" (jetpacs-dialog-dismiss)))))

;;;; Byte-parity: Content-family nodes (widgets.golden 00-16, JW-1)

(ert-deftest jetpacs-widgets/content-goldens ()
  "Content-family constructors build byte-identically to widgets.golden 00-16."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "00" (jetpacs-text "hi"))
      (chk "01" (jetpacs-with-attrs
                 (jetpacs-text "hi" :style 'title :font-weight "bold" :color "#ff0000"
                               :selectable t :max-lines 2 :syntax "elisp")
                 :key "k1" :padding 4))
      (chk "02" (jetpacs-rich-text
                 (list (jetpacs-span "plain")
                       (jetpacs-span "styled" :bg "#eeeeee" :color "primary"
                                     :font-weight 700 :italic t :mono t :underline t
                                     :on-tap (jetpacs-action "span.tap")))
                 :style 'body))
      (chk "03" (jetpacs-icon "star"))
      (chk "04" (jetpacs-icon "star" :badge "3" :color "primary"
                              :content-description "Starred" :size 24))
      (chk "05" (jetpacs-image "https://example.com/a.png"))
      (chk "06" (jetpacs-with-attrs
                 (jetpacs-image "https://example.com/a.png" :content-scale 'crop
                                :content-description "Photo")
                 :aspect_ratio 1.5 :height 80 :width 120))
      (chk "07" (jetpacs-date-stamp))
      (chk "08" (jetpacs-date-stamp :day 5 :month "Jul" :month-index 7
                                    :time "12:30" :year 2026))
      (chk "09" (jetpacs-section-header "Inbox"))
      (chk "10" (jetpacs-section-header "Inbox" :trailing (jetpacs-icon "sort")))
      (chk "11" (jetpacs-empty-state))
      (chk "12" (jetpacs-empty-state :icon "inbox" :title "Nothing here"
                                     :caption "All done" :action-label "Refresh"
                                     :on-tap (jetpacs-action "demo.tap")))
      (chk "13" (jetpacs-progress))
      (chk "14" (jetpacs-progress :variant 'linear :value 0.5))
      (chk "15" (jetpacs-badge "9"))
      (chk "16" (jetpacs-badge "99" :icon "mail" :color "error"
                               :children (list (jetpacs-icon "mail")))))))

(ert-deftest jetpacs-widgets/content-validation ()
  "Content constructors fail fast on statically-invalid input."
  (should-error (jetpacs-text 42))                       ; text must be a string
  (should-error (jetpacs-text "x" :style 'bogus))        ; style enum
  (should-error (jetpacs-text "x" :max-lines 0))         ; positive integer
  (should-error (jetpacs-text "x" :font-weight 950))     ; 100..900
  (should-error (jetpacs-icon "bad!"))                   ; name is a §4.4 id
  (should-error (jetpacs-image "http://x/a.png"))        ; https/data:image only
  (should-error (jetpacs-date-stamp :day 32))            ; 1..31
  (should-error (jetpacs-date-stamp :year 2026.0))       ; integer
  (should-error (jetpacs-progress :value 2))             ; 0..1
  (should-error (jetpacs-empty-state :action-label "Go")) ; both-or-neither
  (should (jetpacs-image "data:image/png;base64,AAAA")))

;;;; The canonical serializer

(ert-deftest jetpacs-widgets/canonical-key-sort ()
  (should (equal (jetpacs-node->canonical-json
                  '(:t "text" :text "hi" :color "primary"))
                 "{\"color\":\"primary\",\"t\":\"text\",\"text\":\"hi\"}")))

(ert-deftest jetpacs-widgets/canonical-nested-sort ()
  "Keys sort independently at every depth."
  (should (equal (jetpacs-node->canonical-json '(:b 1 :a (:z 2 :y 3)))
                 "{\"a\":{\"y\":3,\"z\":2},\"b\":1}")))

(ert-deftest jetpacs-widgets/canonical-booleans ()
  "JSON true/false are elisp t/:json-false, emitted explicitly."
  (should (equal (jetpacs-node->canonical-json '(:t "x" :on t :off :json-false))
                 "{\"off\":false,\"on\":true,\"t\":\"x\"}")))

(ert-deftest jetpacs-widgets/canonical-numbers ()
  "Ints stay ints, floats stay floats (per the caller's elisp type)."
  (should (equal (jetpacs-node->canonical-json '(:big 86400 :f 0.5 :i 5))
                 "{\"big\":86400,\"f\":0.5,\"i\":5}")))

(ert-deftest jetpacs-widgets/canonical-empty-array ()
  (should (equal (jetpacs-node->canonical-json '(:children [] :t "row"))
                 "{\"children\":[],\"t\":\"row\"}")))

(ert-deftest jetpacs-widgets/canonical-vector-of-strings ()
  (should (equal (jetpacs-node->canonical-json (vector "a" "b"))
                 "[\"a\",\"b\"]")))

(ert-deftest jetpacs-widgets/canonical-drops-nil ()
  (should (equal (jetpacs-node->canonical-json '(:a 1 :b nil :c 2))
                 "{\"a\":1,\"c\":2}")))

(ert-deftest jetpacs-widgets/canonical-escapes-strings ()
  "Leaf strings are JSON-escaped."
  (should (equal (jetpacs-node->canonical-json '(:s "a\"b"))
                 "{\"s\":\"a\\\"b\"}")))

(ert-deftest jetpacs-widgets/canonical-round-trips-corpus ()
  "The canonicalizer reproduces EVERY `ebp/goldens/' vector byte-for-byte
from its parsed form -- all 39 node types, the action shapes, and the
hypertext arrays -- independent of the builders.  This validates the one
serializer every future rung depends on before those rungs exist."
  (dolist (name '("widgets" "hypertext"))
    (let ((g (jetpacs-test--golden-map name)))
      (should (> (hash-table-count g) 0))
      (maphash
       (lambda (idx raw)
         (ert-info ((format "%s.golden line %s" name idx))
           (let ((parsed (json-parse-string
                          raw :object-type 'plist :array-type 'array
                          :false-object :json-false :null-object nil)))
             (should (equal (jetpacs-node->canonical-json parsed) raw)))))
       g))))

;;;; The node funnel

(ert-deftest jetpacs-widgets/node-nil-drop ()
  (should (equal (jetpacs--node "text" :text "hi" :color nil :max_lines 2)
                 '(:t "text" :text "hi" :max_lines 2))))

(ert-deftest jetpacs-widgets/node-false-kept ()
  (should (equal (jetpacs--node "chip" :label "x" :selected :json-false)
                 '(:t "chip" :label "x" :selected :json-false))))

(ert-deftest jetpacs-widgets/node-typeless ()
  (should (equal (jetpacs--node nil :builtin "dialog.dismiss")
                 '(:builtin "dialog.dismiss"))))

;;;; Container child helpers

(ert-deftest jetpacs-widgets/children-and-opts-split ()
  (should (equal (jetpacs--children-and-opts
                  '((:t "text" :text "a") (:t "text" :text "b") :spacing 8))
                 '(((:t "text" :text "a") (:t "text" :text "b")) :spacing 8))))

(ert-deftest jetpacs-widgets/as-children-rest-and-list ()
  "&rest children and a single list-of-children agree, and nils drop."
  (let ((a '(:t "text" :text "a")) (b '(:t "text" :text "b")))
    (should (equal (jetpacs--as-children (list a b)) (vector a b)))
    (should (equal (jetpacs--as-children (list (list a b))) (vector a b)))
    (should (equal (jetpacs--as-children (list a nil b)) (vector a b)))
    (should (equal (jetpacs--as-children (list nil)) (vector)))))

;;;; Universal attributes and colors

(ert-deftest jetpacs-widgets/with-attrs ()
  (should (equal (jetpacs-with-attrs '(:t "text" :text "hi")
                                     :key "k1" :padding 4 :bg nil)
                 '(:t "text" :text "hi" :key "k1" :padding 4))))

(ert-deftest jetpacs-widgets/with-attrs-rejects-non-universal ()
  (should-error (jetpacs-with-attrs '(:t "text" :text "hi") :text "no")))

(ert-deftest jetpacs-widgets/color-valid ()
  (should (jetpacs-color-valid-p "primary"))
  (should (jetpacs-color-valid-p "#fff"))
  (should (jetpacs-color-valid-p "#FFAA00"))
  (should (jetpacs-color-valid-p "#12345678"))
  (should-not (jetpacs-color-valid-p "#12"))
  (should-not (jetpacs-color-valid-p "#fffff"))
  (should-not (jetpacs-color-valid-p "reddish"))
  (should-not (jetpacs-color-valid-p 42)))

;;;; Action-descriptor validation (SPEC §14.1)

(ert-deftest jetpacs-widgets/action-requires-dot ()
  (should-error (jetpacs-action "nodot")))

(ert-deftest jetpacs-widgets/action-queue-needs-ttl ()
  (should-error (jetpacs-action "a.b" :when-offline 'queue)))

(ert-deftest jetpacs-widgets/action-wake-needs-ttl ()
  (should-error (jetpacs-action "a.b" :when-offline 'wake)))

(ert-deftest jetpacs-widgets/action-drop-forbids-ttl ()
  (should-error (jetpacs-action "a.b" :ttl-s 5)))

(ert-deftest jetpacs-widgets/action-drop-forbids-dedupe ()
  (should-error (jetpacs-action "a.b" :dedupe "x")))

(ert-deftest jetpacs-widgets/action-drop-explicit-ok ()
  "An explicit `drop' with no ttl/dedupe is valid."
  (should (equal (jetpacs-node->canonical-json
                  (jetpacs-action "a.b" :when-offline 'drop))
                 "{\"action\":\"a.b\",\"when_offline\":\"drop\"}")))

;;;; §4.4 identifier + §14.1 domain validation (build-time strictness)

(ert-deftest jetpacs-widgets/identifier-p ()
  (should (jetpacs--identifier-p "demo.full"))
  (should (jetpacs--identifier-p "manual-sync"))
  (should (jetpacs--identifier-p "demo:full"))
  (should (jetpacs--identifier-p "a/b_c.d"))
  (should (jetpacs--identifier-p "a"))
  (should (jetpacs--identifier-p (make-string 128 ?a)))
  (should-not (jetpacs--identifier-p ".leading"))     ; must begin letter/digit
  (should-not (jetpacs--identifier-p "has space"))
  (should-not (jetpacs--identifier-p "bad!"))
  (should-not (jetpacs--identifier-p (make-string 129 ?a))) ; > 128
  (should-not (jetpacs--identifier-p ""))
  (should-not (jetpacs--identifier-p 42)))

(ert-deftest jetpacs-widgets/action-name-grammar ()
  (should-error (jetpacs-action "nodot"))
  (should-error (jetpacs-action "has space.x"))
  (should-error (jetpacs-action ".leading.dot"))
  (should (jetpacs-action "a.b")))               ; valid namespaced identifier

(ert-deftest jetpacs-widgets/action-ttl-range ()
  "ttl_s must be an integer 1..604800 for queue/wake (SPEC 14.1) — the 0
case is the sharp one (0 is truthy, so a presence-only check let it pass)."
  (should-error (jetpacs-action "a.b" :when-offline 'queue :ttl-s 0))
  (should-error (jetpacs-action "a.b" :when-offline 'queue :ttl-s -5))
  (should-error (jetpacs-action "a.b" :when-offline 'queue :ttl-s 700000))
  (should-error (jetpacs-action "a.b" :when-offline 'queue :ttl-s 3600.0)) ; float
  (should (jetpacs-action "a.b" :when-offline 'queue :ttl-s 1))
  (should (jetpacs-action "a.b" :when-offline 'wake :ttl-s 604800)))

(ert-deftest jetpacs-widgets/action-confirm-nonempty ()
  (should-error (jetpacs-action "a.b" :confirm ""))
  (should (jetpacs-action "a.b" :confirm "Really?")))   ; not an identifier: fine

(ert-deftest jetpacs-widgets/action-dedupe-identifier ()
  (should-error (jetpacs-action "a.b" :when-offline 'queue :ttl-s 5 :dedupe "bad id"))
  (should (jetpacs-action "a.b" :when-offline 'queue :ttl-s 5 :dedupe "demo:full")))

(ert-deftest jetpacs-widgets/action-capture-fields ()
  (should-error (jetpacs-action "a.b" :capture-fields '("a" "a")))   ; not distinct
  (should-error (jetpacs-action "a.b" :capture-fields '("bad!")))    ; not an id
  (should (jetpacs-action "a.b" :capture-fields '("a" "b"))))

;;;; Builtin argument validation

(ert-deftest jetpacs-widgets/builtin-arg-validation ()
  (should-error (jetpacs-view-switch nil))          ; nil would drop → missing member
  (should-error (jetpacs-view-switch "has space"))  ; view is a §4.4 identifier
  (should-error (jetpacs-clipboard-copy nil))       ; text must be a string
  (should-error (jetpacs-trigger-fire "bad!"))      ; id is a §4.4 identifier
  (should-error (jetpacs-share nil))
  (should (jetpacs-view-switch "detail"))
  (should (jetpacs-clipboard-copy ""))              ; empty text is a valid string
  (should (jetpacs-share "x" :title "y")))

;;;; jetpacs-with-attrs: override semantics + value validation

(ert-deftest jetpacs-widgets/with-attrs-overrides ()
  "A re-specified universal attribute REPLACES the existing one (no dup)."
  (should (equal (jetpacs-with-attrs '(:t "text_input" :id "a") :id "b")
                 '(:t "text_input" :id "b"))))

(ert-deftest jetpacs-widgets/with-attrs-validates-values ()
  (should-error (jetpacs-with-attrs '(:t "box") :fill_fraction 2))    ; 0..1
  (should-error (jetpacs-with-attrs '(:t "box") :alpha -1))           ; 0..1
  (should-error (jetpacs-with-attrs '(:t "box") :weight 0))           ; > 0
  (should-error (jetpacs-with-attrs '(:t "box") :aspect_ratio -1))    ; > 0
  (should-error (jetpacs-with-attrs '(:t "box") :padding -1))         ; >= 0
  (should-error (jetpacs-with-attrs '(:t "box") :key "bad!"))         ; §4.4
  (should-error (jetpacs-with-attrs '(:t "box") :align_self "middle"))
  (should-error (jetpacs-with-attrs '(:t "box") :corner '(:bogus 1)))
  (should (jetpacs-with-attrs '(:t "box") :fill_fraction 0.5))
  (should (jetpacs-with-attrs '(:t "box") :corner 4))
  (should (jetpacs-with-attrs '(:t "box") :corner '(:top_start 4)))
  (should (jetpacs-with-attrs '(:t "box") :pad '(:start 2 :vertical 4)))
  (should (jetpacs-with-attrs '(:t "box") :border '(:width 1 :color "outline")))
  (should (jetpacs-with-attrs '(:t "box") :bg "#fff"))
  (should (jetpacs-with-attrs '(:t "box") :bg "primary"))
  (should (jetpacs-with-attrs '(:t "box") :bg "customrole")))         ; unknown role: legal

;;;; Catalog sync with contract.json (the coverage-floor seed)
;;
;; NOTE: these pin the elisp catalogs to `contract.json' (the DERIVED
;; artifact), not to SPEC.md (the authority).  A contract-vs-SPEC drift
;; would not surface here -- e.g. amendment #63 aligned §16.5's table with
;; `contract.json' for `id', which had already diverged.  A SPEC-prose
;; check is future work.

(ert-deftest jetpacs-widgets/catalog-node-types ()
  "The 39-type catalog stays in lockstep with contract.json `node_types'.
When a 40th type appears, this fails -- a reminder to add its constructor."
  (should (equal jetpacs-node-types
                 (alist-get 'node_types (jetpacs-test--contract)))))

(ert-deftest jetpacs-widgets/catalog-core-node-set ()
  (should (equal jetpacs-core-node-set
                 (alist-get 'core_node_set (jetpacs-test--contract)))))

(ert-deftest jetpacs-widgets/catalog-theme-roles ()
  (should (equal jetpacs-theme-roles
                 (alist-get 'theme_roles (jetpacs-test--contract)))))

(ert-deftest jetpacs-widgets/catalog-syntax-roles ()
  (should (equal jetpacs-syntax-roles
                 (alist-get 'syntax_roles (jetpacs-test--contract)))))

(ert-deftest jetpacs-widgets/catalog-universal-attributes ()
  (should (equal jetpacs-universal-attributes
                 (mapcar (lambda (s) (intern (concat ":" s)))
                         (alist-get 'universal_node_attributes
                                    (jetpacs-test--contract))))))

(provide 'jetpacs-widgets-test)
;;; jetpacs-widgets-test.el ends here
