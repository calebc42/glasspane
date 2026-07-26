;;; jetpacs-chrome-test.el --- JA-2c chrome kit exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-2c chrome half (docs/PLAN-jetpacs-apps.md, B6).  Stack pushes
;; are recorded at `ebp-client-surface-update'; view.switched drives the
;; REAL shell handler through `jetpacs--dispatch', proving the kit hook
;; is total under the no-prompts regime.

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

(defconst jetpacs-chrome-test--types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"
   "card" "icon" "icon_button" "lazy_column" "scaffold"])

(defun jetpacs-chrome-test--client (&optional profiles)
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-chrome-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client)
          (or profiles
              `(:app (:node_types ,jetpacs-chrome-test--types
                      :builtins ["view.switch"] :features [])))
          (ebp-client-limits client) '(:max_frame_bytes 4194304))
    client))

(defmacro jetpacs-chrome-test--with (client-form &rest body)
  (declare (indent 1))
  `(let ((client ,client-form))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-test-reset-state)
       (clrhash jetpacs-chrome--stacks))))

(defmacro jetpacs-chrome-test--recording (records &rest body)
  (declare (indent 1))
  `(let ((,records nil))
     (cl-letf (((symbol-function 'ebp-client-surface-update)
                (cl-function
                 (lambda (_c surface spec &rest keys)
                   (push (list surface spec keys) ,records)
                   42))))
       ,@body)))

;;;; Composition

(ert-deftest jetpacs-chrome-screen-shape ()
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-chrome-screen "Files" (jetpacs-text "body")
                                      :back (jetpacs-view-switch "hub")))))
    ;; Load-bearing: back precedes the title; weight rides ON the title;
    ;; back is the view.switch BUILTIN.
    (should (string-match-p "arrow_back" json))
    (should (string-match-p "\"builtin\":\"view.switch\",\"view\":\"hub\"" json))
    (should (string-match-p "\"text\":\"Files\",\"weight\":1" json))
    (should (< (string-search "arrow_back" json)
               (string-search "\"Files\"" json))))
  ;; No back: exactly one top-bar child, no icon_button anywhere.
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-chrome-screen "Hub" (jetpacs-text "b")))))
    (should-not (string-search "icon_button" json))))

(ert-deftest jetpacs-chrome-row-shape ()
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-chrome-row "Docs" :subtitle "3 files" :icon "folder"
                                   :key "r1"
                                   :trailing (jetpacs-icon "chevron_right")
                                   :on-tap (jetpacs-action
                                            "files.open"
                                            :args '(:path "docs"))))))
    ;; :key survived (universal attr via with-attrs — the poc drop bug).
    (should (string-match-p "\"key\":\"r1\"" json))
    (should (string-match-p "\"weight\":1" json))
    (should (string-match-p "\"action\":\"files.open\"" json))
    (should (string-match-p "chevron_right" json))
    (should (string-match-p "\"style\":\"caption\"" json))))

;;;; The stack

(defun jetpacs-chrome-test--define (owner root-id)
  (with-jetpacs-owner owner
    (jetpacs-chrome-define-root
     owner root-id
     (lambda (back)
       (should-not back)
       (jetpacs-chrome-screen "Hub" (jetpacs-text "h"))))))

(ert-deftest jetpacs-chrome-stack-push-drives-builder ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (should (= 42 (jetpacs-chrome-push-screen
                     "filesapp" "detail"
                     (lambda (back)
                       (jetpacs-chrome-screen "Detail" (jetpacs-text "d")
                                              :back back)))))
      (pcase-let ((`(,surface ,spec ,keys) (car recs)))
        (should (equal surface "app:filesapp"))
        (should (equal (plist-get keys :current-view) "detail"))
        (should (equal (plist-get spec :initial_view) "detail"))
        (let ((views (plist-get spec :views)))
          (should (gethash "hub" views))
          (should (gethash "detail" views))
          ;; Detail's back targets hub.
          (should (string-match-p
                   "\"builtin\":\"view.switch\",\"view\":\"hub\""
                   (jetpacs-node->canonical-json (gethash "detail" views))))))
      ;; A third screen backs onto detail.
      (jetpacs-chrome-push-screen
       "filesapp" "deeper"
       (lambda (back)
         (should (equal (plist-get back :view) "detail"))
         (jetpacs-chrome-screen "Deeper" (jetpacs-text "x") :back back)))
      (should (equal (jetpacs-chrome-stack "filesapp")
                     '("deeper" "detail" "hub"))))))

(ert-deftest jetpacs-chrome-pop-and-reset ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (back)
                                    (jetpacs-chrome-screen
                                     "D" (jetpacs-text "d") :back back)))
      (jetpacs-chrome-pop-screen "filesapp")
      (pcase-let ((`(,_s ,spec ,keys) (car recs)))
        (should (equal (plist-get keys :current-view) "hub"))
        (should-not (gethash "detail" (plist-get spec :views))))
      (should (equal (jetpacs-chrome-stack "filesapp") '("hub")))
      ;; Pop at the root: idempotent nil, no push.
      (let ((n (length recs)))
        (should-not (jetpacs-chrome-pop-screen "filesapp"))
        (should (= (length recs) n)))
      ;; Reset from deep.
      (jetpacs-chrome-push-screen "filesapp" "a" (lambda (_b) (jetpacs-text "a")))
      (jetpacs-chrome-push-screen "filesapp" "b" (lambda (_b) (jetpacs-text "b")))
      (jetpacs-chrome-reset-screens "filesapp")
      (should (equal (jetpacs-chrome-stack "filesapp") '("hub"))))))

(ert-deftest jetpacs-chrome-duplicate-id-truncates-and-replaces ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "one")))
      (jetpacs-chrome-push-screen "filesapp" "deeper"
                                  (lambda (_b) (jetpacs-text "two")))
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "Detail2")))
      (should (equal (jetpacs-chrome-stack "filesapp") '("detail" "hub")))
      (pcase-let ((`(,_s ,spec ,_k) (car recs)))
        (should (string-match-p
                 "Detail2"
                 (jetpacs-node->canonical-json
                  (gethash "detail" (plist-get spec :views)))))))))

