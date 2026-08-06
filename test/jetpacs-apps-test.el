;;; jetpacs-apps-test.el --- ERT for the app-identity layer -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Pins the design's contracts (PLAN-poc1-parity, "The app-identity
;; design"): the single-app contract, the composed dock, per-app
;; isolation, and app.open dispatch.

(require 'ert)
(require 'jetpacs-apps)

(defvar jetpacs-apps-test--core
  (list (list :label "Home" :icon "home"
              :on-tap '(:action "hub.home"))))

(defmacro jetpacs-apps-test--env (&rest body)
  (declare (indent 0))
  `(let ((jetpacs-apps--registry nil)
         (jetpacs-apps--current nil)
         (jetpacs-apps-core-dock-items
          (lambda (_surface) jetpacs-apps-test--core))
         (pushed nil))
     (cl-letf (((symbol-function 'jetpacs-flow-continue)
                (lambda (fn) (funcall fn)))
               ((symbol-function 'jetpacs-shell-push)
                (lambda (surface &rest _) (push surface pushed))))
       (ignore pushed)
       ,@body)))

(defun jetpacs-apps-test--labels (items)
  (mapcar (lambda (i) (plist-get i :label)) items))

(ert-deftest jetpacs-apps-zero-apps-is-byte-identical-core ()
  "With no registered apps the composed dock IS the core items."
  (jetpacs-apps-test--env
    (should (equal (jetpacs-apps-dock-items "app:hub")
                   jetpacs-apps-test--core))))

(ert-deftest jetpacs-apps-single-app-merges-without-launcher ()
  "One app: core + its destinations, and no Apps entry."
  (jetpacs-apps-test--env
    (jetpacs-defapp "notes" :label "Notes"
                    :surfaces '("notes.main")
                    :dock (list (list :label "Notes" :icon "note"
                                      :on-tap '(:action "notes.show"))))
    (should (equal (jetpacs-apps-test--labels
                    (jetpacs-apps-dock-items "app:hub"))
                   '("Home" "Notes")))))

(ert-deftest jetpacs-apps-second-app-raises-the-launcher ()
  "Two apps: the current app's items plus a trailing Apps destination."
  (jetpacs-apps-test--env
    (jetpacs-defapp "notes" :label "Notes" :surfaces '("notes.main")
                    :dock (list (list :label "Notes" :icon "note"
                                      :on-tap '(:action "notes.show"))))
    (jetpacs-defapp "agenda" :label "Agenda" :surfaces '("agenda.main")
                    :dock (list (list :label "Agenda" :icon "event"
                                      :on-tap '(:action "agenda.show"))))
    (setq jetpacs-apps--current "notes")
    (let ((labels (jetpacs-apps-test--labels
                   (jetpacs-apps-dock-items "app:hub"))))
      (should (equal labels '("Home" "Notes" "Apps")))
      (should-not (member "Agenda" labels)))
    (setq jetpacs-apps--current "agenda")
    (should (equal (jetpacs-apps-test--labels
                    (jetpacs-apps-dock-items "app:hub"))
                   '("Home" "Agenda" "Apps")))))

(ert-deftest jetpacs-apps-broken-app-costs-only-its-items ()
  "A signaling dock builder drops that app's items, never the dock."
  (jetpacs-apps-test--env
    (jetpacs-defapp "broken" :label "Broken" :surfaces '("broken.main")
                    :dock (lambda (_s) (error "boom")))
    (jetpacs-defapp "notes" :label "Notes" :surfaces '("notes.main")
                    :dock (list (list :label "Notes" :icon "note"
                                      :on-tap '(:action "notes.show"))))
    (setq jetpacs-apps--current "broken")
    (should (equal (jetpacs-apps-test--labels
                    (jetpacs-apps-dock-items "app:hub"))
                   '("Home" "Apps")))))

(ert-deftest jetpacs-apps-open-switches-and-lands-home ()
  "app.open validates the id, sets current, and pushes the app's home."
  (jetpacs-apps-test--env
    (should (eq (jetpacs-apps--action-open '(:app "ghost") nil) 'rejected))
    (jetpacs-defapp "notes" :label "Notes" :surfaces '("notes.main"))
    (should (eq (jetpacs-apps--action-open '(:app "notes") nil) 'accepted))
    (should (equal jetpacs-apps--current "notes"))
    (should (equal pushed '("notes.main")))))

(ert-deftest jetpacs-apps-sole-app-is-current-by-default ()
  "With exactly one app registered it IS the current app, unopened."
  (jetpacs-apps-test--env
    (jetpacs-defapp "notes" :label "Notes" :surfaces '("notes.main"))
    (should (equal (car (jetpacs-apps-current)) "notes"))
    (jetpacs-apps-unregister "notes")
    (should-not (jetpacs-apps-current))))

(ert-deftest jetpacs-apps-grid-orders-cards-by-order ()
  "The Apps grid renders one card per app, sorted by :order."
  (jetpacs-apps-test--env
    (jetpacs-defapp "zeta" :label "Zeta" :order 200
                    :surfaces '("zeta.main"))
    (jetpacs-defapp "alpha" :label "Alpha" :order 50
                    :surfaces '("alpha.main"))
    (let ((labels nil))
      (cl-labels ((walk (n)
                    (when (and (equal (plist-get n :t) "text")
                               (equal (plist-get n :style) "label"))
                      (push (plist-get n :text) labels))
                    ;; The view is a scaffold now: descend :body too.
                    (when-let* ((body (plist-get n :body))) (walk body))
                    (mapc #'walk (append (plist-get n :children) nil))))
        (walk (jetpacs-apps--view)))
      (should (equal (nreverse labels) '("Alpha" "Zeta"))))))

(provide 'jetpacs-apps-test)
;;; jetpacs-apps-test.el ends here