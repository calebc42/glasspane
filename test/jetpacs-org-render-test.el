;;; jetpacs-org-render-test.el --- JA-5b: the org render skin -*- lexical-binding: t; -*-

;;; Commentary:

;; JA-5b's slice of the JA-5 exit gate (docs/PLAN-jetpacs-apps.md JA-5):
;; a fontified org fixture renders to a byte-asserted golden
;; (test/goldens/org-render.golden — regenerate by evaluating
;; `jetpacs-org-render-test--write-golden' after a reviewed change);
;; native upgrades charge the shared budgets (table cells against the
;; A2 aggregate, bytes against the frame allowance) and truncate
;; truthfully; images ship as data: URIs through the org root allowlist
;; with every refusal a silent degrade; the span-action arms mint taps
;; only where intended; and the two verbs run the sections gate order.
;; The TRAP fixture distills org_parser's test corpus — the render and
;; every span arm must survive all of it without signaling.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-org-render)

;;;; Fixtures

(defconst jetpacs-org-render-test--png
  (base64-decode-string
   "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
  "A 1x1 PNG, the deterministic image fixture.")

(defmacro jetpacs-org-render-test--with-file (var content &rest body)
  "Write CONTENT to a temp .org file in a fresh root; bind VAR; run BODY.
The file's directory becomes the sole `jetpacs-org-roots' entry and
gains an `img.png' (the constant 1x1 PNG).  The visiting buffer is
renamed deterministically so descriptor args and exposure keys are
byte-stable.  State is reset around BODY."
  (declare (indent 2))
  `(let* ((dir (file-name-as-directory
                (file-truename (make-temp-file "ja5-render" t))))
          (,var (expand-file-name "fixture.org" dir))
          (jetpacs-org-roots (list dir)))
     (with-temp-file ,var (insert ,content))
     (let ((coding-system-for-write 'binary))
       (write-region jetpacs-org-render-test--png nil
                     (expand-file-name "img.png" dir)))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buf (find-buffer-visiting ,var)))
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))
       (delete-directory dir t)
       (jetpacs-buffer-forget-exposed)
       (jetpacs-org-reset))))

