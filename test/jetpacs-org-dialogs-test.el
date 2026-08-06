;;; jetpacs-org-dialogs-test.el --- JA-5d: footnote + header sheet -*- lexical-binding: t; -*-

;;; Commentary:

;; JA-5d's slice of the JA-5 exit gate: every dialog spec passes the
;; DIALOG profile and carries only drop-mode remote descriptors (SPEC
;; 18.1); dialog ids are fresh per press; the sheet's submitted value is
;; re-validated against a freshly built candidate list (23.2); the
;; mutations ride the JA-4 engine (cycle flushes the log note, duplicate
;; strips IDs, narrow/widen round-trips); Archive is a token-addressed
;; remote descriptor WITH the 14.1 confirm whose replace-set sweep
;; answers a stale sheet honestly; tags write through the charset
;; filter; and the one bridged flow (Refile) is can-bridge gated.
;;
;; Harness: a recorder replaces `ebp-client-dialog-show', capturing
;; (ID SPEC STYLE CALLBACK) so tests inspect specs and drive callbacks
;; directly — no wire, no Companion.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-org-render)   ; pulls jetpacs-org-dialogs

;;;; Harness

(defvar jetpacs-org-dialogs-test--shown nil
  "Recorded dialogs, newest first: (:id ID :spec S :style ST :callback CB).")

(defmacro jetpacs-org-dialogs-test--with-env (&rest body)
  "Stub client (ready, dialog grant, rich profile) + dialog recorder."
  (declare (indent 0))
  `(let ((jetpacs-org-dialogs-test--shown nil)
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ja5d-receipts"))))
     (setf (ebp-client-state client) 'ready
           (ebp-client-granted client) ["surfaces.dialog"]
           (ebp-client-limits client) '(:max_rich_spans 4096
                                        :max_frame_bytes 4194304)
           (ebp-client-profiles client)
           '(:app (:node_types ["text" "rich_text" "image" "divider"
                                "table" "button" "row" "column"]
                   :features [])
             :dialog (:node_types ["text" "rich_text" "button" "row"
                                   "column" "text_input" "enum_list"
                                   "date_button" "time_button" "divider"]
                      :features [])))
     (cl-letf (((symbol-function 'ebp-client-dialog-show)
                (cl-function
                 (lambda (_client id spec &key style callback)
                   (push (list :id id :spec spec :style style
                               :callback callback)
                         jetpacs-org-dialogs-test--shown)
                   (format "req-%d" (length jetpacs-org-dialogs-test--shown))))))
       (unwind-protect
           (progn (jetpacs-attach client) ,@body)
         (jetpacs-detach)
         (jetpacs-org-dialogs-reset)))))

(defmacro jetpacs-org-dialogs-test--with-file (var content &rest body)
  "The render-test fixture shape: temp .org under a fresh root."
  (declare (indent 2))
  `(let* ((dir (file-name-as-directory
                (file-truename (make-temp-file "ja5d" t))))
          (,var (expand-file-name "fixture.org" dir))
          (ebp-org-roots (list dir)))
     (with-temp-file ,var (insert ,content))
     (unwind-protect
         (progn ,@body)
       (dolist (name (list ,var (concat ,var "_archive")))
         (when-let* ((buf (find-buffer-visiting name)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory dir t)
       (jetpacs-buffer-forget-exposed)
       (ebp-org-reset))))

(defun jetpacs-org-dialogs-test--buffer (file)
  (let ((buf (find-file-noselect file)))
    (with-current-buffer buf
      (unless (derived-mode-p 'org-mode) (org-mode))
      (font-lock-ensure (point-min) (point-max)))
    buf))

(defun jetpacs-org-dialogs-test--ref (buf headline)
  (with-current-buffer buf
    (org-with-wide-buffer
     (goto-char (point-min))
     (search-forward headline)
     (ebp-org-ref-at-point))))

(defconst jetpacs-org-dialogs-test--params '(:surface "app:ja5d")
  "Minimal event params for driving handlers and dispatches.")

(defun jetpacs-org-dialogs-test--last ()
  (car jetpacs-org-dialogs-test--shown))

(defun jetpacs-org-dialogs-test--descriptors (node)
  "Every ActionDescriptor reachable in NODE (on_tap + on_pick, deep)."
  (let (out)
    (cl-labels
        ((walk (n)
           (when (consp n)
             (dolist (hook '(:on_tap :on_pick))
               (when-let* ((d (plist-get n hook))) (push d out)))
             (dolist (s (append (plist-get n :spans) nil))
               (when-let* ((d (plist-get s :on_tap))) (push d out)))
             (dolist (c (append (plist-get n :children) nil))
               (walk c)))))
      (walk node))
    out))

(defconst jetpacs-org-dialogs-test--sheet-fixture
  "* TODO Parent :old:\n:PROPERTIES:\n:ID: dup-me\n:END:\nBody.\n** Child\n* Other\n")

(defun jetpacs-org-dialogs-test--show-sheet (buf &optional headline)
  "Drive the sheet for HEADLINE (default Parent); return its ref."
  (let ((ref (jetpacs-org-dialogs-test--ref buf (or headline "Parent"))))
    (jetpacs-org-dialogs--show-sheet buf (plist-get ref :pos)
                                     jetpacs-org-dialogs-test--params)
    ref))

;;;; Profile + descriptor discipline

(ert-deftest jetpacs-org-dialogs-specs-pass-dialog-profile ()
  "EVERY spec this module can show passes the reference dialog profile.
The runtime send is ungated (the sections/files precedent calls ebp
directly), so this pin is the conformance guarantee."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        (concat jetpacs-org-dialogs-test--sheet-fixture
                "Text with a note[fn:1] here.\n\n[fn:1] The definition.\n")
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--show-sheet buf)))
        (jetpacs-org-dialogs--show-set-todo
         ref buf jetpacs-org-dialogs-test--params)
        (jetpacs-org-dialogs--show-priority
         ref buf jetpacs-org-dialogs-test--params)
        (jetpacs-org-dialogs--show-tags
         ref buf jetpacs-org-dialogs-test--params)
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (search-forward "note[fn:1]")
           (jetpacs-org-dialogs--show-footnote
            buf (- (point) 6) jetpacs-org-dialogs-test--params)))
        (should (= 5 (length jetpacs-org-dialogs-test--shown)))
        (dolist (shown jetpacs-org-dialogs-test--shown)
          (should (jetpacs-check-profile (plist-get shown :spec) 'dialog)))))))

(ert-deftest jetpacs-org-dialogs-remote-descriptors-are-drop ()
  "SPEC 18.1: every remote descriptor inside a dialog is drop-mode."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (jetpacs-org-dialogs-test--show-sheet buf)
        (dolist (d (jetpacs-org-dialogs-test--descriptors
                    (plist-get (jetpacs-org-dialogs-test--last) :spec)))
          (should-not (member (plist-get d :when_offline)
                              '("queue" "wake"))))))))

(ert-deftest jetpacs-org-dialogs-fresh-ids-per-press ()
  "Two presses on the same heading get DIFFERENT dialog ids —
18.1 answers a reused outstanding id with 1201."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (jetpacs-org-dialogs-test--show-sheet buf)
        (jetpacs-org-dialogs-test--show-sheet buf)
        (pcase-let ((`(,a ,b) jetpacs-org-dialogs-test--shown))
          (should-not (equal (plist-get a :id) (plist-get b :id))))))))

