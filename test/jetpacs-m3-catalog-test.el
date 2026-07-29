;;; jetpacs-m3-catalog-test.el --- the M3 catalog exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The catalog is 41 components and 279 example screens of authored
;; nodes; nothing else in the tree exercises that much of the builder
;; surface at once.  This suite is the gate: it BUILDS every screen the
;; app can show (Home, 41 component screens, 279 example screens, the
;; theme screen), serializes each through the canonical serializer, and
;; checks the SPEC rules a live push would check -- §16.2 profile,
;; §16.1 document-unique ids -- offline, with no device.
;;
;; It also holds the FIDELITY line: the inventory must still be the
;; upstream inventory (41 components in upstream order, each with its
;; upstream example count), and no example may still carry the
;; generator's triage sentinel.  A component module that quietly drops
;; an example fails here.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-m3-catalog)

(defconst jetpacs-m3-test--inventory
  '(("adaptive" "Adaptive" 7)
    ("badge" "Badge" 1)
    ("bottom-app-bar" "Bottom App Bar" 9)
    ("bottom-sheet" "Bottom Sheet" 3)
    ("buttons" "Buttons" 17)
    ("button-groups" "Button Groups" 4)
    ("card" "Card" 6)
    ("carousel" "Carousel" 6)
    ("checkboxes" "Checkboxes" 5)
    ("chips" "Chips" 13)
    ("date-pickers" "Date pickers" 5)
    ("dialogs" "Dialogs" 3)
    ("extended-fab" "Extended FAB" 12)
    ("floating-action-buttons" "Floating action buttons" 5)
    ("fab-menu" "FAB Menu" 1)
    ("floating-toolbar" "Floating Toolbar" 11)
    ("icon-buttons" "Icon buttons" 12)
    ("lists" "Lists" 12)
    ("loading-indicators" "Loading indicators" 5)
    ("menus" "Menus" 6)
    ("navigation-bar" "Navigation bar" 3)
    ("navigation-drawer" "Navigation drawer" 3)
    ("navigation-rail" "Navigation rail" 8)
    ("navigation-suite-scaffold" "Navigation Suite Scaffold" 2)
    ("progress-indicators" "Progress indicators" 8)
    ("pull-to-refresh-indicator" "Pull-to-Refresh Indicator" 6)
    ("radio-buttons" "Radio buttons" 2)
    ("search-bars" "Search bars" 3)
    ("segmented-button" "Segmented Button" 2)
    ("sliders" "Sliders" 11)
    ("snackbars" "Snackbars" 5)
    ("split-button" "Split Button" 12)
    ("switches" "Switches" 2)
    ("tabs" "Tabs" 12)
    ("text-fields" "Text fields" 14)
    ("time-picker" "Time Picker" 3)
    ("togglebuttons" "ToggleButtons" 10)
    ("tooltips" "Tooltips" 13)
    ("top-app-bar" "Top app bar" 15)
    ("material-shapes" "Material Shapes" 1)
    ("swipe-to-dismiss" "Swipe to Dismiss" 1))
  "(ID NAME EXAMPLE-COUNT) per upstream Components.kt, in its order.")

(defconst jetpacs-m3-test--sentinel "TODO: not yet triaged"
  "The stub generator's triage marker; none may survive.")

(defun jetpacs-m3-test--screens ()
  "Every screen the app can build: a list of (LABEL . NODE)."
  (let ((screens (list (cons "home" (jetpacs-m3-home-screen nil))
                       (cons "theme" (jetpacs-m3-theme-screen nil)))))
    (dolist (component jetpacs-m3-components)
      (let ((id (plist-get component :id)))
        (push (cons (concat "component:" id)
                    (jetpacs-m3-component-screen component nil))
              screens)
        (cl-loop for _example in (plist-get component :examples)
                 for index from 0
                 do (push (cons (format "example:%s/%d" id index)
                                (jetpacs-m3-example-screen component index nil))
                          screens))))
    (nreverse screens)))

