;;; jetpacs-spike-rows.el --- THROWAWAY: measure a vault's flat-row projection -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; spike-elisp of PLAN-refound's data-spike rung.  Reads the live vulpea DB
;; read-only, projects every note into a FLAT ROW, serializes with the same
;; `json-serialize' the wire path uses, and reports the sizes against
;; `max_frame_bytes' (ebp/SPEC.md:247 — exactly 4194304).
;;
;; It answers one question: does a real vault's projection fit in one frame?
;; That decides whether RF-4a ever specifies the reserved bulk carrier
;; (PLAN-refound Decision 9 — do not specify an optimization before measuring
;; the need).  See README.md in this directory for kill criteria and the
;; removal commit.  NOTHING in the base may depend on this file.
;;
;; Run:
;;   emacs -Q --batch -l emacs/spike/jetpacs-spike-rows.el -f jetpacs-spike-report
;;
;; Two row shapes are measured, to bracket the cost of projection richness:
;;
;;   minimal — id, title, todo, tags, level.  What a list view needs.
;;   full    — every scalar the vulpea note struct carries, plus properties
;;             and outline path.  What a typed consumer would want.
;;
;; PROVENANCE (orgseq's model header, verified at
;; ~/pkb/projects/jetpacs-orgseq/orgseq/jetpacs-orgseq-model.el): "the DB
;; drives search, references, and queries; the file drives page rendering (DB
;; titles are display-formatted, so rich rendering re-parses the file)".  So
;; every row here carries `source: "db"' and the projection declares itself
;; DB-derived.  A consumer must NOT treat these titles as the file's text.

;;; Code:

(require 'cl-lib)
(require 'seq)

(defconst jetpacs-spike-max-frame-bytes 4194304
  "SPEC 4.5 `max_frame_bytes', the figure this spike measures against.
Fixed by ebp/SPEC.md:247 at exactly this value; not negotiable per-peer.")