(ert-deftest jetpacs-org-dialogs-sheet-style-and-title ()
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (jetpacs-org-dialogs-test--show-sheet buf)
        (let ((shown (jetpacs-org-dialogs-test--last)))
          (should (equal (plist-get shown :style) "sheet"))
          (should (seq-find
                   (lambda (c) (equal (plist-get c :text) "Parent"))
                   (append (plist-get (plist-get shown :spec) :children)
                           nil))))))))

;;;; Sheet dispatch

(ert-deftest jetpacs-org-dialogs-sheet-dispatch-validates-value ()
  "A submitted value the sheet would not offer NOW mutates nothing."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent"))
             (before (with-current-buffer buf (buffer-string))))
        (jetpacs-org-dialogs--sheet-dispatch
         ref buf "evil-value" jetpacs-org-dialogs-test--params)
        ;; "widen" is not offered on a wide buffer either.
        (jetpacs-org-dialogs--sheet-dispatch
         ref buf "widen" jetpacs-org-dialogs-test--params)
        (should (equal before
                       (with-current-buffer buf (buffer-string))))))))

(ert-deftest jetpacs-org-dialogs-cycle-todo-through-the-engine ()
  "The todo arm rides `ebp-org-toggle-todo' (never raw `org-todo')."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--sheet-dispatch
         ref buf "todo" jetpacs-org-dialogs-test--params)
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should (search-forward "* DONE Parent" nil t))))))))

(ert-deftest jetpacs-org-dialogs-duplicate-strips-ids ()
  "Duplicate copies the subtree; the copy never shares org-id identity."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--sheet-dispatch
         ref buf "duplicate" jetpacs-org-dialogs-test--params)
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should (= 2 (count-matches "^\\* TODO Parent")))
           (should (= 1 (count-matches ":ID: dup-me")))))))))

(ert-deftest jetpacs-org-dialogs-narrow-widen-roundtrip ()
  "Narrow narrows (never inside `org-with-wide-buffer' — the poc
lesson), the candidate list flips to Widen, and widen widens."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (should (assoc "narrow"
                       (jetpacs-org-dialogs--sheet-candidates ref buf)))
        (jetpacs-org-dialogs--sheet-dispatch
         ref buf "narrow" jetpacs-org-dialogs-test--params)
        (with-current-buffer buf
          (should (buffer-narrowed-p))
          (should-not (save-excursion (goto-char (point-min))
                                      (search-forward "* Other" nil t))))
        (should (assoc "widen"
                       (jetpacs-org-dialogs--sheet-candidates ref buf)))
        (jetpacs-org-dialogs--sheet-dispatch
         ref buf "widen" jetpacs-org-dialogs-test--params)
        (with-current-buffer buf
          (should-not (buffer-narrowed-p)))))))

;;;; Archive

(ert-deftest jetpacs-org-dialogs-archive-confirm-present ()
  "Archive rides a remote descriptor with the 14.1 confirm and a token
— never a position, never confirm-less (the poc archived bare)."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (jetpacs-org-dialogs-test--show-sheet buf)
        (let* ((spec (plist-get (jetpacs-org-dialogs-test--last) :spec))
               (archive (seq-find
                         (lambda (d) (equal (plist-get d :action)
                                            "jetpacs.org.archive"))
                         (jetpacs-org-dialogs-test--descriptors spec))))
          (should archive)
          (should (stringp (plist-get archive :confirm)))
          (should (stringp (plist-get (plist-get archive :args) :token)))
          (should-not (plist-get (plist-get archive :args) :pos)))))))

