;;; jetpacs-hypertext.el --- Generic hypertext/document substrate (Tier 0.5) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Tier 0.5: one document card grammar under every "rendered rich
;; document" buffer — the shr consumers (eww, elfeed-show, nov.el,
;; devdocs), plus help-mode and Info-mode.  The same bet jetpacs-tablist
;; makes on tabulated-list-mode and jetpacs-results makes on the
;; next-error protocol: ONE renderer, thin per-family adapters.
;;
;; The design is two-phase, and that is what keeps the adapters thin:
;;
;;   1. An ADAPTER scans a buffer into a neutral DOCUMENT MODEL — a flat
;;      list of segment plists (heading / para / pre / quote / rule /
;;      image / table).  Each family (shr props, help buttons, Info node
;;      structure) has its own scanner; none of them touches the wire.
;;   2. The EMITTER (`jetpacs-hypertext--emit') maps the model onto the
;;      widget vocabulary.  It is the only place that knows the SDUI
;;      nodes, so a new adapter never re-derives them.
;;
;; Fidelity floor: an unrecognised segment degrades to a plain paragraph,
;; never dropped — worst case equals Tier 0, never worse.
;;
;; NAMING: this module (feature `jetpacs-hypertext') sits next to the
;; public builder FUNCTION `jetpacs-hypertext' in jetpacs-widgets.el —
;; the format-6 document-node-array builder.  They are semantically
;; aligned (the module produces exactly the node array that builder
;; wraps) but they are DIFFERENT things: `(require 'jetpacs-hypertext)'
;; loads this file; `(jetpacs-hypertext …)' calls the builder.
;;
;; Rung JC-3b of docs/PLAN-jetpacs-consumers.md.  Ported from poc-v1
;; with the format-6 drift applied throughout (plist spans and args,
;; keyword text styles, SPEC 16.2 optional-node gates, SPEC 4.1
;; sanitization on every network/disk-derived string, SPEC 4.5 budgets)
;; and ONE real rebuild — the image resolver:
;;
;; The poc emitted `file://' paths (via a disk cache under
;; `jetpacs-root') and bare `http://' URLs.  Format 6 registers exactly
;; two image URI forms (SPEC 22.4): `https://' (feature `image.https' —
;; the DEVICE fetches; battery-cheapest, always current) and
;; `data:image/png|jpeg;base64' (feature `image.data').  So the disk
;; cache is DELETED — it existed solely to mint file:// URIs — and with
;; it this module's only dependency on jetpacs-config.  Bytes that exist
;; only inside Emacs are inlined as data: URIs, bounded by the welcome's
;; three per-image limits and the surface's remaining frame budget, or
;; degrade to an alt-text caption.  One consequence worth naming: a
;; readable `:file' (nov.el extracts EPUB resources to disk) stops being
;; a URI form and becomes an INPUT to the data path — nov images are now
;; read off disk, inlined, and cost frame bytes.
;;
;; An unadvertised URI form does not merely look worse: the push gate
;; (`jetpacs-shell--check-features') SIGNALS on it and the whole surface
;; is refused, so the resolver must ask `jetpacs-feature-advertised-p'
;; FIRST and degrade — emit-and-hope is a build-time error here.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'dom)                 ; DOM walking for the eww table pass
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)     ; jetpacs-defaction, feature/node predicates
(require 'jetpacs-buffer)      ; line spans, budgets, exposure, call-shimmed

;; libxml is a build-time option; both functions exist only in a
;; libxml2-enabled Emacs, and the probe below checks before calling.
(declare-function libxml-parse-html-region "xml.c")
(declare-function libxml-available-p "xml.c")

;; Forward declarations for the optional document packages this substrate
;; reads at render time.  None is required at load; each render path
;; checks these at runtime.
(defvar eww-data)
(defvar eww-history)
(defvar eww-history-position)
(defvar help-xref-stack)
(defvar help-xref-forward-stack)
(defvar help-xref-stack-item)
(defvar Info-history)
(defvar Info-history-forward)
(defvar Info-current-node)

;; --- The document model ------------------------------------------------------
;;
;; A model is a list of segment plists.  Every segment carries `:kind';
;; the rest of its keys depend on the kind:
;;
;;   (:kind heading :level N :text STR [:spans SPANS])
;;       A section label.  LEVEL (1-6) is preserved for a future table
;;       of contents; inline emission ignores it (the wire
;;       section_header has one style).
;;   (:kind para  :spans SPANS)  | (:kind para  :text STR)
;;       A paragraph.  SPANS is a list of `jetpacs-span' plists; TEXT is
;;       the plain-text fallback when the adapter has no styled runs.
;;   (:kind pre   :text STR [:syntax SYM])
;;       A preformatted / code block, rendered monospace on a surface.
;;   (:kind quote :spans SPANS) | (:kind quote :text STR)
;;       A blockquote, rendered as a paragraph on a tinted surface.
;;   (:kind rule)
;;       A horizontal rule.
;;   (:kind image :url STR :alt STR :file STR :data STR :content-type SYM)
;;       An image, resolved by `jetpacs-hypertext--image' (see the
;;       commentary).  When nothing resolves, ALT/URL degrades to a
;;       caption.
;;   (:kind table [:rows ROWS] [:table-id N] [:text STR])
;;       A table.  ROWS — row plists (:header BOOL :cells CELLS), each
;;       cell a string or a list of spans — emits a native
;;       `jetpacs-table'.  Without rows, TEXT (the rendered region,
;;       verbatim) emits as a monospace block; TABLE-ID is the shr
;;       render counter the eww DOM pass uses to recover ROWS.
;;   (:kind note :text STR)
;;       A meta caption (truncation markers), styled `caption'.

(defcustom jetpacs-hypertext-max-segments 500
  "Segment cap for one scanned document.
Past the cap, scanning stops and a truncation note segment is appended —
SPEC 4.5's budgets still apply at emit time, but scanning a 50,000-line
Info node just to throw most of it away is CPU spent for nothing."
  :type 'integer :group 'jetpacs)

(defun jetpacs-hypertext--nonempty (s)
  "Return S when it is a non-empty string, else nil."
  (and (stringp s) (not (string-empty-p s)) s))

(defun jetpacs-hypertext--spans-text (spans)
  "Concatenate the plain text of SPANS (span PLISTS — format 6)."
  (mapconcat (lambda (s) (or (plist-get s :text) "")) spans ""))

