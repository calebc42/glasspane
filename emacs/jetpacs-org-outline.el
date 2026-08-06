;;; jetpacs-org-outline.el --- Tier-1 STAGING: the outline card view -*- lexical-binding: t; -*-

;;; Commentary:

;; The card-list VIEW over the base outline extraction (poc 2566-2642)
;; — Tier-1 STAGING, the `jetpacs-org-vulpea.el' precedent: never
;; required by any base module, migrating to the app repo when its
;; Tier-1 rung lands.  Under the ratified split the extraction
;; (jetpacs-org.el, JA-5a A3) is org fact; a heading list styled as
;; tappable cards is opinion — the Orgro-benchmarked BASE experience is
;; the folded document itself, and this Orgzly-shaped list belongs to
;; the app layer.
;;
;; A non-buffer render mints its OWN 23.1 records (the JC-2
;; discipline): each card exposes its heading position for
;; `jetpacs.org.heading' — the same sheet the buffer render's heading
;; tap opens — after a per-buffer supersession so re-renders retire
;; stale positions.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ebp-org)                      ; the outline MODEL; this file is the view
(require 'jetpacs-widgets)
(require 'jetpacs-buffer)
(require 'jetpacs-chrome)

(defvar jetpacs-org-outline-card-function nil
  "When non-nil, the per-record card builder: (RECORD) -> node.
The seam an app layers a richer card through — an agenda card, say —
over the same body.  nil uses the default card.  A custom card that
minted its own descriptors must expose them itself (SPEC 23.1).")

(defun jetpacs-org-outline--subtitle (rec)
  "REC's TODO · ⚑DEADLINE subtitle, or nil when it has neither."
  (let ((todo (plist-get rec :todo))
        (deadline (plist-get rec :deadline)))
    (when (or todo deadline)
      (jetpacs-scalar-text
       (string-join (delq nil (list todo (and deadline
                                             (concat "⚑ " deadline))))
                    " · ")))))

(defun jetpacs-org-outline--default-card (rec)
  "The default heading card for outline RECORD.
Tap opens the header action sheet — the exposure is minted HERE, with
the descriptor, because no buffer render is standing behind this list."
  (let ((name (plist-get rec :buffer))
        (pos (plist-get rec :pos))
        (tappable nil))
    (when (and (stringp name) (integerp pos) (get-buffer name))
      (jetpacs-buffer-expose name pos "jetpacs.org.heading")
      (setq tappable t))
    (jetpacs-chrome-row
     (jetpacs-scalar-text (or (plist-get rec :title) ""))
     :icon (if (plist-get rec :done) "check_circle" "chevron_right")
     :subtitle (jetpacs-org-outline--subtitle rec)
     :key (jetpacs-wire-id
           "org-outline"
           (format "%s:%s" (or (plist-get rec :file) name) pos))
     :on-tap (when tappable
               (jetpacs-action "jetpacs.org.heading"
                               :args (list :buffer name :pos pos))))))

(cl-defun jetpacs-org-outline-body (file &key items items-fn card-fn
                                         header footer
                                         empty-icon empty-title
                                         empty-caption)
  "A file's top-level headings as a list of cards (poc 2618-2642).
Records come from ITEMS, else ITEMS-FN, else
`ebp-org-file-toplevel-records' on FILE (root-checked — signals
`ebp-org-refused' outside the allowlist).  CARD-FN (else
`jetpacs-org-outline-card-function', else the default card) builds
each row; HEADER/FOOTER bracket the list; the empty state uses the
EMPTY-* members.  The records' buffer gets one exposure supersession
so a re-render retires stale positions."
  (let* ((records (ebp-org-outline-cap
                   (or items
                       (and items-fn (funcall items-fn))
                       (and file (ebp-org-file-toplevel-records file)))))
         (card-fn (or card-fn jetpacs-org-outline-card-function
                      #'jetpacs-org-outline--default-card)))
    (when-let* ((name (plist-get (car records) :buffer)))
      (jetpacs-buffer-forget-exposed name))
    (if (null records)
        (jetpacs-empty-state :icon (or empty-icon "list")
                             :title (or empty-title "No headings")
                             :caption empty-caption)
      (apply #'jetpacs-lazy-column
             (append (delq nil (cons header (mapcar card-fn records)))
                     (delq nil (list footer))
                     (list :spacing 4))))))

(provide 'jetpacs-org-outline)
;;; jetpacs-org-outline.el ends here