(defun jetpacs-org-render-test--buffer (file)
  "The org buffer visiting FILE, fontified, deterministically named."
  (let ((buf (find-file-noselect file)))
    (with-current-buffer buf
      (unless (derived-mode-p 'org-mode) (org-mode))
      (rename-buffer "*ja5-golden*" t)
      (font-lock-ensure (point-min) (point-max)))
    buf))

(defmacro jetpacs-org-render-test--with-client (spec &rest body)
  "Attach a stub READY client per SPEC (:limits L :profiles P), run BODY."
  (declare (indent 1))
  `(let ((client (ebp-client-create
                  :receipt-file (make-temp-file "ja5-receipts"))))
     (setf (ebp-client-state client) 'ready)
     (when ,(plist-get spec :limits)
       (setf (ebp-client-limits client) ,(plist-get spec :limits)))
     (when ,(plist-get spec :profiles)
       (setf (ebp-client-profiles client) ,(plist-get spec :profiles)))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach))))

(defconst jetpacs-org-render-test--rich-profile
  '(:app (:node_types ["text" "rich_text" "image" "divider" "table"
                       "button" "row" "column"]
          :features ["image.data" "image.https"]))
  "A profile advertising everything the skin can emit.")

(defconst jetpacs-org-render-test--golden-content
  (concat "* Head\n"
          ":PROPERTIES:\n:ID: golden-1\n:END:\n"
          "Prose with *bold* words.\n\n"
          "- [ ] task one\n"
          "- [X] task two\n\n"
          "| Name | N |\n|------+---|\n| a    | 1 |\n| b    | 22 |\n\n"
          "-----\n\n"
          "#+CAPTION: The picture\n"
          "[[file:img.png][A picture]]\n")
  "The golden fixture: drawer, emphasis, checkboxes, table, rule, image.")

(defconst jetpacs-org-render-test--golden
  (expand-file-name "goldens/org-render.golden"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "The byte-asserted rendering golden.")

(defun jetpacs-org-render-test--render-golden ()
  "The golden fixture rendered to canonical JSON (offline: richer forms)."
  (jetpacs-org-render-test--with-file f jetpacs-org-render-test--golden-content
    (jetpacs-node->canonical-json
     (vconcat (jetpacs-org-render (jetpacs-org-render-test--buffer f))))))

(defun jetpacs-org-render-test--write-golden ()
  "Regenerate the golden from the fixture (run after a reviewed change).
The canonical JSON is a UNIBYTE string (UTF-8 bytes — the fold arrows
are multibyte content), so it is written and read back as raw bytes."
  (let ((coding-system-for-write 'binary))
    (with-temp-file jetpacs-org-render-test--golden
      (set-buffer-multibyte nil)
      (insert (jetpacs-org-render-test--render-golden)))))

(defun jetpacs-org-render-test--nodes-of (nodes type)
  "The members of NODES whose :t is TYPE."
  (seq-filter (lambda (n) (equal (plist-get n :t) type)) nodes))

;;;; The golden and the degrade guarantee

(ert-deftest jetpacs-org-render-golden ()
  "The fixture renders byte-identically to the reviewed golden."
  (should (file-readable-p jetpacs-org-render-test--golden))
  (should (equal (jetpacs-org-render-test--render-golden)
                 (with-temp-buffer
                   (set-buffer-multibyte nil)
                   (insert-file-contents-literally
                    jetpacs-org-render-test--golden)
                   (buffer-string)))))

(ert-deftest jetpacs-org-render-golden-shape ()
  "Structural spot-checks so a golden regen can't silently bless a hole:
one native table, one divider, one data: image with its caption, and
the app profile passes."
  (jetpacs-org-render-test--with-file f jetpacs-org-render-test--golden-content
    (let ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f))))
      (should (= 1 (length (jetpacs-org-render-test--nodes-of nodes "table"))))
      (should (= 1 (length (jetpacs-org-render-test--nodes-of nodes "divider"))))
      (let ((imgs (jetpacs-org-render-test--nodes-of nodes "image")))
        (should (= 1 (length imgs)))
        (should (string-prefix-p "data:image/png;base64,"
                                 (plist-get (car imgs) :url)))
        ;; RFC 4648: no whitespace anywhere in the wire form.
        (should-not (string-match-p "[ \t\n]" (plist-get (car imgs) :url))))
      (should (seq-find (lambda (n) (equal (plist-get n :text) "The picture"))
                        nodes))
      (should (jetpacs-check-profile (vconcat nodes) 'app)))))

(ert-deftest jetpacs-org-render-tier0-fallback-on-parse-error ()
  "A signaling upgrade pass degrades to the pure Tier-0 render —
the skin can subtract nothing."
  (jetpacs-org-render-test--with-file f jetpacs-org-render-test--golden-content
    (let ((buf (jetpacs-org-render-test--buffer f)))
      (cl-letf (((symbol-function 'org-element-parse-buffer)
                 (lambda (&rest _) (error "boom"))))
        (let ((nodes (jetpacs-org-render buf)))
          (should nodes)
          (should-not (jetpacs-org-render-test--nodes-of nodes "table"))
          (should (jetpacs-org-render-test--nodes-of nodes "rich_text")))))))

;;;; Budgets

(ert-deftest jetpacs-org-render-table-cells-spend-aggregate ()
  "A table the A2 cell allowance refuses is DROPPED with a truthful
caption — never emitted into GATE 5's whole-push refusal."
  (jetpacs-org-render-test--with-client
      (:limits '(:max_table_cells 4)
       :profiles jetpacs-org-render-test--rich-profile)
    (jetpacs-org-render-test--with-file f
        "| a | b | c |\n| d | e | f |\n"
      (let ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f))))
        (should-not (jetpacs-org-render-test--nodes-of nodes "table"))
        (should (seq-find (lambda (n)
                            (equal (plist-get n :text)
                                   "… output truncated (surface budget)"))
                          nodes))))))

(ert-deftest jetpacs-org-render-span-budget-truncates-with-caption ()
  "The skin joins the shared span aggregate: many lines under a tiny
`max_rich_spans' truncate with the Tier-0 caption, never over-emit."
  (jetpacs-org-render-test--with-client
      (:limits '(:max_rich_spans 3)
       :profiles jetpacs-org-render-test--rich-profile)
    (jetpacs-org-render-test--with-file f
        "line one\nline two\nline three\nline four\nline five\n"
      (let* ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f)))
             (spans (apply #'+ (mapcar (lambda (n)
                                         (length (append (plist-get n :spans)
                                                         nil)))
                                       (jetpacs-org-render-test--nodes-of
                                        nodes "rich_text")))))
        (should (<= spans 3))
        (should (seq-find (lambda (n)
                            (equal (plist-get n :text)
                                   "… output truncated (surface budget)"))
                          nodes))))))