;; --- The image resolver ------------------------------------------------------
;;
;; Replaces the poc's disk cache (see the commentary).  Resolution order,
;; each row falling through to the caption when its gate fails:
;;
;;   1. svg (either shape) ................ caption — SPEC 17.2 rejects
;;      active formats BEFORE decode; `jetpacs--check-image-url' would
;;      signal on the URI form anyway.
;;   2. `image' node unadvertised ......... caption (SPEC 16.2).
;;   3. https URL + `image.https' ......... pass through untouched.  The
;;      Companion fetches under SPEC 17.2's own limits and SSRF rules.
;;   4. http URL .......................... upgrade to https, retry 3.
;;   5. data:image/png|jpeg + `image.data',
;;      within every limit ................ pass the URI through
;;      untouched (decoded ONCE, only to measure).
;;   6. raw bytes (:data) or a readable :file + `image.data',
;;      png/jpeg, within every limit ...... base64 into a fresh data: URI.
;;   7. anything else ..................... caption.
;;
;; "Every limit" is SPEC 4.5's three per-image limits — REQUIRED in the
;; welcome whenever image support is advertised, and nothing else in
;; this tree reads them — plus the surface's remaining frame budget
;; (base64 inflates ~4/3, and an inlined image competes with the
;; document's own text for `max_frame_bytes').  Pixel counts come from
;; sniffing the PNG IHDR / JPEG SOFn headers directly: exact, ~30 lines,
;; and working in batch and on a headless daemon, where
;; `image-size' needs a live display.  Formats outside the SPEC 17.2
;; guaranteed-decode pair (gif/webp/bmp/heic) are OPTIONAL for the
;; Companion with no per-format feature to ask about, so inlining one is
;; a gamble this resolver refuses — caption.
;;
;; Overlay-supplied images (some packages put the descriptor on an
;; overlay, not text properties) are invisible to `--shr-image-at' and
;; fall through to the paragraph branch as an alt-text run — a
;; pre-existing fidelity floor, kept deliberately.

