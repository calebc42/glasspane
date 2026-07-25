;;; jetpacs-results-test.el --- JC-2 exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-2 exit gate (docs/PLAN-jetpacs-consumers.md): pure-helper ERT
;; (locus parse), render-structural ERT (cards + `results.visit' :args
;; plist + cap note), action round-trip against a stubbed visit seam
;; (armed stepper, boundary clamps), and the tabulated-list skin.

;;; Code:

(require 'ert)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-results)
(require 'jetpacs-tablist)

(defun jetpacs-results-test--source ()
  "The SOURCE buffer the fixture's loci point into."
  (with-current-buffer (get-buffer-create "*jc2-src*")
    (erase-buffer)
    (dotimes (i 3) (insert (format "source line %d\n" i)))
    (goto-char (point-min))
    (current-buffer)))

(defun jetpacs-results-test--occur-like ()
  "A buffer shaped like `occur' output: three rows carrying `occur-target'.
Each marker points into a real SOURCE buffer — a locus whose target is
the results buffer itself is not a jump, and `jetpacs-results--follow'
correctly refuses it."
  (let ((src (jetpacs-results-test--source))
        ;; `inhibit-read-only' around EVERYTHING: on reuse the buffer is
        ;; already in occur-mode, so even the first `erase-buffer' signals.
        (inhibit-read-only t))
    (with-current-buffer (get-buffer-create "*jc2-occur*")
      (erase-buffer)
      (occur-mode)
      (erase-buffer)
      (dotimes (i 3)
        (let ((start (point))
              (target (with-current-buffer src
                        (goto-char (point-min))
                        (forward-line i)
                        (copy-marker (point)))))
          (insert (format "%d:hit number %d\n" (1+ i) i))
          (put-text-property start (1+ start) 'occur-target target)))
      (goto-char (point-min))
      (current-buffer))))

(defmacro jetpacs-results-test--with-client (spec &rest body)
  "Attach a stub READY client, run BODY, always detach."
  (declare (indent 1))
  `(let ((client (ebp-client-create
                  :receipt-file (make-temp-file "jc2-receipts"))))
     (setf (ebp-client-state client) 'ready
           (ebp-client-limits client) '(:max_frame_bytes 4194304)
           (ebp-client-profiles client) ,spec)
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (setq jetpacs-results--nav nil
             jetpacs-results--region nil
             jetpacs-results--file-set nil))))

(defconst jetpacs-results-test--full
  '(:app (:node_types ["text" "row" "column" "box" "spacer" "divider"
                       "button" "text_input" "card" "rich_text" "icon"
                       "icon_button" "chip" "flow_row"]
          :builtins [] :features []))
  "A profile advertising everything these skins want.")

(defconst jetpacs-results-test--core
  '(:app (:node_types ["text" "row" "column" "box" "spacer" "divider"
                       "button" "text_input"]
          :builtins [] :features []))
  "The SPEC 16.2 Core Node Set only — the degrade fixture.")

;;;; Pure helpers