(ert-deftest jetpacs-org-render-exposure-only-for-shipped-nodes ()
  "A checkbox whose line never survived the span budget is NOT exposed:
records mirror the wire, not the builder's attempt (SPEC 23.1)."
  (jetpacs-org-render-test--with-client
      (:limits '(:max_rich_spans 1)
       :profiles jetpacs-org-render-test--rich-profile)
    (jetpacs-org-render-test--with-file f
        "padding line\nmore padding\n- [ ] deep task\n"
      (let* ((buf (jetpacs-org-render-test--buffer f))
             (name (buffer-name buf))
             (pos (with-current-buffer buf
                    (goto-char (point-min))
                    (search-forward "[ ]")
                    (match-beginning 0))))
        (jetpacs-org-render buf)
        (should-not (jetpacs-buffer-exposed-p
                     name pos "jetpacs.org.checkbox"))))))

;;;; Tables

(ert-deftest jetpacs-org-render-table-aligns-cookie ()
  "Explicit <l>/<c>/<r> cookies win over the numeric heuristic."
  (should (equal (jetpacs-org-render--table-aligns
                  '(("h1" "h2" "h3") hline ("<l>" "<c>" "<r>")))
                 '("start" "center" "end"))))

(ert-deftest jetpacs-org-render-table-aligns-numeric-heuristic ()
  "Org's own rule: a mostly-numeric column right-aligns; all-start
collapses to nil so the node stays minimal."
  (should (equal (jetpacs-org-render--table-aligns
                  '(("name" "n") hline ("a" "1") ("b" "22") ("c" "x")))
                 '("start" "end")))
  (should-not (jetpacs-org-render--table-aligns
               '(("a" "b") hline ("c" "d")))))

(ert-deftest jetpacs-org-render-tablel-table-degrades-not-signals ()
  "A table.el table (even the 0-column `+-+') stays Tier-0 text."
  (jetpacs-org-render-test--with-file f
      "+---+---+\n| a | b |\n+---+---+\n\n+-+\n"
    (let ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f))))
      (should-not (jetpacs-org-render-test--nodes-of nodes "table"))
      (should (jetpacs-org-render-test--nodes-of nodes "rich_text")))))

;;;; Images

(ert-deftest jetpacs-org-render-image-https-passthrough ()
  "An https image link passes through for the device to fetch; http
never upgrades."
  (jetpacs-org-render-test--with-file f
      "[[https://example.org/pic.png]]\n\n[[http://example.org/pic.png]]\n"
    (let* ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f)))
           (imgs (jetpacs-org-render-test--nodes-of nodes "image")))
      (should (= 1 (length imgs)))
      (should (equal (plist-get (car imgs) :url)
                     "https://example.org/pic.png")))))

(ert-deftest jetpacs-org-render-image-outside-roots-degrades ()
  "A link to an image OUTSIDE the org roots is never read: the
paragraph stays text.  The allowlist governs what the render may
touch, not what the file may mention."
  (jetpacs-org-render-test--with-file f "[[file:img.png]]\n"
    ;; Rebind roots elsewhere AFTER fixture creation: the file itself
    ;; now sits outside the allowlist, so its image must not resolve.
    (let* ((other (file-name-as-directory
                   (file-truename (make-temp-file "ja5-other" t))))
           (jetpacs-org-roots (list other)))
      (unwind-protect
          (let ((nodes (jetpacs-org-render
                        (jetpacs-org-render-test--buffer f))))
            (should-not (jetpacs-org-render-test--nodes-of nodes "image")))
        (delete-directory other t)))))

(ert-deftest jetpacs-org-render-image-oversize-degrades ()
  "An image over `max_image_bytes' degrades to text (bounded pre-read)."
  (jetpacs-org-render-test--with-client
      (:limits '(:max_image_bytes 8)
       :profiles jetpacs-org-render-test--rich-profile)
    (jetpacs-org-render-test--with-file f "[[file:img.png]]\n"
      (let ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f))))
        (should-not (jetpacs-org-render-test--nodes-of nodes "image"))))))

