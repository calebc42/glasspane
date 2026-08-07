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
(require 'jetpacs-apps)
(require 'jetpacs-m3-catalog)

(defconst jetpacs-m3-test--root
  (expand-file-name ".." (file-name-directory
                          (or load-file-name buffer-file-name)))
  "Repo root, captured at LOAD time — nil inside a test body.")

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
  "Every screen the app can build: a list of (LABEL . NODE).
The source screens are here for the same reason the example screens
are: \"View elisp\" is reachable from the menu of every example that has
a `:build', so its screen is one the app can show and must satisfy the
same gates.  Its body is the ONE piece of catalog content nobody
authored as nodes — it is a file read at build time — which is exactly
why it must be swept rather than trusted."
  (let ((screens (list (cons "home" (jetpacs-m3-home-screen nil))
                       (cons "theme" (jetpacs-m3-theme-screen nil)))))
    (dolist (component jetpacs-m3-components)
      (let ((id (plist-get component :id)))
        (push (cons (concat "component:" id)
                    (jetpacs-m3-component-screen component nil))
              screens)
        (cl-loop for example in (plist-get component :examples)
                 for index from 0
                 do (push (cons (format "example:%s/%d" id index)
                                (jetpacs-m3-example-screen component index nil))
                          screens)
                    (when (plist-get example :build)
                      (push (cons (format "source:%s/%d" id index)
                                  (jetpacs-m3-source-screen component index nil))
                            screens)))))
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
      (should (jetpacs-root-node-p node))
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
                   (ids (append (jetpacs-collect-node-ids home nil)
                                (jetpacs-collect-node-ids screen nil)
                                (jetpacs-collect-node-ids
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

;;;; "View elisp": the example shows its own source

(ert-deftest jetpacs-m3-example-menu-carries-view-elisp ()
  "The Example more-menu gains \"View elisp\" WITHOUT losing upstream's
\"View source code\" — the two answer different questions, the Kotlin
this was ported from and the elisp it was ported to.  The row is offered
whenever there is a defun to show, which is whenever
`jetpacs-m3--example-builder' finds one; only an `:unsupported' example,
which has no builder at all, gets the upstream seven alone.

It was once gated on `:build', which silently denied it to the 26
examples whose sample is a scaffold SLOT — they have a defun, and a good
one, and no way to reach it."
  (let* ((component (jetpacs-m3-component "switches"))
         (json (jetpacs-node->canonical-json
                (jetpacs-m3-example-screen component 0 nil))))
    (should (string-match-p "View elisp" json))
    (should (string-match-p "View source code" json))
    (should (string-match-p "\"action\":\"m3catalog.source\"" json)))
  ;; Home, the component screen and the theme screen never carry it.
  (dolist (node (list (jetpacs-m3-home-screen nil)
                      (jetpacs-m3-theme-screen nil)
                      (jetpacs-m3-component-screen
                       (jetpacs-m3-component "switches") nil)))
    (should-not (string-match-p "View elisp"
                                (jetpacs-node->canonical-json node))))
  ;; A slots-only example HAS a defun and now gets the row.
  (let ((found nil))
    (dolist (component jetpacs-m3-components)
      (cl-loop
       for example in (plist-get component :examples)
       for index from 0
       when (and (null (plist-get example :build))
                 (null (plist-get example :top-bar))
                 (jetpacs-m3--example-builder example))
       do (setq found t)
          (let ((json (jetpacs-node->canonical-json
                       (jetpacs-m3-example-screen component index nil))))
            (should (string-match-p "View elisp" json))
            (should (string-match-p "View source code" json)))))
    (should found))
  ;; An `:unsupported' example has no builder, so no row — and upstream's
  ;; stays, because the Kotlin it was ported from still exists to read.
  (let ((found (jetpacs-m3-test--example-where
                (lambda (e) (plist-get e :unsupported)))))
    (should found)
    (pcase-let ((`(,component ,index ,_example) found))
      (let ((json (jetpacs-node->canonical-json
                   (jetpacs-m3-example-screen component index nil))))
        (should-not (string-match-p "View elisp" json))
        (should (string-match-p "View source code" json))))))

(ert-deftest jetpacs-m3-source-extraction-returns-the-authored-defun ()
  "The modules load from SOURCE .el, so the defining text is recoverable
VERBATIM — docstring, indentation and all — not reconstructed."
  (let* ((example (nth 0 (plist-get (jetpacs-m3-component "switches")
                                    :examples)))
         (source (jetpacs-m3-example-source (plist-get example :build)))
         (text (plist-get source :text)))
    (should (string-prefix-p "(defun jetpacs-m3-" text))
    (should (string-match-p "jetpacs-m3-switches--basic" text))
    ;; The docstring came along, which is what "verbatim" buys.
    (should (string-match-p "Upstream SwitchSample" text))
    ;; And it is a COMPLETE form, not a truncated head: it reads back.
    (let ((form (car (read-from-string text))))
      (should (eq (car form) 'defun))
      (should (eq (nth 1 form) 'jetpacs-m3-switches--basic)))
    (should (string-match-p "jetpacs-m3-switches\\.el"
                            (plist-get source :caption)))))

(ert-deftest jetpacs-m3-source-extraction-falls-back-to-the-closure ()
  "No findable source file means the LOADED CLOSURE, captioned as such.
An uninterned symbol is the honest fixture: nothing put it in
`load-history', which is the same position a REPL-defined builder is
in.  The screen still has something true to show."
  (let ((sym (make-symbol "jetpacs-m3-test--no-source-anywhere")))
    (fset sym (lambda () (jetpacs-text "nowhere")))
    (let ((source (jetpacs-m3-example-source sym)))
      (should (> (length (plist-get source :text)) 0))
      (should (string-match-p "nowhere" (plist-get source :text)))
      (should (string-match-p "LOADED CLOSURE" (plist-get source :caption)))))
  ;; An inline-lambda `:build' (37 of the catalog's builders) takes the
  ;; same path — there is no symbol to look up in the first place.
  (let ((source (jetpacs-m3-example-source (lambda () nil))))
    (should (> (length (plist-get source :text)) 0))
    (should (string-match-p "LOADED CLOSURE" (plist-get source :caption))))
  ;; And a non-function never signals; it just has nothing to say.
  (should (stringp (plist-get (jetpacs-m3-example-source nil) :text))))

(ert-deftest jetpacs-m3-source-extraction-is-capped ()
  "The cap is defensive, announced in the text, and never a failure.
Nothing authored comes near it — the longest catalog builder is under
2000 characters against a 20000 cap — so this drives it with a builder
whose printed form is deliberately enormous."
  (should (= jetpacs-m3-source-max-chars 20000))
  (let ((sym (make-symbol "jetpacs-m3-test--enormous")))
    (fset sym `(lambda () ,(make-string (* 4 jetpacs-m3-source-max-chars) ?x)))
    (let ((text (plist-get (jetpacs-m3-example-source sym) :text)))
      (should (string-match-p "truncated at 20000 characters" text))
      ;; The cap plus the notice, nothing like the 80000 it started at.
      (should (< (length text) (+ jetpacs-m3-source-max-chars 200)))))
  ;; Every real example stays under it untruncated.
  (dolist (component jetpacs-m3-components)
    (dolist (example (plist-get component :examples))
      (when (plist-get example :build)
        (should-not (string-match-p
                     "truncated at"
                     (plist-get (jetpacs-m3-example-source
                                 (plist-get example :build))
                                :text)))))))

(ert-deftest jetpacs-m3-source-screen-offers-copy-and-a-way-back ()
  "The leaf viewer's two affordances: the back arrow and \"Copy sexp\",
the latter riding the `clipboard.copy' builtin rather than a verb, so
it works with Emacs busy."
  (let* ((component (jetpacs-m3-component "switches"))
         (json (jetpacs-node->canonical-json
                (jetpacs-m3-source-screen component 0
                                          (jetpacs-view-switch "home")))))
    (should (string-match-p "\"builtin\":\"clipboard.copy\"" json))
    (should (string-match-p "Copy sexp" json))
    (should (string-match-p "\"builtin\":\"view.switch\"" json))
    ;; Mono and selectable: the screen exists to be read and taken.
    (should (string-match-p "\"style\":\"mono\"" json))
    (should (string-match-p "\"selectable\":true" json))
    ;; A leaf: no pin, because `jetpacs-m3-catalog' cannot reopen an
    ;; `s-' id, and no more-menu, because the menu is what got us here.
    (should-not (string-match-p "m3catalog.pin" json))
    (should-not (string-match-p "View elisp" json))))

(ert-deftest jetpacs-m3-source-verb-rejects-and-stales-correctly ()
  (should (eq 'rejected (jetpacs-m3--on-source '(:component 7 :index 0) nil)))
  (should (eq 'rejected (jetpacs-m3--on-source
                         '(:component "switches" :index "0") nil)))
  (should (eq 'stale (jetpacs-m3--on-source
                      '(:component "nope" :index 0) nil))))

;;;; The floor seam

(ert-deftest jetpacs-m3-ready-hook-is-wired ()
  "The catalog subscribes ITSELF to the floor's READY ladder.
This is the seam that lets an app ship out of tree: the floor no
longer names `jetpacs-m3--on-ready' anywhere, so the only thing
attaching the catalog's client hooks at READY is the `add-hook' the
app runs at load -- and this is the only suite that loads the app."
  (should (memq #'jetpacs-m3--on-ready jetpacs-ready-functions)))

;;;; Material 3 is the design language, and the version is PINNED

(ert-deftest jetpacs-m3-material-version-matches-the-toml ()
  "THE UNANIMOUS-UPDATE MECHANISM.  Material is Jetpacs' design language
and its version has ONE source of truth --
companion/gradle/libs.versions.toml's `material3' entry.
`jetpacs-m3-material-version' restates it so the phone can say which
Material it is showing, and this test reads the toml off disk and
asserts the two are equal.  Bumping the toml without bumping the
constant therefore goes RED: the version moves in the toml, in the
constant, and in the doctrine paragraph of docs/ARCHITECTURE-POC3.md,
or it does not move."
  (let ((toml (expand-file-name "companion/gradle/libs.versions.toml"
                                jetpacs-m3-test--root))
        (version nil))
    (should (file-readable-p toml))
    (with-temp-buffer
      (insert-file-contents toml)
      (goto-char (point-min))
      ;; Line-anchored: [libraries] also carries a `version.ref =
      ;; "material3"', which is a REFERENCE to this entry, not a version.
      (should (re-search-forward "^material3 *= *\"\\([^\"]+\\)\"" nil t))
      (setq version (match-string 1)))
    (should (equal version jetpacs-m3-material-version))))

(ert-deftest jetpacs-m3-home-screen-carries-the-identity ()
  "The root screen says who this app is and which Material it is.
The dock and drawer label stays the short \"Catalog\"; the full ratified
identity lives in the root screen's body, where a sixty-character
string is not a top-bar flex trap."
  (let ((json (jetpacs-node->canonical-json (jetpacs-m3-home-screen nil))))
    (should (string-match-p (regexp-quote (json-serialize
                                           jetpacs-m3-identity))
                            json))
    (should (string-match-p (regexp-quote jetpacs-m3-material-version)
                            json))))

;;;; App identity: `jetpacs-defapp''s first caller

(ert-deftest jetpacs-m3-catalog-registers-as-an-app ()
  "Requiring the catalog REGISTERS it: the app registry is non-vacuous,
and this is the only suite that can say so — `jetpacs-defapp' had zero
callers before the catalog became one."
  (let ((entry (assoc jetpacs-m3-owner jetpacs-apps--registry)))
    (should entry)
    (should (equal (plist-get (cdr entry) :label) "Catalog"))
    (should (member jetpacs-m3-owner (plist-get (cdr entry) :surfaces)))
    ;; The home surface is the one the chrome root was defined on, so
    ;; `app.open' lands somewhere that exists.
    (should (equal (jetpacs-apps--home-surface entry) jetpacs-m3-owner))))

(ert-deftest jetpacs-m3-catalog-dock-composes-after-the-core ()
  "The composed dock is the HOST's core items plus the catalog's, in
that order — and with exactly one registered app the launcher grid
stays off (`jetpacs-apps--multi-p' nil), which is the single-app
contract."
  (let ((jetpacs-apps-core-dock-items
         (lambda (_surface)
           (list (list :label "Home" :icon "home")
                 (list :label "Files" :icon "folder_open")))))
    (should-not (jetpacs-apps--multi-p))
    (should (equal (car (jetpacs-apps-current)) jetpacs-m3-owner))
    (should (equal (mapcar (lambda (i) (plist-get i :label))
                           (jetpacs-apps-dock-items "app:hub"))
                   '("Home" "Files" "Catalog")))
    ;; The destination reads selected only on the catalog's own surface.
    (let ((home (jetpacs-shell-surface-for jetpacs-m3-owner)))
      (cl-flet ((catalog-item (surface)
                  (cl-find "Catalog" (jetpacs-apps-dock-items surface)
                           :key (lambda (i) (plist-get i :label))
                           :test #'equal)))
        (should-not (plist-get (catalog-item "app:hub") :selected))
        (should (plist-get (catalog-item home) :selected))
        ;; A GLOBAL verb: the tap arrives from any surface the dock
        ;; renders on, and it names the catalog's surface explicitly.
        (let ((tap (plist-get (catalog-item "app:hub") :on-tap)))
          (should (equal (plist-get tap :action) "jetpacs.launcher.open"))
          (should (equal (plist-get (plist-get tap :args) :surface) home)))))))

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

;;;; The example's own doc string

(defun jetpacs-m3-test--texts (node)
  "Every `text' member anywhere in NODE's tree, as a list of strings."
  (let (out)
    (cl-labels
        ((walk (x)
           (cond
            ((vectorp x) (mapc #'walk x))
            ((and (consp x) (keywordp (car x)))
             (cl-loop for (key value) on x by #'cddr
                      do (when (and (eq key :text) (stringp value))
                           (push value out))
                         (walk value)))
            ((consp x) (mapc #'walk x)))))
      (walk node))
    (nreverse out)))

(defun jetpacs-m3-test--example-where (predicate)
  "The first (COMPONENT INDEX EXAMPLE) whose EXAMPLE satisfies PREDICATE.
Found rather than hard-coded: these are populations whose membership the
catalog keeps changing, and a test naming one by slug rots the day that
sample is rewritten."
  (cl-loop for component in jetpacs-m3-components
           thereis (cl-loop for example in (plist-get component :examples)
                            for index from 0
                            when (funcall predicate example)
                            return (list component index example))))

(ert-deftest jetpacs-m3-example-screen-carries-the-builder-docstring ()
  "The Example screen says what M3 calls this AND what the elisp says.
Upstream's `:description' is product copy; the builder's docstring is
the only thing on that screen written by whoever actually drew it."
  (let* ((component (jetpacs-m3-component "switches"))
         (texts (jetpacs-m3-test--texts
                 (jetpacs-m3-example-screen component 0 nil))))
    (should (member "Elisp" texts))
    (should (cl-some (lambda (s) (string-match-p "Upstream SwitchSample" s))
                     texts))))

(defun jetpacs-m3-test--anonymous-example ()
  "A (COMPONENT INDEX EXAMPLE) triple whose `:build' is an inline lambda.
Synthetic, and deliberately NOT registered: the catalog no longer has
one to find, every module having been swept to named builders so the
Example screen can show a docstring and the authored source.  The
screen code must still survive a builder with no symbol -- a
REPL-defined one arrives exactly that way -- so the fixture is built
here rather than borrowed from whichever module last owed the debt."
  (let ((component
         (list :id "test-anonymous"
               :name "Anonymous"
               :description "Synthetic component; never registered."
               :examples
               (list (jetpacs-m3-example
                      "AnonymousBuilderSample" "Anonymous examples"
                      :build (lambda () (jetpacs-text "no docstring")))))))
    (list component 0 (car (plist-get component :examples)))))

(ert-deftest jetpacs-m3-doc-block-is-absent-when-there-is-nothing-to-say ()
  "No docstring, no block — never an empty heading.
An inline lambda has none to read and an `:unsupported' example has no
builder at all; both must reach the screen without a bare \"Elisp\"
title standing over nothing."
  (dolist (found (list (jetpacs-m3-test--anonymous-example)
                       (jetpacs-m3-test--example-where
                        (lambda (e) (plist-get e :unsupported)))))
    (should found)
    (pcase-let ((`(,component ,index ,example) found))
      (should-not (jetpacs-m3-example-doc example))
      (should-not (member "Elisp"
                          (jetpacs-m3-test--texts
                           (jetpacs-m3-example-screen
                            component index nil)))))))

(ert-deftest jetpacs-m3-doc-falls-back-to-the-chrome-builder ()
  "An example that IS screen chrome documents itself through its slot.
Seventy examples have no `:build' — their subject is a top bar or a
scaffold slot — and reading only `:build' would leave every one of them
silent on a screen whose whole point is to explain the sample."
  (let ((found (jetpacs-m3-test--example-where
                (lambda (e) (and (null (plist-get e :build))
                                 (null (plist-get e :unsupported))
                                 (jetpacs-m3--example-builder e))))))
    (should found)
    (should (stringp (jetpacs-m3-example-doc (nth 2 found))))))

(ert-deftest jetpacs-m3-doc-names-this-example-not-its-sibling ()
  "The builder that NAMES the example is the one written for it.
Neither plist key wins positionally, and both mistakes are live in this
catalog.  Chrome-as-backdrop: the search-bar samples share a `:build'
that only gives the collapsing bar a hundred lines to scroll, so asking
`:build' made a full-screen-search-bar screen call itself \"the Scaffold
content both scaffold samples share\".  And the mirror image:
`PinnedTopAppBarWithReversedLazyGrid' shares its `:top-bar' with a
SIBLING example and owns only its body, so asking the chrome made that
screen name the sibling's upstream sample and show the sibling's defun.

Both read plausibly, which is exactly why the docstring — not the key —
has to decide."
  ;; The backdrop direction.
  (let* ((component (jetpacs-m3-component "search-bars"))
         (example (nth 1 (plist-get component :examples))))
    (should (eq (jetpacs-m3--example-builder example)
                (plist-get example :top-bar))))
  ;; The sibling direction: shared chrome, unique body.
  (let* ((component (jetpacs-m3-component "top-app-bar"))
         (found (cl-loop for e in (plist-get component :examples)
                         when (equal (plist-get e :name)
                                     "PinnedTopAppBarWithReversedLazyGrid")
                         return e)))
    (should found)
    (should (eq (jetpacs-m3--example-builder found)
                (plist-get found :build)))))

(ert-deftest jetpacs-m3-doc-strings-name-their-own-sample ()
  "A screen must not describe a DIFFERENT upstream sample than its own.
Naming the wrong sibling is the failure mode here — it is never obviously
wrong on screen, so it needs a count.  The exceptions are builders
genuinely shared by several samples, whose docstring describes the shared
thing; that population is allowed but not allowed to GROW silently."
  (let (mismatched)
    (dolist (component jetpacs-m3-components)
      (dolist (example (plist-get component :examples))
        (unless (plist-get example :unsupported)
          (let ((doc (jetpacs-m3-example-doc example))
                (name (plist-get example :name)))
            (unless (and doc (string-search name doc))
              (push (format "%s/%s" (plist-get component :id) name)
                    mismatched))))))
    (should (<= (length mismatched) 15))))

(ert-deftest jetpacs-m3-example-doc-never-signals ()
  "A docstring nobody can read costs its block and nothing else.
`documentation' reads a doc file and can fail on a stripped or moved
function, and this runs while a screen is being BUILT — losing the app
over a comment would be an absurd way to lose it."
  (should-not (jetpacs-m3-example-doc
               (list :build (make-symbol "jetpacs-m3-test--never-defined"))))
  (should-not (jetpacs-m3-example-doc (list :build "not a function")))
  (should-not (jetpacs-m3-example-doc nil)))

(ert-deftest jetpacs-m3-doc-strings-cover-every-named-builder ()
  "The authoring brief has required a docstring per sample from the start.
This is the count that says whether that is actually TRUE, so a new
module which skips one is caught here rather than by a blank space on a
phone.  The examples with no named builder at all are the inline
lambdas, which have no symbol to carry a docstring."
  (let (missing)
    (dolist (component jetpacs-m3-components)
      (cl-loop for example in (plist-get component :examples)
               for index from 0
               when (and (not (plist-get example :unsupported))
                         (jetpacs-m3--example-builder example)
                         (not (jetpacs-m3-example-doc example)))
               do (push (format "%s/%d" (plist-get component :id) index)
                        missing)))
    (should-not missing)))

;;;; The component's node builders

(ert-deftest jetpacs-m3-every-component-names-its-builders ()
  "All 41 map onto the node vocabulary, and every symbol is real.
`jetpacs-m3-defcomponent' signals on an unbound one, so this is really
asking that none was left empty — a component with no `:builders' shows
a Description and then nothing about how to build the thing."
  (dolist (component jetpacs-m3-components)
    (let ((builders (plist-get component :builders)))
      (should builders)
      (dolist (builder builders)
        (should (fboundp builder))
        ;; A node builder, not a verb or a helper that wandered in.
        (should (string-prefix-p "jetpacs-" (symbol-name builder)))
        (should-not (string-prefix-p "jetpacs-m3-" (symbol-name builder)))))))

(ert-deftest jetpacs-m3-component-screen-carries-the-builder-docs ()
  "Upstream says what the component IS; the builder says what you write."
  (let* ((component (jetpacs-m3-component "buttons"))
         (texts (jetpacs-m3-test--texts
                 (jetpacs-m3-component-screen component nil))))
    (should (member "Description" texts))
    (should (member "Elisp" texts))
    (should (member "jetpacs-button" texts))
    ;; The real docstring, not a placeholder.
    (should (cl-some (lambda (s) (string-match-p "SPEC" s)) texts))
    (should (member "Describe jetpacs-button" texts))))

(ert-deftest jetpacs-m3-describe-is-addressed-by-index-never-by-symbol ()
  "The wire names a POSITION in a component's own list, never a symbol.
Resolving a symbol off the wire would let any tap describe anything in
the image — the reasoning `jetpacs-m3--open-source' already records."
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-m3-component-screen
                (jetpacs-m3-component "buttons") nil))))
    (should (string-match-p "\"action\":\"m3catalog.describe\"" json))
    (should (string-match-p "\"component\":\"buttons\"" json))
    ;; The args carry an index and NOT a function name.
    (should-not (string-match-p "\"builder\":" json)))
  ;; Out-of-range, unknown component and non-integer index are refused
  ;; without ever reaching `describe-function'.
  (should (eq 'stale (jetpacs-m3--on-describe
                      '(:component "buttons" :index 99) nil)))
  (should (eq 'stale (jetpacs-m3--on-describe
                      '(:component "no-such-component" :index 0) nil)))
  (should (eq 'rejected (jetpacs-m3--on-describe
                         '(:component "buttons" :index "0") nil)))
  (should (eq 'rejected (jetpacs-m3--on-describe '(:index 0) nil))))

(ert-deftest jetpacs-m3-builder-doc-never-signals ()
  (should-not (jetpacs-m3-builder-doc (make-symbol "jetpacs-m3-test--nope")))
  (should-not (jetpacs-m3-builder-doc nil)))

(provide 'jetpacs-m3-catalog-test)
;;; jetpacs-m3-catalog-test.el ends here
