;;; jetpacs-org-habits.el --- The habits screen (JA-5) -*- lexical-binding: t; -*-

;;; Commentary:

;; org-habit's consistency graph as a phone screen (poc 1696-1895
;; rebuilt).  The desktop shows the graph only inside an agenda; the
;; phone has no agenda, so the habits get their own chrome surface —
;; owner `jetpacs.org', the base-owned-screen precedent (`jetpacs.clip').
;;
;; Data comes from org-habit itself (`org-habit-parse-todo',
;; `org-habit-build-graph') over a window sized to a phone width:
;; `jetpacs-org-habit-preceding-days' + today +
;; `jetpacs-org-habit-following-days' cells, colors resolved from the
;; graph's own faces through the base color machinery so user
;; `org-habit-*-face' customization flows through.  A broken habit (a
;; `:STYLE: habit' heading whose repeater rots) passes `org-is-habit-p'
;; but makes `org-habit-parse-todo' SIGNAL — it is skipped, never
;; fatal.  The file walk derives from `ebp-org-agenda-files' and
;; NEVER calls `org-agenda-files' or `org-map-entries' with the
;; `agenda' scope — the raw walk stats remote names inside the socket
;; filter (JA-4 audit P1-7) and a missing file drives
;; `read-char-exclusive' (P1-5); a grep-pinned test keeps it that way.
;;
;; The strip is ONE canvas node (long histories serialize and pan as
;; one image, the poc's call), its ops spent against `max_canvas_ops'
;; (A2) — a refused spend drops the strip, never the push.  DONE rides
;; a durable descriptor (queue + ttl + per-habit dedupe: marking a
;; habit done must survive a tunnel) through
;; `ebp-org-toggle-todo', whose inline log-note flush writes the
;; `- State "DONE"' line `org-habit-done-dates' counts; the `++'
;; catch-up path can PROMPT (`org-auto-repeat-maybe', JA-4 audit P1-6,
;; open) — the handler catches `inhibited-interaction' and answers a
;; loud `rejected' instead of wedging.  Refs cross the wire as D-4
;; tokens, set "habits", replace-swept per build.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-habit)
(require 'ebp-org)
(require 'jetpacs-org)                  ; NOT the engine: the shim, for its load
                                        ; effect — it registers the engine's token
                                        ; sweep on `jetpacs-teardown-functions'
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-navigate)

;; Soft-coupled (the files precedent): embedded only when loaded.
(declare-function jetpacs-launcher-button "jetpacs-launcher")

(defconst jetpacs-org-habits-owner "jetpacs.org"
  "The owner whose surface hosts the habits screen.")

(defcustom jetpacs-org-habit-preceding-days 21
  "History days in the strip.  Deliberately independent of
`org-habit-preceding-days' — the phone fits fewer cells."
  :type 'integer :group 'jetpacs-org)

(defcustom jetpacs-org-habit-following-days 7
  "Future days in the strip."
  :type 'integer :group 'jetpacs-org)

;;;; Data

(defun jetpacs-org-habits--face-hex (face)
  "FACE's background as wire hex, or nil when unresolvable."
  (let ((face (if (consp face) (car face) face)))
    (when face
      (jetpacs-buffer--color-hex
       (face-attribute face :background nil t)))))

(defun jetpacs-org-habits--graph (habit)
  "HABIT's consistency cells: a list of (:glyph CHAR :color HEX)."
  (let* ((now (current-time))
         (graph (org-habit-build-graph
                 habit
                 (time-subtract
                  now (days-to-time jetpacs-org-habit-preceding-days))
                 now
                 (time-add
                  now (days-to-time jetpacs-org-habit-following-days)))))
    (cl-loop for i from 0 below (length graph)
             collect (list :glyph (aref graph i)
                           :color (jetpacs-org-habits--face-hex
                                   (get-text-property i 'face graph))))))

(defun jetpacs-org-habits--collect ()
  "Every habit across the LOCAL agenda files, memoised.
Each item: (:ref R :title S :todo K :done-today BOOL :cells CELLS)."
  (ebp-org-with-cache 'habits "all"
    (let (out)
      (dolist (file (ebp-org-agenda-files))
        (when (and (stringp file) (file-readable-p file))
          (with-current-buffer (find-file-noselect file t)
            (unless (derived-mode-p 'org-mode) (org-mode))
            (org-with-wide-buffer
             (org-map-entries
              (lambda ()
                (when (org-is-habit-p)
                  ;; ignore-errors at BOTH levels: one rotten habit is
                  ;; skipped, never fatal to the screen.
                  (when-let* ((habit (ignore-errors
                                       (org-habit-parse-todo)))
                              (cells (ignore-errors
                                       (jetpacs-org-habits--graph habit))))
                    (let ((comps (org-heading-components)))
                      (push (list :ref (ebp-org-ref-at-point)
                                  :title (or (nth 4 comps) "")
                                  :todo (nth 2 comps)
                                  :done-today
                                  (and (memq (org-today)
                                             (org-habit-done-dates habit))
                                       t)
                                  :cells cells)
                            out))))))))))
      (nreverse out))))

;;;; Rendering

(cl-defun jetpacs-org-habits--strip (cells &key (cell-width 6) (height 12)
                                           (gap 2))
  "CELLS as ONE canvas of filled rects, or nil when nothing renders.
Ops are spent against the A2 `max_canvas_ops' aggregate; a refused
spend (or a batch session whose faces resolve no colors) drops the
strip rather than the push.  No corner radius — SPEC 17.5's `rect'
has none."
  (let ((ops (delq nil
                   (cl-loop for c in cells and i from 0
                            collect
                            (when-let* ((color (plist-get c :color)))
                              (jetpacs-canvas-rect
                               (* i (+ cell-width gap)) 0
                               cell-width height
                               :fill color))))))
    (when (and ops
               (jetpacs-node-advertised-p "canvas")
               (jetpacs-buffer-spend-limit :max_canvas_ops (length ops)))
      (jetpacs-canvas (* (length cells) (+ cell-width gap)) height ops))))

(defun jetpacs-org-habits--card (item token)
  "One habit card: title, Done affordance, the strip, the TODO caption."
  (jetpacs-with-attrs
   (jetpacs-card
    (jetpacs-column
     (apply #'jetpacs-row
            (append
             (list (jetpacs-with-attrs
                    (jetpacs-text (jetpacs-scalar-text
                                   (plist-get item :title))
                                  :style "label")
                    :weight 1))
             (if (plist-get item :done-today)
                 (list (jetpacs-text "Done ✓" :style "caption"))
               (list (jetpacs-button
                      "Done"
                      (jetpacs-action "jetpacs.org.habit.done"
                                      :args (list :token token)
                                      :when-offline "queue"
                                      :ttl-s 43200
                                      :dedupe (concat "hd-" token))
                      :variant "tonal")))
             (list :align "center" :spacing 8)))
     (or (jetpacs-org-habits--strip (plist-get item :cells))
         (jetpacs-divider))
     (when-let* ((todo (plist-get item :todo)))
       (jetpacs-text (jetpacs-scalar-text todo) :style "caption")))
    :on-tap (jetpacs-action "jetpacs.org.habit.open"
                            :args (list :token token)))
   :key (jetpacs-wire-id "habit" token)))

(defun jetpacs-org-habits--screen (back)
  "Builder for the habits root screen."
  (let* ((items (jetpacs-org-habits--collect))
         (tokens (and items
                      (ebp-org-ref-tokens
                       (mapcar (lambda (i) (plist-get i :ref)) items)
                       :set "habits" :owner jetpacs-org-habits-owner))))
    (jetpacs-chrome-screen
     "Habits"
     (if (null items)
         (jetpacs-empty-state
          :icon "repeat" :title "No habits"
          :caption "Give a repeating TODO the :STYLE: habit property")
       (apply #'jetpacs-lazy-column
              (append (cl-mapcar #'jetpacs-org-habits--card items tokens)
                      (list :spacing 8))))
     :back back
     :actions (when (featurep 'jetpacs-launcher)
                (list (jetpacs-launcher-button))))))

;;;; The verbs (owner-scoped: the habits surface is theirs alone)

(defun jetpacs-org-habits--done (args params)
  "Mark the habit the TOKEN names DONE; SPEC 14.4 status.
The toggle advances the repeater and flushes the `- State' line the
graph counts.  A `++' catch-up can prompt (P1-6, open) — under the
dispatch extent that signals `inhibited-interaction', answered as a
loud `rejected'."
  (let ((token (plist-get args :token)))
    (cond
     ((not (stringp token)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t
      (let ((ref (ebp-org-token-ref
                  token :owner jetpacs-org-habits-owner)))
        (if (null ref)
            'stale
          (condition-case err
              (progn
                (ebp-org-toggle-todo ref 'habits "DONE")
                (jetpacs-shell-notify "Habit done"
                                      (plist-get params :surface))
                (jetpacs-buffer-defer-refresh (plist-get params :surface))
                'accepted)
            (ebp-org-unresolved 'stale)
            (ebp-org-refused 'rejected)
            (error
             (message "jetpacs-org-habits: done failed: %s"
                      (jetpacs-error-label err))
             (jetpacs-shell-notify "That needs the desktop (a prompt)"
                                   (plist-get params :surface))
             'rejected))))))))

(defun jetpacs-org-habits--open (args params)
  "Drill into the habit's buffer (it renders through the org skin)."
  (let ((token (plist-get args :token)))
    (cond
     ((not (stringp token)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t
      (let ((ref (ebp-org-token-ref
                  token :owner jetpacs-org-habits-owner)))
        (if (null ref)
            'stale
          (condition-case nil
              (let ((m (ebp-org-resolve-ref ref)))
                (jetpacs-flow-continue
                 (lambda ()
                   (unwind-protect
                       (jetpacs-navigate-buffer (marker-buffer m))
                     (set-marker m nil))))
                'accepted)
            (ebp-org-unresolved 'stale)
            (ebp-org-refused 'rejected))))))))

(with-jetpacs-owner jetpacs-org-habits-owner
  (jetpacs-defaction "jetpacs.org.habit.done" #'jetpacs-org-habits--done)
  (jetpacs-defaction "jetpacs.org.habit.open" #'jetpacs-org-habits--open)
  (jetpacs-chrome-define-root jetpacs-org-habits-owner "habits"
                              #'jetpacs-org-habits--screen))

(defun jetpacs-org-habits ()
  "Push the habits screen to the device."
  (interactive)
  (jetpacs-shell-push jetpacs-org-habits-owner))

;;;; Reset / unload

(defun jetpacs-org-habits-reset ()
  "Reset habits-module state (the test seam).
The module keeps none of its own — the memo lives in the org cache
namespace `habits' and the tokens in the engine's table — but the
reset ladder names this function so future state has a home."
  nil)

(defun jetpacs-org-habits-unload-function ()
  "Unload hygiene: deregister the verbs and the chrome root."
  (jetpacs-undefaction "jetpacs.org.habit.done")
  (jetpacs-undefaction "jetpacs.org.habit.open")
  (jetpacs-chrome-remove jetpacs-org-habits-owner)
  nil)

(provide 'jetpacs-org-habits)
;;; jetpacs-org-habits.el ends here