;;;; Fidelity: the inventory is upstream's

(ert-deftest jetpacs-m3-inventory-matches-upstream ()
  "41 components, upstream order, upstream names and example counts."
  (should (= (length jetpacs-m3-components)
             (length jetpacs-m3-test--inventory)))
  (cl-loop for component in jetpacs-m3-components
           for (id name count) in jetpacs-m3-test--inventory
           do (should (equal (plist-get component :id) id))
              (should (equal (plist-get component :name) name))
              (should (= (length (plist-get component :examples)) count))))

(ert-deftest jetpacs-m3-inventory-total-is-279 ()
  (should (= 279 (cl-loop for c in jetpacs-m3-components
                          sum (length (plist-get c :examples))))))

(ert-deftest jetpacs-m3-every-example-is-triaged ()
  "Every example either builds a sample or says why it cannot."
  (dolist (component jetpacs-m3-components)
    (dolist (example (plist-get component :examples))
      (let ((label (format "%s/%s" (plist-get component :id)
                           (plist-get example :name)))
            (reason (plist-get example :unsupported)))
        ;; Recreated means ANY of the three: a body, the screen's
        ;; scaffold slots, or its top bar.
        (should (or (functionp (plist-get example :build))
                    (plist-get example :slots)
                    (functionp (plist-get example :top-bar))
                    reason))
        (when reason
          (should (stringp reason))
          ;; A bare sentinel means the component was never triaged.
          (should-not (equal reason jetpacs-m3-test--sentinel))
          ;; The reason is shown to the user; make it a sentence.
          (should (> (length reason) 20))
          (should-not (string-match-p "\\`TODO" reason)))
        (ignore label)))))

(ert-deftest jetpacs-m3-example-names-are-unique-per-component ()
  (dolist (component jetpacs-m3-components)
    (let ((names (mapcar (lambda (e) (plist-get e :name))
                         (plist-get component :examples))))
      (should (= (length names) (length (delete-dups (copy-sequence names))))))))

;;;; Every screen builds, serializes, and stays inside the app profile

(ert-deftest jetpacs-m3-every-screen-builds ()
  "Each screen is a root node that canonicalizes without signalling."
  (dolist (cell (jetpacs-m3-test--screens))
    (let ((node (cdr cell)))
      (should (jetpacs--root-node-p node))
      (should (equal (plist-get node :t) "scaffold"))
      (should (stringp (jetpacs-node->canonical-json node))))))

