;;; jetpacs-launcher-test.el --- JA-6 launcher exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The launcher half of the JA-6 F5 gate: the registry read (self
;; excluded, sorted), the row shape, the open verb's membership
;; stale-guard (the wire does not get to nominate surfaces), and the
;; show verb's :any-surface exemption through the REAL dispatch.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-launcher)

(defconst jetpacs-launcher-test--app-types
  ["text" "row" "column" "box" "card" "lazy_column" "icon_button" "icon"
   "empty_state" "scaffold" "button"])

(defun jetpacs-launcher-test--client ()
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-launcher-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-launcher-test--app-types
                  :builtins ["view.switch"] :features [])))
    client))

(defmacro jetpacs-launcher-test--with-demos (&rest body)
  "BODY with two demo roots registered; they are removed afterwards."
  (declare (indent 0))
  `(unwind-protect
       (progn
         (with-jetpacs-owner "demob" (jetpacs-shell-define-root "demob" #'ignore))
         (with-jetpacs-owner "demoa" (jetpacs-shell-define-root "demoa" #'ignore))
         ,@body)
     (jetpacs-shell-remove-root "app:demoa")
     (jetpacs-shell-remove-root "app:demob")))

(defun jetpacs-launcher-test--collect (node key)
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

(ert-deftest jetpacs-launcher-entries-exclude-self-and-sort ()
  (jetpacs-launcher-test--with-demos
    (let ((entries (jetpacs-launcher--entries)))
      (should (member '("app:demoa" . "demoa") entries))
      (should (member '("app:demob" . "demob") entries))
      (should-not (assoc "app:jetpacs.launcher" entries))
      ;; Sorted by surface: demoa before demob wherever they sit.
      (let ((surfaces (mapcar #'car entries)))
        (should (< (cl-position "app:demoa" surfaces :test #'equal)
                   (cl-position "app:demob" surfaces :test #'equal)))))))

(ert-deftest jetpacs-launcher-view-rows-carry-the-switch ()
  (jetpacs-launcher-test--with-demos
    (let ((view (jetpacs-launcher--view)))
      (should (member "jetpacs.launcher.open"
                      (jetpacs-launcher-test--collect view :action)))
      (should (member (list :surface "app:demoa")
                      (jetpacs-launcher-test--collect view :args))))))

(ert-deftest jetpacs-launcher-open-guards-membership ()
  "A tapped row must still NAME a registered root; an unknown surface
is `stale' (the snapshot is outdated), never a push of whatever string
arrived."
  (jetpacs-launcher-test--with-demos
    (let ((client (jetpacs-launcher-test--client)))
      (unwind-protect
          (progn
            (jetpacs-attach client)
            (let ((handler (gethash "jetpacs.launcher.open"
                                    jetpacs-action-handlers))
                  (pushed '()))
              (cl-letf (((symbol-function 'jetpacs-shell-push)
                         (lambda (surface &rest _) (push surface pushed) 1)))
                (should (eq (jetpacs--dispatch
                             client '(:action "jetpacs.launcher.open"
                                      :surface "app:jetpacs.launcher"
                                      :args (:surface "app:demoa"))
                             handler)
                            'accepted))
                ;; D2: deferred out of the extent.
                (should (null pushed))
                (cl-loop repeat 10 do (accept-process-output nil 0.05))
                (should (equal pushed '("app:demoa")))
                ;; Unknown (a torn-down app's cached row): stale, no push.
                (should (eq (jetpacs--dispatch
                             client '(:action "jetpacs.launcher.open"
                                      :surface "app:jetpacs.launcher"
                                      :args (:surface "app:gone"))
                             handler)
                            'stale))
                (cl-loop repeat 10 do (accept-process-output nil 0.05))
                (should (equal pushed '("app:demoa"))))))
        (jetpacs-detach)
        (jetpacs-test-reset-state)))))

(ert-deftest jetpacs-launcher-show-is-a-global-verb ()
  "The button renders in OTHER owners' top bars, so the event's surface
is legitimately foreign — the :any-surface exemption must hold."
  (jetpacs-launcher-test--with-demos
    (let ((client (jetpacs-launcher-test--client)))
      (unwind-protect
          (progn
            (jetpacs-attach client)
            (let ((handler (gethash "jetpacs.launcher.show"
                                    jetpacs-action-handlers))
                  (pushed '()))
              (cl-letf (((symbol-function 'jetpacs-shell-push)
                         (lambda (surface &rest _) (push surface pushed) 1)))
                (should (eq (jetpacs--dispatch
                             client '(:action "jetpacs.launcher.show"
                                      :surface "app:demoa")
                             handler)
                            'accepted))
                (cl-loop repeat 10 do (accept-process-output nil 0.05))
                (should (equal pushed (list jetpacs-launcher-owner))))))
        (jetpacs-detach)
        (jetpacs-test-reset-state)))))

(ert-deftest jetpacs-launcher-button-shape ()
  (let ((btn (jetpacs-launcher-button)))
    (should (equal (jetpacs-launcher-test--collect btn :action)
                   '("jetpacs.launcher.show")))
    (should (member "icon_button" (jetpacs-launcher-test--collect btn :t)))))

(provide 'jetpacs-launcher-test)
;;; jetpacs-launcher-test.el ends here