(ert-deftest jetpacs-org-render-image-non-regular-file-guarded ()
  "The `file-regular-p' guard is consulted before any read — a FIFO
under a root would hang `insert-file-contents' forever (JA-6 P1-4)."
  (jetpacs-org-render-test--with-file f "[[file:img.png]]\n"
    (let ((read-attempted nil))
      (cl-letf (((symbol-function 'file-regular-p) (lambda (_) nil))
                ((symbol-function 'jetpacs-hypertext-file-bytes)
                 (lambda (_) (setq read-attempted t) nil)))
        (let ((nodes (jetpacs-org-render (jetpacs-org-render-test--buffer f))))
          (should-not (jetpacs-org-render-test--nodes-of nodes "image"))
          (should-not read-attempted))))))

;;;; Span-action arms

(ert-deftest jetpacs-org-render-fold-taps-on-drawer-and-block ()
  "Drawer and block header lines mint `jetpacs.buffer.fold' taps —
the collapse affordance Tier-0's outline detection cannot see."
  (jetpacs-org-render-test--with-file f
      (concat "* H\n"
              ":LOGBOOK:\n- Note taken\n:END:\n"
              "#+begin_example\nbody\n#+end_example\n")
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf)))
      (jetpacs-org-render buf)
      (with-current-buffer buf
        (org-with-wide-buffer
         (goto-char (point-min))
         (search-forward ":LOGBOOK:")
         (should (jetpacs-buffer-exposed-p
                  name (match-beginning 0) "jetpacs.buffer.fold"))
         (search-forward "#+begin_example")
         (should (jetpacs-buffer-exposed-p
                  name (match-beginning 0) "jetpacs.buffer.fold")))))))

(ert-deftest jetpacs-org-render-checkbox-tap-exposed-brackets-only ()
  "The checkbox arm exposes the bracket run; cookies, footnote refs and
timestamps in the same bracket zoo mint nothing (their arms come later,
and the cookie is never a checkbox)."
  (jetpacs-org-render-test--with-file f
      "* Zoo [1/2]\n- [ ] real one\n- done [50%] [2026-01-01 Thu]\n"
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf)))
      (jetpacs-org-render buf)
      (with-current-buffer buf
        (org-with-wide-buffer
         (goto-char (point-min))
         (search-forward "[ ]")
         (should (jetpacs-buffer-exposed-p
                  name (match-beginning 0) "jetpacs.org.checkbox"))
         (goto-char (point-min))
         (search-forward "[1/2]")
         (should-not (jetpacs-buffer-exposed-p
                      name (match-beginning 0) "jetpacs.org.checkbox"))
         (search-forward "[50%]")
         (should-not (jetpacs-buffer-exposed-p
                      name (match-beginning 0) "jetpacs.org.checkbox")))))))