(ert-deftest jetpacs-org-dialogs-archive-effect-and-file ()
  "An armed token archives the subtree into the archive file, saves it
(the poc ignored `org-archive-subtree-save-file-p'), and answers
`accepted'; the spent sheet is abandoned."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (abandoned nil))
        (cl-letf (((symbol-function 'ebp-client-abandon)
                   (lambda (_c id) (push id abandoned))))
          (jetpacs-org-dialogs-test--show-sheet buf)
          (let ((token (plist-get jetpacs-org-dialogs--sheet :token)))
            (should (eq 'accepted
                        (jetpacs-org-dialogs--archive
                         (list :token token)
                         jetpacs-org-dialogs-test--params)))
            (should (equal abandoned '("req-1")))
            (should-not jetpacs-org-dialogs--sheet)))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should-not (search-forward "* TODO Parent" nil t))))
        (should (file-exists-p (concat f "_archive")))
        (with-temp-buffer
          (insert-file-contents (concat f "_archive"))
          (goto-char (point-min))
          (should (search-forward "Parent" nil t)))))))

(ert-deftest jetpacs-org-dialogs-archive-token-stale-after-sweep ()
  "A second sheet re-mints the set; the first sheet's Archive token
answers `stale' — the replace-set sweep keeping old dialogs honest."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (jetpacs-org-dialogs-test--show-sheet buf)
        (let ((old-token (plist-get jetpacs-org-dialogs--sheet :token)))
          (jetpacs-org-dialogs-test--show-sheet buf "Other")
          (should (eq 'stale
                      (jetpacs-org-dialogs--archive
                       (list :token old-token)
                       jetpacs-org-dialogs-test--params))))
        ;; Shape gate.
        (should (eq 'rejected
                    (jetpacs-org-dialogs--archive
                     '(:token 42) jetpacs-org-dialogs-test--params)))))))

;;;; Chained dialogs

(defun jetpacs-org-dialogs-test--submit (shown value &optional fields)
  "Drive SHOWN's callback as a submit of VALUE (+FIELDS plist)."
  (funcall (plist-get shown :callback)
           "submitted"
           (append (list :status "submitted" :value value)
                   (when fields (list :fields fields)))
           nil))

(ert-deftest jetpacs-org-dialogs-set-todo-validates-keyword ()
  "A keyword the buffer defines writes; an invented one writes nothing;
Clear clears."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--show-set-todo
         ref buf jetpacs-org-dialogs-test--params)
        (let ((shown (jetpacs-org-dialogs-test--last)))
          (jetpacs-org-dialogs-test--submit shown "NOSUCHSTATE")
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "* TODO Parent" nil t))))
          (jetpacs-org-dialogs-test--submit shown "DONE")
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "* DONE Parent" nil t))))
          (jetpacs-org-dialogs-test--submit shown "__none__")
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "* Parent" nil t)))))))))

(ert-deftest jetpacs-org-dialogs-priority-set-and-clear ()
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--show-priority
         ref buf jetpacs-org-dialogs-test--params)
        (let ((shown (jetpacs-org-dialogs-test--last)))
          (jetpacs-org-dialogs-test--submit shown "B")
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "[#B]" nil t))))
          ;; Out-of-range char: no write.
          (jetpacs-org-dialogs-test--submit shown "Z")
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "[#B]" nil t))))
          (jetpacs-org-dialogs-test--submit shown "__remove__")
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should-not (search-forward "[#" nil t)))))))))

(ert-deftest jetpacs-org-dialogs-tags-write-through-charset-filter ()
  "The captured field writes org-charset tags; junk is filtered."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--show-tags
         ref buf jetpacs-org-dialogs-test--params)
        (let ((shown (jetpacs-org-dialogs-test--last)))
          ;; The seed carries the current tags.
          (should (seq-find (lambda (c)
                              (and (equal (plist-get c :t) "text_input")
                                   (equal (plist-get c :value) ":old:")))
                            (append (plist-get (plist-get shown :spec)
                                               :children)
                                    nil)))
          (jetpacs-org-dialogs-test--submit
           shown "save" '(:org-tags ":work:bad tag:next:"))
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (search-forward "* TODO Parent")
             (let ((tags (org-get-tags nil t)))
               (should (member "work" tags))
               (should (member "next" tags))
               (should-not (member "old" tags))
               (should-not (seq-find (lambda (tag)
                                       (string-match-p " " tag))
                                     tags))))))))))

;;;; Refile gating

(ert-deftest jetpacs-org-dialogs-refile-is-can-bridge-gated ()
  "With no bridge, the refile flow refuses LOUDLY (snackbar) instead of
raising a prompt nobody can answer (JA-6 audit P2 :284)."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent"))
             (notified nil)
             (prompted nil))
        (cl-letf (((symbol-function 'jetpacs-flow-begin)
                   (lambda (_surface fn) (funcall fn)))
                  ((symbol-function 'jetpacs-dialog-can-bridge-p)
                   (lambda () nil))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notified)))
                  ((symbol-function 'org-refile)
                   (lambda (&rest _) (setq prompted t))))
          (jetpacs-org-dialogs--sheet-dispatch
           ref buf "refile" jetpacs-org-dialogs-test--params)
          (should-not prompted)
          (should notified))))))

(ert-deftest jetpacs-org-dialogs-refile-runs-under-flow ()
  "With a bridge, refile runs at the resolved heading and the caches
and buffers are settled afterward."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent"))
             (refiled-at nil))
        (cl-letf (((symbol-function 'jetpacs-flow-begin)
                   (lambda (_surface fn) (funcall fn)))
                  ((symbol-function 'jetpacs-dialog-can-bridge-p)
                   (lambda () t))
                  ((symbol-function 'org-refile)
                   (lambda (&rest _)
                     (interactive)
                     (setq refiled-at (cons (buffer-name)
                                            (org-get-heading t t t t)))))
                  ((symbol-function 'org-save-all-org-buffers) #'ignore))
          (jetpacs-org-dialogs--sheet-dispatch
           ref buf "refile" jetpacs-org-dialogs-test--params)
          (should (equal (cdr refiled-at) "Parent")))))))

;;;; The tap handlers

(ert-deftest jetpacs-org-dialogs-tap-gates ()
  "The two dialog taps run the sections gate order: shape, exposure,
grant — and only then schedule the dialog."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        (concat jetpacs-org-dialogs-test--sheet-fixture
                "A note[fn:1] here.\n\n[fn:1] Def.\n")
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (name (buffer-name buf))
             ;; Exposure lands at span-RUN starts; the heading line's
             ;; first run starts at its bol (the stars), so that is the
             ;; position a real tap carries — the ref's :pos records
             ;; wherever point stood and may sit mid-run.
             (hpos (with-current-buffer buf
                     (org-with-wide-buffer
                      (goto-char (point-min))
                      (search-forward "* TODO Parent")
                      (line-beginning-position)))))
        ;; Unexposed: rejected.
        (jetpacs-buffer-forget-exposed)
        (should (eq 'rejected
                    (jetpacs-org-dialogs--heading-action
                     (list :buffer name :pos hpos)
                     jetpacs-org-dialogs-test--params)))
        ;; Rendered: the heading line is exposed for the sheet verb and
        ;; the footnote ref for the footnote verb.
        (jetpacs-org-render buf)
        (should (jetpacs-buffer-exposed-p name hpos "jetpacs.org.heading"))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (search-forward "note[fn:1]")
           (should (jetpacs-buffer-exposed-p
                    name (- (point) 6) "jetpacs.org.footnote"))))
        (should (eq 'accepted
                    (jetpacs-org-dialogs--heading-action
                     (list :buffer name :pos hpos)
                     jetpacs-org-dialogs-test--params)))
        ;; Float pos: rejected on shape (the sections lesson).
        (should (eq 'rejected
                    (jetpacs-org-dialogs--heading-action
                     (list :buffer name :pos (float hpos))
                     jetpacs-org-dialogs-test--params)))))))

;;;; The timestamp editor (JA-5e)

(ert-deftest jetpacs-org-dialogs-ts-seed-shapes ()
  "Seeding decodes date/time/repeater NODE-LEGALLY (times zero-padded,
AUDIT-ja5); a habit's /max tail and delay cookies ride the session so
a save preserves them; an absent stamp seeds today with no repeat."
  (let ((s (jetpacs-org-dialogs--ts-seed "<2026-07-05 Sun 8:34 +1w>")))
    (should (equal (plist-get s :date) "2026-07-05"))
    (should (equal (plist-get s :time) "08:34"))
    (should (equal (plist-get s :rep-type) "+"))
    (should (equal (plist-get s :rep-n) "1"))
    (should (equal (plist-get s :rep-unit) "w")))
  (let ((s (jetpacs-org-dialogs--ts-seed "<2026-07-05 Sun .+2d/4d>")))
    (should (equal (plist-get s :rep-type) ".+"))
    (should (equal (plist-get s :rep-n) "2"))
    (should (equal (plist-get s :rep-unit) "d"))
    (should (equal (plist-get s :rep-tail) "/4d")))
  ;; A delay cookie alone never seeds a repeater (the extractor's
  ;; deliberate exclusion) — but it is CARRIED, not dropped.
  (let ((s (jetpacs-org-dialogs--ts-seed "<2026-07-05 Sun -1d>")))
    (should (equal (plist-get s :rep-type) "none"))
    (should (equal (plist-get s :delay) "-1d")))
  (let ((s (jetpacs-org-dialogs--ts-seed nil)))
    (should (stringp (plist-get s :date)))
    (should-not (plist-get s :time))
    (should (equal (plist-get s :rep-type) "none"))))

(ert-deftest jetpacs-org-dialogs-ts-spec-passes-dialog-profile ()
  "The ts dialog is in-profile, its picks are drop-mode remote
descriptors carrying :sid/:field, and the repeater fields are the
capturable trio."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--ts-open
         (list :kind 'planning :ref ref :which "SCHEDULED")
         "<2026-07-05 Sun +1w>" jetpacs-org-dialogs-test--params)
        (let* ((shown (jetpacs-org-dialogs-test--last))
               (spec (plist-get shown :spec)))
          (should (jetpacs-check-profile spec 'dialog))
          (let ((picks (seq-filter
                        (lambda (d) (equal (plist-get d :action)
                                           "jetpacs.org.ts-pick"))
                        (jetpacs-org-dialogs-test--descriptors spec))))
            (should (= 2 (length picks)))
            (dolist (p picks)
              (should (stringp (plist-get (plist-get p :args) :sid)))
              (should (member (plist-get (plist-get p :args) :field)
                              '("date" "time")))
              (should-not (member (plist-get p :when_offline)
                                  '("queue" "wake"))))))))))

(ert-deftest jetpacs-org-dialogs-ts-pick-gates-and-represents ()
  "A pick must name a live session AND its current dialog; a good pick
stores the value, abandons the old dialog, and re-presents fresh."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--ts-open
         (list :kind 'planning :ref ref :which "SCHEDULED")
         nil jetpacs-org-dialogs-test--params)
        (let* ((sid (cl-loop for k being the hash-keys of
                             jetpacs-org-dialogs--ts-sessions
                             return k))
               (session (gethash sid jetpacs-org-dialogs--ts-sessions))
               (dialog-id (plist-get session :dialog-id))
               (abandoned nil))
          ;; Unknown session / wrong dialog / bad value shape.
          (should (eq 'stale (jetpacs-org-dialogs--ts-pick
                              '(:sid "ts-nope" :field "date"
                                :value "2026-01-01")
                              '(:dialog_id "x"))))
          (should (eq 'stale (jetpacs-org-dialogs--ts-pick
                              (list :sid sid :field "date"
                                    :value "2026-01-01")
                              '(:dialog_id "not-the-current-one"))))
          (should (eq 'rejected (jetpacs-org-dialogs--ts-pick
                                 (list :sid sid :field "date"
                                       :value "not-a-date")
                                 (list :dialog_id dialog-id))))
          ;; The good pick: immediate-fire the deferred re-present.
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat fn &rest args)
                       (apply fn args)))
                    ((symbol-function 'ebp-client-abandon)
                     (lambda (_c id) (push id abandoned))))
            (should (eq 'accepted (jetpacs-org-dialogs--ts-pick
                                   (list :sid sid :field "date"
                                         :value "2026-08-01")
                                   (list :dialog_id dialog-id)))))
          (should (equal abandoned
                         (list (plist-get session :request-id))))
          (let ((fresh (gethash sid jetpacs-org-dialogs--ts-sessions)))
            (should (equal (plist-get fresh :date) "2026-08-01"))
            (should-not (equal (plist-get fresh :dialog-id) dialog-id)))
          ;; Two dialogs shown: the original and the re-present.
          (should (= 2 (length jetpacs-org-dialogs-test--shown))))))))

(ert-deftest jetpacs-org-dialogs-ts-save-planning-and-repeater ()
  "Save writes the planning line through the engine's two-step cookie
surgery; the captured repeater fields override the seed; Clear removes."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--ts-open
         (list :kind 'planning :ref ref :which "SCHEDULED")
         nil jetpacs-org-dialogs-test--params)
        (let ((session (cl-loop for s being the hash-values of
                                jetpacs-org-dialogs--ts-sessions
                                return s)))
          (jetpacs-org-dialogs--ts-conclude
           (plist-put (copy-sequence session) :date "2026-08-02")
           "save"
           '(:ts-rep-type "+" :ts-rep-n "2" :ts-rep-unit "w")))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should (re-search-forward
                    "SCHEDULED: <2026-08-02 [A-Za-z]\\{3\\} \\+2w>"
                    nil t))))
        ;; Clear.
        (jetpacs-org-dialogs--ts-open
         (list :kind 'planning :ref ref :which "SCHEDULED")
         nil jetpacs-org-dialogs-test--params)
        (let ((session (cl-loop for s being the hash-values of
                                jetpacs-org-dialogs--ts-sessions
                                return s)))
          (jetpacs-org-dialogs--ts-conclude session "clear" nil))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should-not (search-forward "SCHEDULED:" nil t))))))))

(ert-deftest jetpacs-org-dialogs-ts-body-rewrite-guarded ()
  "A body stamp rewrites literally in place (bracket kept, day name
recomputed); a stamp that MOVED is a no-op plus a snackbar."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        "* H\nSee [2026-07-04 Sat] for details.\n"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (name (buffer-name buf))
             (pos (with-current-buffer buf
                    (org-with-wide-buffer
                     (goto-char (point-min))
                     (search-forward "[2026")
                     (match-beginning 0)))))
        (let ((session (list :target (list :kind 'body :buffer name
                                           :pos pos :bracket ?\[)
                             :params jetpacs-org-dialogs-test--params
                             :date "2026-12-25" :time "09:30"
                             :rep-type "none" :rep-n "1" :rep-unit "w")))
          (jetpacs-org-dialogs--ts-conclude session "save" nil)
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "[2026-12-25 Fri 09:30]" nil t))))
          ;; Shift the buffer: the recorded position no longer holds a
          ;; stamp — nothing is struck.
          (with-current-buffer buf
            (goto-char (point-min))
            (insert "shift\n"))
          (let ((before (with-current-buffer buf (buffer-string))))
            (jetpacs-org-dialogs--ts-conclude session "save" nil)
            (should (equal before
                           (with-current-buffer buf (buffer-string))))))))))

(ert-deftest jetpacs-org-dialogs-timestamp-tap-and-bare-keyword ()
  "A rendered stamp is exposed for the timestamp verb and its handler
accepts; a bare `SCHEDULED:' with no stamp exposes nothing (the
malformed-planning trap from org_parser)."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        "* H\nSCHEDULED: <2026-07-05 Sun>\nSCHEDULED: \nbody\n"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (name (buffer-name buf)))
        (jetpacs-org-render buf)
        (let ((pos (with-current-buffer buf
                     (org-with-wide-buffer
                      (goto-char (point-min))
                      (search-forward "<2026")
                      (match-beginning 0)))))
          (should (jetpacs-buffer-exposed-p
                   name pos "jetpacs.org.timestamp"))
          (should (eq 'accepted
                      (jetpacs-org-dialogs--timestamp-action
                       (list :buffer name :pos pos)
                       jetpacs-org-dialogs-test--params))))
        ;; The bare keyword line: no timestamp exposure anywhere on it.
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (search-forward "SCHEDULED: \n")
           (let ((bol (match-beginning 0)))
             (cl-loop for p from bol below (+ bol 11)
                      do (should-not
                          (jetpacs-buffer-exposed-p
                           name p "jetpacs.org.timestamp"))))))))))

