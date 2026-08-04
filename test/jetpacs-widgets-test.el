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
  (should-error (jetpacs-icon 42))                       ; name must be a string
  (should (jetpacs-icon "arrow up"))                     ; non-identifier name ok (amend 64)
  (should-error (jetpacs-image "http://x/a.png"))        ; https/data:image only
  (should-error (jetpacs-date-stamp :day 32))            ; 1..31
  (should-error (jetpacs-date-stamp :year 2026.0))       ; integer
  (should-error (jetpacs-progress :value 2))             ; 0..1
  (should-error (jetpacs-empty-state :action-label "Go")) ; both-or-neither
  (should (jetpacs-image "data:image/png;base64,AAAA")))

(ert-deftest jetpacs-widgets/content-validation-domains ()
  "Post-audit domain tightenings (§17.1 font_weight, §17.2 active image, §4.2 int)."
  ;; font_weight: only normal/bold or a multiple of 100 in 100..900
  (should-error (jetpacs-text "x" :font-weight "medium"))
  (should-error (jetpacs-text "x" :font-weight "Bold"))   ; case-sensitive
  (should-error (jetpacs-text "x" :font-weight 150))       ; not a multiple of 100
  (should-error (jetpacs-span "x" :font-weight 999))
  (should (jetpacs-text "x" :font-weight "normal"))
  (should (jetpacs-text "x" :font-weight 700))
  (should (jetpacs-span "x" :font-weight 100))
  ;; active image format rejected before decode
  (should-error (jetpacs-image "data:image/svg+xml;base64,AAAA"))
  ;; §4.2 integer ceiling
  (should-error (jetpacs-date-stamp :year (1+ 9007199254740991)))
  (should (jetpacs-date-stamp :year 9007199254740991)))

;;;; Byte-parity: Layout-family nodes (widgets.golden 17-34, JW-2)

(ert-deftest jetpacs-widgets/layout-goldens ()
  "Layout-family constructors build byte-identically to widgets.golden 17-34."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "17" (jetpacs-row))
      (chk "18" (jetpacs-row (jetpacs-text "a") :align 'center :arrange 'space_between
                             :fill t :scroll t :spacing 8))
      (chk "19" (jetpacs-column))
      (chk "20" (jetpacs-column (jetpacs-text "a") :align 'start :arrange 'start
                                :fill t :scroll :json-false :spacing 4))
      ;; golden 21's child is a chip (an input node, JW-3) — use a literal plist
      (chk "21" (jetpacs-flow-row '(:t "chip" :label "a") :align 'top :arrange 'start
                                  :run-spacing 2 :spacing 4))
      (chk "22" (jetpacs-box (jetpacs-text "a") :alignment 'center
                             :on-tap (jetpacs-action "demo.tap")))
      (chk "23" (jetpacs-surface (jetpacs-text "a") :color "surface" :elevation 2
                                 :shape 'rounded))
      (chk "24" (jetpacs-lazy-column (jetpacs-text "a") :content-padding 8 :spacing 4))
      (chk "25" (jetpacs-spacer))
      (chk "26" (jetpacs-with-attrs (jetpacs-spacer) :height 8 :weight 1 :width 8))
      (chk "27" (jetpacs-divider))
      (chk "28" (jetpacs-divider :color "outline" :thickness 1))
      (chk "29" (jetpacs-card (jetpacs-text "a")))
      (chk "30" (jetpacs-card (jetpacs-text "a")
                              :on-tap (jetpacs-action "demo.tap")
                              :on-long-tap (jetpacs-action "demo.long")
                              :swipe-start (jetpacs-swipe "Done"
                                            :on-trigger (jetpacs-action "demo.done"))
                              :swipe-end (jetpacs-swipe "Delete" :icon "delete"
                                          :color "error"
                                          :on-trigger (jetpacs-action "demo.delete"))))
      (chk "31" (jetpacs-collapsible "sec1" (jetpacs-text "Section") (jetpacs-text "body")
                                     :collapsed t
                                     :on-long-tap (jetpacs-action "demo.long")
                                     :swipe-start (jetpacs-swipe "Archive"
                                                   :on-trigger (jetpacs-action "demo.archive"))))
      (chk "32" (jetpacs-reorderable-list
                 (list (jetpacs-with-attrs (jetpacs-text "a") :key "ka")
                       (jetpacs-with-attrs (jetpacs-text "b") :id "kb"))
                 :on-reorder (jetpacs-action "demo.reorder")))
      (chk "33" (jetpacs-tabs
                 (list (jetpacs-tab-item "One") (jetpacs-tab-item "Two" :icon "star"))
                 (list (jetpacs-text "1") (jetpacs-text "2"))
                 :id "tabs1" :initial 1 :on-change (jetpacs-action "demo.tab")
                 :pager-only :json-false :scrollable t))
      (chk "34" (jetpacs-table
                 (list (jetpacs-table-row 'header (jetpacs-table-cell (list (jetpacs-span "H"))))
                       (jetpacs-table-row 'data (jetpacs-table-cell (list (jetpacs-span "v"))
                                                 :on-tap (jetpacs-action "cell.tap")))
                       (jetpacs-table-rule))
                 :aligns '("start" "center")
                 :on-add-col (jetpacs-action "col.add")
                 :on-add-row (jetpacs-action "row.add"))))))