;;;; The trap fixture (org_parser's distilled corpus)

(defconst jetpacs-org-render-test--trap
  (concat
   "* AB:CD: not tags\n"
   "* real :tags: here :a:b:\n"
   "** \n"
   "* A $1\nbody\n* B\n1$ more\n"
   "a/b\nc/d not italic\n"
   "+foo\nbar+ one-newline strike\n"
   "+- Some text here+\n- Some text here\n"
   "~foo *bar* baz~ opaque\n"
   "/foo *bar /baz// nest\n"
   "30. [@30] foo\n"
   "   - bar :: baz\n"
   "     blah\n"
   "   - [ ] *bazinga*\n"
   "- foo\n  #+begin_src\n"
   "- drawer item\n  :foo:\n\n\n  :end:\n"
   "SCHEDULED: \n"
   "* stamps\nSCHEDULED: <2026-07-05 Sun 8:34 +1w/2w>\n"
   "[2026-07-04 Sat .+1w --12d]\n"
   "<2026-07-05 Sun 18:34-19:35>\n"
   "[2026-07-01 Wed]--[2026-07-03 Fri]\n"
   "<%%(diary-float t 4 2)>\n"
   ":LOGBOOK:\n"
   "CLOCK: [2026-07-23 Thu 09:30]--[2026-07-23 Thu 10:19] =>  0:49\n"
   ":END:\n"
   ":PROPERTIES:\n:foo:bar\n:good: value\n:あ: unicode\n:END:\n"
   ":outer:\n:inner:\n:end:\n:end:\n"
   "- [ ] zoo [X] [-] [1/2] [50%] [fn:1] [fn::inline] [cite:@k] "
   "[[l][d]] [2020-01-01] [@30] [] [1/2%] [50%50]\n"
   "-----BEGIN PGP MESSAGE-----\n"
   "not a rule above\n"
   "[[*\\[wtf\\] what?][boxes\u200b]]\n"
   "a_a..a sub a_{a1_{b2}} nest a_* star \\sup1 \\frac12 \\foobar{}\n"
   "[fn:1] a definition\n\nstill the definition\n")
  "org_parser's distilled edge cases — render must survive all of it.")

(ert-deftest jetpacs-org-render-trap-fixture-never-signals ()
  "The full skin over the trap fixture: no signal, taps only where
intended.  `-----BEGIN PGP' must NOT become a divider; the one real
checkbox in the bracket zoo is the only checkbox exposure on its line."
  (jetpacs-org-render-test--with-file f jetpacs-org-render-test--trap
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf))
           (nodes (jetpacs-org-render buf)))
      (should nodes)
      ;; No horizontal rule in the fixture: the PGP armor is text.
      (should-not (jetpacs-org-render-test--nodes-of nodes "divider"))
      (with-current-buffer buf
        (org-with-wide-buffer
         ;; The bracket zoo line is a list item, so exactly ONE checkbox
         ;; exists on it — the item's own leading box; the mid-line
         ;; brackets ([X] [-] cookies footnotes links dates) mint nothing.
         (goto-char (point-min))
         (search-forward "- [ ] zoo")
         (let* ((eol (line-end-position))
                (bol (line-beginning-position))
                (exposed 0))
           (cl-loop for p from bol below eol
                    do (when (jetpacs-buffer-exposed-p
                              name p "jetpacs.org.checkbox")
                         (cl-incf exposed)))
           (should (= exposed 1))))))))

(ert-deftest jetpacs-org-render-folded-upgrades-skipped ()
  "A table inside a FOLDED subtree never upgrades — Tier 0 drops the
hidden lines and the upgrade pass must not resurrect them — while a
caption-less standalone image link (whose element BEGINS at org's
hidden `[[' bracket) still upgrades: hidden-ness is judged over the
whole content extent, not the first char."
  (jetpacs-org-render-test--with-file f
      (concat "* Open\n[[file:img.png]]\n"
              "* Folded\n| hidden | table |\n| a | b |\n")
    (let ((buf (jetpacs-org-render-test--buffer f)))
      (with-current-buffer buf
        (org-with-wide-buffer
         (goto-char (point-min))
         (search-forward "* Folded")
         (org-fold-hide-subtree))
        (font-lock-ensure (point-min) (point-max)))
      (let ((nodes (jetpacs-org-render buf)))
        (should (= 1 (length (jetpacs-org-render-test--nodes-of
                              nodes "image"))))
        (should-not (jetpacs-org-render-test--nodes-of nodes "table"))))))

;;;; The two verbs

(defconst jetpacs-org-render-test--params '(:surface "app:ja5-test")
  "Minimal event params for driving handlers directly.")

(ert-deftest jetpacs-org-render-checkbox-effect-and-cookie-update ()
  "An exposed checkbox tap toggles the box, updates the parent cookie
through org itself, and the deferred save lands the change on disk."
  (jetpacs-org-render-test--with-file f
      "* Tasks [/]\n- [ ] one\n- [X] two\n"
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf))
           (pos (with-current-buffer buf
                  (goto-char (point-min))
                  (search-forward "[ ]")
                  (match-beginning 0))))
      (jetpacs-org-render buf)
      (should (eq 'accepted
                  (jetpacs-org-render--checkbox
                   (list :buffer name :pos pos)
                   jetpacs-org-render-test--params)))
      (with-current-buffer buf
        (org-with-wide-buffer
         (goto-char (point-min))
         (should (search-forward "- [X] one" nil t))
         (goto-char (point-min))
         (should (search-forward "[2/2]" nil t))))
      ;; Flush the idle save by hand (batch has no idle time) and
      ;; confirm the mutation reached disk.
      (jetpacs-org--save-now buf)
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (should (search-forward "- [X] one" nil t))))))