(ert-deftest jetpacs-results-locus-parse ()
  "The locus scan finds one actionable position per marked row."
  (let* ((buf (jetpacs-results-test--occur-like))
         (loci (jetpacs-results--loci buf)))
    (should (= (length loci) 3))
    (should (cl-every #'numberp (mapcar #'car loci)))
    (should (equal (cdr (nth 0 loci)) "1:hit number 0"))
    ;; index-of is exact, and nil (NOT 0) when the position names no locus —
    ;; the caller turns that into `stale' rather than visiting a wrong row.
    (should (= (jetpacs-results--index-of loci (car (nth 2 loci))) 2))
    (should-not (jetpacs-results--index-of loci 99999))))

(ert-deftest jetpacs-results-buffer-p-gates-mode ()
  "SPEC 23.1: only a real results-mode buffer is reachable."
  (should (jetpacs-results--buffer-p (jetpacs-results-test--occur-like)))
  (should-not (jetpacs-results--buffer-p
               (get-buffer-create "*jc2-not-results*")))
  (should-not (jetpacs-results--buffer-p nil)))

;;;; Render

(ert-deftest jetpacs-results-render-structure ()
  "Header caption, one card per locus, plist :args, exposure recorded."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--occur-like))
           (nodes (jetpacs-results-render buf)))
      ;; caption + 3 cards
      (should (= (length nodes) 4))
      (should (equal (plist-get (car nodes) :t) "text"))
      (should (equal (plist-get (car nodes) :text) "3 results"))
      (let* ((card (nth 1 nodes))
             (tap (plist-get card :on_tap))
             (args (plist-get tap :args)))
        (should (equal (plist-get card :t) "card"))
        (should (equal (plist-get tap :action) "results.visit"))
        ;; format-6: args is a keyword plist, not an alist.
        (should (equal (plist-get args :buffer) "*jc2-occur*"))
        (should (numberp (plist-get args :pos)))
        ;; Offline default flipped to drop; nothing here opts into queueing.
        (should-not (plist-get tap :when_offline))
        ;; SPEC 23.1: the skin records its own tap targets — for ITS verb
        ;; only.  A locus must not thereby authorize `emacs.buffer.act',
        ;; which would run the same goto UNSHIMMED (desktop window, and a
        ;; prompt could wedge the dispatch extent).
        (should (jetpacs-buffer-exposed-p "*jc2-occur*"
                                          (plist-get args :pos)
                                          "results.visit"))
        (should-not (jetpacs-buffer-exposed-p "*jc2-occur*"
                                              (plist-get args :pos)
                                              "emacs.buffer.act")))
      ;; The whole tree must clear the live gate.
      (should (jetpacs-check-node-types
               (vconcat nodes)
               (append (plist-get (plist-get jetpacs-results-test--full :app)
                                  :node_types)
                       nil)
               "app")))))

(ert-deftest jetpacs-results-render-cap-note ()
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let ((jetpacs-results-max-loci 2))
      (let ((nodes (jetpacs-results-render (jetpacs-results-test--occur-like))))
        ;; caption + 2 cards + the truncation note
        (should (= (length nodes) 4))
        ;; The count is marked approximate: the scan stops at the cap, so
        ;; the true total is unknown without walking the whole buffer.
        (should (equal (plist-get (car nodes) :text) "2 results+"))
        (should (string-match-p "first 2"
                                (plist-get (car (last nodes)) :text)))
        ;; The stepper's count must not exceed what was rendered AND
        ;; exposed: stepping into an unexposed locus would be refused.
        (should (= (length (jetpacs-results--loci
                            (get-buffer "*jc2-occur*")))
                   2))))))

