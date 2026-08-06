;;; jetpacs-org-test.el --- The org adapter's registration -*- lexical-binding: t; -*-

;;; Commentary:

;; The adapter's gate (docs/PLAN-ebp-org-split.md, G8).  After the
;; split, `jetpacs-org.el' exports no callable symbol: it is an
;; ADAPTER, and what it does happens at load time.  So there is nothing
;; here to call and check — every test below asserts an EFFECT, because
;; all three of the adapter's jobs fail silently when they break.
;;
;; 1. The registration.  `ebp-org-teardown-owner' is the engine's, the
;;    hook is the floor's, and the `add-hook' joining them is the whole
;;    of this file.  The engine suite exercises the sweep by calling it
;;    directly, which stays green with the `add-hook' deleted — until
;;    now nothing anywhere noticed if the adapter stopped adapting.  So
;;    the first test calls only the floor's own `jetpacs-teardown-owner'
;;    and looks for the token afterwards.
;; 2. The reset bridge.  `jetpacs-test-reset-state' reaches the engine
;;    through an `fboundp' probe, and a probe that finds nothing does
;;    not complain — resets simply stop happening.  Asserted positively.
;; 3. The require chain.  The plan expected `jetpacs-org-render' to lose
;;    transitive registration; it survives, one hop longer.  Pinned, in
;;    the membership and in the source links that produce it.
;;
;; Harness: no client, no wire.  A token minted for a synthetic owner is
;; the whole of the engine state this needs, and the ref carries a nil
;; `:file' so the mint's resolve policy has nothing to say about paths —
;; those belong to the engine suite.

;;; Code:

(require 'ert)
(require 'jetpacs-org)                  ; the SHIM, deliberately: the
                                        ; subject here is its load effect
(require 'jetpacs-shell)                ; `jetpacs-teardown-owner' — the
                                        ; floor entry the hook hangs off

(defconst jetpacs-org-test--owner "g8adapter"
  "A synthetic scope key.
Opaque to the engine (which never resolves an owner) and a valid D1
owner to the floor (which validates one before it sweeps).")

(defmacro jetpacs-org-test--with-token (var &rest body)
  "Mint one token for the synthetic owner, bind it to VAR, run BODY.
The nearby suites' fixture shape — set up, `unwind-protect', reset on
the way out — minus the client none of these tests need.  The mint is
asserted live before BODY so a test that finds the token gone has
actually observed a sweep."
  (declare (indent 1))
  `(unwind-protect
       (let ((,var (car (ebp-org-ref-tokens
                         (list (list :id nil :file nil :pos 1
                                     :headline "Synthetic"))
                         :set "g8" :owner jetpacs-org-test--owner))))
         (should (ebp-org-token-ref ,var :owner jetpacs-org-test--owner))
         ,@body)
     (ebp-org-reset)))

(ert-deftest jetpacs-org-teardown-registration-sweeps-end-to-end ()
  "The floor's teardown verb reaches the engine's sweep.
Nothing in this test names `ebp-org-teardown-owner': the owner goes to
`jetpacs-teardown-owner', the floor runs its hook, and the token is
gone on the other side.  That path crosses the `add-hook' in
`jetpacs-org.el' and crosses nothing else, so this is the one
assertion the registration cannot be deleted under."
  (jetpacs-org-test--with-token tok
    (jetpacs-teardown-owner jetpacs-org-test--owner)
    (should-not (ebp-org-token-ref tok :owner jetpacs-org-test--owner))))

(ert-deftest jetpacs-org-reset-bridge-reaches-the-engine ()
  "The floor's `fboundp' probe finds `ebp-org-reset', proved by effect.
`jetpacs-test-reset-state' does not require the engine — it asks
whether the function exists and skips it if not, so the NAME is
load-bearing in the silent direction: rename it without editing the
probe and every fixture in the tree quietly stops resetting engine
state between tests.  A membership check would not catch that; the
cleared table does."
  (jetpacs-org-test--with-token tok
    (jetpacs-test-reset-state)
    (should-not (ebp-org-token-ref tok :owner jetpacs-org-test--owner))))

(ert-deftest jetpacs-org-render-still-carries-the-registration ()
  "Requiring the render skin still installs the teardown sweep.
TWO paths arrive at the same hook and both are pinned here.  The
direct one is this suite's own `(require \\='jetpacs-org)'.  The
transitive one is the property the plan cared about: it predicted that
after the split `jetpacs-org-render' would no longer drag the
registration in, since render requires only the engine — but it does,
one hop longer, render -> jetpacs-org-dialogs -> jetpacs-org.  The
membership alone cannot tell the two apart in a process that has
loaded the shim itself, so the source links are checked too (the
outline suite's scan idiom): drop either require and the device's
render-only load path loses its sweep with nothing to say so."
  (require 'jetpacs-org-render)
  (should (memq #'ebp-org-teardown-owner jetpacs-teardown-functions))
  (let ((dir (file-name-directory (locate-library "jetpacs-org.el" t))))
    (dolist (link '(("jetpacs-org-render.el" . "(require 'jetpacs-org-dialogs)")
                    ("jetpacs-org-dialogs.el" . "(require 'jetpacs-org)")))
      (with-temp-buffer
        (insert-file-contents (expand-file-name (car link) dir))
        (goto-char (point-min))
        (should (search-forward (cdr link) nil t))))))

(ert-deftest jetpacs-org-unload-takes-back-only-the-registration ()
  "The adapter's other half: it removes what it added, and only that.
The engine's tables are `ebp-org-unload-function''s business, so the
sweep function is still defined afterwards — this file never owned it."
  (unwind-protect
      (progn
        (jetpacs-org-unload-function)
        (should-not (memq #'ebp-org-teardown-owner jetpacs-teardown-functions))
        (should (fboundp 'ebp-org-teardown-owner)))
    (add-hook 'jetpacs-teardown-functions #'ebp-org-teardown-owner)))

(provide 'jetpacs-org-test)
;;; jetpacs-org-test.el ends here
