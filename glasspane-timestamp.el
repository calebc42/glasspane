;;; glasspane-timestamp.el --- The planning timestamp dialog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Scheduling a heading in Glasspane: one dialog that shows the whole stamp
;; and lets each part be set in a tap or two, lifted from Orgzly Native's
;; Revived-shaped timestamp dialog and dressed in Material.
;;
;; The day is a date button over Today / Tomorrow / Next week chips; the
;; time and end time are time buttons behind switches; the repeater and the
;; delay (a warning period on a deadline) are switches beside a chip that
;; says the cookie in words and opens a small period picker over the
;; dialog.  Clear, Cancel and Set close it.  Every pick re-shows the dialog
;; under a fresh id with the switches captured, so what the user ticked
;; survives the round trip; a pick from a superseded dialog answers
;; `stale'.
;;
;; The stamp itself is spelled and written by `ebp-org': `ebp-org-ts-parse'
;; seeds the parts, `ebp-org-ts-compose' spells the result and
;; `ebp-org-set-planning-stamp' writes it whole, so the repeater, delay and
;; end time survive the write that Org's own planning helpers would drop.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-material3)
(require 'jetpacs-shell)
(require 'jetpacs-apps)
(require 'jetpacs-dialog-slot)
(require 'jetpacs-dates)
(require 'glasspane-ui)

;;;; Session state (the handlers below are the only writers)

(defvar glasspane-timestamp--session nil
  "The open dialog's parts and target, or nil.
A plist: :ref and :which (\"SCHEDULED\"/\"DEADLINE\") name the heading
stamp; :params the opening event; :date, :time, :end, :repeater, :delay
the parts; :time-on, :end-on, :repeater-on, :delay-on whether each part
is written; :seq and :dialog-id the live dialog's identity.")

(defconst glasspane-timestamp--checks '(time-on end-on repeater-on delay-on)
  "The dialog's switches, each a part of `glasspane-timestamp--session'.")

(defun glasspane-timestamp-check-id (check)
  "The switch node id for CHECK, a symbol from `glasspane-timestamp--checks'."
  (format "gp-ts-%s" check))

(defconst glasspane-timestamp--capture
  (mapcar #'glasspane-timestamp-check-id glasspane-timestamp--checks)
  "The field ids every pick captures, so a re-show keeps the switches.")

(defconst glasspane-timestamp--repeater-re
  "\\`\\(?:\\.\\+\\|\\+\\+\\|\\+\\)[0-9]\\{1,4\\}[hdwmy]\\'"
  "A repeater cookie the dialog writes.")

(defconst glasspane-timestamp--delay-re "\\`--?[0-9]\\{1,4\\}[hdwmy]\\'"
  "A delay or warning cookie the dialog writes.")

;;;; Pure helpers: seeding, spelling, words

(defun glasspane-timestamp-seed (stamp &optional now)
  "The dialog parts for Org timestamp STAMP, or for NOW when it is empty.
Unset parts keep Orgzly's defaults: the current time, `.+1w' and `-1d',
switched off.  NOW defaults to the current time."
  (let* ((now (or now (current-time)))
         (hm (format-time-string "%H:%M" now))
         (parts (list :date (format-time-string "%Y-%m-%d" now)
                      :time hm :end hm :time-on nil :end-on nil
                      :repeater ".+1w" :repeater-on nil
                      :delay "-1d" :delay-on nil))
         (parsed (and (stringp stamp) (ebp-org-ts-parse stamp))))
    (when parsed
      (setq parts (plist-put parts :date (plist-get parsed :date)))
      (when-let* ((time (plist-get parsed :time)))
        (setq parts (plist-put (plist-put parts :time time) :time-on t))
        (setq parts (plist-put parts :end (or (plist-get parsed :end) time)))
        (when (plist-get parsed :end)
          (setq parts (plist-put parts :end-on t))))
      (when-let* ((rep (plist-get parsed :repeater)))
        (setq parts (plist-put (plist-put parts :repeater rep) :repeater-on t)))
      (when-let* ((warn (plist-get parsed :warning)))
        (setq parts (plist-put (plist-put parts :delay warn) :delay-on t))))
    parts))

(defun glasspane-timestamp-compose (session)
  "The active Org timestamp SESSION's switched-on parts spell, or nil."
  (ebp-org-ts-compose
   (list :date (plist-get session :date)
         :time (and (plist-get session :time-on) (plist-get session :time))
         :end (and (plist-get session :time-on) (plist-get session :end-on)
                   (plist-get session :end))
         :repeater (and (plist-get session :repeater-on)
                        (plist-get session :repeater))
         :warning (and (plist-get session :delay-on)
                       (plist-get session :delay)))))

(defun glasspane-timestamp--h23-p ()
  "Whether the device reads a 24-hour clock."
  (equal (plist-get (jetpacs-locale) :hour_cycle) "h23"))

(defun glasspane-timestamp-clock-words (hm)
  "HM (HH:MM) on the device's clock: \"10:11 AM\", or \"10:11\" on h23."
  (if (and (stringp hm) (string-match "\\`\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\'" hm))
      (let ((h (string-to-number (match-string 1 hm)))
            (m (match-string 2 hm)))
        (if (glasspane-timestamp--h23-p)
            (format "%02d:%s" h m)
          (format "%d:%s %s" (let ((x (% h 12))) (if (= x 0) 12 x)) m
                  (if (< h 12) "AM" "PM"))))
    (or hm "")))

(defun glasspane-timestamp-day-words (date &optional today)
  "DATE as the dialog names a day: \"Today · Fri 30 Oct\" or \"Mon 2 Nov\".
TODAY defaults to the current date."
  (or (glasspane-ui-day-words date today) (or date "")))

(defconst glasspane-timestamp--units
  '(("h" . "hour") ("d" . "day") ("w" . "week") ("m" . "month") ("y" . "year"))
  "Org interval unit letters and their singular nouns.")

(defun glasspane-timestamp--period-words (n unit &optional counted)
  "N (a string) UNITs in words: \"week\", \"2 weeks\"; COUNTED keeps \"1 day\"."
  (let ((noun (cdr (assoc unit glasspane-timestamp--units))))
    (cond ((and (equal n "1") (not counted)) noun)
          ((equal n "1") (concat "1 " noun))
          (t (format "%s %ss" n noun)))))

(defun glasspane-timestamp-cookie-words (cookie which)
  "COOKIE in words for a WHICH stamp, or COOKIE itself when unparsed.
A repeater: \"every week\", \"every 2 weeks, catching up\", \"every week
after done\".  A delay on a scheduled stamp: \"appears 1 day late\",
\"first time appears 1 day late\"; a warning on a deadline: \"warns 2
days before\"."
  (if (and (stringp cookie)
           (string-match "\\`\\([.+-]*\\)\\([0-9]+\\)\\([hdwmy]\\)\\'" cookie))
      (let* ((type (match-string 1 cookie))
             (n (match-string 2 cookie))
             (unit (match-string 3 cookie))
             (period (glasspane-timestamp--period-words n unit))
             (counted (glasspane-timestamp--period-words n unit t)))
        (pcase type
          ("+" (format "every %s" period))
          ("++" (format "every %s, catching up" period))
          (".+" (format "every %s after done" period))
          ("-" (if (equal which "DEADLINE")
                   (format "warns %s before" counted)
                 (format "appears %s late" counted)))
          ("--" (format "first time appears %s late" counted))
          (_ cookie)))
    (or cookie "")))

(defun glasspane-timestamp-title-words (session &optional today)
  "The dialog's caption: SESSION's day and every switched-on part, in words.
TODAY defaults to the current date."
  (let ((which (plist-get session :which)))
    (string-join
     (delq nil
           (list (glasspane-timestamp-day-words (plist-get session :date) today)
                 (and (plist-get session :time-on)
                      (concat (glasspane-timestamp-clock-words
                               (plist-get session :time))
                              (and (plist-get session :end-on)
                                   (concat "–" (glasspane-timestamp-clock-words
                                                (plist-get session :end))))))
                 (and (plist-get session :repeater-on)
                      (glasspane-timestamp-cookie-words
                       (plist-get session :repeater) which))
                 (and (plist-get session :delay-on)
                      (glasspane-timestamp-cookie-words
                       (plist-get session :delay) which))))
     " · ")))

;;;; The dialog

(defun glasspane-timestamp--part (part &rest more)
  "The action setting PART of the open dialog, with MORE args.
It captures the switches, so the handler sees what the user ticked."
  (jetpacs-action "glasspane.ts.part"
                  :args (append (list :part part) more)
                  :when-offline "drop"
                  :capture-fields glasspane-timestamp--capture))

(defun glasspane-timestamp--switch (check session &optional disabled)
  "The switch for CHECK of SESSION; DISABLED greys it out.
Flipping it reports the switches, so the title and enablement follow."
  (jetpacs-switch (glasspane-timestamp-check-id check)
                  :checked (if (plist-get session (intern (format ":%s" check)))
                               t :json-false)
                  :on-change (glasspane-timestamp--part "checks")
                  :enabled (if disabled :json-false t)))

(defun glasspane-timestamp--label (text)
  "TEXT as a section label inside the dialog."
  (jetpacs-text text :style "label" :color "primary"))

(defun glasspane-timestamp--quick-chip (label when session today)
  "A chip moving the day to WHEN (\"+0d\", \"+1d\", \"+1w\") from TODAY."
  (jetpacs-chip label
                :selected (jetpacs-bool
                           (equal (plist-get session :date)
                                  (jetpacs-org-relative-date today when)))
                :on-tap (glasspane-timestamp--part "day" :when when)))

(defun glasspane-timestamp--cookie-row (check part session)
  "The switch for CHECK beside a chip saying PART's cookie; the chip picks."
  (let ((which (plist-get session :which))
        (cookie (plist-get session (intern (format ":%s" part)))))
    (jetpacs-row
     (glasspane-timestamp--switch check session)
     (jetpacs-with-attrs
      (jetpacs-material3-assist-chip
       (glasspane-timestamp-cookie-words cookie which)
       :icon (if (equal part "repeater") "repeat" "schedule")
       :on-tap (glasspane-timestamp--part part))
      :weight 1)
     :align "center" :spacing 12 :fill t)))

(defun glasspane-timestamp-dialog (session &optional today)
  "The timestamp dialog for SESSION, seen from ISO TODAY.
Day, times, repeater and delay as Material controls, each optional part
behind a switch; Clear, Cancel and Set below."
  (let* ((today (or today (format-time-string "%Y-%m-%d")))
         (which (plist-get session :which))
         (deadline (equal which "DEADLINE"))
         (time-on (plist-get session :time-on)))
    (jetpacs-column
     (jetpacs-text (if deadline "Deadline" "Scheduled") :style "title")
     (jetpacs-text (glasspane-timestamp-title-words session today)
                   :style "caption" :color "outline")
     (jetpacs-spacer :height 4)
     (glasspane-timestamp--label "Day")
     (jetpacs-with-attrs
      (jetpacs-date-button (glasspane-timestamp-day-words
                            (plist-get session :date) today)
                           (glasspane-timestamp--part "date")
                           :value (plist-get session :date))
      :fill_fraction 1)
     (jetpacs-row
      (glasspane-timestamp--quick-chip "Today" "+0d" session today)
      (glasspane-timestamp--quick-chip "Tomorrow" "+1d" session today)
      (glasspane-timestamp--quick-chip "Next week" "+1w" session today)
      :spacing 6 :scroll t)
     (jetpacs-spacer :height 4)
     (jetpacs-row
      (jetpacs-with-attrs (glasspane-timestamp--label "Time") :weight 1)
      (jetpacs-with-attrs (glasspane-timestamp--label "End time") :weight 1)
      :fill t :spacing 12)
     (jetpacs-row
      (glasspane-timestamp--switch 'time-on session)
      (jetpacs-with-attrs
       (jetpacs-time-button (glasspane-timestamp-clock-words
                             (plist-get session :time))
                            (glasspane-timestamp--part "time")
                            :value (plist-get session :time))
       :weight 1)
      (glasspane-timestamp--switch 'end-on session (not time-on))
      (jetpacs-with-attrs
       (jetpacs-time-button (glasspane-timestamp-clock-words
                             (plist-get session :end))
                            (glasspane-timestamp--part "end")
                            :value (plist-get session :end)
                            :enabled (if time-on t :json-false))
       :weight 1)
      :align "center" :spacing 8 :fill t)
     (jetpacs-spacer :height 4)
     (glasspane-timestamp--label "Repeat")
     (glasspane-timestamp--cookie-row 'repeater-on "repeater" session)
     (glasspane-timestamp--label (if deadline "Warning" "Delay"))
     (glasspane-timestamp--cookie-row 'delay-on "delay" session)
     (jetpacs-spacer :height 8)
     (jetpacs-row
      (jetpacs-button "Clear" (jetpacs-dialog-submit :value "clear")
                      :variant "text" :icon "close")
      (jetpacs-spacer :weight 1)
      (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
      (jetpacs-button "Set"
                      (jetpacs-dialog-submit
                       :value "set"
                       :capture-fields glasspane-timestamp--capture)
                      :variant "filled")
      :align "center" :spacing 8 :fill t)
     :spacing 8)))

;;;; The period picker (a second dialog over the first)

(defun glasspane-timestamp-period-kind (part which)
  "What the period picker asks for PART of a WHICH stamp.
A plist: :title, :description and :types, the cookie prefixes offered
with their labels.  A deadline's delay is a warning period."
  (cond
   ((equal part "repeater")
    '(:title "Repeat"
      :description "After the task is marked done, the repeater shifts its time."
      :types (("+" . "Add period")
              ("++" . "Catch up to the future")
              (".+" . "From the day it's done"))))
   ((equal which "DEADLINE")
    '(:title "Warning period"
      :description "How long before the deadline the agenda warns about it."
      :types (("-" . "Before"))))
   (t
    '(:title "Delay"
      :description "How long after the scheduled day the task appears in the agenda."
      :types (("-" . "Every occurrence")
              ("--" . "First occurrence only"))))))

(defun glasspane-timestamp--cookie-parts (part cookie)
  "COOKIE of PART split as (TYPE N UNIT), with the dialog's defaults."
  (if (and (stringp cookie)
           (string-match "\\`\\([.+-]*\\)\\([0-9]+\\)\\([hdwmy]\\)\\'" cookie))
      (list (match-string 1 cookie) (match-string 2 cookie)
            (match-string 3 cookie))
    (if (equal part "repeater") '(".+" "1" "w") '("-" "1" "d"))))

(defun glasspane-timestamp-period-dialog (kind type n unit)
  "The period picker for KIND (`glasspane-timestamp-period-kind').
TYPE, N and UNIT seed the controls; OK submits capturing them."
  (let* ((types (plist-get kind :types))
         (type-options (mapcar (lambda (c) (jetpacs-enum-option (cdr c) (car c)))
                               types))
         (unit-options (mapcar (lambda (u)
                                 (jetpacs-enum-option
                                  (concat (upcase (substring (cdr u) 0 1))
                                          (substring (cdr u) 1) "s")
                                  (car u)))
                               glasspane-timestamp--units)))
    (apply
     #'jetpacs-column
     (delq nil
           (list
            (jetpacs-text (plist-get kind :title) :style "title")
            (jetpacs-text (plist-get kind :description)
                          :style "caption" :color "outline")
            (jetpacs-spacer :height 4)
            (when (cdr types)
              (if (jetpacs-node-advertised-p "segmented_button" :dialog)
                  (jetpacs-segmented-button "gp-period-type" type-options
                                            :value type)
                (jetpacs-enum-list "gp-period-type" type-options :value type)))
            (jetpacs-row
             (jetpacs-with-attrs
              (jetpacs-text-input "gp-period-n" :value n :label "Every"
                                  :keyboard "number" :single-line t)
              :weight 1)
             (jetpacs-with-attrs
              (if (jetpacs-node-advertised-p "dropdown" :dialog)
                  (jetpacs-dropdown "gp-period-unit" unit-options :value unit
                                    :label "Unit")
                (jetpacs-enum-list "gp-period-unit" unit-options :value unit))
              :weight 1)
             :align "center" :spacing 12 :fill t)
            (jetpacs-spacer :height 8)
            (jetpacs-row
             (jetpacs-spacer :weight 1)
             (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
             (jetpacs-button "OK"
                             (jetpacs-dialog-submit
                              :value "ok"
                              ;; Only fields the dialog draws are captured.
                              :capture-fields (append
                                               (and (cdr types)
                                                    '("gp-period-type"))
                                               '("gp-period-n" "gp-period-unit")))
                             :variant "filled")
             :align "center" :spacing 8 :fill t)
            :spacing 8)))))

(defun glasspane-timestamp--show-period (id spec callback)
  "Show SPEC as dialog ID over the open dialog; CALLBACK takes its conclusion.
The one seam to the client's stacked dialog, so tests can stand in for it."
  (when-let* ((client (jetpacs-client)))
    (ebp-client-dialog-show client id spec :callback callback)))

(defun glasspane-timestamp--ask-period (part)
  "Open the period picker for PART of the open dialog.
It shows over the timestamp dialog; the pick re-shows that dialog."
  (pcase-let* ((session glasspane-timestamp--session)
               (which (plist-get session :which))
               (key (intern (concat ":" part)))
               (on-key (intern (concat ":" part "-on")))
               (kind (glasspane-timestamp-period-kind part which))
               (`(,type ,n ,unit)
                (glasspane-timestamp--cookie-parts part (plist-get session key)))
               (types (mapcar #'car (plist-get kind :types)))
               (type (if (member type types) type (car types))))
    (glasspane-timestamp--show-period
     (jetpacs-wire-id "gp-ts-period" part)
     (glasspane-timestamp-period-dialog kind type n unit)
     (lambda (status result _error)
         (let* ((fields (plist-get result :fields))
                (type (if (cdr types)
                          (or (plist-get fields :gp-period-type) type)
                        (car types)))
                (n (or (plist-get fields :gp-period-n) n))
                (unit (or (plist-get fields :gp-period-unit) unit))
                (cookie (and (stringp type) (stringp n) (stringp unit)
                             (concat type (string-trim n) unit))))
           (when (and glasspane-timestamp--session
                      (equal status "submitted")
                      cookie
                      (member type types)
                      (string-match-p (if (equal part "repeater")
                                          glasspane-timestamp--repeater-re
                                        glasspane-timestamp--delay-re)
                                      cookie))
             (setq glasspane-timestamp--session
                   (plist-put (plist-put glasspane-timestamp--session key cookie)
                              on-key t))
             (glasspane-timestamp--show)))))))

;;;; Showing, picking, concluding

(defun glasspane-timestamp--merge-checks (fields)
  "Fold the captured switch FIELDS into the session."
  (dolist (check glasspane-timestamp--checks)
    (let ((value (plist-get fields (intern (concat ":" (glasspane-timestamp-check-id check))))))
      (when (memq value '(t :json-false))
        (setq glasspane-timestamp--session
              (plist-put glasspane-timestamp--session
                         (intern (format ":%s" check)) (eq value t)))))))

(defun glasspane-timestamp--show ()
  "Show the session as the timestamp dialog under a fresh id.
A pick re-shows it, so the request it replaces concludes unanswered and
only the current dialog may conclude the session."
  (let* ((seq (1+ (or (plist-get glasspane-timestamp--session :seq) 0)))
         (id (jetpacs-wire-id "gp-ts" (number-to-string seq))))
    (setq glasspane-timestamp--session
          (plist-put (plist-put glasspane-timestamp--session :seq seq)
                     :dialog-id id))
    (with-jetpacs-owner "glasspane"
      (jetpacs-dialog-slot-show
       id (glasspane-timestamp-dialog glasspane-timestamp--session)
       :params (plist-get glasspane-timestamp--session :params)
       :on-conclude
       (lambda (status result _error)
         (when (and (equal status "submitted")
                    (equal (plist-get glasspane-timestamp--session :dialog-id)
                           id))
           (glasspane-timestamp--merge-checks (plist-get result :fields))
           (glasspane-timestamp--conclude (plist-get result :value))))))))

(defun glasspane-timestamp--conclude (value)
  "Apply the submitted VALUE, \"set\" or \"clear\", to the heading."
  (let* ((session glasspane-timestamp--session)
         (ref (plist-get session :ref))
         (which (plist-get session :which))
         (params (plist-get session :params))
         (stamp (and (equal value "set")
                     (glasspane-timestamp-compose session))))
    (setq glasspane-timestamp--session nil)
    (when (or (equal value "clear") stamp)
      (condition-case err
          (progn
            (ebp-org-set-planning-stamp ref 'glasspane which stamp)
            (jetpacs-shell-notify
             (if stamp
                 (format "%s %s" (if (equal which "DEADLINE") "Due" "Scheduled")
                         (glasspane-timestamp-title-words
                          (append (list :which which)
                                  (glasspane-timestamp-seed stamp))))
               (format "%s cleared" (if (equal which "DEADLINE")
                                        "Deadline" "Schedule")))
             (plist-get params :surface)))
        ((ebp-org-refused ebp-org-unresolved)
         (jetpacs-shell-notify "That heading is gone" (plist-get params :surface)))
        (error
         (message "glasspane: timestamp %s failed: %s"
                  value (jetpacs-error-label err))
         (jetpacs-shell-notify "That did not work" (plist-get params :surface))))
      (jetpacs-app-defer-refresh params))))

(defun glasspane-timestamp-open (ref which stamp params)
  "Open the dialog on REF's WHICH planning stamp, seeded from STAMP.
PARAMS is the opening event; the conclusion refreshes its surface."
  (setq glasspane-timestamp--session
        (append (list :ref ref :which which :params params)
                (glasspane-timestamp-seed stamp)))
  (glasspane-timestamp--show))

(defun glasspane-timestamp--on-part (args params)
  "Set ARGS' `:part' of the open dialog and show it again.
Picks inject `:value'; the day chips name `:when'.  Every pick captures
the switches into PARAMS and must come from the dialog on screen."
  (let* ((part (plist-get args :part))
         (value (plist-get args :value))
         (today (format-time-string "%Y-%m-%d"))
         (hm (and (stringp value)
                  (string-match "\\`\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\'" value)
                  (format "%02d:%s" (string-to-number (match-string 1 value))
                          (match-string 2 value)))))
    (cond
     ((null glasspane-timestamp--session) 'stale)
     ((not (equal (plist-get params :dialog_id)
                  (plist-get glasspane-timestamp--session :dialog-id)))
      'stale)
     (t
      (glasspane-timestamp--merge-checks (plist-get params :fields))
      (cl-flet ((put (&rest pairs)
                  (cl-loop for (k v) on pairs by #'cddr
                           do (setq glasspane-timestamp--session
                                    (plist-put glasspane-timestamp--session k v)))))
        (let ((outcome
               (pcase part
                 ("date" (when (jetpacs-dates-valid-p value)
                           (put :date value) 'show))
                 ("day" (when-let* ((date (jetpacs-org-relative-date
                                           today (plist-get args :when))))
                          (put :date date) 'show))
                 ("time" (when hm (put :time hm :time-on t) 'show))
                 ("end" (when hm (put :end hm :end-on t) 'show))
                 ("checks" 'show)
                 ((or "repeater" "delay")
                  (glasspane-timestamp--ask-period part) 'asked))))
          (pcase outcome
            ('show (jetpacs-flow-continue #'glasspane-timestamp--show) 'accepted)
            ('asked 'accepted)
            (_ 'rejected))))))))

;;;; Lifecycle

(defconst glasspane-timestamp--verbs '("glasspane.ts.part")
  "The verbs this module owns.")

(defun glasspane-timestamp-register ()
  "Register the dialog's pick verb, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "glasspane.ts.part" #'glasspane-timestamp--on-part
                       :doc "Set one part of the open timestamp dialog"
                       :strict t
                       :args '((:name part :type "text" :required t)
                               (:name value :type "text")
                               (:name when :type "text")))))

(defun glasspane-timestamp-unregister ()
  "Drop the dialog's verb and forget any open session."
  (dolist (name glasspane-timestamp--verbs)
    (jetpacs-undefaction name))
  (setq glasspane-timestamp--session nil))

(provide 'glasspane-timestamp)
;;; glasspane-timestamp.el ends here
