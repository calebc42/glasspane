;;; jetpacs-devtools-test.el --- Devtools exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The devtools gate: the flight recorder keeps the full failure story
;; (condition, backtrace, screen) that SPEC 23.3 scrubs off the wire —
;; and the wire stays scrubbed, asserted here against the pushed spec
;; itself.  The profiler half is v1 parity: build wall clock, last
;; spec, push sizes, the storm predicate.  Recording defaults OFF — the
;; §23.3 "explicit developer setting" floor is itself under test.

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
(require 'jetpacs-devtools)

(defconst jetpacs-devtools-test--types
  ["text" "row" "column" "box" "spacer" "divider" "button" "text_input"
   "card" "icon" "icon_button" "lazy_column" "scaffold"])

(defun jetpacs-devtools-test--client ()
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-devtools-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-profiles client)
          `(:app (:node_types ,jetpacs-devtools-test--types
                  :builtins ["view.switch"] :features []))
          (ebp-client-limits client) '(:max_frame_bytes 4194304))
    client))

(defmacro jetpacs-devtools-test--with (client-form &rest body)
  (declare (indent 1))
  `(let ((client ,client-form))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-test-reset-state)
       (clrhash jetpacs-chrome--stacks))))

(defmacro jetpacs-devtools-test--recording (records &rest body)
  (declare (indent 1))
  `(let ((,records nil))
     (cl-letf (((symbol-function 'ebp-client-surface-update)
                (cl-function
                 (lambda (_c surface spec &rest keys)
                   (push (list surface spec keys) ,records)
                   42))))
       ,@body)))

(defun jetpacs-devtools-test--define-root (owner)
  (with-jetpacs-owner owner
    (jetpacs-chrome-define-root
     owner "home"
     (lambda (_back) (jetpacs-chrome-screen "Hub" (jetpacs-text "h"))))))

;;;; The §23.3 floor

(ert-deftest jetpacs-devtools-recording-defaults-off ()
  "The recorder is the SPEC 23.3 explicit developer setting: off unless asked."
  (should-not (default-value 'jetpacs-devtools-recording)))

;;;; The flight recorder

(ert-deftest jetpacs-devtools-screen-failure-recorded-and-wire-scrubbed ()
  (jetpacs-devtools-test--with (jetpacs-devtools-test--client)
    (jetpacs-devtools-test--recording recs
      (let ((jetpacs-devtools-recording t))
        (jetpacs-devtools-test--define-root "devt")
        (jetpacs-chrome-push-screen
         "devt" "boom" (lambda (_back) (error "boom: %s" "the-datum")))
        ;; The push survived — the screen degraded, the surface shipped.
        (should recs)
        ;; The record kept the whole story.
        (let ((rec (car jetpacs-devtools--records)))
          (should rec)
          (should (equal (plist-get rec :surface) "app:devt"))
          (should (equal (plist-get rec :screen) "boom"))
          (should (eq (plist-get rec :symbol) 'error))
          (should (string-match-p "the-datum" (plist-get rec :message)))
          (should (> (length (plist-get rec :backtrace)) 0)))
        ;; The wire kept nothing: the datum never reaches the spec, the
        ;; scrubbed card does.
        (let ((json (jetpacs-node->canonical-json (nth 1 (car recs)))))
          (should (string-match-p "failed to build" json))
          (should-not (string-match-p "the-datum" json)))))))

(ert-deftest jetpacs-devtools-shell-degrade-ships-the-label-only ()
  "The whole-surface degrade spec is wire-bound and Companion-persisted:
it carries the error SYMBOL, never the datum (SPEC 23.3)."
  (let* ((spec (jetpacs-shell--build
                "app:x"
                (list :builder (lambda () (error "leak: %s" "sms-body")))))
         (json (jetpacs-node->canonical-json spec)))
    (should (string-match-p "Error building" json))
    (should (string-match-p "error" json))
    (should-not (string-match-p "sms-body" json))))

(ert-deftest jetpacs-devtools-recorder-off-keeps-nothing ()
  (jetpacs-devtools-test--with (jetpacs-devtools-test--client)
    (jetpacs-devtools-test--recording recs
      ;; Default-off: same crash, zero retention.
      (jetpacs-devtools-test--define-root "devt")
      (jetpacs-chrome-push-screen
       "devt" "boom" (lambda (_back) (error "boom: %s" "the-datum")))
      (should recs)
      (should-not jetpacs-devtools--records))))

(ert-deftest jetpacs-devtools-gate-failure-recorded ()
  (jetpacs-devtools-test--with (jetpacs-devtools-test--client)
    (jetpacs-devtools-test--recording recs
      (let ((jetpacs-devtools-recording t))
        ;; An unadvertised node type: the gate signals out of the push
        ;; (the sender MUSTs stay loud), and the recorder saw it first.
        (should-error (jetpacs-shell-push "app:devt"
                                          :spec (list :t "video")))
        (let ((rec (car jetpacs-devtools--records)))
          (should rec)
          (should (equal (plist-get rec :surface) "app:devt"))
          (should (eq (plist-get rec :phase) 'gate)))))))

(ert-deftest jetpacs-devtools-record-limit-and-ttl-bound ()
  (let ((jetpacs-devtools-recording t)
        (jetpacs-devtools-record-limit 5)
        (jetpacs-devtools--records nil))
    (dotimes (i 8)
      (jetpacs-devtools--record-failure
       (list :surface (format "s%d" i)) '(error "x")))
    ;; Size bound: only the newest five survive.
    (should (= 5 (length jetpacs-devtools--records)))
    (should (equal "s7" (plist-get (car jetpacs-devtools--records) :surface)))
    ;; Lifetime bound: an entry past the TTL is dropped on the next record.
    (let ((jetpacs-devtools-record-ttl 60))
      (push (list :at (- (float-time) 61) :surface "stale")
            jetpacs-devtools--records)
      (jetpacs-devtools--record-failure '(:surface "fresh") '(error "y"))
      (should-not (seq-find (lambda (r) (equal (plist-get r :surface) "stale"))
                            jetpacs-devtools--records)))))

(ert-deftest jetpacs-devtools-toggle-off-clears ()
  (let ((jetpacs-devtools-recording nil)
        (jetpacs-devtools--records nil))
    (jetpacs-devtools-toggle-recording)
    (should jetpacs-devtools-recording)
    (jetpacs-devtools--record-failure '(:surface "s") '(error "x"))
    (should jetpacs-devtools--records)
    ;; Off ends the retention the setting authorized.
    (jetpacs-devtools-toggle-recording)
    (should-not jetpacs-devtools-recording)
    (should-not jetpacs-devtools--records)))

;;;; The profiler

(ert-deftest jetpacs-devtools-profiler-times-and-keeps-spec ()
  (jetpacs-devtools-test--with (jetpacs-devtools-test--client)
    (jetpacs-devtools-test--recording recs
      (jetpacs-devtools-test--define-root "devt")
      ;; Defining only registers; the build the profiler times happens
      ;; on a push.
      (jetpacs-chrome-push-screen
       "devt" "detail"
       (lambda (back) (jetpacs-chrome-screen "Detail" (jetpacs-text "d")
                                             :back back)))
      (should recs)
      (let ((rec (gethash "app:devt" jetpacs-devtools--builds)))
        (should rec)
        (should (>= (plist-get rec :count) 1))
        (should (numberp (plist-get rec :last-ms))))
      (should (jetpacs-devtools-last-spec "app:devt")))))

(ert-deftest jetpacs-devtools-note-push-tallies-and-sizes ()
  (let ((jetpacs-devtools--pushes (make-hash-table :test 'equal))
        (jetpacs-devtools--push-times nil))
    (jetpacs-devtools--note-push "app:x" (jetpacs-text "hello"))
    (jetpacs-devtools--note-push "app:x" (jetpacs-text "hello again"))
    (let ((rec (gethash "app:x" jetpacs-devtools--pushes)))
      (should (= 2 (plist-get rec :count)))
      (should (natnump (plist-get rec :last-bytes)))
      (should (> (plist-get rec :last-bytes) 0)))
    (should (= 2 (length jetpacs-devtools--push-times)))))

(ert-deftest jetpacs-devtools-storm-p ()
  (let ((now 100.0))
    ;; Eight inside the window trips it…
    (should (jetpacs-devtools--storm-p
             (mapcar (lambda (i) (- now i)) '(0 1 2 3 4 5 6 7)) now 8 10))
    ;; …seven inside plus one outside does not.
    (should-not (jetpacs-devtools--storm-p
                 (mapcar (lambda (i) (- now i)) '(0 1 2 3 4 5 6 20)) now 8 10))))

;;;; The report

(ert-deftest jetpacs-devtools-report-renders ()
  (let ((jetpacs-devtools-recording t)
        (jetpacs-devtools--records nil))
    ;; A message that LOOKS like a format control must render inert
    ;; (SPEC 23.2: peer/error text is an argument, never a template).
    (jetpacs-devtools--record-failure '(:surface "s")
                                      '(error "100%s of the time"))
    (with-current-buffer (jetpacs-devtools-report-buffer)
      (should (string-match-p "100%s of the time"
                              (buffer-substring-no-properties
                               (point-min) (point-max)))))))

(provide 'jetpacs-devtools-test)
;;; jetpacs-devtools-test.el ends here
