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
          (jetpacs-org-roots (list dir)))
     (with-temp-file ,var (insert ,content))
     (unwind-protect
         (progn ,@body)
       (dolist (name (list ,var (concat ,var "_archive")))
         (when-let* ((buf (find-buffer-visiting name)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory dir t)
       (jetpacs-buffer-forget-exposed)
       (jetpacs-org-reset))))

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
     (jetpacs-org-ref-at-point))))

(defconst jetpacs-org-dialogs-test--params '(:surface "app:ja5d")
  "Minimal event params for driving handlers and dispatches.")

(defun jetpacs-org-dialogs-test--last ()
  (car jetpacs-org-dialogs-test--shown))

(defun jetpacs-org-dialogs-test--descriptors (node)
  "Every ActionDescriptor reachable in NODE (children + spans + on_tap)."
  (let (out)
    (cl-labels
        ((walk (n)
           (when (consp n)
             (when-let* ((d (plist-get n :on_tap))) (push d out))
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
  "The todo arm rides `jetpacs-org-toggle-todo' (never raw `org-todo')."
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

(provide 'jetpacs-org-dialogs-test)
;;; jetpacs-org-dialogs-test.el ends here
