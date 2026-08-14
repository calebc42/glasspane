;;; jetpacs-org-toolbar.el --- The org editor toolbar, as data (JA-5) -*- lexical-binding: t; -*-

;;; Commentary:

;; The org formatting toolbar, composed as pure SPEC 17.7 data.  The
;; Companion interprets every item locally — a snippet is one splice
;; and one undo step, a `:line' op never contacts Emacs — so the
;; toolbar works on the plain (non-synchronized) editor and offline.
;; Ported from poc-v1 jetpacs-org-toolbar.el with the format-6 fixes:
;; keyword arguments throughout, and `:long-press' as an OP PLIST
;; (exactly one non-menu operation), not a nested item.  No `:command'
;; ops — those require a synchronized `:document' the plain editor
;; never has, and `jetpacs-editor' rejects them at build time.
;;
;; Host: `jetpacs-editor-org' contributes this data through the generic
;; `jetpacs-editor' adapter registry for `.org' paths.  The file is the
;; specification of what the baseline Org toolbar contains.

;;; Code:

(require 'jetpacs-widgets)

(defvar jetpacs-org-toolbar-src-languages
  '("emacs-lisp" "python" "shell" "kotlin" "java" "javascript"
    "sql" "c" "rust" "go" "org" "text")
  "Preset languages offered by the source-block menu.")

(defun jetpacs-org-toolbar--src-item (lang)
  "A menu item splicing a LANG source block around the cursor."
  (jetpacs-toolbar-item
   :label lang
   :snippet (format "#+begin_src %s\n${cursor}\n#+end_src" lang)
   :placement "block"))

(defun jetpacs-org-toolbar--level-item (prefix n)
  "A menu item splicing PREFIX at level N onto the line start."
  (jetpacs-toolbar-item
   :label (format "%s %d" prefix n)
   :snippet (concat (make-string n ?*) " "
                    (if (equal prefix "TODO") "TODO " ""))
   :placement "line-start"))

(defun jetpacs-org-toolbar ()
  "The org editing toolbar: a list of SPEC 17.7 ToolbarItems."
  (list
   (jetpacs-toolbar-item
    :icon "title" :label "H"
    :menu (mapcar (lambda (n) (jetpacs-org-toolbar--level-item "H" n))
                  '(1 2 3 4 5 6)))
   (jetpacs-toolbar-item
    :icon "task_alt" :label "TODO"
    :menu (mapcar (lambda (n) (jetpacs-org-toolbar--level-item "TODO" n))
                  '(1 2 3 4 5 6)))
   (jetpacs-toolbar-item :icon "format_indent_decrease" :label "←"
                         :line "promote")
   (jetpacs-toolbar-item :icon "format_indent_increase" :label "→"
                         :line "demote")
   (jetpacs-toolbar-item :icon "arrow_upward" :label "↑" :line "move-up")
   (jetpacs-toolbar-item :icon "arrow_downward" :label "↓"
                         :line "move-down")
   (jetpacs-toolbar-item :icon "checklist" :label "☐"
                         :snippet "- [ ] " :placement "line-start")
   (jetpacs-toolbar-item :icon "data_object" :label "[/]"
                         :snippet "[/]"
                         :long-press '(:snippet "[%]"))
   (jetpacs-toolbar-item :icon "format_list_bulleted" :label "•"
                         :snippet "- " :placement "line-start")
   (jetpacs-toolbar-item :icon "format_list_numbered" :label "1."
                         :snippet "1. " :placement "line-start")
   (jetpacs-toolbar-item
    :icon "code" :label "Src"
    :menu (append (mapcar #'jetpacs-org-toolbar--src-item
                          jetpacs-org-toolbar-src-languages)
                  (list (jetpacs-toolbar-item
                         :label "Custom…"
                         :snippet "#+begin_src ${input:Language}\n${cursor}\n#+end_src"
                         :placement "block"))))
   (jetpacs-toolbar-item :icon "data_array" :label "Props"
                         :snippet ":PROPERTIES:\n:END:"
                         :placement "block")
   (jetpacs-toolbar-item :icon "format_bold" :label "B"
                         :snippet "*${selection}*")
   (jetpacs-toolbar-item :icon "format_italic" :label "I"
                         :snippet "/${selection}/")
   (jetpacs-toolbar-item :icon "code" :label "~"
                         :snippet "~${selection}~")
   (jetpacs-toolbar-item :icon "format_strikethrough" :label "S"
                         :snippet "+${selection}+")
   (jetpacs-toolbar-item :icon "link" :label "Link"
                         :snippet "[[${cursor}][${selection}]]")
   (jetpacs-toolbar-item :icon "schedule" :label "TS"
                         :snippet "[${date}]"
                         :long-press '(:snippet "<${date}>"))))

(provide 'jetpacs-org-toolbar)
;;; jetpacs-org-toolbar.el ends here