(ert-deftest jetpacs-org-render-checkbox-stale-when-moved ()
  "An armed position that no longer holds a checkbox answers `stale' —
the re-verify runs before any mutation."
  (jetpacs-org-render-test--with-file f "- [ ] one\n"
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf))
           (pos (with-current-buffer buf
                  (goto-char (point-min))
                  (search-forward "[ ]")
                  (match-beginning 0))))
      (jetpacs-org-render buf)
      (with-current-buffer buf
        (goto-char (point-min))
        (insert "shift everything\n"))
      (should (eq 'stale
                  (jetpacs-org-render--checkbox
                   (list :buffer name :pos pos)
                   jetpacs-org-render-test--params))))))

(ert-deftest jetpacs-org-render-checkbox-rejected-when-unexposed ()
  "A position this render never offered is outside the trust boundary."
  (jetpacs-org-render-test--with-file f "- [ ] one\n"
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf))
           (pos (with-current-buffer buf
                  (goto-char (point-min))
                  (search-forward "[ ]")
                  (match-beginning 0))))
      (ignore buf)
      ;; No render ran since the last reset: nothing is exposed.
      (jetpacs-buffer-forget-exposed)
      (should (eq 'rejected
                  (jetpacs-org-render--checkbox
                   (list :buffer name :pos pos)
                   jetpacs-org-render-test--params)))
      ;; Shape gates: a float pos is rejected outright (integerp, the
      ;; sections lesson), as is a dead buffer name.
      (should (eq 'rejected
                  (jetpacs-org-render--checkbox
                   (list :buffer name :pos (float pos))
                   jetpacs-org-render-test--params)))
      (should (eq 'rejected
                  (jetpacs-org-render--checkbox
                   (list :buffer "*no such buffer*" :pos pos)
                   jetpacs-org-render-test--params))))))

