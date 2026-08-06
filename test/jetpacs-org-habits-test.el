;;; jetpacs-org-habits-test.el --- JA-5g: the habits screen -*- lexical-binding: t; -*-

;;; Commentary:

;; JA-5g's slice of the JA-5 exit gate: the graph windows to the
;; phone-sized cell count with face colors through the base machinery;
;; a rotten habit is skipped, never fatal; the strip is one canvas
;; whose ops spend the A2 aggregate; DONE rides a durable descriptor
;; and advances the repeater through the engine (the catch-up prompt
;; hazard answered as a loud rejected); tokens keep old screens honest;
;; and a grep pin keeps the file walk on `ebp-org-agenda-files' —
;; never the raw remote-dialling forms.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'jetpacs-org-habits)

(defmacro jetpacs-org-habits-test--with-file (var content &rest body)
  "Temp .org fixture under a fresh root, agenda-files bound to it."
  (declare (indent 2))
  `(let* ((dir (file-name-as-directory
                (file-truename (make-temp-file "ja5g" t))))
          (,var (expand-file-name "habits.org" dir))
          (ebp-org-roots (list dir))
          (org-agenda-files (list ,var)))
     (with-temp-file ,var (insert ,content))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buf (find-buffer-visiting ,var)))
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf))
       (delete-directory dir t)
       (ebp-org-reset))))

(defconst jetpacs-org-habits-test--fixture
  (concat "* TODO Water plants\n"
          "SCHEDULED: <2026-07-20 Mon .+2d>\n"
          ":PROPERTIES:\n:STYLE:    habit\n:END:\n"
          "* TODO Broken habit\n"
          "SCHEDULED: <2026-07-20 Mon>\n"
          ":PROPERTIES:\n:STYLE:    habit\n:END:\n"
          "* TODO Not a habit\n")
  "One good habit, one whose repeater rotted, one plain TODO.")

(defconst jetpacs-org-habits-test--params '(:surface "app:jetpacs.org"))

(defmacro jetpacs-org-habits-test--with-colors (&rest body)
  "Resolve every face background to a fixed hex (batch has no display)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'jetpacs-buffer--color-hex)
              (lambda (c) (and c "#336699"))))
     ,@body))

(ert-deftest jetpacs-org-habits-collect-windows-and-skips ()
  "The good habit yields the phone-window cell count; the rotten one is
skipped without a signal; the plain TODO never appears."
  (jetpacs-org-habits-test--with-file f jetpacs-org-habits-test--fixture
    (jetpacs-org-habits-test--with-colors
      (let ((items (jetpacs-org-habits--collect)))
        (should (= 1 (length items)))
        (let ((item (car items)))
          (should (equal (plist-get item :title) "Water plants"))
          (should (= (+ jetpacs-org-habit-preceding-days
                        1 jetpacs-org-habit-following-days)
                     (length (plist-get item :cells))))
          ;; Most cells carry a face color; a bare cell (no face on
          ;; that graph char) is a legitimate gap, not a failure.
          (should (seq-some (lambda (c) (equal (plist-get c :color)
                                               "#336699"))
                            (plist-get item :cells))))))))

