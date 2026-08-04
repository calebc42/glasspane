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
(require 'jsonrpc)

;;;; User options (custom.el: declared defaults, overridable from init.el
;;;; with `setopt' without touching code; per-connection config plists
;;;; override these per client)

(defgroup ebp nil
  "The Emacs Bridge Protocol endpoint."
  :group 'comm
  :prefix "ebp-")

(defcustom ebp-receipt-file (locate-user-emacs-file "ebp-receipts")
  "Default durable store for accepted EventId receipts (SPEC 14.4).
When built-in SQLite is available this names a SQLite database;
otherwise an append-only text file.  A connection's :receipt-file
config overrides it."
  :type 'file)

(defcustom ebp-replay-retry-delay 5
  "Initial seconds before retrying `queue.replay' (SPEC 15.3).
Each retry doubles the delay, capped at `ebp-replay-retry-max'.
A connection's :replay-retry-delay config overrides it."
  :type 'number)

(defcustom ebp-replay-retry-max 60
  "Ceiling in seconds for the replay retry backoff (SPEC 15.3)."
  :type 'number)

(defcustom ebp-request-timeout 10
  "Seconds before Emacs abandons an ordinary request (SPEC 7.1).
EBP defines no protocol-level deadline; this is a purely local choice,
and expiry sends `rpc.cancel' before the request is treated as
concluded.  nil waits forever.  It does NOT govern the methods the
Companion holds open pending user interaction — see
`ebp-dialog-timeout' and `ebp-capability-timeout', which carry SPEC
7.1's 60-second floor."
  :type '(choice (const :tag "No deadline" nil) number))

(defcustom ebp-dialog-timeout nil
  "Seconds a `dialog.show' request waits before giving up (SPEC 18.1).
The protocol holds a dialog open with no timeout and SPEC 7.1 SHOULDs
that Emacs apply none either — nil, the default.  A number is a local
ceiling and MUST NOT be under 60; a smaller one is raised to the floor.
Abandonment sends `rpc.cancel', so the Companion dismisses the dialog
rather than waiting on a reader that has left."
  :type '(choice (const :tag "No deadline" nil) number))

(defcustom ebp-capability-timeout nil
  "Seconds a `capability.invoke' request waits before giving up.
SPEC 20.2 lets the Companion hold the invocation while the user answers
a runtime permission prompt, which no deadline can predict, so SPEC 7.1
SHOULDs none — nil, the default.  A number MUST NOT be under 60."
  :type '(choice (const :tag "No deadline" nil) number))

(defcustom ebp-log-events nil
  "When non-nil, log full JSON-RPC message bodies to the connection's
`*ebp events*' buffer.  Off by default (SPEC 23.3): message bodies carry
authentication proofs, clipboard text, SMS/call content, and private
editor documents that MUST NOT be captured in the clear.  Enable only for
local development."
  :type 'boolean)

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

(defconst ebp-max-safe-integer 9007199254740991
  "SPEC 4.2: the inclusive EBP integer bound (2^53 - 1).")

(defconst ebp-max-json-depth 64
  "SPEC 4.5: a JSON body nests at most 64 containers.")

(defun ebp--exceeds-depth-p (text)
  "Non-nil if TEXT nests JSON containers past `ebp-max-json-depth'.
One linear scan (string contents and escapes skipped) so a hostile body
is refused before the recursive parser can exhaust the stack (SPEC 4.5)."
  (let ((depth 0) (in-string nil) (escaped nil)
        (i 0) (n (length text)) (over nil))
    (while (and (< i n) (not over))
      (let ((c (aref text i)))
        (cond
         (in-string
          (cond (escaped (setq escaped nil))
                ((eq c ?\\) (setq escaped t))
                ((eq c ?\") (setq in-string nil))))
         ((eq c ?\") (setq in-string t))
         ((or (eq c ?{) (eq c ?\[))
          (setq depth (1+ depth))
          (when (> depth ebp-max-json-depth) (setq over t)))
         ((or (eq c ?}) (eq c ?\])) (setq depth (1- depth)))))
      (setq i (1+ i)))
    over))

(defun ebp--check-numbers (value)
  "Signal `ebp-parse-error' if VALUE carries a number SPEC 4.2 forbids.
Amendment #99: an integral literal outside the safe range, or a literal
that overflowed to an infinity, cannot be carried by this data model, so
it is refused during decoding on the same terms as the 4.5 depth limit.
Emacs reads oversized integers as bignums and overflowing literals as
infinities, so both survive `json-parse-string' silently otherwise.  A
literal that underflowed to zero decodes AS zero and is accepted.
VALUE is walked structurally: alist conses and array lists alike."
  (cond
   ((integerp value)
    (when (or (> value ebp-max-safe-integer)
              (< value (- ebp-max-safe-integer)))
      (signal 'ebp-parse-error (list "integer out of range"))))
   ((floatp value)
    (when (or (isnan value) (= value 1.0e+INF) (= value -1.0e+INF))
      (signal 'ebp-parse-error (list "number out of range"))))
   ((consp value)
    (ebp--check-numbers (car value))
    (ebp--check-numbers (cdr value)))))

(defun ebp--json-serialize (value)
  "Serialize VALUE (alists/plists per `json-serialize') to a JSON string."
  (json-serialize value :null-object :null :false-object :false))

(defconst ebp--empty-object (make-hash-table :test #'equal :size 1)
  "Serializes as {} — SPEC 7.1 requires object params, never null.")

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
  "\\`\\(?:0\\|[1-9][0-9]*\\)\\'"
  "SPEC 6.1/6.2: unsigned decimal, no leading zeroes except the value 0.
Anchored to the whole STRING (\\=\\` and \\=\\'), not to lines: Emacs `^' and
`$' match at line boundaries, so the line-anchored form accepted a bare
LF inside the value and a value like \"2\\nX: 1\" passed as 2.  The header
section is split on CRLF only, so such a value is reachable on the wire.")

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
  (let ((text (ebp--decode-utf-8 bytes)))
    ;; SPEC 4.5/23.5: refuse an over-deep body before the recursive parser
    ;; can exhaust the stack — enforcement precedes expensive decoding.
    (when (ebp--exceeds-depth-p text)
      (signal 'ebp-parse-error (list "nesting depth exceeds 64")))
    (let ((value (ebp--json-parse text)))
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
      ;; SPEC 4.2 (amendment #99): numbers this data model cannot carry.
      (ebp--check-numbers value)
      value)))

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
  "SPEC 7.2: a string identifier of at most 64 ASCII octets (never
empty), or a safe integer.  Amendments #34/#80: jsonrpc.el's sequential
integer ids conform without adaptation; `null' and fractional numbers
do not."
  (or (and (integerp id)
           (<= (- ebp-max-safe-integer) id ebp-max-safe-integer))
      (and (stringp id)
           (<= 1 (length id) ebp-max-request-id-octets)
           (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9._:/-]*\\'" id))))

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

;;;; The connection subclass (kit section 3's sanctioned seam)

;; jsonrpc.el's dispatch loop strips `:data' from outbound error replies
;; (verified against 1.0.25, and documented in the conversion kit).  SPEC 8
;; requires every EBP error to carry `data.kind', and SPEC 15.3 degrades
;; `blocked_by' to "json-rpc-error" without it.  The reply is emitted
;; synchronously within the dispatch extent, so a handler stashes its data
;; on the connection and this override re-attaches it.

(defclass ebp--connection (jsonrpc-process-connection)
  ((ebp-error-data :initform nil :accessor ebp--connection-error-data)
   (ebp-client :initform nil :accessor ebp--connection-client)))

(cl-defmethod jsonrpc-convert-to-endpoint ((conn ebp--connection)
                                           _message subtype)
  (let ((converted (cl-call-next-method)))
    (when-let* ((data (ebp--connection-error-data conn)))
      (setf (ebp--connection-error-data conn) nil)
      (when (eq subtype 'reply)
        (when-let* ((err (plist-get converted :error)))
          (plist-put err :data data))))
    converted))

;; SPEC 22.3 / amendment #124 (W10): every outbound write — request,
;; notification, or reply; they all funnel through this generic — resumes
;; a paused reader FIRST and stakes the in-send claim the pause path
;; consults.  This is the A8 §1.5 invariant in code: reading may pause
;; only while nothing of ours is in flight, because our re-entrant
;; reading inside a blocked send is what unwedges a Companion whose
;; single reader thread is blocked writing to us.
(defvar ebp--in-send)                   ; defined with the overload section

(cl-defmethod jsonrpc-connection-send :around ((conn ebp--connection)
                                               &rest _args
                                               &key &allow-other-keys)
  (when-let* ((client (ebp--connection-client conn)))
    (ebp-client--inbound-resume client))
  (let ((ebp--in-send t))
    (cl-call-next-method)))

(defun ebp-client--error (client code message kind &rest extra)
  "Signal a SPEC 8 error whose `data.kind' survives the reply path."
  (when-let* ((conn (ebp-client-connection client)))
    (setf (ebp--connection-error-data conn)
          (append (list :kind kind) extra)))
  (jsonrpc-error :code code :message message))

;;;; Client engine (SPEC 9-10) on core jsonrpc.el

;; Decision log #2 (ebp slop-docs/JSONRPC-conversion-kit.md): the Emacs
;; side rents core jsonrpc.el unmodified for transport, framing, and id
;; bookkeeping.  What remains ours — because the library is deliberately
;; fail-open — is everything these dispatchers and drivers do: the
;; fail-closed handshake, hand-rolled -32601, session state, the welcome
;; verification, the 10.3 barrier, and surface revisions.  The strict
;; decoder/encoder above stay exported as the reference SPEC 6 receiver
;; (conformance suites, future non-jsonrpc transports); the live
;; connection reads with jsonrpc.el's tolerances, as SPEC 6.2 permits
;; the Emacs endpoint.

(cl-defstruct (ebp-client (:constructor ebp--make-client))
  (state 'connected)
  config          ; plist: :client-name :client-version :pairing-id :token
                  ;        :wants, :receipt-file, and for tests :client-nonce
  connection      ; jsonrpc-process-connection
  (handlers (make-hash-table :test #'equal)) ; method-name -> fn
  client-nonce
  ;; Welcome absorption (SPEC 10.2/10.3 steps 1-2).
  granted profiles surfaces limits input-state
  ;; SPEC 20.1: the device report, present when capabilities/triggers granted.
  device
  ;; SPEC 13.1: monotonic per-surface revisions; floors absorbed from the
  ;; welcome and from every applied/stale result.
  (revisions (make-hash-table :test #'equal))
  ;; SPEC 14: the action allowlist and the durable EventId receipts.
  (actions (make-hash-table :test #'equal))
  (receipts (make-hash-table :test #'equal))
  receipt-db     ; sqlite handle when the backend is built-in SQLite
  ;; SPEC 14.6: latest input values by (surface . id), and this side's
  ;; reset history for the P1 #2 reconciliation rule.
  (input-values (make-hash-table :test #'equal))
  (reset-history (make-hash-table :test #'equal))
  state-changed-functions ; called with (client surface revision id value)
  ;; SPEC 20.1.1: the last-reported window geometry plist
  ;; (:width_dp :height_dp :width_class :height_class), from the welcome
  ;; mirror and every window.changed since.
  window
  window-changed-functions ; called with (client window-plist)
  ;; SPEC 19: Emacs's mirror of synchronized editors, (doc . id) ->
  ;; plist (:session :seq :text :cursor).  Emacs chars ARE Unicode
  ;; scalar values, so splice positions are char positions directly.
  (editors (make-hash-table :test #'equal))
  edit-change-functions ; called with (client document editor-id text)
  ;; SPEC 19.3 (amendment #71): called with (client document editor-id
  ;; seed-text prior-text) when edit.open arrives, so the application can
  ;; compare the seed against its real document and reconcile explicitly.
  edit-open-functions
  ready-functions ; abnormal hook: called with the client on READY
  ;; SPEC 15.3: the latest replay summary and the bounded-backoff timer
  ;; that retries while `remaining' is nonzero.
  replay-summary
  replay-retry-timer   ; PENDING retry, nil once it fires (see #--schedule)
  replay-in-flight     ; a queue.replay request awaiting its answer
  ;; Called with (client summary) when a replay pass settles with the
  ;; backlog drained (remaining 0) in READY — the application's seam for
  ;; refreshing views that replayed events just mutated.
  after-replay-functions
  close-reason
  ;; SPEC 22.3 (W10, docs/W10-overload-plan.md): the Emacs endpoint's own
  ;; bounds.  `process' is ours — `ebp-connect' creates it — so the
  ;; inbound half can stop/continue reading without touching jsonrpc
  ;; internals.
  process
  (outstanding 0)  ; requests in flight (the sender-side ceiling)
  outstanding-held ; sticky refusal latch until <= `ebp-overload-resume'
  inbound-paused   ; reading stopped for transport backpressure
  overloaded)      ; 1401 sent, close in progress — the rate-limit latch

(defun ebp-client-create (&rest config)
  "Create a client engine in `connected'.  CONFIG is the struct's config
plist plus optionally :ready-function, :state-changed-function,
:before-replay-function (the SPEC 10.3 step-3 seam),
:after-replay-function (called with (CLIENT SUMMARY) when a replay pass
settles with the backlog drained), :edit-open-function (the SPEC 19.3
amendment-#71 seed-reconciliation seam), :receipt-file, and
:replay-retry-delay.  Without :receipt-file the SPEC 14.4 EventId
receipts default to `ebp-receipts' under `user-emacs-directory' —
`accepted' always names a durable commitment."
  (unless (plist-member config :receipt-file)
    (setq config (plist-put (copy-sequence config) :receipt-file
                            ebp-receipt-file)))
  (let ((client (ebp--make-client :config config)))
    (when-let* ((fn (plist-get config :ready-function)))
      (push fn (ebp-client-ready-functions client)))
    (when-let* ((fn (plist-get config :state-changed-function)))
      (push fn (ebp-client-state-changed-functions client)))
    ;; The endpoint's own SPEC 14 method servers; their registered
    ;; content is the application's (REWRITE-PLAN boundary).
    (ebp-client-register-handler client "event.action"
                                 #'ebp-client--handle-event-action)
    (ebp-client-register-handler client "state.changed"
                                 #'ebp-client--handle-state-changed)
    (ebp-client-register-handler client "window.changed"
                                 #'ebp-client--handle-window-changed)
    (when-let* ((fn (plist-get config :edit-change-function)))
      (push fn (ebp-client-edit-change-functions client)))
    (when-let* ((fn (plist-get config :edit-open-function)))
      (push fn (ebp-client-edit-open-functions client)))
    (when-let* ((fn (plist-get config :after-replay-function)))
      (push fn (ebp-client-after-replay-functions client)))
    (ebp-client-register-handler client "edit.open"
                                 #'ebp-client--handle-edit-open)
    (ebp-client-register-handler client "edit.delta"
                                 #'ebp-client--handle-edit-delta)
    (ebp-client-register-handler client "edit.caret"
                                 #'ebp-client--handle-edit-caret)
    (ebp-client-register-handler client "edit.close"
                                 #'ebp-client--handle-edit-close)
    (ebp-client-register-handler client "edit.complete"
                                 #'ebp-client--handle-edit-complete)
    (ebp-client--receipts-load client)
    client))

(defun ebp-client-register-handler (client method fn)
  "Register FN for inbound METHOD (a string).
For a request, FN is called with (CLIENT PARAMS) and must return the
result object or signal `jsonrpc-error'; the reply is the library's.
For a notification the return value is ignored."
  (puthash method fn (ebp-client-handlers client)))

(defun ebp-client-close (client reason)
  "Enter `closed' (SPEC 10.1: any state may transition to CLOSED)."
  (unless (eq (ebp-client-state client) 'closed)
    (setf (ebp-client-state client) 'closed
          (ebp-client-close-reason client) reason)
    (when-let* ((timer (ebp-client-replay-retry-timer client)))
      (cancel-timer timer)
      (setf (ebp-client-replay-retry-timer client) nil))
    (setf (ebp-client-replay-in-flight client) nil)
    (when-let* ((db (ebp-client-receipt-db client)))
      (ignore-errors (sqlite-close db))
      (setf (ebp-client-receipt-db client) nil))
    (when-let* ((conn (ebp-client-connection client)))
      (ignore-errors (jsonrpc-shutdown conn)))))

(defun ebp-client-forget-pairing (client)
  "SPEC 9.1 (amendment #72): local removal of this pairing.
Closes the connection, durably erases the EventId receipt store (the
SQLite or text file and its sidecars), clears the in-memory receipts,
and scrubs the token from this client's config.  Erasure covers
everything this library persists; a copy of the token the application
stored elsewhere (auth-source, custom code) is the application's to
erase.  Removal at this endpoint prevents future authentication but
cannot erase storage on a disconnected Companion (SPEC 9.1).

Returns t when erasure completed, nil when any part failed — so a
caller can tell the user the pairing is NOT fully forgotten instead of
reporting a success that did not happen.

The token is destroyed with `clear-string', which zeroes it in place:
the config holds the CALLER's string, so dropping this client's
reference alone would leave the secret live in the caller's structure.

The receipt store is process-wide, not partitioned by pairing.  Under
`android-loopback-tcp' that is exact — the profile permits exactly one
paired authority (SPEC 5.2) — but a multi-authority profile MUST
partition it before reusing this."
  (ebp-client-close client 'forget-pairing)
  (let ((ok t))
    (when-let* ((file (plist-get (ebp-client-config client) :receipt-file)))
      (dolist (f (list file (concat file "-wal") (concat file "-shm")))
        (when (file-exists-p f)
          (condition-case err
              (delete-file f)
            (error (setq ok nil)
                   (message "ebp: could not erase receipt store %s: %s"
                            f (car err)))))))
    ;; Every in-memory store scoped to the identity (SPEC 9.1 names
    ;; queued payloads, input drafts, cached surfaces, tombstones ...).
    (clrhash (ebp-client-receipts client))
    (clrhash (ebp-client-input-values client))
    (clrhash (ebp-client-reset-history client))
    (clrhash (ebp-client-revisions client))
    (clrhash (ebp-client-editors client))
    (setf (ebp-client-surfaces client) nil
          (ebp-client-input-state client) nil)
    (let ((token (plist-get (ebp-client-config client) :token)))
      (when (stringp token) (ignore-errors (clear-string token))))
    (setf (ebp-client-config client)
          (plist-put (ebp-client-config client) :token nil))
    ok))

(defun ebp-client--step (client event)
  "Advance the pure SPEC 10.1 machine or close on an illegal EVENT."
  (let ((next (ebp-session-step (ebp-client-state client) event)))
    (if next
        (setf (ebp-client-state client) next)
      (ebp-client-close client (list 'illegal-transition
                                     (ebp-client-state client) event)))))

(defun ebp-client--cancel (client id)
  "SPEC 7.1/7.5: announce local abandonment of outstanding request ID.
jsonrpc.el's timeout deletes the continuation, logs, and writes NOTHING
to the peer (emacs-30.1 jsonrpc.el:891-896), so without this the
responder holds the request outstanding forever and the id — which SPEC
7.2 forbids reusing until the request has concluded — never concludes.
`rpc.cancel' is legal only after authentication; before that SPEC 9
closes the transport instead of appending a frame."
  (when (memq (ebp-client-state client) '(syncing ready))
    (ignore-errors (ebp-client-notify client 'rpc.cancel (list :id id)))))

(defun ebp-client--user-paced-timeout (secs)
  "SPEC 7.1: clamp SECS for a method the responder holds pending user
interaction (`dialog.show' SPEC 18.1, `capability.invoke' SPEC 20.2).
nil means no deadline, which the spec SHOULDs; anything under the
60-second floor is raised to it rather than silently honoured."
  (cond ((null secs) nil)
        ((< secs 60)
         (display-warning
          'ebp (format "request timeout %ss is below SPEC 7.1's 60 s floor \
for user-paced methods; using 60" secs)
          :warning)
         60)
        (t secs)))

;;;; Overload (SPEC 22.3), the Emacs endpoint's own bounds — W10

;; docs/W10-overload-plan.md is the design record; RESEARCH-A8 §1/§7 the
;; fact base.  Amendment #125: these bounds are not relaxed by renting
;; jsonrpc.el — its queues are our queues.  The inbound half's shaping
;; constraint (A8 §1.5): pausing the reader while one of our sends is in
;; flight can convert overload into deadlock, so a pause is never taken
;; inside a send and every send path resumes reading first (the :around
;; method on `jsonrpc-connection-send' above).

(defconst ebp-overload-hold 512
  "SPEC 22.3 high-water mark: refuse/pause at this much queued work.
Mirrors the Companion's `PENDING_HOLD' so both ends share one figure.")

(defconst ebp-overload-resume 128
  "SPEC 22.3 low-water mark: resume below this.  Twin of `PENDING_RESUME'.")

(defconst ebp-overload-exhaust 2048
  "SPEC 22.3 exhaustion: a parsed backlog this deep is reachable only by
growth during sends, where pausing is forbidden (A8 §1.5) — capacity is
declared exhausted: one `log.error' 1401, then close.")

(defconst ebp-max-dispatch-depth 32
  "Bound on re-entrant dispatch depth (SPEC 22.3 via amendment #124).
Each level is an inbound message dispatched from inside a blocked send
that is itself inside such a dispatch (A8 §1.4: nesting unbounded,
completion LIFO); past this the stack itself is the exhausted resource.")

(defvar ebp--in-send nil
  "Non-nil while `jsonrpc-connection-send' is on the stack for an ebp
connection.  The pause path consults it: never stop reading inside a
send (amendment #124: state a send claimed stays claimed).")

(defvar ebp--in-filter nil
  "Non-nil while our process-filter wrapper is on the stack.
The backlog check runs only at the OUTERMOST exit — jsonrpc.el's filter
can be re-entered (bug#60088's shape), and an inner exit would measure a
queue the outer invocation is still filling.")

(defvar ebp--dispatch-depth 0
  "Current re-entrant inbound dispatch depth (SPEC 22.3, amendment #124).")

(defun ebp-client--backlog (client)
  "Parsed-but-undispatched inbound messages for CLIENT.
jsonrpc.el's filter drains its `jsonrpc-mqueue' process property into
0-delay timers at every invocation's end (emacs-30.1 jsonrpc.el:770-812),
so the parsed-message queue LIVES in `timer-list': ours are exactly the
timers whose args lead with our connection object."
  (let ((conn (ebp-client-connection client)) (n 0))
    (dolist (tm timer-list n)
      (when (eq (car-safe (timer--args tm)) conn)
        (setq n (1+ n))))))

(defun ebp-client--inbound-pause (client)
  "Stop reading — §22.3's transport backpressure — never inside a send."
  (let ((proc (ebp-client-process client)))
    (when (and proc (not ebp--in-send)
               (not (ebp-client-inbound-paused client))
               (process-live-p proc))
      (setf (ebp-client-inbound-paused client) t)
      (stop-process proc))))

(defun ebp-client--inbound-resume (client)
  "Resume reading.  The send path calls this FIRST (A8 §1.5 invariant)."
  (let ((proc (ebp-client-process client)))
    (when (and proc (ebp-client-inbound-paused client))
      (setf (ebp-client-inbound-paused client) nil)
      (when (process-live-p proc)
        (continue-process proc)))))

(defun ebp-client--inbound-check (client)
  "At the outermost filter exit: pause at HOLD, close past EXHAUST."
  (unless (ebp-client-overloaded client)
    (let ((backlog (ebp-client--backlog client)))
      (cond
       ((>= backlog ebp-overload-exhaust)
        (ebp-client--overload-close client 'inbound-backlog))
       ((>= backlog ebp-overload-hold)
        (ebp-client--inbound-pause client))))))

(defun ebp-client--overload-close (client why)
  "SPEC 22.3: capacity exhausted — one `log.error' 1401, then close.
The once-per-connection latch IS the required rate limit: the close
that MUST follow the report makes a second report impossible."
  (unless (ebp-client-overloaded client)
    (setf (ebp-client-overloaded client) t)
    (ignore-errors
      (ebp-client-notify client 'log.error
                         (list :code 1401
                               :message "Inbound processing capacity exhausted"
                               :data (list :kind "overloaded"))))
    (message "ebp: overloaded (%s); closing" why)
    (ebp-client-close client (list 'overloaded why))))

;;;; Rented-library sink redaction and decode isolation (SPEC 23.3/23.5)

(defun ebp--jsonrpc-warn-redact (orig format &rest args)
  "Redact `jsonrpc--warn' while our process filter is on the stack.
jsonrpc.el's only payload-carrying warn site is the in-filter decode
failure (emacs-30.1 jsonrpc.el:768: \"Invalid JSON: %s %s\" with the
whole `buffer-string'), which writes the raw frame body — a volatile
password value, an auth proof — to *Warnings* AND *Messages*.  SPEC 23.3
names both as forbidden sinks, and disabling the events buffer
\(`ebp-connect') does not cover them.  Gating on `ebp--in-filter' keeps
this advice inert for every other jsonrpc.el consumer in the session
\(eglot's warnings pass through untouched)."
  (if (or ebp-log-events (not ebp--in-filter))
      (apply orig format args)
    (funcall orig "%s"
             "ebp: jsonrpc diagnostic redacted (SPEC 23.3; set `ebp-log-events' to t to include frame bodies)")))

(unless (advice-member-p #'ebp--jsonrpc-warn-redact 'jsonrpc--warn)
  (advice-add 'jsonrpc--warn :around #'ebp--jsonrpc-warn-redact))

(defconst ebp--unknown-method-sentinel "ebp.unknown-method"
  "Replacement for an inbound method name no handler is registered for.
jsonrpc.el `intern's the method name before any dispatch check
\(emacs-30.1 jsonrpc.el:305,320 — the exact behavior SPEC 23.5's note
names), so a peer's choice of names would grow the global obarray for
the life of the process.  Substituting this sentinel BEFORE dispatch
keeps the growth at one symbol; behavior is unchanged because the
dispatchers answer any unregistered method with -32601 (requests) or a
logged ignore (notifications) either way — the substitution reaches
exactly the messages already bound for those arms.")
;; Pre-intern it so the first hostile frame allocates nothing.
(intern ebp--unknown-method-sentinel)

(defun ebp--remap-decoded (tree)
  "Re-home symbols in decoded TREE onto the global obarray, in place.
The decode ran under a throwaway `obarray' (see `ebp-connect'), so every
member-name keyword it interned is invisible to `plist-get' against our
source-literal keywords.  Any symbol whose name is already globally
interned — the envelope keys, every contract member name our code
mentions — is replaced by its global twin; a name interned nowhere else
is peer-invented, and KEEPING the throwaway symbol is the point: it dies
with the message (SPEC 23.5).  Idempotent, so re-walking an
already-remapped message is safe."
  (cond
   ((consp tree)
    (let ((cell tree))
      (while (consp cell)
        (let ((head (car cell)))
          (cond
           ((symbolp head)
            (let ((global (and head (intern-soft (symbol-name head)))))
              (when (and global (not (eq global head)))
                (setcar cell global))))
           ((or (consp head) (vectorp head))
            (ebp--remap-decoded head))))
        (setq cell (cdr cell))))
    tree)
   ((vectorp tree)
    (dotimes (i (length tree))
      (let ((el (aref tree i)))
        (cond
         ((symbolp el)
          (let ((global (and el (intern-soft (symbol-name el)))))
            (when (and global (not (eq global el)))
              (aset tree i global))))
         ((or (consp el) (vectorp el))
          (ebp--remap-decoded el)))))
    tree)
   (t tree)))

(defun ebp--isolate-parsed-messages (client)
  "Remap the parsed-but-undispatched inbound queue for CLIENT.
Runs at the filter wrapper's exit, after the decode that ran under a
throwaway `obarray' and before any dispatch timer can fire (timers
cannot run inside a process filter's synchronous extent).  jsonrpc.el
drained its mqueue into 0-delay timers, so the queue to walk is exactly
`ebp-client--backlog's: timers whose args lead with our connection.
Each message gets (a) its keyword tree re-homed onto the global obarray
and (b) an unregistered method name replaced by the sentinel, so
jsonrpc.el's pre-dispatch `intern' of it never reaches the global
obarray (SPEC 23.5)."
  (let ((conn (ebp-client-connection client)))
    (dolist (tm timer-list)
      (when (eq (car-safe (timer--args tm)) conn)
        (let ((msg (cadr (timer--args tm))))
          (when (consp msg)
            (ebp--remap-decoded msg)
            (let ((method (plist-get msg :method)))
              (when (and (stringp method)
                         (not (gethash method (ebp-client-handlers client))))
                (plist-put msg :method ebp--unknown-method-sentinel)))))))))

(defmacro ebp--with-dispatch (client &rest body)
  "Run BODY as one depth-bounded inbound dispatch (SPEC 22.3, #124).
Past `ebp-max-dispatch-depth' the client is overload-closed and BODY
never runs — the 1401 signal concludes a request cheaply; from a
notification's bare dispatch it lands in the timer, which swallows it.
Doubles as a drain point: a paused reader resumes at the low-water mark."
  (declare (indent 1))
  `(let ((ebp--dispatch-depth (1+ ebp--dispatch-depth)))
     (when (> ebp--dispatch-depth ebp-max-dispatch-depth)
       (ebp-client--overload-close ,client 'dispatch-depth)
       (jsonrpc-error :code 1401 :message "Overloaded"))
     (when (and (ebp-client-inbound-paused ,client)
                (<= (ebp-client--backlog ,client) ebp-overload-resume))
       (ebp-client--inbound-resume ,client))
     ,@body))

;; SPEC 24.2: the reference endpoint gates its own sends.  The welcome's
;; `granted' was absorbed (SPEC 10.2) but never consulted — the v2
;; review's open P1: `theme.set'/`dialog.show' emitted unconditionally,
;; so a consumer using ebp.el as the reference endpoint was ungated.
(define-error 'ebp-ungranted
              "EBP method requires a capability the welcome did not grant")

(defconst ebp--method-capabilities
  '((dialog\.show       . "surfaces.dialog")
    (toast\.show        . "presentation.toast")
    (pie_menu\.show     . "presentation.pie-menu")
    (pie_menu\.dismiss  . "presentation.pie-menu")
    (theme\.set         . "theme")
    (reminders\.set     . "reminders.owner")
    (edit\.resync       . "editor.sync")
    (edit\.apply        . "editor.sync")
    (diagnostics\.show  . "editor.sync")
    (eldoc\.show        . "editor.sync")
    (fontify\.show      . "editor.sync")
    (capability\.invoke . "capabilities")
    (triggers\.set      . "triggers"))
  "Emacs-sender method → the SPEC 22.1 capability that gates it.
Mirrors the `capability' field of the contract's method registry for
every unconditionally gated Emacs-or-either-sender method; the wire
suite pins the two together so registry drift is a test failure, not a
runtime surprise (the same contract the Kotlin `MethodRegistry`
carries).  Methods whose contract capability is `core' are ungated and
deliberately absent.  `surface.update' is `core-or-surface-capability':
its gate depends on the surface namespace, which a method-level table
cannot express, so the namespace rule stays with the callers.")

(defun ebp-client--check-granted (client method)
  "Signal `ebp-ungranted' unless METHOD's gating capability was granted.
Fail closed: before any welcome is absorbed, every gated METHOD
refuses — `granted' is nil and a gated send pre-`READY' is illegal
anyway (SPEC 11).  Signal data is (METHOD CAPABILITY).  Callers that
gate above this (`jetpacs-granted-p' branches) never reach the signal,
so their user-visible taxonomy is unchanged; a caller that reaches it
has a gating bug, and the reference endpoint refuses to convert that
bug into non-conformant wire traffic."
  (when-let* ((cap (alist-get method ebp--method-capabilities)))
    (unless (seq-contains-p (ebp-client-granted client) cap)
      (signal 'ebp-ungranted (list method cap)))))

(defun ebp-client--request (client method params callback &optional timeout)
  "Send a request through jsonrpc.el; ids are the library's integers.
CALLBACK receives (RESULT ERROR); exactly one is non-nil except for the
{} result, where both may be nil — check ERROR, not RESULT.

TIMEOUT is a number of seconds, the symbol `none' for no deadline at
all, or nil for `ebp-request-timeout'.  EBP itself defines no deadline
(SPEC 7.1); every one of these is a purely local choice, and expiry is
ABANDONMENT — so it sends `rpc.cancel' before treating the request as
concluded, and jsonrpc.el's own removal of the continuation supplies the
matching \"ignore any later response\" half.

Returns the request's wire ID, usable with `ebp-client-abandon' when the
CALLER abandons before any deadline (a local `keyboard-quit' out of a
synchronous wait, for instance) — or nil when the SPEC 22.3 sender
ceiling refused the request: hold at `ebp-overload-hold' outstanding,
resume at `ebp-overload-resume' (sticky hysteresis, the Companion's
twin), concluding the refused CALLBACK locally, synchronously, and
exactly once with `1401 overloaded' — self-inflicted load never closes
the connection and never touches the wire.  `queue.replay' is exempt:
the §15.3 replay is single-flight, so it cannot be the resource the
ceiling protects, while refusing it would stall durable delivery on our
own load (§22.3's forged-`blocked_by' clause).

Signals `ebp-ungranted' for a capability-gated METHOD the session has
not granted (SPEC 24.2) — before the overload ceiling, since an
ungranted send is a caller bug, never load."
  (ebp-client--check-granted client method)
  (when (and (ebp-client-outstanding-held client)
             (<= (ebp-client-outstanding client) ebp-overload-resume))
    (setf (ebp-client-outstanding-held client) nil))
  (if (and (not (eq method 'queue.replay))
           (or (ebp-client-outstanding-held client)
               (>= (ebp-client-outstanding client) ebp-overload-hold)))
      (progn
        (setf (ebp-client-outstanding-held client) t)
        ;; :ebp-local marks this as OUR synthetic refusal — callback-only,
        ;; never serialized.  A peer's 1401 is byte-identical otherwise
        ;; (1401 is a MANDATORY response code for max_dialogs), and the
        ;; will-retry semantics belong ONLY to the local ceiling.
        (funcall callback nil '(:code 1401
                                :message "Outstanding requests exhausted"
                                :data (:kind "overloaded")
                                :ebp-local t))
        nil)
    (let* ((conn (ebp-client-connection client))
           (secs (cond ((eq timeout 'none) nil)
                       ((numberp timeout) timeout)
                       (t ebp-request-timeout)))
           ;; emacs-30.1 jsonrpc.el:882 takes (cl-incf (jsonrpc--next-request-id
           ;; conn)) for every non-deferred request, and `jsonrpc-async-request'
           ;; returns nil — this is the only way to learn the id we must cancel.
           ;; We never pass :deferred, and the counter only ever increases, so
           ;; SPEC 7.1's "MUST NOT reuse the id" holds structurally.
           (id (1+ (jsonrpc--next-request-id conn)))
           (done nil)
           (finish
            (lambda (result error)
              ;; Decrement exactly once, whichever way the request
              ;; concludes (answer, close-fails-locally, timeout); the
              ;; callback then runs as one depth-bounded dispatch —
              ;; continuations nest inside sends exactly like handlers.
              (unless done
                (setq done t)
                (cl-decf (ebp-client-outstanding client)))
              (ebp--with-dispatch client
                (funcall callback result error)))))
      (cl-incf (ebp-client-outstanding client))
      (condition-case err
          (jsonrpc-async-request
           conn method params
           :timeout secs
           :success-fn (lambda (result) (funcall finish result nil))
           :error-fn (lambda (error)
                       (funcall finish nil (or error '(:code -32603))))
           :timeout-fn (lambda ()
                         (ebp-client--cancel client id)
                         (funcall finish nil '(:code -32000 :message "timeout"))))
        (error
         ;; The send SIGNALLED, so no continuation was registered and no
         ;; callback will ever run — without this rollback the claim above
         ;; is permanent and the session walks toward `ebp-overload-hold'
         ;; on requests that never existed.  Reachable today: a param that
         ;; `json-serialize' refuses (a raw-byte string, a non-finite
         ;; float) signals out of `jsonrpc-connection-send', and callers
         ;; like `jetpacs-shell-push' catch that by design.  The signal
         ;; must still reach them, so re-raise after the rollback.
         (unless done
           (setq done t)
           (cl-decf (ebp-client-outstanding client)))
         (signal (car err) (cdr err))))
      id)))

(defun ebp-client-abandon (client id)
  "Announce local abandonment of outstanding request ID (SPEC 7.1/7.5).
The public face of the expiry path's `rpc.cancel', for when the CALLER
gives up before any local deadline — canonically a `keyboard-quit' out
of a synchronous wait over an async request, e.g. a bridged prompt
dialog, which SPEC 18.1 then concludes with error 1301 and dismisses on
the device.

Send-only: jsonrpc.el still holds the continuation, so the request's
callback WILL fire when the peer answers (normally with 1301).  A
caller that abandons must arrange for its callback to no-op afterwards."
  (ebp-client--cancel client id))

(defun ebp-client-notify (client method params)
  "Send a notification (SPEC 7.1).
Signals `ebp-ungranted' for a capability-gated METHOD the session has
not granted (SPEC 24.2; fail closed before any welcome)."
  (ebp-client--check-granted client method)
  (jsonrpc-notify (ebp-client-connection client) method params))

;;;###autoload
(defun ebp-client-start (client)
  "Send `session.hello' (SPEC 9.2) and drive the handshake to READY."
  (let* ((config (ebp-client-config client))
         (nonce (or (plist-get config :client-nonce) (ebp-generate-nonce))))
    (setf (ebp-client-client-nonce client) nonce)
    (ebp-client--request
     client 'session.hello
     (ebp-hello-params (plist-get config :client-name)
                       (plist-get config :client-version)
                       (plist-get config :pairing-id)
                       nonce
                       (plist-get config :wants))
     (lambda (result error) (ebp-client--on-nonce client result error)))
    (ebp-client--step client 'hello-sent)))

(defun ebp-client--on-nonce (client result error)
  "Handle the `session.hello' result (SPEC 9.2)."
  (let ((server-nonce (and (null error) (plist-get result :server_nonce))))
    (if (not (and server-nonce (ebp-valid-nonce-p server-nonce)))
        (ebp-client-close client (list 'hello-failed error))
      (ebp-client--step client 'nonce-received)
      (let ((config (ebp-client-config client)))
        (ebp-client--request
         client 'auth.response
         (ebp-auth-params (plist-get config :pairing-id)
                          (ebp-client-client-nonce client)
                          server-nonce
                          (plist-get config :token))
         (lambda (result error)
           (ebp-client--on-welcome client server-nonce result error))))
      (ebp-client--step client 'auth-sent))))

(defconst ebp--welcome-required
  '(:server_proof :protocol :server :granted :surface_profiles :surfaces
    :queued_events :limits)
  "SPEC 10.2: members the welcome result MUST contain.")

(defun ebp-client--send-ready (client replay-errored)
  "SPEC 10.3 step 5: leave SYNCING once the replay barrier has concluded.
REPLAY-ERRORED non-nil means step 4 ended without a summary, so nothing
is known about `remaining' — force one SPEC 15.3 retry cycle in READY
rather than assume the backlog is drained."
  (ebp-client--request
   client 'session.ready ebp--empty-object
   (lambda (_result error)
     (if error
         (ebp-client-close client (list 'ready-failed error))
       (ebp-client--step client 'ready-confirmed)
       (dolist (fn (ebp-client-ready-functions client))
         (funcall fn client))
       ;; SPEC 15.3: retry with bounded backoff while remaining.
       (if replay-errored
           (ebp-client--force-replay-retry client)
         (ebp-client--schedule-replay-retry client nil)
         (ebp-client--replay-settled client))))))

(defun ebp-client--on-welcome (client server-nonce result error)
  "Verify and absorb the welcome (SPEC 9.3, 10.2), then run the
synchronization barrier (SPEC 10.3)."
  (cond
   (error (ebp-client-close client (list 'auth-failed error)))
   ((cl-notevery (lambda (m) (plist-member result m)) ebp--welcome-required)
    (ebp-client-close client '(welcome-incomplete)))
   ((not (let ((config (ebp-client-config client)))
           ;; SPEC 9.3: verify server_proof before trusting welcome data.
           (ebp-verify-server-proof (plist-get result :server_proof)
                                    (plist-get config :token)
                                    (plist-get config :pairing-id)
                                    (ebp-client-client-nonce client)
                                    server-nonce)))
    (ebp-client-close client '(server-proof-invalid)))
   (t
    ;; SPEC 10.3 steps 1-2: absorb floors and merge input state.
    (setf (ebp-client-granted client) (plist-get result :granted)
          (ebp-client-profiles client) (plist-get result :surface_profiles)
          (ebp-client-surfaces client) (plist-get result :surfaces)
          (ebp-client-limits client) (plist-get result :limits)
          (ebp-client-input-state client) (plist-get result :input_state)
          ;; SPEC 20.1: absorb the device report (nil unless a module granted).
          (ebp-client-device client) (plist-get result :device)
          ;; SPEC 20.1.1: the welcome's window mirror, so the FIRST
          ;; snapshot can be authored for the right size class.
          (ebp-client-window client) (plist-get result :window))
    ;; Reported floors cover snapshots AND tombstones (SPEC 10.2/13.3).
    (cl-loop for (key entry) on (plist-get result :surfaces) by #'cddr
             do (puthash (substring (symbol-name key) 1)
                         (plist-get entry :revision)
                         (ebp-client-revisions client)))
    ;; Step 2: merge welcome input_state into the UI-state store.
    (cl-loop for (skey svals) on (plist-get result :input_state) by #'cddr
             do (cl-loop for (ikey value) on svals by #'cddr
                         do (puthash (cons (substring (symbol-name skey) 1)
                                           (substring (symbol-name ikey) 1))
                                     value
                                     (ebp-client-input-values client))))
    (ebp-client--step client 'welcome-verified)
    ;; SPEC 10.3 step 3: the application pushes required surfaces (with
    ;; retained drafts reflected) BEFORE replay; send order is wire order.
    (when-let* ((fn (plist-get (ebp-client-config client)
                               :before-replay-function)))
      (funcall fn client))
    ;; Step 4: replay concludes before session.ready — and SPEC 10.3: a
    ;; replay concludes for the barrier on ANY result, ANY JSON-RPC error,
    ;; or local abandonment.  An error must not close the connection: the
    ;; backlog is durable, FIFO survives, and SPEC 15.3 retries it in READY.
    ;; A replay may make one round trip per retained event up to
    ;; max_queued_events, so the local deadline must be generous and must
    ;; not be the only thing that ends SYNCING.
    (ebp-client--request
     client 'queue.replay ebp--empty-object
     (lambda (result error)
       (if error
           (display-warning
            'ebp (format "queue.replay concluded with error %S; proceeding \
to session.ready and retrying in READY (SPEC 10.3)" error)
            :warning)
         (setf (ebp-client-replay-summary client) result))
       (ebp-client--send-ready client (and error t)))
     300))))

(defun ebp-client--schedule-replay-retry (client delay)
  "SPEC 10.3/15.3: after READY, retry `queue.replay' with bounded
backoff while the backlog has `remaining' events.  DELAY nil starts at
the configured :replay-retry-delay (default 5 s); each retry doubles it,
capped at 60 s."
  (let* ((summary (ebp-client-replay-summary client))
         (remaining (and summary (plist-get summary :remaining))))
    (when (and remaining (> remaining 0)
               (eq (ebp-client-state client) 'ready))
      ;; Never leave a predecessor running: two live retry timers would
      ;; double the replay rate and defeat the bounded backoff.
      (when-let* ((live (ebp-client-replay-retry-timer client)))
        (cancel-timer live)
        (setf (ebp-client-replay-retry-timer client) nil))
      (let ((next (or delay
                      (plist-get (ebp-client-config client)
                                 :replay-retry-delay)
                      ebp-replay-retry-delay)))
        (setf (ebp-client-replay-retry-timer client)
              (run-at-time
               next nil
               (lambda ()
                 ;; The slot means PENDING, not "ever scheduled".  Clear
                 ;; it the instant this timer fires: a fired timer left in
                 ;; the slot makes every later force-retry read "one is
                 ;; already coming" forever, and the Companion's pump —
                 ;; unpaused ONLY by queue.replay — stalls for the session.
                 (setf (ebp-client-replay-retry-timer client) nil)
                 (when (eq (ebp-client-state client) 'ready)
                   (setf (ebp-client-replay-in-flight client) t)
                   (condition-case _err
                       (ebp-client--request
                        client 'queue.replay ebp--empty-object
                        (lambda (result error)
                          (setf (ebp-client-replay-in-flight client) nil)
                          (if error
                              ;; SPEC 15.3: bounded backoff continues even
                              ;; across an errored retry (1600 and friends).
                              (ebp-client--schedule-replay-retry
                               client (min ebp-replay-retry-max (* 2 next)))
                            (setf (ebp-client-replay-summary client) result)
                            (ebp-client--schedule-replay-retry
                             client (min ebp-replay-retry-max (* 2 next)))
                            (ebp-client--replay-settled client)))
                        300)
                     ;; A send that SIGNALS registers no continuation, so
                     ;; the callback above never runs — clear the claim
                     ;; here or the same stall returns by another door.
                     (error
                      (setf (ebp-client-replay-in-flight client) nil)
                      (ebp-client--schedule-replay-retry
                       client (min ebp-replay-retry-max (* 2 next)))))))))))))

(defun ebp-client--replay-settled (client)
  "Run the `:after-replay-function' hooks when the backlog is drained.
Called after a replay summary is absorbed; fires only in `ready' with
`remaining' 0 — replayed events have all reached a permanent
disposition, so the application may refresh views they mutated."
  (let ((summary (ebp-client-replay-summary client)))
    (when (and (eq (ebp-client-state client) 'ready)
               summary
               (eql (plist-get summary :remaining) 0))
      (dolist (fn (ebp-client-after-replay-functions client))
        (funcall fn client summary)))))

(defun ebp-client--force-replay-retry (client &optional delay)
  "SPEC 15.3: after answering 1500 event-retry, Emacs SHOULD call
`queue.replay' again with bounded backoff — the pump is paused until it
does.  Forces one retry cycle even when the last summary was clean.
DELAY overrides the first attempt's delay; it is IGNORED when a replay
is already PENDING (a live timer) or IN FLIGHT (a request awaiting its
answer) — the earlier schedule wins.  Both halves of that guard are
load-bearing: without the in-flight half a 1500 answered while a replay
is on the wire would schedule a redundant second one, and without the
timer being cleared when it fires the guard would mean \"ever
scheduled\" and every later retry would silently do nothing."
  (unless (or (ebp-client-replay-retry-timer client)
              (ebp-client-replay-in-flight client))
    (setf (ebp-client-replay-summary client)
          (plist-put (copy-sequence (or (ebp-client-replay-summary client)
                                        '(:remaining 0)))
                     :remaining (max 1 (or (plist-get
                                            (ebp-client-replay-summary client)
                                            :remaining)
                                           1))))
    (ebp-client--schedule-replay-retry client delay)))

(defun ebp-client-event-retry (client &optional after-s message)
  "Answer the in-flight `event.action' with `1500 event-retry' (SPEC 14.4).
DOES NOT RETURN — signals, concluding the dispatch without a receipt:
the Companion RETAINS its durable record and stays the owner, its pump
pauses (SPEC 15.3), and this schedules the `queue.replay' that unpauses
it — first attempt after AFTER-S seconds when given, else the bounded
backoff default.  Without that replay the pump would stay paused until
an unrelated retry fired: the silent-divergence class this seam closes.

MESSAGE, when given, MUST carry no user content (SPEC 23.3).
`:retry_after_s' rides the error data as an ADVISORY extra member (SPEC
8 permits extras; 15.3 defines no such field, so the Companion may
ignore it — the enforced cadence is the local replay backoff)."
  (when after-s
    (unless (and (numberp after-s) (> after-s 0))
      (error "ebp-client-event-retry: AFTER-S must be a positive number")))
  (when message
    (unless (stringp message)
      (error "ebp-client-event-retry: MESSAGE must be a string")))
  (ebp-client--force-replay-retry client after-s)
  (apply #'ebp-client--error client 1500
         (or message "Event not accepted yet; retry")
         "event-retry"
         ;; SPEC 4.2: *_s members are INTEGER seconds; a float here is a
         ;; content-invalid frame.  Ceiling, floored at 1 — advising a
         ;; zero-second retry defeats the point of asking.
         (when after-s (list :retry_after_s (max 1 (ceiling after-s))))))

;;;; Dispatchers (SPEC 7.3) — ours because the library is fail-open

(defun ebp-client--authenticated-p (client)
  "Non-nil once CLIENT has verified the welcome (SPEC 10.1).
Authentication completes at the `awaiting-welcome' -> `syncing'
transition (the server_proof and welcome are verified there), so
`syncing' and `ready' are the authenticated states.  `syncing' counts
because SPEC 15.3 queue replay delivers `event.action' requests before
`session.ready'."
  (memq (ebp-client-state client) '(syncing ready)))

(defun ebp-client--request-dispatcher (client _conn method params)
  "Gate an inbound request on session state, then dispatch (SPEC 7.3/10.1).
Framing and the JSON-RPC shape are already validated by the library.
Before authentication the Companion is untrusted: every request fails
closed with 1200, even a known or wrong-direction one (SPEC 10.1).
Afterwards an unknown request receives -32601; the library never sends
either error itself."
  (ebp--with-dispatch client
    ;; SPEC 10.1: pre-auth, a structurally valid request other than the
    ;; handshake reply MUST receive 1200 not-authenticated — and the client
    ;; never receives the handshake methods, so every inbound request does.
    (unless (ebp-client--authenticated-p client)
      (ebp-client--error client 1200 "Not authenticated" "not-authenticated"))
    (let ((handler (gethash (symbol-name method) (ebp-client-handlers client))))
      (if handler
          (ebp-client--serializable client (funcall handler client params))
        (ebp-client--error client -32601 "Method not found"
                           "method-not-found")))))

(defun ebp-client--serializable (client result)
  "SPEC 7.1: return RESULT, or signal -32603 if it cannot be serialized.
A responder that computes a result it cannot serialize MUST answer with
`-32603 internal-error' and MUST NOT leave the request unanswered — but
jsonrpc.el runs the handler inside a `condition-case' and then calls
`jsonrpc--reply' OUTSIDE it (emacs-30.1 jsonrpc.el:300-317), so a reply
body that `json-serialize' refuses escapes through the process filter
and the Companion waits forever on a request it will never see answered.
Emacs's own encoder is the strictest party here: `json-serialize'
signals past 50 nested containers (src/json.c), well inside what a
handler may legitimately build.  Serializing twice costs a small string
on the reply path; leaving a request outstanding costs the session."
  (condition-case err
      (progn (ebp--json-serialize result) result)
    (error
     ;; The message is the encoder's own ("Maximum JSON serialization depth
     ;; exceeded"), never the value — SPEC 23.2 keeps document content out
     ;; of diagnostics.
     (ebp-client--error client -32603 "Internal error" "internal-error"
                        :reason (error-message-string err)))))

(defun ebp-client--notification-dispatcher (client _conn method params)
  "Gate an inbound notification on session state, then dispatch (SPEC 7.3/10.1).
Before authentication all notifications are logged locally and dropped
without `log.error' (SPEC 10.1); afterwards an unknown notification is
logged and ignored (SPEC 7.3)."
  (ebp--with-dispatch client
    (cond
     ((not (ebp-client--authenticated-p client))
      (message "ebp: pre-auth notification %s dropped" method))
     ((gethash (symbol-name method) (ebp-client-handlers client))
      (funcall (gethash (symbol-name method) (ebp-client-handlers client))
               client params))
     (t (message "ebp: unknown notification %s ignored" method)))))

;;;; Actions and events (SPEC 14), the Emacs endpoint half

(defconst ebp--event-id-re "\\`[0-9a-f]\\{32\\}\\'"
  "SPEC 4.4: an EventId is exactly 32 lowercase hexadecimal characters.")

(defconst ebp-receipt-retention-seconds 604800
  "SPEC 14.4: accepted EventIds are durably retained at least this long.")

(defun ebp-client-register-action (client action fn)
  "Register FN as the allowlisted handler for ACTION (SPEC 14.1).
FN is called with (CLIENT PARAMS) after envelope validation and the
duplicate check, inside the dispatch extent.  It MUST return one of the
symbols `accepted', `stale', or `rejected' (SPEC 14.4/14.5); for
`accepted', this library durably commits the EventId receipt before the
result leaves — never author a handler whose effect must not run twice
without also making it idempotent, as 14.4 recommends."
  (puthash action fn (ebp-client-actions client)))

(defun ebp-client--receipts-load (client)
  "Open the durable receipt store and load surviving EventIds.
Backend: built-in SQLite when available (transactional commits, indexed
duplicate lookup, in-place pruning); otherwise the append-only text
file with load-time pruning."
  (when-let* ((file (plist-get (ebp-client-config client) :receipt-file)))
    (let ((cutoff (- (float-time) ebp-receipt-retention-seconds)))
      (cond
       ((and (fboundp 'sqlite-available-p) (sqlite-available-p))
        (condition-case nil
            (let ((db (sqlite-open file)))
              (sqlite-execute db "CREATE TABLE IF NOT EXISTS receipts \
(event_id TEXT PRIMARY KEY, ts REAL)")
              ;; SPEC 14.4: the 604800 s retention is a floor; prune past it.
              (sqlite-execute db "DELETE FROM receipts WHERE ts < ?"
                              (list cutoff))
              (dolist (row (sqlite-select db "SELECT event_id, ts \
FROM receipts"))
                (puthash (car row) (cadr row)
                         (ebp-client-receipts client)))
              (setf (ebp-client-receipt-db client) db))
          ;; An unopenable path degrades to commit-time failure -> 1500.
          (error nil)))
       ((file-readable-p file)
        (dolist (line (split-string
                       (with-temp-buffer
                         (insert-file-contents file)
                         (buffer-string))
                       "\n" t))
          (pcase-let ((`(,id ,ts) (split-string line " ")))
            (when (and id ts (> (string-to-number ts) cutoff))
              (puthash id (string-to-number ts)
                       (ebp-client-receipts client))))))))))

(defun ebp-client--receipt-commit (client event-id)
  "Durably record EVENT-ID (SPEC 14.4); nil when the commitment failed."
  (condition-case nil
      (let ((now (float-time))
            (db (ebp-client-receipt-db client)))
        (cond
         (db
          ;; SQLite's default synchronous=FULL is the durable commit.
          (sqlite-execute db
                          "INSERT OR REPLACE INTO receipts VALUES (?, ?)"
                          (list event-id now)))
         ((and (fboundp 'sqlite-available-p) (sqlite-available-p))
          ;; SQLite exists but the store never opened: no durable path.
          (error "receipt store unavailable"))
         (t
          (when-let* ((file (plist-get (ebp-client-config client)
                                       :receipt-file)))
            ;; Emacs 30 defaults write-region-inhibit-fsync to t; a
            ;; receipt not on stable storage is not a 14.4 commitment.
            (let ((write-region-inhibit-fsync nil))
              (write-region (format "%s %s\n" event-id now)
                            nil file t 'silent)))))
        (puthash event-id now (ebp-client-receipts client))
        t)
    (error nil)))

(defun ebp-client--event-context-valid-p (params)
  "SPEC 14.4: surface, dialog, and global events carry exclusive context."
  (let ((surface (plist-get params :surface))
        (revision (plist-get params :revision_seen))
        (dialog (plist-get params :dialog_id)))
    (cond
     (surface (and (stringp surface) (integerp revision) (>= revision 0)
                   (null dialog)))
     (dialog (and (stringp dialog) (null revision)))
     (t (null revision)))))

(defun ebp-client--handle-event-action (client params)
  "The `event.action' server (SPEC 14.4).
Validation order per 14.4: envelope, allowlist, duplicate ID — before
any application behavior.  The reply is the dispatcher's return value;
the durable receipt commit happens synchronously before `accepted'
leaves, which is exactly the ordering 14.4 requires."
  (let ((event-id (plist-get params :event_id))
        (action (plist-get params :action)))
    (unless (and (stringp event-id)
                 (string-match-p ebp--event-id-re event-id)
                 (stringp action) (string-search "." action)
                 (integerp (plist-get params :occurred_at_ms))
                 (ebp-client--event-context-valid-p params))
      (ebp-client--error client -32602 "Invalid params" "invalid-params"))
    (cond
     ;; SPEC 14.4: a repeated ID MUST NOT deliberately repeat the effect.
     ((gethash event-id (ebp-client-receipts client))
      '(:status "duplicate"))
     ((null (gethash action (ebp-client-actions client)))
      '(:status "rejected" :message "action not allowlisted"))
     (t
      (pcase (funcall (gethash action (ebp-client-actions client))
                      client params)
        ('accepted
         (if (ebp-client--receipt-commit client event-id)
             '(:status "accepted")
           ;; SPEC 14.4: no commitment, no accepted — retryable instead,
           ;; and SPEC 15.3: schedule the replay that unpauses the pump.
           (ebp-client--force-replay-retry client)
           (ebp-client--error client 1500 "Receipt commit failed"
                              "event-retry")))
        ('stale '(:status "stale"))
        ('rejected '(:status "rejected"))
        (other (ebp-client--error client -32603
                                  (format "handler returned %S" other)
                                  "internal-error")))))))

;;;; Input state (SPEC 14.6 + P1 #2), the Emacs endpoint half

(defun ebp-client-input-value (client surface id)
  "The latest reconciled value for SURFACE's stateful node ID."
  (gethash (cons surface id) (ebp-client-input-values client)))

(defun ebp-client--record-reset-ids (client surface revision reset-ids)
  "Remember that REVISION explicitly reset RESET-IDS (P1 #2)."
  (when reset-ids
    (push (cons revision (append reset-ids nil))
          (gethash surface (ebp-client-reset-history client)))))

(defun ebp-client--state-reset-p (client surface revision-seen id)
  "SPEC 14.6: a reset at a revision above REVISION-SEEN supersedes the
reported draft; only a later-revision report reinstates one."
  (cl-some (lambda (entry)
             (and (> (car entry) revision-seen)
                  (member id (cdr entry))))
           (gethash surface (ebp-client-reset-history client))))

(defun ebp-client--handle-window-changed (client params)
  "The `window.changed' receiver (SPEC 20.1.1).
Stores the geometry plist and runs `window-changed-functions' — the
application's seam for re-authoring layout for the new size class."
  (setf (ebp-client-window client) params)
  (dolist (fn (ebp-client-window-changed-functions client))
    (funcall fn client params)))

(defun ebp-client--handle-state-changed (client params)
  "The `state.changed' receiver (SPEC 14.6 + P1 #2).
An old `revision_seen' is never an error: the value is adopted unless a
later snapshot explicitly reset that ID."
  (let ((surface (plist-get params :surface))
        (revision (plist-get params :revision_seen))
        (id (plist-get params :id)))
    (when (and (stringp surface) (integerp revision) (stringp id))
      (if (ebp-client--state-reset-p client surface revision id)
          (message "ebp: state.changed for reset %s/%s discarded" surface id)
        (puthash (cons surface id) (plist-get params :value)
                 (ebp-client-input-values client))
        (dolist (fn (ebp-client-state-changed-functions client))
          (funcall fn client surface revision id
                   (plist-get params :value)))))))

;;;; Editor sync (SPEC 19), the Emacs endpoint half

;; Emacs mirrors the Companion's shadow.  It RECEIVES edit.open/delta/caret/
;; close (notifications) and answers edit.complete (request); it SENDS
;; edit.apply/resync (requests) and the annotation notifications.  Positions
;; are Unicode scalar values = Emacs char positions.

(defun ebp-client-editor-text (client document editor-id)
  "The mirrored text of the synchronized editor, or nil."
  (plist-get (gethash (cons document editor-id) (ebp-client-editors client))
             :text))

(defun ebp-client--editor-changed (client document editor-id)
  (dolist (fn (ebp-client-edit-change-functions client))
    (funcall fn client document editor-id
             (ebp-client-editor-text client document editor-id))))

(defun ebp-client--handle-edit-open (client params)
  "SPEC 19.3: seed the mirror for a new editor session.
Amendment #71: Emacs MUST compare the seed against its own document and
reconcile explicitly, never silently overwrite either side.  The
document lives above this library, so after the mirror adopts the seed
\(the mirror shadows the Companion; a reconciling edit needs its fresh
session and seq) the `:edit-open-function' hooks receive
\(CLIENT DOCUMENT EDITOR-ID SEED-TEXT PRIOR-TEXT) — PRIOR-TEXT is the
previous mirror text, nil for a fresh session — and the application
adopts the seed, issues a reconciling `ebp-client-edit-apply', or
surfaces a conflict."
  (let* ((doc (plist-get params :document))
         (eid (plist-get params :editor_id))
         (prior (gethash (cons doc eid) (ebp-client-editors client)))
         (prior-text (plist-get prior :text)))
    (puthash (cons doc eid)
             (list :session (plist-get params :session)
                   :seq (plist-get params :seq)
                   :text (plist-get params :text)
                   :cursor (plist-get params :cursor))
             (ebp-client-editors client))
    (dolist (fn (ebp-client-edit-open-functions client))
      (funcall fn client doc eid (plist-get params :text) prior-text))
    (ebp-client--editor-changed client doc eid)))

(defun ebp-client--handle-edit-delta (client params)
  "SPEC 19.3: apply the splice at seq+1; on any mismatch, mark the local
view stale and resync once."
  (let* ((doc (plist-get params :document))
         (eid (plist-get params :editor_id))
         (ed (gethash (cons doc eid) (ebp-client-editors client))))
    (when (and ed (equal (plist-get ed :session) (plist-get params :session)))
      (let ((text (plist-get ed :text))
            (start (plist-get params :start))
            (del (plist-get params :del))
            (ins (plist-get params :text))
            (len (plist-get params :len)))
        (if (and (= (plist-get params :seq) (1+ (plist-get ed :seq)))
                 (<= 0 start) (<= 0 del) (<= (+ start del) (length text)))
            (let ((new (concat (substring text 0 start) ins
                               (substring text (+ start del)))))
              (if (= (length new) len)
                  (progn
                    (setf (plist-get ed :text) new
                          (plist-get ed :seq) (plist-get params :seq))
                    (ebp-client--editor-changed client doc eid))
                (ebp-client-edit-resync client doc eid)))
          (ebp-client-edit-resync client doc eid))))))

(defun ebp-client--handle-edit-caret (client params)
  "SPEC 19.3: best-effort caret; accepted only on session/seq match."
  (let ((ed (gethash (cons (plist-get params :document)
                           (plist-get params :editor_id))
                     (ebp-client-editors client))))
    (when (and ed (equal (plist-get ed :session) (plist-get params :session))
               (= (plist-get ed :seq) (plist-get params :seq)))
      (setf (plist-get ed :cursor) (plist-get params :cursor)))))

(defun ebp-client--handle-edit-close (client params)
  "SPEC 19.3: release the mirrored session."
  (let ((doc (plist-get params :document))
        (eid (plist-get params :editor_id)))
    (remhash (cons doc eid) (ebp-client-editors client))
    (ebp-client--editor-changed client doc eid)))

(defun ebp-client--handle-edit-complete (client params)
  "SPEC 19.3: answer a completion request from the application's
`:edit-complete-function' (doc editor-id text cursor) -> (PREFIX . CANDS),
each candidate a plist (:label :annotation? :insert?).  Session/seq must
match or the query is editor-stale."
  (let* ((doc (plist-get params :document))
         (eid (plist-get params :editor_id))
         (ed (gethash (cons doc eid) (ebp-client-editors client)))
         (fn (plist-get (ebp-client-config client) :edit-complete-function)))
    (unless (and ed (equal (plist-get ed :session) (plist-get params :session))
                 (= (plist-get ed :seq) (plist-get params :seq)))
      (ebp-client--error client 1201 "Editor stale" "content-invalid"
                         :reason "editor-stale"))
    (if fn
        (let ((r (funcall fn doc eid (plist-get ed :text)
                          (plist-get params :cursor))))
          (list :prefix (or (car r) "") :candidates (vconcat (cdr r))))
      (list :prefix "" :candidates []))))

(cl-defun ebp-client-edit-apply (client document editor-id start del text
                                 &key callback)
  "SPEC 19.4: push an Emacs edit to the Companion; it wins seq+1 or loses
with a typed stale (the incoming delta is then authoritative).
Amendment #84: a splice whose resulting document would exceed the
negotiated `max_editor_bytes' (its JCS-serialized UTF-8 length, SPEC
4.5) MUST NOT be emitted; it is refused locally and CALLBACK receives
\(nil ERROR) with a synthetic `1201' `editor-too-large' plist mirroring
the wire shape."
  (let ((ed (gethash (cons document editor-id) (ebp-client-editors client))))
    (when ed
      (let* ((old (plist-get ed :text))
             (new (concat (substring old 0 start) text
                          (substring old (+ start del))))
             (max-bytes (plist-get (ebp-client-limits client)
                                   :max_editor_bytes)))
        (if (and max-bytes
                 (> (string-bytes (json-serialize new)) max-bytes))
            (when callback
              (funcall callback nil
                       '(:code 1201
                         :message "resulting document exceeds max_editor_bytes"
                         :data (:kind "content-invalid"
                                :reason "editor-too-large"))))
          (let ((session (plist-get ed :session))
                (seq-at-send (plist-get ed :seq)))
            (ebp-client--request
             client 'edit.apply
             (list :document document :editor_id editor-id
                   :session session
                   :seq (1+ seq-at-send) :start start :del del
                   :text text :len (length new) :cursor (+ start (length text)))
             (lambda (result error)
               (when (and (null error)
                          (equal (plist-get result :status) "applied"))
                 ;; A8 H2 (candidate R1): the mirror may have moved while
                 ;; our send blocked — a re-entrant `edit.open' reseeded
                 ;; it, `edit.close' removed it, a delta advanced it.
                 ;; Adopt the pre-send splice only into the SAME live
                 ;; entry at the SAME session and seq; any other live
                 ;; state is a stale view of our own making, and resync
                 ;; is its recovery (SPEC 19.4).
                 (let ((live (gethash (cons document editor-id)
                                      (ebp-client-editors client))))
                   (cond
                    ((and (eq live ed)
                          (equal (plist-get live :session) session)
                          (= (plist-get live :seq) seq-at-send))
                     (setf (plist-get ed :text) new
                           (plist-get ed :seq) (plist-get result :seq))
                     (ebp-client--editor-changed client document editor-id))
                    (live
                     (ebp-client-edit-resync client document editor-id)))))
               (when callback
                 (funcall callback (and result (plist-get result :status))
                          error))))))))))

(defun ebp-client-edit-resync (client document editor-id)
  "SPEC 19.4: recover a stale local view — the Companion returns full
state under a fresh session at seq 0."
  (let ((ed (gethash (cons document editor-id) (ebp-client-editors client))))
    (when ed
      (ebp-client--request
       client 'edit.resync
       (list :document document :editor_id editor-id
             :session (plist-get ed :session))
       (lambda (result error)
         (unless error
           (puthash (cons document editor-id)
                    (list :session (plist-get result :session) :seq 0
                          :text (plist-get result :text)
                          :cursor (plist-get result :cursor))
                    (ebp-client-editors client))
           (ebp-client--editor-changed client document editor-id)))))))

;;;; Surface push (SPEC 13.1-13.3), the client half

(defun ebp-client--surface-floor (client surface)
  (gethash surface (ebp-client-revisions client) -1))

(defun ebp-client--absorb-floor (client surface revision)
  "Absorb a reported revision floor; floors only ever rise (SPEC 13.1)."
  (puthash surface
           (max revision (ebp-client--surface-floor client surface))
           (ebp-client-revisions client)))

(defun ebp-client--surface-request (client method surface params callback
                                           &optional on-claim)
  "Send a revisioned surface request and absorb the result floor.
Returns the revision used.  CALLBACK, when given, receives (STATUS ERROR)
where STATUS is \"applied\" or \"stale\" (SPEC 13.2: stale is benign).

ON-CLAIM, when given, is called with the claimed revision after the
revision is claimed and BEFORE the request reaches the wire.  Anything a
racing inbound frame may consult MUST be recorded there rather than after
the send returns: `process-send-string' is not atomic with respect to our
own state.  A frame large enough to fill the socket buffer blocks in
`send_process', which spins in `wait_reading_process_output', which runs
timers — and jsonrpc.el dispatches from timers, so an inbound
notification can be handled re-entrantly INSIDE this send.  See
docs/RESEARCH-A8-2026-07-25.md."
  (let ((revision (1+ (ebp-client--surface-floor client surface))))
    ;; Claim the revision at send time so a second push in flight is newer.
    (puthash surface revision (ebp-client-revisions client))
    (when on-claim (funcall on-claim revision))
    (ebp-client--request
     client method
     (append `(:surface ,surface :revision ,revision) params)
     (lambda (result error)
       (unless error
         (ebp-client--absorb-floor client surface
                                   (plist-get result :revision)))
       (when callback
         (funcall callback (and result (plist-get result :status)) error))))
    revision))

(cl-defun ebp-client-surface-update (client surface spec
                                     &key stale-after-s stale-spec current-view
                                     reset-input-ids callback)
  "Push a complete snapshot for SURFACE (SPEC 13.2); returns its revision.
SPEC is the SurfaceSpec value.  What the spec contains is the
application's business (REWRITE-PLAN boundary); this owns the revisions."
  (ebp-client--surface-request
   client 'surface.update surface
   `(:spec ,spec
     ,@(when stale-after-s `(:stale_after_s ,stale-after-s))
     ,@(when stale-spec `(:stale_spec ,stale-spec))
     ,@(when current-view `(:current_view ,current-view))
     ,@(when reset-input-ids
         `(:reset_input_ids ,(vconcat reset-input-ids))))
   callback
   ;; P1 #2: this side's reset history reconciles racing state.changed —
   ;; and it MUST be recorded before the snapshot reaches the wire, not
   ;; after the send returns.  A snapshot big enough to block the socket
   ;; lets an inbound `state.changed' dispatch re-entrantly inside this
   ;; send (see `ebp-client--surface-request'); recorded afterwards,
   ;; `ebp-client--state-reset-p' would not yet see this revision's reset
   ;; and would adopt a draft this very snapshot supersedes.
   (lambda (revision)
     (ebp-client--record-reset-ids client surface revision reset-input-ids))))

(cl-defun ebp-client-surface-remove (client surface &key callback)
  "Tombstone SURFACE at a fresh revision (SPEC 13.3); returns the revision."
  (ebp-client--surface-request client 'surface.remove surface nil callback))

;;;; Toasts (SPEC 18.2), the client half

(cl-defun ebp-client-toast (client text &key duration-s)
  "Show a best-effort toast (SPEC 18.2).  TEXT is plain text; DURATION-S,
when given, is 1..10 seconds.  Fire-and-forget: a toast is never an
acknowledgement and carries no result."
  (ebp-client-notify
   client 'toast.show
   `(:text ,text ,@(when duration-s `(:duration_s ,duration-s)))))

;;;; Themes (SPEC 18.4), the client half

(cl-defun ebp-client-theme-set (client &key (dark 'system) colors syntax
                                       (dynamic 'system) font-scale
                                       layout-direction)
  "Push a complete theme replacement (SPEC 18.4).  DARK selects polarity:
t forces dark, `:false' (or `:json-false') forces light, and the default
`system' omits the member so the Companion follows the device setting
\(amendment #36).  COLORS and SYNTAX are role-map plists mirroring the
Emacs theme, or the symbol `null' to send JSON null and select the
Companion's native scheme.  Each call fully replaces the previously
pushed theme.  Values are normalized to the live connection's jsonrpc
sentinels (`:json-false' / nil); the reference encoder's `:false' and
`:null' are accepted here but never handed to jsonrpc.el, which rejects
them.

DYNAMIC t asks for the device's wallpaper-derived Material You palette
as the BASE scheme where the platform has one — Emacs could never send
that as COLORS, since it derives from the wallpaper; pushed roles still
overlay it.  FONT-SCALE is a number 0.4..2.0 scaling every text node
together; LAYOUT-DIRECTION is \"ltr\" or \"rtl\" mirroring the whole
layout.  All three follow the device/system setting when omitted — the
same tri-state convention as DARK."
  (when font-scale
    (unless (and (numberp font-scale) (<= 0.4 font-scale 2.0))
      (error "ebp-client-theme-set: :font-scale must be a number in 0.4..2.0, got %S"
             font-scale)))
  (when layout-direction
    (unless (member layout-direction '("ltr" "rtl"))
      (error "ebp-client-theme-set: :layout-direction must be \"ltr\" or \"rtl\", got %S"
             layout-direction)))
  (ebp-client-notify
   client 'theme.set
   `(,@(pcase dark
         ('system nil)
         ('t '(:dark t))
         ((or :false :json-false) '(:dark :json-false))
         (_ (error "ebp-client-theme-set: :dark must be t, :false, or \
omitted (system); got %S" dark)))
     ,@(pcase dynamic
         ('system nil)
         ('t '(:dynamic t))
         ((or :false :json-false) '(:dynamic :json-false))
         (_ (error "ebp-client-theme-set: :dynamic must be t, :false, or \
omitted (system); got %S" dynamic)))
     ,@(when font-scale `(:font_scale ,font-scale))
     ,@(when layout-direction `(:layout_direction ,layout-direction))
     ,@(when colors `(:colors ,(if (memq colors '(null :null)) nil colors)))
     ,@(when syntax `(:syntax ,(if (memq syntax '(null :null)) nil syntax))))))

;;;; Reminders (SPEC 18.6), the client half

(cl-defun ebp-client-reminders-set (client owner reminders &key callback)
  "Replace OWNER's reminder set (SPEC 18.6).  REMINDERS is a vector of
plists `(:id ID :title S :at_ms MS)' with optional `:body S' and a remote
`:on_tap DESC'; the Companion injects `owner'/`reminder_id' at tap time.
An empty vector clears the owner's set.  CALLBACK receives (COUNT ERROR):
COUNT is the owner's accepted total, ERROR the JSON-RPC error plist (1201
`reminder-limit' or content-invalid).  Replaces only this owner's set."
  (ebp-client--request
   client 'reminders.set
   `(:owner ,owner :reminders ,reminders)
   (lambda (result error)
     (when callback
       (funcall callback (and result (plist-get result :count)) error)))))

;;;; Device capabilities (SPEC 20), the client half

(defun ebp-client-device-caps (client)
  "The capability identifiers the Companion advertised (SPEC 20.1), a list.
Nil until the welcome carried a device report (capabilities/triggers)."
  (append (plist-get (ebp-client-device client) :caps) nil))

(cl-defun ebp-client-capability-invoke (client cap &key args callback)
  "Invoke Companion capability CAP (SPEC 20.2).  ARGS is the closed Args
plist for the catalog row, or nil for an empty `{}'.  CALLBACK receives
(RESULT ERROR): RESULT is the exact catalog Result plist; ERROR the
JSON-RPC error plist (1001 `cap-unsupported', 1002 `cap-permission',
1003 `cap-failed', or -32602 for an invalid Args shape).  A capability
invocation is session-scoped and non-durable, and an indeterminate
outcome MUST NOT be auto-retried (SPEC 20.2)."
  (ebp-client--request
   client 'capability.invoke
   `(:cap ,cap ,@(when args `(:args ,args)))
   (lambda (result error)
     (when callback (funcall callback result error)))
   ;; SPEC 20.2: the Companion may hold this while the OS asks the user for
   ;; a runtime permission — SPEC 7.1 forbids a deadline under 60 s here.
   (or (ebp-client--user-paced-timeout ebp-capability-timeout) 'none)))

;;;; Device triggers (SPEC 21), the client half

(defun ebp-client-device-trigger-types (client)
  "The trigger-type identifiers the Companion advertised (SPEC 20.1/21).
Nil until the welcome carried a device report (triggers granted)."
  (append (plist-get (ebp-client-device client) :trigger_types) nil))

(defun ebp-client-device-state-types (client)
  "The sampleable state-type identifiers the Companion advertised
\(SPEC 20.1), a list.  Never includes a predicate-only type:
`time.window' is valid in a `when' gate but never listed here
\(SPEC 21.7, amendment #75).  Nil until the welcome carried a device
report."
  (append (plist-get (ebp-client-device client) :state_types) nil))

(cl-defun ebp-client-triggers-set (client triggers &key callback
                                          omitted-function)
  "Replace the pairing identity's trigger set (SPEC 21.1).  TRIGGERS is a
vector of trigger plists — each `(:id ID :type TYPE)' plus optional
`:params', `:when' (a vector of state predicates, flat AND), `:policy'
\(drop/queue/wake), `:ttl_s', `:dedupe', `:throttle_s', and `:on_fire' (a
vector of `(:cap C :args ...)' or `(:notify (:text S :title? S))').  A fired
trigger arrives as an `event.action' whose action is `trigger.fired'; register
a handler with `ebp-client-register-action'.  CALLBACK receives (COUNT ERROR):
COUNT is the accepted total, ERROR the JSON-RPC error plist (1101
`triggers-rejected', identifying the offending trigger).  An empty vector
clears every registration; the whole set is validated before any change.

SPEC 21.3 (amendments #75, #90): every `when' predicate type that is not
predicate-only MUST be advertised in `device.state_types'; `time.window'
is predicate-only and always authorable.  A trigger naming an
unadvertised type is OMITTED — per trigger, so the remaining entries are
still sent and the accepted `count' reflects only those — and never
weakened by dropping the offending predicate.  Because `count' is the
sole wire evidence of an omission, each one is surfaced: through
OMITTED-FUNCTION when given, called with the list of omitted trigger
plists, and otherwise as a `display-warning'."
  (let* ((advertised (ebp-client-device-state-types client))
         (kept '()) (omitted '()))
    (seq-doseq (trigger triggers)
      (if (seq-some (lambda (pred)
                      (let ((type (plist-get pred :type)))
                        (not (or (equal type "time.window")
                                 (member type advertised)))))
                    (or (plist-get trigger :when) []))
          (push trigger omitted)
        (push trigger kept)))
    (setq kept (nreverse kept) omitted (nreverse omitted))
    (when omitted
      (if omitted-function
          (funcall omitted-function omitted)
        (display-warning
         'ebp
         (format "omitted %d trigger(s) whose `when' names a type absent \
from device.state_types %S (SPEC 21.3): %S"
                 (length omitted) advertised
                 (mapcar (lambda (tr) (plist-get tr :id)) omitted))
         :warning)))
    (ebp-client--request
     client 'triggers.set
     `(:triggers ,(vconcat kept))
     (lambda (result error)
       (when callback
         (funcall callback (and result (plist-get result :count)) error))))))

;;;; Pie menus (SPEC 18.3), the client half

(cl-defun ebp-client-pie-menu-show (client menu-id categories &key center-label)
  "Show an ephemeral radial menu (SPEC 18.3).  CATEGORIES is a vector of
1..10 plists, each `(:label S :on_tap DESC)' for a leaf or
`(:label S :items [(:label S :on_tap DESC) ...])' for a nested set.
Every DESC is a remote drop-only ActionDescriptor; the Companion injects
`menu_id'/`category_index'/`item_index' at selection.  Showing an
existing MENU-ID replaces it."
  (ebp-client-notify
   client 'pie_menu.show
   `(:menu_id ,menu-id :categories ,categories
     ,@(when center-label `(:center_label ,center-label)))))

(defun ebp-client-pie-menu-dismiss (client menu-id)
  "Dismiss the pie menu MENU-ID (SPEC 18.3); unknown ids are a no-op."
  (ebp-client-notify client 'pie_menu.dismiss `(:menu_id ,menu-id)))

;;;; Dialogs (SPEC 18.1), the client half

(cl-defun ebp-client-dialog-show (client dialog-id spec &key style callback)
  "Show a modal dialog (SPEC 18.1).  DIALOG-ID is an identifier; SPEC is
the dialog SurfaceSpec.  CALLBACK receives (STATUS RESULT ERROR): STATUS
is submitted or dismissed; RESULT is the full result plist (with
`value' and `fields' on submit); a cancelled dialog arrives as ERROR
1301.  This is the endpoint's send mechanism; turning an Emacs prompt
into a dialog is an application concern above this boundary."
  (ebp-client--request
   client 'dialog.show
   `(:dialog_id ,dialog-id :spec ,spec ,@(when style `(:style ,style)))
   (lambda (result error)
     (when callback
       (funcall callback (and result (plist-get result :status))
                result error)))
   ;; SPEC 18.1: a dialog is held until the user acts — there is no
   ;; protocol timeout, and SPEC 7.1 SHOULDs no local one either.  A
   ;; configured ceiling is floored at 60 s; expiry sends `rpc.cancel',
   ;; which SPEC 18.1 concludes with 1301 and dismisses the dialog.
   (or (ebp-client--user-paced-timeout ebp-dialog-timeout) 'none)))

;;;; TCP transport (SPEC 5.2): jsonrpc-process-connection, unmodified

;;;###autoload
(defun ebp-connect (host port &rest config)
  "Dial the Companion at HOST:PORT and start the handshake.
CONFIG is `ebp-client-create' config.  Returns the client.  Transport,
framing, and id bookkeeping are core jsonrpc.el's; reconnection policy
stays with the caller for now."
  (let* ((client (apply #'ebp-client-create config))
         ;; Pin the coding system: jsonrpc.el 1.0.25 never sets one, so an
         ;; ambient `coding-system-for-read' (or `undecided' auto-detection
         ;; picking a non-UTF-8 charset, or DOS eol conversion mangling the
         ;; \r\n header terminator) would corrupt framing.
         ;;
         ;; It MUST be utf-8-unix, NOT binary, even though Content-Length
         ;; counts octets: jsonrpc.el's process buffer is MULTIBYTE and
         ;; `jsonrpc--process-filter' sizes the body with `position-bytes'.
         ;; Under binary the filter inserts a unibyte string, every octet
         ;; >= 0x80 becomes a raw-byte char of 2 internal bytes,
         ;; `position-bytes' over-counts, and the body is truncated — the
         ;; frame is then silently dropped as invalid JSON.  Verified on
         ;; 30.1: a framed body carrying "café" dispatches under
         ;; utf-8-unix and vanishes under binary.
         (proc (make-network-process
                :name "ebp" :host host :service port :noquery t
                :coding 'utf-8-unix))
         (conn (make-instance
                'ebp--connection
                :name "ebp" :process proc
                ;; SPEC 23.3: do not capture message bodies in the clear by
                ;; default; :size 0 disables the events buffer (opt in for dev).
                :events-buffer-config
                (if ebp-log-events '(:size nil :format full) '(:size 0))
                :request-dispatcher
                (lambda (c m p) (ebp-client--request-dispatcher client c m p))
                :notification-dispatcher
                (lambda (c m p) (ebp-client--notification-dispatcher client c m p))
                :on-shutdown
                (lambda (_c)
                  (ebp-client-close client '(shutdown))))))
    (setf (ebp-client-connection client) conn
          (ebp-client-process client) proc
          (ebp--connection-client conn) client)
    ;; SPEC 22.3 inbound bound (W10): jsonrpc.el installed its filter on
    ;; OUR process in `initialize-instance'; wrap it so the outermost
    ;; exit — the admission point, and the only code of ours that runs
    ;; while a flood is starving the timer drain — measures the parsed
    ;; backlog and applies backpressure.  Public process API only;
    ;; jsonrpc.el itself stays rented unmodified.
    ;;
    ;; SPEC 23.5 decode isolation rides the same seam: the rented filter
    ;; parses with `:object-type' plist, interning every peer-supplied
    ;; member name, so the parse runs under a THROWAWAY obarray (fresh
    ;; per invocation — a partial frame's names die with the chunk that
    ;; completes it) and the exit remaps the parsed queue onto the global
    ;; obarray where a global twin exists (`ebp--isolate-parsed-messages';
    ;; also the unknown-method sentinel).  `ebp--in-filter' additionally
    ;; scopes the `jsonrpc--warn' redaction (SPEC 23.3).  Known residue,
    ;; accepted: jsonrpc.el's bug#60088 re-entry reschedule would re-run
    ;; the filter OUTSIDE this wrapper, but that path needs
    ;; `accept-process-output' inside our own filter extent, which no ebp
    ;; code performs.
    (add-function :around (process-filter proc)
                  (lambda (orig p string)
                    (let ((outermost (not ebp--in-filter))
                          (ebp--in-filter t))
                      (unwind-protect
                          (let ((obarray (obarray-make)))
                            (funcall orig p string))
                        (ebp--isolate-parsed-messages client)
                        (when outermost
                          (ebp-client--inbound-check client)))))
                  '((name . ebp-overload)))
    (ebp-client-start client)
    client))

(provide 'ebp)
;;; ebp.el ends here
