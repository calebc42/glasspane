;;; jetpacs-org-outline-test.el --- JA-5h: the Tier-1 outline view -*- lexical-binding: t; -*-

;;; Commentary:

;; The staging card view: a card exposes its heading position for the
;; sheet verb WITH its descriptor (the JC-2 own-records discipline);
;; the body caps, brackets, seams and empties correctly.  Base must
;; never require this file — that stays enforced socially (the vulpea
;; precedent), pinned here by a load check.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-org-outline)

(defmacro jetpacs-org-outline-test--with-file (var content &rest body)
  (declare (indent 2))
  `(let* ((dir (file-name-as-directory
                (file-truename (make-temp-file "ja5h" t))))
          (,var (expand-file-name "outline.org" dir))
          (ebp-org-roots (list dir)))
     (with-temp-file ,var (insert ,content))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buf (find-buffer-visiting ,var)))
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))
       (delete-directory dir t)
       (jetpacs-buffer-forget-exposed)
       (ebp-org-reset))))

(defconst jetpacs-org-outline-test--fixture
  (concat "* TODO Alpha\nDEADLINE: <2026-08-01 Sat>\nbody\n"
          "** Sub (never a card)\n"
          "* DONE Beta\n"
          "* Gamma\n"))

(ert-deftest jetpacs-org-outline-card-exposes-heading-verb ()
  "The default card mints the sheet descriptor AND its record together."
  (jetpacs-org-outline-test--with-file f jetpacs-org-outline-test--fixture
    (let* ((recs (ebp-org-file-toplevel-records f))
           (card (jetpacs-org-outline--default-card (car recs)))
           (rec (car recs)))
      (should (equal (plist-get card :t) "card"))
      (should (jetpacs-buffer-exposed-p (plist-get rec :buffer)
                                        (plist-get rec :pos)
                                        "jetpacs.org.heading"))
      ;; The descriptor is reachable in the card and names the record.
      (let (desc)
        (cl-labels ((walk (n)
                      (when (consp n)
                        (when-let* ((d (plist-get n :on_tap)))
                          (setq desc d))
                        (dolist (c (append (plist-get n :children) nil))
                          (walk c)))))
          (walk card))
        (should (equal (plist-get desc :action) "jetpacs.org.heading"))
        (should (equal (plist-get (plist-get desc :args) :pos)
                       (plist-get rec :pos)))))))

(ert-deftest jetpacs-org-outline-body-cap-seam-and-empty ()
  "The body lists only level-1 records, honors the cap, the card seam,
and the empty state."
  (jetpacs-org-outline-test--with-file f jetpacs-org-outline-test--fixture
    (let ((body (jetpacs-org-outline-body f)))
      (should (equal (plist-get body :t) "lazy_column"))
      (should (= 3 (length (append (plist-get body :children) nil)))))
    (let ((ebp-org-outline-max-headings 1))
      (let ((body (jetpacs-org-outline-body f)))
        (should (= 1 (length (append (plist-get body :children) nil))))))
    ;; The card seam.
    (let* ((jetpacs-org-outline-card-function
            (lambda (rec) (jetpacs-text (plist-get rec :title))))
           (body (jetpacs-org-outline-body f))
           (first (aref (plist-get body :children) 0)))
      (should (equal (plist-get first :t) "text"))
      (should (equal (plist-get first :text) "Alpha")))
    ;; Empty state.
    (let ((body (jetpacs-org-outline-body nil :items nil)))
      (should (equal (plist-get body :t) "empty_state")))))

(ert-deftest jetpacs-org-outline-never-loaded-by-base ()
  "Loading every base module must not drag the staging view in —
the vulpea precedent, pinned."
  (should-not (featurep 'jetpacs-org-vulpea))  ; the precedent holds too
  (let ((loaded (mapcar (lambda (f) (format "%s" f)) features)))
    (ignore loaded)
    ;; This suite required it explicitly; the pin is that NO base
    ;; module's require chain does — asserted by grepping the sources.
    ;; BOTH prefixes: after the ebp-org split half of base is `ebp-',
    ;; and a `jetpacs-'-only regexp would scan half the tree while
    ;; still passing — a pin whose scan set narrows silently is the
    ;; failure mode, not the guard.
    (dolist (module (directory-files
                     (file-name-directory
                      (locate-library "jetpacs-org-outline.el" t))
                     t "\\`\\(jetpacs\\|ebp\\)-.*\\.el\\'"))
      (unless (member (file-name-nondirectory module)
                      '("jetpacs-org-outline.el"))
        (with-temp-buffer
          (insert-file-contents module)
          (goto-char (point-min))
          (should-not (search-forward "(require 'jetpacs-org-outline)"
                                      nil t)))))))

(provide 'jetpacs-org-outline-test)
;;; jetpacs-org-outline-test.el ends here