;;;; The log-note dialog (JA-5e)

(ert-deftest jetpacs-org-dialogs-log-note-follows-a-cancelled-note ()
  "A toggle that cancels a free-text note is followed by the note
dialog; Save writes a LOGBOOK line `ebp-org-parse-logbook' reads
back; dismissing keeps today's cancel."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent"))
             (org-log-done 'note)
             ;; The write lands wherever `org-log-beginning' says — the
             ;; user's own config.  Configure the drawer so the engine
             ;; parser assertion below applies (default nil = body).
             (org-log-into-drawer t))
        ;; Immediate-fire only the note dialog's deferral (no ts-open
        ;; in this path, so no sweep-timer recursion).
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (_time _repeat fn &rest args) (apply fn args))))
          (jetpacs-org-dialogs--sheet-dispatch
           ref buf "todo" jetpacs-org-dialogs-test--params))
        (let ((shown (jetpacs-org-dialogs-test--last)))
          (should shown)
          (should (jetpacs-check-profile (plist-get shown :spec) 'dialog))
          (jetpacs-org-dialogs-test--submit
           shown "save" '(:org-note "Finished on the tablet"))
          (with-current-buffer buf
            (org-with-wide-buffer
             (goto-char (point-min))
             (should (search-forward "- Note taken on [" nil t))
             (should (search-forward "Finished on the tablet" nil t))
             ;; The engine's parser reads the line back as a note.
             (goto-char (point-min))
             (search-forward "* DONE Parent")
             (let ((entries (ebp-org-logbook-entries (point))))
               (should (seq-find
                        (lambda (e)
                          (and (eq (plist-get e :type) 'note)
                               (string-match-p "Finished on the tablet"
                                               (plist-get e :content))))
                        entries))))))))))

