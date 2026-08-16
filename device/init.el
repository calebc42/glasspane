;;; init.el --- Compatibility loader for managed Jetpacs -*- lexical-binding: t; -*-

;; New onboarding adds the same load-path and `require' forms directly to the
;; user's init.el.  Keep this wrapper in the managed tree so older one-line
;; loaders continue to work during migration.

(add-to-list
 'load-path
 (expand-file-name "emacs/"
                   (file-name-directory (or load-file-name buffer-file-name))))
(require 'jetpacs)

;;; init.el ends here