(ert-deftest jetpacs-org-render-widen-affordance-and-gate ()
  "A narrowed buffer renders the widen button and exposes the verb;
the handler widens only what the render offered."
  (jetpacs-org-render-test--with-file f
      "* One\nbody one\n* Two\nbody two\n"
    (let* ((buf (jetpacs-org-render-test--buffer f))
           (name (buffer-name buf)))
      ;; Unexposed first: rejected.
      (jetpacs-buffer-forget-exposed)
      (should (eq 'rejected
                  (jetpacs-org-render--widen
                   (list :buffer name)
                   jetpacs-org-render-test--params)))
      (with-current-buffer buf
        (goto-char (point-min))
        (org-narrow-to-subtree))
      (let ((nodes (jetpacs-org-render buf)))
        (should (equal (plist-get (car nodes) :t) "button"))
        (should (jetpacs-buffer-exposed-buffer-p name "jetpacs.org.widen")))
      (should (eq 'accepted
                  (jetpacs-org-render--widen
                   (list :buffer name)
                   jetpacs-org-render-test--params)))
      (with-current-buffer buf
        (should-not (buffer-narrowed-p))))))

;;;; LaTeX on jetpacs-async (JA-5c)

(defconst jetpacs-org-render-test--latex-content
  "before\n\\begin{equation}\ne = mc^2\n\\end{equation}\nafter\n"
  "One LaTeX environment between two prose lines.")