;;;; add-heading (JA-5f)

(ert-deftest jetpacs-org-dialogs-add-heading-gates ()
  "Unexposed, non-file and outside-roots buffers are rejected; the
armed case defers to the flow and answers accepted."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f "* Existing\n"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (name (buffer-name buf))
             (flowed nil))
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (setq flowed fn))))
          ;; Unexposed.
          (jetpacs-buffer-forget-exposed)
          (should (eq 'rejected
                      (jetpacs-org-dialogs--add-heading
                       (list :buffer name)
                       jetpacs-org-dialogs-test--params)))
          ;; A file outside the org roots.
          (jetpacs-org-add-heading-descriptor name)
          (let ((ebp-org-roots
                 (list (file-name-as-directory
                        (make-temp-file "ja5f-other" t)))))
            (should (eq 'rejected
                        (jetpacs-org-dialogs--add-heading
                         (list :buffer name)
                         jetpacs-org-dialogs-test--params))))
          ;; Armed and in-root.
          (jetpacs-org-add-heading-descriptor name)
          (should (eq 'accepted
                      (jetpacs-org-dialogs--add-heading
                       (list :buffer name)
                       jetpacs-org-dialogs-test--params)))
          (should (functionp flowed)))))))

(ert-deftest jetpacs-org-dialogs-add-heading-flow-inserts-and-saves ()
  "The bridged prompt appends `* TITLE' at wide point-max (newlines
flattened) and runs the engine's file-save seam; a blank or quit
answer is a loud no-op."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f "* Existing\nbody"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (saved nil)
             (ebp-org-file-save-function
              (lambda (b) (setq saved (buffer-name b)))))
        (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                   (lambda () t))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) "  Captured\non the go  ")))
          (jetpacs-org-dialogs--add-heading-flow
           buf jetpacs-org-dialogs-test--params))
        (should (equal saved (buffer-name buf)))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should (search-forward "* Captured on the go\n" nil t))))
        ;; Cancelled: nothing inserted, nothing saved.
        (setq saved nil)
        (let ((before (with-current-buffer buf (buffer-string))))
          (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                     (lambda () t))
                    ((symbol-function 'read-string)
                     (lambda (&rest _) (keyboard-quit))))
            (jetpacs-org-dialogs--add-heading-flow
             buf jetpacs-org-dialogs-test--params))
          (should-not saved)
          (should (equal before
                         (with-current-buffer buf (buffer-string)))))))))

