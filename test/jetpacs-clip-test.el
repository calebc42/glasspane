;;; jetpacs-clip-test.el --- JA-1 clip view exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-1 clip half of the exit gate (docs/PLAN-jetpacs-apps.md).
;; The view tests run offline (advertised-p assumes the richer form)
;; and against stub profiles that witness both the live gate pass and
;; the unadvertised degrade; the refresh handler is driven through the
;; REAL `jetpacs--dispatch' so D1/D2 are the live properties.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-clip)

(defconst jetpacs-clip-test--app-types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"
   "card" "lazy_column" "icon_button" "icon" "empty_state" "scaffold"])

(defun jetpacs-clip-test--client (&optional builtins)
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-clip-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-clip-test--app-types
                  :builtins ,(or builtins
                                 ["view.switch" "companion.settings.open"
                                  "clipboard.copy" "share.send"
                                  "trigger.fire"])
                  :features [])))
    client))

(defmacro jetpacs-clip-test--attached (client-form &rest body)
  (declare (indent 1))
  `(let ((client ,client-form))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-test-reset-state)
       (when (timerp jetpacs-clip--refresh-timer)
         (cancel-timer jetpacs-clip--refresh-timer)
         (setq jetpacs-clip--refresh-timer nil)))))

(defun jetpacs-clip-test--collect (node key)
  "Every value of KEY in the plist tree NODE."
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

;;;; The B13 predicate

(ert-deftest jetpacs-clip-builtin-advertised-p-offline ()
  (should (jetpacs-builtin-advertised-p "clipboard.copy")))

(ert-deftest jetpacs-clip-builtin-advertised-p-live ()
  (jetpacs-clip-test--attached (jetpacs-clip-test--client)
    ;; The [...] literals are VECTORS — this is the coercion witness.
    (should (jetpacs-builtin-advertised-p "clipboard.copy"))
    (should (jetpacs-builtin-advertised-p "share.send")))
  (jetpacs-clip-test--attached (jetpacs-clip-test--client [])
    (should-not (jetpacs-builtin-advertised-p "clipboard.copy"))))

;;;; Pure shaping

(ert-deftest jetpacs-clip-truncate-bytes-ascii ()
  (pcase-let ((`(,text . ,truncp)
               (jetpacs-clip--truncate-bytes (make-string 5000 ?a) 4096)))
    (should (= (length text) 4096))
    (should (= (string-bytes text) 4096))
    (should truncp))
  (pcase-let ((`(,text . ,truncp)
               (jetpacs-clip--truncate-bytes (make-string 10 ?a) 4096)))
    (should (= (length text) 10))
    (should-not truncp)))

(ert-deftest jetpacs-clip-truncate-bytes-multibyte-boundary ()
  (pcase-let ((`(,text . ,truncp)
               (jetpacs-clip--truncate-bytes (make-string 2000 ?€) 4096)))
    (should truncp)
    ;; 1365 chars x 3 bytes = 4095: max fit with no char split.
    (should (= (string-bytes text) 4095))
    (should (cl-every (lambda (c) (eq c ?€)) (string-to-list text)))))

(ert-deftest jetpacs-clip-preview-flattens ()
  (should (equal (jetpacs-clip--preview "line1\nline2\tend") "line1 line2 end"))
  (let ((p (jetpacs-clip--preview (make-string 300 ?a))))
    (should (= (length p) 121))
    (should (string-suffix-p "…" p)))
  (should (equal (jetpacs-clip--preview "  \n\t ") "(whitespace)")))

;;;; Cards

(ert-deftest jetpacs-clip-card-sanitizes-raw-bytes ()
  (dolist (bad (list (concat "ab" (string #x3FFFFF) "cd")
                     (concat "x" (string #xD800) "y")))
    (let ((card (jetpacs-clip--entry-card bad t)))
      ;; Serializes without signalling (the raw byte would have made
      ;; json-serialize throw wrong-type-argument)...
      (should (stringp (jetpacs-node->canonical-json card)))
      ;; ...and the descriptor text carries the replacement char.
      (let ((desc (car (delq nil (jetpacs-clip-test--collect card :on_tap)))))
        (should (string-match-p "�" (plist-get desc :text)))))))

(ert-deftest jetpacs-clip-card-descriptor-shape ()
  (let ((card (jetpacs-clip--entry-card "one\ntwo" t)))
    (let ((descs (jetpacs-clip-test--collect card :on_tap)))
      (should (equal (car (delq nil descs))
                     '(:builtin "clipboard.copy" :text "one\ntwo"))))
    ;; The preview flattened; the payload kept its newline.
    (let ((texts (jetpacs-clip-test--collect card :text)))
      (should (member "one two" texts)))))

;;;; The view against live gates

(ert-deftest jetpacs-clip-view-passes-live-gates ()
  (jetpacs-clip-test--attached (jetpacs-clip-test--client)
    (let* ((kill-ring '("alpha" "beta"))
           (view (jetpacs-clip--view)))
      (should (equal (plist-get view :t) "scaffold"))
      (should (equal (plist-get (plist-get view :on_refresh) :action)
                     "clip.refresh"))
      (jetpacs-check-profile view 'app)
      ;; GATE 1b over the Companion's real advertisement: no signal.
      (jetpacs-shell--check-builtins
       view '("view.switch" "companion.settings.open" "clipboard.copy"
              "share.send" "trigger.fire")
       "app"))))

(ert-deftest jetpacs-clip-view-degrades-unadvertised ()
  (jetpacs-clip-test--attached (jetpacs-clip-test--client [])
    (let* ((kill-ring '("alpha"))
           (view (jetpacs-clip--view)))
      ;; No builtin anywhere — the pre-check averts the GATE 1b signal.
      (should-not (delq nil (jetpacs-clip-test--collect view :builtin)))
      (jetpacs-shell--check-builtins view '() "app")
      ;; The preview row is selectable as the fallback.
      (should (memq t (jetpacs-clip-test--collect view :selectable))))))

(ert-deftest jetpacs-clip-empty-and-count-caps ()
  (let ((kill-ring nil))
    (should (equal (plist-get (plist-get (jetpacs-clip--view) :body) :t)
                   "empty_state")))
  (let ((kill-ring (cl-loop for i below 40 collect (format "k-%02d" i)))
        (jetpacs-clip-max-entries 30))
    (let ((body (plist-get (jetpacs-clip--view) :body)))
      (should (= (length (plist-get body :children)) 31))
      (should (equal (plist-get (aref (plist-get body :children) 0) :text)
                     "30 of 40 kills, newest first")))))

;;;; Refresh: D1 + D2 through the real dispatch

(ert-deftest jetpacs-clip-refresh-carries-surface ()
  (jetpacs-clip-test--attached (jetpacs-clip-test--client)
    (let ((pushed '()))
      (cl-letf (((symbol-function 'jetpacs-shell-push)
                 (lambda (surface &rest _) (push surface pushed) 1)))
        (let ((status (jetpacs--dispatch
                       client '(:action "clip.refresh" :surface "app:clip")
                       (gethash "clip.refresh" jetpacs-action-handlers))))
          (should (eq status 'accepted))
          ;; D2: nothing pushed inside the extent.
          (should (null pushed)))
        (cl-loop repeat 10 do (accept-process-output nil 0.05))
        (should (equal pushed '("app:clip")))
        ;; The originating surface wins, not the owner's.
        (jetpacs--dispatch client '(:action "clip.refresh"
                                    :surface "app:other")
                           (gethash "clip.refresh" jetpacs-action-handlers))
        (cl-loop repeat 10 do (accept-process-output nil 0.05))
        (should (equal (car pushed) "app:other"))))))

(ert-deftest jetpacs-clip-kill-advice-gating ()
  (let ((scheduled 0))
    (cl-letf (((symbol-function 'jetpacs-clip--schedule-refresh)
               (lambda () (cl-incf scheduled))))
      ;; Detached: invisible.
      (let ((kill-ring nil) (kill-ring-yank-pointer nil))
        (kill-new "x")
        (should (= scheduled 0)))
      (jetpacs-clip-test--attached (jetpacs-clip-test--client)
        (let ((kill-ring nil) (kill-ring-yank-pointer nil))
          (let ((jetpacs-clip-auto-refresh nil))
            (kill-new "y")
            (should (= scheduled 0)))
          (kill-new "z")
          (should (= scheduled 1)))))))

;;;; The golden

(defconst jetpacs-clip-test--golden
  (expand-file-name "goldens/clip-view.golden"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "The byte-asserted view golden.")

(defun jetpacs-clip-test--golden-file ()
  jetpacs-clip-test--golden)

(defun jetpacs-clip-test--write-golden ()
  "Regenerate the golden from the current builder."
  (let ((kill-ring '("alpha" "beta\ngamma")))
    (with-temp-file (jetpacs-clip-test--golden-file)
      (insert (jetpacs-node->canonical-json (jetpacs-clip--view)) "\n"))))

(ert-deftest jetpacs-clip-golden ()
  "Offline render over a fixed ring byte-matches the checked-in golden."
  (let ((kill-ring '("alpha" "beta\ngamma")))
    (should (string= (concat (jetpacs-node->canonical-json
                              (jetpacs-clip--view))
                             "\n")
                     (with-temp-buffer
                       (insert-file-contents
                        (jetpacs-clip-test--golden-file))
                       (buffer-string))))))

(provide 'jetpacs-clip-test)
;;; jetpacs-clip-test.el ends here
