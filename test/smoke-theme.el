;;; smoke-theme.el --- W9-h theme mirror device smoke -*- lexical-binding: t; -*-
;; Push a surface, then a full §18.4 palette (dark + a mirrored role map incl.
;; the success/warning extension roles). The app mirrors it: the surface goes
;; teal-dark, primary/secondary buttons take the pushed hues, and the
;; success/warning-colored chips render in their pushed colors (screenshot).
(require 'ebp)
(let ((client
       (ebp-connect
        "127.0.0.1" 8765
        :client-name "wsl-emacs" :client-version "30.1"
        :pairing-id "101112131415161718191a1b1c1d1e1f"
        :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
        :wants '("theme")
        :receipt-file (make-temp-file "ebp-theme-receipts")
        :ready-function
        (lambda (c)
          (ebp-client-surface-update
           c "app:main"
           '(:t "column" :padding 24 :spacing 12
             :children [(:t "text" :style "headline" :text "Mirrored theme")
                        (:t "button" :label "Primary"
                         :on_tap (:action "demo.p"))
                        (:t "row" :spacing 8
                         :children [(:t "badge" :label "OK" :color "success")
                                    (:t "badge" :label "Warn" :color "warning")])
                        (:t "surface" :color "primary_container" :padding 12
                         :corner 12
                         :children [(:t "text" :color "on_primary_container"
                                     :text "on a primary container")])]))
          ;; A dark palette mirroring an Emacs theme, incl. success/warning.
          (ebp-client-theme-set
           c :dark t
           :colors '(:primary "#66d9ef" :on_primary "#08303a"
                     :primary_container "#0d4a57" :on_primary_container "#c9f2fb"
                     :secondary "#a6e22e" :surface "#141821"
                     :on_surface "#e6e9ef" :surface_variant "#232838"
                     :success "#8fd694" :warning "#e6c76b"))))))
  (cl-loop repeat 60 do (accept-process-output nil 0.1))
  (message "theme smoke: state=%s" (ebp-client-state client))
  (kill-emacs 0))
;;; smoke-theme.el ends here