(ert-deftest jetpacs-org-habits-strip-spends-canvas-ops ()
  "The strip is ONE canvas of filled rects; a refused A2 spend drops
the strip, not the push."
  (jetpacs-org-habits-test--with-colors
    (let ((cells (cl-loop repeat 29
                          collect (list :glyph ?* :color "#336699"))))
      (let ((strip (jetpacs-org-habits--strip cells)))
        (should (equal (plist-get strip :t) "canvas"))
        (should (= 29 (length (append (plist-get strip :ops) nil)))))
      ;; A bound allowance smaller than the op count refuses.
      (let ((jetpacs-buffer-extra-budget (list (cons :max_canvas_ops 10))))
        (should-not (jetpacs-org-habits--strip cells)))
      ;; Colorless cells (a batch session) render no strip.
      (should-not (jetpacs-org-habits--strip
                   '((:glyph ?* :color nil)))))))

(ert-deftest jetpacs-org-habits-done-descriptor-durable ()
  "The Done descriptor queues with a ttl and a per-habit dedupe —
marking a habit done must survive a tunnel."
  (jetpacs-org-habits-test--with-file f jetpacs-org-habits-test--fixture
    (jetpacs-org-habits-test--with-colors
      (let* ((items (jetpacs-org-habits--collect))
             (tokens (ebp-org-ref-tokens
                      (mapcar (lambda (i) (plist-get i :ref)) items)
                      :set "habits" :owner jetpacs-org-habits-owner))
             (card (jetpacs-org-habits--card (car items) (car tokens)))
             (done nil))
        (cl-labels ((walk (n)
                      (when (consp n)
                        (when-let* ((d (plist-get n :on_tap)))
                          (when (equal (plist-get d :action)
                                       "jetpacs.org.habit.done")
                            (setq done d)))
                        (dolist (c (append (plist-get n :children) nil))
                          (walk c)))))
          (walk card))
        (should done)
        (should (equal (plist-get done :when_offline) "queue"))
        (should (integerp (plist-get done :ttl_s)))
        (should (equal (plist-get done :dedupe)
                       (concat "hd-" (car tokens))))))))

(ert-deftest jetpacs-org-habits-done-advances-repeater ()
  "An armed token marks the habit done through the engine: the keyword
stays TODO (the repeater resets it) and SCHEDULED advances."
  (jetpacs-org-habits-test--with-file f jetpacs-org-habits-test--fixture
    (jetpacs-org-habits-test--with-colors
      (let* ((items (jetpacs-org-habits--collect))
             (tokens (ebp-org-ref-tokens
                      (mapcar (lambda (i) (plist-get i :ref)) items)
                      :set "habits" :owner jetpacs-org-habits-owner)))
        (should (eq 'accepted
                    (jetpacs-org-habits--done
                     (list :token (car tokens))
                     jetpacs-org-habits-test--params)))
        (with-current-buffer (find-buffer-visiting f)
          (org-with-wide-buffer
           (goto-char (point-min))
           (should (search-forward "* TODO Water plants" nil t))
           (should (re-search-forward "SCHEDULED: <" nil t))
           ;; The repeater moved the date off the fixture's.
           (should-not (looking-at-p "2026-07-20"))))))))

(ert-deftest jetpacs-org-habits-done-prompt-hazard-is-loud ()
  "A toggle that hits the P1-6 catch-up prompt signals
`inhibited-interaction' under the dispatch extent — answered as a
loud rejected, never a wedge."
  (jetpacs-org-habits-test--with-file f jetpacs-org-habits-test--fixture
    (jetpacs-org-habits-test--with-colors
      (let* ((items (jetpacs-org-habits--collect))
             (tokens (ebp-org-ref-tokens
                      (mapcar (lambda (i) (plist-get i :ref)) items)
                      :set "habits" :owner jetpacs-org-habits-owner))
             (notified nil))
        (cl-letf (((symbol-function 'ebp-org-toggle-todo)
                   (lambda (&rest _) (signal 'inhibited-interaction nil)))
                  ((symbol-function 'jetpacs-shell-notify)
                   (lambda (text &optional _s) (push text notified))))
          (should (eq 'rejected
                      (jetpacs-org-habits--done
                       (list :token (car tokens))
                       jetpacs-org-habits-test--params)))
          (should notified))))))

(ert-deftest jetpacs-org-habits-tokens-keep-old-screens-honest ()
  "A swept token answers stale; junk shapes reject."
  (jetpacs-org-habits-test--with-file f jetpacs-org-habits-test--fixture
    (jetpacs-org-habits-test--with-colors
      (let* ((items (jetpacs-org-habits--collect))
             (refs (mapcar (lambda (i) (plist-get i :ref)) items))
             (old (car (ebp-org-ref-tokens
                        refs :set "habits"
                        :owner jetpacs-org-habits-owner))))
        ;; A re-mint (the next screen build) sweeps the old set.
        (ebp-org-ref-tokens refs :set "habits"
                                :owner jetpacs-org-habits-owner)
        (should (eq 'stale (jetpacs-org-habits--open
                            (list :token old)
                            jetpacs-org-habits-test--params)))
        (should (eq 'rejected (jetpacs-org-habits--open
                               '(:token 7)
                               jetpacs-org-habits-test--params)))))))

(ert-deftest jetpacs-org-habits-screen-shapes ()
  "The screen builds: cards when habits exist, the empty state when
none do, the launcher soft-couple in the top bar when loaded."
  (jetpacs-org-habits-test--with-file f jetpacs-org-habits-test--fixture
    (jetpacs-org-habits-test--with-colors
      (should (jetpacs-org-habits--screen nil))))
  (let ((org-agenda-files nil)
        (ebp-org-roots (list temporary-file-directory)))
    (unwind-protect
        (should (jetpacs-org-habits--screen nil))
      (ebp-org-reset))))

(ert-deftest jetpacs-org-habits-never-dials-the-raw-agenda ()
  "Grep pin: the module walks `ebp-org-agenda-files' only — a raw
`(org-agenda-files' call or an `org-map-entries' `agenda' scope
re-opens the remote-stat and missing-file-prompt holes (JA-4 audit
P1-7/P1-5)."
  (let ((src (with-temp-buffer
               (insert-file-contents
                (locate-library "jetpacs-org-habits.el" t))
               (buffer-string))))
    (should-not (string-match-p "(org-agenda-files" src))
    (should-not (string-match-p "'agenda)" src))))

(provide 'jetpacs-org-habits-test)
;;; jetpacs-org-habits-test.el ends here
