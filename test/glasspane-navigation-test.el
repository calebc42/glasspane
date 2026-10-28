;;; glasspane-navigation-test.el --- Contract tests for one document route -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; These tests guard a semantic boundary that static applet validation cannot
;; infer: different identity adapters may name a document, but none may create
;; its own Files presentation policy.  See ../NAVIGATION.org.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'seq)
(require 'glasspane)
(glasspane-register)  ; `require' only loads

(defconst glasspane-navigation-test--source-directory
  (expand-file-name ".."
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Glasspane's flat applet source directory.")

(ert-deftest glasspane-navigation-test-declares-material-renderer ()
  "Glasspane, rather than Jetpacs foundation, selects Material 3."
  (let ((entry (assoc glasspane-owner jetpacs-apps--registry)))
    (should entry)
    (should (equal (plist-get (cdr entry) :requires-extensions)
                   '("jetpacs.material3")))
    (should (equal jetpacs-material3-extension "jetpacs.material3"))))

(ert-deftest glasspane-navigation-test-canonical-document-policy ()
  "A document open fixes Files, reader, Back screen, and return policy."
  (let (events)
    (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (feature target)
                 (and (equal feature "action.open_surface")
                      (eq target :app))))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (path surface &optional position browser-id browser-fab
                             return-action)
                 (push (list 'open path surface position browser-id browser-fab
                             return-action)
                       events)
                 'accepted))
              ((symbol-function 'glasspane-org-reader-prepare-landing)
               (lambda (path) (push (list 'prepare path) events))))
      (should (eq (glasspane-navigation-open-document
                   "/vault/work.org" 37)
                  'accepted)))
    (setq events (nreverse events))
    ;; Files validates and accepts first; reader state changes before its
    ;; deferred render, but never for a refused path.
    (should (equal (caar events) 'open))
    (should (equal (cadr events) '(prepare "/vault/work.org")))
    (let* ((open (car events))
           (return (nth 6 open)))
      (should (equal (seq-take open 6)
                     '(open "/vault/work.org" "app:jetpacs.files" 37
                            "files-return" nil)))
      (should (equal (plist-get return :action)
                     "glasspane.files.return"))
      (should (equal (plist-get return :open_surface) "app:glasspane")))
    (setq events nil)
    (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (&rest _) t))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (&rest _) 'rejected))
              ((symbol-function 'glasspane-org-reader-prepare-landing)
               (lambda (path) (push path events))))
      (should (eq (glasspane-navigation-open-document
                   "/outside/refused.org")
                  'rejected))
      (should-not events))
    (should (eq (glasspane-navigation-open-document nil) 'rejected))
    (should (eq (glasspane-navigation-open-document "/vault/work.org" "37")
                'rejected))))

(ert-deftest glasspane-navigation-test-entry-builders-name-authority-only ()
  "Heading cards and file rows choose identity, never presentation policy.
The detail card and the Area declaring card carry a durable heading token
and open the heading's page on Glasspane's own surface (`heading.tap');
the page's Open in file is the document route.  Every builder that opens a
document is named here: the Area file row and the Archive row carry a
validated path (`glasspane.document.open') and present the one Files
surface."
  (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
             (lambda (&rest _) t)))
    (let* ((project (glasspane-detail-agenda-card
                     '((headline . "Ship it") (token . "heading-token"))))
           (project-action (plist-get project :on_tap))
           (declaring (glasspane-areas--declaring-card
                       '((headline . "Tech") (todo . nil) (tags . ["tech"])
                         (areas . ["tech"]) (file . "/vault/areas.org")
                         (pos . 1) (token . "decl-token"))))
           (declaring-action (plist-get declaring :on_tap))
           (file-row (glasspane-areas--file-row "/vault/work.org"))
           (file-action (plist-get file-row :on_tap))
           (archive-row (glasspane-resources-archive-row
                         (list :path "/vault/work.org_archive"
                               :mtime (encode-time 0 30 9 2 1 2026))))
           (archive-action (plist-get archive-row :on_tap)))
      (should (equal (plist-get project-action :action) "heading.tap"))
      (should (equal (plist-get project-action :args)
                     '(:token "heading-token")))
      (should-not (plist-get project-action :open_surface))
      (should (equal (plist-get declaring-action :action) "heading.tap"))
      (should (equal (plist-get declaring-action :args)
                     '(:token "decl-token")))
      (should-not (plist-get declaring-action :open_surface))
      (should (equal (plist-get file-action :action)
                     "glasspane.document.open"))
      (should (equal (plist-get file-action :args)
                     '(:path "/vault/work.org")))
      (should (equal (plist-get archive-action :action)
                     "glasspane.document.open"))
      (should (equal (plist-get archive-action :args)
                     '(:path "/vault/work.org_archive")))
      (dolist (action (list file-action archive-action))
        (should (equal (plist-get action :open_surface)
                       "app:jetpacs.files"))))))

(ert-deftest glasspane-navigation-test-authority-adapters-converge ()
  "Token and path verbs call one document presenter."
  (let (calls)
    (cl-letf (((symbol-function 'ebp-org-token-ref)
               (lambda (_token &rest _) 'durable-ref))
              ((symbol-function 'jetpacs-org-heading-location)
               (lambda (_ref) '(buffer "/vault/work.org" 73)))
              ((symbol-function 'glasspane-navigation-open-document)
               (lambda (path &optional position)
                 (push (list path position) calls)
                 'accepted)))
      (should (eq (glasspane-detail--on-visit
                   '(:token "project-token") nil)
                  'accepted))
      (should (eq (glasspane-navigation--on-document-open
                   '(:path "/vault/work.org") nil)
                  'accepted)))
    (should (equal (nreverse calls)
                   '(("/vault/work.org" 73)
                     ("/vault/work.org" nil))))))

(ert-deftest glasspane-navigation-test-link-destinations-converge ()
  "An Org-resolved link destination takes the same presenter as tokens and paths.
Staying on the link means Org handed an external target to the system, and a
buffer without a file is left to the foundation drill."
  (let (calls notices)
    (cl-letf (((symbol-function 'glasspane-navigation-open-document)
               (lambda (path &optional position)
                 (push (list path position) calls)
                 'accepted))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (text &rest _) (push text notices))))
      (with-temp-buffer
        (org-mode)
        (insert "See [[https://example.com][web]] now.\n")
        (let ((source (current-buffer))
              (own (jetpacs-shell-surface-for "glasspane")))
          (with-temp-buffer
            (setq buffer-file-name "/vault/other.org")
            (unwind-protect
                (progn
                  (should (glasspane-org-reader--present-link-destination
                           source (current-buffer) 42 own 5))
                  ;; Another app's surface, not the document Files shows:
                  ;; not Glasspane's to present.
                  (should-not (glasspane-org-reader--present-link-destination
                               source (current-buffer) 42 "app:elsewhere" 5)))
              (setq buffer-file-name nil)))
          (should (glasspane-org-reader--present-link-destination
                   source source 7 nil 5))
          (with-temp-buffer
            (should-not (glasspane-org-reader--present-link-destination
                         source (current-buffer) 1 own 5))))))
    (should (equal calls '(("/vault/other.org" 42))))
    (should (equal notices '("Opened link")))))

(ert-deftest glasspane-navigation-test-real-org-token-preserves-position ()
  "A real durable heading token resolves to canonical PATH and POSITION."
  (let* ((root (make-temp-file "glasspane-navigation" t))
         (path (expand-file-name "project.org" root))
         (org-directory root)
         (ebp-org-roots (list root))
         buffer token expected opened)
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "* Project\n** TODO Canonical target\nBody\n"))
          (setq buffer (find-file-noselect path))
          (with-current-buffer buffer
            (org-mode)
            (org-with-wide-buffer
             (goto-char (point-min))
             (re-search-forward "^\\*\\* TODO Canonical target$")
             (goto-char (line-beginning-position))
             (let ((ref (ebp-org-ref-at-point)))
               (setq expected (plist-get ref :pos)
                     token (car (ebp-org-ref-tokens
                                 (list ref) :set "navigation-real"
                                 :owner "glasspane"))))))
          (cl-letf (((symbol-function 'glasspane-navigation-open-document)
                     (lambda (file &optional position)
                       (setq opened (list file position))
                       'accepted)))
            (should (eq (glasspane-detail--on-visit
                         (list :token token) nil)
                        'accepted)))
          (should (equal opened (list (file-truename path) expected))))
      (ebp-org-ref-tokens nil :set "navigation-real" :owner "glasspane")
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest glasspane-navigation-test-one-low-level-files-boundary ()
  "Only glasspane-navigation.el may call `jetpacs-files-open-path'."
  (let ((sources
         (directory-files glasspane-navigation-test--source-directory
                          t "\\.el\\'"))
        owners)
    (dolist (source sources)
      (with-temp-buffer
        (insert-file-contents source)
        (goto-char (point-min))
        (when (re-search-forward
               "([ \t\n]*jetpacs-files-open-path\\_>" nil t)
          (push (file-name-nondirectory source) owners))))
    (should (equal (nreverse owners) '("glasspane-navigation.el")))))

(ert-deftest glasspane-navigation-test-lifecycle-is-symmetric ()
  "Canonical actions register and unregister while Files owns the Back observer."
  (unwind-protect
      (progn
        (glasspane-navigation-register)
        (dolist (verb glasspane-navigation--verbs)
          (should (gethash verb jetpacs-action-handlers))
          (should (equal (jetpacs--owner-of "action" verb) "glasspane")))
        (should (memq #'jetpacs-files--on-view-change
                      jetpacs-shell-view-change-functions))
        (glasspane-navigation-unregister)
        (dolist (verb glasspane-navigation--verbs)
          (should-not (gethash verb jetpacs-action-handlers))))
    (glasspane-navigation-register)))

(ert-deftest glasspane-navigation-test-reader-actions-admitted-on-files-surface ()
  "Reader-emitted detail, tag, and return actions pass D1 on the Files surface."
  (dolist (verb '("heading.tap" "heading.todo-cycle"
                  "heading.duplicate" "heading.props.show"
                  "heading.clock-in" "search.by-tag"
                  "jetpacs.files.return" "glasspane.files.return"))
    (should (gethash verb jetpacs-action-handlers))
    (should (gethash verb jetpacs--any-surface-actions))))

(ert-deftest glasspane-navigation-test-evicted-return-screen-falls-back-on-browser ()
  "When a 3-screen reader drill evicts `guest-glasspane-files-return', Back to
Files' root `browser' view still completes the armed Glasspane return once."
  (let ((jetpacs-apps--current "glasspane")
        (jetpacs-apps--current-route "projects")
        (jetpacs-files--return-armed "app:glasspane")
        (returns 0))
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (surface &rest _)
                 (when (equal surface (jetpacs-shell-surface-for "glasspane"))
                   (cl-incf returns)))))
      (jetpacs-files--on-view-change "app:jetpacs.files" "browser")
      (should (= returns 1))
      (should-not jetpacs-files--return-armed)
      ;; Subsequent `browser' view transitions do not re-trigger the return.
      (jetpacs-files--on-view-change "app:jetpacs.files" "browser")
      (should (= returns 1)))))

(ert-deftest glasspane-navigation-test-peers-declare-system-back ()
  "A peer screen draws no arrow but names the root for the back gesture.
Without `on_back' the Companion finishes the Activity on a peer."
  (dolist (builder (list #'glasspane-projects-screen
                         #'glasspane-areas-screen
                         #'glasspane-resources-screen
                         #'glasspane-srs-screen
                         #'glasspane-resources-archive-screen))
    (cl-letf (((symbol-function 'glasspane-resources--index) (lambda () nil))
              ((symbol-function 'glasspane-resources--archive-files)
               (lambda () nil))
              ((symbol-function 'glasspane-areas--index) (lambda () nil))
              ((symbol-function 'glasspane-org-todo-items) (lambda () nil)))
      (let ((peer (funcall builder nil))
            (child (funcall builder (jetpacs-view-switch "glasspane-agenda"))))
        (should (equal (plist-get peer :on_back)
                       '(:builtin "view.switch" :view "glasspane-agenda")))
        (should (equal (plist-get (plist-get peer :on_refresh) :action)
                       "glasspane.refresh"))
        ;; A drilled copy keeps the arrow and declares no second gesture.
        (should-not (plist-get child :on_back))))))

(ert-deftest glasspane-navigation-test-child-back-survives-eviction ()
  "A child's Back reopens its parent when the bounded stack evicted it."
  (let ((to-areas (jetpacs-view-switch "glasspane-areas"))
        (to-root (jetpacs-view-switch "glasspane-agenda"))
        (reopen (jetpacs-action "areas.open")))
    (should (eq (glasspane-ui-parent-back to-areas "glasspane-areas" reopen)
                to-areas))
    (should (eq (glasspane-ui-parent-back to-root "glasspane-areas" reopen)
                reopen))
    (should (eq (glasspane-ui-parent-back nil "glasspane-areas" reopen)
                reopen))
    ;; Route-aware: a transient screen above the root keeps chrome's switch
    ;; while Agenda is selected, and reopens an evicted destination.
    (let ((jetpacs-apps--current-route "agenda"))
      (should (eq (glasspane-ui-route-back to-root) to-root)))
    (let ((jetpacs-apps--current-route "projects"))
      (should (equal (plist-get (glasspane-ui-route-back to-root) :action)
                     "projects.open"))
      (should (eq (glasspane-ui-route-back to-areas) to-areas)))
    (let ((jetpacs-apps--current-route "no-such-route"))
      (should (eq (glasspane-ui-route-back to-root) to-root)))))

(ert-deftest glasspane-navigation-test-list-keys-are-opaque-and-distinct ()
  "Cards carry stable keys that never spell a path and differ per listing."
  (let* ((item '((headline . "Ship") (file . "/vault/secret dir/work.org")
                 (pos . 120) (type . "scheduled") (date . "2026-10-28")
                 (token . "tok")))
         (again (glasspane-ui-item-key item))
         (deadline (glasspane-ui-item-key
                    (cons '(type . "deadline") item)))
         (grouped (glasspane-ui-item-key item "Home")))
    (should (stringp again))
    (should (equal again (glasspane-ui-item-key item)))
    (should-not (string-search "work.org" again))
    (should-not (string-search "secret" again))
    (should (jetpacs-identifier-p again))
    (should-not (equal again deadline))
    (should-not (equal again grouped))
    ;; A token-only item (a vulpea note) still gets a key; nothing gets none.
    (should (stringp (glasspane-ui-item-key '((token . "tok-only")))))
    (should-not (glasspane-ui-item-key '((headline . "Plain"))))
    (let ((card (glasspane-detail-agenda-card item '("Home") "Home")))
      (should (equal (plist-get card :key) grouped))
      (should (equal (plist-get (plist-get card :on_tap) :action)
                     "heading.tap")))))

(ert-deftest glasspane-navigation-test-area-drill-is-a-child-push ()
  "Opening an Area pushes above the Areas list instead of replacing it."
  (let (pushed)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-apps-note-route)
               (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-chrome-reset-screens)
               (lambda (&rest _) (error "a drill must not reset")))
              ((symbol-function 'jetpacs-chrome-push-screen)
               (lambda (surface id builder)
                 (setq pushed (list surface id builder)))))
      (should (eq (glasspane-areas--on-drill
                   '(:category "Home") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal (seq-take pushed 2)
                     (list "app:glasspane" (jetpacs-wire-id "area" "Home")))))))

(ert-deftest glasspane-navigation-test-age-words ()
  "Edit times read in words, never as raw timestamps."
  (let ((now (encode-time 0 0 12 28 10 2026)))
    (cl-flet ((ago (seconds)
                (glasspane-ui-age-words (time-subtract now seconds) now)))
      (should (equal (ago 5) "Edited just now"))
      (should (equal (ago 300) "Edited 5 min ago"))
      (should (equal (ago 3600) "Edited 1 hour ago"))
      (should (equal (ago (* 3 3600)) "Edited 3 hours ago"))
      (should (equal (ago 86400) "Edited yesterday"))
      (should (equal (ago (* 5 86400)) "Edited 5 days ago"))
      (should (equal (ago (* 45 86400)) "Edited 1 month ago"))
      (should (equal (ago (* 100 86400)) "Edited 3 months ago"))
      (should (equal (ago (* 800 86400)) "Edited 2 years ago"))
      (should-not (glasspane-ui-age-words nil)))))

(provide 'glasspane-navigation-test)
;;; glasspane-navigation-test.el ends here
