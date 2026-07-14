;;; glasspane-source.el --- Glasspane org data as a jetpacs binding source -*- lexical-binding: t; -*-

;; The data half of Glasspane's declarative (`:spec') views: a jetpacs
;; `jetpacs-defsource' named "glasspane.org" that wraps the app's org query
;; engine — `glasspane-org--query' over `jetpacs-org-parse-query', i.e.
;; whichever of vulpea / org-ql / the built-in interpreter is live — and
;; NORMALIZES each result item to core's domain-neutral field contract before
;; core sees it.  This is the "a source normalizes engine data" half of the
;; binding layer (see the submodule's docs/BINDING.md): the query engine and
;; its memo stay app-side; the canonicalizer adapts their output.
;;
;; Why a canonicalizer.  A raw Glasspane item alist carries engine-native
;; shapes the `:spec' transforms don't understand:
;;   - `scheduled'/`deadline' are RAW org timestamp strings ("<2026-07-13 Mon
;;     09:00>"); the `date'/`date-label' transforms want an ISO "YYYY-MM-DD".
;;   - `tags' is a VECTOR; the `tags-list'/`count' transforms want a list.
;;   - `priority' is a char in the vulpea path; a "text" field wants a string.
;; `glasspane-source--canonicalize' maps each item to those canonical types,
;; and `:fields' declares them so a `:spec' template can bind them.  `ref' is
;; an opaque locator (an alist as built by `jetpacs-org-heading-ref') and is
;; passed through intact for an action's `:args'.
;;
;; Why UNCACHED.  `glasspane-org--query' is itself memoised, and its memo is
;; the one seam every mutation path already busts via
;; `jetpacs-org-cache-invalidate' — including in-buffer edits that have not
;; yet reached disk.  A source-level `:cache-key' keyed on file mtime (the only
;; freshness signal a nullary token could cheaply read) would serve stale rows
;; after exactly those edits.  Re-canonicalising the already-memoised query
;; result on each push is cheap (a `mapcar' over a bounded item list) and
;; always fresh, so we lean on the engine's own correctly-invalidated cache
;; rather than add a second one that is harder to keep honest.

;;; Code:

(require 'jetpacs-source)
(require 'jetpacs-surfaces)
(require 'glasspane-org)

(defun glasspane-source--iso-date (ts)
  "The \"YYYY-MM-DD\" date inside org timestamp string TS, or nil.
Mirrors the agenda's presentation helper `glasspane-ui--ts-date'; kept
local so the data layer does not `require' a view module."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" ts))
    (match-string 1 ts)))

(defun glasspane-source--string (v)
  "Coerce V to a string, or nil when V is nil.
Leaves an absent field nil (so its template placeholder drops cleanly)."
  (and v (if (stringp v) v (format "%s" v))))

(defun glasspane-source--priority (v)
  "Coerce a priority V to its letter string (\"A\"), or nil.
The org path already hands us a string, but the vulpea path passes the
priority verbatim, where it may be a character code (?A); `format' would
turn that into \"65\", so decode a character with `char-to-string'."
  (cond ((null v) nil)
        ((stringp v) v)
        ((characterp v) (char-to-string v))
        (t (format "%s" v))))

(defun glasspane-source--canonicalize (item)
  "Map raw Glasspane org ITEM alist to the \"glasspane.org\" canonical fields.
Returns a fresh symbol-keyed alist; see this file's commentary for the
per-field normalization contract."
  (list (cons 'headline  (glasspane-source--string (alist-get 'headline item)))
        (cons 'todo      (glasspane-source--string (alist-get 'todo item)))
        (cons 'scheduled (glasspane-source--iso-date (alist-get 'scheduled item)))
        (cons 'deadline  (glasspane-source--iso-date (alist-get 'deadline item)))
        (cons 'tags      (append (alist-get 'tags item) nil))   ; vector -> list
        (cons 'priority  (glasspane-source--priority (alist-get 'priority item)))
        (cons 'ref       (alist-get 'ref item))))               ; opaque locator

(defun glasspane-source--org-query (params)
  "The \"glasspane.org\" `:query' thunk: PARAMS -> canonical item list.
PARAMS is the canonical params alist; its `query' is a search string in
any shape `jetpacs-org-parse-query' accepts.  An empty/nil query yields
no items (never an error)."
  (mapcar #'glasspane-source--canonicalize
          (glasspane-org--query
           (jetpacs-org-parse-query (alist-get 'query params)))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defsource "glasspane.org"
    :params '((:name query :type "text" :required t))
    :fields '((:name "headline"  :type "text")
              (:name "todo"      :type "text")
              (:name "scheduled" :type "date")
              (:name "deadline"  :type "date")
              (:name "tags"      :type "string-list")
              (:name "priority"  :type "text")
              (:name "ref"       :type "ref"))
    :query #'glasspane-source--org-query))

(provide 'glasspane-source)
;;; glasspane-source.el ends here