(ert-deftest jetpacs-org-dialogs-add-heading-is-can-bridge-gated ()
  "With no bridge the flow refuses loudly — never a desktop prompt."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f "* Existing\n"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (notified nil)
             (prompted nil))
        (cl-letf (((symbol-function 'jetpacs-dialog-can-bridge-p)
                   (lambda () nil))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notified)))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) (setq prompted t) "X")))
          (jetpacs-org-dialogs--add-heading-flow
           buf jetpacs-org-dialogs-test--params)
          (should-not prompted)
          (should notified))))))

;;;; AUDIT-ja5 regressions (each pins a confirmed finding)

(ert-deftest jetpacs-org-dialogs-schedule-arm-maps-scheduled ()
  "P1: (upcase \"schedule\") is \"SCHEDULE\" — the arm shipped unable to
write.  The mapping is explicit now; both arms name real engine keys."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent"))
             (opened nil))
        (cl-letf (((symbol-function 'jetpacs-org-dialogs--ts-open)
                   (lambda (target _stamp _params) (push target opened)))
                  ((symbol-function 'run-at-time)
                   (lambda (_t _r fn &rest args) (apply fn args))))
          (jetpacs-org-dialogs--sheet-dispatch
           ref buf "schedule" jetpacs-org-dialogs-test--params)
          (jetpacs-org-dialogs--sheet-dispatch
           ref buf "deadline" jetpacs-org-dialogs-test--params))
        (should (equal (mapcar (lambda (tgt) (plist-get tgt :which))
                               (nreverse opened))
                       '("SCHEDULED" "DEADLINE")))))))

(ert-deftest jetpacs-org-dialogs-copy-button-needs-dialog-profile ()
  "P1: the Copy builtin ships inside a DIALOG spec, so the DIALOG
profile's advertisement governs — an app-profile gate emitted a
builtin the reference Companion's dialog validator 1201s."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        "A note[fn:1] here.\n\n[fn:1] The definition.\n"
      ;; App advertises clipboard.copy; the dialog profile does NOT —
      ;; the reference Companion's exact shape.
      (setf (ebp-client-profiles (jetpacs-client))
            '(:app (:node_types ["text" "rich_text" "button" "column"]
                    :builtins ["clipboard.copy" "dialog.submit"
                               "dialog.dismiss"])
              :dialog (:node_types ["text" "rich_text" "button" "row"
                                    "column" "text_input" "enum_list"
                                    "date_button" "time_button"]
                       :builtins ["dialog.submit" "dialog.dismiss"])))
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (search-forward "note[fn:1]")
           (jetpacs-org-dialogs--show-footnote
            buf (- (point) 6) jetpacs-org-dialogs-test--params)))
        (let* ((spec (plist-get (jetpacs-org-dialogs-test--last) :spec))
               (builtins (mapcar (lambda (d) (plist-get d :builtin))
                                 (jetpacs-org-dialogs-test--descriptors
                                  spec))))
          (should-not (member "clipboard.copy" builtins)))))))