(defmacro jetpacs-org-render-test--with-latex-stub (counter &rest body)
  "Stub `org-create-formula-image' to write the constant PNG; run BODY.
COUNTER (a symbol) is bound to a counter cell incremented per compile."
  (declare (indent 1))
  `(let ((,counter (list 0)))
     (cl-letf (((symbol-function 'org-create-formula-image)
                (lambda (_string tofile _options _buffer &optional _type)
                  (cl-incf (car ,counter))
                  (let ((coding-system-for-write 'binary))
                    (write-region jetpacs-org-render-test--png nil tofile))))
               ;; Pin the process config so the png gate passes without
               ;; a TeX toolchain installed.
               ((symbol-value 'org-preview-latex-default-process) 'dvipng))
       (unwind-protect
           (progn ,@body)
         (jetpacs-async-reset)
         (jetpacs-org-render-reset)))))

(ert-deftest jetpacs-org-render-latex-off-dispatch-extent-then-ready ()
  "The render never compiles inline: the first pass splices a pending
affordance and queues the compile; the drain (a timer in production)
compiles ONCE; the re-render ships the width-capped data: image."
  (jetpacs-org-render-test--with-latex-stub compiles
    (jetpacs-org-render-test--with-file f
        jetpacs-org-render-test--latex-content
      (let* ((buf (jetpacs-org-render-test--buffer f))
             (nodes (jetpacs-org-render buf)))
        ;; Pending: no compile ran on the render stack.
        (should (= 0 (car compiles)))
        (should (= 1 (length jetpacs-org-render--latex-queue)))
        (should-not (jetpacs-org-render-test--nodes-of nodes "image"))
        ;; One drain tick = one compile.
        (jetpacs-org-render--latex-drain)
        (should (= 1 (car compiles)))
        (let* ((nodes (jetpacs-org-render buf))
               (imgs (jetpacs-org-render-test--nodes-of nodes "image")))
          (should (= 1 (length imgs)))
          (should (string-prefix-p "data:image/png;base64,"
                                   (plist-get (car imgs) :url)))
          ;; 1x1 fixture PNG: width 1, under the 340 cap.
          (should (equal 1 (plist-get (car imgs) :width))))))))

(ert-deftest jetpacs-org-render-latex-memo-survives-async-eviction ()
  "The module memo, not the async table, is the durable cache: after a
full async reset (the global eviction sweep's worst case) the loader
answers from the memo without recompiling."
  (jetpacs-org-render-test--with-latex-stub compiles
    (jetpacs-org-render-test--with-file f
        jetpacs-org-render-test--latex-content
      (let ((buf (jetpacs-org-render-test--buffer f)))
        (jetpacs-org-render buf)
        (jetpacs-org-render--latex-drain)
        (jetpacs-org-render buf)          ; ready
        (should (= 1 (car compiles)))
        ;; The sweep: async cache gone, memo intact.
        (jetpacs-async-reset)
        ;; First post-sweep render re-reports pending by the async
        ;; contract, but the loader resolved synchronously from the
        ;; memo — no queue entry, no compile.
        (jetpacs-org-render buf)
        (should (= 0 (length jetpacs-org-render--latex-queue)))
        (should (= 1 (car compiles)))
        (let ((nodes (jetpacs-org-render buf)))
          (should (= 1 (length (jetpacs-org-render-test--nodes-of
                                nodes "image")))))))))

(ert-deftest jetpacs-org-render-latex-fail-memoised ()
  "A failed compile memoises `fail': the environment renders a truthful
caption and the toolchain is never re-run for that fragment."
  (jetpacs-org-render-test--with-latex-stub compiles
    (cl-letf (((symbol-function 'org-create-formula-image)
               (lambda (&rest _)
                 (cl-incf (car compiles))
                 (error "no toolchain"))))
      (jetpacs-org-render-test--with-file f
          jetpacs-org-render-test--latex-content
        (let ((buf (jetpacs-org-render-test--buffer f)))
          (jetpacs-org-render buf)
          (jetpacs-org-render--latex-drain)
          (should (= 1 (car compiles)))
          (let ((nodes (jetpacs-org-render buf)))
            (should (seq-find (lambda (n)
                                (equal (plist-get n :text) "[LaTeX failed]"))
                              nodes)))
          ;; Async swept, memo remembers the failure: no second attempt.
          (jetpacs-async-reset)
          (jetpacs-org-render buf)
          (should (= 0 (length jetpacs-org-render--latex-queue)))
          (should (= 1 (car compiles))))))))

(ert-deftest jetpacs-org-render-latex-png-only-gate ()
  "A non-PNG preview process leaves the environment as styled text —
SVG is an active format SPEC 17.2 rejects, and the user's configured
process is never silently overridden."
  (jetpacs-org-render-test--with-latex-stub compiles
    (let ((org-preview-latex-default-process 'dvisvgm))
      (jetpacs-org-render-test--with-file f
          jetpacs-org-render-test--latex-content
        (let* ((buf (jetpacs-org-render-test--buffer f))
               (nodes (jetpacs-org-render buf)))
          (should (= 0 (car compiles)))
          (should-not jetpacs-org-render--latex-queue)
          (should-not (jetpacs-org-render-test--nodes-of nodes "image"))
          (should (seq-find
                   (lambda (n)
                     (seq-find (lambda (s)
                                 (string-match-p "\\\\begin{equation}"
                                                 (or (plist-get s :text) "")))
                               (append (plist-get n :spans) nil)))
                   (jetpacs-org-render-test--nodes-of nodes "rich_text"))))))))

(ert-deftest jetpacs-org-render-latex-eviction-cleanup-dequeues ()
  "An evicted async entry dequeues its un-started compile via the
cleanup thunk — the drain never burns a tick on a view nobody shows."
  (jetpacs-org-render-test--with-latex-stub compiles
    (jetpacs-org-render-test--with-file f
        jetpacs-org-render-test--latex-content
      (let ((buf (jetpacs-org-render-test--buffer f)))
        (jetpacs-org-render buf)
        (should (= 1 (length jetpacs-org-render--latex-queue)))
        (jetpacs-async-reset)             ; sweep runs the cancel thunks
        (should (= 0 (length jetpacs-org-render--latex-queue)))
        (should (= 0 (car compiles)))))))

(provide 'jetpacs-org-render-test)
;;; jetpacs-org-render-test.el ends here
