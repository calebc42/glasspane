;;; jetpacs-files-test.el --- JA-6 F1 exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-6 F1 half of the exit gate (docs/PLAN-jetpacs-apps.md): the
;; floor guard's :require modes driven DIRECTLY (the plan's named cases
;; — symlink-inside-root, path-prefix-not-component, remote-filename —
;; plus the absent/directory modes JA-6's ops will lean on), the /sdcard
;; probe, the dired card skin's ordering and both caps, and the three
;; browse verbs through the REAL `jetpacs--dispatch' so D1/D2 are the
;; live properties.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-buffer)
(require 'jetpacs-chrome)
(require 'jetpacs-navigate)
(require 'jetpacs-files)

;;;; Fixtures

(defmacro jetpacs-files-test--with-tree (root &rest body)
  "BODY with ROOT bound to a fresh temp directory that is the only root.
The probe is bound OFF (memo nil, not `unset'), so no test leaks the
host machine's /sdcard-alikes into the allowlist."
  (declare (indent 1))
  `(let ((,root (file-name-as-directory
                 (make-temp-file "jetpacs-files-test" t))))
     (unwind-protect
         (let ((jetpacs-files-roots (list ,root))
               (jetpacs-files-default-dir ,root)
               (jetpacs-files--dir nil)
               (jetpacs-files-shared-storage nil)
               (jetpacs-files--shared-dir nil))
           ,@body)
       (delete-directory ,root t))))

(defun jetpacs-files-test--touch (path)
  "Create an empty file at PATH, parents included."
  (make-directory (file-name-directory path) t)
  (write-region "" nil path nil 'silent)
  path)

(defun jetpacs-files-test--refusal (thunk)
  "The `jetpacs-path-refused' reason symbol THUNK signals, or `:no-signal'."
  (condition-case err
      (progn (funcall thunk) :no-signal)
    (jetpacs-path-refused (cadr err))))