(ert-deftest jetpacs-org-dialogs-rep-unit-injection-blocked ()
  "P1 (23.1): a crafted repeater UNIT reached the org file verbatim —
a device could smuggle a heading.  Every captured field is now
shape-checked; a failing member is dropped, never written."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--ts-open
         (list :kind 'planning :ref ref :which "SCHEDULED")
         nil jetpacs-org-dialogs-test--params)
        (let ((session (cl-loop for s being the hash-values of
                                jetpacs-org-dialogs--ts-sessions
                                return s)))
          (jetpacs-org-dialogs--ts-conclude
           (plist-put (copy-sequence session) :date "2026-08-02")
           "save"
           '(:ts-rep-type "+" :ts-rep-n "1"
             :ts-rep-unit "w>\n* EVIL :tag:")))
        (with-current-buffer buf
          (org-with-wide-buffer
           (should-not (save-excursion (goto-char (point-min))
                                       (search-forward "EVIL" nil t)))
           ;; The invalid unit fell back to the seed; the legal cookie
           ;; still wrote.
           (goto-char (point-min))
           (should (re-search-forward
                    "SCHEDULED: <2026-08-02 [A-Za-z]\\{3\\} \\+1w>"
                    nil t))))))))

(ert-deftest jetpacs-org-dialogs-ts-seed-legal-and-preserving ()
  "P2: a 1-digit hour and an hourly repeater are legal org that the
dialog nodes reject — the spec build signaled inside the timer and the
tap was silently dead.  Seeds are node-legal now, and the cookies the
editor cannot represent (raw hourly repeater, /max tail, delay) ride
the session and survive a body save."
  (let ((s (jetpacs-org-dialogs--ts-seed "<2026-07-30 Thu 9:30 +2h>")))
    (should (equal (plist-get s :time) "09:30"))
    (should (equal (plist-get s :rep-type) "none"))
    (should (equal (plist-get s :rep-raw) "+2h")))
  (let ((s (jetpacs-org-dialogs--ts-seed "<2026-07-20 Mon .+2d/4d -1d>")))
    (should (equal (plist-get s :rep-type) ".+"))
    (should (equal (plist-get s :rep-tail) "/4d"))
    (should (equal (plist-get s :delay) "-1d")))
  ;; The build itself: a legal-org stamp yields a dialog, not a signal.
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        "* H\nSee <2026-07-30 Thu 9:30 +2h> then.\n"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (name (buffer-name buf))
             (pos (with-current-buffer buf
                    (org-with-wide-buffer
                     (goto-char (point-min))
                     (search-forward "<2026")
                     (match-beginning 0)))))
        (jetpacs-org-dialogs--ts-open
         (list :kind 'body :buffer name :pos pos :bracket ?<)
         "<2026-07-30 Thu 9:30 +2h>" jetpacs-org-dialogs-test--params)
        (let ((shown (jetpacs-org-dialogs-test--last)))
          (should shown)
          (should (jetpacs-check-profile (plist-get shown :spec) 'dialog)))
        ;; Saving preserves the unrepresentable hourly cookie.
        (let ((session (cl-loop for s being the hash-values of
                                jetpacs-org-dialogs--ts-sessions
                                return s)))
          (jetpacs-org-dialogs--ts-body-write
           (plist-get session :target)
           (plist-put (copy-sequence session) :date "2026-08-01")
           "save"))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (should (search-forward "+2h>" nil t))))))))

(ert-deftest jetpacs-org-dialogs-inline-footnote-shows-definition ()
  "P2: nth 3 of `org-footnote-at-reference-p' IS the inline definition
string; reading it as a boolean showed the [fn:...] wrapper instead."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        "Body text[fn:note:the actual definition].\n"
      (let ((buf (jetpacs-org-dialogs-test--buffer f)))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (search-forward "[fn:")
           (let ((info (jetpacs-org-dialogs--footnote-info
                        buf (match-beginning 0))))
             (should (plist-get info :inline))
             (should (equal (plist-get info :definition)
                            "the actual definition")))))))))

