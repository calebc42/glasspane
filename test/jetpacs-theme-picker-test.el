;;; jetpacs-theme-picker-test.el --- ERT for the theme-picker scaffold -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The promoted scaffold's gate (docs/PLAN-jetpacs-debt-and-scaffold.md
;; §3 step 3, reversing FOUNDATION-GAPS #8): the coverage moved here
;; from test/glasspane-test.el WITH the module, because it exercises the
;; scaffold alone — every provider is a lambda and every action name a
;; plain string (the "ef." spellings below are data, kept from the
;; first instantiation).  The ef assertions proper — glasspane-ef
;; instantiating this scaffold — stay in the glasspane suite.

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-theme-picker)

(ert-deftest jetpacs-theme-picker-scaffold ()
  "The scaffold: display names, the swatch rebuild on
`jetpacs-surface' + universal width/height, the preview's modus-5.0
gate, light/dark grouping with the active-theme marker, the mirror
note both ways, and the customize cross-link — every node through the
canonical wire encoding."
  (should (equal (jetpacs-theme-picker-display-name
                  "ef-" (intern "ef-melissa-dark"))
                 "Melissa Dark"))
  ;; Swatch: nil-safe, circle surface, dp via universal attrs.
  (should-not (jetpacs-theme-picker--swatch nil))
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-theme-picker--swatch "#aabbcc"))))
    (should (string-search "\"shape\":\"circle\"" json))
    (should (string-search "\"color\":\"#aabbcc\"" json))
    (should (string-search "\"width\":22" json)))
  (should (string-search "\"height\":18"
                         (jetpacs-node->canonical-json
                          (jetpacs-theme-picker--swatch "#123456" 18))))
  ;; Preview gates on the modus 5.0 palette machinery.
  (let ((color-fn (lambda (&rest _) "#001122")))
    (when (not (fboundp 'modus-themes-activate))
      (should-not (jetpacs-theme-picker-preview color-fn 'any)))
    (cl-letf (((symbol-function 'modus-themes-activate) (lambda (&rest _))))
      (should (= (length (jetpacs-theme-picker-preview color-fn 'any)) 3))))
  ;; Grouping, the active marker, and the load-action args plist.
  (let* ((day (intern "ef-day")) (night (intern "ef-night"))
         (section (jetpacs-theme-picker-themes-section
                   (list day night) day
                   :dark-p-fn (lambda (theme) (eq theme night))
                   :display-fn #'symbol-name
                   :color-fn (lambda (&rest _) nil)
                   :load-action "ef.load"))
         (json (jetpacs-node->canonical-json
                (apply #'jetpacs-column section))))
    (should (= (length section) 4))          ; Light hdr, day, Dark hdr, night
    (should (string-search "\"title\":\"Light\"" json))
    (should (string-search "\"title\":\"Dark\"" json))
    (should (string-search "check_circle" json))
    (should (string-search "\"theme\":\"ef-night\"" json))
    ;; The active theme's card is not re-loadable.
    (should-not (string-search "\"theme\":\"ef-day\"" json)))
  ;; Mirror note both ways; the mode variable is a hard require here.
  (let ((jetpacs-theme-mode 'mirror))
    (should (string-search "Mirroring"
                           (jetpacs-node->canonical-json
                            (jetpacs-theme-picker-mirror-note "ef.mirror")))))
  (let ((jetpacs-theme-mode 'system))
    (let ((json (jetpacs-node->canonical-json
                 (jetpacs-theme-picker-mirror-note "ef.mirror"))))
      (should (string-search "Mirror on phone" json))
      (should (string-search "\"action\":\"ef.mirror\"" json))))
  ;; Current-card none arm, and the customize cross-link.
  (should (string-search "No ef theme active"
                         (jetpacs-node->canonical-json
                          (jetpacs-theme-picker-current-card
                           nil
                           :display-fn #'symbol-name
                           :dark-p-fn #'ignore
                           :color-fn #'ignore
                           :mirror-action "ef.mirror"
                           :none-label "No ef theme active"))))
  (let ((json (jetpacs-node->canonical-json
               (jetpacs-theme-picker-more-link "ef-themes"))))
    (should (string-search "\"action\":\"customize.show\"" json))
    (should (string-search "\"group\":\"ef-themes\"" json))))

;;; jetpacs-theme-picker-test.el ends here