(ert-deftest jetpacs-results-render-degrades-to-core ()
  "SPEC 16.2: card/rich_text/icon are OPTIONAL; a Core-only Companion
still gets a rendered, tappable list."
  (jetpacs-results-test--with-client jetpacs-results-test--core
    (let ((nodes (jetpacs-results-render (jetpacs-results-test--occur-like))))
      (should (jetpacs-check-node-types
               (vconcat nodes)
               (append (plist-get (plist-get jetpacs-results-test--core :app)
                                  :node_types)
                       nil)
               "app"))
      ;; Still tappable: the fallback carries a Core button.
      (should (member "button" (jetpacs--collect-node-types
                                (vconcat nodes) '()))))))

(ert-deftest jetpacs-results-empty-falls-back-to-tier0 ()
  "A results buffer with no parsed loci renders faithful Tier-0 text."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (with-current-buffer (get-buffer-create "*jc2-empty*")
      (let ((inhibit-read-only t))
        (erase-buffer) (occur-mode) (erase-buffer)
        (insert "Searching...\n"))
      (let ((nodes (jetpacs-results-render (current-buffer))))
        (should nodes)
        (should-not (member "card" (jetpacs--collect-node-types
                                    (vconcat nodes) '())))))))

;;;; Actions

(defun jetpacs-results-test--visit (buf pos &optional params)
  (funcall (gethash "results.visit" jetpacs-action-handlers)
           (list :buffer (buffer-name buf) :pos pos)
           (or params '(:surface "app:demo"))))

(ert-deftest jetpacs-results-visit-statuses ()
  "SPEC 14.4/14.5/23.1: every branch answers the right status."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--occur-like))
           (visited nil)
           (jetpacs-results-visit-region-function
            (lambda (name beg end label &optional point)
              (setq visited (list name beg end label point)))))
      ;; Render first: only offsets this Emacs offered are tappable.
      (jetpacs-results-render buf)
      (let ((loci (jetpacs-results--loci buf)))
        ;; Not a results buffer -> rejected.
        (should (eq (funcall (gethash "results.visit" jetpacs-action-handlers)
                             '(:buffer "*jc2-not-results*" :pos 1)
                             '(:surface "app:demo"))
                    'rejected))
        ;; A never-exposed offset -> rejected (SPEC 23.1).
        (should (eq (jetpacs-results-test--visit buf 99999) 'rejected))
        ;; Malformed args -> rejected.
        (should (eq (funcall (gethash "results.visit" jetpacs-action-handlers)
                             '(:buffer 42) '(:surface "app:demo"))
                    'rejected))
        ;; A real locus visits and arms the stepper.
        (should (eq (jetpacs-results-test--visit buf (car (nth 1 loci)))
                    'accepted))
        (should visited)
        (should (equal (plist-get jetpacs-results--nav :index) 1))
        (should (= (plist-get jetpacs-results--nav :count) 3))
        (should (eq (plist-get jetpacs-results--nav :kind) 'buffer))))))

(ert-deftest jetpacs-results-visit-moved-row-is-stale ()
  "SPEC 14.5: an exposed offset that no longer names a locus means the
list moved under the user — `stale' (re-presentable), never a silent
visit of a different row."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--occur-like))
           (pos (car (nth 2 (jetpacs-results--loci buf)))))
      (jetpacs-results-render buf)
      ;; Rewrite the buffer so that offset is no longer a locus, without
      ;; disturbing the exposure record.
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "1:only one hit now\n")
          (put-text-property (point-min) (1+ (point-min))
                             'occur-target (copy-marker (point-min)))))
      (should (eq (jetpacs-results-test--visit buf pos) 'stale)))))

(ert-deftest jetpacs-results-visit-file-loci ()
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((file (make-temp-file "jc2-src" nil ".txt" "a\nb\nc\nd\n"))
           (visited nil)
           (jetpacs-results-visit-region-function
            (lambda (&rest a) (setq visited a))))
      (jetpacs-results-set-file-loci
       (list (list :file file :line 2 :text "b")))
      (let ((handler (gethash "results.visit" jetpacs-action-handlers)))
        ;; Out of range -> stale (the set changed), not rejected.
        (should (eq (funcall handler '(:index 5) '(:surface "app:demo"))
                    'stale))
        (should (eq (funcall handler '(:index 0) '(:surface "app:demo"))
                    'accepted))
        (should visited)
        (should (eq (plist-get jetpacs-results--nav :kind) 'file))))))

(ert-deftest jetpacs-results-step-boundaries ()
  "The stepper walks the armed set and reports its edges as `stale'."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--occur-like))
           (jetpacs-results-visit-region-function #'ignore)
           (step (gethash "results.step" jetpacs-action-handlers)))
      (jetpacs-results-render buf)
      ;; Nothing armed yet.
      (should (eq (funcall step '(:dir 1) nil) 'rejected))
      ;; Arm at index 0.
      (jetpacs-results-test--visit buf (car (nth 0 (jetpacs-results--loci buf))))
      (should (= (plist-get jetpacs-results--nav :index) 0))
      ;; Before the first is an edge, not an error.
      (should (eq (funcall step '(:dir -1) nil) 'stale))
      ;; Forward twice reaches the last.
      (should (eq (funcall step '(:dir 1) nil) 'accepted))
      (should (= (plist-get jetpacs-results--nav :index) 1))
      (should (eq (funcall step '(:dir 1) nil) 'accepted))
      (should (= (plist-get jetpacs-results--nav :index) 2))
      (should (eq (funcall step '(:dir 1) nil) 'stale))
      ;; A bogus direction is rejected, never coerced.
      (should (eq (funcall step '(:dir 7) nil) 'rejected))
      (should (eq (funcall step '(:dir "1") nil) 'rejected)))))

(ert-deftest jetpacs-results-step-chrome ()
  "Only the in-range direction is offered at each end."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--occur-like))
           (jetpacs-results-visit-region-function #'ignore))
      (jetpacs-results-render buf)
      (jetpacs-results-test--visit buf (car (nth 0 (jetpacs-results--loci buf))))
      (let* ((dest (plist-get jetpacs-results--nav :dest))
             (nodes (jetpacs-results-buffer-view-actions dest))
             (kinds (jetpacs--collect-node-types (vconcat nodes) '())))
        ;; At index 0 of 3: next only.
        (should nodes)
        (should (= (length (plist-get (car nodes) :children)) 1))
        (should (member "icon_button" kinds)))
      ;; A different buffer gets no chrome.
      (should-not (jetpacs-results-buffer-view-actions "*somewhere-else*")))))

;;;; tabulated-list skin

(defun jetpacs-results-test--tablist ()
  "A live tabulated-list buffer with two rows and a sortable column."
  (with-current-buffer (get-buffer-create "*jc2-tablist*")
    (tabulated-list-mode)
    (setq tabulated-list-format [("Name" 10 t) ("Note" 10 nil)]
          tabulated-list-entries
          '(("a" ["alpha" "first"]) ("b" ["beta" "second"]))
          tabulated-list-sort-key '("Name" . nil))
    (tabulated-list-init-header)
    (tabulated-list-print)
    (current-buffer)))

(ert-deftest jetpacs-tablist-render-structure ()
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--tablist))
           (nodes (jetpacs-tablist-render buf))
           (kinds (jetpacs--collect-node-types (vconcat nodes) '())))
      (should (string-match-p "2 rows"
                              (format "%s" (jetpacs-node->canonical-json
                                            (vconcat nodes)))))
      (should (member "chip" kinds))       ; the sortable column
      (should (member "card" kinds))       ; the rows
      ;; Row taps reuse emacs.buffer.act AND are exposed (SPEC 23.1) —
      ;; without the exposure this skin's every tap would be refused.
      (with-current-buffer buf
        (let ((rows (jetpacs-tablist--rows)))   ; needs the buffer current
          ;; The tablist rows DO tap emacs.buffer.act, so that is the verb
          ;; they authorize — and only that one.
          (should (jetpacs-buffer-exposed-p "*jc2-tablist*"
                                            (nth 0 (car rows))
                                            "emacs.buffer.act"))
          (should-not (jetpacs-buffer-exposed-p "*jc2-tablist*"
                                                (nth 0 (car rows))
                                                "results.visit"))))
      (should (jetpacs-check-node-types
               (vconcat nodes)
               (append (plist-get (plist-get jetpacs-results-test--full :app)
                                  :node_types)
                       nil)
               "app")))))

(ert-deftest jetpacs-tablist-render-degrades-to-core ()
  (jetpacs-results-test--with-client jetpacs-results-test--core
    (let ((nodes (jetpacs-tablist-render (jetpacs-results-test--tablist))))
      (should (jetpacs-check-node-types
               (vconcat nodes)
               (append (plist-get (plist-get jetpacs-results-test--core :app)
                                  :node_types)
                       nil)
               "app")))))

(ert-deftest jetpacs-tablist-action-statuses ()
  "SPEC 14.4/23.1: sort and refresh validate against the buffer's own
format and answer real statuses."
  (jetpacs-results-test--with-client jetpacs-results-test--full
    (let* ((buf (jetpacs-results-test--tablist))
           (refreshed nil)
           (jetpacs-buffer-refresh-function
            (lambda (surface) (setq refreshed surface)))
           (sort (gethash "tablist.sort" jetpacs-action-handlers))
           (refresh (gethash "tablist.refresh" jetpacs-action-handlers))
           (params '(:surface "app:demo")))
      ;; Unknown buffer / wrong mode / unknown column -> rejected.
      (should (eq (funcall sort '(:buffer "*nope*" :column "Name") params)
                  'rejected))
      (should (eq (funcall sort (list :buffer (buffer-name buf)
                                      :column "NoSuchColumn")
                           params)
                  'rejected))
      ;; A real column sorts, re-pushes the ORIGINATING surface, accepts.
      (should (eq (funcall sort (list :buffer (buffer-name buf)
                                      :column "Name")
                           params)
                  'accepted))
      (should (equal refreshed "app:demo"))
      (with-current-buffer buf
        ;; Same column again flips direction.
        (should (equal (car tabulated-list-sort-key) "Name")))
      (setq refreshed nil)
      (should (eq (funcall refresh (list :buffer (buffer-name buf)) params)
                  'accepted))
      (should (equal refreshed "app:demo"))
      (should (eq (funcall refresh '(:buffer "*nope*") params) 'rejected)))))

(provide 'jetpacs-results-test)
;;; jetpacs-results-test.el ends here
