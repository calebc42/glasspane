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
         (jetpacs-apps-core-drawer-rows nil)
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
      (should-not (member "Agenda" labels))
      (let* ((apps (car (last (jetpacs-apps-dock-items "app:hub"))))
             (tap (plist-get apps :on-tap)))
        (should (equal (plist-get tap :action) "jetpacs.launcher.open"))
        (should (equal (plist-get (plist-get tap :args) :surface)
                       "app:jetpacs.app-store"))))
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

(ert-deftest jetpacs-apps-for-surface-reads-claims ()
  "The public identity read: a claimed surface answers its entry
\(colon-aware) and an unclaimed one answers nil."
  (jetpacs-apps-test--env
    (jetpacs-defapp "notes" :label "Notes" :icon "note"
                    :surfaces '("notes.main"))
    (should (equal (car (jetpacs-apps-for-surface "app:notes.main"))
                   "notes"))
    (should-not (jetpacs-apps-for-surface "app:jetpacs.settings"))
    ;; The HOME-only read: ownership answers for every claimed
    ;; surface, identity only for the app's home.
    (jetpacs-defapp "multi" :label "Multi" :surfaces '("multi.home"
                                                       "multi.aux"))
    (should (equal (car (jetpacs-apps-for-surface "app:multi.aux"))
                   "multi"))
    (should (equal (car (jetpacs-apps-home-for-surface "app:multi.home"))
                   "multi"))
    (should-not (jetpacs-apps-home-for-surface "app:multi.aux"))))

(ert-deftest jetpacs-apps-drawer-composes-head-then-core ()
  "The composed drawer (S8): the Apps row first, one S1 nest per app
declaring destinations, then the host's seeded tail rows — the hub's
pass-4 IA, now surface-independent."
  (jetpacs-apps-test--env
    (setq jetpacs-apps-core-drawer-rows
          (lambda (_surface) (list (jetpacs-text "core-tail"))))
    (jetpacs-defapp "notes" :label "Notes" :surfaces '("notes.main")
                    :destinations
                    (list (list :key "inbox" :label "Inbox"
                                :verb "notes.inbox")))
    (let* ((drawer (jetpacs-apps-drawer "app:hub"))
           (printed (format "%S" drawer))
           (kids (append (plist-get drawer :children) nil)))
      (should (equal (plist-get drawer :t) "lazy_column"))
      ;; Head: the Apps entry leads.
      (should (string-search "drawer-apps" (format "%S" (car kids))))
      ;; The S1 nest and its deep link render.
      (should (string-search "Inbox" printed))
      (should (string-search "app.open" printed))
      ;; Tail: the seeded core rows close the list.
      (should (string-search "core-tail" (format "%S" (car (last kids)))))
      ;; Order: head strictly before tail.
      (should (< (string-search "drawer-apps" printed)
                 (string-search "core-tail" printed))))))

