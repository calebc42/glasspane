;;; jetpacs-hypertext-test.el --- JC-3b hypertext skin exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JC-3b exit gate (docs/PLAN-jetpacs-consumers.md + the JC-3 review):
;; a hand-built shr-prop fixture renders to a byte-asserted golden
;; (test/goldens/hypertext-doc.golden — regenerate by evaluating
;; `jetpacs-hypertext-test--write-golden' after a reviewed change); the
;; image resolver's decision table is witnessed case by case; SPEC 4.1
;; raw octets survive; SPEC 16.2 optional types degrade on a Core-only
;; profile; SPEC 23.1 whole-buffer exposure gates `hypertext.nav'; the
;; SPEC 14.4 nav status matrix holds; and SPEC 4.5 budgets truncate.
;;
;; The shr fixture is hand-built against the props CONTRACT (the
;; firewall section of jetpacs-hypertext.el) rather than rendered by
;; shr itself: deterministic, libxml-free, and it tests OUR reader.
;; Whether live shr still writes those props is the device smoke's job.

;;; Code:

(require 'ert)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-hypertext)

(defconst jetpacs-hypertext-test--golden
  (expand-file-name "goldens/hypertext-doc.golden"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "The byte-asserted document-render golden.")

;; --- Fixtures ----------------------------------------------------------------

(defmacro jetpacs-hypertext-test--with-client (spec &rest body)
  "Attach a stub READY client per SPEC (:limits L :profiles P), run BODY."
  (declare (indent 1))
  `(let ((client (ebp-client-create
                  :receipt-file (make-temp-file "jc3b-receipts"))))
     (setf (ebp-client-state client) 'ready)
     (when ,(plist-get spec :limits)
       (setf (ebp-client-limits client) ,(plist-get spec :limits)))
     (when ,(plist-get spec :profiles)
       (setf (ebp-client-profiles client) ,(plist-get spec :profiles)))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach))))

(defun jetpacs-hypertext-test--shr-fixture ()
  "A deterministic buffer written in shr's rendered-buffer markup.
Covers: an shr-h1 heading, a two-line paragraph (reflow), a link run
(tap survival), a table region stamped `shr-table-id', and an https
image run."
  (with-current-buffer (get-buffer-create "*jc3b-shr*")
    (fundamental-mode)
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert (propertize "The Heading" 'face 'shr-h1) "\n\n")
    (insert "First line of prose\ncontinues here\n\n")
    (let ((km (make-sparse-keymap)))
      (define-key km (kbd "RET") #'ignore)
      (insert (propertize "a link" 'keymap km 'mouse-face 'highlight
                          'help-echo "https://example.org")
              " in prose\n\n"))
    (insert (propertize "cell-a  cell-b" 'shr-table-id 1) "\n")
    (insert (propertize "cell-c  cell-d" 'shr-table-indent 1) "\n\n")
    (insert (propertize " " 'image-url "https://example.org/pic.png"
                        'shr-alt "A picture") "\n")
    (current-buffer)))

(defun jetpacs-hypertext-test--render-fixture ()
  "The shr fixture rendered to canonical JSON (offline: richer forms)."
  (jetpacs-node->canonical-json
   (vconcat (jetpacs-hypertext-render (jetpacs-hypertext-test--shr-fixture)))))

(defun jetpacs-hypertext-test--write-golden ()
  "Regenerate the golden from the fixture (run after a reviewed change)."
  (with-temp-file jetpacs-hypertext-test--golden
    (insert (jetpacs-hypertext-test--render-fixture))))

(defun jetpacs-hypertext-test--u32 (v)
  "V as four big-endian bytes."
  (list (logand (ash v -24) #xFF) (logand (ash v -16) #xFF)
        (logand (ash v -8) #xFF) (logand v #xFF)))

(defun jetpacs-hypertext-test--png (w h)
  "Fake PNG bytes with an IHDR declaring W x H (headers only)."
  (apply #'unibyte-string
         (append (list #x89 ?P ?N ?G #x0D #x0A #x1A #x0A 0 0 0 13
                       ?I ?H ?D ?R)
                 (jetpacs-hypertext-test--u32 w)
                 (jetpacs-hypertext-test--u32 h)
                 (list 8 6 0 0 0 0 0 0 0))))

(defun jetpacs-hypertext-test--jpeg (w h)
  "Fake JPEG bytes with a SOF0 declaring W x H (headers only)."
  (apply #'unibyte-string
         (append (list #xFF #xD8                     ; SOI
                       #xFF #xE0 0 4 0 0             ; APP0, len 4
                       #xFF #xC0 0 17 8)             ; SOF0, len 17, prec
                 (list (ash h -8) (logand h #xFF)
                       (ash w -8) (logand w #xFF))
                 (list 3 0 0 0 0 0 0 0 0 0 0 0))))

;; --- Golden + structure ------------------------------------------------------

(ert-deftest jetpacs-hypertext-golden ()
  "The shr fixture renders byte-identically to the reviewed golden."
  (should (file-readable-p jetpacs-hypertext-test--golden))
  (should (equal (jetpacs-hypertext-test--render-fixture)
                 (with-temp-buffer
                   (insert-file-contents jetpacs-hypertext-test--golden)
                   (buffer-string)))))

(ert-deftest jetpacs-hypertext-model-shapes ()
  "The scanner recovers heading / para / table / image in order, the
paragraph reflowed across its lines with a joiner span."
  (let* ((buf (jetpacs-hypertext-test--shr-fixture))
         (model (jetpacs-hypertext--scan-shr buf))
         (kinds (mapcar (lambda (s) (plist-get s :kind)) model)))
    (should (equal kinds '(heading para para table image)))
    (should (equal (plist-get (nth 0 model) :text) "The Heading"))
    (should (= (plist-get (nth 0 model) :level) 1))
    ;; The two prose lines reflow into ONE paragraph joined by a space.
    (should (equal (jetpacs-hypertext--spans-text
                    (plist-get (nth 1 model) :spans))
                   "First line of prose continues here"))
    ;; The table region keeps both lines (the id-less second block
    ;; continues the first) verbatim.
    (should (string-match-p "cell-a  cell-b\ncell-c  cell-d"
                            (plist-get (nth 3 model) :text)))
    (should (equal (plist-get (nth 4 model) :url)
                   "https://example.org/pic.png"))))

(ert-deftest jetpacs-hypertext-emitted-colors-are-registered ()
  "Every :color the emitter puts on a node is a registered 16.6 role —
the poc's `surface_container' was not, and the Companion's fallback made
code blocks silently lose their tint."
  (let (colors)
    (cl-labels ((walk (n)
                  (when (plist-get n :color) (push (plist-get n :color) colors))
                  (mapc #'walk (append (plist-get n :children) nil))))
      (mapc #'walk (jetpacs-hypertext--emit
                    (list '(:kind pre :text "code")
                          '(:kind quote :text "quoted")))))
    (should colors)
    (dolist (c colors) (should (jetpacs-color-valid-p c)))))

(ert-deftest jetpacs-hypertext-info-classifier ()
  "Info headings lift by their underline; the bare rule line drops."
  (with-temp-buffer
    (insert "Node Title\n==========\n\nBody text here\n")
    (rename-buffer "*jc3b-info*" t)
    (let* ((model (jetpacs-hypertext--scan-lines
                   (current-buffer) #'jetpacs-hypertext--info-line-class))
           (kinds (mapcar (lambda (s) (plist-get s :kind)) model)))
      (should (equal kinds '(heading para)))
      (should (= (plist-get (car model) :level) 2))
      (should (equal (plist-get (car model) :text) "Node Title")))))

;; --- The image resolver (the JC-3b rebuild) ----------------------------------

(defun jetpacs-hypertext-test--node-t (node) (plist-get node :t))

(ert-deftest jetpacs-hypertext-image-svg-rejected-before-decode ()
  "SPEC 17.2: svg — either shape — degrades to a caption, no signal."
  (dolist (seg '((:kind image :url "data:image/svg+xml;base64,PHN2Zz4="
                  :alt "vector")
                 (:kind image :data "<svg xmlns=whatever>"
                  :content-type svg :alt "vector")))
    (let ((node (jetpacs-hypertext--image seg)))
      (should (equal (jetpacs-hypertext-test--node-t node) "text"))
      (should (string-match-p "vector" (plist-get node :text))))))

(ert-deftest jetpacs-hypertext-image-https-forms ()
  "https passes through under `image.https'; captions without it;
http upgrades to https (SPEC 22.4 registers no plaintext form)."
  ;; Offline (no client): richer form assumed — passthrough.
  (let ((node (jetpacs-hypertext--image
               '(:kind image :url "https://example.org/a.png" :alt "A"))))
    (should (equal (jetpacs-hypertext-test--node-t node) "image"))
    (should (equal (plist-get node :url) "https://example.org/a.png")))
  ;; http upgrades.
  (let ((node (jetpacs-hypertext--image
               '(:kind image :url "http://example.org/a.png" :alt "A"))))
    (should (equal (plist-get node :url) "https://example.org/a.png")))
  ;; Advertised set without image.https: caption, never an emit-and-hope
  ;; (the push gate SIGNALS on an unadvertised URI form).
  ;; The node IS advertised here, so the caption below is provably the
  ;; missing FEATURE's doing, not the missing node type's.
  (jetpacs-hypertext-test--with-client
      (:profiles '(:app (:node_types ["image" "text"]
                         :features ["image.data"])))
    (let ((node (jetpacs-hypertext--image
                 '(:kind image :url "https://example.org/a.png" :alt "A"))))
      (should (equal (jetpacs-hypertext-test--node-t node) "text"))
      (should (string-match-p "\\[image: A\\]" (plist-get node :text))))))

(ert-deftest jetpacs-hypertext-image-data-uri-passthrough-and-limits ()
  "A fitting data: URI rides through untouched under `image.data'; each
per-image limit independently degrades it to the caption (SPEC 4.5:
limits apply per image, and a sender MUST respect them)."
  (let* ((png (jetpacs-hypertext-test--png 3 2))
         (uri (concat "data:image/png;base64,"
                      (base64-encode-string png t))))
    (cl-flet ((resolve (limits)
                ;; :node_types matters: with a live client a missing
                ;; list is NOT support for everything (SPEC 10.2), so
                ;; the `image' node itself must be advertised too.
                (jetpacs-hypertext-test--with-client
                    (:limits limits
                     :profiles '(:app (:node_types ["image" "text"]
                                       :features ["image.data"])))
                  (jetpacs-hypertext-test--node-t
                   (jetpacs-hypertext--image
                    (list :kind 'image :url uri :alt "P"))))))
      (should (equal (resolve '(:max_image_bytes 4096 :max_image_pixels 100
                                :max_decoded_image_bytes 4096))
                     "image"))
      (should (equal (resolve '(:max_image_bytes 8)) "text"))
      (should (equal (resolve '(:max_image_pixels 4)) "text"))
      (should (equal (resolve '(:max_decoded_image_bytes 16)) "text")))
    ;; Untouched means UNTOUCHED: the URI is not re-encoded.
    (let ((node (jetpacs-hypertext--image (list :kind 'image :url uri))))
      (should (equal (plist-get node :url) uri)))))

(ert-deftest jetpacs-hypertext-image-bytes-inline-and-sniff ()
  "shr :data bytes inline as a fresh data: URI; a readable :file becomes
an input to the data path; unmeasurable or non-png/jpeg bytes caption."
  ;; :data png bytes -> data URI.
  (let ((node (jetpacs-hypertext--image
               (list :kind 'image :data (jetpacs-hypertext-test--png 2 2)
                     :alt "D"))))
    (should (equal (jetpacs-hypertext-test--node-t node) "image"))
    (should (string-prefix-p "data:image/png;base64," (plist-get node :url))))
  ;; jpeg sniffs from magic bytes, no :content-type needed.
  (let ((node (jetpacs-hypertext--image
               (list :kind 'image :data (jetpacs-hypertext-test--jpeg 4 3)))))
    (should (string-prefix-p "data:image/jpeg;base64," (plist-get node :url))))
  ;; gif magic: OPTIONAL decoder, no feature to ask about -> caption.
  (should (equal (jetpacs-hypertext-test--node-t
                  (jetpacs-hypertext--image
                   (list :kind 'image :data "GIF89a-not-really" :alt "G")))
                 "text"))
  ;; A readable file inlines; an unreadable one captions.
  (let ((f (make-temp-file "jc3b-img" nil ".png"
                           (jetpacs-hypertext-test--png 2 2))))
    (unwind-protect
        (let ((node (jetpacs-hypertext--image (list :kind 'image :file f))))
          (should (string-prefix-p "data:image/png;base64,"
                                   (plist-get node :url))))
      (delete-file f)))
  (should (equal (jetpacs-hypertext-test--node-t
                  (jetpacs-hypertext--image
                   '(:kind image :file "/nonexistent/x.png" :alt "F")))
                 "text")))

(ert-deftest jetpacs-hypertext-image-respects-frame-budget ()
  "An inlined image competes with the document's own text: base64 past
the remaining frame budget degrades to the caption, not a blown push."
  (let ((jetpacs-buffer--budget (cons nil 16)))  ; 16 bytes left
    (should (equal (jetpacs-hypertext-test--node-t
                    (jetpacs-hypertext--image
                     (list :kind 'image
                           :data (jetpacs-hypertext-test--png 2 2))))
                   "text"))))

(ert-deftest jetpacs-hypertext-size-sniffers ()
  "PNG IHDR and JPEG SOFn header sniffing is exact — the measurement
works in batch and on a headless daemon, where `image-size' cannot."
  (should (equal (jetpacs-hypertext--png-size
                  (jetpacs-hypertext-test--png 640 480))
                 '(640 . 480)))
  (should (equal (jetpacs-hypertext--jpeg-size
                  (jetpacs-hypertext-test--jpeg 320 200))
                 '(320 . 200)))
  (should-not (jetpacs-hypertext--image-dimensions "GIF89a-not-really"))
  (should-not (jetpacs-hypertext--image-dimensions "")))

;; --- SPEC 16.2: the Core-only profile ----------------------------------------

(ert-deftest jetpacs-hypertext-core-only-profile-degrades ()
  "Every optional type degrades on a Core-only profile and the render
still serializes — the poc gated NONE, and the push gate SIGNALS."
  (jetpacs-hypertext-test--with-client
      (:profiles '(:app (:node_types ["text" "row" "column" "box" "spacer"
                                      "divider" "button" "text_input"]
                         :features [])))
    (let* ((nodes (jetpacs-hypertext--emit
                   (list '(:kind heading :text "H")
                         (list :kind 'para :spans (list (jetpacs-span "p")))
                         '(:kind pre :text "code")
                         '(:kind quote :text "q")
                         '(:kind table
                           :rows ((:header t :cells ("a" "b")))
                           :text "a  b")
                         '(:kind image :url "https://x.example/i.png"
                           :alt "pic"))))
           (kinds (mapcar (lambda (n) (plist-get n :t)) nodes)))
      (should (equal kinds '("text" "text" "text" "text" "text" "text")))
      ;; And the whole thing serializes.
      (should (stringp (jetpacs-node->canonical-json (vconcat nodes)))))))

;; --- SPEC 4.1: raw octets ----------------------------------------------------

(ert-deftest jetpacs-hypertext-raw-octets-survive ()
  "Raw bytes in a heading, a table region, and the eww title sanitize to
U+FFFD instead of taking `json-serialize' down."
  (let ((raw (string-to-multibyte (unibyte-string #xC8 #xC9))))
    (with-current-buffer (get-buffer-create "*jc3b-raw*")
      (fundamental-mode)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert (propertize (concat "Head" raw "ing") 'face 'shr-h1) "\n\n")
      (insert (propertize (concat "cell" raw) 'shr-table-id 1) "\n")
      (setq-local eww-data (list :title (concat "T" raw)))
      (let ((nodes (jetpacs-hypertext-render (current-buffer))))
        (should (stringp (jetpacs-node->canonical-json (vconcat nodes)))))
      (should (equal (jetpacs-hypertext--eww-title (current-buffer))
                     "T��")))))

;; --- SPEC 23.1 + 14.4: hypertext.nav -----------------------------------------

(defun jetpacs-hypertext-test--help-buffer ()
  "A rendered help-mode buffer with fake nav state."
  (with-current-buffer (get-buffer-create "*jc3b-help*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "Help text about a thing\n"))
    (help-mode)
    (setq-local help-xref-stack (list (list 1 #'ignore)))
    (jetpacs-hypertext-render-help (current-buffer))
    (current-buffer)))

(ert-deftest jetpacs-hypertext-nav-requires-presentation ()
  "SPEC 23.1: nav on a live but never-rendered buffer is refused; the
whole-buffer record is written by a render and superseded by forget."
  (jetpacs-buffer-forget-exposed)
  (with-temp-buffer
    (rename-buffer "*jc3b-unrendered*" t)
    (insert "text\n")
    (should (eq (funcall (gethash "hypertext.nav" jetpacs-action-handlers)
                         '(:buffer "*jc3b-unrendered*" :op "back")
                         '(:surface "app:demo"))
                'rejected)))
  (let ((buf (jetpacs-hypertext-test--help-buffer)))
    (should (jetpacs-buffer-exposed-buffer-p (buffer-name buf)
                                             "hypertext.nav"))
    (jetpacs-buffer-forget-exposed (buffer-name buf))
    (should-not (jetpacs-buffer-exposed-buffer-p (buffer-name buf)
                                                 "hypertext.nav"))
    (kill-buffer buf)))

(ert-deftest jetpacs-hypertext-rerender-supersedes-exposure ()
  "SPEC 23.1: a re-render drops offsets the previous render exposed."
  (let ((buf (jetpacs-hypertext-test--shr-fixture)))
    (jetpacs-buffer-forget-exposed)
    (jetpacs-buffer-expose (buffer-name buf) 99999 "emacs.buffer.act")
    (jetpacs-hypertext-render buf)
    (should-not (jetpacs-buffer-exposed-p (buffer-name buf) 99999
                                          "emacs.buffer.act"))))

(ert-deftest jetpacs-hypertext-nav-status-matrix ()
  "SPEC 14.4: bad buffer / bad op / op outside this mode's allowlist ->
`rejected'; a valid op -> `accepted' with the mode's own command run and
the deferred re-push aimed at the EVENT's surface, not a default."
  (let* ((buf (jetpacs-hypertext-test--help-buffer))
         (name (buffer-name buf))
         (nav (gethash "hypertext.nav" jetpacs-action-handlers))
         (params '(:surface "app:demo"))
         (ran nil) (pushed nil))
    (unwind-protect
        (cl-letf (((symbol-function 'help-go-back)
                   (lambda () (interactive) (setq ran t)))
                  (jetpacs-buffer-refresh-function
                   (lambda (surface) (setq pushed surface))))
          (should (eq (funcall nav '(:buffer "*nope*" :op "back") params)
                      'rejected))
          (should (eq (funcall nav (list :buffer name :op 42) params)
                      'rejected))
          ;; `reload' is real wire vocabulary — for eww-mode, not here.
          (should (eq (funcall nav (list :buffer name :op "reload") params)
                      'rejected))
          ;; And a name that is no op at all cannot be interned into one.
          (should (eq (funcall nav (list :buffer name :op "shell-command")
                               params)
                      'rejected))
          (should-not ran)
          (should (eq (funcall nav (list :buffer name :op "back") params)
                      'accepted))
          (should ran)
          ;; The re-push is deferred (D2) and carries the event's surface.
          (should-not pushed)
          (sit-for 0.1)
          (should (equal pushed "app:demo")))
      (kill-buffer buf))))

(ert-deftest jetpacs-hypertext-nav-failure-is-rejected ()
  "A navigation command that signals answers `rejected', not a claimed
success — the shim swallows errors, so only the ON-ERROR thunk knows."
  (let* ((buf (jetpacs-hypertext-test--help-buffer))
         (name (buffer-name buf))
         (nav (gethash "hypertext.nav" jetpacs-action-handlers)))
    (unwind-protect
        (cl-letf (((symbol-function 'help-go-back)
                   (lambda () (interactive) (error "no history"))))
          (should (eq (funcall nav (list :buffer name :op "back")
                               '(:surface "app:demo"))
                      'rejected)))
      (kill-buffer buf))))

;; --- SPEC 4.5: budgets -------------------------------------------------------

(ert-deftest jetpacs-hypertext-scan-cap ()
  "The segment cap stops the scan and marks the cut with a note."
  (let ((jetpacs-hypertext-max-segments 5))
    (with-temp-buffer
      (rename-buffer "*jc3b-long*" t)
      (dotimes (i 20) (insert (format "line %d\n" i)))
      (let* ((model (jetpacs-hypertext--scan-lines (current-buffer)))
             (kinds (mapcar (lambda (s) (plist-get s :kind)) model)))
        (should (= (length model) 6))
        (should (eq (car (last kinds)) 'note))))))

(ert-deftest jetpacs-hypertext-emit-respects-frame-budget ()
  "The emit walk spends the shared byte budget down and stops with the
truncation caption instead of over-emitting."
  (jetpacs-hypertext-test--with-client
      (:limits '(:max_frame_bytes 3400))    ; headroom leaves ~1352 bytes
    (let* ((model (cl-loop for i below 50
                           collect (list :kind 'para
                                         :text (format "paragraph %d" i))))
           (nodes (jetpacs-buffer-with-budget
                    (jetpacs-hypertext--emit model))))
      (should (< (length nodes) 51))
      (should (equal (plist-get (car (last nodes)) :text)
                     "… output truncated (surface budget)")))))

(ert-deftest jetpacs-hypertext-table-cell-cap ()
  "A DOM table past the welcome's `max_table_cells' keeps its monospace
fallback (nothing else in the tree reads that limit)."
  (let ((dom '(table nil
               (tr nil (td nil "a") (td nil "b") (td nil "c") (td nil "d"))
               (tr nil (td nil "e") (td nil "f") (td nil "g") (td nil "h"))
               (tr nil (td nil "i") (td nil "j") (td nil "k") (td nil "l")))))
    (should (jetpacs-hypertext--dom-table-rows dom))
    (jetpacs-hypertext-test--with-client (:limits '(:max_table_cells 10))
      (should-not (jetpacs-hypertext--dom-table-rows dom)))))

(ert-deftest jetpacs-hypertext-tables-stay-monospace-without-libxml ()
  "Positive knowledge: no libxml probe, no DOM pass — the model rides
through untouched and the monospace fallback survives."
  (cl-letf (((symbol-function 'jetpacs-hypertext--libxml-p) (lambda () nil)))
    (with-temp-buffer
      (rename-buffer "*jc3b-nolibxml*" t)
      (setq-local eww-data '(:source "<table><tr><td>x</td></tr></table>"))
      (let ((model (list '(:kind table :table-id 1 :text "x"))))
        (should (eq (jetpacs-hypertext--eww-resolve-tables
                     model (current-buffer))
                    model))))))

;; --- Registration guard ------------------------------------------------------

(ert-deftest jetpacs-hypertext-register-guard ()
  "Registering an umbrella mode is refused — dispatch is derived-mode-p,
so `special-mode' would claim occur, compilation, and Info."
  (should-error (jetpacs-hypertext-register-shr-mode 'special-mode))
  (should-error (jetpacs-hypertext-register-shr-mode 'text-mode)))

(provide 'jetpacs-hypertext-test)
;;; jetpacs-hypertext-test.el ends here
