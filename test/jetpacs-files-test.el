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
  "The `ebp-path-refused' reason symbol THUNK signals, or `:no-signal'."
  (condition-case err
      (progn (funcall thunk) :no-signal)
    (ebp-path-refused (cadr err))))

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
                       (ebp-check-path "/ssh:evil:/x" (list root))))))
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
      (should (equal (ebp-check-path (concat root "org/inside") (list org))
                     (file-truename (concat root "org/inside"))))
      (should (eq 'outside-roots
                  (jetpacs-files-test--refusal
                   (lambda () (ebp-check-path evil (list org)))))))))

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
                           (ebp-check-path (concat root "link/secret")
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
            (should (equal (ebp-check-path (concat real "f")
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
                     (ebp-check-path f (list root) :require 'directory)))))
      (should (eq 'not-a-directory
                  (jetpacs-files-test--refusal
                   (lambda ()
                     (ebp-check-path (concat root "missing") (list root)
                                     :require 'directory)))))
      (should (equal (ebp-check-path sub (list root) :require 'directory)
                     (file-truename sub)))
      ;; The landing case: a directory contains itself.
      (should (equal (ebp-check-path root (list root) :require 'directory)
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
                           (ebp-check-path f (list root) :require 'absent)))))
            ;; A new tail under a root passes and comes back truenamed.
            (should (equal (ebp-check-path (concat root "new") (list root)
                                           :require 'absent)
                           (concat (file-name-as-directory
                                    (file-truename root))
                                   "new")))
            ;; A deep new tail passes too (mkdir -p semantics are the
            ;; caller's business; containment is ours).
            (should (stringp (ebp-check-path (concat root "a/b/c")
                                             (list root)
                                             :require 'absent)))
            ;; Containment is checked on the RESOLVED name, so an
            ;; in-root symlink cannot smuggle a create/rename TARGET out.
            (make-symbolic-link (directory-file-name outside)
                                (concat root "link"))
            (should (eq 'outside-roots
                        (jetpacs-files-test--refusal
                         (lambda ()
                           (ebp-check-path (concat root "link/new")
                                           (list root)
                                           :require 'absent)))))
            ;; And an absent path outside any root is refused as
            ;; containment, never reported on via `exists'.
            (should (eq 'outside-roots
                        (jetpacs-files-test--refusal
                         (lambda ()
                           (ebp-check-path (concat outside "new")
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
                         (lambda () (ebp-check-path f (list root))))))
            (should (equal (ebp-check-path f (list root) :require nil)
                           (file-truename f))))
        (set-file-modes f #o600)))))

(ert-deftest jetpacs-files-guard-unknown-require-is-a-caller-error ()
  "An unknown :require is a BUG at the call site — a plain `error',
never a `ebp-path-refused' a handler would answer to the device."
  (jetpacs-files-test--with-tree root
    (should-error (ebp-check-path root (list root) :require 'writable)
                  :type 'error)
    (should-not (eq 'ebp-path-refused
                    (car (should-error
                          (ebp-check-path root (list root)
                                          :require 'writable)))))))

(ert-deftest jetpacs-files-guard-no-roots-stays-distinct ()
  "Unconfigured and out-of-policy are different conditions."
  (jetpacs-files-test--with-tree root
    (should (eq 'no-roots
                (jetpacs-files-test--refusal
                 (lambda () (ebp-check-path root '())))))
    (should (eq 'no-roots
                (jetpacs-files-test--refusal
                 (lambda ()
                   (ebp-check-path root '("/nonexistent-root-xyz"))))))
    (should (eq 'outside-roots
                (jetpacs-files-test--refusal
                 (lambda () (ebp-check-path "/etc" (list root))))))))

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
      (let ((actions (jetpacs-files-test--collect cards :action)))
        ;; The tap verbs, in listing order (each row also carries the F3
        ;; long-press menu and the trailing delete).
        (should (equal (seq-filter (lambda (a)
                                     (member a '("jetpacs.files.cd"
                                                 "jetpacs.files.open")))
                                   actions)
                       '("jetpacs.files.cd" "jetpacs.files.cd"
                         "jetpacs.files.open" "jetpacs.files.open")))
        (should (= (seq-count (lambda (a) (equal a "jetpacs.files.menu"))
                              actions)
                   4))
        (should (= (seq-count (lambda (a) (equal a "jetpacs.files.delete"))
                              actions)
                   4)))
      ;; Args carry the absolute paths; every delete carries `:confirm'.
      (let ((args (jetpacs-files-test--collect cards :args)))
        (should (member (list :dir (concat root "adir")) args))
        (should (member (list :path (concat root "afile")) args)))
      (should (= (seq-count #'stringp (jetpacs-files-test--collect cards :confirm))
                 4))
      ;; Every row key is a minted SPEC 4.4 identifier.
      (dolist (key (jetpacs-files-test--collect cards :key))
        (should (jetpacs-identifier-p key))))))

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
      (should (jetpacs-identifier-p key)))))

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
  "F4 contract: an ELIGIBLE file opens the editor screen; a file the
editor cannot host (here: binary) falls back to the buffer host.  Both
effects run OUTSIDE the dispatch extent (D2)."
  (jetpacs-files-test--with-tree root
    (let ((f (concat root "f.txt"))
          (bin (concat root "b.dat")))
      (write-region "hello\n" nil f nil 'silent)
      (let ((coding-system-for-write 'binary))
        (write-region "x\0y" nil bin nil 'silent))
      (jetpacs-files-test--attached (jetpacs-files-test--client)
        (let ((navigated '()) (screens '()) (notes '())
              (jetpacs-files--edit nil))
          (cl-letf (((symbol-function 'jetpacs-navigate-buffer)
                     (lambda (buf surface &rest _)
                       (push (cons (buffer-file-name (get-buffer buf)) surface)
                             navigated)))
                    ((symbol-function 'jetpacs-chrome-push-screen)
                     (lambda (surface id builder)
                       (push (list surface id builder) screens) 1))
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (text &optional _s) (push text notes))))
            ;; Eligible: the editor screen, seeded from disk.
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.open"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,f))
                         (gethash "jetpacs.files.open" jetpacs-action-handlers))
                        'accepted))
            ;; D2: nothing happened inside the extent.
            (should (null screens))
            (should (null navigated))
            (jetpacs-files-test--pump)
            (should (equal screens
                           (list (list "app:jetpacs.files" "edit"
                                       #'jetpacs-files--edit-screen))))
            (should (null navigated))
            (should (equal (plist-get jetpacs-files--edit :seed) "hello\n"))
            (should (equal (plist-get jetpacs-files--edit :path)
                           (file-truename f)))
            (should (stringp (plist-get jetpacs-files--edit :mtime)))
            ;; Binary: the read fallback, quietly.
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.open"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,bin))
                         (gethash "jetpacs.files.open" jetpacs-action-handlers))
                        'accepted))
            (jetpacs-files-test--pump)
            (should (equal navigated
                           (list (cons (file-truename bin)
                                       "app:jetpacs.files"))))
            (should (= (length screens) 1))
            (should (null notes))
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
                           (ebp-check-path root (list root)
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

;;;; The five ops (F3)

(defmacro jetpacs-files-test--with-ops (bindings &rest body)
  "BODY with notifications, pushes and the prompts stubbed.
BINDINGS is a plist: :read-string and :completing-read are functions (or
values) substituted for the real prompts.  Binds NOTES (newest first)
and PUSHES in BODY's scope."
  (declare (indent 1))
  `(let ((notes '()) (pushes '()))
     (cl-letf (((symbol-function 'jetpacs-shell-notify)
                (lambda (text &optional _s) (push text notes)))
               ((symbol-function 'jetpacs-shell-push)
                (lambda (surface &rest _) (push surface pushes) 1))
               ((symbol-function 'read-string)
                ,(or (plist-get bindings :read-string)
                     '(lambda (&rest _) (error "read-string not expected"))))
               ((symbol-function 'completing-read)
                ,(or (plist-get bindings :completing-read)
                     '(lambda (&rest _) (error "completing-read not expected")))))
       (ignore notes pushes)
       ,@body)))

(ert-deftest jetpacs-files-duplicate-name-bumps ()
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "f.txt"))))
      (should (equal (jetpacs-files--duplicate-name f)
                     (concat root "f copy.txt")))
      (jetpacs-files-test--touch (concat root "f copy.txt"))
      (should (equal (jetpacs-files--duplicate-name f)
                     (concat root "f copy 2.txt")))
      (jetpacs-files-test--touch (concat root "f copy 2.txt"))
      (should (equal (jetpacs-files--duplicate-name f)
                     (concat root "f copy 3.txt"))))
    (make-directory (concat root "d"))
    (should (equal (jetpacs-files--duplicate-name (concat root "d"))
                   (concat root "d copy")))))

(ert-deftest jetpacs-files-op-rename-guards-and-renames ()
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "old.txt"))))
      ;; Success.
      (jetpacs-files-test--with-ops
          (:read-string (lambda (&rest _) "new.txt"))
        (jetpacs-files--op-rename f "app:jetpacs.files")
        (should (equal (car notes) "Renamed to new.txt"))
        (should (file-exists-p (concat root "new.txt")))
        (should-not (file-exists-p f))
        (should (equal pushes '("app:jetpacs.files"))))
      ;; Exists-refusal: never clobber (the absent-mode guard).
      (jetpacs-files-test--touch (concat root "taken.txt"))
      (jetpacs-files-test--touch f)
      (jetpacs-files-test--with-ops
          (:read-string (lambda (&rest _) "taken.txt"))
        (jetpacs-files--op-rename f "app:jetpacs.files")
        (should (equal (car notes) "Rename refused: exists"))
        (should (file-exists-p f)))
      ;; Separators never even reach the guard.
      (jetpacs-files-test--with-ops
          (:read-string (lambda (&rest _) "sub/evil"))
        (jetpacs-files--op-rename f "app:jetpacs.files")
        (should (equal (car notes) "Name can't contain '/'")))
      ;; C-g (rpc.cancel on device) is a clean cancel.
      (jetpacs-files-test--with-ops
          (:read-string (lambda (&rest _) (signal 'quit nil)))
        (jetpacs-files--op-rename f "app:jetpacs.files")
        (should (equal (car notes) "Rename cancelled"))
        (should (file-exists-p f))))))

(ert-deftest jetpacs-files-op-move-guards-and-moves ()
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "m.txt")))
          (sub (concat root "sub/"))
          (outside (file-name-as-directory
                    (make-temp-file "jetpacs-move-out" t))))
      (make-directory sub)
      (unwind-protect
          (progn
            ;; Success.
            (jetpacs-files-test--with-ops
                (:read-string (lambda (&rest _) sub))
              (jetpacs-files--op-move f "app:jetpacs.files")
              (should (file-exists-p (concat sub "m.txt")))
              (should-not (file-exists-p f))
              (should (string-prefix-p "Moved to " (car notes))))
            ;; No such destination.
            (jetpacs-files-test--touch f)
            (jetpacs-files-test--with-ops
                (:read-string (lambda (&rest _) (concat root "missing/")))
              (jetpacs-files--op-move f "app:jetpacs.files")
              (should (equal (car notes) "Move refused: not-a-directory"))
              (should (file-exists-p f)))
            ;; Outside the roots.
            (jetpacs-files-test--with-ops
                (:read-string (lambda (&rest _) outside))
              (jetpacs-files--op-move f "app:jetpacs.files")
              (should (equal (car notes) "Move refused: outside-roots"))
              (should (file-exists-p f)))
            ;; Target exists.
            (jetpacs-files-test--touch (concat sub "m.txt"))
            (jetpacs-files-test--with-ops
                (:read-string (lambda (&rest _) sub))
              (jetpacs-files--op-move f "app:jetpacs.files")
              (should (equal (car notes) "Move refused: exists"))
              (should (file-exists-p f))))
        (delete-directory outside t)))))

(ert-deftest jetpacs-files-op-duplicate-copies ()
  (jetpacs-files-test--with-tree root
    (let ((f (concat root "f.txt")))
      (write-region "content\n" nil f nil 'silent)
      (jetpacs-files-test--with-ops nil
        (jetpacs-files--op-duplicate f "app:jetpacs.files")
        (should (equal (car notes) "Duplicated to f copy.txt"))
        (should (file-exists-p (concat root "f copy.txt")))
        (with-temp-buffer
          (insert-file-contents (concat root "f copy.txt"))
          (should (equal (buffer-string) "content\n")))))
    (make-directory (concat root "d"))
    (jetpacs-files-test--touch (concat root "d/child"))
    (jetpacs-files-test--with-ops nil
      (jetpacs-files--op-duplicate (concat root "d") "app:jetpacs.files")
      (should (file-exists-p (concat root "d copy/child"))))))

(ert-deftest jetpacs-files-op-new-creates ()
  (jetpacs-files-test--with-tree root
    ;; A file.
    (jetpacs-files-test--with-ops
        (:read-string (lambda (&rest _) "n.org")
         :completing-read (lambda (&rest _) "File"))
      (jetpacs-files--op-new root "app:jetpacs.files")
      (should (equal (car notes) "Created n.org"))
      (should (file-regular-p (concat root "n.org"))))
    ;; A folder.
    (jetpacs-files-test--with-ops
        (:read-string (lambda (&rest _) "d")
         :completing-read (lambda (&rest _) "Folder"))
      (jetpacs-files--op-new root "app:jetpacs.files")
      (should (file-directory-p (concat root "d"))))
    ;; Traversal is refused before the guard even runs.
    (jetpacs-files-test--with-ops
        (:read-string (lambda (&rest _) "../evil"))
      (jetpacs-files--op-new root "app:jetpacs.files")
      (should (equal (car notes) "Name can't contain '/'")))
    ;; Exists-refusal.
    (jetpacs-files-test--with-ops
        (:read-string (lambda (&rest _) "n.org")
         :completing-read (lambda (&rest _) "File"))
      (jetpacs-files--op-new root "app:jetpacs.files")
      (should (equal (car notes) "Create refused: exists")))))

(ert-deftest jetpacs-files-delete-action-confirmed-effect ()
  "The handler never prompts — the Companion presented `:confirm'
before the event existed — and the effect is synchronous (14.4)."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let ((handler (gethash "jetpacs.files.delete" jetpacs-action-handlers))
            (f (jetpacs-files-test--touch (concat root "f.txt")))
            (notes '()) (pushed '()))
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notes)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (surface &rest _) (push surface pushed) 1)))
          ;; A file: gone synchronously, push deferred.
          (should (eq (jetpacs--dispatch
                       client `(:action "jetpacs.files.delete"
                                :surface "app:jetpacs.files"
                                :args (:path ,f))
                       handler)
                      'accepted))
          (should-not (file-exists-p f))
          (should (equal (car notes) "Deleted f.txt"))
          (should (null pushed))
          (jetpacs-files-test--pump)
          (should (equal pushed '("app:jetpacs.files")))
          ;; Already gone: the snapshot is outdated — stale, not an error.
          (should (eq (jetpacs--dispatch
                       client `(:action "jetpacs.files.delete"
                                :surface "app:jetpacs.files"
                                :args (:path ,f))
                       handler)
                      'stale))
          ;; A directory: recursive.
          (make-directory (concat root "d"))
          (jetpacs-files-test--touch (concat root "d/child"))
          (should (eq (jetpacs--dispatch
                       client `(:action "jetpacs.files.delete"
                                :surface "app:jetpacs.files"
                                :args (:path ,(concat root "d")))
                       handler)
                      'accepted))
          (should-not (file-exists-p (concat root "d")))
          ;; Out of policy.
          (should (eq (jetpacs--dispatch
                       client '(:action "jetpacs.files.delete"
                                :surface "app:jetpacs.files"
                                :args (:path "/etc/passwd"))
                       handler)
                      'rejected))
          (should (equal (car notes) "Delete refused: outside-roots"))
          (should (file-exists-p "/etc/passwd")))))))

(ert-deftest jetpacs-files-menu-gates-shows-and-routes ()
  "The menu: capability-gated, dialog deferred out of the extent, rows
concluding with op keys, and the callback re-entering through a fresh
flow to run the op."
  (jetpacs-files-test--with-tree root
    (let ((f (jetpacs-files-test--touch (concat root "old.txt"))))
      (jetpacs-files-test--attached (jetpacs-files-test--client)
        (let ((handler (gethash "jetpacs.files.menu" jetpacs-action-handlers))
              (shown '()) (notes '()))
          (cl-letf (((symbol-function 'jetpacs-shell-notify)
                     (lambda (text &optional _s) (push text notes)))
                    ((symbol-function 'ebp-client-dialog-show)
                     (cl-function
                      (lambda (_client id spec &key callback &allow-other-keys)
                        (push (list id spec callback) shown)))))
            ;; No grant: rejected, loudly.
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.menu"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,f))
                         handler)
                        'rejected))
            (should (equal (car notes) "Needs the dialog capability"))
            ;; Granted: accepted, and the dialog raised only after the
            ;; extent (D2).
            (setf (ebp-client-granted client) ["surfaces.dialog"])
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.menu"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,f))
                         handler)
                        'accepted))
            (should (null shown))
            (jetpacs-files-test--pump)
            (should (= (length shown) 1))
            (pcase-let ((`(,id ,spec ,callback) (car shown)))
              (should (string-prefix-p "files-" id))
              (should (equal (jetpacs-files-test--collect spec :value)
                             '("rename" "move" "duplicate")))
              ;; Four buttons: three ops and a way out.
              (should (= (seq-count (lambda (x) (equal x "button"))
                                    (jetpacs-files-test--collect spec :t))
                        4))
              ;; The callback runs the op through a FRESH flow (an ebp
              ;; callback's stack has no dispatch to inherit from).
              (let ((flowed '()))
                (cl-letf (((symbol-function 'jetpacs-flow-begin)
                           (lambda (surface fn)
                             (push surface flowed) (funcall fn)))
                          ((symbol-function 'read-string)
                           (lambda (&rest _) "renamed.txt"))
                          ((symbol-function 'jetpacs-shell-push)
                           (lambda (&rest _) 1)))
                  (funcall callback "submitted" '(:value "rename") nil)
                  (should (equal flowed '("app:jetpacs.files")))
                  (should (file-exists-p (concat root "renamed.txt")))
                  (should-not (file-exists-p f)))))
            ;; Two menus never share a dialog id (the 18.1 reuse trap).
            (jetpacs-files-test--pump)
            (let ((jetpacs-files--dialog-seq jetpacs-files--dialog-seq))
              (jetpacs-files--ops-menu-show f "app:jetpacs.files")
              (jetpacs-files--ops-menu-show f "app:jetpacs.files")
              (should (= (length shown) 3))
              (should-not (equal (car (nth 0 shown)) (car (nth 1 shown)))))
            ;; Out of policy: rejected before any dialog.
            (should (eq (jetpacs--dispatch
                         client '(:action "jetpacs.files.menu"
                                  :surface "app:jetpacs.files"
                                  :args (:path "/etc/passwd"))
                         handler)
                        'rejected))))))))

(ert-deftest jetpacs-files-new-action-gates-and-defers ()
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let ((handler (gethash "jetpacs.files.new" jetpacs-action-handlers))
            (ran '()) (notes '()))
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notes)))
                  ((symbol-function 'jetpacs-files--op-new)
                   (lambda (dir surface) (push (cons dir surface) ran))))
          ;; No grant: rejected.
          (should (eq (jetpacs--dispatch
                       client '(:action "jetpacs.files.new"
                                :surface "app:jetpacs.files")
                       handler)
                      'rejected))
          ;; Granted: accepted, op deferred with the validated dir.
          (setf (ebp-client-granted client) ["surfaces.dialog"])
          (should (eq (jetpacs--dispatch
                       client '(:action "jetpacs.files.new"
                                :surface "app:jetpacs.files")
                       handler)
                      'accepted))
          (should (null ran))
          (jetpacs-files-test--pump)
          (should (equal ran
                         (list (cons (ebp-check-path
                                      root (list root) :require 'directory)
                                     "app:jetpacs.files")))))))))

;;;; The plain editor (F4) + B11

(ert-deftest jetpacs-files-b11-and-the-editor-cap ()
  "B11: the accessor reads the welcome limit; the cap derives from the
TIGHTER of the event and frame bounds and never exceeds the custom
ceiling; offline it is the custom ceiling alone."
  ;; No client: accessor nil, cap = custom.
  (should-not (jetpacs-max-event-bytes))
  (let ((jetpacs-files-max-bytes 262144))
    (should (= (jetpacs-files--editor-cap) 262144)))
  ;; Attached: the declared limits drive the derivation.
  (jetpacs-files-test--attached (jetpacs-files-test--client)
    (setf (ebp-client-limits client) '(:max_event_bytes 300000))
    (should (= (jetpacs-max-event-bytes) 300000))
    (let ((jetpacs-files-max-bytes 262144))
      ;; Event bound only: (300000 - 16384) / 4.
      (should (= (jetpacs-files--editor-cap) 70904))
      ;; The frame bound is TIGHTER here and must win.
      (setf (ebp-client-limits client)
            '(:max_event_bytes 300000 :max_frame_bytes 100000))
      (should (= (jetpacs-files--editor-cap)
                 (/ (- (cdr (jetpacs-buffer-budgets)) 16384) 4)))
      ;; The custom ceiling always binds from above.
      (let ((jetpacs-files-max-bytes 1000))
        (should (= (jetpacs-files--editor-cap) 1000))))))

(ert-deftest jetpacs-files-mtime-stamp-is-opaque-and-changes ()
  (jetpacs-files-test--with-tree root
    (should-not (jetpacs-files--mtime-stamp (concat root "missing")))
    (let ((f (jetpacs-files-test--touch (concat root "f"))))
      (let ((s1 (jetpacs-files--mtime-stamp f)))
        (should (stringp s1))
        (should (equal s1 (jetpacs-files--mtime-stamp f)))
        (sleep-for 0.02)
        (write-region "x" nil f nil 'silent)
        (should-not (equal s1 (jetpacs-files--mtime-stamp f)))))))

(ert-deftest jetpacs-files-edit-open-routes-by-eligibility ()
  (jetpacs-files-test--with-tree root
    (let ((f (concat root "f.txt"))
          (raw (concat root "raw.txt"))
          (screens '()) (navigated '()) (notes '())
          (jetpacs-files--edit nil))
      (write-region "hello\n" nil f nil 'silent)
      (write-region "placeholder\n" nil raw nil 'silent)
      (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                 (lambda (surface id builder)
                   (push (list surface id builder) screens) 1))
                ((symbol-function 'jetpacs-navigate-buffer)
                 (lambda (buf _surface &rest _) (push buf navigated)))
                ((symbol-function 'jetpacs-shell-notify)
                 (lambda (text &optional _s) (push text notes))))
        ;; Eligible.
        (should-not (jetpacs-files--edit-open (file-truename f) "app:jetpacs.files"))
        (should (= (length screens) 1))
        (should (equal (plist-get jetpacs-files--edit :seed) "hello\n"))
        ;; Oversize: told, and read-only.
        (let ((jetpacs-files-max-bytes 4))
          (should (eq (jetpacs-files--edit-open (file-truename f)
                                                "app:jetpacs.files")
                      'oversize)))
        (should (equal (car notes) "Too large to edit here — read-only"))
        (should (= (length navigated) 1))
        ;; Unsaved desktop edits: told, and read-only.
        (let ((buf (find-file-noselect (file-truename f))))
          (unwind-protect
              (progn
                (with-current-buffer buf (goto-char (point-max)) (insert "z"))
                (should (eq (jetpacs-files--edit-open (file-truename f)
                                                      "app:jetpacs.files")
                            'desktop-modified))
                (should (equal (car notes)
                               "Unsaved desktop edits — read-only")))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))
        ;; Undecodable content: quietly read-only — the round-trip would
        ;; corrupt exactly the bytes the wire cannot carry.  The
        ;; raw-byte char is SYNTHESIZED rather than written to disk: on
        ;; this platform coding detection resolves every stray octet to
        ;; a real character (latin-1 wins, and even a forced utf-8 read
        ;; of byte 200 yields U+00C8, not #x3FFFC8), so no fixture file
        ;; reaches the branch through `insert-file-contents'.  Raw-byte
        ;; chars do occur — a literal read, a buffer sliced from binary
        ;; — and this pins the routing for when they do.
        (let ((before (length notes)))
          (cl-letf (((symbol-function 'insert-file-contents)
                     (lambda (&rest _) (insert "caf" (string #x3FFFC8) "e\n")))
                    ;; The fallback reads the file too; keep the stub off
                    ;; its path so this leg tests ROUTING, not find-file.
                    ((symbol-function 'find-file-noselect)
                     (lambda (&rest _) (get-buffer-create "*f4-raw*"))))
            (should (eq (jetpacs-files--edit-open (file-truename raw)
                                                  "app:jetpacs.files")
                        'unencodable)))
          (should (= (length notes) before)))
        (should (= (length screens) 1))))))

(ert-deftest jetpacs-files-edit-screen-shape ()
  (jetpacs-files-test--with-tree root
    (let* ((f (jetpacs-files-test--touch (concat root "notes.org")))
           (jetpacs-files--edit (list :path (file-truename f)
                                      :seed "seed text"
                                      :mtime "123.000000")))
      (let ((screen (jetpacs-files--edit-screen nil)))
        (should (member "notes.org" (jetpacs-files-test--collect screen :text)))
        (should (equal (jetpacs-files-test--collect screen :value)
                       '("seed text")))
        (should (member "jetpacs.files.save"
                        (jetpacs-files-test--collect screen :action)))
        (let ((args (car (jetpacs-files-test--collect screen :args))))
          (should (equal (plist-get args :path) (file-truename f)))
          (should (equal (plist-get args :mtime) "123.000000")))
        (should (cl-some (lambda (id) (string-prefix-p "fedit-" id))
                         (jetpacs-files-test--collect screen :id)))))
    (let ((jetpacs-files--edit nil))
      (should (member "empty_state"
                      (jetpacs-files-test--collect
                       (jetpacs-files--edit-screen nil) :t))))))

(defun jetpacs-files-test--sync-client ()
  "A client that can host the SYNCHRONIZED rung: `editor.sync' granted,
`editor' advertised for the app target, and a §19 `max_editor_bytes'."
  (let ((client (jetpacs-files-test--client)))
    (setf (ebp-client-granted client) '("editor.sync")
          (ebp-client-limits client) '(:max_editor_bytes 65536)
          (ebp-client-profiles client)
          `(:app (:node_types ,(vconcat jetpacs-files-test--app-types
                                        ["editor"])
                  :builtins ["view.switch"] :features [])))
    client))

(ert-deftest jetpacs-files-edit-open-climbs-to-the-synced-rung ()
  "The top rung is the DEFAULT for a file that qualifies: the buffer is
attached BEFORE the push and never in the builder, the record carries
the session keys, and the document id keeps its extension."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--sync-client)
      (let ((f (concat root "lib.el"))
            (screens '()) (attached '())
            (jetpacs-files--edit nil))
        (write-region "(defun f ())\n" nil f nil 'silent)
        (unwind-protect
            (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                       (lambda (surface id builder)
                         ;; ATTACH BEFORE THE PUSH: the record is
                         ;; already complete when the builder could run.
                         (push (list surface id builder) screens)
                         (should (plist-get jetpacs-files--edit :document))
                         1))
                      ((symbol-function 'ebp-sync-attach)
                       (lambda (_c doc eid buf) (push (list doc eid buf) attached)
                         buf)))
              (let ((true (file-truename f)))
                (should-not (jetpacs-files--edit-open true "app:jetpacs.files"))
                (should (= (length screens) 1))
                (should (= (length attached) 1))
                (pcase-let ((`(,doc ,eid ,buf) (car attached)))
                  ;; The mint keeps the extension — it is what
                  ;; `ebp-complete--mode-for' matches against
                  ;; `auto-mode-alist' to pick the shadow's mode.
                  (should (string-prefix-p "doc:" doc))
                  (should (string-suffix-p ".el" doc))
                  ;; The editor id MUST be the node id: that is what the
                  ;; Companion stamps into every §19 frame, so a routing
                  ;; key registered under anything else never matches and
                  ;; the whole session lands nowhere (found on device).
                  (should (equal eid (jetpacs-wire-id "fedit" true)))
                  (should (buffer-live-p buf))
                  (should (equal (buffer-file-name buf) true))
                  (with-current-buffer buf
                    ;; Phone keystrokes must not litter #autosave# files.
                    (should-not buffer-auto-save-file-name))
                  (should (eq buf (plist-get jetpacs-files--edit :buffer))))
                ;; And the builder emits a node under exactly that id.
                (should (member (plist-get jetpacs-files--edit :editor-id)
                                (jetpacs-files-test--collect
                                 (jetpacs-files--edit-screen nil) :id)))
                ;; The screen the builder produces carries the session.
                (let ((screen (jetpacs-files--edit-screen nil)))
                  (should (member (plist-get jetpacs-files--edit :document)
                                  (jetpacs-files-test--collect screen :document)))
                  (should (member "elisp"
                                  (jetpacs-files-test--collect screen :syntax)))
                  ;; The reconnect seed still rides (SPEC 19.3), and so
                  ;; does on_save.
                  (should (equal (jetpacs-files-test--collect screen :value)
                                 '("(defun f ())\n")))
                  (should (member "jetpacs.files.save"
                                  (jetpacs-files-test--collect screen :action))))
                ;; Building again attaches NOTHING: the chrome rebuilds
                ;; the whole stack per push, and a binding remade there
                ;; would discard unflushed edits every time.
                (jetpacs-files--edit-screen nil)
                (should (= (length attached) 1))))
          (when-let* ((buf (plist-get jetpacs-files--edit :buffer)))
            (when (buffer-live-p buf)
              (with-current-buffer buf (set-buffer-modified-p nil))
              (kill-buffer buf))))))))

(ert-deftest jetpacs-files-edit-open-degrades-to-the-plain-rung ()
  "Each way down the ladder: the toggle off, the capability ungranted,
and past `max_editor_bytes' but within the plain cap.  All three land
on the PLAIN editor — no document, no attach, still editable."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--sync-client)
      (let ((f (concat root "lib.el"))
            (attached 0)
            (jetpacs-files--edit nil))
        (write-region "(defun f ())\n" nil f nil 'silent)
        (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                   (lambda (&rest _) 1))
                  ((symbol-function 'ebp-sync-attach)
                   (lambda (_c _d _e buf) (cl-incf attached) buf)))
          (let ((true (file-truename f)))
            (let ((jetpacs-files-sync-editor nil))
              (should-not (jetpacs-files--edit-open true "app:jetpacs.files"))
              (should-not (plist-get jetpacs-files--edit :document)))
            (setf (ebp-client-granted client) nil)
            (should-not (jetpacs-files--edit-open true "app:jetpacs.files"))
            (should-not (plist-get jetpacs-files--edit :document))
            (setf (ebp-client-granted client) '("editor.sync"))
            ;; Past the §19 bound but inside the plain one: the plain
            ;; editor, not a lost editor.
            (setf (ebp-client-limits client) '(:max_editor_bytes 4))
            (should-not (jetpacs-files--edit-open true "app:jetpacs.files"))
            (should-not (plist-get jetpacs-files--edit :document))
            (should (= attached 0))))))))

(ert-deftest jetpacs-files-edit-open-sync-keeps-unsaved-desktop-edits ()
  "The desktop-modified refusal belongs to the rungs that would LOSE
the text.  The synchronized rung seeds from the BUFFER, so it opens —
and the seed is the buffer's text, which is what makes the Companion's
reseed a no-op instead of a silent revert."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--sync-client)
      (let ((f (concat root "lib.el"))
            (jetpacs-files--edit nil))
        (write-region "(defun f ())\n" nil f nil 'silent)
        (let ((buf (find-file-noselect (file-truename f))))
          (unwind-protect
              (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                         (lambda (&rest _) 1))
                        ((symbol-function 'ebp-sync-attach)
                         (lambda (_c _d _e b) b)))
                (with-current-buffer buf
                  (goto-char (point-max)) (insert ";; local\n"))
                (should-not (jetpacs-files--edit-open (file-truename f)
                                                      "app:jetpacs.files"))
                (should (plist-get jetpacs-files--edit :document))
                (should (equal (plist-get jetpacs-files--edit :seed)
                               "(defun f ())\n;; local\n"))
                ;; Without sync the same buffer refuses, as before.
                (let ((jetpacs-files-sync-editor nil)
                      (navigated '()))
                  (cl-letf (((symbol-function 'jetpacs-navigate-buffer)
                             (lambda (b &rest _) (push b navigated)))
                            ((symbol-function 'jetpacs-shell-notify) #'ignore))
                    (should (eq (jetpacs-files--edit-open (file-truename f)
                                                          "app:jetpacs.files")
                                'desktop-modified)))))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))))))

(ert-deftest jetpacs-files-document-id-is-extension-preserving ()
  "NOT `jetpacs-wire-id': that appends the sha1 LAST, and the document
id is what `ebp-complete--mode-for' matches against `auto-mode-alist'."
  (let ((el (jetpacs-files--document-id "/home/x/init.el"))
        (none (jetpacs-files--document-id "/home/x/README")))
    (should (string-prefix-p "doc:" el))
    (should (string-suffix-p ".el" el))
    (should (equal el (jetpacs-files--document-id "/home/x/init.el")))
    (should-not (equal el (jetpacs-files--document-id "/home/y/init.el")))
    (should-not (string-match-p "\\." (substring none 4)))
    ;; A legal SPEC 4.4 identifier: begins alnum, allowed charset only.
    (should (string-match-p "\\`doc:[a-z0-9]+\\(\\.[A-Za-z0-9]+\\)?\\'" el))))

(ert-deftest jetpacs-files-save-guards-then-writes ()
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      ;; `let*', not `let': a lambda in a PARALLEL let cannot see its
      ;; sibling binding, so `hooked' would compile as a free (dynamic)
      ;; reference and signal `void-variable' when the hook runs — which
      ;; is exactly how the isolation defect below was found.
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "f.txt"))
             (hooked '()) (notes '()) (pushed '())
             (jetpacs-files--edit nil)
             (jetpacs-files-after-save-hook
              (list (lambda (path) (push path hooked)))))
        (write-region "old\n" nil f nil 'silent)
        (cl-letf (((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notes)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (surface &rest _) (push surface pushed) 1)))
        (let ((true (file-truename f)))
          (setq jetpacs-files--edit
                (list :path true :seed "old\n"
                      :mtime (jetpacs-files--mtime-stamp true)))
          ;; Happy path, no visiting buffer.
          (should (eq (jetpacs--dispatch
                       client `(:action "jetpacs.files.save"
                                :surface "app:jetpacs.files"
                                :args (:path ,true
                                       :mtime ,(jetpacs-files--mtime-stamp true)
                                       :value "new\n"))
                       handler)
                      'accepted))
          (with-temp-buffer
            (insert-file-contents true)
            (should (equal (buffer-string) "new\n")))
          (should (equal (car notes) "Saved f.txt"))
          (should (equal hooked (list true)))
          ;; The edit state re-stamped for the NEXT save.
          (should (equal (plist-get jetpacs-files--edit :seed) "new\n"))
          (should (equal (plist-get jetpacs-files--edit :mtime)
                         (jetpacs-files--mtime-stamp true)))
          (should (null pushed))
          (jetpacs-files-test--pump)
          (should (equal pushed '("app:jetpacs.files")))
          ;; Stale stamp: the disk moved on — nothing written.
          (let ((old-stamp (jetpacs-files--mtime-stamp true)))
            (sleep-for 0.02)
            (write-region "external\n" nil true nil 'silent)
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.save"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,true :mtime ,old-stamp
                                         :value "clobber\n"))
                         handler)
                        'stale))
            (should (equal (car notes) "File changed on disk — not saved"))
            (with-temp-buffer
              (insert-file-contents true)
              (should (equal (buffer-string) "external\n"))))
          ;; A modified visiting buffer refuses; an unmodified one is the
          ;; save route — WIDENED, mode intact, buffer left unmodified.
          (let ((buf (find-file-noselect true)))
            (unwind-protect
                (progn
                  (with-current-buffer buf
                    (goto-char (point-max)) (insert "local"))
                  (should (eq (jetpacs--dispatch
                               client `(:action "jetpacs.files.save"
                                        :surface "app:jetpacs.files"
                                        :args (:path ,true
                                               :mtime ,(jetpacs-files--mtime-stamp true)
                                               :value "v2\n"))
                               handler)
                              'rejected))
                  (should (equal (car notes)
                                 "Unsaved desktop edits — not saved"))
                  (with-current-buffer buf
                    (set-buffer-modified-p nil)
                    (revert-buffer nil t)
                    (narrow-to-region (point-min) (1+ (point-min))))
                  (should (eq (jetpacs--dispatch
                               client `(:action "jetpacs.files.save"
                                        :surface "app:jetpacs.files"
                                        :args (:path ,true
                                               :mtime ,(jetpacs-files--mtime-stamp true)
                                               :value "v3 whole\n"))
                               handler)
                              'accepted))
                  ;; The whole content is replaced and the buffer is left
                  ;; WIDENED — the write-first route refreshes the
                  ;; visiting buffer via `revert-buffer', which widens,
                  ;; and after a full swap a surviving narrowing would
                  ;; show a lie.
                  (with-current-buffer buf
                    (should (equal (buffer-string) "v3 whole\n"))
                    (should (= (point-min) 1))
                    (should (= (point-max) (1+ (buffer-size))))
                    (should-not (buffer-modified-p)))
                  (with-temp-buffer
                    (insert-file-contents true)
                    (should (equal (buffer-string) "v3 whole\n"))))
              (with-current-buffer buf (set-buffer-modified-p nil))
              (kill-buffer buf)))
          ;; Oversize, wrong type, out of policy.
          (let ((jetpacs-files-max-bytes 4))
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.save"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,true
                                         :mtime ,(jetpacs-files--mtime-stamp true)
                                         :value "12345"))
                         handler)
                        'rejected))
            (should (equal (car notes) "Save too large")))
          (should (eq (jetpacs--dispatch
                       client `(:action "jetpacs.files.save"
                                :surface "app:jetpacs.files"
                                :args (:path ,true :mtime "x" :value 5))
                       handler)
                      'rejected))
          (should (eq (jetpacs--dispatch
                       client '(:action "jetpacs.files.save"
                                :surface "app:jetpacs.files"
                                :args (:path "/etc/hostname" :mtime "x"
                                       :value "v"))
                       handler)
                      'rejected))
          (should (equal (car notes) "Save refused: outside-roots"))
          ;; Saving the init file gets the honest instruction.
          (let ((user-init-file true))
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.save"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,true
                                         :mtime ,(jetpacs-files--mtime-stamp true)
                                         :value "init\n"))
                         handler)
                        'accepted))
            (should (equal (car notes)
                           "Saved init — restart Emacs to apply config changes")))))))))

(ert-deftest jetpacs-files-save-synced-leg-writes-the-buffer ()
  "Under SPEC 19 sync the BUFFER is the authority, not the frame's
`value': the save flushes, writes the buffer, never reverts (a re-read
is a change track-changes would echo as a spurious edit.apply), and the
desktop-modified refusal does not apply — a synced buffer is
intentionally modified by every device keystroke.  The mtime gate is
orthogonal to sync and still answers `stale'."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "f.el"))
             (notes '()) (flushed '()) (reverted 0)
             (jetpacs-files--edit nil))
        (write-region "old\n" nil f nil 'silent)
        (let* ((true (file-truename f))
               (buf (find-file-noselect true)))
          (unwind-protect
              (cl-letf (((symbol-function 'jetpacs-shell-notify)
                         (lambda (text &optional _s) (push text notes)))
                        ((symbol-function 'jetpacs-shell-push)
                         (lambda (&rest _) 1))
                        ((symbol-function 'ebp-sync-buffer)
                         (lambda (_c _d _e) buf))
                        ((symbol-function 'ebp-sync-flush)
                         (lambda (&optional b) (push b flushed)))
                        ((symbol-function 'revert-buffer)
                         (lambda (&rest _) (cl-incf reverted))))
                (with-current-buffer buf
                  (erase-buffer)
                  (insert "from the buffer\n"))
                (setq jetpacs-files--edit
                      (list :path true :seed "old\n"
                            :mtime (jetpacs-files--mtime-stamp true)
                            :coding nil
                            :document "doc:abc.el" :editor-id "body"))
                ;; The device's `value' DISAGREES on purpose: the buffer
                ;; is the superset, and it is what lands on disk.
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.save"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,true
                                             :mtime ,(jetpacs-files--mtime-stamp true)
                                             :value "from the device\n"))
                             handler)
                            'accepted))
                (with-temp-buffer
                  (insert-file-contents true)
                  (should (equal (buffer-string) "from the buffer\n")))
                (should (equal flushed (list buf)))
                (should (= reverted 0))
                (with-current-buffer buf
                  (should-not (buffer-modified-p)))
                ;; The seed record follows the buffer, and the session
                ;; keys survive the re-stamp (they are the builder's).
                (should (equal (plist-get jetpacs-files--edit :seed)
                               "from the buffer\n"))
                (should (equal (plist-get jetpacs-files--edit :document)
                               "doc:abc.el"))
                ;; A stale stamp still refuses, sync or no sync.
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.save"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,true :mtime "0.0"
                                             :value "clobber\n"))
                             handler)
                            'stale))
                (with-temp-buffer
                  (insert-file-contents true)
                  (should (equal (buffer-string) "from the buffer\n"))))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))))))

(ert-deftest jetpacs-files-save-synced-leaves-the-buffer-unmodified ()
  "The whole synchronized round trip with NOTHING about sync stubbed —
a real `ebp-sync-attach', a real inbound `edit.delta', the real save
verb — because the sibling above stubs `ebp-sync-buffer' and
`ebp-sync-flush' and therefore never runs a line of the bridge.  On
device the flag came back `t' after a save that had cleared it, and the
stubs are why no suite could see it.

The buffer must be clean at every point where nothing has been typed:
after an attach that finds the session already open (a reconnect, or a
second open of a file whose editor is still on a present surface), and
after each save.  A DEVICE KEYSTROKE is the one thing that legitimately
marks it, and that is asserted too — a guard that clamped the flag
would pass everything else here and lose the user's edits."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--sync-client)
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "f.el"))
             (doc "doc:f.el") (eid "fedit-1")
             (session (make-string 32 ?a))
             (sent '())
             (jetpacs-files--edit nil))
        (write-region "(defun f ())\n" nil f nil 'silent)
        (let* ((true (file-truename f))
               (buf nil))
          (unwind-protect
              (cl-letf (((symbol-function 'ebp-client--request)
                         (lambda (_c method params cb &optional _t)
                           (push (list method params cb) sent) nil))
                        ;; The annotation riders fire from timers the pump
                        ;; below runs; unstubbed they reach jsonrpc and
                        ;; spray "Error running timer" through the gate log.
                        ((symbol-function 'ebp-client-notify)
                         (lambda (_c method params)
                           (push (list method params nil) sent) nil))
                        ((symbol-function 'jetpacs-shell-notify) #'ignore)
                        ((symbol-function 'jetpacs-shell-push)
                         (lambda (&rest _) 1)))
                ;; The Companion has the session open over the file's own
                ;; text — the state every reconnect and every re-open of a
                ;; live editor arrives in.
                (ebp-client--handle-edit-open
                 client (list :document doc :editor_id eid :session session
                              :seq 0 :text "(defun f ())\n" :cursor 0))
                (setq buf (find-file-noselect true))
                (ebp-sync-attach client doc eid buf)
                ;; ATTACH MUST NOT DIRTY A BUFFER THAT ALREADY AGREES.
                (with-current-buffer buf (should-not (buffer-modified-p)))
                (setq jetpacs-files--edit
                      (list :path true :seed "(defun f ())\n"
                            :mtime (jetpacs-files--mtime-stamp true)
                            :coding nil
                            :document doc :editor-id eid :buffer buf))
                ;; One device keystroke: this SHOULD leave the flag set.
                (ebp-client--handle-edit-delta
                 client (list :document doc :editor_id eid :session session
                              :seq 1 :start 12 :del 0 :text "x" :len 14))
                (with-current-buffer buf
                  (should (buffer-modified-p))
                  (should (equal (buffer-string) "(defun f ())x\n")))
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.save"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,true
                                             :mtime ,(jetpacs-files--mtime-stamp true)
                                             :value "(defun f ())x\n"))
                             handler)
                            'accepted))
                (with-temp-buffer
                  (insert-file-contents true)
                  (should (equal (buffer-string) "(defun f ())x\n")))
                (with-current-buffer buf (should-not (buffer-modified-p)))
                ;; The post-save legs the device actually runs, in order:
                ;; the annotation timers the keystroke armed, a reseed
                ;; carrying the text the save recorded, and a re-attach
                ;; over the still-live session.  None of them is a user
                ;; edit, so none of them may set the flag.
                (jetpacs-files-test--pump)
                (with-current-buffer buf (should-not (buffer-modified-p)))
                (ebp-client--handle-edit-open
                 client (list :document doc :editor_id eid
                              :session (make-string 32 ?b) :seq 0
                              :text (plist-get jetpacs-files--edit :seed)
                              :cursor 0))
                (with-current-buffer buf (should-not (buffer-modified-p)))
                (ebp-sync-attach client doc eid buf)
                (with-current-buffer buf (should-not (buffer-modified-p)))
                ;; And a genuinely DIFFERENT seed still adopts — the guard
                ;; skips the no-op, it does not stop the bridge working.
                (ebp-client--handle-edit-open
                 client (list :document doc :editor_id eid
                              :session (make-string 32 ?c) :seq 0
                              :text "(defun g ())\n" :cursor 0))
                (ebp-sync-attach client doc eid buf)
                (with-current-buffer buf
                  (should (equal (buffer-string) "(defun g ())\n"))))
            (when (buffer-live-p buf)
              (with-current-buffer buf (set-buffer-modified-p nil))
              (kill-buffer buf))))))))

(ert-deftest jetpacs-files-save-synced-sends-outside-the-coding-binding ()
  "The synchronized save's flush must not run inside the write's
`coding-system-for-write' binding.  The whole bridge is real down to
`ebp-client--request', which is the last rung before jsonrpc.el and
therefore the honest place to read the dynamic environment the outbound
`edit.apply' is issued in: what it observes is what any encoder on that
path would use.

This is HARDENING, not a repair of a live corruption.  `ebp-connect'
pins the socket `:coding utf-8-unix' at creation and Emacs consults
`coding-system-for-write' for a process only THERE, never at
`process-send-string' time, so today's frames are UTF-8 whatever is
bound around them.  The binding is still wrong to hold across a send —
it is ambient state leaking past the one write it was captured for, and
the send is re-entrant (a frame that fills the socket buffer blocks in
`send_process', which runs timers, which is how jsonrpc.el dispatches),
so an inbound handler can run arbitrary file I/O underneath it.  The
`write-region' keeps the binding; the wire does not."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--sync-client)
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "f.el"))
             (doc "doc:f.el") (eid "fedit-1")
             (session (make-string 32 ?a))
             (seed "(defun f ())\n")
             (observed 'unset) (methods '())
             (jetpacs-files--edit nil))
        (write-region seed nil f nil 'silent)
        (let* ((true (file-truename f))
               (buf nil))
          (unwind-protect
              (cl-letf (((symbol-function 'ebp-client--request)
                         (lambda (_c method _params _cb &optional _t)
                           (push method methods)
                           (when (eq method 'edit.apply)
                             (setq observed coding-system-for-write))
                           nil))
                        ((symbol-function 'ebp-client-notify)
                         (lambda (&rest _) nil))
                        ((symbol-function 'jetpacs-shell-notify) #'ignore)
                        ((symbol-function 'jetpacs-shell-push)
                         (lambda (&rest _) 1)))
                (ebp-client--handle-edit-open
                 client (list :document doc :editor_id eid :session session
                              :seq 0 :text seed :cursor 0))
                (setq buf (find-file-noselect true))
                (ebp-sync-attach client doc eid buf)
                (setq jetpacs-files--edit
                      (list :path true :seed seed
                            :mtime (jetpacs-files--mtime-stamp true)
                            ;; The file's own coding, captured at open —
                            ;; the value the write legitimately needs and
                            ;; the send legitimately must not see.
                            :coding 'iso-latin-1
                            :document doc :editor-id eid :buffer buf))
                ;; A DESKTOP edit the tracker has seen but has not sent:
                ;; the only state in which the save's flush actually
                ;; reaches the wire, and therefore the only one that can
                ;; observe the leak.  The non-ASCII char also proves the
                ;; write kept its coding.
                (with-current-buffer buf
                  (goto-char (point-max))
                  (insert ";; caf\N{LATIN SMALL LETTER E WITH ACUTE}\n"))
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.save"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,true
                                             :mtime ,(jetpacs-files--mtime-stamp true)
                                             :value ,seed))
                             handler)
                            'accepted))
                ;; The flush still HAPPENS — a hoist that simply dropped
                ;; the send would satisfy the assertion below otherwise.
                (should (memq 'edit.apply methods))
                ;; ...and it is issued under the ambient coding, not the
                ;; edited file's.
                (should (eq observed nil))
                ;; ...while the write itself still honors the file's own
                ;; coding: latin-1 puts e-acute on disk as the single
                ;; octet #xE9, which UTF-8 would have written as two.
                (with-temp-buffer
                  (set-buffer-multibyte nil)
                  (insert-file-contents-literally true)
                  (should (string-search "\xe9" (buffer-string)))))
            (when (buffer-live-p buf)
              (with-current-buffer buf (set-buffer-modified-p nil))
              (kill-buffer buf))))))))

(ert-deftest jetpacs-files-save-synced-writes-the-whole-buffer ()
  "A NARROWED synced buffer saves the whole file, not the accessible
portion.  `write-region' and `buffer-substring-no-properties' both honor
the restriction, so under a narrowing the save wrote only the visible
region over the file, cleared the modified flag (destroying the user's
recovery path), and re-stamped the reconnect seed to the truncated text.
Narrowing a file buffer is ordinary Emacs — `jetpacs-org-render' even
renders a widen affordance for it — so this was reachable, silent, and
unrecoverable."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "f.txt"))
             (whole "AAA\nBBB\nCCC\n")
             (jetpacs-files--edit nil))
        (write-region whole nil f nil 'silent)
        (let* ((true (file-truename f))
               (buf (find-file-noselect true)))
          (unwind-protect
              (cl-letf (((symbol-function 'jetpacs-shell-notify) #'ignore)
                        ((symbol-function 'jetpacs-shell-push)
                         (lambda (&rest _) 1))
                        ((symbol-function 'ebp-sync-buffer)
                         (lambda (_c _d _e) buf))
                        ((symbol-function 'ebp-sync-flush) #'ignore))
                (with-current-buffer buf
                  (goto-char (point-min))
                  (narrow-to-region 5 9)
                  (should (equal (buffer-string) "BBB\n")))
                (setq jetpacs-files--edit
                      (list :path true :seed whole
                            :mtime (jetpacs-files--mtime-stamp true)
                            :coding nil
                            :document "doc:f.txt" :editor-id "body"))
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.save"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,true
                                             :mtime ,(jetpacs-files--mtime-stamp true)
                                             :value ,whole))
                             handler)
                            'accepted))
                ;; The file keeps the lines outside the restriction...
                (with-temp-buffer
                  (insert-file-contents true)
                  (should (equal (buffer-string) whole)))
                ;; ...and so does the reconnect seed, which must describe
                ;; what actually landed on disk or the next `edit.open'
                ;; reseeds the device from truncated text.
                (should (equal (plist-get jetpacs-files--edit :seed) whole))
                ;; The restriction itself is the user's, and survives.
                (with-current-buffer buf
                  (should (equal (buffer-string) "BBB\n"))))
            (with-current-buffer buf
              (widen)
              (set-buffer-modified-p nil))
            (kill-buffer buf)))))))

(ert-deftest jetpacs-files-save-survives-a-broken-seam ()
  "A save whose after-save subscriber SIGNALS still answers `accepted'.
The write is already durable when the seam runs; letting the signal
escape would answer `rejected', which SPEC 14.4 makes PERMANENT — the
Companion would re-deliver a save that already landed.  (This is how
the defect was found: a test whose hook lambda died on a free variable
flipped an otherwise-perfect save to `rejected'.)"
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "f.txt"))
             (jetpacs-files--edit nil)
             (jetpacs-files-after-save-hook
              (list (lambda (_path) (error "seam exploded")))))
        (write-region "old\n" nil f nil 'silent)
        (cl-letf (((symbol-function 'jetpacs-shell-notify) #'ignore)
                  ((symbol-function 'jetpacs-shell-push) (lambda (&rest _) 1)))
          (let ((true (file-truename f)))
            (should (eq (jetpacs--dispatch
                         client `(:action "jetpacs.files.save"
                                  :surface "app:jetpacs.files"
                                  :args (:path ,true
                                         :mtime ,(jetpacs-files--mtime-stamp true)
                                         :value "new\n"))
                         handler)
                        'accepted))
            (with-temp-buffer
              (insert-file-contents true)
              (should (equal (buffer-string) "new\n")))))))))

;;;; The editor app seams (F5)

(ert-deftest jetpacs-files-editor-seams-feed-the-screen ()
  "All four seams reach their slots; a body seam that passes (nil)
falls through to the plain editor."
  (jetpacs-files-test--with-tree root
    (let* ((f (jetpacs-files-test--touch (concat root "notes.org")))
           (jetpacs-files--edit (list :path (file-truename f)
                                      :seed "seed" :mtime "1.000000"))
           (seen '()))
      ;; Defaults: the plain editor, no actions, no fab, no toolbar.
      (let ((screen (jetpacs-files--edit-screen nil)))
        (should (member "editor" (jetpacs-files-test--collect screen :t)))
        (should-not (jetpacs-files-test--collect screen :toolbar)))
      ;; All four attached.
      (let* ((jetpacs-files-editor-body-functions
              (list (lambda (path) (push (cons 'body path) seen) nil)
                    (lambda (_path) (jetpacs-text "org outline instead"))))
             (jetpacs-files-editor-actions-functions
              (list (lambda (_p) (list (jetpacs-icon-button
                                        "toc" (jetpacs-action "demo.outline")
                                        :content-description "Outline")))
                    (lambda (_p) (list (jetpacs-icon-button
                                        "language" (jetpacs-action "demo.render")
                                        :content-description "Rendered")))))
             (jetpacs-files-editor-toolbar-function (lambda (_p) "orgtb"))
             (jetpacs-files-editor-fab-function
              (lambda (_p) (jetpacs-icon-button
                            "add" (jetpacs-action "demo.add")
                            :content-description "Add heading")))
             (screen (jetpacs-files--edit-screen nil)))
        ;; The second body fn REPLACED the editor (first passed).
        (should (equal (car seen) (cons 'body (file-truename f))))
        (should (member "org outline instead"
                        (jetpacs-files-test--collect screen :text)))
        (should-not (member "editor" (jetpacs-files-test--collect screen :t)))
        ;; Both action providers appended into the top bar.
        (should (member "demo.outline"
                        (jetpacs-files-test--collect screen :action)))
        (should (member "demo.render"
                        (jetpacs-files-test--collect screen :action)))
        ;; The fab landed in the scaffold slot.
        (should (member "demo.add"
                        (jetpacs-files-test--collect screen :action))))
      ;; Toolbar without a body override: rides the editor node.
      (let* ((jetpacs-files-editor-toolbar-function (lambda (_p) "orgtb"))
             (screen (jetpacs-files--edit-screen nil)))
        (should (equal (jetpacs-files-test--collect screen :toolbar)
                       '("orgtb")))))))

;;;; JA-6 P1 regressions (docs/AUDIT-ja6-2026-07-28.md)

;; P1-1: destructive ops act on the LITERAL directory entry, with
;; containment confirmed on BOTH sides (the truename AND the parent's
;; truename plus the final component).  These drive the REAL
;; dispatch/menu pipeline because that is where the truename
;; substitution happened — direct op calls could not tell pre from
;; post fix.

(ert-deftest jetpacs-files-delete-unlinks-a-symlink-never-follows ()
  "Delete acts on the entry the user confirmed: a symlink is UNLINKED,
never followed (the truename route recursively deleted the link's
TARGET tree); a dangling link is a deletable entry, not `stale'; and
an out-of-sandbox entry pointing INTO a root is refused on the literal
side rather than admitted through its truename."
  (jetpacs-files-test--with-tree root
    (let ((outside (file-name-as-directory
                    (make-temp-file "jetpacs-del-out" t))))
      (unwind-protect
          (jetpacs-files-test--attached (jetpacs-files-test--client)
            (let ((handler (gethash "jetpacs.files.delete"
                                    jetpacs-action-handlers))
                  (notes '()))
              (make-directory (concat root "target"))
              (jetpacs-files-test--touch (concat root "target/keep"))
              (make-symbolic-link (concat root "target") (concat root "link"))
              (jetpacs-files-test--touch (concat root "f"))
              (cl-letf (((symbol-function 'jetpacs-shell-notify)
                         (lambda (text &optional _s) (push text notes)))
                        ((symbol-function 'jetpacs-shell-push)
                         (lambda (&rest _) 1)))
                ;; A link row: the LINK goes; the target tree stays.
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.delete"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,(concat root "link")))
                             handler)
                            'accepted))
                (should-not (file-symlink-p (concat root "link")))
                (should (file-exists-p (concat root "target/keep")))
                ;; A dangling link still NAMES an entry: deletable.
                (make-symbolic-link (concat root "missing")
                                    (concat root "dangle"))
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.delete"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,(concat root "dangle")))
                             handler)
                            'accepted))
                (should-not (file-symlink-p (concat root "dangle")))
                ;; The closed hole: an out-of-sandbox ENTRY whose
                ;; truename points in must not unlink either side.
                (make-symbolic-link (concat root "f")
                                    (concat outside "link2"))
                (should (eq (jetpacs--dispatch
                             client `(:action "jetpacs.files.delete"
                                      :surface "app:jetpacs.files"
                                      :args (:path ,(concat outside "link2")))
                             handler)
                            'rejected))
                (should (equal (car notes) "Delete refused: outside-roots"))
                (should (file-exists-p (concat root "f")))
                (should (file-symlink-p (concat outside "link2"))))))
        (delete-directory outside t)))))

(ert-deftest jetpacs-files-menu-ops-act-on-the-link-not-its-target ()
  "The menu pipeline hands the ops the LITERAL entry: rename and move
relocate the LINK itself (rename(2) semantics), and duplicate pins
`copy-file''s native follow — a regular copy of the target's content."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (setf (ebp-client-granted client) ["surfaces.dialog"])
      (let ((handler (gethash "jetpacs.files.menu" jetpacs-action-handlers))
            (shown '()) (reply nil))
        (make-directory (concat root "target"))
        (jetpacs-files-test--touch (concat root "target/keep"))
        (make-directory (concat root "sub"))
        (write-region "payload\n" nil (concat root "f.txt") nil 'silent)
        (make-symbolic-link (concat root "target") (concat root "linkr"))
        (make-symbolic-link (concat root "target") (concat root "linkm"))
        (make-symbolic-link (concat root "f.txt") (concat root "flink"))
        (cl-letf (((symbol-function 'jetpacs-shell-notify) #'ignore)
                  ((symbol-function 'jetpacs-shell-push) (lambda (&rest _) 1))
                  ((symbol-function 'jetpacs-flow-begin)
                   (lambda (_surface fn) (funcall fn)))
                  ((symbol-function 'read-string) (lambda (&rest _) reply))
                  ((symbol-function 'ebp-client-dialog-show)
                   (cl-function
                    (lambda (_client id spec &key callback &allow-other-keys)
                      (push (list id spec callback) shown)))))
          (cl-flet ((menu-round (path op answer)
                      (setq reply answer)
                      (should (eq (jetpacs--dispatch
                                   client `(:action "jetpacs.files.menu"
                                            :surface "app:jetpacs.files"
                                            :args (:path ,path))
                                   handler)
                                  'accepted))
                      (jetpacs-files-test--pump)
                      (funcall (nth 2 (car shown)) "submitted"
                               (list :value op) nil)))
            ;; Rename: the LINK is renamed; the target tree untouched.
            (menu-round (concat root "linkr") "rename" "link2")
            (should (file-symlink-p (concat root "link2")))
            (should-not (file-symlink-p (concat root "linkr")))
            (should (file-exists-p (concat root "target/keep")))
            ;; Move: the LINK relocates, still a link; target untouched.
            (menu-round (concat root "linkm") "move" (concat root "sub/"))
            (should (file-symlink-p (concat root "sub/linkm")))
            (should-not (file-symlink-p (concat root "linkm")))
            (should (file-exists-p (concat root "target/keep")))
            ;; Duplicate: `copy-file' FOLLOWS the link (native — pinned):
            ;; a REGULAR copy of the target's content, target untouched.
            (menu-round (concat root "flink") "duplicate" nil)
            (let ((copy (concat root "flink copy")))
              (should (file-regular-p copy))
              (should-not (file-symlink-p copy))
              (with-temp-buffer
                (insert-file-contents copy)
                (should (equal (buffer-string) "payload\n"))))
            (should (file-symlink-p (concat root "flink")))
            (with-temp-buffer
              (insert-file-contents (concat root "f.txt"))
              (should (equal (buffer-string) "payload\n")))))))))

;; P1-2: the file's own coding, captured at open, rides the save.

(ert-deftest jetpacs-files-save-round-trips-the-files-own-coding ()
  "An open-then-save round trip with the UNMODIFIED seed leaves the
file's bytes untouched: utf-8-dos keeps its CRLFs and latin-1 keeps
its single-byte é, instead of both silently converting to LF/UTF-8."
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
            (jetpacs-files--edit nil))
        (cl-letf (((symbol-function 'jetpacs-shell-notify) #'ignore)
                  ((symbol-function 'jetpacs-shell-push) (lambda (&rest _) 1))
                  ((symbol-function 'jetpacs-chrome-push-screen)
                   (lambda (&rest _) 1)))
          (cl-flet ((round-trip-bytes (name coding content)
                      (let ((f (concat root name)))
                        (let ((coding-system-for-write coding))
                          (write-region content nil f nil 'silent))
                        (let ((true (file-truename f)))
                          (should-not (jetpacs-files--edit-open
                                       true "app:jetpacs.files"))
                          (should (eq (jetpacs--dispatch
                                       client
                                       `(:action "jetpacs.files.save"
                                         :surface "app:jetpacs.files"
                                         :args (:path ,true
                                                :mtime ,(plist-get
                                                         jetpacs-files--edit
                                                         :mtime)
                                                :value ,(plist-get
                                                         jetpacs-files--edit
                                                         :seed)))
                                       handler)
                                      'accepted))
                          (with-temp-buffer
                            (set-buffer-multibyte nil)
                            (insert-file-contents-literally true)
                            (buffer-string))))))
            (should (equal (round-trip-bytes "crlf.txt" 'utf-8-dos
                                             "line one\nline two\n")
                           "line one\r\nline two\r\n"))
            (should (equal (round-trip-bytes "l1.txt" 'iso-latin-1 "café\n")
                           (unibyte-string ?c ?a ?f #xE9 ?\n)))))))))

;; P1-3: save refuses BEFORE mutating; never routes through
;; `save-buffer''s interactive-recovery prompts.

(ert-deftest jetpacs-files-save-refuses-unwritable-before-any-mutation ()
  "A write-protected file: the save is REFUSED up front — disk
unchanged, the visiting desktop buffer unchanged and unmodified —
instead of clobbering the buffer and then failing to write it."
  (skip-unless (not (zerop (user-uid))))   ; root writes anywhere
  (jetpacs-files-test--with-tree root
    (jetpacs-files-test--attached (jetpacs-files-test--client)
      (let* ((handler (gethash "jetpacs.files.save" jetpacs-action-handlers))
             (f (concat root "keep.txt"))
             (notes '())
             (jetpacs-files--edit nil))
        (write-region "keep\n" nil f nil 'silent)
        (let* ((true (file-truename f))
               (buf (find-file-noselect true)))
          (unwind-protect
              (progn
                (set-file-modes true #o444)
                (cl-letf (((symbol-function 'jetpacs-shell-notify)
                           (lambda (text &optional _s) (push text notes)))
                          ((symbol-function 'jetpacs-shell-push)
                           (lambda (&rest _) 1)))
                  (should (eq (jetpacs--dispatch
                               client `(:action "jetpacs.files.save"
                                        :surface "app:jetpacs.files"
                                        :args (:path ,true
                                               :mtime ,(jetpacs-files--mtime-stamp true)
                                               :value "device\n"))
                               handler)
                              'rejected))
                  (should (equal (car notes) "Save refused: unwritable"))
                  (with-temp-buffer
                    (insert-file-contents true)
                    (should (equal (buffer-string) "keep\n")))
                  (with-current-buffer buf
                    (should (equal (buffer-string) "keep\n"))
                    (should-not (buffer-modified-p)))))
            (set-file-modes true #o644)
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))))))

;; P1-4: non-regular files are dropped before ANY read — an open(2) on
;; a FIFO blocks forever and no in-process timer can interrupt it.

(ert-deftest jetpacs-files-grep-and-edit-open-drop-non-regular-files ()
  "A FIFO under a root: the scan skips it (result well inside the
wall-clock budget) and a tap refuses `not-a-file' without opening it.
External watchdog writers UNBLOCK a regressed open so the test FAILS
in bounded time instead of hanging the suite."
  (skip-unless (executable-find "mkfifo"))
  (jetpacs-files-test--with-tree root
    (let ((pipe (concat root "pipe"))
          (w1 nil) (w2 nil))
      (call-process "mkfifo" nil nil nil pipe)
      (skip-unless (and (file-exists-p pipe)
                        (not (file-regular-p pipe))))
      (write-region "needle\n" nil (concat root "a.txt") nil 'silent)
      (unwind-protect
          (progn
            (setq w1 (start-process
                      "jf-watchdog1" nil "sh" "-c"
                      (format "sleep 8; : > %s"
                              (shell-quote-argument pipe))))
            (setq w2 (start-process
                      "jf-watchdog2" nil "sh" "-c"
                      (format "sleep 16; : > %s"
                              (shell-quote-argument pipe))))
            ;; The scan, pumped against the wall clock: a regression
            ;; blocks until the watchdog writes (~8s), which fails the
            ;; elapsed assertion rather than wedging ert.
            (let ((result nil)
                  (start (float-time))
                  elapsed)
              (jetpacs-files--grep-start root "needle"
                                         (lambda (r) (setq result r)))
              (while (and (not result) (< (- (float-time) start) 5))
                (accept-process-output nil 0.02))
              (setq elapsed (- (float-time) start))
              (should result)
              (should (< elapsed 5))
              (should (equal (mapcar #'car (plist-get result :hits))
                             (list (concat root "a.txt")))))
            ;; The tap: refused outright — NEVER the buffer-host
            ;; fallback, whose `find-file-noselect' blocks identically.
            (let ((screens '()) (navigated '()) (notes '())
                  (jetpacs-files--edit nil))
              (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                         (lambda (&rest args) (push args screens) 1))
                        ((symbol-function 'jetpacs-navigate-buffer)
                         (lambda (buf &rest _) (push buf navigated)))
                        ((symbol-function 'jetpacs-shell-notify)
                         (lambda (text &optional _s) (push text notes))))
                (should (eq (jetpacs-files--edit-open (file-truename pipe)
                                                      "app:jetpacs.files")
                            'not-a-file))
                (should (equal notes '("Open refused: not-a-file")))
                (should (null navigated))
                (should (null screens)))))
        (when (and w1 (process-live-p w1)) (delete-process w1))
        (when (and w2 (process-live-p w2)) (delete-process w2))))))

;; P1-5: the wire-safe gate at the remaining `:args' sites.

(ert-deftest jetpacs-files-wire-unsafe-paths-never-reach-args ()
  "A raw-byte directory name: the up-row and shared-row vanish rather
than carry raw `:args' (which reach `json-serialize' and take the push
down), the body still renders and serializes, and the editor never
seeds from a wire-unsafe path — the read fallback hosts it."
  (jetpacs-files-test--with-tree root
    ;; The banked trap: (concat root (unibyte-string 255) ...) is
    ;; UNIBYTE; the held canonical form must be its `file-truename'
    ;; (multibyte, raw-byte char #x3FFFFF) or `jetpacs-files--wire-safe-p's
    ;; char-class regexp cannot see the byte.
    (make-directory (concat root (unibyte-string 255) "dir/sub") t)
    (let ((bad-dir (file-truename (concat root (unibyte-string 255) "dir")))
          (bad-sub (file-truename
                    (concat root (unibyte-string 255) "dir/sub"))))
      ;; Fixture sanity: the held form really is wire-unsafe.
      (should-not (jetpacs-files--wire-safe-p bad-dir))
      ;; (a) The up-row from inside the raw-byte tree: no row at all.
      (should-not (jetpacs-files--up-row (file-name-as-directory bad-sub)))
      ;; (b) The body still RENDERS (a real lazy_column, not a degrade)
      ;; and the whole tree serializes.
      (let ((jetpacs-files--dir (file-name-as-directory bad-sub)))
        (let ((body (jetpacs-files--body)))
          (should (equal (plist-get body :t) "lazy_column"))
          (should (stringp (jetpacs-node->canonical-json body)))))
      ;; (c) The shared-storage shortcut: silently absent.
      (let ((jetpacs-files--dir nil)
            (jetpacs-files--shared-dir (file-name-as-directory bad-dir)))
        (should-not (jetpacs-files--shared-row)))
      ;; (d) The editor: a wire-unsafe PATH never seeds the screen.
      (make-directory (concat root (unibyte-string 255) "d") t)
      (let ((raw-f (concat root (unibyte-string 255) "d/f.txt")))
        (write-region "plain\n" nil raw-f nil 'silent)
        (let ((bad-f (file-truename raw-f))
              (screens '()) (navigated '())
              (jetpacs-files--edit nil))
          (cl-letf (((symbol-function 'jetpacs-chrome-push-screen)
                     (lambda (&rest args) (push args screens) 1))
                    ((symbol-function 'jetpacs-navigate-buffer)
                     (lambda (buf &rest _) (push buf navigated)))
                    ((symbol-function 'jetpacs-shell-notify) #'ignore))
            (should (eq (jetpacs-files--edit-open bad-f "app:jetpacs.files")
                        'unencodable))
            (should (= (length navigated) 1))
            (should (null screens))))))))

(provide 'jetpacs-files-test)
;;; jetpacs-files-test.el ends here
