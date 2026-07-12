;;; build-bundle.el --- Regenerate the Glasspane single-file bundle -*- lexical-binding: t; -*-

;; Concatenate the Glasspane app sources into one loadable bundle at the repo
;; root. Run after editing any source file:
;;
;;   emacs --batch -l emacs/build-bundle.el
;;
;; Output:
;;   glasspane.el  — the Glasspane Tier-1 app (emacs/apps/): the org app, the
;;                   magit pie, the demo tour.  (The package/customize
;;                   browsers, tools hub, and automations view moved into
;;                   the jetpacs core 2026-07-10 — the core bundle ships
;;                   them.)
;;
;; Unlike the old monorepo bundle, this does NOT inline the Jetpacs core. The
;; bundle opens with `(require 'jetpacs-core)`, so the jetpacs foundation bundle
;; (jetpacs-core.el, from the separate jetpacs repo / the `jetpacs' submodule) must be
;; on `load-path' first. That is the whole point of the split: Glasspane is
;; pure elisp that `(require 's the core, never a copy of it.
;;
;; The files are emitted in dependency order. Because every source ends with a
;; `(provide 'FEATURE)', the inter-file `(require ...)' forms for app features
;; become no-ops once the providing chunk has loaded earlier in the bundle;
;; the core `(require 'jetpacs-...)' forms resolve against the already-loaded
;; jetpacs-core. External requires (org, dired, cl-lib, ...) resolve normally.

;;; Code:

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       ;; Dependency order. Do not reorder without re-checking the require
       ;; graph.
       (app-files '("apps/jetpacs-magit.el"
                    "apps/glasspane/glasspane-org.el"
                    "apps/glasspane/glasspane-org-rich.el"
                    "apps/glasspane/glasspane-org-reader.el"
                    "apps/glasspane/glasspane-clock.el"
                    "apps/glasspane/glasspane-org-toolbar.el"
                    "apps/glasspane/glasspane-ui.el"
                    "apps/glasspane/glasspane-agenda.el"
                    "apps/glasspane/glasspane-capture.el"
                    "apps/glasspane/glasspane-detail.el"
                    "apps/glasspane/glasspane-search.el"
                    "apps/glasspane/glasspane-table.el"
                    "apps/glasspane/glasspane-journal.el"
                    "apps/glasspane/glasspane-views.el"
                    "apps/glasspane/glasspane-automations.el"
                    "apps/glasspane/glasspane-notes.el"
                    "apps/glasspane/glasspane-srs.el"
                    "apps/glasspane/glasspane-demo.el"
                    "apps/glasspane/glasspane-gallery.el"
                    "apps/glasspane/glasspane-config.el"
                    "apps/glasspane/glasspane.el"))
       (out (expand-file-name "../glasspane.el" here)))
  (with-temp-file out
    (insert ";;; glasspane.el --- Glasspane Emacs client (Jetpacs Tier-1 app), single-file bundle -*- lexical-binding: t; -*-\n"
            ";;\n"
            ";; GENERATED FILE -- do not edit by hand.\n"
            ";; Produced by emacs/build-bundle.el from the emacs/apps/ sources.\n"
            ";; Concatenated in dependency order; each part keeps its own `provide',\n"
            ";; so the inter-file `require' forms resolve within this file.\n"
            ";;\n"
            ";; Requires the Jetpacs core (jetpacs-core.el) on `load-path' first.\n"
            ";;\n"
            ";;; Code:\n\n"
            "(require 'jetpacs-core)\n\n")
    (dolist (f app-files)
      (insert ";;; ==================================================================\n"
              (format ";;; BEGIN %s\n" f)
              ";;; ==================================================================\n\n")
      (insert-file-contents (expand-file-name f here))
      (goto-char (point-max))
      (insert "\n"))
    (insert "(provide 'glasspane)\n"
            ";;; glasspane.el ends here\n"))
  (message "Wrote %s" out))

;;; build-bundle.el ends here
