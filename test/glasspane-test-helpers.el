;;; glasspane-test-helpers.el --- Shared utilities for tests
;;; Code:
(require 'ert)

;;; glasspane-tests.el --- ERT suite for the Glasspane app -*- lexical-binding: t; -*-

;; Run from the repo root (any Emacs 28+), with the jetpacs submodule checked out:
;;   git submodule update --init
;;   emacs -Q --batch -l test/glasspane-tests.el -f ert-run-tests-batch-and-exit
;;
;; The Jetpacs core this app builds on comes from the `jetpacs' git submodule
;; (emacs/core there); this repo carries only the Glasspane Tier-1 sources.

;;; Code:

(defvar jetpacs-tests--dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this test file.")

;; Core from the jetpacs submodule; the app sources from this repo.
(dolist (dir '("../jetpacs/emacs/core" "../emacs/apps" "../emacs/apps/glasspane"))
  (add-to-list 'load-path (expand-file-name dir jetpacs-tests--dir)))

(require 'ert)

(require 'cl-lib)

(require 'jetpacs)

(require 'jetpacs-triggers)

(require 'jetpacs-device)

(require 'jetpacs-apps)

(require 'jetpacs-widgets)

(require 'jetpacs-lint)

(require 'jetpacs-shell)

(require 'glasspane-org)

(require 'glasspane-source)

(require 'jetpacs-keymap)

(require 'jetpacs-magit)

(require 'jetpacs-ghostel)

(require 'jetpacs-files)

(require 'jetpacs-minibuffer)

(require 'glasspane-ui)
(require 'glasspane-agenda)
(require 'glasspane-capture)
(require 'glasspane-detail)
(require 'glasspane-search)
(require 'glasspane-table)
(require 'jetpacs-emacs-ui)

(require 'jetpacs-complete)

(require 'jetpacs-sync)

(require 'glasspane-demo)

(require 'glasspane-gallery)

(require 'glasspane-config)

(require 'glasspane-journal)

(require 'glasspane-views)

(require 'glasspane-automations)

(require 'glasspane-notes)

(require 'glasspane-srs)

(defmacro jetpacs-tests--with-search-fixture (&rest body)
  "Run BODY with a temp org agenda file of known headings."
  `(let ((file (make-temp-file "jetpacs-search" nil ".org")))
     (with-temp-file file
       (insert "* TODO [#A] Fix the server :server:urgent:\n"
               "DEADLINE: <" (format-time-string "%Y-%m-%d") ">\n"
               "* DONE Deploy the Server :Server:\n"
               "* Buy milk :home:\n"
               "Semi-skimmed preferred.\n"
               "* TODO Call plumber :home:\n"))
     (unwind-protect
         (let ((org-agenda-files (list file)))
           (glasspane-org-cache-invalidate)
           ,@body)
       (delete-file file))))

