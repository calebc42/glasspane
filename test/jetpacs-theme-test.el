;;; jetpacs-theme-test.el --- JA-1 theme + modus exit gate -*- lexical-binding: t; -*-

;;; Commentary:

;; The JA-1 theme half of the exit gate (docs/PLAN-jetpacs-apps.md).
;; The color plumbing runs pure; the modus tests load a REAL modus theme
;; in batch (the palette path is display-free — that asymmetry is itself
;; part of the design); the send tests capture at `ebp-client-notify';
;; and the modus toggle is driven through ebp's REAL
;; `ebp-client--handle-event-action', so the 14.4 status contract and
;; the D2 no-prompt property are the live ones.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-async)
(require 'jetpacs-surfaces)
(require 'jetpacs-theme)

(defun jetpacs-theme-test--client (&optional granted)
  (let ((client (ebp-client-create
                 :receipt-file (make-temp-file "jetpacs-theme-receipts"))))
    (setf (ebp-client-state client) 'ready
          (ebp-client-granted client) (or granted ["theme"]))
    client))

(defmacro jetpacs-theme-test--with-modus (theme &rest body)
  "Enable modus THEME for BODY; always disable and cancel the debounce."
  (declare (indent 1))
  `(progn
     (require-theme 'modus-themes)
     (load-theme ,theme t)
     (unwind-protect (progn ,@body)
       (disable-theme ,theme)
       (when (timerp jetpacs-theme--timer)
         (cancel-timer jetpacs-theme--timer)
         (setq jetpacs-theme--timer nil)))))

(defmacro jetpacs-theme-test--attached (client-form &rest body)
  "Attach CLIENT-FORM for BODY; always detach, reset, cancel the debounce."
  (declare (indent 1))
  `(let ((client ,client-form))
     (unwind-protect
         (progn (jetpacs-attach client) ,@body)
       (jetpacs-detach)
       (jetpacs-test-reset-state)
       (when (timerp jetpacs-theme--timer)
         (cancel-timer jetpacs-theme--timer)
         (setq jetpacs-theme--timer nil)))))

;;;; Color plumbing (pure — provably tty-exact because this suite IS batch)

(ert-deftest jetpacs-theme/hex-parse-is-tty-exact ()
  (should (equal (jetpacs-theme--hex "#2e3440") "#2e3440"))
  (should (equal (jetpacs-theme--hex "#abc") "#aabbcc"))
  (should (equal (jetpacs-theme--hex "#aaaabbbbcccc") "#aabbcc"))
  (should-not (jetpacs-theme--rgb "unspecified-bg"))
  (should-not (jetpacs-theme--rgb 'unspecified))
  (should-not (jetpacs-theme--hex "no-such-color-xyzzy")))

(ert-deftest jetpacs-theme/blend-and-dark-p ()
  (should (equal (jetpacs-theme--blend "#000000" "#ffffff" 0.5) "#808080"))
  (should (equal (jetpacs-theme--blend "#ff0000" "#0000ff" 1.0) "#ff0000"))
  (should (jetpacs-theme--dark-p "#2e3440"))
  (should-not (jetpacs-theme--dark-p "#fafafa"))
  (should-not (jetpacs-theme--blend "#123456" "unspecified-fg" 0.5)))

(ert-deftest jetpacs-theme/face-color-resolves-and-inherits ()
  (defface jetpacs-theme-test--a '((t :foreground "#112233")) "Test face.")
  (defface jetpacs-theme-test--b '((t :inherit jetpacs-theme-test--a))
    "Test face inheriting a.")
  (should (equal (jetpacs-theme--face-color
                  :foreground 'jetpacs-theme-test--b)
                 "#112233"))
  ;; An undefined face first in FACES falls through (the facep guard).
  (should (equal (jetpacs-theme--face-color
                  :foreground 'jetpacs-theme-test--undefined
                  'jetpacs-theme-test--a)
                 "#112233"))
  (should-not (jetpacs-theme--face-color
               :foreground 'jetpacs-theme-test--undefined)))

;;;; Modus extraction against a real loaded theme

(ert-deftest jetpacs-theme/modus-colors-are-contract-roles ()
  "Every emitted color key is a contract theme role; success/warning
present; primary and error match the palette's own answers — computed
expectations, so a modus version bump cannot silently break the suite."
  (jetpacs-theme-test--with-modus 'modus-operandi
    (let ((colors (jetpacs-theme--colors)))
      (should colors)
      (cl-loop for (k _v) on colors by #'cddr
               do (should (member (substring (symbol-name k) 1)
                                  jetpacs-theme-roles)))
      (should (plist-get colors :success))
      (should (plist-get colors :warning))
      (should (equal (plist-get colors :primary)
                     (jetpacs-theme--hex
                      (modus-themes-get-color-value 'accent-0
                                                    :with-overrides))))
      (should (equal (plist-get colors :error)
                     (jetpacs-theme--hex
                      (modus-themes-get-color-value 'err
                                                    :with-overrides)))))))

(ert-deftest jetpacs-theme/modus-syntax-styles-are-objects ()
  "Syntax values are SyntaxStyle plists — never vectors; :meta duplicates
:preprocessor; :paren is not emitted; keys (minus :meta) are contract
syntax roles."
  (jetpacs-theme-test--with-modus 'modus-operandi
    (let ((syn (jetpacs-theme--syntax)))
      (should syn)
      (cl-loop for (k v) on syn by #'cddr do
               (should (consp v))
               (should (string-match-p "\\`#[0-9a-f]\\{6\\}\\'"
                                       (plist-get v :fg)))
               (unless (eq k :meta)
                 (should (member (substring (symbol-name k) 1)
                                 jetpacs-syntax-roles))))
      (should (equal (plist-get syn :meta) (plist-get syn :preprocessor)))
      (should (consp (plist-get syn :heading)))
      (should-not (vectorp (plist-get syn :heading)))
      (should-not (plist-member syn :paren)))))

(ert-deftest jetpacs-theme/payload-forces-polarity ()
  (jetpacs-theme-test--with-modus 'modus-vivendi
    (should (eq (plist-get (jetpacs-theme-payload) :dark) t)))
  (jetpacs-theme-test--with-modus 'modus-operandi
    (should (eq (plist-get (jetpacs-theme-payload) :dark) :false))))

(ert-deftest jetpacs-theme/modus-queries-are-version-adaptive ()
  (jetpacs-theme-test--with-modus 'modus-operandi
    (should (jetpacs-modus-available-p))
    (should (memq 'modus-operandi (jetpacs-modus-themes)))
    (should (eq (jetpacs-modus-current) 'modus-operandi))
    (should-not (jetpacs-modus-dark-p 'modus-operandi))
    (should (jetpacs-modus-dark-p 'modus-vivendi))))

;;;; The mode matrix

(ert-deftest jetpacs-theme/frame-args-mode-matrix ()
  (let ((jetpacs-theme-mode 'system))
    (let ((args (jetpacs-theme--frame-args)))
      (should (equal args '(:colors null :syntax null)))
      (should-not (plist-member args :dark))))
  (let ((jetpacs-theme-mode 'light))
    (should (eq (plist-get (jetpacs-theme--frame-args) :dark) :false)))
  (let ((jetpacs-theme-mode 'dark))
    (should (eq (plist-get (jetpacs-theme--frame-args) :dark) t)))
  (jetpacs-theme-test--with-modus 'modus-operandi
    (let ((jetpacs-theme-mode 'mirror))
      (should (equal (jetpacs-theme--frame-args) (jetpacs-theme-payload)))))
  ;; Mirror on a colorless frame yields nil — the caller must not push.
  (cl-letf (((symbol-function 'jetpacs-theme--colors) (lambda () nil)))
    (let ((jetpacs-theme-mode 'mirror))
      (should-not (jetpacs-theme--frame-args)))))

;;;; Sends through the real seam

(ert-deftest jetpacs-theme/send-goes-through-theme-set ()
  (jetpacs-theme-test--with-modus 'modus-operandi
    (jetpacs-theme-test--attached (jetpacs-theme-test--client)
      (let ((sent '()))
        (cl-letf (((symbol-function 'ebp-client-notify)
                   (lambda (_c method params) (push (cons method params) sent))))
          (let ((jetpacs-theme-mode 'mirror))
            (jetpacs-theme-send))
          (should (= (length sent) 1))
          (should (eq (caar sent) 'theme.set))
          (let ((params (cdar sent)))
            (should (plist-member params :dark))
            (should (string-match-p
                     "\\`#" (plist-get (plist-get params :colors) :primary)))
            (should (consp (plist-get params :syntax))))
          ;; Clear: colors/syntax normalized to JSON null, no :dark.
          (jetpacs-theme-clear)
          (should (= (length sent) 2))
          (should (equal (cdar sent) '(:colors nil :syntax nil))))))))

(ert-deftest jetpacs-theme/no-send-when-ungranted-or-disconnected ()
  (jetpacs-theme-test--with-modus 'modus-operandi
    ;; Granted [] — send declines, push-mode schedules nothing.
    (jetpacs-theme-test--attached (jetpacs-theme-test--client [])
      (let ((sent 0))
        (cl-letf (((symbol-function 'ebp-client-notify)
                   (lambda (&rest _) (cl-incf sent))))
          (jetpacs-theme-send)
          (jetpacs-theme--push-mode)
          (should (= sent 0))
          (should-not jetpacs-theme--timer))))
    ;; Detached — same.
    (let ((sent 0))
      (cl-letf (((symbol-function 'ebp-client-notify)
                 (lambda (&rest _) (cl-incf sent))))
        (jetpacs-theme-send)
        (jetpacs-theme--push-mode)
        (should (= sent 0))
        (should-not jetpacs-theme--timer)))))

(ert-deftest jetpacs-theme/debounce-collapses-bursts ()
  (jetpacs-theme-test--with-modus 'modus-operandi
    (jetpacs-theme-test--attached (jetpacs-theme-test--client)
      (let ((sent 0)
            (jetpacs-theme-mode 'mirror))
        (cl-letf (((symbol-function 'ebp-client-notify)
                   (lambda (&rest _) (cl-incf sent))))
          (jetpacs-theme--on-theme-change)
          (jetpacs-theme--on-theme-change)
          (jetpacs-theme--on-theme-change)
          (should (timerp jetpacs-theme--timer))
          (let ((deadline (+ (float-time) 2)))
            (while (and jetpacs-theme--timer (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (should (= sent 1)))
        ;; Non-mirror modes schedule nothing from a theme change.
        (let ((jetpacs-theme-mode 'system))
          (jetpacs-theme--on-theme-change)
          (should-not jetpacs-theme--timer))))))

;;;; jetpacs.theme.modus-toggle through the real dispatch

(ert-deftest jetpacs-theme/modus-toggle-real-dispatch ()
  (jetpacs-theme-test--with-modus 'modus-operandi
    (jetpacs-theme-test--attached (jetpacs-theme-test--client)
      ;; jetpacs-attach replayed the load-time registration.
      (should (gethash "jetpacs.theme.modus-toggle" (ebp-client-actions client)))
      (unwind-protect
          (let ((modus-themes-to-toggle '(modus-operandi modus-vivendi)))
            (let ((result (ebp-client--handle-event-action
                           client
                           (list :event_id (make-string 32 ?a)
                                 :action "jetpacs.theme.modus-toggle"
                                 :occurred_at_ms 1784700000000))))
              (should (equal (plist-get result :status) "accepted"))
              (should (eq (jetpacs-modus-current) 'modus-vivendi))))
        (disable-theme 'modus-vivendi)))))

(ert-deftest jetpacs-theme/modus-toggle-rejects-cleanly ()
  "A toggle set that is not exactly two themes is REFUSED by the
pre-check — the completing-read fallback must never be reached, so the
refusal is a clean rejected, not a no-prompts warning."
  (jetpacs-theme-test--with-modus 'modus-operandi
    (jetpacs-theme-test--attached (jetpacs-theme-test--client)
      (let ((prompted 0))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) (cl-incf prompted) "modus-vivendi")))
          (let ((modus-themes-to-toggle '(modus-operandi)))
            (let ((result (ebp-client--handle-event-action
                           client
                           (list :event_id (make-string 32 ?b)
                                 :action "jetpacs.theme.modus-toggle"
                                 :occurred_at_ms 1784700000000))))
              (should (equal (plist-get result :status) "rejected"))
              (should (= prompted 0)))))))))

;;;; granted-p (B1) and the promoted sanitizer

(ert-deftest jetpacs-theme/granted-p-vector-membership ()
  (let ((client (jetpacs-theme-test--client ["theme" "editor.sync"])))
    ;; Explicit-client form works unattached — the gate-conversion shape.
    (should (jetpacs-granted-p "theme" client))
    (should-not (jetpacs-granted-p "triggers" client))
    (jetpacs-theme-test--attached client
      (should (jetpacs-granted-p "theme"))
      (should-not (jetpacs-granted-p "triggers"))))
  ;; No client anywhere: fail closed.
  (should-not (jetpacs-granted-p "theme")))

(ert-deftest jetpacs-theme/scalar-text-promoted ()
  (should (equal (jetpacs-scalar-text "plain") "plain"))
  (should (equal (jetpacs-scalar-text (string ?a #x3FFF80 ?b)) "a�b"))
  ;; The renderer-local name survives as an alias (defalias stores the
  ;; SYMBOL; resolve both through the indirection).
  (require 'jetpacs-buffer)
  (should (eq (indirect-function 'jetpacs-buffer-scalar-text)
              (indirect-function 'jetpacs-scalar-text))))

;;;; Faces-arm golden mapping (deterministic, stub-seamed at --face-color only)

(ert-deftest jetpacs-theme/faces-arm-golden-mapping ()
  (let ((table '((:background default "#101418")
                 (:foreground default "#e0e0e0")
                 (:foreground font-lock-keyword-face "#c080ff")
                 (:foreground font-lock-constant-face "#66d9ef")
                 (:foreground error "#ff5555")
                 (:foreground success "#50fa7b")
                 (:foreground warning "#f1fa8c")
                 (:foreground shadow "#888888"))))
    (cl-letf (((symbol-function 'jetpacs-theme--modus-p) (lambda () nil))
              ((symbol-function 'jetpacs-theme--face-color)
               (lambda (attr &rest faces)
                 (cl-loop for f in faces
                          for hit = (cl-find-if
                                     (lambda (row)
                                       (and (eq (nth 0 row) attr)
                                            (eq (nth 1 row) f)))
                                     table)
                          when hit return (nth 2 hit)))))
      (let ((colors (jetpacs-theme--colors)))
        (should (equal (plist-get colors :primary) "#c080ff"))
        (should (equal (plist-get colors :background) "#101418"))
        (should (equal (plist-get colors :error) "#ff5555"))
        (should (equal (plist-get colors :success) "#50fa7b"))
        (should (equal (plist-get colors :warning) "#f1fa8c"))
        (should (equal (plist-get colors :outline) "#888888"))
        ;; The container blend runs for real over the stubbed inputs.
        (should (equal (plist-get colors :primary_container)
                       (jetpacs-theme--blend "#c080ff" "#101418" 0.22)))
        (should (equal (plist-get colors :tertiary) "#66d9ef"))))))


;;;; E6: off, the payload seam, synchronous READY, and the wiring pins

(ert-deftest jetpacs-theme-off-emits-nothing ()
  "Mode `off': base NEVER touches theme.set — no frame, no clear.
Pre-fix, merely loading this file made the default mode clear a
Tier-1's persisted palette 0.2 s after every READY."
  (jetpacs-theme-test--attached (jetpacs-theme-test--client)
    (let ((sent 0)
          (jetpacs-theme-mode 'off))
      (cl-letf (((symbol-function 'ebp-client-theme-set)
                 (lambda (&rest _) (cl-incf sent))))
        (jetpacs-theme--send-now)
        (jetpacs-theme--push-mode)
        (should-not (timerp jetpacs-theme--timer))
        (jetpacs-theme--on-ready client)
        (should (= sent 0))))))

(ert-deftest jetpacs-theme-payload-function-wins ()
  "An explicit `jetpacs-theme-payload-function' beats the mode matrix —
base's machinery becomes the Tier-1's transport, not its competitor.
A nil return means nothing-to-push."
  (jetpacs-theme-test--attached (jetpacs-theme-test--client)
    (let ((captured nil)
          (jetpacs-theme-mode 'mirror)
          (jetpacs-theme-payload-function
           (lambda () '(:colors null :syntax null :dark t))))
      (cl-letf (((symbol-function 'ebp-client-theme-set)
                 (lambda (_c &rest args) (setq captured args))))
        (jetpacs-theme--send-now)
        (should (equal captured '(:colors null :syntax null :dark t)))
        (setq captured :unset
              jetpacs-theme-payload-function (lambda () nil))
        (jetpacs-theme--send-now)
        (should (eq captured :unset))))))

(ert-deftest jetpacs-theme-ready-sends-synchronously ()
  "The READY paint is NOT debounced: the debounce exists for
load-theme's disable+enable pair, and deferring the FIRST frame was a
0.2 s wrong-palette flash on every pairing."
  (jetpacs-theme-test--attached (jetpacs-theme-test--client)
    (let ((sent 0)
          (jetpacs-theme-mode 'system))
      (cl-letf (((symbol-function 'ebp-client-theme-set)
                 (lambda (&rest _) (cl-incf sent))))
        (jetpacs-theme--on-ready client)
        ;; Sent NOW — no timer armed, nothing pending.
        (should (= sent 1))
        (should-not (timerp jetpacs-theme--timer))))))

(ert-deftest jetpacs-theme-debounce-regate-blocks-a-changed-session ()
  "The inner re-gate: the timer body re-checks grant and connection,
because both can change in 0.2 s.  The audit measured this guard
replaceable by (when t ...) with every theme test green — this is the
missing witness."
  (jetpacs-theme-test--attached (jetpacs-theme-test--client)
    (let ((sent 0)
          (jetpacs-theme-mode 'system))
      (cl-letf (((symbol-function 'ebp-client-theme-set)
                 (lambda (&rest _) (cl-incf sent))))
        (jetpacs-theme--push-mode)
        (should (timerp jetpacs-theme--timer))
        ;; The session loses the grant before the timer fires.  Cancel
        ;; the REAL timer and drive its function by hand — funcalling
        ;; alone leaves the scheduled object queued, and it would fire
        ;; 0.2 s later inside a LATER test's drain loop (measured: it
        ;; polluted the burst test two tests down).
        (setf (ebp-client-granted client) ["editor.sync"])
        (let ((tm jetpacs-theme--timer))
          (cancel-timer tm)
          (funcall (timer--function tm)))
        (should (= sent 0))))))

(ert-deftest jetpacs-theme-wiring-is-pinned ()
  "The audit deleted BOTH load-time wirings with the suite green: the
enable/disable-theme hooks and the ready-hook install.  Pin all three."
  (should (memq #'jetpacs-theme--on-theme-change enable-theme-functions))
  (should (memq #'jetpacs-theme--on-theme-change disable-theme-functions))
  (let ((client (jetpacs-theme-test--client)))
    (jetpacs--install-ready-hooks client)
    (should (memq #'jetpacs-theme--on-ready
                  (ebp-client-ready-functions client)))))

(ert-deftest jetpacs-theme-modus-module-is-hook-free ()
  "`jetpacs-modus' is the JA-10 substrate: requiring it must observably
change NOTHING — a Tier-1 loads it for the queries, not the machinery."
  (let ((enable-theme-functions nil)
        (disable-theme-functions nil)
        (jetpacs-teardown-functions nil))
    (load "jetpacs-modus" nil t)   ; re-load from load-path, fresh
    (should-not enable-theme-functions)
    (should-not disable-theme-functions)
    (should-not jetpacs-teardown-functions)))

(provide 'jetpacs-theme-test)
;;; jetpacs-theme-test.el ends here
