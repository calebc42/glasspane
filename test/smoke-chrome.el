;;; smoke-chrome.el --- W9-g: §17.6 scaffold chrome -*- lexical-binding: t; -*-

;; Push a full scaffold (top_bar, body, fab, bottom_bar, floating_toolbar,
;; drawer, on_refresh). The adb driver taps the fab, opens the drawer and taps
;; its item, and pulls to refresh. PASS = the surface applies and every
;; landed gesture dispatched its action (refresh only via the user gesture).

(require 'ebp)

(defvar ebp-smoke--events nil)

(let* ((client
        (ebp-connect
         "127.0.0.1" 8765
         :client-name "wsl-emacs" :client-version "30.1"
         :pairing-id "101112131415161718191a1b1c1d1e1f"
         :token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw")
         :wants '("theme")
         :receipt-file (make-temp-file "ebp-chrome-receipts")
         :ready-function
         (lambda (c)
           (ebp-client-surface-update
            c "app:main"
            '(:t "scaffold"
              :top_bar (:t "text" :text "Chrome" :style "title")
              ;; lazy_column body: pull-to-refresh needs a nested-scroll
              ;; container at the top for the overscroll gesture to register.
              :body (:t "lazy_column" :padding 24 :spacing 8
                     :children [(:t "text" :key "b1" :text "Body content")
                                (:t "text" :key "b2" :text "pull down to refresh")])
              :fab (:t "icon_button" :icon "add"
                    :content_description "fab-add"
                    :on_tap (:action "demo.fab"))
              :bottom_bar (:t "row" :padding 8 :arrange "space_evenly"
                           :children [(:t "icon_button" :icon "home"
                                       :content_description "nav-home"
                                       :on_tap (:action "demo.nav1"))
                                      (:t "icon_button" :icon "search"
                                       :content_description "nav-search"
                                       :on_tap (:action "demo.nav2"))])
              :floating_toolbar (:t "row" :padding 4
                                 :children [(:t "assist_chip" :label "Tool"
                                             :on_tap (:action "demo.tool"))])
              :drawer (:t "column" :padding 16
                       :children [(:t "text" :text "Drawer" :style "title")
                                  (:t "button" :label "Drawer item"
                                   :on_tap (:action "demo.drawer"))])
              :on_refresh (:action "demo.refresh"))
            :callback (lambda (status error)
                        (message "CHROME status=%S error=%S" status error)))))))
  (dolist (a '("demo.fab" "demo.nav1" "demo.nav2" "demo.tool"
               "demo.drawer" "demo.refresh"))
    (ebp-client-register-action
     client a
     (lambda (_c params)
       (push (plist-get params :action) ebp-smoke--events)
       (message "ACTION %s" (plist-get params :action))
       'accepted)))
  (cl-loop repeat 500 do (accept-process-output nil 0.1))
  (let ((events (nreverse ebp-smoke--events)))
    (message "EVENTS %S" events)
    (message "chrome smoke: fab=%S drawer=%S refresh=%S nav=%S"
             (and (member "demo.fab" events) t)
             (and (member "demo.drawer" events) t)
             (and (member "demo.refresh" events) t)
             (and (member "demo.nav1" events) t))
    ;; PASS if at least fab + drawer + refresh landed.
    (kill-emacs (if (and (member "demo.fab" events)
                         (member "demo.drawer" events)
                         (member "demo.refresh" events))
                    0 1))))

;;; smoke-chrome.el ends here
