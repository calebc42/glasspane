;;; jetpacs-m3-repl.el --- The Catalog Playground -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The catalog's third non-upstream section, after the identity header
;; and "View elisp".  Those two let you READ what a sample is; this one
;; lets you CHANGE it.
;;
;; Every Example screen grows a bottom sheet resting at a peek over the
;; sample.  Drag it up and it holds the sample's own authored elisp,
;; seeded into a synchronized editor with real `elisp-completion-at-point'
;; answering from Emacs, and a history of what you have evaluated.  Send
;; a form that returns a node and the SAMPLE ABOVE YOU RE-RENDERS as
;; that node.  Send anything else and its printed value lands in a card.
;;
;; WHY A SHEET AND NOT A SCREEN.  A fourth screen works — "View elisp"
;; is one, and `jetpacs-chrome--stack-insert' evicts from the middle to
;; make room.  But a REPL over a component has to keep the component ON
;; SCREEN while you change it; that is the whole difference between a
;; viewer and a loop.  The sheet is the only surface that does.
;;
;; THE SAMPLE STAYS THE SAMPLE.  An override is per example, keyed by
;; `jetpacs-m3-example-screen-id', so nothing you do here leaks into a
;; sibling — and it is discarded by the Reset row, which every panel
;; carries, because a catalog whose samples have quietly stopped being
;; upstream's samples is no longer a catalog.  Nothing is persisted:
;; reloading the module is a reset.
;;
;; THREE EXAMPLES CANNOT HAVE THE SHEET.  Bottom Sheet's own samples ARE
;; the sheet slot, and `jetpacs-scaffold' keeps the first of a duplicate
;; keyword silently.  So the core seam tells this module whether the
;; slot is free, and where it is not the panel rides an in-body
;; `collapsible' instead — which §17.3 keeps expanded across the
;; re-pushes the loop is made of, so it behaves the same way.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-repl)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-repl-peek-height 96
  "The peek height of the Playground sheet, in dp.
Enough to read the handle and the title and know it is there; small
enough that the sample it is about is not the thing it covers.")

(defvar jetpacs-m3-repl--overrides (make-hash-table :test #'equal)
  "Example screen id -> the node last evaluated for it.
The catalog's other live state — `jetpacs-m3--flags',
`jetpacs-m3-fn-registry' — is authored BY a sample.  This is authored by
the user, over a sample, and is the only state here that can make a
screen stop showing what upstream ships.  Hence per-example, hence
never persisted, hence a Reset on every panel.")

(defun jetpacs-m3-repl-session (id index)
  "The `jetpacs-repl' session id for component ID's example INDEX."
  (format "m3:%s/%d" id index))