(defun jetpacs-spike--load ()
  "Load vulpea from the user's ELPA without their interactive config."
  (require 'package)
  (setq package-user-dir (expand-file-name "~/.emacs.d/elpa"))
  (package-initialize)
  ;; org first: vulpea's tag-settings fingerprint reads
  ;; `org-use-tag-inheritance' during db init.
  (require 'org)
  (require 'vulpea-db-query))

(defun jetpacs-spike--str (v)
  "V as a JSON string, or :null when absent.
`json-serialize' has no single nil: elisp nil is both false and the empty
list, so every absent scalar is made explicit here rather than left to the
encoder's defaults."
  (if (and v (stringp v)) v :null))

(defun jetpacs-spike--vec (v)
  "List V as a JSON array; nil becomes an EMPTY array, never null.
An absent tag list and a present-but-empty one are the same fact to a
consumer, and a row of `[]' costs two bytes."
  (if v (vconcat (mapcar (lambda (x) (format "%s" x)) v)) []))

(defun jetpacs-spike--props (alist)
  "Property ALIST as a JSON object (a plist with keyword keys)."
  (if (null alist)
      (list :_empty :null)
    (apply #'append
           (mapcar (lambda (cell)
                     (list (intern (concat ":" (format "%s" (car cell))))
                           (jetpacs-spike--str (cdr cell))))
                   alist))))

(defun jetpacs-spike-row-minimal (n)
  "Project note N to the minimal flat row: what a list view needs."
  (list :id (jetpacs-spike--str (vulpea-note-id n))
        :title (jetpacs-spike--str (vulpea-note-title n))
        :todo (jetpacs-spike--str (vulpea-note-todo n))
        :tags (jetpacs-spike--vec (vulpea-note-tags n))
        :level (or (vulpea-note-level n) 0)))

(defun jetpacs-spike-row-full (n)
  "Project note N to the full flat row: every scalar the struct carries.
`source' is load-bearing, not decoration: the DB's title is
display-formatted (orgseq model header), so a consumer that wants the
file's own text must re-parse the file.  The projection says which it is."
  (list :id (jetpacs-spike--str (vulpea-note-id n))
        :source "db"
        :path (jetpacs-spike--str (vulpea-note-path n))
        :level (or (vulpea-note-level n) 0)
        :pos (or (vulpea-note-pos n) 0)
        :title (jetpacs-spike--str (vulpea-note-title n))
        :file_title (jetpacs-spike--str (vulpea-note-file-title n))
        :todo (jetpacs-spike--str (vulpea-note-todo n))
        :priority (jetpacs-spike--str (vulpea-note-priority n))
        :scheduled (jetpacs-spike--str (vulpea-note-scheduled n))
        :deadline (jetpacs-spike--str (vulpea-note-deadline n))
        :closed (jetpacs-spike--str (vulpea-note-closed n))
        :tags (jetpacs-spike--vec (vulpea-note-tags n))
        :aliases (jetpacs-spike--vec (vulpea-note-aliases n))
        :outline_path (jetpacs-spike--vec (vulpea-note-outline-path n))
        :properties (jetpacs-spike--props (vulpea-note-properties n))))

(defun jetpacs-spike--utf8 (s)
  "Octet length of S as UTF-8 — what the wire actually counts (SPEC 4.5)."
  (string-bytes (encode-coding-string s 'utf-8 t)))

(defun jetpacs-spike--percentile (sorted p)
  "The P percentile (0.0-1.0) of SORTED, a sorted list of numbers."
  (if (null sorted) 0
    (nth (min (1- (length sorted))
              (floor (* p (length sorted))))
         sorted)))

(defun jetpacs-spike--measure (notes label projector)
  "Project NOTES with PROJECTOR and report sizes under LABEL."
  (let* ((p0 (float-time))
         (rows (mapcar projector notes))
         (p1 (float-time))
         ;; The whole projection as ONE document, the way a bulk push would
         ;; carry it: {"rows": [...]}.
         (doc (list :rows (vconcat rows)))
         (s0 (float-time))
         (json (json-serialize doc))
         (s1 (float-time))
         (total (jetpacs-spike--utf8 json))
         (per (sort (mapcar (lambda (r) (jetpacs-spike--utf8 (json-serialize r)))
                            rows)
                    #'<))
         (sum-per (apply #'+ per))
         (frac (/ (float total) jetpacs-spike-max-frame-bytes)))
    (message "")
    (message "== %s ==" label)
    (message "  rows                 %d" (length rows))
    (message "  project              %.1f ms" (* 1000 (- p1 p0)))
    (message "  json-serialize       %.1f ms  (%.1f%% of total time)"
             (* 1000 (- s1 s0))
             (* 100 (/ (- s1 s0) (max 1e-9 (+ (- p1 p0) (- s1 s0))))))
    (message "  TOTAL bytes          %d  (%.1f KiB)" total (/ total 1024.0))
    (message "  vs max_frame_bytes   %.2f%%  of %d"
             (* 100 frac) jetpacs-spike-max-frame-bytes)
    (message "  rows over one frame  %d"
             (seq-count (lambda (b) (> b jetpacs-spike-max-frame-bytes)) per))
    (message "  per-row bytes        min %d  p50 %d  p95 %d  max %d  mean %.0f"
             (car per)
             (jetpacs-spike--percentile per 0.50)
             (jetpacs-spike--percentile per 0.95)
             (car (last per))
             (/ (float sum-per) (length per)))
    (message "  notes to fill 1 frame ~%d  (at the mean row)"
             (floor (/ jetpacs-spike-max-frame-bytes
                       (max 1 (/ (float sum-per) (length per))))))
    (list :label label :total total :frac frac :rows (length rows))))

;;;###autoload
(defun jetpacs-spike-report ()
  "Measure the live vault's flat-row projection. Read-only."
  (jetpacs-spike--load)
  (let* ((q0 (float-time))
         (notes (vulpea-db-query))
         (q1 (float-time))
         (files (length (delete-dups
                         (mapcar #'vulpea-note-path notes)))))
    (message "vault: %d notes across %d files   (db query %.1f ms)"
             (length notes) files (* 1000 (- q1 q0)))
    (message "db:    %s" (if (boundp 'vulpea-db-location) vulpea-db-location "?"))
    (jetpacs-spike--measure notes "MINIMAL row (id/title/todo/tags/level)"
                            #'jetpacs-spike-row-minimal)
    (jetpacs-spike--measure notes "FULL row (every struct scalar + properties)"
                            #'jetpacs-spike-row-full)
    (message "")))

(provide 'jetpacs-spike-rows)
;;; jetpacs-spike-rows.el ends here
