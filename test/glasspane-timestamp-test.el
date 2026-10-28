;;; glasspane-timestamp-test.el --- The planning timestamp dialog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Seeding, spelling and words; the dialog specs against the dialog
;; profile; the pick handler's re-show and staleness; the conclusion's
;; write through ebp-org; the period picker's callback.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'glasspane)

(glasspane-register)  ; `require' only loads

(defun glasspane-timestamp-test--session (stamp &optional which)
  "A session over STAMP for WHICH, seeded like the dialog seeds it."
  (append (list :which (or which "SCHEDULED") :ref 'test-ref
                :params '(:surface "app:glasspane"))
          (glasspane-timestamp-seed stamp)))

(ert-deftest glasspane-timestamp-test-seed-and-compose-round-trip ()
  "Parsed parts switch their rows on; composing spells the stamp back."
  (let ((s (glasspane-timestamp-test--session
            "<2026-10-30 Fri 09:00-10:30 +1w -1d>")))
    (should (equal (plist-get s :date) "2026-10-30"))
    (should (plist-get s :time-on))
    (should (plist-get s :end-on))
    (should (plist-get s :repeater-on))
    (should (plist-get s :delay-on))
    (should (equal (glasspane-timestamp-compose s)
                   "<2026-10-30 Fri 09:00-10:30 +1w -1d>")))
  ;; Empty stamp: today, now, defaults off; a switched-off part is not spelled.
  (let* ((now (encode-time 0 30 14 28 10 2026))
         (s (append '(:which "DEADLINE") (glasspane-timestamp-seed nil now))))
    (should (equal (plist-get s :date) "2026-10-28"))
    (should (equal (plist-get s :time) "14:30"))
    (should-not (plist-get s :time-on))
    (should (equal (plist-get s :repeater) ".+1w"))
    (should (equal (plist-get s :delay) "-1d"))
    (should (equal (glasspane-timestamp-compose s) "<2026-10-28 Wed>"))
    (should (equal (glasspane-timestamp-compose (plist-put s :time-on t))
                   "<2026-10-28 Wed 14:30>"))))

(ert-deftest glasspane-timestamp-test-words ()
  "Cookies and the title read in words."
  (should (equal (glasspane-timestamp-cookie-words "+1w" "SCHEDULED") "every week"))
  (should (equal (glasspane-timestamp-cookie-words "++2d" "SCHEDULED")
                 "every 2 days, catching up"))
  (should (equal (glasspane-timestamp-cookie-words ".+1m" "SCHEDULED")
                 "every month after done"))
  (should (equal (glasspane-timestamp-cookie-words "-1d" "SCHEDULED")
                 "appears 1 day late"))
  (should (equal (glasspane-timestamp-cookie-words "--2w" "SCHEDULED")
                 "first time appears 2 weeks late"))
  (should (equal (glasspane-timestamp-cookie-words "-3d" "DEADLINE")
                 "warns 3 days before"))
  (should (equal (glasspane-timestamp-cookie-words "junk" "DEADLINE") "junk"))
  (cl-letf (((symbol-function 'jetpacs-locale) (lambda () '(:hour_cycle "h23"))))
    (should (equal (glasspane-timestamp-title-words
                    (glasspane-timestamp-test--session
                     "<2026-10-30 Fri 09:00-10:30 +1w -1d>")
                    "2026-10-28")
                   "Fri 30 Oct · 09:00–10:30 · every week · appears 1 day late")))
  (cl-letf (((symbol-function 'jetpacs-locale) (lambda () nil)))
    (should (equal (glasspane-timestamp-clock-words "14:05") "2:05 PM"))
    (should (equal (glasspane-timestamp-clock-words "00:10") "12:10 AM"))))

(ert-deftest glasspane-timestamp-test-dialogs-fit-the-dialog-profile ()
  "Both dialogs serialize within the dialog profile and name their verbs."
  (let* ((s (glasspane-timestamp-test--session "<2026-10-30 Fri 09:00>"))
         (spec (glasspane-timestamp-dialog s "2026-10-28"))
         (json (jetpacs-node->canonical-json spec)))
    (should (jetpacs-check-profile spec 'dialog))
    (dolist (text '("Scheduled" "Today" "Tomorrow" "Next week" "Repeat" "Delay"
                    "Clear" "Cancel" "Set" "date_button" "time_button"
                    "gp-ts-time-on" "gp-ts-end-on" "gp-ts-repeater-on"
                    "gp-ts-delay-on" "glasspane.ts.part"))
      (should (string-search text json)))
    ;; Every pick captures the switches; Set captures them too.
    (should (string-search "\"capture_fields\":[\"gp-ts-time-on\"" json))
    ;; A deadline's delay row is a warning.
    (should (string-search
             "Warning"
             (jetpacs-node->canonical-json
              (glasspane-timestamp-dialog
               (glasspane-timestamp-test--session nil "DEADLINE") "2026-10-28"))))
    ;; Without a time the end time is disabled.
    (let ((off (jetpacs-node->canonical-json
                (glasspane-timestamp-dialog
                 (glasspane-timestamp-test--session nil) "2026-10-28"))))
      (should (string-search "\"enabled\":false" off))))
  (dolist (case '(("repeater" "SCHEDULED" "Repeat" 3)
                  ("delay" "SCHEDULED" "Delay" 2)
                  ("delay" "DEADLINE" "Warning period" 1)))
    (pcase-let* ((`(,part ,which ,title ,count) case)
                 (kind (glasspane-timestamp-period-kind part which))
                 (spec (glasspane-timestamp-period-dialog kind
                                                           (caar (plist-get kind :types))
                                                           "1" "w"))
                 (json (jetpacs-node->canonical-json spec)))
      (should (equal (plist-get kind :title) title))
      (should (= (length (plist-get kind :types)) count))
      (should (jetpacs-check-profile spec 'dialog))
      (should (string-search "gp-period-n" json))
      (should (string-search "gp-period-unit" json))
      (if (> count 1)
          (should (string-search "gp-period-type" json))
        (should-not (string-search "gp-period-type" json))))))

