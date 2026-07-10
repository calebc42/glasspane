;;; jetpacs-magit.el --- Curated Tier 1 magit pie menu -*- lexical-binding: t; -*-

;; The first curated Tier 1 radial menu: magit-status.  Four categories
;; fan out as a speed dial; each opens a pie of hand-labelled bindings.
;; Entries marked as prefixes (Commit, Push, Branch, …) are magit's
;; transient commands — running one activates the transient, and
;; `jetpacs-keymap--sync-pie' then pushes the live transient's own pie, so
;; the drill-in continues seamlessly into magit's real menus.
;;
;; This is pure data plus key dispatch: nothing here requires magit at
;; load time.  Keys are executed in the magit buffer through the same
;; allowlisted `jetpacs.keymap.run' action as everything else.

;;; Code:

(require 'jetpacs-keymap)

(defconst jetpacs-magit--menu
  '(("Stage" "add"
     ("s"   "Stage")
     ("u"   "Unstage")
     ("S"   "Stage all")
     ("U"   "Unstage all")
     ("k"   "Discard")
     ("g"   "Refresh"))
    ("Share" "sync"
     ("c"   "Commit" t)
     ("P"   "Push" t)
     ("F"   "Pull" t)
     ("f"   "Fetch" t)
     ("!"   "Run" t))
    ("Branch" "call_split"
     ("b"   "Branch" t)
     ("m"   "Merge" t)
     ("r"   "Rebase" t)
     ("z"   "Stash" t)
     ("t"   "Tag" t))
    ("Inspect" "history"
     ("l"   "Log" t)
     ("d"   "Diff" t)
     ("y"   "Refs" t)
     ("$"   "Process")))
  "Curated magit-status pie menu: (CATEGORY ICON (KEY LABEL [PREFIX-P])...).
PREFIX-P marks a transient prefix — the pie shows a ▸ and running it
drills into the live transient's own pie.")

(defun jetpacs-magit--binding-spec (entry buffer-name)
  "Build one pie binding spec from ENTRY (KEY LABEL [PREFIX-P])."
  (pcase-let ((`(,key ,label ,prefix-p) entry))
    (append
     `((key . ,key)
       (label . ,label)
       (action . ,(jetpacs-action "jetpacs.keymap.run"
                               :args `((buffer . ,buffer-name)
                                       (key . ,key))
                               :when-offline "drop")))
     (when prefix-p '((is_prefix . t))))))

(defun jetpacs-magit-pie-spec (buffer)
  "Curated Tier 1 pie-menu spec for magit BUFFER."
  (let ((buffer-name (buffer-name buffer)))
    `((center_label . "Magit")
      (buffer . ,buffer-name)
      (categories
       . ,(vconcat
           (mapcar
            (lambda (cat)
              (pcase-let ((`(,label ,icon . ,entries) cat))
                `((label . ,label)
                  (icon . ,icon)
                  (bindings . ,(vconcat
                                (mapcar (lambda (e)
                                          (jetpacs-magit--binding-spec e buffer-name))
                                        entries))))))
            jetpacs-magit--menu))))))

(jetpacs-keymap-register-tier1 'magit-status-mode #'jetpacs-magit-pie-spec)

(provide 'jetpacs-magit)
;;; jetpacs-magit.el ends here
