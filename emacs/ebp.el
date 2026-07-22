;;; ebp.el --- EBP 2 wire core, client side -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Emacs-side wire core for the Emacs Bridge Protocol, written against
;; ebp/SPEC.md (protocol 2, document 2.0.0-draft).  Rung W1 of
;; docs/REWRITE-PLAN.md: framing (SPEC 6), envelope conventions (SPEC 7),
;; the JSON data-model receiver rules this layer owns (SPEC 4.1),
;; pairing/proof construction (SPEC 9), and a pure client session state
;; machine (SPEC 10.1).  Transport wiring (network process, reconnect)
;; is rung W3 and does not live here yet.
;;
;; Every function cites the section it implements.  Behavior with no
;; section is a bug in this file or an amendment owed to ebp/.

;;; Code:

(require 'cl-lib)

;;;; Errors

;; SPEC 6.2: header-section failures force connection closure.
(define-error 'ebp-frame-close "EBP framing error requiring connection close")
;; SPEC 6.2: EOF in the middle of a frame terminates the session.
(define-error 'ebp-frame-incomplete "EBP frame incomplete at end of stream")
;; SPEC 6.2: invalid UTF-8 or invalid JSON after a complete body.
(define-error 'ebp-parse-error "EBP body is not valid UTF-8 JSON")
;; SPEC 6.2 / 4.1: top-level non-object, batch array, duplicate members.
(define-error 'ebp-invalid-request "EBP body is not a valid single message object")

;;;; Limits (SPEC 4.5, fixed)

(defconst ebp-max-header-octets 8192
  "SPEC 4.5: framing header section limit, including the final CRLF pair.")
(defconst ebp-max-body-octets 4194304
  "SPEC 4.5: JSON body limit in octets.")
(defconst ebp-max-request-id-octets 64
  "SPEC 7.2: request IDs are identifiers of at most 64 ASCII octets.")

;;;; JSON (SPEC 4.1)

(defun ebp--json-parse (text)
  "Parse TEXT as JSON, returning alists/lists.  Signals `ebp-parse-error'."
  (condition-case nil
      (json-parse-string text :object-type 'alist :array-type 'list
                         :null-object :null :false-object :false)
    (error (signal 'ebp-parse-error (list text)))))

(defun ebp--json-serialize (value)
  "Serialize VALUE (alists/plists per `json-serialize') to a JSON string."
  (json-serialize value :null-object :null :false-object :false))

(defun ebp--string-token-end (text start)
  "Index of the closing quote of the JSON string starting at START in TEXT."
  (let ((i (1+ start)) (n (length text)))
    (while (and (< i n) (not (eq (aref text i) ?\")))
      (setq i (if (eq (aref text i) ?\\) (+ i 2) (1+ i))))
    (when (>= i n) (signal 'ebp-parse-error (list "unterminated string")))
    i))

(defun ebp--duplicate-members-p (text)
  "Non-nil when valid-JSON TEXT contains an object with duplicate member names.
SPEC 4.1: a receiver MUST reject duplicate member names.  Key comparison is
semantic (after escape decoding), so \"a\" and \"\\u0061\" collide.
TEXT must already have parsed successfully."
  (let ((i 0) (n (length text)) (stack '()))
    (catch 'dup
      (while (< i n)
        (let ((c (aref text i)))
          (cond
           ((memq c '(?\s ?\t ?\n ?\r)) (cl-incf i))
           ((eq c ?{)
            (push (cons (make-hash-table :test #'equal) 'key) stack)
            (cl-incf i))
           ((eq c ?\[) (push 'arr stack) (cl-incf i))
           ((memq c '(?} ?\])) (pop stack) (cl-incf i))
           ((eq c ?\")
            (let* ((end (ebp--string-token-end text i))
                   (raw (substring text i (1+ end)))
                   (top (car stack)))
              (setq i (1+ end))
              (when (and (consp top) (eq (cdr top) 'key))
                (let ((key (ebp--json-parse raw)))
                  (when (gethash key (car top)) (throw 'dup t))
                  (puthash key t (car top))
                  (setcdr top 'colon)))))
           ((eq c ?:)
            (let ((top (car stack)))
              (when (and (consp top) (eq (cdr top) 'colon))
                (setcdr top 'value)))
            (cl-incf i))
           ((eq c ?,)
            (let ((top (car stack)))
              (when (consp top) (setcdr top 'key)))
            (cl-incf i))
           (t ;; number / true / false / null
            (while (and (< i n)
                        (not (memq (aref text i)
                                   '(?, ?} ?\] ?\s ?\t ?\n ?\r))))
              (cl-incf i))))))
      nil)))

(defun ebp--decode-utf-8 (bytes)
  "Decode unibyte BYTES as strict UTF-8 or signal `ebp-parse-error'.
SPEC 4.1: a receiver MUST reject a body containing invalid UTF-8."
  (let ((decoded (decode-coding-string bytes 'utf-8)))
    ;; Emacs maps undecodable bytes to raw-byte characters above #x10FFFF.
    (if (cl-find-if (lambda (ch) (> ch #x10FFFF)) decoded)
        (signal 'ebp-parse-error (list "invalid UTF-8"))
      decoded)))

;;;; Framing decoder (SPEC 6.2)

(cl-defstruct (ebp-decoder (:constructor ebp-make-decoder))
  (buffer "" :documentation "Pending unibyte bytes."))

(defconst ebp--content-length-re
  "^\\(?:0\\|[1-9][0-9]*\\)$"
  "SPEC 6.1/6.2: unsigned decimal, no leading zeroes except the value 0.")

(defun ebp--parse-header (head)
  "Parse the unibyte header section HEAD (without the final CRLFCRLF).
Return the declared body length or signal `ebp-frame-close' (SPEC 6.2)."
  (let ((lengths '()))
    (dolist (line (split-string head "\r\n" nil))
      (when (string-empty-p line)
        (signal 'ebp-frame-close (list "malformed header line")))
      (let ((colon (string-search ":" line)))
        (unless colon
          (signal 'ebp-frame-close (list "malformed header line")))
        (let ((name (substring line 0 colon))
              ;; Receiver MAY accept optional horizontal whitespace.
              (value (string-trim (substring line (1+ colon)) "[ \t]+" "[ \t]+")))
          (when (string-equal-ignore-case name "Content-Length")
            (unless (string-match-p ebp--content-length-re value)
              (signal 'ebp-frame-close (list "invalid Content-Length value")))
            (push (string-to-number value) lengths)))))
    (unless (= (length lengths) 1)
      (signal 'ebp-frame-close
              (list (if lengths "duplicate Content-Length" "missing Content-Length"))))
    (let ((len (car lengths)))
      (when (> len ebp-max-body-octets)
        ;; SPEC 6.2: close immediately on an oversized declaration.
        (signal 'ebp-frame-close (list "oversized body declaration")))
      len)))

(defun ebp--parse-body (bytes)
  "Decode one complete frame body BYTES into a message object.
SPEC 6.2 + 4.1: strict UTF-8, valid JSON, single top-level object,
no duplicate member names."
  (let* ((text (ebp--decode-utf-8 bytes))
         (value (ebp--json-parse text)))
    (unless (and (listp value) (or (null value) (consp (car value))))
      ;; Top-level arrays (batches) and scalars are prohibited.
      (signal 'ebp-invalid-request (list "top-level value is not an object")))
    ;; `nil' parses ambiguously ({} and [] both -> nil); {} is a valid
    ;; (if useless) message object, [] is a prohibited batch.  Disambiguate
    ;; on the first non-whitespace character.
    (when (and (null value)
               (eq (aref (string-trim-left text) 0) ?\[))
      (signal 'ebp-invalid-request (list "batch arrays are prohibited")))
    (when (ebp--duplicate-members-p text)
      (signal 'ebp-invalid-request (list "duplicate member names")))
    value))

(defun ebp-decoder-feed (decoder bytes)
  "Feed unibyte BYTES into DECODER; return the list of complete messages.
Implements the SPEC 6.2 receiver.  Signals `ebp-frame-close',
`ebp-parse-error', or `ebp-invalid-request' on the conditions the spec
assigns to each."
  (setf (ebp-decoder-buffer decoder)
        (concat (ebp-decoder-buffer decoder) bytes))
  (let ((messages '()) (done nil))
    (while (not done)
      (let* ((buf (ebp-decoder-buffer decoder))
             (term (string-search "\r\n\r\n" buf)))
        (cond
         ((null term)
          ;; SPEC 6.2: the header section may not exceed 8,192 octets.
          (when (> (length buf) ebp-max-header-octets)
            (signal 'ebp-frame-close (list "header section too large")))
          (setq done t))
         ((> (+ term 4) ebp-max-header-octets)
          (signal 'ebp-frame-close (list "header section too large")))
         (t
          (let* ((len (ebp--parse-header (substring buf 0 term)))
                 (body-start (+ term 4))
                 (body-end (+ body-start len)))
            (if (< (length buf) body-end)
                (setq done t)       ; retain partial data across reads
              (setf (ebp-decoder-buffer decoder) (substring buf body-end))
              (push (ebp--parse-body (substring buf body-start body-end))
                    messages)))))))
    (nreverse messages)))

(defun ebp-decoder-finish (decoder)
  "Declare end of stream.  SPEC 6.2: EOF mid-frame terminates the session."
  (unless (string-empty-p (ebp-decoder-buffer decoder))
    (signal 'ebp-frame-incomplete
            (list (length (ebp-decoder-buffer decoder))))))

;;;; Framing encoder (SPEC 6.1)

(defun ebp-encode-frame (json-text)
  "Wrap JSON-TEXT in exact SPEC 6.1 framing; return unibyte bytes.
The length is computed after UTF-8 encoding, never from characters."
  (let ((body (encode-coding-string json-text 'utf-8)))
    (when (> (length body) ebp-max-body-octets)
      (signal 'ebp-frame-close (list "body exceeds max_frame_bytes")))
    (concat (format "Content-Length: %d\r\n\r\n" (length body)) body)))

;;;; Envelope (SPEC 7)

(defun ebp-valid-request-id-p (id)
  "SPEC 7.2: a string identifier of at most 64 ASCII octets, never empty."
  (and (stringp id)
       (<= 1 (length id) ebp-max-request-id-octets)
       (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" id)))

(defun ebp-request (id method params)
  "Build a request plist (SPEC 7.1).  PARAMS must be a JSON object value."
  (unless (ebp-valid-request-id-p id) (error "Invalid request id: %S" id))
  `(:jsonrpc "2.0" :id ,id :method ,method :params ,params))

(defun ebp-notification (method params)
  "Build a notification plist (SPEC 7.1)."
  `(:jsonrpc "2.0" :method ,method :params ,params))

(defun ebp-result-response (id result)
  "Build a success response (SPEC 7.1).  Empty results are {}, never null."
  `(:jsonrpc "2.0" :id ,id :result ,result))

(defun ebp-error-response (id code message &optional data)
  "Build an error response carrying the SPEC 8 shape."
  `(:jsonrpc "2.0" :id ,id
    :error (:code ,code :message ,message
            ,@(when data (list :data data)))))

(defun ebp-message-class (msg)
  "Classify parsed alist MSG per SPEC 7.1.
Returns one of `request', `notification', `response', or nil for a
structurally invalid message."
  (let ((jsonrpc (alist-get 'jsonrpc msg))
        (method (alist-get 'method msg))
        (has-id (assq 'id msg))
        (has-result (assq 'result msg))
        (has-error (assq 'error msg)))
    (cond
     ((not (equal jsonrpc "2.0")) nil)
     ((and method has-id (not has-result) (not has-error)) 'request)
     ((and method (not has-id) (not has-result) (not has-error)) 'notification)
     ((and (not method) has-id (xor has-result has-error)) 'response)
     (t nil))))

;;;; Pairing and proofs (SPEC 9)

(defun ebp--hmac-sha256 (key message)
  "HMAC-SHA256 (RFC 2104) of unibyte MESSAGE with unibyte KEY, binary output."
  (let* ((block 64)
         (key (if (> (length key) block)
                  (secure-hash 'sha256 key nil nil t)
                key))
         (key (concat key (make-string (- block (length key)) 0)))
         (ipad (apply #'unibyte-string
                      (mapcar (lambda (b) (logxor b #x36)) key)))
         (opad (apply #'unibyte-string
                      (mapcar (lambda (b) (logxor b #x5c)) key))))
    (secure-hash 'sha256
                 (concat opad (secure-hash 'sha256 (concat ipad message)
                                           nil nil t))
                 nil nil t)))

(defun ebp--hex (bytes)
  "Lowercase hexadecimal of unibyte BYTES."
  (mapconcat (lambda (b) (format "%02x" b)) bytes ""))

(defun ebp-decode-pairing-token (display)
  "Decode the 22-character base64url token DISPLAY to 16 raw octets.
SPEC 9.1: RFC 4648 base64url with padding omitted; both endpoints MUST
use the decoded raw octets as the HMAC key."
  (unless (and (stringp display) (= (length display) 22))
    (error "Pairing token must be 22 base64url characters"))
  (let ((raw (base64-decode-string (concat display "==") t)))
    (unless (= (length raw) 16)
      (error "Pairing token did not decode to 16 octets"))
    raw))

(defun ebp-valid-nonce-p (s)
  "SPEC 4.4/9.2: exactly 32 lowercase hexadecimal characters."
  (and (stringp s) (string-match-p "\\`[0-9a-f]\\{32\\}\\'" s)))

(defun ebp-valid-proof-p (s)
  "SPEC 4.4: exactly 64 lowercase hexadecimal characters."
  (and (stringp s) (string-match-p "\\`[0-9a-f]\\{64\\}\\'" s)))

(defun ebp-generate-nonce ()
  "Fresh 32-hex nonce from the operating system CSPRNG (SPEC 9.2)."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'binary))
      ;; /dev/urandom is not seekable, so positioned reads are unusable;
      ;; take exactly 16 octets through a pipe instead.
      (call-process "head" "/dev/urandom" t nil "-c" "16"))
    (unless (= (buffer-size) 16)
      (error "CSPRNG read returned %d octets" (buffer-size)))
    (ebp--hex (buffer-string))))

(defun ebp-client-proof (token pairing-id client-nonce server-nonce)
  "SPEC 9.3 client proof over the exact ASCII concatenation."
  (ebp--hex (ebp--hmac-sha256
             token
             (format "EBP/2 client:%s:%s:%s"
                     pairing-id client-nonce server-nonce))))

(defun ebp-server-proof (token pairing-id client-nonce server-nonce)
  "SPEC 9.3 companion proof; note the swapped nonce order."
  (ebp--hex (ebp--hmac-sha256
             token
             (format "EBP/2 companion:%s:%s:%s"
                     pairing-id server-nonce client-nonce))))

(defun ebp--constant-time-equal (a b)
  "Compare strings A and B without early exit on the first difference."
  (and (stringp a) (stringp b)
       (= (length a) (length b))
       (let ((diff 0))
         (dotimes (i (length a))
           (setq diff (logior diff (logxor (aref a i) (aref b i)))))
         (zerop diff))))

(defun ebp-verify-server-proof (proof token pairing-id client-nonce server-nonce)
  "Verify a welcome's server proof (SPEC 9.3).  Malformed proofs never match."
  (and (ebp-valid-proof-p proof)
       (ebp--constant-time-equal
        proof (ebp-server-proof token pairing-id client-nonce server-nonce))))

;;;; Handshake messages (SPEC 9.2)

(defun ebp-hello-params (client-name client-version pairing-id client-nonce wants)
  "Build `session.hello' params (SPEC 9.2)."
  `(:protocol 2
    :client (:name ,client-name :version ,client-version)
    :pairing_id ,pairing-id
    :client_nonce ,client-nonce
    :wants ,(vconcat wants)))

(defun ebp-auth-params (pairing-id client-nonce server-nonce token)
  "Build `auth.response' params with the computed proof (SPEC 9.3)."
  `(:pairing_id ,pairing-id
    :client_nonce ,client-nonce
    :server_nonce ,server-nonce
    :client_proof ,(ebp-client-proof token pairing-id client-nonce server-nonce)))

;;;; Client session state machine (SPEC 10.1), pure

;; States: `connected' -> `challenged' -> `syncing' -> `ready'; any -> `closed'.
;; This is the Emacs-side view: we transition on our own sends and on
;; verified responses.  Transport wiring arrives in rung W3.

(defun ebp-session-step (state event)
  "Pure transition: STATE symbol + EVENT symbol -> new state, or nil if illegal.
Events: `hello-sent', `nonce-received', `auth-sent', `welcome-verified',
`ready-confirmed', `close'."
  (pcase (cons state event)
    (`(connected . hello-sent) 'awaiting-nonce)
    (`(awaiting-nonce . nonce-received) 'challenged)
    (`(challenged . auth-sent) 'awaiting-welcome)
    (`(awaiting-welcome . welcome-verified) 'syncing)
    (`(syncing . ready-confirmed) 'ready)
    (`(,_ . close) 'closed)
    (_ nil)))

(provide 'ebp)
;;; ebp.el ends here
