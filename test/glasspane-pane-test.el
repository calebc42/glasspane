;;; glasspane-pane-test.el --- Lists beside the heading page -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Wide windows show Agenda, Projects and Area drills beside a heading
;; pane; a tap there selects instead of pushing.  Compact windows, other
;; screens and Companions without `pane_scaffold' keep the push.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'glasspane)

(glasspane-register)  ; `require' only loads

(defmacro glasspane-pane-test--with (width stack advertised &rest body)
  "Run BODY with window WIDTH, Glasspane STACK and pane ADVERTISED."
  (declare (indent 3))
  `(let ((glasspane-ui--pane-selection (make-hash-table :test #'equal))
         (pushed nil) (refreshed nil))
     (cl-letf (((symbol-function 'jetpacs-window-class) (lambda (_) ,width))
               ((symbol-function 'jetpacs-node-advertised-p)
                (lambda (type &rest _)
                  (or (not (equal type "pane_scaffold")) ,advertised)))
               ((symbol-function 'jetpacs-chrome-stack) (lambda (_) ,stack))
               ((symbol-function 'jetpacs-chrome-push-screen-later)
                (lambda (_s id _b) (push id pushed)))
               ((symbol-function 'jetpacs-chrome-defer-current-view-refresh)
                (lambda (s) (push s refreshed)))
               ((symbol-function 'ebp-org-token-ref)
                (lambda (tok &rest _) (and (equal tok "tok") '(:file "/v/a.org" :pos 7)))))
       ,@body)))

(ert-deftest glasspane-pane-test-wide-tap-selects-instead-of-pushing ()
  "On Agenda at expanded width a tap fills the pane and rebuilds the top."
  (glasspane-pane-test--with "expanded" '("glasspane-agenda") t
    (should (eq (glasspane-detail--on-tap '(:token "tok") '(:surface "app:glasspane"))
                'accepted))
    (should-not pushed)
    (should refreshed)
    (should (equal (glasspane-ui-pane-selection "glasspane-agenda")
                   '(:file "/v/a.org" :pos 7)))
    ;; Closing clears it.
    (should (eq (glasspane-ui--on-pane-close nil '(:surface "app:glasspane"))
                'accepted))
    (should-not (glasspane-ui-pane-selection "glasspane-agenda"))))

(ert-deftest glasspane-pane-test-area-drill-and-projects-are-pane-screens ()
  "Area drill ids and Projects select; Search and the detail screen push."
  (should (glasspane-ui-pane-screen-p (jetpacs-wire-id "area" "Home")))
  (should (glasspane-ui-pane-screen-p "glasspane-projects"))
  (should-not (glasspane-ui-pane-screen-p "glasspane-search"))
  (should-not (glasspane-ui-pane-screen-p "glasspane-areas"))
  (glasspane-pane-test--with "medium" '("glasspane-search" "glasspane-agenda") t
    (glasspane-detail--on-tap '(:token "tok") '(:surface "app:glasspane"))
    (should (equal pushed '("glasspane-detail")))))

(ert-deftest glasspane-pane-test-compact-or-unadvertised-pushes ()
  "A phone, or a Companion without pane_scaffold, keeps the push."
  (glasspane-pane-test--with "compact" '("glasspane-agenda") t
    (glasspane-detail--on-tap '(:token "tok") '(:surface "app:glasspane"))
    (should (equal pushed '("glasspane-detail")))
    (should-not (glasspane-ui-pane-selection "glasspane-agenda")))
  (glasspane-pane-test--with "expanded" '("glasspane-agenda") nil
    (glasspane-detail--on-tap '(:token "tok") '(:surface "app:glasspane"))
    (should (equal pushed '("glasspane-detail")))))

(ert-deftest glasspane-pane-test-screen-builds-pane-scaffold ()
  "The screen pairs its list with the page, a placeholder, or degrades."
  (glasspane-pane-test--with "expanded" '("glasspane-agenda") t
    (cl-letf (((symbol-function 'glasspane-agenda-body) (lambda () (jetpacs-text "list"))))
      ;; Nothing selected: the placeholder.
      (let ((body (plist-get (glasspane-agenda-screen nil) :body)))
        (should (equal (plist-get body :t) "pane_scaffold"))
        (should (string-search "Select a heading"
                               (jetpacs-node->canonical-json body))))
      ;; Selected: the page, with a close action that Back honours.
      (glasspane-ui-pane-select "glasspane-agenda" '(:file "/v/a.org" :pos 7))
      (cl-letf (((symbol-function 'glasspane-ui--detail-meta)
                 (lambda (_) '(:file "/v/a.org" :pos 7 :file-title "Life")))
                ((symbol-function 'glasspane-detail-pane)
                 (lambda (_) (jetpacs-text "page"))))
        (let* ((screen (glasspane-agenda-screen nil))
               (json (jetpacs-node->canonical-json (plist-get screen :body))))
          (should (string-search "page" json))
          (should (equal (plist-get (plist-get screen :on_back) :action)
                         "glasspane.pane.close"))))
      ;; Stale: the selection clears and the placeholder returns.
      (cl-letf (((symbol-function 'glasspane-ui--detail-meta)
                 (lambda (_) (signal 'ebp-org-unresolved '("gone")))))
        (should (string-search "Select a heading"
                               (jetpacs-node->canonical-json
                                (plist-get (glasspane-agenda-screen nil) :body))))
        (should-not (glasspane-ui-pane-selection "glasspane-agenda"))))))

(ert-deftest glasspane-pane-test-compact-screen-is-the-list-alone ()
  "A phone gets the list, no pane scaffold."
  (glasspane-pane-test--with "compact" '("glasspane-agenda") t
    (cl-letf (((symbol-function 'glasspane-agenda-body) (lambda () (jetpacs-text "list"))))
      (should (equal (plist-get (plist-get (glasspane-agenda-screen nil) :body) :t)
                     "text")))))

(ert-deftest glasspane-pane-test-selected-card-and-leave ()
  "The selected heading's card is marked; leaving closes the pane."
  (let ((glasspane-ui-pane-current (cons "/v/a.org" 7)))
    (cl-letf (((symbol-function 'file-truename) #'identity)
              ((symbol-function 'glasspane-ui-item-areas) (lambda (_) nil)))
      (should (equal (plist-get (glasspane-detail-agenda-card
                                 '((headline . "x") (file . "/v/a.org") (pos . 7)
                                   (token . "t")))
                                :variant)
                     "elevated"))
      (should-not (plist-get (glasspane-detail-agenda-card
                              '((headline . "y") (file . "/v/a.org") (pos . 9)
                                (token . "t")))
                             :variant))))
  (glasspane-pane-test--with "expanded" '("glasspane-projects") t
    (glasspane-ui-pane-select "glasspane-projects" '(:file "/v/a.org" :pos 7))
    (let (repushed)
      (cl-letf (((symbol-function 'jetpacs-shell-push-caught)
                 (lambda (s) (setq repushed s))))
        (glasspane-detail--leave '(:surface "app:glasspane")))
      (should (equal repushed "app:glasspane"))
      (should-not (glasspane-ui-pane-selection "glasspane-projects")))))

(provide 'glasspane-pane-test)
;;; glasspane-pane-test.el ends here