(ert-deftest jetpacs-org-dialogs-sheet-refuses-rotted-pos ()
  "P2 (14.5): a rotted pos must answer \"gone\", never resolve to
whatever heading now encloses it — every sheet arm and the Archive
token would target the WRONG subtree."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (body-pos (with-current-buffer buf
                         (org-with-wide-buffer
                          (goto-char (point-min))
                          (search-forward "Body.")
                          (match-beginning 0))))
             (notified nil))
        (should-not (jetpacs-org-dialogs--ref-at buf body-pos))
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notified))))
          (jetpacs-org-dialogs--show-sheet
           buf body-pos jetpacs-org-dialogs-test--params))
        (should (equal notified '("No heading there")))
        (should-not jetpacs-org-dialogs-test--shown)))))

(ert-deftest jetpacs-org-dialogs-archive-dialog-context-surface ()
  "P2: the Archive event arrives in DIALOG context (:dialog_id, no
:surface) — feedback and the re-push must target the surface the sheet
was opened FROM, not the shell default."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (notified-to nil) (refreshed-to nil))
        (jetpacs-org-dialogs-test--show-sheet buf)
        (let ((token (plist-get jetpacs-org-dialogs--sheet :token)))
          (cl-letf (((symbol-function 'jetpacs-shell-notify)
                     (lambda (_text &optional s) (push s notified-to)))
                    ((symbol-function 'jetpacs-buffer-defer-refresh)
                     (lambda (s) (push s refreshed-to)))
                    ((symbol-function 'ebp-client-abandon) #'ignore))
            (should (eq 'accepted
                        (jetpacs-org-dialogs--archive
                         (list :token token)
                         '(:dialog_id "sheet-dialog-1"))))))
        (should (equal notified-to '("app:ja5d")))
        (should (equal refreshed-to '("app:ja5d")))))))

(ert-deftest jetpacs-org-dialogs-footnote-drill-targets-tap-surface ()
  "P2: the Go-to-definition drill must land on the TAPPED surface — a
bare navigate from a timer resolves to the shell default."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        "A note[fn:1] here.\n\n[fn:1] Def.\n"
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (navigated-to 'unset))
        (with-current-buffer buf
          (org-with-wide-buffer
           (goto-char (point-min))
           (search-forward "note[fn:1]")
           (jetpacs-org-dialogs--show-footnote
            buf (- (point) 6) jetpacs-org-dialogs-test--params)))
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (_t _r fn &rest args) (apply fn args)))
                  ((symbol-function 'jetpacs-navigate-buffer)
                   (lambda (_buf &optional surface _label)
                     (setq navigated-to surface))))
          (jetpacs-org-dialogs-test--submit
           (jetpacs-org-dialogs-test--last) "edit"))
        (should (equal navigated-to "app:ja5d"))))))

(ert-deftest jetpacs-org-dialogs-pick-preserves-repeater-edits ()
  "P2 (14.1): the pick descriptors CAPTURE the repeater trio, and the
handler merges the captured values before re-presenting — a date pick
no longer wipes uncommitted repeater edits."
  (jetpacs-org-dialogs-test--with-env
    (jetpacs-org-dialogs-test--with-file f
        jetpacs-org-dialogs-test--sheet-fixture
      (let* ((buf (jetpacs-org-dialogs-test--buffer f))
             (ref (jetpacs-org-dialogs-test--ref buf "Parent")))
        (jetpacs-org-dialogs--ts-open
         (list :kind 'planning :ref ref :which "SCHEDULED")
         nil jetpacs-org-dialogs-test--params)
        ;; The descriptors carry the capture set.
        (let* ((spec (plist-get (jetpacs-org-dialogs-test--last) :spec))
               (picks (seq-filter
                       (lambda (d) (equal (plist-get d :action)
                                          "jetpacs.org.ts-pick"))
                       (jetpacs-org-dialogs-test--descriptors spec))))
          (dolist (p picks)
            (should (equal (append (plist-get p :capture_fields) nil)
                           '("ts-rep-type" "ts-rep-n" "ts-rep-unit")))))
        (let* ((sid (cl-loop for k being the hash-keys of
                             jetpacs-org-dialogs--ts-sessions
                             return k))
               (dialog-id (plist-get (gethash
                                      sid jetpacs-org-dialogs--ts-sessions)
                                     :dialog-id)))
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_t _r fn &rest args) (apply fn args)))
                    ((symbol-function 'ebp-client-abandon) #'ignore))
            (should (eq 'accepted
                        (jetpacs-org-dialogs--ts-pick
                         (list :sid sid :field "date"
                               :value "2026-09-01")
                         (list :dialog_id dialog-id
                               :fields '(:ts-rep-type "++"
                                         :ts-rep-n "2"
                                         :ts-rep-unit "m"))))))
          (let ((fresh (gethash sid jetpacs-org-dialogs--ts-sessions)))
            (should (equal (plist-get fresh :date) "2026-09-01"))
            (should (equal (plist-get fresh :rep-type) "++"))
            (should (equal (plist-get fresh :rep-n) "2"))
            (should (equal (plist-get fresh :rep-unit) "m"))))))))

(provide 'jetpacs-org-dialogs-test)
;;; jetpacs-org-dialogs-test.el ends here
