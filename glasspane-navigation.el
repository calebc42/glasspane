;;; glasspane-navigation.el --- One document route for every Glasspane entry -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Glasspane has many ways to NAME a document location, but exactly one way
;; to PRESENT it.  A Project/Agenda/Notes row carries an app-scoped Org token;
;; a Resource row carries a path.  Their handlers validate those different
;; authorities and then converge here:
;;
;;   durable heading token --resolve--> (path, position) --+
;;                                                       +--> Files document host
;;   indexed Resource path ----validate at Files-------->+
;;
;; This distinction is intentional.  Putting a raw position into a long-lived
;; card would discard `ebp-org' identity and staleness handling; making a file
;; row mint a heading token would invent an identity it does not have.  What
;; must never vary by entry point is the presentation policy after resolution:
;; the Files surface, the Glasspane Org reader state, the staged Back screen,
;; and the return action are all owned by this module.
;;
;; Feature modules therefore build cross-surface descriptors with
;; `glasspane-navigation-heading-action' or
;; `glasspane-navigation-document-action', and handlers finish through
;; `glasspane-navigation-open-document'.  The only direct call to
;; `jetpacs-files-open-path' in the applet is the low-level boundary below.
;; `test/glasspane-navigation-test.el' enforces that source-level rule.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-files)
(require 'jetpacs-reader-org)
(require 'glasspane-ui)

;; Keep the detail module loadable without the optional foldable reader.  In a
;; complete Glasspane registration `glasspane.el' loads the reader before this
;; module, so the contextual preparation function is present.
(require 'glasspane-org-reader nil t)
(declare-function glasspane-org-reader-prepare-landing
                  "glasspane-org-reader" (path))

(defconst glasspane-navigation--document-open-verb
  "glasspane.document.open"
  "Path-authority adapter for the canonical document presenter.")

(defconst glasspane-navigation--files-return-verb
  "glasspane.files.return"
  "Cross-surface Back verb installed on Glasspane-owned Files screens.")

(defun glasspane-navigation-files-surface ()
  "Return the one Files surface used by every Glasspane handoff."
  (jetpacs-files-surface))

(defun glasspane-navigation-heading-action (token)
  "Return the canonical Files-opening action for heading TOKEN.
TOKEN remains the authority: `heading.visit' resolves it immediately before
calling `glasspane-navigation-open-document'.  Return nil unless TOKEN is a
string, so a malformed item loses only its affordance."
  (and (stringp token)
       (jetpacs-shell-action-opening-surface
        "heading.visit" (glasspane-navigation-files-surface)
        :args (list :token token))))

(defun glasspane-navigation-document-action (path)
  "Return the canonical Files-opening action for document PATH.
The action handler never trusts PATH merely because it came from a rendered
row; `jetpacs-files-open-path' revalidates it against the effective roots.
Return nil unless PATH is a string."
  (and (stringp path)
       (jetpacs-shell-action-opening-surface
        glasspane-navigation--document-open-verb
        (glasspane-navigation-files-surface)
        :args (list :path path))))

(defun glasspane-navigation-return-action ()
  "Return the negotiated action from Files to Glasspane, or nil.
Older Companions without `action.open_surface' retain Files' local Back
behavior.  A modern Companion returns to the untouched Glasspane stack, so a
Project remains a Project and a Resource remains a Resource after the trip."
  (jetpacs-files-return-action
   (jetpacs-shell-surface-for "glasspane")
   glasspane-navigation--files-return-verb))

(cl-defun glasspane-navigation-open-files-path
    (path &key position browser-id browser-fab return-action)
  "Open PATH through Glasspane's sole low-level Files boundary.
POSITION, BROWSER-ID, BROWSER-FAB, and RETURN-ACTION map directly to the
document host's public handoff seam.  Feature modules should use
`glasspane-navigation-open-document' for a regular document; this lower-level
function exists for Resources' explicit directory browser."
  (jetpacs-files-open-path
   path (glasspane-navigation-files-surface) position browser-id browser-fab
   return-action))

(defun glasspane-navigation-open-document (path &optional position)
  "Present document PATH at optional POSITION by Glasspane's canonical route.
All direct document entry points call this function after validating their
own identity type.  Files validates PATH synchronously and queues the actual
open as a flow continuation.  Only after that validation succeeds do we reset
an Org document to Glasspane's visible tree presentation; the state is ready
before the queued render without allowing a refused path to allocate reader
state.

The staged screen, return descriptor, and cross-surface return state machine
are owned by `jetpacs-files'.  Return `rejected' for malformed PATH or
POSITION."
  (let ((status
         (with-jetpacs-owner "glasspane"
           (jetpacs-files-open-document
            path position glasspane-navigation--files-return-verb))))
    (when (and (eq status 'accepted)
               (ebp-org-path-p path)
               (fboundp 'glasspane-org-reader-prepare-landing))
      (glasspane-org-reader-prepare-landing path))
    status))

(defun glasspane-navigation--on-document-open (args params)
  "Open ARGS' path unless the path action in PARAMS is stale."
  (let ((path (plist-get args :path)))
    (cond
     ((not (stringp path)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t (glasspane-navigation-open-document path)))))

(defun glasspane-navigation-return (args params)
  "Return from Files to Glasspane's unchanged navigation stack.
Delegates ARGS and PARAMS to `jetpacs-files-return'."
  (with-jetpacs-owner "glasspane"
    (jetpacs-files-return args params)))

(defconst glasspane-navigation--verbs
  '("glasspane.document.open" "glasspane.files.return")
  "The canonical document-route verbs owned by this module.")

(defun glasspane-navigation-register ()
  "Register the canonical document actions idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction
     "glasspane.document.open" #'glasspane-navigation--on-document-open
     :doc "Open a validated path through Glasspane's canonical document route"
     :strict t
     :args '((:name path :type "text" :required t)))
    (jetpacs-defaction
     "glasspane.files.return" #'glasspane-navigation-return
     :doc "Return from Files to Glasspane's untouched navigation stack"
     :any-surface t)))

(defun glasspane-navigation-unregister ()
  "Drop every canonical document action."
  (dolist (name glasspane-navigation--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-navigation)
;;; glasspane-navigation.el ends here