(ert-deftest jetpacs-widgets/layout-validation ()
  "Layout constructors enforce their §17.3 invariants."
  (should-error (jetpacs-row (jetpacs-text "a") :align 'bogus))      ; align enum
  (should-error (jetpacs-row (jetpacs-text "a") :arrange 'nope))     ; arrange enum
  (should-error (jetpacs-row (jetpacs-text "a") :scroll 1))          ; bool t/:json-false
  (should-error (jetpacs-box (jetpacs-text "a") :alignment 'middle)) ; box alignment enum
  (should-error (jetpacs-surface (jetpacs-text "a") :shape 'blob))   ; shape enum
  ;; reorderable_list: every item needs a unique key/id
  (should-error (jetpacs-reorderable-list (list (jetpacs-text "a"))))
  (should-error (jetpacs-reorderable-list
                 (list (jetpacs-with-attrs (jetpacs-text "a") :key "k")
                       (jetpacs-with-attrs (jetpacs-text "b") :key "k"))))
  ;; tabs: equal non-zero length; initial < count
  (should-error (jetpacs-tabs (list (jetpacs-tab-item "A"))
                              (list (jetpacs-text "1") (jetpacs-text "2"))))
  (should-error (jetpacs-tabs '() '()))
  (should-error (jetpacs-tabs (list (jetpacs-tab-item "A")) (list (jetpacs-text "1"))
                              :initial 1))
  ;; table row kind + collapsible header
  (should-error (jetpacs-table-row 'footer (jetpacs-table-cell (list (jetpacs-span "x")))))
  (should-error (jetpacs-collapsible "s" "not-a-node")))

(ert-deftest jetpacs-widgets/descriptor-validation ()
  "Post-audit: on_* / on_trigger / swipe fields are validated (§17.1, §17.3)."
  ;; swipe on_trigger is required (§17.3 {icon?, label, color?, on_trigger})
  (should-error (jetpacs-swipe "Done"))
  (should (jetpacs-swipe "Done" :on-trigger (jetpacs-action "demo.done")))
  ;; on_* must be an action/builtin descriptor, exactly one discriminator
  (should-error (jetpacs-box (jetpacs-text "a") :on-tap "not-a-descriptor"))
  (should-error (jetpacs-box (jetpacs-text "a") :on-tap '(:action "x" :builtin "y")))
  (should-error (jetpacs-tabs (list (jetpacs-tab-item "A")) (list (jetpacs-text "1"))
                              :on-change '(:foo 1)))
  (should-error (jetpacs-span "x" :on-tap "nope"))
  (should (jetpacs-box (jetpacs-text "a") :on-tap (jetpacs-view-switch "detail")))
  ;; swipe_start/swipe_end must be swipe sides (label + on_trigger)
  (should-error (jetpacs-card (jetpacs-text "a") :swipe-start '(:label "x")))
  (should (jetpacs-card (jetpacs-text "a")
                        :swipe-start (jetpacs-swipe "x" :on-trigger (jetpacs-action "a.b")))))

(ert-deftest jetpacs-widgets/layout-negative-dp ()
  "Negative dp values are rejected (§17.3)."
  (should-error (jetpacs-surface (jetpacs-text "a") :elevation -1))
  (should-error (jetpacs-lazy-column (jetpacs-text "a") :spacing -1))
  (should-error (jetpacs-divider :thickness -1))
  (should-error (jetpacs-flow-row (jetpacs-text "a") :run-spacing -1)))

;;;; Byte-parity: Input-family nodes (widgets.golden 35-44, 48-55, JW-3)

(ert-deftest jetpacs-widgets/input-goldens ()
  "Input-family constructors build byte-identically (editor 45-47 is JW-4)."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "35" (jetpacs-button "OK" (jetpacs-action "demo.tap")))
      (chk "36" (jetpacs-button "OK" (jetpacs-action "demo.tap")
                                :enabled :json-false :icon "check" :variant 'tonal))
      (chk "37" (jetpacs-icon-button "menu" (jetpacs-action "demo.tap")
                                     :badge "2" :content-description "Open menu"))
      (chk "38" (jetpacs-chip "Tag"))
      (chk "39" (jetpacs-chip "Tag" :enabled t :icon "tag"
                              :on-tap (jetpacs-action "demo.tap") :selected t))
      (chk "40" (jetpacs-assist-chip "Help" :icon "info"
                                     :on-tap (jetpacs-action "demo.tap")))
      (chk "41" (jetpacs-menu
                 (list (jetpacs-menu-item "Open" (jetpacs-action "demo.tap"))
                       (jetpacs-menu-item "Delete" (jetpacs-action "demo.delete")
                                          :enabled :json-false :icon "delete"))
                 :icon "more"))
      (chk "42" (jetpacs-text-input "title"))
      (chk "43" (jetpacs-text-input "title"
                                    :autofocus t :clear-on-submit t :enabled t
                                    :hint "Title" :keyboard 'text :label "Title"
                                    :max-lines 1 :min-lines 1 :monospace :json-false
                                    :on-change (jetpacs-action "title.change")
                                    :on-submit (jetpacs-action "title.submit")
                                    :single-line t :syntax "org" :value "draft"))
      (chk "44" (jetpacs-text-input "pw" :password t
                                    :on-submit (jetpacs-action "auth.submit"
                                                :capture-fields '("pw"))))
      (chk "48" (jetpacs-checkbox "done" :checked t :enabled t :label "Done"
                                  :on-change (jetpacs-action "todo.toggle")))
      (chk "49" (jetpacs-switch "dark" :checked :json-false :label "Dark"
                                :on-change (jetpacs-action "theme.toggle")))
      (chk "50" (jetpacs-enum-list "state"
                                   (list (jetpacs-enum-option "Todo" "TODO")
                                         (jetpacs-enum-option "Done" "DONE"))
                                   :on-change (jetpacs-action "state.set") :value "TODO"))
      (chk "51" (jetpacs-enum-list "tags"
                                   (list (jetpacs-enum-option "Work" "work")
                                         (jetpacs-enum-option "Home" "home"))
                                   :allow-add t :multi-select t
                                   :on-change (jetpacs-action "tags.set")
                                   :value '("work" "home")))
      (chk "52" (jetpacs-date-button "Due" (jetpacs-action "due.pick")
                                     :value "2026-07-22"))
      (chk "53" (jetpacs-time-button "At" (jetpacs-action "at.pick") :value "09:30"))
      (chk "54" (jetpacs-slider "vol" (jetpacs-action "vol.set")
                                :max 10 :min 0 :value 5))
      (chk "55" (jetpacs-slider "zoom" (jetpacs-action "zoom.set")
                                :value 2 :values '(1 2 4))))))

(ert-deftest jetpacs-widgets/input-validation ()
  "Input constructors enforce their §17.4 rules."
  (should-error (jetpacs-button "x" "not-a-descriptor"))       ; on_tap descriptor
  (should-error (jetpacs-button "x" (jetpacs-action "a.b") :variant 'ghost)) ; variant enum
  (should-error (jetpacs-icon-button "bad!" (jetpacs-action "a.b")))         ; icon id
  ;; text_input line counts + single_line + password
  (should-error (jetpacs-text-input "i" :min-lines 3 :max-lines 2))
  (should-error (jetpacs-text-input "i" :single-line t :max-lines 2))
  (should-error (jetpacs-text-input "i" :single-line t :value "a\nb"))
  (should-error (jetpacs-text-input "i" :password t :value "secret"))
  (should-error (jetpacs-text-input "i" :password t :on-change (jetpacs-action "a.b")))
  (should-error (jetpacs-text-input "i" :keyboard 'braille))
  ;; enum_list distinct + value-in-options
  (should-error (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" "x")
                                             (jetpacs-enum-option "B" "x"))))
  (should-error (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" "x"))
                                   :value "y"))
  (should (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" "x"))
                             :allow-add t :value "y"))            ; allow_add bypasses
  ;; slider continuous vs discrete
  (should-error (jetpacs-slider "s" (jetpacs-action "a.b") :min 5 :max 5))   ; min<max
  (should-error (jetpacs-slider "s" (jetpacs-action "a.b") :value 9 :max 5)) ; in range
  (should-error (jetpacs-slider "s" (jetpacs-action "a.b") :values '(1 1 2))) ; strictly inc
  (should-error (jetpacs-slider "s" (jetpacs-action "a.b") :values '(1 2) :min 0)) ; discrete omits min
  (should-error (jetpacs-slider "s" (jetpacs-action "a.b") :values '(1 2 4) :value 3)) ; value listed
  ;; date/time formats + range
  (should-error (jetpacs-date-button "D" (jetpacs-action "a.b") :value "2026/07/22"))
  (should-error (jetpacs-time-button "T" (jetpacs-action "a.b") :value "9:30"))
  (should-error (jetpacs-date-button "D" (jetpacs-action "a.b") :value "2026-13-40"))
  (should-error (jetpacs-time-button "T" (jetpacs-action "a.b") :value "25:61")))

(ert-deftest jetpacs-widgets/input-json-equality ()
  "Post-audit: §4.3 numeric equality (1 == 1.0) in enum/slider value checks."
  ;; slider discrete: a float value matching an int-listed number is accepted
  (should (jetpacs-slider "s" (jetpacs-action "a.b") :values '(1 2 4) :value 2.0))
  (should (jetpacs-slider "s" (jetpacs-action "a.b") :values '(0.5 1.0 1.5) :value 1))
  ;; enum value-in-options under §4.3
  (should (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" 1.0)) :value 1))
  ;; option distinctness under §4.3: 1 and 1.0 are NOT distinct
  (should-error (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" 1)
                                             (jetpacs-enum-option "B" 1.0))))
  ;; multi-select: distinct value elements; a bare scalar is rejected
  (should-error (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" "a"))
                                   :allow-add t :multi-select t :value '("a" "a")))
  (should-error (jetpacs-enum-list "e" (list (jetpacs-enum-option "A" "a"))
                                   :multi-select t :value "a")))

;;;; Byte-parity: editor + toolbar (widgets.golden 45-47, JW-4)

(ert-deftest jetpacs-widgets/editor-goldens ()
  "Editor + toolbar constructors build byte-identically to widgets.golden 45-47."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "45" (jetpacs-editor "body"))
      (chk "46" (jetpacs-editor "body"
                                :autofocus :json-false :chromeless :json-false
                                :line-numbers t
                                :on-enter (jetpacs-action "note.enter")
                                :on-save (jetpacs-action "note.save")
                                :publish-state t :read-only :json-false :syntax "org"
                                :toolbar (list
                                          (jetpacs-toolbar-item :label "TODO"
                                                                :placement 'line-start
                                                                :snippet "TODO ")
                                          (jetpacs-toolbar-item
                                           :icon "menu"
                                           :menu (list (jetpacs-toolbar-item
                                                        :label "Date" :snippet "${date}"))))
                                :value "local text"))
      (chk "47" (jetpacs-editor "doc" :complete t :document "doc:notes/123"
                                :toolbar (list (jetpacs-toolbar-item
                                                :command "org-refile" :icon "refile")))))))

(ert-deftest jetpacs-widgets/editor-validation ()
  "Editor + toolbar enforce their §17.4/§17.7 rules."
  ;; complete requires document
  (should-error (jetpacs-editor "e" :complete t))
  (should (jetpacs-editor "e" :complete t :document "doc:x"))
  ;; a toolbar command op requires document
  (should-error (jetpacs-editor "e" :toolbar (list (jetpacs-toolbar-item
                                                    :command "cmd" :icon "i"))))
  (should (jetpacs-editor "e" :document "doc:x"
                          :toolbar (list (jetpacs-toolbar-item :command "cmd" :icon "i"))))
  ;; toolbar-item: label or icon required; exactly one primary op
  (should-error (jetpacs-toolbar-item :snippet "x"))                 ; no label/icon
  (should-error (jetpacs-toolbar-item :label "L"))                   ; zero ops
  (should-error (jetpacs-toolbar-item :label "L" :snippet "x" :line 'promote)) ; two ops
  (should-error (jetpacs-toolbar-item :label "L" :line 'bogus))      ; line enum
  ;; menu items must be non-menu
  (should-error (jetpacs-toolbar-item
                 :icon "m"
                 :menu (list (jetpacs-toolbar-item :icon "n"
                              :menu (list (jetpacs-toolbar-item :label "x" :snippet "y"))))))
  ;; snippet: at most one ${input:...}, respecting the $$ escape
  (should-error (jetpacs-toolbar-item :label "L"
                                      :snippet "${input:A} ${input:B}"))
  (should (jetpacs-toolbar-item :label "L" :snippet "$${input:A} ${input:B}"))
  (should (jetpacs-toolbar-item :label "L" :snippet "${input:Prompt}")))

(ert-deftest jetpacs-widgets/editor-audit-fixes ()
  "Post-audit: nested command->document, long_press value, snippet scan."
  ;; command nested in a menu still requires document
  (should-error (jetpacs-editor "e" :toolbar
                                (list (jetpacs-toolbar-item
                                       :icon "m"
                                       :menu (list (jetpacs-toolbar-item
                                                    :command "cmd" :icon "i"))))))
  (should (jetpacs-editor "e" :document "doc:x" :toolbar
                          (list (jetpacs-toolbar-item
                                 :icon "m"
                                 :menu (list (jetpacs-toolbar-item
                                              :command "cmd" :icon "i"))))))
  ;; command in a long_press also requires document
  (should-error (jetpacs-editor "e" :toolbar
                                (list (jetpacs-toolbar-item
                                       :label "L" :snippet "x"
                                       :long-press '(:command "cmd")))))
  ;; long_press op VALUE is validated (snippet with two input tokens)
  (should-error (jetpacs-toolbar-item :label "L" :snippet "a"
                                      :long-press '(:snippet "${input:A}${input:B}")))
  (should (jetpacs-toolbar-item :label "L" :snippet "a"
                                :long-press '(:command "org-refile")))
  ;; snippet: a ${input:} inside another token's prompt body is not double-counted
  (should (jetpacs-toolbar-item :label "L" :snippet "${input:pre ${input:X}}"))
  ;; only the 3-char $${ escapes; $$${input:X} then a real token = one token
  (should (jetpacs-toolbar-item :label "L" :snippet "$$${input:X}${input:Y}")))

;;;; Byte-parity: Visualization nodes (widgets.golden 56-58, JW-5)

(ert-deftest jetpacs-widgets/viz-goldens ()
  "Visualization constructors build byte-identically to widgets.golden 56-58."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "56" (jetpacs-chart
                 (list (jetpacs-chart-series
                        (list (jetpacs-chart-point 0 1)
                              (jetpacs-chart-point 1 3 :meta '(:n "b")))
                        :color "primary" :name "steps"))
                 :height 120 :kind 'bar :on-point-tap (jetpacs-action "point.tap")
                 :summary "Steps rose from 1 to 3" :y-range '(0 10)))
      (chk "57" (jetpacs-canvas
                 100 50
                 (list (jetpacs-canvas-line 0 0 100 50 :color "#333333" :width 2)
                       (jetpacs-canvas-rect 5 5 20 10 :color "outline"
                                            :fill "#eeeeee" :stroke-width 1)
                       (jetpacs-canvas-circle 50 25 10 :color "primary")
                       (jetpacs-canvas-path
                        (list (jetpacs-canvas-point 0 0) (jetpacs-canvas-point 10 10))
                        :closed :json-false :color "#000000")
                       (jetpacs-canvas-text 10 40 "label" :size 12))
                 :children (list (jetpacs-text "fallback"))))
      (chk "58" (jetpacs-month-grid
                 "2026-07"
                 :marks (list (cons "2026-07-04" (jetpacs-month-mark 2 :color "primary")))
                 :max-month "2026-12" :min-month "2026-01"
                 :on-day-tap (jetpacs-action "day.tap")
                 :on-month-change (jetpacs-action "month.nav")
                 :selected "2026-07-22")))))

(ert-deftest jetpacs-widgets/viz-validation ()
  "Visualization constructors enforce their §17.5 rules."
  (should-error (jetpacs-chart-point "x" 1))                  ; x finite number
  (should-error (jetpacs-chart (list) :height -1))            ; height positive
  (should-error (jetpacs-chart (list) :y-range '(10 0)))      ; min < max
  (should-error (jetpacs-chart (list) :kind 'pie))            ; kind enum
  (should-error (jetpacs-canvas 0 50 (list)))                 ; width positive
  (should-error (jetpacs-canvas-rect 0 0 -1 5))               ; width non-negative
  (should-error (jetpacs-canvas-circle 0 0 5 :fill "#12"))     ; fill is a Color (bad hex)
  (should-error (jetpacs-month-mark 4))                       ; dots 0..3
  (should-error (jetpacs-month-grid "2026-13"))               ; YYYY-MM month range
  (should-error (jetpacs-month-grid "2026-07" :min-month "2026-12" :max-month "2026-01"))
  (should-error (jetpacs-month-grid
                 "2026-07"
                 :marks (list (cons "bad-date" (jetpacs-month-mark 1)))))
  ;; a raw mark value bypassing jetpacs-month-mark is still validated (post-audit)
  (should-error (jetpacs-month-grid "2026-07"
                                    :marks (list (cons "2026-07-04" '(:dots 99)))))
  (should-error (jetpacs-month-grid "2026-07"
                                    :marks (list (cons "2026-07-04" '(:bogus 1)))))
  ;; chart point meta must be an object (post-audit)
  (should-error (jetpacs-chart-point 0 1 :meta 5)))

(ert-deftest jetpacs-widgets/month-grid-marks-order ()
  "Multiple marks serialize with keys sorted (string<), matching json.dumps."
  (should (equal
           (jetpacs-node->canonical-json
            (jetpacs-month-grid "2026-07"
                                :marks (list (cons "2026-07-20" (jetpacs-month-mark 1))
                                             (cons "2026-07-04" (jetpacs-month-mark 2)))))
           "{\"marks\":{\"2026-07-04\":{\"dots\":2},\"2026-07-20\":{\"dots\":1}},\"month\":\"2026-07\",\"t\":\"month_grid\"}")))

;;;; Byte-parity: scaffold (widgets.golden 59-60) + SurfaceSpec shapes (JW-6)

(ert-deftest jetpacs-widgets/scaffold-goldens ()
  "Scaffold builds byte-identically to widgets.golden 59-60."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "59" (jetpacs-scaffold))
      (chk "60" (jetpacs-scaffold
                 :body (jetpacs-column) :bottom-bar (jetpacs-row)
                 :drawer (jetpacs-column)
                 :fab (jetpacs-icon-button "add" (jetpacs-action "demo.tap"))
                 :floating-toolbar (jetpacs-row)
                 :on-refresh (jetpacs-action "app.refresh")
                 :snackbar "Saved"
                 :snackbar-action (jetpacs-snackbar-action
                                   "Undo" (jetpacs-action "demo.undo"))
                 :top-bar (jetpacs-text "App"))))))

(ert-deftest jetpacs-widgets/surface-shapes ()
  "§13.4 SurfaceSpec wrappers serialize to the documented shapes."
  ;; app multi-view: {views (id-keyed, sorted), initial_view}
  (should (equal
           (jetpacs-node->canonical-json
            (jetpacs-multi-view (list (cons "list" (jetpacs-column))
                                      (cons "detail" (jetpacs-column)))
                                "list"))
           "{\"initial_view\":\"list\",\"views\":{\"detail\":{\"children\":[],\"t\":\"column\"},\"list\":{\"children\":[],\"t\":\"column\"}}}"))
  ;; notification: {body, meta?}
  (should (equal (jetpacs-node->canonical-json
                  (jetpacs-notification-surface (jetpacs-text "hi")))
                 "{\"body\":{\"t\":\"text\",\"text\":\"hi\"}}"))
  ;; widget: {title, body, empty?, header_action?}
  (should (equal (jetpacs-node->canonical-json
                  (jetpacs-widget-surface "Title" (jetpacs-text "hi")))
                 "{\"body\":{\"t\":\"text\",\"text\":\"hi\"},\"title\":\"Title\"}")))

(ert-deftest jetpacs-widgets/scaffold-surface-validation ()
  "Scaffold + SurfaceSpec wrappers enforce their rules."
  (should-error (jetpacs-scaffold :body "not-a-node"))
  (should-error (jetpacs-snackbar-action "Undo" "not-a-descriptor"))
  ;; multi-view: non-empty, identifier ids, initial_view must exist
  (should-error (jetpacs-multi-view '() "x"))
  (should-error (jetpacs-multi-view (list (cons "bad id" (jetpacs-column))) "bad id"))
  (should-error (jetpacs-multi-view (list (cons "list" (jetpacs-column))) "detail"))
  (should-error (jetpacs-widget-surface "T" "not-a-node"))
  (should-error (jetpacs-notification-surface "not-a-node"))
  ;; post-audit: snackbar_action shape validated
  (should-error (jetpacs-scaffold :snackbar-action "not-an-object"))
  (should-error (jetpacs-scaffold :snackbar-action '(:label "x")))   ; missing on_tap
  ;; post-audit: envelope slots require a ROOT node (:t), not a :t-less sub-spec
  (should-error (jetpacs-scaffold :body (jetpacs-action "a.b")))
  (should-error (jetpacs-multi-view (list (cons "v" (jetpacs-action "a.b"))) "v"))
  (should-error (jetpacs-widget-surface "T" (jetpacs-snackbar-action
                                             "x" (jetpacs-action "a.b")))))

;;;; Byte-parity: hypertext block sequences (hypertext.golden 00-03, JW-7)

(ert-deftest jetpacs-widgets/hypertext-goldens ()
  "Hypertext block sequences build byte-identically to hypertext.golden."
  (let ((g (jetpacs-test--golden-map "hypertext")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "hypertext.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "00" (jetpacs-hypertext
                 (jetpacs-section-header "Note")
                 (jetpacs-text "Body paragraph.")
                 (jetpacs-divider)
                 (jetpacs-text "Footer" :style 'caption)))
      (chk "01" (jetpacs-hypertext
                 (jetpacs-table
                  (list (jetpacs-table-row 'header
                                           (jetpacs-table-cell (list (jetpacs-span "Task")))
                                           (jetpacs-table-cell (list (jetpacs-span "State"))))
                        (jetpacs-table-row 'data
                                           (jetpacs-table-cell (list (jetpacs-span "Write spec")))
                                           (jetpacs-table-cell (list (jetpacs-span "DONE" :font-weight "bold"))))))))
      (chk "02" (jetpacs-hypertext
                 (jetpacs-column
                  (jetpacs-card (jetpacs-text "Agenda item")
                                :on-tap (jetpacs-action "agenda.open"))
                  :spacing 8)))
      (chk "03" (jetpacs-hypertext
                 (jetpacs-rich-text
                  (list (jetpacs-span "Mixed ")
                        (jetpacs-span "styles" :italic t)
                        (jetpacs-span " inline" :mono t))))))))

(ert-deftest jetpacs-widgets/profile-gating ()
  "jetpacs-check-profile / -node-types gate emitted types to the target (§16.2)."
  ;; reference set sizes + exact membership (app == the 52 node types)
  (should (= (length jetpacs-app-node-types) 52))
  (should (= (length jetpacs-dialog-node-types) 34))
  (should (= (length jetpacs-notification-node-types) 6))
  (should (equal (sort (copy-sequence jetpacs-app-node-types) #'string<)
                 (sort (copy-sequence jetpacs-node-types) #'string<)))
  ;; post-audit: a data key named "t" inside opaque args/meta is NOT a node type
  (should (jetpacs-check-profile
           (jetpacs-button "Go" (jetpacs-action "foo.bar" :args '(:t "note"))) 'app))
  (should (jetpacs-check-profile
           (jetpacs-chart (list (jetpacs-chart-series
                                 (list (jetpacs-chart-point 0 5 :meta '(:t 123))))))
           'app))
  ;; post-audit: a bare list of nodes is scanned (not silently skipped)
  (should-error (jetpacs-check-profile
                 (list (jetpacs-text "x") (jetpacs-chart nil)) 'notification))
  ;; notification (6) forbids chart/button/text_input; allows core layout+text
  (should (jetpacs-check-profile (jetpacs-column (jetpacs-text "x")) 'notification))
  (should-error (jetpacs-check-profile (jetpacs-chart nil) 'notification))
  (should-error (jetpacs-check-profile (jetpacs-button "x" (jetpacs-action "a.b"))
                                       'notification))
  ;; dialog (27) forbids scaffold/layout/viz.  `editor' IS advertised:
  ;; JC-4b added it to the Companion's DIALOG_NODE_TYPES so a dialog could
  ;; host the capf picker, and this reference constant lagged that change
  ;; until the app-tier verdict pass caught the drift (B14).  The picker
  ;; still worked on device because the runtime SPEC 16.2 gate reads the
  ;; LIVE welcome; only this reference union disagreed — which is exactly
  ;; the class of drift a pin test exists to catch, so it now pins the
  ;; agreeing direction.
  (should (jetpacs-check-profile (jetpacs-editor "e" :document "doc:x") 'dialog))
  (should-error (jetpacs-check-profile (jetpacs-tabs (list (jetpacs-tab-item "A"))
                                                     (list (jetpacs-text "1")))
                                       'dialog))
  (should (jetpacs-check-profile (jetpacs-checkbox "c") 'dialog))
  ;; app (39) allows everything, incl. nested
  (should (jetpacs-check-profile (jetpacs-scaffold :body (jetpacs-chart nil)) 'app))
  ;; the scan is RECURSIVE: a chart nested in a notification tree is caught
  (should-error (jetpacs-check-profile
                 (jetpacs-column (jetpacs-chart nil)) 'notification))
  ;; generic guard against an arbitrary advertised set
  (should-error (jetpacs-check-node-types (jetpacs-text "x") '("row" "column")))
  (should (jetpacs-check-node-types (jetpacs-row (jetpacs-text "x"))
                                    '("row" "text"))))

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
  "The 44-type catalog stays in lockstep with contract.json `node_types'.
When a 45th type appears, this fails -- a reminder to add its constructor."
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

(ert-deftest jetpacs-widgets/catalog-node-schema ()
  "The GENERATED `jetpacs-node-schema' still matches the contract.
The drift half of the tools/gen-jetpacs-vocabulary.py pattern: when this
fails the contract moved, so REGENERATE rather than editing
emacs/jetpacs-vocabulary.el by hand."
  (let* ((contract (jetpacs-test--contract))
         (schema (alist-get 'node_schema contract))
         (expected
          (mapcar (lambda (type)
                    (let ((row (alist-get (intern type) schema)))
                      (list type
                            (sort (copy-sequence (alist-get 'required row))
                                  #'string<)
                            (sort (copy-sequence (alist-get 'optional row))
                                  #'string<))))
                  (alist-get 'node_types contract))))
    (should (equal jetpacs-node-schema expected))))

;;;; Container trailing options (checked against the generated schema)

(defun jetpacs-test--error-message (thunk)
  "The error message THUNK signals, or nil when it returns."
  (condition-case err (progn (funcall thunk) nil)
    (error (error-message-string err))))

(ert-deftest jetpacs-widgets/container-rejects-an-unknown-option ()
  "A misspelled trailing option signals instead of vanishing.
The containers read their options with `plist-get', so before this
`:spacng' was silently dropped and the row rendered with no spacing."
  (let ((msg (jetpacs-test--error-message
              (lambda () (jetpacs-row (jetpacs-text "a") :spacng 8)))))
    (should msg)
    (should (string-match-p "not a member of" msg))
    ;; The message lists what IS allowed, or fixing a typo means going
    ;; to read the contract.
    (should (string-match-p "spacing" msg))))

(ert-deftest jetpacs-widgets/container-rejects-a-universal-attribute ()
  "A §16.5 attribute passed as a trailing option names its real home.
`(jetpacs-row … :padding 8)' is the mistake authors actually make: it
type-checked, serialized, and emitted a row with no padding."
  (let ((msg (jetpacs-test--error-message
              (lambda () (jetpacs-row (jetpacs-text "a") :padding 8)))))
    (should msg)
    (should (string-match-p "universal attribute" msg))
    (should (string-match-p "jetpacs-with-attrs" msg)))
  ;; …including the hyphenated spelling of a wire-spelled attribute.
  (should (jetpacs-test--error-message
           (lambda () (jetpacs-column (jetpacs-text "a") :min-width 8))))
  ;; The same attribute stays legal where it belongs.
  (should (jetpacs-with-attrs (jetpacs-row (jetpacs-text "a")) :padding 8)))

(ert-deftest jetpacs-widgets/container-options-cover-every-container ()
  "Every `&rest'-children container checks against its own node type."
  (dolist (case '((jetpacs-row . "row")
                  (jetpacs-column . "column")
                  (jetpacs-flow-row . "flow_row")
                  (jetpacs-box . "box")
                  (jetpacs-surface . "surface")
                  (jetpacs-lazy-column . "lazy_column")
                  (jetpacs-card . "card")))
    (let ((msg (jetpacs-test--error-message
                (lambda () (funcall (car case) (jetpacs-text "a") :nope 1)))))
      (should msg)
      (should (string-match-p (regexp-quote (cdr case)) msg))))
  ;; collapsible takes id and header positionally, before its children.
  (should (jetpacs-test--error-message
           (lambda ()
             (jetpacs-collapsible "i" (jetpacs-text "h")
                                  (jetpacs-text "a") :nope 1)))))

(ert-deftest jetpacs-widgets/container-takes-a-list-of-children ()
  "The computed-children form is supported alongside trailing options.
Undocumented until now, which is why callers reached for
`(apply #\\='jetpacs-row (append … (list :spacing 8)))' instead."
  (should (equal (jetpacs-node->canonical-json
                  (jetpacs-row (list (jetpacs-text "a") (jetpacs-text "b"))
                               :spacing 8))
                 (jetpacs-node->canonical-json
                  (jetpacs-row (jetpacs-text "a") (jetpacs-text "b")
                               :spacing 8)))))

;;;; The wire-id minter (JA-2/B5)

(ert-deftest jetpacs-widgets/wire-id-valid-for-hostile-names ()
  (dolist (name '("*shell*" "*ielm*" "*Async Shell Command*" "shell<2>"
                  " *hidden*" "«weird»" "/ssh:host:/e/x.el" ""))
    (let ((id (jetpacs-wire-id "files" name)))
      (should (jetpacs--identifier-p id))
      (should (<= (length id) 128)))))

(ert-deftest jetpacs-widgets/wire-id-golden-and-comint-compatible ()
  "Byte-compatibility with the pre-promotion comint minter: live SPEC
13.6 drafts key on these exact ids."
  (should (equal (jetpacs-wire-id "comint" "*shell*")
                 (concat "comint-c-shell--"
                         (substring (sha1 "*shell*") 0 8))))
  (require (quote jetpacs-comint))
  (should (equal (jetpacs-comint--input-id "*shell*")
                 (jetpacs-wire-id "comint" "*shell*")))
  ;; The plan's exit-gate name class round-trips.
  (let ((id (jetpacs-wire-id "witheditor" "*shell /ssh:host:*")))
    (should (string-prefix-p "witheditor-c-shell-/ssh:host:-" id))
    (should (string-suffix-p (substring (sha1 "*shell /ssh:host:*") 0 8)
                             id))))

(ert-deftest jetpacs-widgets/wire-id-collisions-and-stability ()
  ;; Sanitize-lossiness kept apart by the hash of the ORIGINAL.
  (should-not (equal (jetpacs-wire-id "x" "*shell*")
                     (jetpacs-wire-id "x" "-shell-")))
  (should (equal (jetpacs-wire-id "x" "*shell*")
                 (jetpacs-wire-id "x" "*shell*")))
  (should-not (equal (jetpacs-wire-id "files" "n")
                     (jetpacs-wire-id "hosts" "n"))))

(ert-deftest jetpacs-widgets/wire-id-ceiling-and-bad-prefix ()
  (should (jetpacs--identifier-p
           (jetpacs-wire-id "witheditor" (make-string 400 ?*))))
  (should-error (jetpacs-wire-id "has space" "n"))
  (should-error (jetpacs-wire-id (make-string 101 ?p) "n"))
  (should-error (jetpacs-wire-id "p" 42)))

(provide 'jetpacs-widgets-test)
;;; jetpacs-widgets-test.el ends here