(defconst jetpacs-hypertext--data-uri-types
  '(("image/png" . png) ("image/jpeg" . jpeg))
  "data: URI MIME type -> image type symbol.
Narrowed to SPEC 17.2's guaranteed-decode pair; anything else captions.")

(defun jetpacs-hypertext--decode-data-uri (url)
  "Decode a base64 data: image URL into (DATA . TYPE), or nil.
DATA is a unibyte string; TYPE is `png' or `jpeg'.  Call ONCE and bind —
the payload decode is not free."
  (when (and (stringp url)
             (string-match "\\`data:\\([^;,]+\\);base64,\\(.*\\)\\'" url))
    (let ((type (cdr (assoc (downcase (match-string 1 url))
                            jetpacs-hypertext--data-uri-types)))
          (data (ignore-errors (base64-decode-string (match-string 2 url)))))
      (and data type (cons data type)))))

(defun jetpacs-hypertext--sniff-type (data)
  "Image type symbol from DATA's magic bytes: `png', `jpeg', or nil."
  (cond
   ((and (> (length data) 8)
         (string-prefix-p "\x89PNG\r\n\x1a\n" data)) 'png)
   ((and (> (length data) 3)
         (= (aref data 0) #xFF) (= (aref data 1) #xD8)) 'jpeg)))

(defun jetpacs-hypertext--png-size (data)
  "PNG dimensions (WIDTH . HEIGHT) from DATA's IHDR chunk, or nil.
The IHDR is mandatory-first: width at byte 16, height at 20, both
big-endian u32."
  (when (and (> (length data) 24)
             (string-prefix-p "\x89PNG\r\n\x1a\n" data))
    (cl-flet ((u32 (i) (+ (* (aref data i) 16777216)
                          (* (aref data (+ i 1)) 65536)
                          (* (aref data (+ i 2)) 256)
                          (aref data (+ i 3)))))
      (cons (u32 16) (u32 20)))))

(defun jetpacs-hypertext--jpeg-size (data)
  "JPEG dimensions (WIDTH . HEIGHT) from DATA's SOFn marker, or nil.
Walks the marker segments: a start-of-frame (C0-CF except the
non-frame C4/C8/CC) carries height at +5 and width at +7, big-endian
u16.  Bounded by DATA's length; a malformed stream returns nil."
  (when (and (> (length data) 4)
             (= (aref data 0) #xFF) (= (aref data 1) #xD8))
    (let ((i 2) (len (length data)) size)
      (while (and (not size) (< (+ i 9) len))
        (if (/= (aref data i) #xFF)
            (setq i len)                ; lost sync: give up
          (let ((marker (aref data (1+ i))))
            (cond
             ((memq marker '(#x01 #xD8)) (cl-incf i 2)) ; standalone
             ((<= #xD0 marker #xD7) (cl-incf i 2))      ; RSTn
             ((and (<= #xC0 marker #xCF)
                   (not (memq marker '(#xC4 #xC8 #xCC))))
              (setq size (cons (+ (* (aref data (+ i 7)) 256)
                                  (aref data (+ i 8)))
                               (+ (* (aref data (+ i 5)) 256)
                                  (aref data (+ i 6))))))
             (t (cl-incf i (+ 2 (* (aref data (+ i 2)) 256)
                              (aref data (+ i 3)))))))))
      size)))

(defun jetpacs-hypertext--image-dimensions (data)
  "(WIDTH . HEIGHT) of the png/jpeg bytes DATA, or nil when unmeasurable."
  (or (jetpacs-hypertext--png-size data)
      (jetpacs-hypertext--jpeg-size data)))

(defun jetpacs-hypertext--image-fits-p (data)
  "Non-nil when image bytes DATA fit every per-image and frame limit.
DATA is the ENCODED file (SPEC 4.5's `max_image_bytes'); the decoded
bitmap is estimated as 4 bytes per pixel against
`max_decoded_image_bytes', with pixel counts sniffed from the headers —
an UNMEASURABLE image does not fit (skipping the check and relying on
the Companion is a 1201 voiding the whole surface).  The base64 wire
form (~4/3 of DATA) must also fit the surface's remaining frame budget
when one is bound; SPEC 4.5: a sender MUST respect reported limits and
MUST NOT rely on receiver truncation."
  (let* ((client (jetpacs-client))
         (limits (and client (ebp-client-limits client)))
         (max-bytes (plist-get limits :max_image_bytes))
         (max-decoded (plist-get limits :max_decoded_image_bytes))
         (max-pixels (plist-get limits :max_image_pixels))
         (dims (jetpacs-hypertext--image-dimensions data))
         (pixels (and dims (* (car dims) (cdr dims))))
         (b64-len (* 4 (ceiling (length data) 3)))
         (frame-left (cdr-safe jetpacs-buffer--budget)))
    (and dims
         (or (null max-bytes) (<= (length data) max-bytes))
         (or (null max-pixels) (<= pixels max-pixels))
         (or (null max-decoded) (<= (* pixels 4) max-decoded))
         (or (null frame-left) (<= b64-len frame-left)))))

(defun jetpacs-hypertext--file-bytes (file)
  "FILE's bytes as a unibyte string, or nil when unreadable or oversize.
Bounded BEFORE reading by `max_image_bytes' (2 MiB when no client
advertises one), so an arbitrarily large disk file never lands in
memory just to be refused."
  (when (and (stringp file) (file-readable-p file))
    (let* ((client (jetpacs-client))
           (cap (or (and client (plist-get (ebp-client-limits client)
                                           :max_image_bytes))
                    (* 2 1024 1024)))
           (size (file-attribute-size (file-attributes file))))
      (when (and size (<= size cap))
        (ignore-errors
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert-file-contents-literally file)
            (buffer-string)))))))

(defun jetpacs-hypertext--image (seg)
  "Resolve image SEG per the module commentary's decision table.
Returns a `jetpacs-image' node or the alt-text caption — never nil,
never an unadvertised URI form (the push gate would refuse the whole
surface), never svg (SPEC 17.2 rejects active formats before decode)."
  (let* ((alt (jetpacs-hypertext--nonempty
               (and (stringp (plist-get seg :alt))
                    (jetpacs-buffer--scalar-text (plist-get seg :alt)))))
         (url (plist-get seg :url))
         (file (plist-get seg :file))
         (data (plist-get seg :data))
         (ctype (plist-get seg :content-type))
         (caption
          (lambda ()
            (jetpacs-text
             (format "[image: %s]"
                     (or alt
                         (and (stringp url) (jetpacs-buffer--scalar-text url))
                         "…"))
             :style "caption")))
         (https-ok
          (lambda (u)
            (and (jetpacs-feature-advertised-p "image.https")
                 (jetpacs-image u :content-description alt))))
         (inline-ok
          (lambda (bytes type)
            ;; Only the SPEC 17.2 guaranteed-decode pair is inlined —
            ;; there is no per-format feature to ask about (22.4
            ;; registers URI forms, not codecs), so anything else is a
            ;; gamble on an OPTIONAL decoder.
            (and (jetpacs-feature-advertised-p "image.data")
                 (memq type '(png jpeg))
                 (jetpacs-hypertext--image-fits-p bytes)
                 (jetpacs-image
                  (concat "data:image/" (if (eq type 'png) "png" "jpeg")
                          ";base64," (base64-encode-string bytes t))
                  :content-description alt)))))
    (or
     (cond
      ;; 1. svg, either shape: an active format, rejected before decode.
      ((or (eq ctype 'svg)
           (and (stringp url) (string-prefix-p "data:image/svg" url)))
       nil)
      ;; 2. The image node itself is OPTIONAL (SPEC 16.2).
      ((not (jetpacs-node-advertised-p "image")) nil)
      ;; 3. https: the device fetches — zero frame bytes, always current.
      ((and (stringp url) (string-prefix-p "https://" url))
       (funcall https-ok url))
      ;; 4. http: not a registered form; upgrade and let the Companion's
      ;;    fetch discipline (SPEC 17.2) succeed or placeholder.
      ((and (stringp url) (string-prefix-p "http://" url))
       (funcall https-ok (concat "https" (substring url 4))))
      ;; 5. A legal data: URI rides through UNTOUCHED when it fits —
      ;;    decoded once, only to measure (the poc decoded twice).
      ((and (stringp url) (string-prefix-p "data:" url))
       (when-let* ((decoded (jetpacs-hypertext--decode-data-uri url)))
         (and (jetpacs-feature-advertised-p "image.data")
              (jetpacs-hypertext--image-fits-p (car decoded))
              (jetpacs-image url :content-description alt))))
      ;; 6. Bytes that exist only inside Emacs: shr descriptor :data, or
      ;;    a readable :file (nov.el's extracted EPUB resources — now an
      ;;    input to the data path, costing frame bytes).
      ((stringp data)
       (funcall inline-ok data
                (or (and (memq ctype '(png jpeg)) ctype)
                    (jetpacs-hypertext--sniff-type data))))
      ((stringp file)
       (when-let* ((bytes (jetpacs-hypertext--file-bytes file)))
         (funcall inline-ok bytes
                  (or (and (memq ctype '(png jpeg)) ctype)
                      (jetpacs-hypertext--sniff-type bytes))))))
     ;; 7. Nothing resolved: the caption — degraded, never dropped.
     (funcall caption))))

;; --- The emitter -------------------------------------------------------------

(defun jetpacs-hypertext--spend-spans (spans)
  "Cap SPANS against the shared SPEC 4.5 span budget and spend it down.
Returns the (possibly capped) spans.  `max_rich_spans' is an AGGREGATE
count across one SurfaceSpec, so every rich_text and table this document
emits draws on the same allowance."
  (let ((budget jetpacs-buffer--budget))
    (if (not (and budget (integerp (car budget))))
        spans
      (let ((left (car budget)))
        (when (> (length spans) left)
          (setq spans (jetpacs-buffer--cap-spans spans (max 1 left))))
        (setcar budget (max 0 (- left (length spans))))
        spans))))

(defun jetpacs-hypertext--paragraph (seg)
  "A paragraph body node from SEG's :spans (preferred) or :text.
Degrades to a flattened Core `text' when `rich_text' is unadvertised
(SPEC 16.2)."
  (let ((spans (plist-get seg :spans))
        (text (plist-get seg :text)))
    (cond
     ((and spans (> (length spans) 0))
      (setq spans (jetpacs-hypertext--spend-spans spans))
      (if (jetpacs-node-advertised-p "rich_text")
          (jetpacs-rich-text spans)
        (jetpacs-buffer--spans->text spans)))
     ((jetpacs-hypertext--nonempty text) (jetpacs-text text))
     (t (jetpacs-text "")))))

(defun jetpacs-hypertext--heading (seg)
  "A section_header node from heading SEG, or a title text when
`section_header' is unadvertised (SPEC 16.2)."
  (let ((label (or (jetpacs-hypertext--nonempty (plist-get seg :text))
                   (jetpacs-hypertext--nonempty
                    (jetpacs-hypertext--spans-text (plist-get seg :spans)))
                   "")))
    (if (jetpacs-node-advertised-p "section_header")
        (jetpacs-section-header label)
      (jetpacs-text label :style "title"))))

(defun jetpacs-hypertext--pre (seg)
  "A preformatted/code block node from SEG on a tinted surface.
The surface wrapper is OPTIONAL (SPEC 16.2); unadvertised, the bare
monospace text stands alone.  `surface_variant' is the REGISTERED
16.6 role (the poc's `surface_container' is not registered — the
Companion's fallback made code blocks silently lose their tint)."
  (let* ((syntax (plist-get seg :syntax))
         (body (jetpacs-text (or (plist-get seg :text) "")
                             :style "mono"
                             :syntax (and (symbolp syntax) syntax
                                          (symbol-name syntax)))))
    (if (jetpacs-node-advertised-p "surface")
        (jetpacs-with-attrs
         (jetpacs-surface (list body)
                          :color "surface_variant" :shape "rounded_small")
         :padding 3)
      body)))

(defun jetpacs-hypertext--quote (seg)
  "A blockquote node from SEG: its paragraph body on a tinted surface,
or the bare paragraph when `surface' is unadvertised (SPEC 16.2)."
  (let ((para (jetpacs-hypertext--paragraph seg)))
    (if (jetpacs-node-advertised-p "surface")
        (jetpacs-with-attrs
         (jetpacs-surface (list para)
                          :color "surface_variant" :shape "rounded_small")
         :padding 3)
      para)))

(defun jetpacs-hypertext--table (seg)
  "A table node from SEG: native `jetpacs-table' when :rows were
recovered (the eww DOM pass) and `table' is advertised, else its
rendered :text verbatim as a monospace block — shr's own alignment,
exactly what Tier 0 shows, never a reflow."
  (let ((rows (plist-get seg :rows)))
    (cond
     ((and rows (jetpacs-node-advertised-p "table")
           ;; The cells draw on the aggregate span budget too.
           (let ((cells (apply #'+ (mapcar (lambda (r)
                                             (length (plist-get r :cells)))
                                           rows)))
                 (budget jetpacs-buffer--budget))
             (or (not (and budget (integerp (car budget))))
                 (and (<= cells (car budget))
                      (progn (setcar budget (- (car budget) cells)) t)))))
      (jetpacs-table
       (mapcar
        (lambda (row)
          (apply #'jetpacs-table-row
                 (if (plist-get row :header) "header" "data")
                 (mapcar (lambda (cell)
                           (jetpacs-table-cell
                            (if (stringp cell) (list (jetpacs-span cell))
                              cell)))
                         (plist-get row :cells))))
        rows)))
     ((jetpacs-hypertext--nonempty (plist-get seg :text))
      (jetpacs-hypertext--pre (list :text (plist-get seg :text))))
     (t (jetpacs-text "")))))

(defun jetpacs-hypertext--emit-segment (seg)
  "Map one document SEG (a segment plist) to an SDUI node.
An unrecognised kind degrades to a plain paragraph — never dropped."
  (pcase (plist-get seg :kind)
    ('heading (jetpacs-hypertext--heading seg))
    ('para    (jetpacs-hypertext--paragraph seg))
    ('pre     (jetpacs-hypertext--pre seg))
    ('quote   (jetpacs-hypertext--quote seg))
    ('rule    (jetpacs-divider))
    ('image   (jetpacs-hypertext--image seg))
    ('table   (jetpacs-hypertext--table seg))
    ('note    (jetpacs-text (or (plist-get seg :text) "…") :style "caption"))
    (_        (jetpacs-hypertext--paragraph seg))))

(defun jetpacs-hypertext--emit (model &optional title)
  "Emit document MODEL (a list of segment plists) as a LIST of nodes.
TITLE, when a non-empty string, leads with a title text node.  Spends
the shared SPEC 4.5 budget (`jetpacs-buffer-with-budget') down per node
and stops with the same truncation caption `--render-region' appends —
a sender MUST respect reported limits, never rely on receiver
truncation.  This is the single place that knows the wire vocabulary;
adapters build MODEL and never touch nodes."
  (let ((budget jetpacs-buffer--budget)
        (truncated nil)
        nodes)
    (cl-block walk
      (dolist (seg (append
                    (when (jetpacs-hypertext--nonempty title)
                      (list (list :kind 'heading
                                  :text (jetpacs-buffer--scalar-text title))))
                    model))
        (let ((node (jetpacs-hypertext--emit-segment seg)))
          (when (and budget (integerp (cdr budget)))
            (let ((size (jetpacs-buffer--node-bytes node)))
              (when (> size (cdr budget))
                (setq truncated t)
                (cl-return-from walk))
              (setcdr budget (- (cdr budget) size))))
          (push node nodes)
          ;; The aggregate span budget is spent: stop here.
          (when (and budget (integerp (car budget)) (<= (car budget) 0))
            (setq truncated t)
            (cl-return-from walk)))))
    (when truncated
      (push (jetpacs-text "… output truncated (surface budget)"
                          :style "caption")
            nodes))
    (nreverse nodes)))

;; --- shr props contract (the drift firewall) ---------------------------------
;;
;; Everything this file knows about shr's *rendered-buffer* markup lives
;; in this section, so an shr change across Emacs versions is a one-spot
;; edit.  Links and inline emphasis are NOT read here — they ride the
;; Tier 0 line-span builder (`jetpacs-buffer--line-spans'), which already
;; turns shr's mouse-face/keymap link runs into `emacs.buffer.act' taps
;; and maps face emphasis to span styling.  Only block structure is
;; shr-specific.

(defconst jetpacs-hypertext--shr-heading-faces
  '((shr-h1 . 1) (shr-h2 . 2) (shr-h3 . 3)
    (shr-h4 . 4) (shr-h5 . 5) (shr-h6 . 6))
  "shr heading faces mapped to their level (1-6).")

(defun jetpacs-hypertext--face-list (pos)
  "The `face'/`font-lock-face' value at POS as a list of refs (nil-safe)."
  (let ((f (or (get-text-property pos 'face)
               (get-text-property pos 'font-lock-face))))
    (cond ((null f) nil)
          ((and (consp f) (keywordp (car f))) (list f)) ; a single plist
          ((listp f) f)
          (t (list f)))))

(defun jetpacs-hypertext--collapse-ws (s)
  "Collapse whitespace runs in S (a heading rendered across wrapped lines)
to single spaces, and trim — so a filled multi-line heading reads as one
label."
  (string-trim (replace-regexp-in-string "[ \t\n]+" " " s)))

(defun jetpacs-hypertext--shr-placeholder-image-p (type data)
  "Non-nil when TYPE/DATA is shr's not-yet-fetched placeholder rectangle.
In batch or before a fetch completes, `shr-put-image' displays a
generated gray-gradient SVG; treating that as content would show gray
boxes instead of images, so the resolver sees no data at all."
  (and (eq type 'svg)
       (stringp data)
       (string-match-p "url(#background)" data)))

(defun jetpacs-hypertext--shr-image-at (pos)
  "An image segment plist for the shr image run at POS, or nil.
Reads shr's rendered-buffer markup: the `image-url' property (the real
source URL), `shr-alt' (the alt text), and the `display' image
descriptor's :file / :data / :type — with the placeholder rectangle
discarded.  Text properties only: an overlay-supplied image is
invisible here and degrades to its alt-text run (fidelity floor)."
  (let* ((url (get-text-property pos 'image-url))
         (alt (get-text-property pos 'shr-alt))
         (disp (get-text-property pos 'display))
         (desc (and (eq (car-safe disp) 'image) (cdr disp)))
         (type (plist-get desc :type))
         (file (plist-get desc :file))
         (data (plist-get desc :data)))
    (when (jetpacs-hypertext--shr-placeholder-image-p type data)
      (setq data nil type nil))
    (when (or url alt desc)
      (list :kind 'image
            :url (jetpacs-hypertext--nonempty url)
            :alt (jetpacs-hypertext--nonempty alt)
            :file (jetpacs-hypertext--nonempty file)
            :data (and (stringp data) (not (string-empty-p data)) data)
            :content-type type))))

(defun jetpacs-hypertext--image-run-p (pos)
  "Non-nil when POS is inside an shr image run."
  (or (get-text-property pos 'image-url)
      (get-text-property pos 'shr-alt)
      (eq (car-safe (get-text-property pos 'display)) 'image)))

(defun jetpacs-hypertext--block-table-id (beg end)
  "The `shr-table-id' of the rendered table block [BEG, END), or nil.
shr stamps the table's start with `shr-table-id' (a per-render counter),
the key the eww DOM pass uses to pair a rendered region with its
<table>."
  (let ((pos beg) id)
    (while (and (< pos end) (not id))
      (setq id (get-text-property pos 'shr-table-id)
            pos (or (next-single-property-change pos 'shr-table-id nil end)
                    end)))
    id))

(defun jetpacs-hypertext--table-block-p (beg end)
  "Non-nil when the block [BEG, END) is an shr-rendered table region."
  (or (jetpacs-hypertext--block-table-id beg end)
      (let ((pos beg) found)
        (while (and (< pos end) (not found))
          (setq found (get-text-property pos 'shr-table-indent)
                pos (or (next-single-property-change
                         pos 'shr-table-indent nil end)
                        end)))
        found)))

(defun jetpacs-hypertext--block-images (beg end)
  "Image segments when block [BEG, END) is image-only, else nil.
Walks the block's property runs collecting shr image runs; any
non-image, non-whitespace text makes this nil — a mixed block stays a
paragraph whose inline images degrade to their alt text (the fidelity
floor)."
  (let ((pos beg) images stray)
    (while (and (< pos end) (not stray))
      (let ((next (or (next-property-change pos nil end) end)))
        (if (jetpacs-hypertext--image-run-p pos)
            (let ((seg (jetpacs-hypertext--shr-image-at pos)))
              ;; One image's alt text may split into several property
              ;; runs (help-echo boundaries, fill) — collapse
              ;; consecutive equals.
              (when (and seg (not (equal seg (car images))))
                (push seg images)))
          (unless (string-blank-p (buffer-substring-no-properties pos next))
            (setq stray t)))
        (setq pos next)))
    (and (not stray) (nreverse images))))

(defun jetpacs-hypertext--heading-level-at (pos)
  "Heading level 1-6 if POS is faced as an shr heading, else nil."
  (cl-some (lambda (f)
             (and (symbolp f)
                  (cdr (assq f jetpacs-hypertext--shr-heading-faces))))
           (jetpacs-hypertext--face-list pos)))

;; --- Adapter: shr-rendered buffers (eww, and every shr consumer) -------------
;;
;; shr separates block elements with a blank line, so the model is
;; recovered block by block: a block faced as an shr heading becomes a
;; heading segment; everything else becomes a paragraph whose spans
;; (links + emphasis) come from the Tier 0 line-span builder, reflowed
;; across the block's lines.

(defun jetpacs-hypertext--block-end (limit)
  "End of the block whose first line starts at point: the last non-blank
line's end before a blank line or LIMIT.  Point is at a non-blank line's
beginning; the buffer is not moved."
  (save-excursion
    (let ((end (min (line-end-position) limit)))
      (while (and (< (line-end-position) limit)
                  (zerop (forward-line 1))
                  (< (point) limit)
                  (not (looking-at-p "[ \t]*$")))
        (setq end (min (line-end-position) limit)))
      end)))

(defun jetpacs-hypertext--block-heading-level (beg end)
  "Heading level if any run in [BEG, END) is faced as an shr heading."
  (let ((pos beg) lvl)
    (while (and (< pos end) (not lvl))
      (setq lvl (jetpacs-hypertext--heading-level-at pos)
            pos (next-single-property-change pos 'face nil end)))
    lvl))

(defun jetpacs-hypertext--block-spans (beg end buffer-name)
  "Spans for paragraph block [BEG, END), reflowed across its lines.
Reuses `jetpacs-buffer--line-spans' with monospace and color emission
off (document prose is proportional and themed by the device), so shr
links become `emacs.buffer.act' taps and face emphasis maps to span
styling for free; non-empty lines are joined by a space so the
paragraph reflows.

Colors MUST stay off at this seam: the fg/bg reference hexes are bound
only inside `jetpacs-buffer--render-region', so a caller with
`jetpacs-buffer-emit-colors' non-nil would emit an explicit `:color' on
EVERY span — bloating the frame and overriding the device theme."
  (let ((jetpacs-buffer-monospace nil)
        (jetpacs-buffer-emit-colors nil)
        chunks)
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (let ((line (jetpacs-buffer--line-spans
                     (line-beginning-position)
                     (min (line-end-position) end)
                     buffer-name)))
          (when line (push line chunks)))
        (forward-line 1)))
    (setq chunks (nreverse chunks))
    (apply #'append
           (cl-loop for chunk in chunks
                    for i from 0
                    collect (if (zerop i) chunk
                              (cons (jetpacs-span " ") chunk))))))

(defun jetpacs-hypertext--skip-inter-block (limit)
  "Advance point over inter-block blank space up to LIMIT, stopping at an
shr image run.  On an Emacs built without SVG support, `shr-tag-img'
renders an image as a lone space rather than a placeholder glyph
carrying its alt text; that space is meaningful markup, not inter-block
whitespace, so the block scan must not skip it — otherwise the image is
dropped below the Tier-0 fidelity floor instead of degrading to its
URL/alt caption."
  (while (and (< (point) limit)
              (memq (char-after) '(?\s ?\t ?\n))
              (not (jetpacs-hypertext--image-run-p (point))))
    (forward-char 1)))

(defun jetpacs-hypertext--scan-shr (buf)
  "Scan shr-rendered BUF into a document model, capped by
`jetpacs-hypertext-max-segments' (a truncation note marks the cut)."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let ((name (buffer-name buf)) (limit (point-max))
            (count 0) segments)
        (while (and (< (point) limit)
                    (< count jetpacs-hypertext-max-segments))
          (jetpacs-hypertext--skip-inter-block limit)
          (when (< (point) limit)
            (let* ((beg (line-beginning-position))
                   (end (jetpacs-hypertext--block-end limit))
                   (level nil) (images nil))
              (cond
               ;; A rendered table region: keep its lines verbatim as
               ;; the monospace fallback; the eww DOM pass may upgrade
               ;; it to native rows via its shr-table-id.  A table block
               ;; with no id of its own continues the previous table
               ;; (shr stamps the id once, at the table's start; a blank
               ;; row splits the region).
               ((jetpacs-hypertext--table-block-p beg end)
                (let ((id (jetpacs-hypertext--block-table-id beg end))
                      (text (jetpacs-buffer--scalar-text
                             (buffer-substring-no-properties beg end)))
                      (prev (car segments)))
                  (if (and (null id) prev
                           (eq (plist-get prev :kind) 'table))
                      (setcar segments
                              (plist-put (copy-sequence prev) :text
                                         (concat (plist-get prev :text)
                                                 "\n" text)))
                    (push (list :kind 'table :table-id id :text text)
                          segments)
                    (cl-incf count))))
               ;; An image-only block: one segment per image.
               ((setq images (jetpacs-hypertext--block-images beg end))
                (dolist (img images)
                  (push img segments)
                  (cl-incf count)))
               ((setq level (jetpacs-hypertext--block-heading-level beg end))
                (push (list :kind 'heading :level level
                            :text (jetpacs-hypertext--collapse-ws
                                   (jetpacs-buffer--scalar-text
                                    (buffer-substring-no-properties beg end))))
                      segments)
                (cl-incf count))
               (t
                (let ((spans (jetpacs-hypertext--block-spans beg end name)))
                  (when spans
                    (push (list :kind 'para :spans spans) segments)
                    (cl-incf count)))))
              (goto-char end))))
        (when (and (>= count jetpacs-hypertext-max-segments)
                   (< (point) limit))
          (push (list :kind 'note :text "… document truncated") segments))
        (nreverse segments)))))

(defun jetpacs-hypertext--eww-title (buf)
  "The document title for BUF from `eww-data', or nil.
Network-derived: sanitized per SPEC 4.1."
  (with-current-buffer buf
    (when-let* ((title (and (boundp 'eww-data) eww-data
                            (jetpacs-hypertext--nonempty
                             (plist-get eww-data :title)))))
      (jetpacs-buffer--scalar-text title))))

;; --- The eww DOM table pass --------------------------------------------------
;;
;; shr renders a <table> as aligned monospace text; the real structure
;; is only in the HTML.  eww keeps that HTML (`eww-data' :source), so
;; table segments are upgraded to native rows by re-parsing it and
;; pairing each rendered region's `shr-table-id' with the document-order
;; <table> list.  Anything ambiguous — nested tables (render order
;; diverges from document order), ragged rows (colspans), oversize —
;; stays the monospace fallback: exactly what Tier 0 shows today, never
;; a wrong table.

(defcustom jetpacs-hypertext-table-max-rows 100
  "Row cap for native table recovery.
A <table> with more rows than this keeps its monospace rendering (a
phone table this size wants a purpose-built view, not a widget)."
  :type 'integer :group 'jetpacs)

(defun jetpacs-hypertext--libxml-p ()
  "Positive knowledge that libxml HTML parsing is available."
  (and (fboundp 'libxml-available-p)
       (libxml-available-p)
       (fboundp 'libxml-parse-html-region)))

(defun jetpacs-hypertext--dom-table-rows (table)
  "Row plists from DOM TABLE node, or nil when irregular.
Rows are the <tr>s in document order; a row's cells are its <th>/<td>
children flattened to text (network-derived: sanitized per SPEC 4.1); a
row containing a <th> is a header row.  Ragged tables (colspan/rowspan
artifacts), oversize tables, and tables past the welcome's
`max_table_cells' return nil — the caller keeps the monospace
fallback."
  (let* ((trs (dom-by-tag table 'tr))
         (rows
          (mapcar
           (lambda (tr)
             (let ((cells (seq-filter
                           (lambda (c) (memq (dom-tag c) '(th td)))
                           (dom-non-text-children tr))))
               (list :header (and (seq-find (lambda (c)
                                              (eq (dom-tag c) 'th))
                                            cells)
                                  t)
                     :cells (mapcar
                             (lambda (c)
                               (jetpacs-hypertext--collapse-ws
                                (jetpacs-buffer--scalar-text
                                 (dom-texts c ""))))
                             cells))))
           trs))
         (widths (delete-dups (mapcar (lambda (r)
                                        (length (plist-get r :cells)))
                                      rows)))
         (client (jetpacs-client))
         (max-cells (and client (plist-get (ebp-client-limits client)
                                           :max_table_cells))))
    (and rows
         (<= (length rows) jetpacs-hypertext-table-max-rows)
         (= (length widths) 1)              ; every row the same cell count
         (> (car widths) 0)
         (or (null max-cells)
             (<= (* (length rows) (car widths)) max-cells))
         rows)))

(defun jetpacs-hypertext--eww-resolve-tables (model buf)
  "Upgrade MODEL's table segments with native rows from BUF's eww source.
Returns MODEL (segments upgraded where recovery is unambiguous).
Requires libxml (positive knowledge — the probe, not the version) and
the page source in `eww-data'; a document containing nested tables is
left entirely alone, since shr's table-id render order diverges from
document order there."
  (let ((source (with-current-buffer buf
                  (and (boundp 'eww-data) eww-data
                       (plist-get eww-data :source)))))
    (if (not (and (cl-some (lambda (s) (and (eq (plist-get s :kind) 'table)
                                            (plist-get s :table-id)))
                           model)
                  (jetpacs-hypertext--libxml-p)
                  (stringp source)))
        model
      (let* ((dom (with-temp-buffer
                    (insert source)
                    (libxml-parse-html-region (point-min) (point-max))))
             (tables (and dom (dom-by-tag dom 'table))))
        (if (or (null tables)
                (cl-some (lambda (tbl)
                           (> (length (dom-by-tag tbl 'table)) 1))
                         tables))
            model
          (mapcar
           (lambda (seg)
             (let* ((id (and (eq (plist-get seg :kind) 'table)
                             (plist-get seg :table-id)))
                    ;; shr binds `shr-table-id' to 0 and increments
                    ;; BEFORE stamping, so the first table is id 1.
                    (table (and (integerp id) (> id 0)
                                (nth (1- id) tables)))
                    (rows (and table
                               (jetpacs-hypertext--dom-table-rows table))))
               (if rows
                   (plist-put (copy-sequence seg) :rows rows)
                 seg)))
           model))))))

;; --- Document navigation (the nav toolbar + hypertext.nav action) ------------
;;
;; A rendered document navigates by running the mode's OWN commands
;; (eww/help history, Info node motion) — never a command named on the
;; wire.  The wire carries only an op string; the op->command allowlist
;; and the mode gate live here, exactly like `results.visit'.

(defconst jetpacs-hypertext--nav-ops
  '((eww-mode  (back . eww-back-url) (forward . eww-forward-url)
               (reload . eww-reload))
    (help-mode (back . help-go-back) (forward . help-go-forward))
    (Info-mode (prev . Info-prev) (next . Info-next) (up . Info-up)
               (toc . Info-toc)
               (back . Info-history-back) (forward . Info-history-forward)))
  "Per-mode document-nav op -> the mode's own command.
The op symbol is all the wire carries; the command is resolved here, so
no command name ever travels over the wire.")

(defconst jetpacs-hypertext--nav-icons
  '((back    . ("arrow_back"    . "Back"))
    (forward . ("arrow_forward" . "Forward"))
    (reload  . ("refresh"       . "Reload"))
    (prev    . ("chevron_left"  . "Previous"))
    (next    . ("chevron_right" . "Next"))
    (up      . ("arrow_upward"  . "Up"))
    (toc     . ("toc"           . "Contents")))
  "Nav op -> (ICON . LABEL) for the toolbar.")

(defun jetpacs-hypertext--nav-mode (&optional buffer)
  "The `jetpacs-hypertext--nav-ops' mode key BUFFER derives from, or nil."
  (with-current-buffer (or buffer (current-buffer))
    (cl-some (lambda (cell) (and (derived-mode-p (car cell)) (car cell)))
             jetpacs-hypertext--nav-ops)))

(defun jetpacs-hypertext--nav-command (mode op)
  "The command for nav OP (a symbol) in MODE, or nil if not allowlisted."
  (cdr (assq op (cdr (assq mode jetpacs-hypertext--nav-ops)))))

(defun jetpacs-hypertext--nav-live-ops (mode)
  "The live nav ops for MODE in the current buffer, in display order.
Liveness is exact where cheap (the history stacks); Info node motion
\(prev/next/up/toc) is always offered — the command self-messages at a
node boundary and the shim swallows it."
  (pcase mode
    ('eww-mode
     (append
      (and (bound-and-true-p eww-history)
           (< eww-history-position (length eww-history)) '(back))
      (and (boundp 'eww-history-position)
           (> eww-history-position 1) '(forward))
      '(reload)))
    ('help-mode
     (append (and (bound-and-true-p help-xref-stack) '(back))
             (and (bound-and-true-p help-xref-forward-stack) '(forward))))
    ('Info-mode
     (append '(prev next up toc)
             (and (bound-and-true-p Info-history) '(back))
             (and (bound-and-true-p Info-history-forward) '(forward))))
    (_ nil)))

(defun jetpacs-hypertext--nav-toolbar (buffer-name mode)
  "An icon-button row of the live nav ops for MODE in the current
buffer, or nil when there are none.  `icon_button' is OPTIONAL
(SPEC 16.2); unadvertised, Core buttons carry the labels.  The
descriptors take the default offline policy (`drop') — a queued
\"go back\" replayed after a reconnect is meaningless."
  (let ((ops (jetpacs-hypertext--nav-live-ops mode))
        (icon-ok (jetpacs-node-advertised-p "icon_button")))
    (when ops
      (apply #'jetpacs-row
             (append
              (mapcar
               (lambda (op)
                 (let ((ico (cdr (assq op jetpacs-hypertext--nav-icons)))
                       (act (jetpacs-action
                             "hypertext.nav"
                             :args (list :buffer buffer-name
                                        :op (symbol-name op)))))
                   (if icon-ok
                       (jetpacs-icon-button (car ico) act
                                            :content-description (cdr ico))
                     (jetpacs-button (cdr ico) act))))
               ops)
              (list :spacing 4))))))

(defun jetpacs-hypertext--refresh (params)
  "Re-push the surface the event came from, deferred.
The seam takes a surface as of JC-1: under decision D1 every owner has
its own, so a zero-arg call would refresh the wrong one.  Deferred
because `jetpacs-shell-push' signals on a gate failure, which must not
escape after the navigation already happened."
  (let ((surface (plist-get params :surface)))
    (run-at-time
     0 nil
     (lambda ()
       (when (functionp jetpacs-buffer-refresh-function)
         (condition-case err
             (funcall jetpacs-buffer-refresh-function surface)
           (error (message "jetpacs-hypertext: refresh failed: %s"
                           (jetpacs--error-label err)))))))))

(jetpacs-defaction "hypertext.nav"
  ;; Navigate a rendered document buffer by running its mode's OWN
  ;; command.  Gate chain (SPEC 23.1/23.2): the buffer must exist, must
  ;; have been PRESENTED by this Emacs to this Companion (the
  ;; whole-buffer exposure record — nav is not snapshot-indexed, so
  ;; there is no per-offset record to consult and no `stale' status to
  ;; derive), must derive from a registered document mode, and the op
  ;; must be in that mode's allowlist.  `intern-soft' cannot mint a
  ;; symbol from wire data.  An op outside the mode's allowlist is
  ;; permanently invalid -> `rejected'.
  (lambda (args params)
    (let* ((buffer (plist-get args :buffer))
           (op (plist-get args :op))
           (buf (and (stringp buffer) (get-buffer buffer))))
      (cond
       ((or (null buf) (not (stringp op))) 'rejected)
       ((not (jetpacs-buffer-exposed-buffer-p buffer "hypertext.nav"))
        'rejected)
       (t
        (with-current-buffer buf
          (let* ((mode (jetpacs-hypertext--nav-mode buf))
                 (cmd (and mode (jetpacs-hypertext--nav-command
                                 mode (intern-soft op)))))
            (if (not (commandp cmd))
                'rejected
              ;; The shim swallows errors and returns a position either
              ;; way, so a failing command is indistinguishable from
              ;; success without the ON-ERROR thunk — `accepted' must
              ;; name a navigation that actually completed (SPEC 14.4).
              (let ((failed nil))
                (jetpacs-buffer-call-shimmed
                 cmd (lambda (_err) (setq failed t)))
                (if failed
                    'rejected
                  (jetpacs-hypertext--refresh params)
                  'accepted))))))))))

(defun jetpacs-hypertext--render-document (buf segments title)
  "Assemble a rendered document for BUF: the nav toolbar (if any) atop
the emitted SEGMENTS, led by TITLE.  Returns a LIST of nodes (the
renderer seam contract).  Runs in BUF for buffer-local nav state.
Shares ONE SPEC 4.5 budget across the whole document, and writes the
whole-buffer exposure record that authorizes `hypertext.nav' for this
buffer until the next render supersedes it."
  (with-current-buffer buf
    (let* ((mode (jetpacs-hypertext--nav-mode buf))
           (toolbar (and mode (jetpacs-hypertext--nav-toolbar
                               (buffer-name buf) mode))))
      (when mode
        (jetpacs-buffer-expose-buffer (buffer-name buf) "hypertext.nav"))
      (jetpacs-buffer-with-budget
        (append (and toolbar (list toolbar))
                (jetpacs-hypertext--emit segments title))))))

(defun jetpacs-hypertext-render (buf)
  "Tier 0.5 renderer for shr-rendered document buffers (registered for
eww).  Falls back to the Tier 0 generic renderer for an empty or
still-loading buffer, or one shr left no recoverable structure in."
  (with-current-buffer buf
    (if (< (buffer-size) 1)
        (jetpacs-buffer-render buf)
      ;; This render supersedes the last one's records (SPEC 23.1); the
      ;; scan below re-exposes the link positions it emits.
      (jetpacs-buffer-forget-exposed (buffer-name buf))
      (let ((model (jetpacs-hypertext--scan-shr buf)))
        (if model
            (jetpacs-hypertext--render-document
             buf (jetpacs-hypertext--eww-resolve-tables model buf)
             (jetpacs-hypertext--eww-title buf))
          (jetpacs-buffer-render buf))))))

;; --- Generic line scanner (for the non-shr text families) --------------------
;;
;; help and Info are not shr buffers; their structure is line-oriented
;; and alignment-bearing (argument lists, menus), so — unlike the shr
;; adapter's block reflow — each non-blank line becomes its own
;; paragraph, preserving layout.  Links and buttons (help xrefs, Info
;; menu entries and *note refs) ride the Tier 0 line-span builder into
;; `emacs.buffer.act' taps for free.

(defun jetpacs-hypertext--scan-lines (buf &optional classify)
  "Scan BUF into a model, one segment per non-blank line (layout
preserved), capped by `jetpacs-hypertext-max-segments'.  CLASSIFY, if
non-nil, is called with (BEG END) at each non-blank line and returns a
heading level (integer) to make that line a heading, the symbol `skip'
to drop it (e.g. an Info underline rule), or nil for a paragraph."
  (with-current-buffer buf
    ;; Colors off: document text is theme-colored (and see the
    ;; `--block-spans' seam note).  A lazily-fontified buffer must be
    ;; fontified first or it renders unstyled below the Tier-0 floor.
    (let ((jetpacs-buffer-emit-colors nil)
          (name (buffer-name buf))
          (count 0)
          segments)
      (ignore-errors (font-lock-ensure (point-min) (point-max)))
      (save-excursion
        (goto-char (point-min))
        (while (and (not (eobp))
                    (< count jetpacs-hypertext-max-segments))
          (let ((bol (line-beginning-position))
                (eol (line-end-position)))
            (unless (>= bol eol)              ; blank line
              (let ((class (and classify (funcall classify bol eol))))
                (cond
                 ((eq class 'skip))
                 ((integerp class)
                  (push (list :kind 'heading :level class
                              :text (jetpacs-hypertext--collapse-ws
                                     (jetpacs-buffer--scalar-text
                                      (buffer-substring-no-properties
                                       bol eol))))
                        segments)
                  (cl-incf count))
                 (t
                  (let ((spans (jetpacs-buffer--line-spans bol eol name)))
                    (when spans
                      (push (list :kind 'para :spans spans) segments)
                      (cl-incf count))))))))
          (forward-line 1))
        (when (and (>= count jetpacs-hypertext-max-segments)
                   (not (eobp)))
          (push (list :kind 'note :text "… document truncated") segments)))
      (nreverse segments))))

;; --- Adapter: help-mode ------------------------------------------------------

(defun jetpacs-hypertext--help-title (buf)
  "A title for help BUF from `help-xref-stack-item' (the current
subject).  Sanitized: the subject can be an arbitrary object printed."
  (with-current-buffer buf
    (and (boundp 'help-xref-stack-item)
         (consp help-xref-stack-item)
         (when-let* ((s (jetpacs-hypertext--nonempty
                         (format "%s" (cadr help-xref-stack-item)))))
           (jetpacs-buffer--scalar-text s)))))

(defun jetpacs-hypertext-render-help (buf)
  "Tier 0.5 renderer for help-mode: a nav toolbar and the help subject
over the help text, whose xref buttons are tappable through the Tier 0
line-span builder."
  (with-current-buffer buf
    (if (< (buffer-size) 1)
        (jetpacs-buffer-render buf)
      (jetpacs-buffer-forget-exposed (buffer-name buf))
      (jetpacs-hypertext--render-document
       buf (jetpacs-hypertext--scan-lines buf)
       (jetpacs-hypertext--help-title buf)))))

;; --- Adapter: Info-mode ------------------------------------------------------

(defun jetpacs-hypertext--info-underlined-level (eol)
  "Heading level if the line ending at EOL is underlined by a rule line
just below it (Info section headings): * chapter = 1, = section = 2,
- sub = 3."
  (save-excursion
    (goto-char eol)
    (when (zerop (forward-line 1))
      (let ((u (string-trim (buffer-substring-no-properties
                             (line-beginning-position)
                             (line-end-position)))))
        (cond ((string-match-p "\\`\\*\\{2,\\}\\'" u) 1)
              ((string-match-p "\\`=\\{2,\\}\\'" u) 2)
              ((string-match-p "\\`-\\{2,\\}\\'" u) 3))))))

(defun jetpacs-hypertext--info-line-class (beg end)
  "Classify an Info line [BEG, END): a heading level, `skip', or nil."
  (let ((text (string-trim (buffer-substring-no-properties beg end))))
    (if (string-match-p "\\`\\(=\\{2,\\}\\|-\\{2,\\}\\|\\*\\{2,\\}\\)\\'" text)
        'skip                               ; a bare underline rule — drop it
      (jetpacs-hypertext--info-underlined-level end))))

(defun jetpacs-hypertext--info-title (buf)
  "A title for Info BUF: its current node name (breadcrumb)."
  (with-current-buffer buf
    (and (boundp 'Info-current-node)
         (when-let* ((s (jetpacs-hypertext--nonempty
                         (format "%s" Info-current-node))))
           (jetpacs-buffer--scalar-text s)))))

(defun jetpacs-hypertext-render-info (buf)
  "Tier 0.5 renderer for Info-mode: a nav toolbar and the node name over
the node body, with menu entries and cross-references tappable via the
Tier 0 line-span builder and === / --- underlined headings lifted to
sections."
  (with-current-buffer buf
    (if (< (buffer-size) 1)
        (jetpacs-buffer-render buf)
      (jetpacs-buffer-forget-exposed (buffer-name buf))
      (jetpacs-hypertext--render-document
       buf (jetpacs-hypertext--scan-lines
            buf #'jetpacs-hypertext--info-line-class)
       (jetpacs-hypertext--info-title buf)))))

;; --- Registrations & third-party riders --------------------------------------

(defun jetpacs-hypertext-register-shr-mode (mode)
  "Register MODE (a major-mode symbol) to render as a hypertext document.
The one-line rider seam for any package whose buffers are shr-rendered
HTML — feed readers, EPUB readers, doc browsers:

  (with-eval-after-load \\='elfeed-show
    (jetpacs-hypertext-register-shr-mode \\='elfeed-show-mode))

Register each concrete mode, never `special-mode' itself: dispatch is by
`derived-mode-p', and half of Emacs derives from special-mode."
  (when (memq mode '(special-mode fundamental-mode text-mode))
    (error "Register the package's own mode, not %s (dispatch is derived-mode-p)"
           mode))
  (jetpacs-render-buffer-register mode #'jetpacs-hypertext-render))

;; eww, help, and Info are built-ins this foundation may name directly.
(jetpacs-render-buffer-register 'eww-mode #'jetpacs-hypertext-render)
(jetpacs-render-buffer-register 'help-mode #'jetpacs-hypertext-render-help)
(jetpacs-render-buffer-register 'Info-mode #'jetpacs-hypertext-render-info)

;; The known third-party shr consumers ride as soon as they load; none
;; is ever required from here.
(with-eval-after-load 'elfeed-show
  (jetpacs-hypertext-register-shr-mode 'elfeed-show-mode))
(with-eval-after-load 'nov
  (jetpacs-hypertext-register-shr-mode 'nov-mode))
(with-eval-after-load 'devdocs
  (jetpacs-hypertext-register-shr-mode 'devdocs-mode))

(provide 'jetpacs-hypertext)
;;; jetpacs-hypertext.el ends here
