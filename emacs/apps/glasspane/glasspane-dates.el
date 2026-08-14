;;; glasspane-dates.el --- App-local date helpers for Glasspane -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The G5 date-helper module (docs/PLAN-glasspane-app.md):
;; jetpacs-date-format/-shift/-month-abbrev lived in the v1 CORE and
;; exist nowhere in v3 (FOUNDATION-GAPS #10), so the daily surfaces
;; carry their own — transliterated from the v1 core widgets file.
;; Pure string/time functions with no bridge dependency, so any layer
;; of the app may use them.

;;; Code:

(require 'calendar)

(defconst glasspane-dates--month-abbrevs
  ["Jan" "Feb" "Mar" "Apr" "May" "Jun"
   "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"]
  "Short ENGLISH month labels: card date chips must not follow the
desktop locale, or the same vault renders differently per machine.")

(defun glasspane-dates-month-abbrev (n)
  "The three-letter English abbreviation for month N (1 = Jan .. 12 = Dec).
Returns nil when N is not an integer in 1..12."
  (and (integerp n) (>= n 1) (<= n 12)
       (aref glasspane-dates--month-abbrevs (1- n))))

(defun glasspane-dates-encode (date)
  "Encoded noon of DATE (\"YYYY-MM-DD\"); noon dodges DST date flips.
Parses by position, never by regexp/split, so it is safe inside a
`replace-regexp-in-string' replacement function (match data intact)."
  (encode-time 0 0 12
               (string-to-number (substring date 8 10))
               (string-to-number (substring date 5 7))
               (string-to-number (substring date 0 4))))

(defun glasspane-dates-shift (date n unit)
  "Shift DATE (\"YYYY-MM-DD\") by N UNITs (`day', `week', or `month').
Month arithmetic clamps the day into the target month, so Jan 31 + 1
month is Feb 28, not an invalid date."
  (let ((y (string-to-number (substring date 0 4)))
        (m (string-to-number (substring date 5 7)))
        (d (string-to-number (substring date 8 10))))
    (if (eq unit 'month)
        (let* ((total (+ (* 12 y) (1- m) n))
               (ny (/ total 12))
               (nm (1+ (% total 12))))
          (format "%04d-%02d-%02d" ny nm
                  (min d (calendar-last-day-of-month nm ny))))
      (let ((days (* n (if (eq unit 'week) 7 1))))
        ;; Noon avoids DST-transition off-by-one-day surprises.
        (format-time-string "%Y-%m-%d"
                            (time-add (glasspane-dates-encode date)
                                      (* days 86400)))))))

(defun glasspane-dates-format (date fmt)
  "Render DATE (\"YYYY-MM-DD\") through `format-time-string' FMT."
  (format-time-string fmt (glasspane-dates-encode date)))

(provide 'glasspane-dates)
;;; glasspane-dates.el ends here