(ert-deftest glasspane-timestamp-test-picks-reshow-and-stale-picks-refuse ()
  "A pick moves one part, keeps the captured switches and re-shows."
  (let ((shown nil) (continued nil))
    (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'client))
              ((symbol-function 'jetpacs-dialog-slot-show)
               (lambda (id spec &rest _) (push (list id spec) shown) id))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (push fn continued))))
      (glasspane-timestamp-open 'ref "SCHEDULED" "<2026-10-30 Fri>"
                                '(:surface "app:glasspane"))
      (should (= (length shown) 1))
      (let* ((live (plist-get glasspane-timestamp--session :dialog-id))
             (params (list :dialog_id live
                           :fields '(:gp-ts-time-on t :gp-ts-end-on :json-false))))
        (should (eq (glasspane-timestamp--on-part '(:part "day" :when "+1d") params)
                    'accepted))
        (should (equal (plist-get glasspane-timestamp--session :date)
                       (jetpacs-dates-shift (format-time-string "%Y-%m-%d") 1 'day)))
        ;; The captured switch arrived with the pick.
        (should (plist-get glasspane-timestamp--session :time-on))
        (should-not (plist-get glasspane-timestamp--session :end-on))
        (should (= (length continued) 1))
        (funcall (pop continued))
        (should (= (length shown) 2))
        ;; The old dialog id is stale now.
        (should (eq (glasspane-timestamp--on-part '(:part "time" :value "9:15")
                                                  params)
                    'stale))
        (let ((fresh (list :dialog_id
                           (plist-get glasspane-timestamp--session :dialog-id))))
          (should (eq (glasspane-timestamp--on-part '(:part "time" :value "9:15")
                                                    fresh)
                      'accepted))
          (should (equal (plist-get glasspane-timestamp--session :time) "09:15"))
          (should (eq (glasspane-timestamp--on-part '(:part "date" :value "junk")
                                                    fresh)
                      'rejected))
          (should (eq (glasspane-timestamp--on-part '(:part "nope") fresh)
                      'rejected)))))
    (setq glasspane-timestamp--session nil)
    (should (eq (glasspane-timestamp--on-part '(:part "day" :when "+0d") nil)
                'stale))))

(ert-deftest glasspane-timestamp-test-set-and-clear-write-through-ebp-org ()
  "Set writes the whole stamp; Clear removes it; the surface refreshes."
  (let* ((dir (make-temp-file "glasspane-ts" t))
         (file (expand-file-name "a.org" dir))
         (ebp-org-roots (list dir))
         (org-agenda-files (list file))
         (concluders nil) (refreshes 0) (notes nil))
    (unwind-protect
        (progn
          (write-region "* TODO Review\nBody.\n" nil file nil 'silent)
          (ebp-org-cache-invalidate)
          (let ((ref (with-current-buffer (find-file-noselect file)
                       (goto-char (point-min))
                       (ebp-org-ref-at-point))))
            (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'client))
                      ((symbol-function 'jetpacs-dialog-slot-show)
                       (lambda (id _spec &rest keys)
                         (push (cons id (plist-get keys :on-conclude)) concluders)
                         id))
                      ((symbol-function 'jetpacs-app-defer-refresh)
                       (lambda (_params) (cl-incf refreshes)))
                      ((symbol-function 'jetpacs-shell-notify)
                       (lambda (text &rest _) (push text notes)))
                      ((symbol-function 'ebp-org-defer-save) #'ignore))
              (glasspane-timestamp-open ref "SCHEDULED" nil
                                        '(:surface "app:glasspane"))
              (setq glasspane-timestamp--session
                    (plist-put (plist-put glasspane-timestamp--session
                                          :date "2026-10-30")
                               :repeater "+1w"))
              (funcall (cdar concluders) "submitted"
                       '(:value "set"
                         :fields (:gp-ts-time-on t :gp-ts-repeater-on t))
                       nil)
              (with-current-buffer (find-file-noselect file)
                (let ((stamp (org-entry-get (point-min) "SCHEDULED")))
                  (should (string-prefix-p "<2026-10-30 Fri " stamp))
                  (should (string-search "+1w>" stamp))
                  (should (string-match-p " [0-9][0-9]:[0-9][0-9] " stamp))))
              (should-not glasspane-timestamp--session)
              (should (= refreshes 1))
              (should (cl-some (lambda (n) (string-prefix-p "Scheduled " n)) notes))
              ;; Clear.
              (glasspane-timestamp-open ref "SCHEDULED" "<2026-10-30 Fri>"
                                        '(:surface "app:glasspane"))
              (funcall (cdar concluders) "submitted" '(:value "clear") nil)
              (with-current-buffer (find-file-noselect file)
                (should-not (org-entry-get (point-min) "SCHEDULED")))
              (should (= refreshes 2))
              ;; A dismissal writes nothing.
              (glasspane-timestamp-open ref "DEADLINE" nil
                                        '(:surface "app:glasspane"))
              (funcall (cdar concluders) "dismissed" nil nil)
              (should (= refreshes 2)))))
      (setq glasspane-timestamp--session nil)
      (dolist (b (buffer-list))
        (when (equal (buffer-file-name b) file)
          (with-current-buffer b (set-buffer-modified-p nil))
          (kill-buffer b)))
      (delete-directory dir t))))

(ert-deftest glasspane-timestamp-test-period-picker-sets-the-cookie ()
  "The picker's OK writes a validated cookie and switches its row on."
  (let ((shown 0) (period nil))
    (cl-letf (((symbol-function 'jetpacs-client) (lambda () 'client))
              ;; No live welcome: the picker takes its enum-list fallbacks.
              ((symbol-function 'jetpacs-node-advertised-p) (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-dialog-slot-show)
               (lambda (id &rest _) (cl-incf shown) id))
              ((symbol-function 'glasspane-timestamp--show-period)
               (lambda (id spec callback)
                 (setq period (list id spec callback))
                 id)))
      (glasspane-timestamp-open 'ref "SCHEDULED" nil '(:surface "app:glasspane"))
      (let ((params (list :dialog_id
                          (plist-get glasspane-timestamp--session :dialog-id))))
        (should (eq (glasspane-timestamp--on-part '(:part "repeater") params)
                    'accepted)))
      (should period)
      (should (jetpacs-check-profile (nth 1 period) 'dialog))
      ;; Junk is refused and changes nothing.
      (funcall (nth 2 period) "submitted"
               '(:fields (:gp-period-type "+" :gp-period-n "x" :gp-period-unit "w"))
               nil)
      (should (equal (plist-get glasspane-timestamp--session :repeater) ".+1w"))
      (should-not (plist-get glasspane-timestamp--session :repeater-on))
      (funcall (nth 2 period) "submitted"
               '(:fields (:gp-period-type "++" :gp-period-n "2" :gp-period-unit "d"))
               nil)
      (should (equal (plist-get glasspane-timestamp--session :repeater) "++2d"))
      (should (plist-get glasspane-timestamp--session :repeater-on))
      (should (= shown 2))
      ;; A deadline's warning has one type; the picker needs no type field.
      (setq glasspane-timestamp--session
            (plist-put glasspane-timestamp--session :which "DEADLINE"))
      (let ((params (list :dialog_id
                          (plist-get glasspane-timestamp--session :dialog-id))))
        (should (eq (glasspane-timestamp--on-part '(:part "delay") params)
                    'accepted)))
      (funcall (nth 2 period) "submitted"
               '(:fields (:gp-period-n "3" :gp-period-unit "d")) nil)
      (should (equal (plist-get glasspane-timestamp--session :delay) "-3d"))
      (should (plist-get glasspane-timestamp--session :delay-on)))
    (setq glasspane-timestamp--session nil)))

(ert-deftest glasspane-timestamp-test-lifecycle-is-symmetric ()
  "The verb registers under Glasspane and leaves with it."
  (should (equal (jetpacs--owner-of "action" "glasspane.ts.part") "glasspane"))
  (unwind-protect
      (progn
        (glasspane-timestamp-unregister)
        (should-not (gethash "glasspane.ts.part" jetpacs-action-handlers)))
    (glasspane-timestamp-register))
  (should (gethash "glasspane.ts.part" jetpacs-action-handlers)))

(provide 'glasspane-timestamp-test)
;;; glasspane-timestamp-test.el ends here