(ert-deftest jetpacs-apps-drawer-standalone-withdraws-and-core-isolates ()
  "A standalone app's own surface gets NO composed drawer (the
CHROME-VOCABULARY withdrawal); foreign surfaces keep it.  A
signalling core seed costs the tail rows, never the drawer."
  (jetpacs-apps-test--env
    (jetpacs-defapp "solo" :label "Solo" :surfaces '("solo.main")
                    :chrome 'standalone)
    (should-not (jetpacs-apps-drawer
                 (jetpacs-shell-surface-for "solo.main")))
    (should (jetpacs-apps-drawer "app:hub"))
    (setq jetpacs-apps-core-drawer-rows (lambda (_s) (error "boom")))
    (let ((drawer (jetpacs-apps-drawer "app:hub")))
      (should (equal (plist-get drawer :t) "lazy_column"))
      (should (string-search "drawer-apps" (format "%S" drawer))))))

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
                               (member (plist-get n :text)
                                       '("Alpha" "Zeta")))
                      (push (plist-get n :text) labels))
                    ;; The view is a chrome screen: descend :body too.
                    (when-let* ((body (plist-get n :body))) (walk body))
                    (mapc #'walk (append (plist-get n :children) nil))))
        (walk (jetpacs-apps--view)))
      (should (equal (nreverse labels) '("Alpha" "Zeta"))))))

(ert-deftest jetpacs-apps-drawer-row-opens-the-combined-view ()
  "Pass 2: one plain Apps row targeting the app-store surface."
  (let ((row (jetpacs-apps-drawer-row)))
    (should (equal (plist-get row :t) "card"))
    (let ((tap (plist-get row :on_tap)))
      (should (equal (plist-get tap :action) "jetpacs.launcher.open"))
      (should (equal (plist-get (plist-get tap :args) :surface)
                     "app:jetpacs.app-store")))))

;;;; The S1 destination registry (CHROME-VOCABULARY v3, build-within)

(ert-deftest jetpacs-apps-destinations-validate-at-build ()
  "A LIST of destinations is checked at `jetpacs-defapp' time — the
build-time-validation house rule; a FUNCTION is deferred trust,
re-checked (and isolated) per read."
  (jetpacs-apps-test--env
    (should-error (jetpacs-defapp "bad" :surfaces '("bad.main")
                                  :destinations '((:key "x"))))
    (should-error (jetpacs-defapp "bad" :surfaces '("bad.main")
                                  :destinations
                                  '((:key "has space" :label "X"
                                     :verb "x.open"))))
    (should-error (jetpacs-defapp "bad" :surfaces '("bad.main")
                                  :destinations
                                  '((:key "a" :label "A" :verb "a.open")
                                    (:key "a" :label "B" :verb "b.open"))))
    ;; A dotless verb can never have a registered handler: refused at
    ;; build (the jetpacs-action rule).
    (should-error (jetpacs-defapp "bad" :surfaces '("bad.main")
                                  :destinations
                                  '((:key "a" :label "A" :verb "open"))))
    ;; The function form registers unchecked and a BROKEN one costs
    ;; only that app's reads — including the escape hatches: a function
    ;; returning a FUNCTION, or an improper list, must not slip a
    ;; functionp fast path into a caller's mapcar.
    (jetpacs-defapp "fn" :surfaces '("fn.main")
                    :destinations (lambda () (error "boom")))
    (should-not (jetpacs-apps-destinations "fn"))
    (jetpacs-defapp "fn2" :surfaces '("fn2.main")
                    :destinations (lambda () '((:key "k"))))
    (should-not (jetpacs-apps-destinations "fn2"))
    (jetpacs-defapp "fn3" :surfaces '("fn3.main")
                    :destinations (lambda () (lambda () nil)))
    (should-not (jetpacs-apps-destinations "fn3"))
    (jetpacs-defapp "fn4" :surfaces '("fn4.main")
                    :destinations (lambda () (cons '(:key "a") 'improper)))
    (should-not (jetpacs-apps-destinations "fn4"))
    (jetpacs-defapp "ok" :surfaces '("ok.main")
                    :destinations
                    '((:key "one" :label "One" :verb "ok.one")))
    (should (equal (plist-get (car (jetpacs-apps-destinations "ok"))
                              :key)
                   "one"))))

(ert-deftest jetpacs-apps-open-route-redispatches-on-the-apps-surface ()
  "The S1 deep link end to end, WITH the D1 gate live: the row's tap
arrives from a HOST surface, `app.open' is ownerless so the gate lets
it through, and the route's OWNER-SCOPED verb (no `:any-surface') is
re-dispatched with the app's own home surface — where the same gate
passes.  The control proves the mechanism is load-bearing: the same
verb dispatched directly from the host surface refuses."
  (jetpacs-apps-test--env
    (let ((seen nil))
      (unwind-protect
          (progn
            (with-jetpacs-owner "routed"
              (jetpacs-defaction "routed.open"
                                 (lambda (_args params)
                                   ;; The re-dispatch must hand over the
                                   ;; FLOW identity too, not just the
                                   ;; dispatch params: flow-surface wins
                                   ;; over params in every downstream
                                   ;; navigate/flow pattern.
                                   (push (list (plist-get params :surface)
                                               (jetpacs-flow-surface)
                                               (jetpacs-device-flow-p))
                                         seen)
                                   'accepted)))
            ;; The owner must OWN its surface for the gate to pass.
            (cl-letf (((symbol-function 'jetpacs-owned-surface-p)
                       (lambda (surface owner)
                         (and (equal owner "routed")
                              (equal surface "app:routed.main")))))
              (jetpacs-defapp "routed" :surfaces '("routed.main")
                              :destinations
                              '((:key "main" :label "Main"
                                 :verb "routed.open")))
              ;; CONTROL: the bare verb from the host surface refuses.
              (should (eq (jetpacs--dispatch
                           nil '(:action "routed.open"
                                 :surface "app:hub")
                           (gethash "routed.open" jetpacs-action-handlers))
                          'rejected))
              (should-not seen)
              ;; The S1 path: app.open from the SAME host surface.
              (should (eq (jetpacs--dispatch
                           nil '(:action "app.open" :surface "app:hub"
                                 :args (:app "routed" :route "main"))
                           (gethash "app.open" jetpacs-action-handlers))
                          'accepted))
              (should (equal seen
                             '(("app:routed.main" "app:routed.main" t))))
              (should (equal jetpacs-apps--current "routed"))
              ;; The route handler accepted, so NO redundant home push.
              (should-not pushed)
              ;; A vanished route is stale — the row outlived its
              ;; registry.
              (should (eq (jetpacs-apps--action-open
                           '(:app "routed" :route "ghost") nil)
                          'stale))
              ;; A refusing route still opens the app: home fallback.
              (with-jetpacs-owner "routed"
                (jetpacs-defaction "routed.open"
                                   (lambda (_a _p) 'rejected)))
              (should (eq (jetpacs-apps--action-open
                           '(:app "routed" :route "main") nil)
                          'accepted))
              (should (equal pushed '("routed.main")))
              ;; A SIGNALING route (incl. the typed jsonrpc errors
              ;; jetpacs--dispatch deliberately re-signals) must not
              ;; die in the timer: it maps to the same fallback.
              (with-jetpacs-owner "routed"
                (jetpacs-defaction "routed.open"
                                   (lambda (_a _p)
                                     (signal 'jsonrpc-error
                                             '("retry" (jsonrpc-error-code . 1500))))))
              (setq pushed nil)
              (should (eq (jetpacs-apps--action-open
                           '(:app "routed" :route "main") nil)
                          'accepted))
              (should (equal pushed '("routed.main")))))
        (jetpacs-undefaction "routed.open")))))

(ert-deftest jetpacs-apps-destination-rows-compose-the-host-nests ()
  "The host consumption seam: one collapsible nest per app WITH
destinations, each row tapping the global `app.open' with its route;
apps without destinations cost nothing, and every node round-trips
the canonical encoding."
  (jetpacs-apps-test--env
    (jetpacs-defapp "plain" :surfaces '("plain.main"))
    (jetpacs-defapp "routed" :label "Routed" :icon "event"
                    :surfaces '("routed.main")
                    :destinations
                    '((:key "one" :label "One" :subtitle "First"
                       :verb "routed.one")
                      (:key "two" :label "Two" :verb "routed.two")))
    (let ((nests (jetpacs-apps-destination-rows)))
      (should (= 1 (length nests)))
      (let ((json (jetpacs-node->canonical-json (car nests))))
        (should (string-search "\"collapsible\"" json))
        ;; Collapsed by default — explicit, because the node's own
        ;; default is expanded.
        (should (string-search "\"collapsed\":true" json))
        (should (string-search "Routed" json))
        (should (string-search "app.open" json))
        (should (string-search "\"route\":\"one\"" json))
        (should (string-search "\"route\":\"two\"" json))
        ;; The rows must NOT dispatch the owner-scoped verbs directly.
        (should-not (string-search "routed.one" json))))))

;;;; The S2/S5 integration poles (CHROME-VOCABULARY v3)

(ert-deftest jetpacs-apps-chrome-pole-validates-and-composes ()
  "The `:chrome' pole: junk refuses at build; STANDALONE withdraws the
core dock and the app's items stay off foreign surfaces; PRIMARY
retains the global core and fills the remaining slots with destination tabs
through `app.open' `:route', Apps folding into the drawer."
  (jetpacs-apps-test--env
    (should-error (jetpacs-defapp "bad" :surfaces '("bad.main")
                                  :chrome 'sideways))
    ;; STANDALONE.
    (jetpacs-defapp "solo" :label "Solo" :surfaces '("solo.main")
                    :chrome 'standalone
                    :dock (list (list :label "Own" :icon "home"
                                      :on-tap '(:action "solo.show"))))
    (jetpacs-defapp "other" :label "Other" :surfaces '("other.main"))
    (setq jetpacs-apps--current "solo")
    (cl-letf (((symbol-function 'jetpacs-shell-surface-for)
               (lambda (owner) (concat "app:" owner))))
      ;; Its own surface: ONLY its authored items — no core, no Apps.
      (should (equal (jetpacs-apps-test--labels
                      (jetpacs-apps-dock-items "app:solo.main"))
                     '("Own")))
      ;; A foreign surface: core + Apps, and the standalone app's
      ;; items stay off it.
      (let ((labels (jetpacs-apps-test--labels
                     (jetpacs-apps-dock-items "app:hub"))))
        (should (equal labels '("Home" "Apps")))
        (should-not (member "Own" labels)))
      ;; The S3 wrapper: globals withdraw on the standalone surface
      ;; and survive on foreign ones.
      (let ((jetpacs-apps-core-global-actions (lambda (_s) '(seed))))
        (should-not (jetpacs-apps-global-actions "app:solo.main"))
        (should (equal (jetpacs-apps-global-actions "app:hub")
                       '(seed))))
      ;; The S10 wrapper: the DATA globals withdraw on exactly the same
      ;; surfaces — placement moves where a global rides, never whether
      ;; a standalone app must wear one — and a signalling seed costs
      ;; the globals, not the caller.
      (let ((jetpacs-apps-core-global-items
             (lambda (_s) (list (list :icon "terminal" :label "M-x"
                                      :on-tap '(:action "jetpacs.emacs.mx"))))))
        (should-not (jetpacs-apps-global-items "app:solo.main"))
        (should (equal (jetpacs-apps-test--labels
                        (jetpacs-apps-global-items "app:hub"))
                       '("M-x"))))
      (let ((jetpacs-apps-core-global-items (lambda (_s) (error "boom"))))
        (should-not (jetpacs-apps-global-items "app:hub")))
      ;; PRIMARY: the global core + destination tabs, Apps folded away.
      (jetpacs-defapp "prime" :label "Prime" :surfaces '("prime.main")
                      :chrome 'primary
                      :destinations
                      '((:key "one" :label "One" :icon "event"
                         :verb "prime.one")
                        (:key "two" :label "Two" :verb "prime.two")
                        (:key "three" :label "Three" :verb "prime.three")
                        (:key "four" :label "Four" :verb "prime.four")
                        (:key "five" :label "Five" :verb "prime.five")))
      (setq jetpacs-apps--current "prime"
            jetpacs-apps--current-route "two")
      (let* ((items (jetpacs-apps-dock-items "app:hub"))
             (labels (jetpacs-apps-test--labels items)))
        ;; This fixture has one core item, leaving four tabs in the M3
        ;; five-item budget; no trailing Apps.
        (should (equal labels '("Home" "One" "Two" "Three" "Four")))
        (should-not (member "Five" labels))
        (should-not (member "Apps" labels))
        ;; The tab rides the S1 deep link and the routed one is
        ;; selected.
        (let ((two (cl-find "Two" items
                            :key (lambda (i) (plist-get i :label))
                            :test #'equal)))
          (should (plist-get two :selected))
          (should (string-search "\"route\":\"two\""
                                 (jetpacs-node->canonical-json
                                  (plist-get two :on-tap)))))
        (should-not (plist-get
                     (cl-find "One" items
                              :key (lambda (i) (plist-get i :label))
                              :test #'equal)
                     :selected))))))

(provide 'jetpacs-apps-test)
;;; jetpacs-apps-test.el ends here
