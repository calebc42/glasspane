;;; smoke-syntax.el --- W9-h2 syntax fontification smoke -*- lexical-binding: t; -*-
;; Push text nodes with `syntax` languages (elisp, python, org) plus a
;; syntax-highlighted text_input. The device fontifies each with the pushed
;; theme.set `syntax` palette (SyntaxStyle fg per role). PASS is visual
;; (screenshot): keywords/strings/comments/headings render in distinct colours.
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-syntax-receipts")
        :ready-function
        (lambda (c)
          ;; A dark palette with an explicit syntax role map (SyntaxStyle
          ;; objects carrying `fg`), mirroring an Emacs theme.
          (ebp-client-theme-set
           c :dark t
           :colors '(:surface "#141821" :on_surface "#e6e9ef")
           :syntax '(:keyword (:fg "#ff79c6" :font_weight "bold")
                     :string (:fg "#f1fa8c")
                     :comment (:fg "#6272a4" :italic t)
                     :function (:fg "#8be9fd")
                     :constant (:fg "#bd93f9")
                     :heading (:fg "#50fa7b")))
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 20 :spacing 14
             :children
             [(:t "text" :style "title" :text "Syntax fontification")
              (:t "text" :syntax "elisp" :style "mono"
               :text ";; a comment\n(defun greet (name)\n  (message \"hi %s\" name))")
              (:t "text" :syntax "python" :style "mono"
               :text "def add(a, b):  # sum\n    return a + b")
              (:t "text" :syntax "org"
               :text "* TODO Ship it :urgent:\n- a /list/ with ~code~\n[[https://x][link]]")
              (:t "text_input" :id "code" :syntax "elisp"
               :label "elisp field"
               :value "(let ((x 1)) (+ x 2))")]))))))
  (cl-loop repeat 60 do (accept-process-output nil 0.1))
  (message "syntax smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-syntax.el ends here