(defun jetpacs-files-test--collect (node key)
  "Every value of KEY in the plist tree NODE, in order."
  (let (hits)
    (cl-labels ((walk (n)
                  (cond
                   ((vectorp n) (mapc #'walk n))
                   ((and (consp n) (keywordp (car n)))
                    (cl-loop for (k v) on n by #'cddr
                             do (when (eq k key) (push v hits))
                             (walk v)))
                   ((consp n) (mapc #'walk n)))))
      (walk node))
    (nreverse hits)))

(defconst jetpacs-files-test--app-types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"
   "card" "lazy_column" "icon_button" "icon" "empty_state" "scaffold"])

(defun jetpacs-files-test--client ()
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-files-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-files-test--app-types
                  :builtins ["view.switch" "clipboard.copy"]
                  :features [])))
    client))

(defmacro jetpacs-files-test--attached (client-form &rest body)
  (declare (indent 1))
  `(let ((client ,client-form))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-test-reset-state))))

(defun jetpacs-files-test--pump ()
  "Drive the run-at-time continuations."
  (cl-loop repeat 10 do (accept-process-output nil 0.05)))

;;;; The floor guard, driven directly (the plan's named cases)

(ert-deftest jetpacs-files-guard-remote-refused-before-any-stat ()
  "No stat-family primitive ever receives the REMOTE name — the stat IS
the connection, and this rung's browse verbs run inside handlers.
\(Total-call counting is wrong here: `file-remote-p' on an ssh name
autoloads TRAMP, and the library load stats plenty of LOCAL files.)"
  (jetpacs-files-test--with-tree root
    (let ((stats 0))
      (cl-letf* ((record (lambda (real)
                           (lambda (&rest args)
                             (when (and (stringp (car args))
                                        (string-prefix-p "/ssh:" (car args)))
                               (cl-incf stats))
                             (apply real args))))
                 ((symbol-function 'file-truename)
                  (funcall record (symbol-function 'file-truename)))
                 ((symbol-function 'file-exists-p)
                  (funcall record (symbol-function 'file-exists-p)))
                 ((symbol-function 'file-attributes)
                  (funcall record (symbol-function 'file-attributes)))
                 ((symbol-function 'file-readable-p)
                  (funcall record (symbol-function 'file-readable-p)))
                 ((symbol-function 'file-directory-p)
                  (funcall record (symbol-function 'file-directory-p)))
                 ((symbol-function 'file-accessible-directory-p)
                  (funcall record
                           (symbol-function 'file-accessible-directory-p))))
        (should (eq 'remote
                    (jetpacs-files-test--refusal
                     (lambda ()
                       (jetpacs-check-path "/ssh:evil:/x" (list root))))))
        (should (= stats 0))))))

(ert-deftest jetpacs-files-guard-prefix-is-not-containment ()
  "Root .../org must not authorize .../org-evil — components, not prefixes.
The root is passed WITHOUT a trailing slash on purpose: that is how
users write configuration, and it is the shape where a string-prefix
check admits the sibling (a slashed root makes prefix matching
accidentally safe, and a test using it cannot tell the two apart)."
  (jetpacs-files-test--with-tree root
    (let ((org (concat root "org"))     ; no trailing slash
          (evil (jetpacs-files-test--touch (concat root "org-evil/x"))))
      (jetpacs-files-test--touch (concat root "org/inside"))
      (should (equal (jetpacs-check-path (concat root "org/inside") (list org))
                     (file-truename (concat root "org/inside"))))
      (should (eq 'outside-roots
                  (jetpacs-files-test--refusal
                   (lambda () (jetpacs-check-path evil (list org)))))))))

(ert-deftest jetpacs-files-guard-symlink-inside-root-refused ()
  "A symlink SITTING inside a root but POINTING outside cannot smuggle
a path past the boundary — both sides are truenamed."
  (jetpacs-files-test--with-tree root
    (let* ((outside (file-name-as-directory
                     (make-temp-file "jetpacs-files-outside" t))))
      (unwind-protect
          (progn
            (jetpacs-files-test--touch (concat outside "secret"))
            (make-symbolic-link (directory-file-name outside)
                                (concat root "link"))
            (should (eq 'outside-roots
                        (jetpacs-files-test--refusal
                         (lambda ()
                           (jetpacs-check-path (concat root "link/secret")
                                               (list root)))))))
        (delete-directory outside t)))))

(ert-deftest jetpacs-files-guard-symlinked-root-authorizes-real-tree ()
  "A root that IS a symlink still authorizes its real tree."
  (jetpacs-files-test--with-tree root
    (let* ((real (file-name-as-directory
                  (make-temp-file "jetpacs-files-real" t))))
      (unwind-protect
          (progn
            (jetpacs-files-test--touch (concat real "f"))
            (make-symbolic-link (directory-file-name real)
                                (concat root "sroot"))
            (should (equal (jetpacs-check-path (concat real "f")
                                               (list (concat root "sroot")))
                           (file-truename (concat real "f")))))
        (delete-directory real t)))))

(ert-deftest jetpacs-files-guard-require-directory ()
  "The browse mode: a file and a missing name both fail as
`not-a-directory'; a directory — including the root itself — passes."
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "f")))
          (sub (concat root "sub/")))
      (make-directory sub)
      (should (eq 'not-a-directory
                  (jetpacs-files-test--refusal
                   (lambda ()
                     (jetpacs-check-path f (list root) :require 'directory)))))
      (should (eq 'not-a-directory
                  (jetpacs-files-test--refusal
                   (lambda ()
                     (jetpacs-check-path (concat root "missing") (list root)
                                         :require 'directory)))))
      (should (equal (jetpacs-check-path sub (list root) :require 'directory)
                     (file-truename sub)))
      ;; The landing case: a directory contains itself.
      (should (equal (jetpacs-check-path root (list root) :require 'directory)
                     (file-truename root))))))

(ert-deftest jetpacs-files-guard-require-absent ()
  "The rename/create-target mode: existence refuses, containment still
binds — including a target smuggled through an in-root symlink."
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "f")))
          (outside (file-name-as-directory
                    (make-temp-file "jetpacs-files-out2" t))))
      (unwind-protect
          (progn
            (should (eq 'exists
                        (jetpacs-files-test--refusal
                         (lambda ()
                           (jetpacs-check-path f (list root) :require 'absent)))))
            ;; A new tail under a root passes and comes back truenamed.
            (should (equal (jetpacs-check-path (concat root "new") (list root)
                                               :require 'absent)
                           (concat (file-name-as-directory
                                    (file-truename root))
                                   "new")))
            ;; A deep new tail passes too (mkdir -p semantics are the
            ;; caller's business; containment is ours).
            (should (stringp (jetpacs-check-path (concat root "a/b/c")
                                                 (list root)
                                                 :require 'absent)))
            ;; Containment is checked on the RESOLVED name, so an
            ;; in-root symlink cannot smuggle a create/rename TARGET out.
            (make-symbolic-link (directory-file-name outside)
                                (concat root "link"))
            (should (eq 'outside-roots
                        (jetpacs-files-test--refusal
                         (lambda ()
                           (jetpacs-check-path (concat root "link/new")
                                               (list root)
                                               :require 'absent)))))
            ;; And an absent path outside any root is refused as
            ;; containment, never reported on via `exists'.
            (should (eq 'outside-roots
                        (jetpacs-files-test--refusal
                         (lambda ()
                           (jetpacs-check-path (concat outside "new")
                                               (list root)
                                               :require 'absent))))))
        (delete-directory outside t)))))

(ert-deftest jetpacs-files-guard-require-nil-is-containment-only ()
  "The nil mode skips the existence stat entirely; the default refuses
the same file as `unreadable'."
  (skip-unless (not (zerop (user-uid))))   ; root ignores modes
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "locked"))))
      (set-file-modes f 0)
      (unwind-protect
          (progn
            (should (eq 'unreadable
                        (jetpacs-files-test--refusal
                         (lambda () (jetpacs-check-path f (list root))))))
            (should (equal (jetpacs-check-path f (list root) :require nil)
                           (file-truename f))))
        (set-file-modes f #o600)))))

(ert-deftest jetpacs-files-guard-unknown-require-is-a-caller-error ()
  "An unknown :require is a BUG at the call site — a plain `error',
never a `jetpacs-path-refused' a handler would answer to the device."
  (jetpacs-files-test--with-tree root
    (should-error (jetpacs-check-path root (list root) :require 'writable)
                  :type 'error)
    (should-not (eq 'jetpacs-path-refused
                    (car (should-error
                          (jetpacs-check-path root (list root)
                                              :require 'writable)))))))

(ert-deftest jetpacs-files-guard-no-roots-stays-distinct ()
  "Unconfigured and out-of-policy are different conditions."
  (jetpacs-files-test--with-tree root
    (should (eq 'no-roots
                (jetpacs-files-test--refusal
                 (lambda () (jetpacs-check-path root '())))))
    (should (eq 'no-roots
                (jetpacs-files-test--refusal
                 (lambda ()
                   (jetpacs-check-path root '("/nonexistent-root-xyz"))))))
    (should (eq 'outside-roots
                (jetpacs-files-test--refusal
                 (lambda () (jetpacs-check-path "/etc" (list root))))))))

;;;; The /sdcard probe and the effective roots

(ert-deftest jetpacs-files-probe-disabled-and-explicit ()
  (jetpacs-files-test--with-tree root
    ;; Disabled: memo re-armed, config nil -> nothing.
    (let ((jetpacs-files--shared-dir 'unset)
          (jetpacs-files-shared-storage nil))
      (should-not (jetpacs-files-shared-dir))
      (should (equal (jetpacs-files--roots) (list root))))
    ;; Explicit accessible dir: normalized, memoized, in the roots.
    (let* ((shared (file-name-as-directory
                    (make-temp-file "jetpacs-files-shared" t))))
      (unwind-protect
          (let ((jetpacs-files--shared-dir 'unset)
                (jetpacs-files-shared-storage (directory-file-name shared))
                (probes 0))
            (cl-letf* ((real (symbol-function 'jetpacs-files--detect-shared-dir))
                       ((symbol-function 'jetpacs-files--detect-shared-dir)
                        (lambda () (cl-incf probes) (funcall real))))
              (should (equal (jetpacs-files-shared-dir) shared))
              (should (equal (jetpacs-files-shared-dir) shared))
              (should (= probes 1)))
            (should (member shared (jetpacs-files--roots)))
            ;; The widened sandbox is REAL: a file there clears the guard.
            (let ((f (jetpacs-files-test--touch (concat shared "f"))))
              (should (equal (jetpacs-files--check f)
                             (file-truename f)))))
        (delete-directory shared t)))))

;;;; The dired card skin

(defun jetpacs-files-test--card-titles (cards)
  "First text of each card node in CARDS."
  (mapcar (lambda (c) (car (jetpacs-files-test--collect c :text))) cards))

(ert-deftest jetpacs-files-skin-dirs-first-and-tappable ()
  (jetpacs-files-test--with-tree root
    (make-directory (concat root "zdir"))
    (make-directory (concat root "adir"))
    (jetpacs-files-test--touch (concat root "bfile"))
    (jetpacs-files-test--touch (concat root "afile"))
    (let ((cards (jetpacs-files--dired-cards (dired-noselect root))))
      ;; Root is the ceiling: no up-row, so exactly the four entries.
      (should (equal (jetpacs-files-test--card-titles cards)
                     '("adir" "zdir" "afile" "bfile")))
      (should (equal (jetpacs-files-test--collect cards :action)
                     '("jetpacs.files.cd" "jetpacs.files.cd"
                       "jetpacs.files.open" "jetpacs.files.open")))
      ;; Args carry the absolute paths.
      (let ((args (jetpacs-files-test--collect cards :args)))
        (should (equal (plist-get (nth 0 args) :dir) (concat root "adir")))
        (should (equal (plist-get (nth 2 args) :path) (concat root "afile"))))
      ;; Every row key is a minted SPEC 4.4 identifier.
      (dolist (key (jetpacs-files-test--collect cards :key))
        (should (jetpacs--identifier-p key))))))

(ert-deftest jetpacs-files-skin-up-row-only-within-roots ()
  (jetpacs-files-test--with-tree root
    (let ((sub (concat root "sub/")))
      (make-directory sub)
      ;; Parent inside the roots: the up-row leads there.
      (let ((cards (jetpacs-files--dired-cards (dired-noselect sub))))
        (should (equal (car (jetpacs-files-test--card-titles cards)) ".."))
        (should (equal (plist-get (car (jetpacs-files-test--collect cards :args))
                                  :dir)
                       root)))
      ;; Roots pinned AT the subdir: the ceiling has no up.
      (let* ((jetpacs-files-roots (list sub))
             (cards (jetpacs-files--dired-cards (dired-noselect sub))))
        (should-not (member ".." (jetpacs-files-test--card-titles cards)))))))

(ert-deftest jetpacs-files-skin-row-cap-reports-the-rest ()
  (jetpacs-files-test--with-tree root
    (dolist (n '("a" "b" "c" "d")) (jetpacs-files-test--touch (concat root n)))
    (let* ((jetpacs-files-max-rows 2)
           (cards (jetpacs-files--dired-cards (dired-noselect root))))
      (should (= (length cards) 3))
      (should (equal (jetpacs-files-test--card-titles (list (nth 2 cards)))
                     '("+2 more not shown"))))))

(ert-deftest jetpacs-files-skin-scan-cap-stops-the-walk ()
  (jetpacs-files-test--with-tree root
    (dolist (n '("a" "b" "c" "d" "e")) (jetpacs-files-test--touch (concat root n)))
    (let* ((jetpacs-files-scan-cap 2)
           (cards (jetpacs-files--dired-cards (dired-noselect root)))
           (texts (jetpacs-files-test--collect cards :text)))
      ;; 2 entries + the stopped caption; the walk never met the rest.
      (should (cl-some (lambda (s) (string-match-p "stopped at 2" s)) texts))
      (should (= (length cards) 3)))))

(ert-deftest jetpacs-files-skin-unencodable-name-renders-inert ()
  "A path that cannot round-trip the wire renders without any action:
`:args' is opaque to the shell walkers, and a raw byte there reaches
`json-serialize' and takes the whole push down."
  (let* ((bad (concat "/tmp/jetpacs-x/bad-" (string #x3FFF80)))
         (card (jetpacs-files--entry-row bad nil)))
    (should-not (jetpacs-files-test--collect card :action))
    (should (cl-some (lambda (s) (string-match-p "unencodable" s))
                     (jetpacs-files-test--collect card :text)))
    (let ((key (car (jetpacs-files-test--collect card :key))))
      (should (jetpacs--identifier-p key)))))

(ert-deftest jetpacs-files-skin-rides-the-render-dispatch ()
  "`jetpacs-render-buffer' on a dired buffer lands in this skin."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--touch (concat root "f"))
    (let ((buf (dired-noselect root)))
      (should (equal (jetpacs-render-buffer buf)
                     (jetpacs-files--dired-cards buf))))))

(ert-deftest jetpacs-files-body-degrades-outside-roots ()
  (jetpacs-files-test--with-tree root
    ;; A view state outside the roots (stale config, edited variable)
    ;; degrades to an empty state, never a signal out of the builder.
    (let* ((outside (file-name-as-directory
                     (make-temp-file "jetpacs-files-out3" t))))
      (unwind-protect
          (let ((jetpacs-files--dir outside))
            (let ((body (jetpacs-files--body)))
              (should (equal (plist-get body :t) "empty_state"))))
        (delete-directory outside t)))
    ;; The landing renders: a lazy_column whose first child is the
    ;; current-directory caption.
    (let ((body (jetpacs-files--body)))
      (should (equal (plist-get body :t) "lazy_column"))
      (should (equal (plist-get (aref (plist-get body :children) 0) :style)
                     "caption")))))

;;;; The browse verbs through the real dispatch (D1 + D2)

(ert-deftest jetpacs-files-cd-validates-then-defers-the-push ()
  (jetpacs-files-test--with-tree root
    (let ((sub (concat root "sub/")))
      (make-directory sub)
      (jetpacs-files-test--attached (jetpacs-files-test--client)
        (let ((pushed '()) (notes '()))
          (cl-letf (((symbol-function 'jetpacs-shell-push)
                     (lambda (surface &rest _) (push surface pushed) 1))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (text &optional _s) (push text notes))))
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.cd"
                                  :surface "app:jetpacs.files"
                                  :args (:dir ,(directory-file-name sub)))
                         (gethash "jetpacs.files.cd" jetpacs-action-handlers))
                        'accepted))
            (should (equal jetpacs-files--dir (file-truename sub)))
            ;; D2: nothing pushed inside the extent.
            (should (null pushed))
            (jetpacs-files-test--pump)
            (should (equal pushed '("app:jetpacs.files")))
            ;; Out of policy: rejected, state untouched, the user told.
            (should (eq (jetpacs--dispatch
                         client '(:action "jetpacs.files.cd"
                                  :surface "app:jetpacs.files"
                                  :args (:dir "/etc"))
                         (gethash "jetpacs.files.cd" jetpacs-action-handlers))
                        'rejected))
            (should (equal jetpacs-files--dir (file-truename sub)))
            (should (= (length notes) 1))
            ;; E2b/D1: a foreign surface never reaches the handler.
            (let ((warning-minimum-log-level :emergency))
              (should (eq (jetpacs--dispatch
                           client `(:action "jetpacs.files.cd"
                                    :surface "app:other"
                                    :args (:dir ,(directory-file-name sub)))
                           (gethash "jetpacs.files.cd" jetpacs-action-handlers))
                          'rejected)))))))))

(ert-deftest jetpacs-files-open-defers-the-prompting-effect ()
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "f.txt"))))
      (jetpacs-files-test--attached (jetpacs-files-test--client)
        (let ((navigated '()) (opened-inside 'unset) (notes '()))
          (cl-letf (((symbol-function 'jetpacs-navigate-buffer)
                     (lambda (buf surface &rest _)
                       (push (cons (buffer-file-name (get-buffer buf)) surface)
                             navigated)))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (text &optional _s) (push text notes))))
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.open"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,f))
                         (gethash "jetpacs.files.open" jetpacs-action-handlers))
                        'accepted))
            ;; D2: the open (it can prompt) happened OUTSIDE the extent.
            (setq opened-inside navigated)
            (jetpacs-files-test--pump)
            (should (null opened-inside))
            (should (equal navigated
                           (list (cons (file-truename f)
                                       "app:jetpacs.files"))))
            ;; Outside the roots: rejected before any effect.
            (should (eq (jetpacs--dispatch
                         client '(:action "jetpacs.files.open"
                                  :surface "app:jetpacs.files"
                                  :args (:path "/etc/passwd"))
                         (gethash "jetpacs.files.open" jetpacs-action-handlers))
                        'rejected))
            (jetpacs-files-test--pump)
            (should (= (length navigated) 1))
            (should (= (length notes) 1))))))))

(ert-deftest jetpacs-files-open-on-a-directory-is-cd ()
  (jetpacs-files-test--with-tree root
    (let ((sub (concat root "sub/")))
      (make-directory sub)
      (jetpacs-files-test--attached (jetpacs-files-test--client)
        (let ((pushed '()) (navigated 0))
          (cl-letf (((symbol-function 'jetpacs-shell-push)
                     (lambda (surface &rest _) (push surface pushed) 1))
                    ((symbol-function 'jetpacs-navigate-buffer)
                     (lambda (&rest _) (cl-incf navigated))))
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.open"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,(directory-file-name sub)))
                         (gethash "jetpacs.files.open" jetpacs-action-handlers))
                        'accepted))
            (should (equal jetpacs-files--dir (file-truename sub)))
            (jetpacs-files-test--pump)
            (should (= navigated 0))
            (should (equal pushed '("app:jetpacs.files")))))))))

(ert-deftest jetpacs-files-refresh-repushes-the-origin ()
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let ((pushed '()))
        (cl-letf (((symbol-function 'jetpacs-shell-push)
                   (lambda (surface &rest _) (push surface pushed) 1)))
          (should (eq (jetpacs--dispatch
                       client '(:action "jetpacs.files.refresh"
                                :surface "app:jetpacs.files")
                       (gethash "jetpacs.files.refresh" jetpacs-action-handlers))
                      'accepted))
          (should (null pushed))
          (jetpacs-files-test--pump)
          (should (equal pushed '("app:jetpacs.files"))))))))

;;;; Content search (F2)

(defun jetpacs-files-test--scan (dir query)
  "Drive the chunked scan to completion; return the result plist."
  (let (result)
    (jetpacs-files--grep-start dir query (lambda (r) (setq result r)))
    (cl-loop repeat 200 until result do (accept-process-output nil 0.02))
    result))

(ert-deftest jetpacs-files-grep-matches-literally ()
  "The query is a LITERAL, never a regexp (#137: an exposed pattern
grammar is received interpretation), and matching is case-insensitive
with one hit per line."
  (jetpacs-files-test--with-tree root
    (let ((f (concat root "f.txt")))
      (write-region "a.*b\naxxb\nTODO and todo\n" nil f nil 'silent)
      (let ((hits (jetpacs-files--grep-file f ".*" 100)))
        (should (= (length hits) 1))
        (should (= (nth 1 (car hits)) 1)))
      (let ((hits (jetpacs-files--grep-file f "todo" 100)))
        (should (= (length hits) 1))
        (should (= (nth 1 (car hits)) 3))))))

(ert-deftest jetpacs-files-grep-nul-guard-skips-binaries ()
  (jetpacs-files-test--with-tree root
    (let ((bin (concat root "bin.dat"))
          (txt (concat root "t.txt"))
          (coding-system-for-write 'binary))
      (write-region "head\0needle\n" nil bin nil 'silent)
      (write-region "needle\n" nil txt nil 'silent)
      (should-not (jetpacs-files--grep-file bin "needle" 100))
      (should (= (length (jetpacs-files--grep-file txt "needle" 100)) 1)))))

(ert-deftest jetpacs-files-grep-file-honours-hits-left ()
  (jetpacs-files-test--with-tree root
    (let ((f (concat root "f.txt")))
      (write-region "n\nn\nn\nn\nn\n" nil f nil 'silent)
      (should (= (length (jetpacs-files--grep-file f "n" 2)) 2))
      (should-not (jetpacs-files--grep-file f "n" 0)))))

(ert-deftest jetpacs-files-grep-scan-skips-what-it-must ()
  "Excluded dirs, oversize files, backups, and anything behind a
symlink — the guard validated the START directory, and a link out of
the sandbox must not let the scan read what open would refuse."
  (jetpacs-files-test--with-tree root
    (let* ((outside (file-name-as-directory
                     (make-temp-file "jetpacs-grep-out" t))))
      (unwind-protect
          (progn
            (write-region "needle in plain\n" nil (concat root "plain.txt")
                          nil 'silent)
            (make-directory (concat root ".git"))
            (write-region "needle in vcs\n" nil (concat root ".git/config")
                          nil 'silent)
            (write-region (concat (make-string 300 ?x) " needle\n") nil
                          (concat root "big.txt") nil 'silent)
            (write-region "needle in backup\n" nil (concat root "x.txt~")
                          nil 'silent)
            (write-region "needle outside\n" nil (concat outside "o.txt")
                          nil 'silent)
            (make-symbolic-link (directory-file-name outside)
                                (concat root "ldir"))
            (make-symbolic-link (concat outside "o.txt")
                                (concat root "lfile.txt"))
            (let* ((jetpacs-files-grep-max-file-bytes 100)
                   (result (jetpacs-files-test--scan root "needle"))
                   (files (mapcar #'car (plist-get result :hits))))
              (should result)
              (should (equal files (list (concat root "plain.txt"))))
              (should-not (plist-get result :truncated))))
        (delete-directory outside t)))))

(ert-deftest jetpacs-files-grep-scan-caps-files-and-hits ()
  (jetpacs-files-test--with-tree root
    (dolist (n '("a" "b" "c"))
      (write-region "needle\n" nil (concat root n ".txt") nil 'silent))
    (let* ((jetpacs-files-grep-max-files 2)
           (result (jetpacs-files-test--scan root "needle")))
      (should (plist-get result :truncated))
      (should (<= (length (plist-get result :hits)) 2)))
    (write-region "n\nn\nn\nn\nn\n" nil (concat root "many.txt") nil 'silent)
    (let* ((jetpacs-files-grep-max-hits 3)
           (result (jetpacs-files-test--scan root "n")))
      (should (plist-get result :truncated))
      (should (= (length (plist-get result :hits)) 3)))))

(ert-deftest jetpacs-files-grep-scan-is-async-and-cancellable ()
  (jetpacs-files-test--with-tree root
    (write-region "needle\n" nil (concat root "bfile.txt") nil 'silent)
    (write-region "needle\n" nil (concat root "afile.txt") nil 'silent)
    ;; Nothing resolves inside the caller's extent, and a cancelled scan
    ;; never resolves at all.
    (let* ((resolved nil)
           (cancel (jetpacs-files--grep-start
                    root "needle" (lambda (r) (setq resolved r)))))
      (should-not resolved)
      (funcall cancel)
      (cl-loop repeat 20 do (accept-process-output nil 0.02))
      (should-not resolved))
    ;; Uncancelled: resolves once, hits sorted by file then line.
    (let ((result (jetpacs-files-test--scan root "needle")))
      (should result)
      (should (equal (mapcar #'car (plist-get result :hits))
                     (list (concat root "afile.txt")
                           (concat root "bfile.txt")))))))

(ert-deftest jetpacs-files-grep-action-validates-then-defers ()
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let ((screens '()) (notes '()))
        (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                   (lambda (surface id builder)
                     (push (list surface id builder) screens) 1))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notes))))
          (let ((handler (gethash "jetpacs.files.grep" jetpacs-action-handlers)))
            ;; Not a string / blank / oversize: rejected before any work.
            (should (eq (jetpacs--dispatch
                         client '(:action "jetpacs.files.grep"
                                  :surface "app:jetpacs.files"
                                  :args (:value 5))
                         handler)
                        'rejected))
            (should (eq (jetpacs--dispatch
                         client '(:action "jetpacs.files.grep"
                                  :surface "app:jetpacs.files"
                                  :args (:value "   "))
                         handler)
                        'rejected))
            (let ((jetpacs-files-grep-max-query-chars 4))
              (should (eq (jetpacs--dispatch
                           client '(:action "jetpacs.files.grep"
                                    :surface "app:jetpacs.files"
                                    :args (:value "12345"))
                           handler)
                          'rejected))
              (should (= (length notes) 1)))
            ;; Valid: accepted, request recorded trimmed, the screen
            ;; push deferred out of the extent (D2).
            (should (eq (jetpacs--dispatch
                         client '(:action "jetpacs.files.grep"
                                  :surface "app:jetpacs.files"
                                  :args (:value "  needle  "))
                         handler)
                        'accepted))
            (should (equal (plist-get jetpacs-files--grep-request :query)
                           "needle"))
            (should (equal (plist-get jetpacs-files--grep-request :dir)
                           (jetpacs-check-path root (list root)
                                               :require 'directory)))
            (should (null screens))
            (jetpacs-files-test--pump)
            (should (equal screens
                           (list (list "app:jetpacs.files" "grep"
                                       #'jetpacs-files--grep-screen))))
            ;; A poisoned view state is refused at the handler, loudly.
            (let* ((outside (file-name-as-directory
                             (make-temp-file "jetpacs-grep-out2" t))))
              (unwind-protect
                  (let ((jetpacs-files--dir outside))
                    (should (eq (jetpacs--dispatch
                                 client '(:action "jetpacs.files.grep"
                                          :surface "app:jetpacs.files"
                                          :args (:value "needle"))
                                 handler)
                                'rejected))
                    (should (= (length notes) 2)))
                (delete-directory outside t)))))))))

(ert-deftest jetpacs-files-grep-screen-pending-then-ready ()
  "The results screen through the REAL async cache: first build starts
the loader and shows progress; the completion makes a later build read
the cards, with the snippet and an open tap on each hit."
  (jetpacs-files-test--with-tree root
    (write-region "the needle line\n" nil (concat root "f.txt") nil 'silent)
    (unwind-protect
        (let ((jetpacs-files--grep-request (list :query "needle" :dir root))
              (jetpacs-current-owner jetpacs-files-owner))
          (let ((first (jetpacs-files--grep-screen nil)))
            (should (member "progress"
                            (jetpacs-files-test--collect first :t))))
          (let (ready)
            (cl-loop repeat 200
                     do (accept-process-output nil 0.02)
                        (setq ready (jetpacs-files--grep-screen nil))
                     until (member "jetpacs.files.open"
                                   (jetpacs-files-test--collect ready :action)))
            (should (member "jetpacs.files.open"
                            (jetpacs-files-test--collect ready :action)))
            (let ((texts (jetpacs-files-test--collect ready :text)))
              (should (cl-some (lambda (s)
                                 (string-match-p "1 matching line" s))
                               texts))
              (should (member "the needle line" texts))
              (should (member "L1" texts)))))
      (jetpacs-async-reset))))

(ert-deftest jetpacs-files-body-carries-the-search-input ()
  (jetpacs-files-test--with-tree root
    (let ((body (jetpacs-files--body)))
      (should (member "files-grep-input"
                      (jetpacs-files-test--collect body :id)))
      (should (member "jetpacs.files.grep"
                      (jetpacs-files-test--collect body :action))))))

(provide 'jetpacs-files-test)
;;; jetpacs-files-test.el ends here