(defun jetpacs-tests--search-headlines (query)
  "Headlines returned for QUERY, in file order."
  (mapcar (lambda (it) (alist-get 'headline it))
          (glasspane-org--search query)))

;; ─── Buffer-view line numbers ───────────────────────────────────────────────

(require 'jetpacs-buffer)

(defun jetpacs-tests--first-span-text (node)
  (alist-get 'text (aref (alist-get 'spans node) 0)))

;; ─── Org drawers ─────────────────────────────────────────────────────────────

(defun jetpacs-tests--find-node (tree pred)
  "Depth-first search of widget TREE for a node satisfying PRED.
TREE may be a node (alist), a list of nodes, or a vector of nodes."
  (cond
   ((vectorp tree)
    (cl-some (lambda (x) (jetpacs-tests--find-node x pred)) tree))
   ((and (consp tree) (consp (car tree)) (symbolp (caar tree)))
    (if (funcall pred tree) tree
      (cl-some (lambda (kv) (and (consp kv)
                                 (jetpacs-tests--find-node (cdr kv) pred)))
               tree)))
   ((consp tree)
    (cl-some (lambda (x) (jetpacs-tests--find-node x pred)) tree))))

;; ─── Widget wire format (golden snapshot) ───────────────────────────────────

(defconst jetpacs-tests--golden-file
  (expand-file-name "widgets.golden" jetpacs-tests--dir))

(defun jetpacs-tests--canon (x)
  "Recursively sort alist keys in X so serialization order is stable."
  (cond
   ((and (consp x) (consp (car x)) (symbolp (caar x)))
    (sort (mapcar (lambda (kv) (cons (car kv) (jetpacs-tests--canon (cdr kv))))
                  (copy-sequence x))
          (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b))))))
   ((vectorp x) (vconcat (mapcar #'jetpacs-tests--canon x)))
   (t x)))

(defun jetpacs-tests--widget-cases ()
  "A battery exercising every widget constructor with all its options."
  (let* ((act (jetpacs-action "x.y" :args '((k . "v"))
                           :when-offline "drop" :dedupe "d"))
         (leaf (jetpacs-text "leaf")))
    (list
     (jetpacs-text "hi")
     (jetpacs-text "hi" 'title 1 "#FF0000" t 2 4)
     (jetpacs-markup "code" :syntax "elisp" :style 'body :padding 4)
     (jetpacs-rich-text (list (jetpacs-span "a" :bold t)) :style 'body :padding 2)
     (jetpacs-span "s" :bold t :italic t :underline t :strike t :code t
                :tag t :baseline "super" :color "#FFF" :on-tap act :mono t)
     (jetpacs-row leaf leaf)
     (jetpacs-flow-row leaf)
     (jetpacs-column leaf)
     (jetpacs-box (list leaf) :alignment "center" :padding 2 :weight 1 :on-tap act)
     (jetpacs-surface (list leaf) :color "#111" :shape "rounded" :elevation 2 :padding 3)
     (jetpacs-surface (list leaf) :color "surface_container" :shape "rounded_small" :fill t)
     (jetpacs-lazy-column leaf leaf)
     (jetpacs-spacer :height 4 :width 2 :weight 1)
     (jetpacs-divider)
     (jetpacs-card (list leaf) :on-tap act :padding 8 :weight 1)
     (jetpacs-collapsible "cid" leaf (list leaf) :collapsed t :on-long-tap act)
     (jetpacs-reorderable-list (list '((label . "h") (level . 1))) :on-reorder act)
     (jetpacs-action "y.z")
     act
     (jetpacs-clipboard-action "copied text")
     (jetpacs-button "L" act :icon "add" :variant "text" :weight 1 :padding 2)
     (jetpacs-date-button "L" act :value "2026-01-01")
     (jetpacs-time-button "L" act :value "10:00")
     (jetpacs-image "http://x" :content-description "d" :padding 1)
     (jetpacs-icon-button "add" act :content-description "c" :padding 1)
     (jetpacs-menu (list (jetpacs-menu-item "L" act :icon "add")) :icon "more_vert" :padding 2)
     (jetpacs-text-input "tid" :value "v" :hint "h" :label "l" :on-submit act
                      :single-line t :min-lines 1 :max-lines 3
                      :monospace t :syntax "org" :padding 2)
     (jetpacs-text-input "tid2" :multi-line t)
     (jetpacs-enum-list "eid" '("a" "b") :value '("a") :multi-select t
                     :allow-add t :on-change act :padding 1)
     (jetpacs-checkbox "kid" :checked t :label "l" :on-change act :padding 1)
     (jetpacs-switch "sid" :checked t :label "l" :on-change act :padding 1)
     (jetpacs-icon "add" :size 20 :color "#FFF" :padding 1)
     (jetpacs-chip "l" :on-tap act :selected t :icon "add" :padding 1)
     (jetpacs-progress :variant "linear" :value 0.5 :padding 1)
     (jetpacs-assist-chip "l" :on-tap act :icon "add" :padding 1)
     (jetpacs-section-header "t" :trailing leaf :padding 1)
     (jetpacs-empty-state :icon "inbox" :title "t" :caption "c"
                       :on-tap act :action-label "al" :padding 1)
     (jetpacs-date-stamp :date "2026-07-02" :time "10:00" :padding 1)
     (jetpacs-date-stamp :day 2 :month "Jul" :month-index 7 :year 2026)
     (jetpacs-editor "f.org" "content" :on-save act :read-only t :syntax "org"
                  :line-numbers "absolute" :complete t
                  :chromeless t :publish-state t)
     (jetpacs-drawer (list (jetpacs-drawer-item "i" "l" act :selected t)) :header "h")
     (jetpacs-top-bar "t" :nav-icon "menu" :nav-action act :actions (list leaf))
     (jetpacs-fab "add" :label "l" :on-tap act :extended t)
     (jetpacs-bottom-bar (list (jetpacs-nav-item "i" "l" act :selected t)))
     (jetpacs-scaffold :top-bar (jetpacs-top-bar "t") :fab (jetpacs-fab "add")
                    :body leaf :bottom-bar (jetpacs-bottom-bar nil)
                    :snackbar "s" :drawer (jetpacs-drawer nil :header "h")
                    :on-refresh act)
     (jetpacs-table
      (list (jetpacs-table-row
             (list (jetpacs-table-cell (list (jetpacs-span "Item" :bold t)))
                   (jetpacs-table-cell (list (jetpacs-span "Qty"))))
             :header t)
            (jetpacs-table-rule)
            (jetpacs-table-row
             (list (jetpacs-table-cell (list (jetpacs-span "apples"))
                                    :on-tap act :on-long-tap act)
                   (jetpacs-table-cell (list (jetpacs-span "4"))))))
      :aligns '("start" "end") :on-add-row act :on-add-col act :padding 2)
     (jetpacs-table
      (list (jetpacs-table-row (list (jetpacs-table-cell (list (jetpacs-span "a")))))))
     (jetpacs-scroll-row leaf leaf)
     ;; Phase C — composition knobs
     (jetpacs-slider "vol" act :value 0.3 :min 0.0 :max 1.0 :steps 10)
     (jetpacs-row leaf leaf :spacing 4 :align "top")
     (jetpacs-column leaf leaf :spacing 6 :align "center")
     (jetpacs-surface (list leaf) :width 120 :height 40 :fill-fraction 0.5
                   :border (jetpacs-border :width 2 :color "#888"))
     (jetpacs-image "http://x" :width 100 :height 80 :aspect-ratio 1.5
                 :content-scale "crop")
     ;; Phase D — visualization ladder
     (jetpacs-chart (list (jetpacs-chart-series '(1 3 2 5) :label "a" :color "#4C6FFF")
                       (jetpacs-chart-series '(2 2 4 3)))
                 :kind "line" :height 160 :y-range '(0 6) :summary "trend"
                 :on-point-tap act)
     (jetpacs-canvas 100 60
                  (list (jetpacs-draw-line 0 0 100 60 :color "#888" :stroke 2)
                        (jetpacs-draw-rect 10 10 30 20 :fill t :color "primary" :radius 4)
                        (jetpacs-draw-circle 70 30 15 :color "#E64980")
                        (jetpacs-draw-path '((0 60) (50 0) (100 60)) :closed t :fill t)
                        (jetpacs-draw-text 50 30 "hi" :align "center" :size 10))))))

(defun jetpacs-tests--widget-lines ()
  (let ((i -1))
    (mapcar (lambda (c)
              (setq i (1+ i))
              (format "%02d %s" i
                      (json-serialize (jetpacs-tests--canon c)
                                      :null-object :null
                                      :false-object :false)))
            (jetpacs-tests--widget-cases))))

(defun jetpacs-tests-regen-widget-golden ()
  "Rewrite the golden snapshot from the current constructors.
Only run this after an INTENTIONAL wire-format change; review the diff."
  (with-temp-file jetpacs-tests--golden-file
    (insert (string-join (jetpacs-tests--widget-lines) "\n") "\n"))
  (message "Wrote %s" jetpacs-tests--golden-file))

;; ─── Multi-tenant ownership (Phase E) ─────────────────────────────────────────

;; ─── App identity (jetpacs-defapp, AUTO Task 14) ────────────────────────────────

;; ─── Protocol frame shapes (golden snapshot, SPEC §10–§11) ──────────────────

(defconst jetpacs-tests--frames-golden-file
  (expand-file-name "frames.golden" jetpacs-tests--dir))

(defun jetpacs-tests--device-cases ()
  "One `capability.invoke' payload per `jetpacs-device-*' wrapper.
Captures what each thin defun hands the funnel — the SPEC §10 arg
shapes — without touching the wire."
  (let (calls)
    (cl-letf (((symbol-function 'jetpacs-device--invoke)
               (lambda (cap args &optional _callback)
                 (push `((kind . "capability.invoke")
                         (payload
                          . ((cap . ,cap)
                             (args . ,(or args (make-hash-table
                                                :test 'equal))))))
                       calls))))
      (jetpacs-device-intent :action "android.intent.action.VIEW"
                          :data "https://example.com")
      (jetpacs-device-intent :package "com.termux"
                          :class-name "com.termux.app.TermuxActivity"
                          :mode "activity"
                          :extras '((com.example.FLAG . t)
                                    (com.example.COUNT . 3)))
      (jetpacs-device-app-launch "org.gnu.emacs")
      (jetpacs-device-apps-list #'ignore)
      (jetpacs-device-vibrate 300)
      (jetpacs-device-vibrate nil '(0 100 50 100))
      (jetpacs-device-tts "hello" :pitch 1.2 :rate 0.9)
      (jetpacs-device-volume-set "music" 5)
      (jetpacs-device-ringer-mode "vibrate")
      (jetpacs-device-flashlight t)
      (jetpacs-device-flashlight nil)
      (jetpacs-device-media-key "play_pause")
      (jetpacs-device-clipboard-read #'ignore)
      (jetpacs-device-settings-open "wifi")
      (jetpacs-device-keep-screen-on t)
      (jetpacs-device-brightness 128)
      (jetpacs-device-dnd "priority"))
    (nreverse calls)))

(defun jetpacs-tests--frame-cases ()
  "Outbound protocol frame payloads pinned by test/frames.golden.
Trigger and capability frames today; new wire frames add cases here."
  (let ((jetpacs-triggers--table (make-hash-table :test 'equal)))
    ;; Batch Emacs is disconnected, so these registers never send.
    (jetpacs-trigger-register "power-sync" :type "power"
                           :params '((state . "connected"))
                           :policy "wake" :dedupe "power-sync" :throttle-s 60
                           :on-fire [((cap . "flashlight")
                                      (args . ((on . t))))])
    (jetpacs-trigger-register "screen-off" :type "screen"
                           :params '((state . "off")))
    (append
     (list
      `((kind . "triggers.set")
        (payload . ((triggers . ,(jetpacs-triggers--specs))))))
     (jetpacs-tests--device-cases))))

(defun jetpacs-tests--frame-lines ()
  (let ((i -1))
    (mapcar (lambda (c)
              (setq i (1+ i))
              (format "%02d %s" i
                      (json-serialize (jetpacs-tests--canon c)
                                      :null-object :null
                                      :false-object :false)))
            (jetpacs-tests--frame-cases))))

(defun jetpacs-tests-regen-frame-golden ()
  "Rewrite the frame golden snapshot from the current senders.
Only run this after an INTENTIONAL wire-format change; review the diff."
  (with-temp-file jetpacs-tests--frames-golden-file
    (insert (string-join (jetpacs-tests--frame-lines) "\n") "\n"))
  (message "Wrote %s" jetpacs-tests--frames-golden-file))

;; ─── Saved views (PKM Task 11) ───────────────────────────────────────────────

(defun jetpacs-tests--views-items ()
  "Synthetic heading items exercising all three renderings."
  '(((headline . "Write spec") (todo . "TODO") (tags . ["work"])
     (scheduled . "<2026-07-04 Sat>")
     (ref . ((file . "/tmp/a.org") (pos . 1) (headline . "Write spec"))))
    ((headline . "Ship it") (todo . "NEXT") (tags . [])
     (scheduled . nil)
     (ref . ((file . "/tmp/a.org") (pos . 50) (headline . "Ship it"))))))

;; ─── Org-defined automations (AUTO Task 13) ──────────────────────────────────

(defmacro jetpacs-tests--with-automations-file (content &rest body)
  "Run BODY with a temp automations file holding CONTENT."
  (declare (indent 1))
  `(let* ((file (make-temp-file "jetpacs-autom" nil ".org"))
          (glasspane-automations-file file)
          (glasspane-automations--ids nil)
          (jetpacs-triggers--table (make-hash-table :test 'equal))
          (jetpacs-triggers-changed-hook nil))
     (unwind-protect
         (progn (with-temp-file file (insert ,content))
                ,@body)
       (when-let ((buf (find-buffer-visiting file))) (kill-buffer buf))
       (delete-file file))))

;; ─── Notes bridge: wikilinks + backlinks (PKM 3–4, vulpea mocked) ────────────

(defmacro jetpacs-tests--with-fake-vulpea (notes &rest body)
  "Run BODY with the vulpea seam answering from NOTES (plists)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'glasspane-notes-available-p) (lambda () t))
             ((symbol-function 'vulpea-db-search-by-title)
              (lambda (pattern)
                (cl-remove-if-not
                 (lambda (n) (string-match-p (regexp-quote (downcase pattern))
                                             (downcase (plist-get n :title))))
                 ,notes)))
             ((symbol-function 'vulpea-db-query-by-links-some)
              (lambda (_ids &optional _type) ,notes))
             ((symbol-function 'vulpea-db-get-by-id)
              (lambda (id)
                (cl-find id ,notes
                         :key (lambda (n) (plist-get n :id))
                         :test #'equal)))
             ((symbol-function 'vulpea-note-id)
              (lambda (n) (plist-get n :id)))
             ((symbol-function 'vulpea-note-title)
              (lambda (n) (plist-get n :title)))
             ((symbol-function 'vulpea-note-path)
              (lambda (n) (plist-get n :path)))
             ((symbol-function 'vulpea-note-aliases)
              (lambda (n) (plist-get n :aliases))))
     ,@body))

;; ─── SRS skin: review over org-srs (org-srs mocked) ──────────────────────────

(defvar jetpacs-tests--srs-items nil "The mocked pending queue (item-args).")

(defvar jetpacs-tests--srs-rated nil "Ratings recorded by the mock engine.")

(defmacro jetpacs-tests--with-fake-org-srs (&rest body)
  "Run BODY with a minimal org-srs *engine* mock.
`jetpacs-tests--srs-items' is the pending queue (a list of item-args);
`jetpacs-tests--srs-rated' records ratings.  Session state is reset per
invocation; per-item positions (markers, regions, clozes) are mocked
in individual tests where needed."
  (declare (indent 0))
  `(let ((glasspane-srs--available t)
         (glasspane-srs--active nil)
         (glasspane-srs--current nil)
         (glasspane-srs--revealed nil)
         (glasspane-srs--undo nil)
         (jetpacs-tests--srs-items nil)
         (jetpacs-tests--srs-rated nil)
         (jetpacs-shell--snackbar nil))
     (cl-letf (((symbol-function 'org-srs-review-pending-items)
                (lambda (&optional _) jetpacs-tests--srs-items))
               ((symbol-function 'org-srs-item-marker)
                (lambda (&rest _) (copy-marker (point-min))))
               ((symbol-function 'org-srs-review-rate)
                (lambda (rating &rest _) (push rating jetpacs-tests--srs-rated)))
               ((symbol-function 'org-srs-item-call-with-current)
                (lambda (thunk &rest _) (funcall thunk)))
               ((symbol-function 'org-srs-table-goto-column)
                (lambda (_) t))
               ((symbol-function 'org-srs-stats-intervals)
                (lambda () '(:again 600 :hard 86400 :good 259200 :easy 604800)))
               ((symbol-function 'org-srs-time-seconds-desc)
                (lambda (secs) (list (/ secs 60) :minute)))
               ((symbol-function 'jetpacs-shell-push)
                (cl-function (lambda (&optional _tab &key _switch-to)))))
       ,@body)))

;; ─── Ghostel skin ───────────────────────────────────────────────────────────

(defmacro jetpacs-tests--with-fake-ghostel (name &rest body)
  "Run BODY in a fake live ghostel buffer NAME.
Fakes the mode symbol and the buffer-local lifecycle process the skin's
liveness gate checks; ghostel itself is never loaded."
  (declare (indent 1))
  `(let* ((buf (get-buffer-create ,name))
          (pipe (make-pipe-process :name "ghostel-test-pipe" :noquery t)))
     (unwind-protect
         (with-current-buffer buf
           (insert "prompt$ ls\nfile-a\nfile-b\n")
           (setq-local major-mode 'ghostel-mode)
           (setq-local ghostel--process pipe)
           ,@body)
       (delete-process pipe)
       (kill-buffer buf))))

(provide 'jetpacs-tests)

(provide 'glasspane-test-helpers)