(ert-deftest jetpacs-m3-every-screen-is-in-the-app-profile ()
  "No screen emits a node type outside the reference `app' profile (§16.2)."
  (dolist (cell (jetpacs-m3-test--screens))
    (should (jetpacs-check-profile (cdr cell) 'app))))

(ert-deftest jetpacs-m3-no-sample-degrades-to-an-error-card ()
  "A signalling sample builder degrades to an `error' empty_state; none may.
`jetpacs-m3--example-body' catches the signal so one bad sample cannot
take the app down -- which would also hide the bug from every other
test here, so this is the one that looks for the degrade."
  (dolist (component jetpacs-m3-components)
    (dolist (example (plist-get component :examples))
      (when (plist-get example :build)
        (let* ((node (jetpacs-m3--example-body example))
               (json (jetpacs-node->canonical-json node)))
          (should-not
           (string-match-p "Sample failed to build" json)))))))

(ert-deftest jetpacs-m3-node-ids-are-unique-per-document ()
  "§16.1: ids are unique across the whole surface document.
The deepest document is Home + a component screen + one of its example
screens, the exact stack `jetpacs-chrome--build' composes."
  (let ((home (jetpacs-m3-home-screen nil)))
    (dolist (component jetpacs-m3-components)
      (let ((screen (jetpacs-m3-component-screen component nil)))
        (cl-loop
         for _example in (plist-get component :examples)
         for index from 0
         do (let* ((example-screen
                    (jetpacs-m3-example-screen component index nil))
                   (ids (append (jetpacs--collect-node-ids home nil)
                                (jetpacs--collect-node-ids screen nil)
                                (jetpacs--collect-node-ids
                                 example-screen nil))))
              (should (equal (sort (copy-sequence ids) #'string<)
                             (sort (delete-dups (copy-sequence ids))
                                   #'string<)))))))))

(ert-deftest jetpacs-m3-example-screens-title-their-example ()
  "The Example screen's top bar carries the upstream example name.
Skipped for an example that authors its own `:top-bar' — the whole
point of that slot is that the sample OWNS the bar, title included."
  (dolist (component jetpacs-m3-components)
    (cl-loop
     for example in (plist-get component :examples)
     for index from 0
     unless (plist-get example :top-bar)
     do (let ((json (jetpacs-node->canonical-json
                     (jetpacs-m3-example-screen component index nil))))
          (should (string-match-p
                   (regexp-quote
                    (concat "\"text\":"
                            (json-serialize (plist-get example :name))))
                   json))))))

(ert-deftest jetpacs-m3-custom-top-bars-offer-a-way-back ()
  "An example owning the top bar must still render the back affordance.
`jetpacs-chrome-screen' supplies it for every other screen; a sample
that replaces the bar takes on that duty, and a screen with no way
back strands the user in a three-deep stack."
  (dolist (component jetpacs-m3-components)
    (cl-loop
     for example in (plist-get component :examples)
     for index from 0
     when (plist-get example :top-bar)
     do (let ((json (jetpacs-node->canonical-json
                     (jetpacs-m3-example-screen
                      component index (jetpacs-view-switch "home")))))
          (should (string-match-p "\"builtin\":\"view.switch\"" json))))))

;;;; The verbs

(ert-deftest jetpacs-m3-open-rejects-and-stales-correctly ()
  (should (eq 'rejected (jetpacs-m3--on-open '(:component 7) nil)))
  (should (eq 'stale (jetpacs-m3--on-open '(:component "nope") nil)))
  (should (eq 'rejected (jetpacs-m3--on-example
                         '(:component "buttons" :index "0") nil)))
  (should (eq 'rejected (jetpacs-m3--on-demo '(:message 3) nil)))
  (should (eq 'rejected (jetpacs-m3--on-pin '(:screen nil) nil)))
  (should (eq 'rejected (jetpacs-m3--on-pref '(:key "bogus") nil))))

(ert-deftest jetpacs-m3-pin-toggles ()
  (let ((jetpacs-m3-favorite nil))
    (jetpacs-m3--on-pin '(:screen "c-buttons") nil)
    (should (equal jetpacs-m3-favorite "c-buttons"))
    (jetpacs-m3--on-pin '(:screen "c-buttons") nil)
    (should-not jetpacs-m3-favorite)))

(ert-deftest jetpacs-m3-expressive-filter-shrinks-the-lists ()
  (let ((jetpacs-m3-show-only-expressive t))
    (should (< (length (jetpacs-m3-visible-components))
               (length jetpacs-m3-components)))
    (dolist (component (jetpacs-m3-visible-components))
      (should (jetpacs-m3-visible-examples component))))
  (let ((jetpacs-m3-show-only-expressive nil))
    (should (= (length (jetpacs-m3-visible-components))
               (length jetpacs-m3-components)))))

(ert-deftest jetpacs-m3-visible-examples-keep-upstream-indices ()
  "Filtering must not renumber examples -- the index is the wire address."
  (let* ((component (jetpacs-m3-component "buttons"))
         (jetpacs-m3-show-only-expressive t))
    (dolist (cell (jetpacs-m3-visible-examples component))
      (should (eq (cdr cell)
                  (nth (car cell) (plist-get component :examples)))))))

(provide 'jetpacs-m3-catalog-test)
;;; jetpacs-m3-catalog-test.el ends here