(ert-deftest jetpacs-chrome-view-switched-truncates ()
  "Driven through the REAL registered shell handler: total under the
no-prompts regime, silent (no push), unknown views ignored."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "d")))
      (jetpacs-chrome-push-screen "filesapp" "deeper"
                                  (lambda (_b) (jetpacs-text "x")))
      (let ((n (length recs)))
        (should (eq 'accepted
                    (jetpacs--dispatch
                     client '(:action "view.switched"
                              :surface "app:filesapp"
                              :args (:view "detail"))
                     (gethash "view.switched" jetpacs-action-handlers))))
        (should (equal (jetpacs-chrome-stack "filesapp") '("detail" "hub")))
        (should (= (length recs) n))
        ;; Unknown view: untouched.
        (jetpacs--dispatch client '(:action "view.switched"
                                    :surface "app:filesapp"
                                    :args (:view "nowhere"))
                           (gethash "view.switched" jetpacs-action-handlers))
        (should (equal (jetpacs-chrome-stack "filesapp")
                       '("detail" "hub")))))))

(ert-deftest jetpacs-chrome-two-surfaces-independent ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "appa" "hub-a")
      (jetpacs-chrome-test--define "appb" "hub-b")
      (jetpacs-chrome-push-screen "appa" "d1" (lambda (_b) (jetpacs-text "d")))
      (should (equal (nth 0 (car recs)) "app:appa"))
      (should (equal (jetpacs-chrome-stack "appb") '("hub-b")))
      (jetpacs--dispatch client '(:action "view.switched"
                                  :surface "app:appa" :args (:view "hub-a"))
                         (gethash "view.switched" jetpacs-action-handlers))
      (should (equal (jetpacs-chrome-stack "appa") '("hub-a")))
      (should (equal (jetpacs-chrome-stack "appb") '("hub-b"))))))

(ert-deftest jetpacs-chrome-background-refresh-omits-current-view ()
  "SPEC 13.4 conformance: a plain refresh names no current_view but the
snapshot still carries every view with initial_view at the stack top."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (jetpacs-chrome-push-screen "filesapp" "detail"
                                  (lambda (_b) (jetpacs-text "d")))
      (jetpacs-shell-push "filesapp")
      (pcase-let ((`(,_s ,spec ,keys) (car recs)))
        (should-not (plist-get keys :current-view))
        (should (equal (plist-get spec :initial_view) "detail"))
        (should (gethash "hub" (plist-get spec :views)))))))

(ert-deftest jetpacs-chrome-push-screen-validates-before-wire ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (should-error (jetpacs-chrome-push-screen "filesapp" "/sdcard/x"
                                                #'ignore))
      (should-error (jetpacs-chrome-push-screen "neverdefined" "s" #'ignore))
      (should (equal (jetpacs-chrome-stack "filesapp") '("hub")))
      (should (null recs)))))

(ert-deftest jetpacs-chrome-drill-adapter ()
  "The C7 adapter: minted id, deferred push, repeat-drill replace-top."
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (jetpacs-chrome-test--recording recs
      (jetpacs-chrome-test--define "filesapp" "hub")
      (let ((deferred '()))
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (_t _r fn &rest _) (push fn deferred) nil)))
          (should (jetpacs-chrome--drill
                   "app:filesapp"
                   (lambda () (list (jetpacs-text "body")))
                   "*hostile name*"))
          ;; Stack mutated synchronously; the push deferred.
          (should (= (length (jetpacs-chrome-stack "app:filesapp")) 2))
          (should (null recs))
          (funcall (car deferred))
          (should (= (length recs) 1))
          ;; Repeat drill with the SAME label: replace-top, not stacking.
          (jetpacs-chrome--drill "app:filesapp"
                                 (lambda () (list (jetpacs-text "again")))
                                 "*hostile name*")
          (should (= (length (jetpacs-chrome-stack "app:filesapp")) 2)))))))

(ert-deftest jetpacs-chrome-teardown-hook-drops-stacks ()
  (jetpacs-chrome-test--with (jetpacs-chrome-test--client)
    (cl-letf (((symbol-function 'ebp-client-surface-remove)
               (cl-function (lambda (&rest _) 1))))
      (jetpacs-chrome-test--define "filesapp" "hub")
      (should (jetpacs-chrome-stack "filesapp"))
      (jetpacs-teardown-owner "filesapp")
      (should-not (jetpacs-chrome-stack "filesapp")))))

(provide 'jetpacs-chrome-test)
;;; jetpacs-chrome-test.el ends here