(defun jetpacs-m3-repl-document (id index)
  "The synchronized document id for component ID's example INDEX.
Ends `.el' because `ebp-complete--mode-for' matches the document against
`auto-mode-alist' to choose the shadow buffer's major mode — that suffix
is what makes the elisp capfs answer.  Per example, so a half-typed
form cannot follow you into the next one."
  (format "m3-%s-%d.el" id index))

(defun jetpacs-m3-repl-editor-id (id index)
  "The editor node id for component ID's example INDEX."
  (format "%s-repl-%d" id index))

(defun jetpacs-m3-repl-override (id index)
  "The node last evaluated for component ID's example INDEX, or nil."
  (gethash (jetpacs-m3-example-screen-id id index)
           jetpacs-m3-repl--overrides))

;;;; The panel

(defun jetpacs-m3-repl--seed (component index)
  "COMPONENT's example INDEX authored elisp, as prompt seed text.
The sample's own defun, so the first thing the field holds is the thing
it is about — the difference between a REPL you can start using and an
empty box over a component whose vocabulary you do not know yet."
  (let* ((example (nth index (plist-get component :examples)))
         (builder (jetpacs-m3--example-builder example)))
    (or (and builder (jetpacs-m3--defun-text builder))
        (format ";; %s has no authored elisp to seed.\n"
                (plist-get example :name)))))

(defun jetpacs-m3-repl-panel (component index)
  "The Playground panel for COMPONENT's example INDEX."
  (let* ((id (plist-get component :id))
         (session (jetpacs-m3-repl-session id index))
         (overridden (jetpacs-m3-repl-override id index)))
    (jetpacs-column
     (jetpacs-row
      (jetpacs-with-attrs
       (jetpacs-text "Playground" :style "title") :weight 1)
      (jetpacs-icon-button
       "restart_alt"
       (jetpacs-action "m3catalog.repl.reset"
                       :args (list :component id :index index))
       :content-description "Reset the sample"
       :variant (and overridden "tonal"))
      :align "center" :fill t)
     (jetpacs-text
      (if overridden
          "Showing your node. Reset restores the upstream sample."
          "Edit the sample and send it. A node replaces what is above.")
      :style "caption")
     (jetpacs-divider)
     ;; ARGS is what makes the verb multi-session: the send button
     ;; dispatches with no value and reads the mirror, so this pair is
     ;; the only thing on that dispatch saying WHICH example it is for.
     ;; Without it every send was rejected in silence — found on
     ;; hardware, by a Playground whose button did nothing.
     (jetpacs-with-attrs
      (if-let* ((cards (jetpacs-repl-cards
                        session :verb "m3catalog.repl"
                        :args (list :component id :index index))))
          (apply #'jetpacs-lazy-column cards)
        (jetpacs-repl-empty-state))
      :weight 1)
     (jetpacs-repl-input-row
      :editor-id (jetpacs-m3-repl-editor-id id index)
      :document (jetpacs-m3-repl-document id index)
      :verb "m3catalog.repl"
      :args (list :component id :index index)
      :value (jetpacs-m3-repl--seed component index))
     :spacing 8 :fill t)))

(defun jetpacs-m3-repl-extras (component index sheet-free-p)
  "The Playground, as `jetpacs-m3-example-extras-function' answers it.
On the sheet when the slot is free; in an in-body `collapsible' when the
example's own sample IS the sheet, which §17.3 keeps expanded across the
re-pushes the loop is made of."
  (let* ((id (plist-get component :id))
         (panel (jetpacs-m3--guard "playground"
                                   (lambda () (jetpacs-m3-repl-panel
                                               component index))))
         (override (jetpacs-m3-repl-override id index)))
    (append
     (and override (list :override override))
     (if sheet-free-p
         (list :scaffold (list :sheet panel
                               :sheet-peek-height jetpacs-m3-repl-peek-height))
       (list :body
             (list (jetpacs-collapsible
                    (format "%s-playground-%d" id index)
                    (jetpacs-text "Playground" :style "title")
                    panel :collapsed t)))))))

;;;; The verbs

(defun jetpacs-m3-repl--on-eval (args params)
  "Evaluate the Playground's input for one example and re-render it.

Mirrors `hub.eval': the send button arrives WITHOUT a value and reads
the synchronized mirror, because the editor carries a `:document' and is
therefore not a stateful draft; on-enter and the re-run button carry
`:value'.

A returned NODE becomes the sample.  Anything else is a card.  That is
the whole loop, and the node case is the one the catalog exists for: the
print step of this REPL is a rendering."
  (let* ((id (plist-get args :component))
         (index (plist-get args :index))
         (surface (plist-get params :surface))
         (component (and (stringp id) (jetpacs-m3-component id))))
    (cond
     ((not (and (stringp id) (integerp index))) 'rejected)
     ((null component) 'stale)
     ((not (< -1 index (length (plist-get component :examples)))) 'stale)
     (t
      (let ((input (or (plist-get args :value)
                       (when-let* ((client (jetpacs-client)))
                         (ebp-client-editor-text
                          client
                          (jetpacs-m3-repl-document id index)
                          (jetpacs-m3-repl-editor-id id index))))))
        (if (not (and (stringp input) (not (string-blank-p input))))
            'rejected
          (jetpacs-flow-continue
           (lambda ()
             (pcase-let ((`(,value ,_output ,errorp)
                          (jetpacs-repl-run
                           (jetpacs-m3-repl-session id index) input)))
               ;; A node replaces the sample; a value that is not a node
               ;; stays in its card, and an ERROR never touches the
               ;; sample at all — the screen you were looking at is the
               ;; one thing a failed experiment must not cost you.
               (when (and (not errorp) (jetpacs-root-node-p value))
                 (puthash (jetpacs-m3-example-screen-id id index) value
                          jetpacs-m3-repl--overrides))
               (condition-case err
                   (jetpacs-shell-push (or surface jetpacs-m3-owner))
                 (error (message "jetpacs-m3-repl: refresh failed: %s"
                                 (jetpacs-error-label err)))))))
          'accepted))))))

(defun jetpacs-m3-repl--on-reset (args params)
  "Discard one example's override and re-render it as upstream's."
  (let ((id (plist-get args :component))
        (index (plist-get args :index))
        (surface (plist-get params :surface)))
    (cond
     ((not (and (stringp id) (integerp index))) 'rejected)
     ((null (jetpacs-m3-component id)) 'stale)
     (t (remhash (jetpacs-m3-example-screen-id id index)
                 jetpacs-m3-repl--overrides)
        (jetpacs-flow-continue
         (lambda ()
           (condition-case err
               (jetpacs-shell-push (or surface jetpacs-m3-owner))
             (error (message "jetpacs-m3-repl: reset refresh failed: %s"
                             (jetpacs-error-label err))))))
        'accepted))))

;;;###autoload
(defun jetpacs-m3-repl-reset-all ()
  "Discard every Playground override — M-x parity for the Reset rows.
`docs/CHROME-VOCABULARY.md': chrome is a projection of commands, so
every affordance is reachable without it."
  (interactive)
  (clrhash jetpacs-m3-repl--overrides)
  (when (jetpacs-connected-p)
    (ignore-errors (jetpacs-shell-push jetpacs-m3-owner)))
  (message "jetpacs-m3: every sample is upstream's again"))

(defun jetpacs-m3-repl-register ()
  "Attach the Playground to the catalog's Example screens."
  (with-jetpacs-owner jetpacs-m3-owner
    (jetpacs-defaction "m3catalog.repl" #'jetpacs-m3-repl--on-eval)
    (jetpacs-defaction "m3catalog.repl.reset" #'jetpacs-m3-repl--on-reset))
  (setq jetpacs-m3-example-extras-function #'jetpacs-m3-repl-extras))

(jetpacs-m3-repl-register)

(provide 'jetpacs-m3-repl)
;;; jetpacs-m3-repl.el ends here
