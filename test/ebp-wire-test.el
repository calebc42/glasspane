;;; ebp-wire-test.el --- W1 conformance suite for ebp.el -*- lexical-binding: t; -*-

;;; Commentary:

;; Driven by the ebp submodule's conformance corpus (SPEC 24.5-24.6):
;; - the 9.3 HMAC known-answer vector, recomputed from scratch;
;; - every goldens/wire fixture decoded at whole/1-octet/7-octet chunk
;;   sizes with the manifest's expected outcome (positive fixtures must
;;   yield the expected messages; negative fixtures the expected error);
;; - encoder byte syntax, including the UTF-8 byte-count rule;
;; - envelope classification and handshake params against contract.json.

;;; Code:

(require 'ert)
(require 'ebp)

(defconst ebp-test--root
  (expand-file-name ".." (file-name-directory
                          (or load-file-name buffer-file-name)))
  "llm-poc-2 checkout root.")

(defconst ebp-test--ebp (expand-file-name "ebp" ebp-test--root)
  "The ebp submodule: spec, contract, goldens.")

(defun ebp-test--read-bytes (path)
  "Unibyte contents of PATH."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (buffer-string)))

(defun ebp-test--read-json (path)
  "Parse the JSON file at PATH into alists/lists."
  (json-parse-string (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))
                     :object-type 'alist :array-type 'list
                     :null-object :null :false-object :false))

(defun ebp-test--json-equal (a b)
  "Structural JSON equality over parsed alist/list values (SPEC 4.3-ish).
Alists compare as unordered member sets; lists as ordered arrays."
  (cond
   ((and (consp a) (consp (car-safe a)) (consp b) (consp (car-safe b)))
    (and (= (length a) (length b))
         (cl-every (lambda (pair)
                     (let ((other (assq (car pair) b)))
                       (and other (ebp-test--json-equal (cdr pair) (cdr other)))))
                   a)))
   ((and (listp a) (listp b)) ; arrays (or the ambiguous empty {}/[])
    (and (= (length a) (length b))
         (cl-every #'ebp-test--json-equal a b)))
   ((and (numberp a) (numberp b)) (= a b))
   (t (equal a b))))

;;;; SPEC 9.3 known-answer vector

(ert-deftest ebp-test-kat-proofs ()
  "The 9.3 KAT reproduces exactly, from token decode through both proofs."
  (let ((token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw"))
        (pid "101112131415161718191a1b1c1d1e1f")
        (cn "202122232425262728292a2b2c2d2e2f")
        (sn "303132333435363738393a3b3c3d3e3f"))
    (should (equal (ebp-client-proof token pid cn sn)
                   (concat "03e270fd0af4566336283444b641a722"
                           "b5828c190ebdbe3dc50c5be2c9c9fb43")))
    (should (equal (ebp-server-proof token pid cn sn)
                   (concat "e9333d48cfc2780d708db4a9782705c5"
                           "e1c988c7eedc2d1734051f2fb9be58ec")))
    (should (ebp-verify-server-proof
             (ebp-server-proof token pid cn sn) token pid cn sn))
    (should-not (ebp-verify-server-proof
                 (ebp-client-proof token pid cn sn) token pid cn sn))))

;;;; Wire fixtures (SPEC 24.5: varied chunk sizes; 24.6 items 1-3)

(defconst ebp-test--error-map
  '(("close" . ebp-frame-close)
    ("incomplete-frame" . ebp-frame-incomplete)
    ("parse-error" . ebp-parse-error)
    ("invalid-request" . ebp-invalid-request)))

(defun ebp-test--chunkings (bytes)
  `(("whole" . (,bytes))
    ("1-octet" . ,(cl-loop for i below (length bytes)
                           collect (substring bytes i (1+ i))))
    ("7-octet" . ,(cl-loop for i below (length bytes) by 7
                           collect (substring bytes i
                                              (min (+ i 7) (length bytes)))))))

(defun ebp-test--run-fixture (bytes)
  "Feed BYTES through a fresh decoder; return (messages . nil) or (nil . err)."
  (condition-case err
      (let ((dec (ebp-make-decoder)) (msgs '()))
        (cons (progn
                (setq msgs (ebp-decoder-feed dec bytes))
                (ebp-decoder-finish dec)
                msgs)
              nil))
    ((ebp-frame-close ebp-frame-incomplete ebp-parse-error ebp-invalid-request)
     (cons nil (car err)))))

(defun ebp-test--run-fixture-chunked (chunks)
  (condition-case err
      (let ((dec (ebp-make-decoder)) (msgs '()))
        (dolist (c chunks) (setq msgs (nconc msgs (ebp-decoder-feed dec c))))
        (ebp-decoder-finish dec)
        (cons msgs nil))
    ((ebp-frame-close ebp-frame-incomplete ebp-parse-error ebp-invalid-request)
     (cons nil (car err)))))

(defconst ebp-test--claims-strict-framing t
  "Non-nil when this endpoint owes every SPEC 6.2 receiver duty itself.

SPEC 24.5 lets a Golden scope its expectation to a role, because SPEC 6.2
scopes several receiver duties by role and an Emacs endpoint MAY elect the
delegation clause — in which case a duplicate-member or over-deep body it
handed to a host library is silently accepted instead of refused, and the
manifest's expectation is unproducible.  This endpoint does NOT elect it:
`ebp-make-decoder' is our own framing and JSON-model receiver, not
jsonrpc.el's, so we are held to the Companion-strength expectation on every
fixture.  A fork that delegates flips this to nil and gets SPEC 24.5's
excused-role obligation instead — a bounded terminal reaction — rather than
skipping the vector.")

(ert-deftest ebp-test-wire-goldens ()
  "Every ebp/goldens/wire fixture behaves per its manifest entry, at
whole, 1-octet, and 7-octet transport-read chunk sizes."
  (let* ((manifest (ebp-test--read-json
                    (expand-file-name "goldens/wire/manifest.json"
                                      ebp-test--ebp))))
    (dolist (fx (alist-get 'fixtures manifest))
      (let* ((file (alist-get 'file fx))
             (bytes (ebp-test--read-bytes
                     (expand-file-name (concat "goldens/wire/" file)
                                       ebp-test--ebp)))
             (kind (alist-get 'kind fx)))
        (dolist (chunking (ebp-test--chunkings bytes))
          (pcase-let ((`(,msgs . ,err)
                       (ebp-test--run-fixture-chunked (cdr chunking))))
            (if (equal kind "positive")
                (let ((expected (alist-get 'expect_messages fx)))
                  (should-not err)
                  (should (= (length msgs) (length expected)))
                  (cl-loop for m in msgs for e in expected
                           do (should (ebp-test--json-equal m e))))
              (let* ((want (cdr (assoc (alist-get 'expect_error fx)
                                       ebp-test--error-map)))
                     (roles (append (alist-get 'roles fx) nil))
                     (normative (or (null roles) (member "emacs" roles))))
                (if (or normative ebp-test--claims-strict-framing)
                    (should (eq err want))
                  ;; SPEC 24.5: an excused role still owes a bounded terminal
                  ;; reaction — the stream left synchronized or closed, and no
                  ;; application effect. Never a skipped vector.
                  (should (or err (<= (length msgs) 1))))))))))))

(ert-deftest ebp-test-utf8-byte-count-fixture ()
  "SPEC 24.6 item 1: the UTF-8 fixture's Content-Length differs from its
character count, and our encoder reproduces the octet count exactly."
  (let* ((bytes (ebp-test--read-bytes
                 (expand-file-name "goldens/wire/03-utf8-length.bin"
                                   ebp-test--ebp)))
         (header-end (+ (string-search "\r\n\r\n" bytes) 4))
         (declared (progn
                     (string-match "Content-Length: \\([0-9]+\\)" bytes)
                     (string-to-number (match-string 1 bytes))))
         (body-bytes (substring bytes header-end))
         (body-text (decode-coding-string body-bytes 'utf-8)))
    (should (= declared (length body-bytes)))
    (should-not (= declared (length body-text)))
    ;; Encoder: re-framing the decoded text reproduces the same octet count.
    (let ((reframed (ebp-encode-frame body-text)))
      (should (equal reframed bytes)))))

;;;; Encoder syntax (SPEC 6.1)

(ert-deftest ebp-test-encoder-syntax ()
  (let ((frame (ebp-encode-frame "{}")))
    (should (equal frame "Content-Length: 2\r\n\r\n{}")))
  ;; Non-ASCII: length is octets, not characters — 9 characters, 10 octets.
  (let ((frame (ebp-encode-frame "{\"a\":\"é\"}")))
    (should (string-prefix-p "Content-Length: 10\r\n\r\n" frame))))

(ert-deftest ebp-test-over-deep-body-is-parse-error ()
  "SPEC 4.5: a body nesting past 64 containers is a parse error, refused
before the recursive parser can run."
  (let ((deep (concat (apply #'concat (make-list 65 "{\"a\":"))
                      "1" (make-string 65 ?}))))
    (should-error (ebp-decoder-feed (ebp-make-decoder) (ebp-encode-frame deep))
                  :type 'ebp-parse-error))
  ;; Exactly 64 containers is within the limit and decodes.
  (let ((ok (concat (apply #'concat (make-list 64 "{\"a\":"))
                    "1" (make-string 64 ?}))))
    (should (ebp-decoder-feed (ebp-make-decoder) (ebp-encode-frame ok)))))

;;;; Envelope (SPEC 7)

(ert-deftest ebp-test-envelope-classification ()
  (should (eq (ebp-message-class
               '((jsonrpc . "2.0") (id . "r1") (method . "session.ready")
                 (params . nil)))
              'request))
  (should (eq (ebp-message-class
               '((jsonrpc . "2.0") (method . "state.changed") (params . nil)))
              'notification))
  (should (eq (ebp-message-class '((jsonrpc . "2.0") (id . "r1") (result . nil)))
              'response))
  (should-not (ebp-message-class '((jsonrpc . "1.0") (method . "x"))))
  (should-not (ebp-message-class '((jsonrpc . "2.0") (id . "r1")
                                   (result . nil) (error . nil)))))

(ert-deftest ebp-test-request-id-grammar ()
  "SPEC 7.2 (amendments #34/#80): string identifiers 1..64 octets, or
safe integers; null and fractional numbers never."
  (should (ebp-valid-request-id-p "r1"))
  (should (ebp-valid-request-id-p (make-string 64 ?a)))
  (should-not (ebp-valid-request-id-p (make-string 65 ?a)))
  (should-not (ebp-valid-request-id-p ""))
  (should (ebp-valid-request-id-p 7))
  (should-not (ebp-valid-request-id-p 7.0))
  (should-not (ebp-valid-request-id-p nil)))

;;;; Handshake params against contract.json (format 6)

(ert-deftest ebp-test-handshake-params-match-contract ()
  "Builder output carries exactly the contract's required params."
  (let* ((contract (ebp-test--read-json
                    (expand-file-name "contract.json" ebp-test--ebp)))
         (methods (alist-get 'methods contract))
         (needed (lambda (m)
                   (alist-get 'required
                              (alist-get 'params (alist-get m methods)))))
         (keys (lambda (plist)
                 (cl-loop for (k _) on plist by #'cddr
                          collect (substring (symbol-name k) 1))))
         (token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw"))
         (hello (ebp-hello-params "test-client" "0.0.1"
                                  "101112131415161718191a1b1c1d1e1f"
                                  "202122232425262728292a2b2c2d2e2f" '()))
         (auth (ebp-auth-params "101112131415161718191a1b1c1d1e1f"
                                "202122232425262728292a2b2c2d2e2f"
                                "303132333435363738393a3b3c3d3e3f" token)))
    (should (null (cl-set-exclusive-or (funcall keys hello)
                                       (funcall needed 'session\.hello)
                                       :test #'equal)))
    (should (null (cl-set-exclusive-or (funcall keys auth)
                                       (funcall needed 'auth\.response)
                                       :test #'equal)))
    (should (ebp-valid-proof-p (plist-get auth :client_proof)))))

;;;; Duplicate members and nonce grammar

(ert-deftest ebp-test-duplicate-member-scan ()
  (should (ebp--duplicate-members-p "{\"a\":1,\"a\":2}"))
  ;; Semantic comparison: a is "a".
  (should (ebp--duplicate-members-p "{\"a\":1,\"\\u0061\":2}"))
  (should-not (ebp--duplicate-members-p "{\"a\":1,\"b\":{\"a\":2}}"))
  (should-not (ebp--duplicate-members-p "{\"a\":[{\"x\":1},{\"x\":2}]}"))
  (should-not (ebp--duplicate-members-p "{\"a\":\"a\",\"b\":\"a\"}")))

(ert-deftest ebp-test-nonce-generation ()
  (let ((n1 (ebp-generate-nonce)) (n2 (ebp-generate-nonce)))
    (should (ebp-valid-nonce-p n1))
    (should (ebp-valid-nonce-p n2))
    (should-not (equal n1 n2))))

;;;; Session state machine (SPEC 10.1, client view)

(ert-deftest ebp-test-session-transitions ()
  (let ((s 'connected))
    (dolist (step '((hello-sent . awaiting-nonce)
                    (nonce-received . challenged)
                    (auth-sent . awaiting-welcome)
                    (welcome-verified . syncing)
                    (ready-confirmed . ready)))
      (setq s (ebp-session-step s (car step)))
      (should (eq s (cdr step)))))
  ;; Illegal transitions return nil; close is always legal.
  (should-not (ebp-session-step 'connected 'welcome-verified))
  (should-not (ebp-session-step 'ready 'hello-sent))
  (should (eq (ebp-session-step 'ready 'close) 'closed))
  (should (eq (ebp-session-step 'connected 'close) 'closed)))

;;;; W3/W4: the jsonrpc-backed client against a scripted loopback companion

;; The client under test is the real `ebp-connect' live path (core
;; jsonrpc.el, decision log #2).  The scripted companion on the other end
;; of the loopback speaks through the reference encoder/decoder, so both
;; conformance layers exercise each other.

(defconst ebp-test--kat-token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw"))
(defconst ebp-test--kat-pid "101112131415161718191a1b1c1d1e1f")
(defconst ebp-test--kat-cn "202122232425262728292a2b2c2d2e2f")
(defconst ebp-test--kat-sn "303132333435363738393a3b3c3d3e3f")

(defconst ebp-test--welcome-limits
  '(:max_frame_bytes 4194304 :max_queued_events 256
    :max_queued_bytes 8388608 :max_event_bytes 262144
    :max_surfaces 16 :max_surface_ids 1024
    :max_field_bytes 65536 :max_input_state_bytes 262144
    :max_capture_fields 64))

(defun ebp-test--welcome-result (&optional server-proof drop surfaces)
  "A minimal SPEC 10.2 welcome result plist.
SERVER-PROOF overrides the correct KAT proof; DROP removes that member;
SURFACES overrides the empty surfaces map."
  (let ((welcome
         `(:server_proof ,(or server-proof
                              (ebp-server-proof ebp-test--kat-token
                                                ebp-test--kat-pid
                                                ebp-test--kat-cn
                                                ebp-test--kat-sn))
           :protocol 2
           :server (:name "kat-companion" :version "1.0.0")
           :granted ["theme"]
           :surface_profiles
           (:app (:node_types ["text" "row" "column" "box" "spacer"
                               "divider" "button" "text_input"]
                  :builtins ["view.switch" "companion.settings.open"]
                  :features []))
           :surfaces ,(or surfaces ebp--empty-object)
           :queued_events 0
           :limits ,ebp-test--welcome-limits)))
    (if drop
        (cl-loop for (k v) on welcome by #'cddr
                 unless (eq k drop) append (list k v))
      welcome)))

(defun ebp-test--start-companion (script)
  "Loopback scripted companion; returns (:port P :received FN :stop FN).
SCRIPT is called with (MSG SEND) per decoded inbound message."
  (let* ((received '())
         (decoders (make-hash-table :test #'eq))
         (server
          (make-network-process
           :name "ebp-test-companion" :server t :host "127.0.0.1" :service t
           :coding 'binary :noquery t
           :filter
           (lambda (conn bytes)
             (let ((dec (or (gethash conn decoders)
                            (puthash conn (ebp-make-decoder) decoders))))
               (dolist (msg (ebp-decoder-feed dec bytes))
                 (push msg received)
                 (funcall script msg
                          (lambda (reply)
                            (process-send-string
                             conn
                             (ebp-encode-frame
                              (ebp--json-serialize reply)))))))))))
    (list :port (cadr (process-contact server))
          :received (lambda () (reverse received))
          :stop (lambda () (delete-process server)))))

(cl-defun ebp-test--kat-script (&key welcome-fn after-ready surface-fn
                                     replay-fn)
  "The default conformant companion script over the KAT pairing.
REPLAY-FN, when given, is called with the 1-based replay call number and
returns that call's summary plist."
  (let ((replay-calls 0))
    (lambda (msg send)
      (let* ((method (alist-get 'method msg))
             (id (alist-get 'id msg))
             (reply (lambda (result)
                      (funcall send `(:jsonrpc "2.0" :id ,id :result ,result)))))
        (pcase method
          ("session.hello"
           (funcall reply `(:server_nonce ,ebp-test--kat-sn)))
          ("auth.response"
           (funcall reply (funcall (or welcome-fn #'identity)
                                   (ebp-test--welcome-result))))
          ("queue.replay"
           (cl-incf replay-calls)
           (funcall reply
                    (if replay-fn
                        (funcall replay-fn replay-calls)
                      '(:delivered 0 :rejected 0 :expired 0 :remaining 0
                        :blocked_by :null))))
        ("session.ready"
         (funcall reply ebp--empty-object)
         (when after-ready (funcall after-ready send)))
        ("surface.update"
         (funcall reply
                  (funcall (or surface-fn
                               (lambda (m)
                                 `(:status "applied"
                                   :revision ,(alist-get
                                               'revision (alist-get 'params m))
                                   :present t)))
                           msg)))
        ("surface.remove"
         (funcall reply `(:status "applied"
                          :revision ,(alist-get 'revision (alist-get 'params msg))
                          :present :false))))))))

(defun ebp-test--connect (port &rest extra)
  (apply #'ebp-connect "127.0.0.1" port
         :client-name "test-client" :client-version "0.0.1"
         :pairing-id ebp-test--kat-pid :token ebp-test--kat-token
         :wants '("theme") :client-nonce ebp-test--kat-cn
         ;; Tests never write the default user-emacs-directory receipts;
         ;; callers may override with their own :receipt-file first.
         (append extra (list :receipt-file
                             (make-temp-file "ebp-test-receipts")))))

(defun ebp-test--wait (pred &optional timeout)
  "Pump the event loop until PRED or TIMEOUT (default 5 s); return PRED."
  (let ((deadline (+ (float-time) (or timeout 5))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall pred)))

(defmacro ebp-test--with-companion (spec &rest body)
  "Bind SPEC = (SERVER-VAR CLIENT-VAR SCRIPT &rest CONNECT-ARGS); cleanup after."
  (declare (indent 1))
  (pcase-let ((`(,server-var ,client-var ,script . ,connect-args) spec))
    `(let* ((,server-var (ebp-test--start-companion ,script))
            (,client-var (ebp-test--connect (plist-get ,server-var :port)
                                            ,@connect-args)))
       (unwind-protect (progn ,@body)
         (ignore-errors (ebp-client-close ,client-var 'test-done))
         (funcall (plist-get ,server-var :stop))))))

(ert-deftest ebp-test-client-handshake-to-ready ()
  "The full SPEC 10.3 barrier over a live loopback: hello, auth, replay,
ready — in order, with the KAT proof on the wire."
  (let ((ready nil))
    (ebp-test--with-companion
        (server client (ebp-test--kat-script)
                :ready-function (lambda (_c) (setq ready t)))
      (should (ebp-test--wait (lambda () ready)))
      (should (eq (ebp-client-state client) 'ready))
      (let ((methods (mapcar (lambda (m) (alist-get 'method m))
                             (funcall (plist-get server :received)))))
        (should (equal methods '("session.hello" "auth.response"
                                 "queue.replay" "session.ready"))))
      ;; The auth request carried the exact KAT client proof.
      (let ((auth (nth 1 (funcall (plist-get server :received)))))
        (should (equal (alist-get 'client_proof (alist-get 'params auth))
                       (ebp-client-proof ebp-test--kat-token ebp-test--kat-pid
                                         ebp-test--kat-cn ebp-test--kat-sn))))
      ;; Welcome absorption (jsonrpc parses arrays as vectors).
      (should (equal (ebp-client-granted client) ["theme"]))
      (should (= (plist-get (ebp-client-limits client) :max_frame_bytes)
                 4194304)))))

(ert-deftest ebp-test-client-rejects-bad-server-proof ()
  "SPEC 9.3: Emacs MUST verify server_proof before trusting the welcome."
  (ebp-test--with-companion
      (server client
              (ebp-test--kat-script
               :welcome-fn
               (lambda (w)
                 (plist-put (copy-sequence w) :server_proof
                            (ebp-client-proof ebp-test--kat-token
                                              ebp-test--kat-pid
                                              ebp-test--kat-cn
                                              ebp-test--kat-sn)))))
    (should (ebp-test--wait
             (lambda () (eq (ebp-client-state client) 'closed))))
    (should (equal (ebp-client-close-reason client) '(server-proof-invalid)))))

(ert-deftest ebp-test-client-rejects-incomplete-welcome ()
  "SPEC 10.2: the welcome MUST contain the required members."
  (ebp-test--with-companion
      (server client
              (ebp-test--kat-script
               :welcome-fn (lambda (_w) (ebp-test--welcome-result nil :limits))))
    (should (ebp-test--wait
             (lambda () (eq (ebp-client-state client) 'closed))))
    (should (equal (ebp-client-close-reason client) '(welcome-incomplete)))))

(ert-deftest ebp-test-client-answers-unknown-request ()
  "SPEC 7.3: an unknown request receives -32601 — hand-rolled, because
jsonrpc.el's default is fail-open (kit section 3)."
  (ebp-test--with-companion
      (server client
              (ebp-test--kat-script
               :after-ready
               (lambda (send)
                 (funcall send `(:jsonrpc "2.0" :id 99 :method "no.such"
                                 :params ,ebp--empty-object)))))
    (should (ebp-test--wait
             (lambda ()
               (cl-find-if (lambda (m)
                             (and (equal (alist-get 'id m) 99)
                                  (alist-get 'error m)))
                           (funcall (plist-get server :received))))))
    (let ((response (cl-find-if (lambda (m) (equal (alist-get 'id m) 99))
                                (funcall (plist-get server :received)))))
      (should (= (alist-get 'code (alist-get 'error response)) -32601)))
    (should (eq (ebp-client-state client) 'ready))))

(ert-deftest ebp-test-client-handler-registry ()
  "Registered handlers answer inbound requests through the library's
reply path; params arrive as plists."
  (let ((seen nil))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :after-ready
                 (lambda (send)
                   (funcall send
                            '(:jsonrpc "2.0" :id 100 :method "event.action"
                              :params (:event_id "00112233445566778899aabbccddeeff"
                                       :action "demo.tap"
                                       :occurred_at_ms 1784700000000))))))
      (ebp-client-register-handler
       client "event.action"
       (lambda (_c params)
         (setq seen (plist-get params :action))
         '(:status "accepted")))
      (should (ebp-test--wait
               (lambda ()
                 (cl-find-if (lambda (m)
                               (and (equal (alist-get 'id m) 100)
                                    (alist-get 'result m)))
                             (funcall (plist-get server :received))))))
      (should (equal seen "demo.tap"))
      (let ((response (cl-find-if (lambda (m) (equal (alist-get 'id m) 100))
                                  (funcall (plist-get server :received)))))
        (should (equal (alist-get 'status (alist-get 'result response))
                       "accepted"))))))

(ert-deftest ebp-test-client-surface-revisions-above-floors ()
  "SPEC 10.3 step 3 + 13.1 over the live path: pushes climb past reported
floors (including tombstones) and absorb applied/stale results."
  (let ((ready nil) (statuses '()))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :welcome-fn
                 (lambda (_w)
                   (ebp-test--welcome-result
                    nil nil '(:app:main (:revision 41 :present t)
                              :app:old (:revision 9 :present :false))))
                 :surface-fn
                 (lambda (m)
                   (let ((rev (alist-get 'revision (alist-get 'params m))))
                     (if (= rev 43)
                         '(:status "stale" :revision 50 :present t)
                       `(:status "applied" :revision ,rev :present t)))))
                :ready-function (lambda (_c) (setq ready t)))
      (should (ebp-test--wait (lambda () ready)))
      (let ((record (lambda (status _err) (push status statuses))))
        ;; First push climbs past the welcome floor.
        (should (= (ebp-client-surface-update client "app:main"
                                              '(:t "text" :text "hi")
                                              :callback record)
                   42))
        ;; The tombstoned surface's floor is honored on reuse.
        (should (= (ebp-client-surface-update client "app:old"
                                              '(:t "text" :text "back")
                                              :callback record)
                   10))
        ;; In-flight pushes still get newer revisions; this one draws the
        ;; scripted stale at 50.
        (should (= (ebp-client-surface-update client "app:main"
                                              '(:t "text" :text "again")
                                              :callback record)
                   43))
        (should (ebp-test--wait (lambda () (= (length statuses) 3))))
        (should (equal (sort (copy-sequence statuses) #'string<)
                       '("applied" "applied" "stale")))
        ;; The stale result absorbed the Companion's floor (SPEC 13.2).
        (should (= (ebp-client-surface-update client "app:main"
                                              '(:t "text" :text "newest"))
                   51))))))

(ert-deftest ebp-test-client-surface-remove-is-revisioned ()
  "SPEC 13.3: removal claims a fresh revision like any mutation."
  (let ((ready nil) (status nil))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :welcome-fn
                 (lambda (_w)
                   (ebp-test--welcome-result
                    nil nil '(:app:main (:revision 41 :present t)))))
                :ready-function (lambda (_c) (setq ready t)))
      (should (ebp-test--wait (lambda () ready)))
      (should (= (ebp-client-surface-remove
                  client "app:main"
                  :callback (lambda (s _e) (setq status s)))
                 42))
      (should (ebp-test--wait (lambda () status)))
      (should (equal status "applied"))
      (let ((remove (cl-find-if
                     (lambda (m) (equal (alist-get 'method m) "surface.remove"))
                     (funcall (plist-get server :received)))))
        (should (= (alist-get 'revision (alist-get 'params remove)) 42))
        (should-not (assq 'spec (alist-get 'params remove))))
      ;; Recreating the surface climbs past the tombstone.
      (should (= (ebp-client-surface-update client "app:main"
                                            '(:t "text" :text "reborn"))
                 43)))))

;;;; W5: the event.action server and state.changed (SPEC 14)

(defun ebp-test--event-params (event-id &optional action)
  `(:event_id ,event-id
    :action ,(or action "demo.count")
    :surface "app:main" :revision_seen 41
    :occurred_at_ms 1784700000000))

(defun ebp-test--send-event (send id event-id &optional action)
  (funcall send `(:jsonrpc "2.0" :id ,id :method "event.action"
                  :params ,(ebp-test--event-params event-id action))))

(defun ebp-test--response-for (server id)
  (cl-find-if (lambda (m) (and (equal (alist-get 'id m) id)
                               (or (alist-get 'result m) (alist-get 'error m))))
              (funcall (plist-get server :received))))

(ert-deftest ebp-test-inbound-fails-closed-before-auth ()
  "SPEC 10.1/7.3: before the welcome is verified every inbound request
receives 1200 not-authenticated — even a registered or unknown one — and
every notification is dropped, with no handler run.  `syncing' (replay)
and `ready' dispatch normally."
  (let* ((ran nil)
         (params (ebp-test--event-params "00112233445566778899aabbccddeeff"))
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts")))
         (dispatch-code
          (lambda (method)
            (condition-case err
                (progn (ebp-client--request-dispatcher client nil method params)
                       nil)
              (jsonrpc-error (alist-get 'jsonrpc-error-code (cdr err)))))))
    ;; Spy handlers replace the endpoint's real SPEC 14 servers.
    (ebp-client-register-handler client "event.action"
                                 (lambda (_c _p) (setq ran t) '(:status "accepted")))
    (ebp-client-register-handler client "state.changed"
                                 (lambda (_c _p) (setq ran t)))
    (dolist (state '(connected awaiting-nonce challenged awaiting-welcome))
      (setf (ebp-client-state client) state)
      (setq ran nil)
      ;; A registered request fails closed with 1200, handler untouched.
      (should (equal (funcall dispatch-code 'event.action) 1200))
      (should-not ran)
      ;; An unknown request is 1200 too — not -32601 (SPEC 10.1).
      (should (equal (funcall dispatch-code 'no.such) 1200))
      ;; A notification is dropped silently.
      (ebp-client--notification-dispatcher client nil 'state.changed params)
      (should-not ran))
    (dolist (state '(syncing ready))
      (setf (ebp-client-state client) state)
      (setq ran nil)
      (ebp-client--request-dispatcher client nil 'event.action params)
      (should ran)
      (setq ran nil)
      (ebp-client--notification-dispatcher client nil 'state.changed params)
      (should ran))))

(ert-deftest ebp-test-event-action-statuses-and-duplicates ()
  "SPEC 14.4: accepted commits a receipt; a repeated EventId returns
duplicate without repeating the effect; unregistered actions reject."
  (let ((runs 0))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :after-ready
                 (lambda (send)
                   (ebp-test--send-event send 200 (make-string 32 ?a))
                   (ebp-test--send-event send 201 (make-string 32 ?a))
                   (ebp-test--send-event send 202 (make-string 32 ?b)
                                         "no.handler"))))
      (ebp-client-register-action
       client "demo.count"
       (lambda (_c _params) (cl-incf runs) 'accepted))
      (should (ebp-test--wait (lambda () (ebp-test--response-for server 202))))
      (should (equal (alist-get 'status (alist-get 'result
                                                   (ebp-test--response-for server 200)))
                     "accepted"))
      (should (equal (alist-get 'status (alist-get 'result
                                                   (ebp-test--response-for server 201)))
                     "duplicate"))
      (should (= runs 1))
      (should (equal (alist-get 'status (alist-get 'result
                                                   (ebp-test--response-for server 202)))
                     "rejected")))))

(ert-deftest ebp-test-event-action-duplicate-after-restart ()
  "SPEC 24.6 item 9: duplicate delivery after Emacs restart returns
duplicate from the durable receipt store, without the handler running."
  (let* ((receipt-file (make-temp-file "ebp-receipts"))
         (event-id (make-string 32 ?c))
         (runs 0))
    (unwind-protect
        (progn
          ;; First life: accept and durably commit.
          (ebp-test--with-companion
              (server client
                      (ebp-test--kat-script
                       :after-ready
                       (lambda (send) (ebp-test--send-event send 300 event-id)))
                      :receipt-file receipt-file)
            (ebp-client-register-action
             client "demo.count" (lambda (_c _p) (cl-incf runs) 'accepted))
            (should (ebp-test--wait
                     (lambda () (ebp-test--response-for server 300)))))
          (should (= runs 1))
          ;; Second life: same receipt file, same EventId redelivered.
          (ebp-test--with-companion
              (server client
                      (ebp-test--kat-script
                       :after-ready
                       (lambda (send) (ebp-test--send-event send 301 event-id)))
                      :receipt-file receipt-file)
            (ebp-client-register-action
             client "demo.count" (lambda (_c _p) (cl-incf runs) 'accepted))
            (should (ebp-test--wait
                     (lambda () (ebp-test--response-for server 301))))
            (should (equal (alist-get 'status
                                      (alist-get 'result
                                                 (ebp-test--response-for server 301)))
                           "duplicate"))
            (should (= runs 1))))
      (delete-file receipt-file))))

(ert-deftest ebp-test-event-action-malformed-is-invalid-params ()
  "SPEC 7.3: structurally invalid request params receive -32602."
  (ebp-test--with-companion
      (server client
              (ebp-test--kat-script
               :after-ready
               (lambda (send)
                 ;; Both surface and dialog context: exclusivity violated.
                 (funcall send '(:jsonrpc "2.0" :id 400 :method "event.action"
                                 :params (:event_id "00112233445566778899aabbccddeeff"
                                          :action "demo.count"
                                          :surface "app:main" :revision_seen 1
                                          :dialog_id "d1"
                                          :occurred_at_ms 1784700000000))))))
    (should (ebp-test--wait (lambda () (ebp-test--response-for server 400))))
    (should (= (alist-get 'code (alist-get 'error
                                           (ebp-test--response-for server 400)))
               -32602))))

(ert-deftest ebp-test-state-changed-adopt-and-reset ()
  "SPEC 14.6 + P1 #2: values adopt across old revisions; an explicit
reset at a higher revision supersedes; a later report reinstates."
  (let ((ready nil) (seen '()))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :welcome-fn
                 (lambda (_w) (ebp-test--welcome-result
                               nil nil '(:app:main (:revision 41 :present t))))
                 :after-ready
                 (lambda (send)
                   ;; Adopted: no reset history yet.
                   (funcall send '(:jsonrpc "2.0" :method "state.changed"
                                   :params (:surface "app:main" :revision_seen 41
                                            :id "title" :value "first")))))
                :ready-function (lambda (_c) (setq ready t))
                :state-changed-function
                (lambda (_c _s _r id value) (push (cons id value) seen)))
      (should (ebp-test--wait (lambda () (and ready seen))))
      (should (equal (ebp-client-input-value client "app:main" "title")
                     "first"))
      ;; Push revision 42 resetting the draft; a racing report against 41
      ;; must be discarded, one against 42 adopted (P1 #2).
      (ebp-client-surface-update client "app:main"
                                 '(:t "text_input" :id "title")
                                 :reset-input-ids '("title"))
      (ebp-client--handle-state-changed
       client '(:surface "app:main" :revision_seen 41
                :id "title" :value "raced-and-lost"))
      (should (equal (ebp-client-input-value client "app:main" "title")
                     "first"))
      (ebp-client--handle-state-changed
       client '(:surface "app:main" :revision_seen 42
                :id "title" :value "reinstated"))
      (should (equal (ebp-client-input-value client "app:main" "title")
                     "reinstated")))))

(ert-deftest ebp-test-reset-history-precedes-the-send ()
  "A8/H1: a send is NOT atomic with respect to our own state.
`process-send-string' on a frame large enough to fill the socket buffer
blocks in `send_process', which spins in `wait_reading_process_output'
\(emacs-30.1 src/process.c:6851), which runs `timer_check'
\(src/process.c:5434) — and jsonrpc.el dispatches inbound messages from
timers (jsonrpc.el:804-811).  So an inbound `state.changed' can be
handled re-entrantly INSIDE our own `surface.update' send, with
`jsonrpc--in-process-filter' nil, which is why the bug#60088 guard does
not cover it.

The reset history must therefore be recorded before the frame reaches
the wire.  Recorded after the send returns, the racing report finds no
reset for this revision and adopts a draft the snapshot supersedes
\(SPEC 14.6 / P1 #2).  See docs/RESEARCH-A8-2026-07-25.md."
  (let* ((client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts")))
         (raced nil))
    ;; The Companion has already reported a floor of 41, so the push below
    ;; claims 42 and its `reset_input_ids' supersedes any report against 41.
    (puthash "app:main" 41 (ebp-client-revisions client))
    (cl-letf (((symbol-function 'ebp-client--request)
               (lambda (c _method _params _callback &optional _timeout)
                 ;; The re-entrant dispatch, at the only moment it can
                 ;; occur: inside the send, before it has returned.
                 (setq raced t)
                 (ebp-client--handle-state-changed
                  c '(:surface "app:main" :revision_seen 41
                      :id "title" :value "raced-and-lost")))))
      (should (equal (ebp-client-surface-update
                      client "app:main" '(:t "text_input" :id "title")
                      :reset-input-ids '("title"))
                     42)))
    (should raced)
    (should-not (ebp-client-input-value client "app:main" "title"))
    ;; The reset is recorded once, against the revision actually sent.
    (should (equal (gethash "app:main" (ebp-client-reset-history client))
                   '((42 "title"))))))

(ert-deftest ebp-test-transport-coding-is-pinned ()
  "A8/3-c: `ebp-connect' pins `:coding utf-8-unix' and MUST keep doing so.
Left unpinned, `undecided' latches `undecided-dos', which strips the CR
from the `\\r\\n\\r\\n' terminator; jsonrpc.el's header search
\(emacs-30.1 jsonrpc.el:740-744) matches a literal CRLF, so it never
fires.  There is no error, no close, and no diagnostic — the connection
simply never dispatches again, which is exactly the unbounded stall
amendment #91 ruled out as a conforming alternative.

Pairs with `ebp-test-live-socket-carries-non-ascii', which guards the
other half (`binary' over-counts a non-ASCII body via `position-bytes')."
  (dolist (probe '((utf-8-unix . t) (undecided . nil)))
    (let* ((coding (car probe))
           (expect (cdr probe))
           (got nil)
           (server
            (make-network-process
             :name "ebp-pin-server" :server t :host "127.0.0.1"
             :service t :coding 'binary :noquery t
             :filter
             (lambda (conn _bytes)
               (let ((body "{\"jsonrpc\":\"2.0\",\"method\":\"probe.note\",\
\"params\":{\"n\":1}}"))
                 (process-send-string
                  conn (concat (format "Content-Length: %d\r\n\r\n"
                                       (string-bytes body))
                               body))))))
           (port (cadr (process-contact server)))
           (proc (make-network-process
                  :name "ebp-pin-client" :host "127.0.0.1" :service port
                  :noquery t :coding coding))
           (conn (make-instance 'jsonrpc-process-connection
                                :name "ebp-pin" :process proc
                                :notification-dispatcher
                                (lambda (_c m p) (push (list m p) got)))))
      (unwind-protect
          (progn
            (process-send-string proc "hi")
            (dotimes (_ 30) (accept-process-output nil 0.05))
            (if expect
                (should (equal got '((probe.note (:n 1)))))
              ;; Pin the failure mode too, so the docstring stays true.
              (should (eq (car (process-coding-system proc)) 'undecided-dos))
              (should-not got)))
        (ignore-errors (delete-process proc))
        (ignore-errors (delete-process server))))))

;;;; W6: replay retries with bounded backoff (SPEC 10.3/15.3)

(ert-deftest ebp-test-replay-retry-until-drained ()
  "A blocked barrier replay still reaches READY (SPEC 10.3), then the
client retries with backoff until `remaining' drains (SPEC 15.3)."
  (let ((ready nil))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :replay-fn
                 (lambda (n)
                   (if (= n 1)
                       ;; The first replay stops on a transient error with
                       ;; two events still retained.
                       '(:delivered 1 :rejected 0 :expired 0 :remaining 2
                         :blocked_by "event-retry")
                     '(:delivered 2 :rejected 0 :expired 0 :remaining 0
                       :blocked_by :null))))
                :replay-retry-delay 0.15
                :ready-function (lambda (_c) (setq ready t)))
      ;; SPEC 10.3: the blocked replay concluded; READY is reached.
      (should (ebp-test--wait (lambda () ready)))
      (should (= (plist-get (ebp-client-replay-summary client) :remaining) 2))
      ;; The bounded-backoff retry drains the backlog.
      (should (ebp-test--wait
               (lambda ()
                 (= (plist-get (ebp-client-replay-summary client) :remaining)
                    0))))
      (let ((replays (cl-count-if
                      (lambda (m) (equal (alist-get 'method m) "queue.replay"))
                      (funcall (plist-get server :received)))))
        (should (= replays 2))))))

(ert-deftest ebp-test-errored-replay-still-reaches-ready ()
  "SPEC 10.3 (amendment #112): a replay concludes for the barrier on ANY
result, ANY JSON-RPC error, or local abandonment — and in every case
Emacs MUST proceed to `session.ready'.  An error here used to close the
connection, stranding a durable backlog behind a transport that never
came back and leaving SYNCING as the terminal state."
  (let ((ready nil))
    (ebp-test--with-companion
        (server client
                (lambda (msg send)
                  (let* ((method (alist-get 'method msg))
                         (id (alist-get 'id msg))
                         (reply (lambda (result)
                                  (funcall send `(:jsonrpc "2.0" :id ,id
                                                  :result ,result)))))
                    (pcase method
                      ("session.hello"
                       (funcall reply `(:server_nonce ,ebp-test--kat-sn)))
                      ("auth.response"
                       (funcall reply (ebp-test--welcome-result)))
                      ("queue.replay"
                       ;; SPEC 15.3's 1600 backlog-unavailable: transient,
                       ;; and the events stay durable on the Companion.
                       (funcall send `(:jsonrpc "2.0" :id ,id
                                       :error (:code 1600
                                               :message "backlog unavailable"
                                               :data (:kind "event-retry")))))
                      ("session.ready" (funcall reply ebp--empty-object)))))
                :replay-retry-delay 0.15
                :ready-function (lambda (_c) (setq ready t)))
      (should (ebp-test--wait (lambda () ready)))
      (should (eq (ebp-client-state client) 'ready))
      (let ((methods (mapcar (lambda (m) (alist-get 'method m))
                             (funcall (plist-get server :received)))))
        ;; The errored replay is followed by session.ready — and by exactly
        ;; one replay before READY, never a second (SPEC 10.3).
        (should (equal (seq-take methods 4)
                       '("session.hello" "auth.response"
                         "queue.replay" "session.ready"))))
      ;; Nothing is known about `remaining' after an error, so SPEC 15.3's
      ;; retry must still run rather than assume a drained backlog.
      (should (ebp-test--wait
               (lambda ()
                 (> (cl-count-if
                     (lambda (m) (equal (alist-get 'method m) "queue.replay"))
                     (funcall (plist-get server :received)))
                    1)))))))

(ert-deftest ebp-test-abandoned-request-is-cancelled-on-the-wire ()
  "SPEC 7.1/7.5 (amendment #112): a requester that stops waiting MUST send
`rpc.cancel' for that id before treating the request as concluded.
jsonrpc.el's timeout deletes the continuation and writes NOTHING to the
peer, so without this the Companion holds the request outstanding
forever and the id never concludes for SPEC 7.2."
  (let ((ready nil) (answered 'pending))
    (ebp-test--with-companion
        (server client
                ;; A companion that completes the handshake and then never
                ;; answers surface.update.
                (lambda (msg send)
                  (let* ((method (alist-get 'method msg))
                         (id (alist-get 'id msg))
                         (reply (lambda (result)
                                  (funcall send `(:jsonrpc "2.0" :id ,id
                                                  :result ,result)))))
                    (pcase method
                      ("session.hello"
                       (funcall reply `(:server_nonce ,ebp-test--kat-sn)))
                      ("auth.response"
                       (funcall reply (ebp-test--welcome-result)))
                      ("queue.replay"
                       (funcall reply '(:delivered 0 :rejected 0 :expired 0
                                        :remaining 0 :blocked_by :null)))
                      ("session.ready" (funcall reply ebp--empty-object)))))
                :ready-function (lambda (_c) (setq ready t)))
      (should (ebp-test--wait (lambda () ready)))
      (let ((ebp-request-timeout 0.3))
        (ebp-client-surface-update
         client "main" '(:type "text" :text "hi")
         :callback (lambda (status error)
                     (setq answered (list status error)))))
      ;; The local deadline expires: the callback sees the abandonment...
      (should (ebp-test--wait (lambda () (not (eq answered 'pending)))))
      (should (equal (plist-get (nth 1 answered) :code) -32000))
      ;; ...and the peer is told, with the id of the very request abandoned.
      (should (ebp-test--wait
               (lambda ()
                 (cl-find-if
                  (lambda (m) (equal (alist-get 'method m) "rpc.cancel"))
                  (funcall (plist-get server :received))))))
      (let* ((received (funcall (plist-get server :received)))
             (update (cl-find-if
                      (lambda (m) (equal (alist-get 'method m) "surface.update"))
                      received))
             (cancel (cl-find-if
                      (lambda (m) (equal (alist-get 'method m) "rpc.cancel"))
                      received)))
        (should (equal (alist-get 'id (alist-get 'params cancel))
                       (alist-get 'id update)))
        ;; SPEC 7.5: a cancellation is a notification, never a request.
        (should-not (alist-get 'id cancel))))))

(ert-deftest ebp-test-user-paced-timeout-floor ()
  "SPEC 7.1 (amendment #112): a requester MUST NOT apply a deadline under
60 seconds to the methods a responder holds pending user interaction —
`dialog.show' (SPEC 18.1) and `capability.invoke' (SPEC 20.2) — and
SHOULD apply none.  jsonrpc.el's 10 s default silently discards the
eventual answer, which for a dialog carrying `capture_fields' means a
submitted password is transmitted and then dropped."
  ;; No configured ceiling means no deadline at all, the SHOULD.
  (should (null (ebp-client--user-paced-timeout nil)))
  ;; A ceiling at or above the floor is honoured verbatim.
  (should (= 3600 (ebp-client--user-paced-timeout 3600)))
  (should (= 60 (ebp-client--user-paced-timeout 60)))
  ;; Anything under it is raised, not obeyed.
  (should (= 60 (ebp-client--user-paced-timeout 10)))
  (should (= 60 (ebp-client--user-paced-timeout 0.5)))
  ;; The defaults ship as "no deadline" for both user-paced methods.
  (should (null ebp-dialog-timeout))
  (should (null ebp-capability-timeout)))

(ert-deftest ebp-test-barrier-seam-and-kind-carrying-errors ()
  "SPEC 10.3 step 3: :before-replay-function pushes surfaces before the
replay on the wire; SPEC 8: a receipt-commit failure answers 1500 with
data.kind event-retry surviving jsonrpc.el's reply path."
  (let ((ready nil))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :after-ready
                 (lambda (send)
                   (ebp-test--send-event send 500 (make-string 32 ?d))))
                :receipt-file "/nonexistent-ebp-dir/receipts"
                :before-replay-function
                (lambda (c)
                  (ebp-client-surface-update c "app:pre"
                                             '(:t "text" :text "step 3")))
                :ready-function (lambda (_c) (setq ready t)))
      (ebp-client-register-action
       client "demo.count" (lambda (_c _p) 'accepted))
      (should (ebp-test--wait (lambda () ready)))
      ;; Step 3 before step 4, in wire order.
      (let ((methods (mapcar (lambda (m) (alist-get 'method m))
                             (funcall (plist-get server :received)))))
        (should (equal (cl-subseq methods 0 5)
                       '("session.hello" "auth.response" "surface.update"
                         "queue.replay" "session.ready"))))
      ;; The un-writable receipt file forces 1500 — with its kind intact.
      (should (ebp-test--wait (lambda () (ebp-test--response-for server 500))))
      (let ((err (alist-get 'error (ebp-test--response-for server 500))))
        (should (= (alist-get 'code err) 1500))
        (should (equal (alist-get 'kind (alist-get 'data err))
                       "event-retry"))))))

(ert-deftest ebp-test-negative-revision-seen-is-invalid ()
  "SPEC 14.4: revision_seen is a non-negative integer."
  (ebp-test--with-companion
      (server client
              (ebp-test--kat-script
               :after-ready
               (lambda (send)
                 (funcall send '(:jsonrpc "2.0" :id 501 :method "event.action"
                                 :params (:event_id "00112233445566778899aabbccddeeff"
                                          :action "demo.count"
                                          :surface "app:main" :revision_seen -1
                                          :occurred_at_ms 1784700000000))))))
    (ebp-client-register-action
     client "demo.count" (lambda (_c _p) 'accepted))
    (should (ebp-test--wait (lambda () (ebp-test--response-for server 501))))
    (should (= (alist-get 'code (alist-get 'error
                                           (ebp-test--response-for server 501)))
               -32602))))

;;;; Endpoint gaps closed after amendments #67-86 (2026-07-24)

(ert-deftest ebp-test-live-socket-carries-non-ascii ()
  "The live connection must decode a non-ASCII body.
`ebp-connect' pins `:coding utf-8-unix'.  `binary' looks right (SPEC 6
counts OCTETS) but is wrong here: jsonrpc.el's process buffer is
multibyte and `jsonrpc--process-filter' sizes the body with
`position-bytes', so a unibyte insert makes every octet >= 0x80 a
2-internal-byte raw char, the length arithmetic over-counts, and the
frame is silently dropped.  Every other wire test is ASCII-only, so
this is the only guard on that regression."
  (dolist (probe '((utf-8-unix . t) (binary . nil)))
    (let* ((coding (car probe))
           (expect (cdr probe))
           (got nil)
           (server
            (make-network-process
             :name "ebp-coding-server" :server t :host "127.0.0.1"
             :service t :coding 'binary :noquery t
             :filter
             (lambda (conn _bytes)
               (let* ((body (encode-coding-string
                             "{\"jsonrpc\":\"2.0\",\"method\":\"probe.note\",\
\"params\":{\"text\":\"café\"}}"
                             'utf-8))
                      (frame (concat (format "Content-Length: %d\r\n\r\n"
                                             (length body))
                                     body)))
                 (process-send-string conn frame)))))
           (port (cadr (process-contact server)))
           (proc (make-network-process
                  :name "ebp-coding-client" :host "127.0.0.1" :service port
                  :noquery t :coding coding))
           (conn (make-instance 'jsonrpc-process-connection
                                :name "ebp-coding" :process proc
                                :notification-dispatcher
                                (lambda (_c m p) (push (list m p) got)))))
      (unwind-protect
          (progn
            (process-send-string proc "hi")
            (dotimes (_ 30) (accept-process-output nil 0.05))
            (if expect
                (should (equal got '((probe.note (:text "café")))))
              ;; Pin the failure mode too, so the comment above stays true.
              (should-not got)))
        (ignore-errors (jsonrpc-shutdown conn))
        (ignore-errors (delete-process server))))))

(ert-deftest ebp-test-request-id-integer ()
  "SPEC 7.2 / amendments #34+#80: ids are strings or safe integers."
  (should (ebp-valid-request-id-p 1))
  (should (ebp-valid-request-id-p 0))
  (should (ebp-valid-request-id-p -3))
  (should (ebp-valid-request-id-p 9007199254740991))
  (should-not (ebp-valid-request-id-p 9007199254740992))
  (should-not (ebp-valid-request-id-p 1.5))
  (should-not (ebp-valid-request-id-p nil))
  (should (ebp-valid-request-id-p "req-1"))
  (should-not (ebp-valid-request-id-p ""))
  (should-not (ebp-valid-request-id-p (make-string 65 ?a))))

(ert-deftest ebp-test-theme-set-live-sentinels ()
  "theme.set params carry jsonrpc.el's sentinels; the reference
encoder's `:false'/`:null' are normalized, never sent (live-path bug)."
  (let* ((sent nil)
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts"))))
    (cl-letf (((symbol-function 'ebp-client-notify)
               (lambda (_c method params) (setq sent (cons method params)))))
      ;; Default: follow-system omits :dark entirely (amendment #36).
      (ebp-client-theme-set client)
      (should (equal (cdr sent) '()))
      ;; :false and :json-false both normalize to :json-false.
      (ebp-client-theme-set client :dark :false)
      (should (equal (cdr sent) '(:dark :json-false)))
      (ebp-client-theme-set client :dark :json-false)
      (should (equal (cdr sent) '(:dark :json-false)))
      (ebp-client-theme-set client :dark t)
      (should (equal (cdr sent) '(:dark t)))
      ;; null mirrors clear as JSON null = elisp nil under jsonrpc.el.
      (ebp-client-theme-set client :colors 'null :syntax 'null)
      (should (equal (cdr sent) '(:colors nil :syntax nil)))
      ;; Every emitted shape must survive the live encoder.
      (dolist (params (list '(:dark :json-false) '(:colors nil :syntax nil)))
        (should (json-serialize params :false-object :json-false
                                :null-object nil))))
    (should-error (ebp-client-theme-set client :dark 'sideways))))

(ert-deftest ebp-test-edit-apply-editor-too-large ()
  "SPEC 19.4 / amendment #84: a splice past max_editor_bytes is refused
locally with a synthetic 1201 editor-too-large; nothing reaches the wire."
  (let* ((sent nil) (cb nil)
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts"))))
    (setf (ebp-client-limits client) '(:max_editor_bytes 16))
    (puthash '("doc:1" . "body")
             (list :session (make-string 32 ?0) :seq 0 :text "seed" :cursor 0)
             (ebp-client-editors client))
    (cl-letf (((symbol-function 'ebp-client--request)
               (lambda (_c method params _cb &optional _t)
                 (push (cons method params) sent))))
      ;; 4 seed chars + 20 inserted + 2 JCS quotes = 26 > 16: refused.
      (ebp-client-edit-apply client "doc:1" "body" 4 0
                             (make-string 20 ?x)
                             :callback (lambda (status error)
                                         (setq cb (list status error))))
      (should-not sent)
      (should (null (car cb)))
      (should (= (plist-get (cadr cb) :code) 1201))
      (should (equal (plist-get (plist-get (cadr cb) :data) :reason)
                     "editor-too-large"))
      ;; A small splice is sent with the precomputed resulting length.
      (ebp-client-edit-apply client "doc:1" "body" 4 0 "+ok")
      (should (equal (caar sent) 'edit.apply))
      (should (= (plist-get (cdar sent) :len) 7)))))

(ert-deftest ebp-test-triggers-set-when-gate ()
  "SPEC 21.3 (amendments #75, #90): a `when' type must be advertised in
device.state_types; predicate-only time.window is always authorable; an
offending trigger is OMITTED per trigger — the rest are still sent — and
the omission is surfaced, never silent."
  (let* ((sent nil)
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts"))))
    (setf (ebp-client-device client) '(:state_types ["screen"]))
    (should (equal (ebp-client-device-state-types client) '("screen")))
    (cl-letf (((symbol-function 'ebp-client--request)
               (lambda (_c method params _cb &optional _t)
                 (push (cons method params) sent))))
      ;; Advertised and predicate-only types pass untouched.
      (ebp-client-triggers-set
       client (vector '(:id "t1" :type "battery.level"
                        :when [(:type "screen" :state "off")
                               (:type "time.window" :after "22:00")])))
      (should (= (length (plist-get (cdar sent) :triggers)) 1))
      ;; An unadvertised type omits ONLY that trigger; the rest still go,
      ;; and the omission reaches the caller.
      (let (told)
        (ebp-client-triggers-set
         client
         (vector '(:id "keep" :type "battery.level")
                 '(:id "drop" :type "battery.level" :when [(:type "power")]))
         :omitted-function (lambda (om) (setq told om)))
        (let ((triggers (plist-get (cdar sent) :triggers)))
          (should (= (length triggers) 1))
          (should (equal (plist-get (aref triggers 0) :id) "keep")))
        (should (= (length told) 1))
        (should (equal (plist-get (car told) :id) "drop")))
      ;; With no :omitted-function the omission still surfaces (a warning),
      ;; never a silent drop.
      (let ((warned nil))
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest _) (setq warned t))))
          (ebp-client-triggers-set
           client (vector '(:id "d" :type "battery.level"
                            :when [(:type "power")]))))
        (should warned)
        (should (= (length (plist-get (cdar sent) :triggers)) 0))))))

(ert-deftest ebp-test-forget-pairing ()
  "SPEC 9.1 / amendment #72: local pairing removal erases the receipt
store durably, clears in-memory receipts, and scrubs the token."
  (let* ((file (make-temp-file "ebp-test-receipts"))
         (client (ebp-client-create
                  :receipt-file file
                  :token "AAECAwQFBgcICQoLDA0ODw"
                  :pairing-id (make-string 32 ?1))))
    (should (ebp-client--receipt-commit client (make-string 32 ?c)))
    (should (= (hash-table-count (ebp-client-receipts client)) 1))
    (ebp-client-forget-pairing client)
    (should (eq (ebp-client-state client) 'closed))
    (should-not (file-exists-p file))
    (should (= (hash-table-count (ebp-client-receipts client)) 0))
    (should-not (plist-get (ebp-client-config client) :token))))

(ert-deftest ebp-test-edit-open-reconcile-seam ()
  "SPEC 19.3 / amendment #71: the :edit-open-function hook sees the seed
and the prior mirror text, after the mirror adopts the fresh session."
  (let* ((calls nil)
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts")
                  :edit-open-function
                  (lambda (c doc eid seed prior)
                    ;; The mirror already carries the seed: a reconciling
                    ;; edit.apply from here sees the new session/seq.
                    (push (list doc eid seed prior
                                (ebp-client-editor-text c doc eid))
                          calls)))))
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?0) :seq 0
                  :text "fresh seed" :cursor 0))
    (should (equal (car calls)
                   '("doc:1" "body" "fresh seed" nil "fresh seed")))
    ;; Reconnect: a second open for the same identity exposes the prior text.
    (ebp-client--handle-edit-open
     client (list :document "doc:1" :editor_id "body"
                  :session (make-string 32 ?1) :seq 0
                  :text "reconnect seed" :cursor 0))
    (should (equal (car calls)
                   '("doc:1" "body" "reconnect seed" "fresh seed"
                     "reconnect seed")))))

(ert-deftest ebp-test-after-replay-settled ()
  "The :after-replay-function seam fires only in READY with the backlog
drained (remaining 0)."
  (let* ((fired nil)
         (client (ebp-client-create
                  :receipt-file (make-temp-file "ebp-test-receipts")
                  :after-replay-function
                  (lambda (_c summary) (push summary fired)))))
    ;; Not ready: never fires.
    (setf (ebp-client-replay-summary client) '(:remaining 0))
    (ebp-client--replay-settled client)
    (should-not fired)
    ;; Ready with a backlog: not yet.
    (setf (ebp-client-state client) 'ready
          (ebp-client-replay-summary client) '(:remaining 2))
    (ebp-client--replay-settled client)
    (should-not fired)
    ;; Ready and drained: fires with the summary.
    (setf (ebp-client-replay-summary client) '(:remaining 0 :delivered 2))
    (ebp-client--replay-settled client)
    (should (equal fired '((:remaining 0 :delivered 2))))))

;;;; W10 — overload (SPEC 22.3, §24.6 item 14; docs/W10-overload-plan.md)

(ert-deftest ebp-test-sender-ceiling-refuses-and-recovers ()
  "SPEC 22.3 sender ceiling: hold at `ebp-overload-hold', sticky until
`ebp-overload-resume', refusal concluded locally/synchronously/once with
1401 and NOTHING on the wire, `queue.replay' exempt, decrement
exactly-once.  The library calls are stubbed so the ceiling logic is
what is under test; the loopback tests cover the live path."
  (let ((client (ebp-client-create :receipt-file (make-temp-file "ebp-ovl")))
        (sent '()) (refusals '()))
    (cl-letf (((symbol-function 'jsonrpc-async-request)
               (cl-function
                (lambda (_conn method _params &key success-fn
                               &allow-other-keys)
                  (push (cons method success-fn) sent))))
              ((symbol-function 'jsonrpc--next-request-id) (lambda (_c) 41)))
      ;; Fill to the hold mark; every one goes to the library.
      (dotimes (_ ebp-overload-hold)
        (should (ebp-client--request client 'surface.update '(:x 1) #'ignore)))
      (should (= (ebp-client-outstanding client) ebp-overload-hold))
      (should (= (length sent) ebp-overload-hold))
      ;; The next is refused: nil id, synchronous 1401, wire untouched.
      (should-not (ebp-client--request
                   client 'dialog.show '(:y 2)
                   (lambda (r e) (push (cons r e) refusals))))
      (should (equal refusals
                     '((nil . (:code 1401
                               :message "Outstanding requests exhausted"
                               :data (:kind "overloaded"))))))
      (should (= (length sent) ebp-overload-hold))
      ;; Sticky: one answer arriving does not lift the hold ...
      (funcall (cdr (car sent)) '(:ok t))
      (should (= (ebp-client-outstanding client) (1- ebp-overload-hold)))
      (should-not (ebp-client--request client 'dialog.show '(:y 3)
                                       (lambda (r e)
                                         (push (cons r e) refusals))))
      (should (= (length refusals) 2))
      ;; ... but queue.replay is exempt even while held (§22.3's
      ;; single-flight clause: refusing it forges blocked_by).
      (should (ebp-client--request client 'queue.replay '(:z 1) #'ignore))
      (should (= (length sent) (1+ ebp-overload-hold)))
      ;; Exactly-once: a duplicate conclusion cannot double-decrement.
      (funcall (cdr (car sent)) '(:ok t))
      (funcall (cdr (car sent)) '(:ok t))
      (should (= (ebp-client-outstanding client) (1- ebp-overload-hold)))
      ;; Drain to the resume mark: the hold lifts and requests flow.
      (while (> (ebp-client-outstanding client) ebp-overload-resume)
        (funcall (cdr (pop sent)) '(:ok t)))
      (should (ebp-client--request client 'dialog.show '(:y 4) #'ignore))
      (should-not (ebp-client-outstanding-held client)))))

(ert-deftest ebp-test-sender-ceiling-rolls-back-a-signalling-send ()
  "A send that SIGNALS must not burn an outstanding slot.
No continuation is registered and no callback ever runs, so without the
rollback the claim is permanent and repeated failures walk the client to
`ebp-overload-hold' on requests that never reached the wire.  The signal
must still escape: `jetpacs-shell-push' and the sections/results skins
all catch it by design.  Found by the app-tier verdict pass (B12)
against the W10 ceiling."
  (let ((client (ebp-client-create :receipt-file (make-temp-file "ebp-ovl"))))
    (cl-letf (((symbol-function 'jsonrpc--next-request-id) (lambda (_c) 7))
              ((symbol-function 'jsonrpc-async-request)
               (lambda (&rest _) (error "unserializable param"))))
      (dotimes (_ 50)
        (should-error (ebp-client--request client 'surface.update
                                           '(:bad "\xff") #'ignore)))
      (should (= (ebp-client-outstanding client) 0))
      (should-not (ebp-client-outstanding-held client)))
    ;; And a healthy request afterwards still claims and releases normally.
    (let (fire)
      (cl-letf (((symbol-function 'jsonrpc--next-request-id) (lambda (_c) 7))
                ((symbol-function 'jsonrpc-async-request)
                 (cl-function (lambda (_c _m _p &key success-fn
                                          &allow-other-keys)
                                (setq fire success-fn)))))
        (ebp-client--request client 'surface.update '(:ok t) #'ignore)
        (should (= (ebp-client-outstanding client) 1))
        (funcall fire '(:status "applied"))
        (should (= (ebp-client-outstanding client) 0))))))

(ert-deftest ebp-test-sender-ceiling-close-fails-locally ()
  "SPEC 22.3: on close, outstanding requests fail LOCALLY — jsonrpc's
sentinel errors every continuation, our callbacks conclude, the counter
returns to zero.  Live loopback; the companion swallows surface.update."
  (let ((concluded '()))
    (ebp-test--with-companion
        (server client
                (let ((kat (ebp-test--kat-script)))
                  (lambda (msg send)
                    ;; Handshake conforms; surface.update never answers.
                    (unless (equal (alist-get 'method msg) "surface.update")
                      (funcall kat msg send)))))
      (should (ebp-test--wait
               (lambda () (eq (ebp-client-state client) 'ready))))
      (dotimes (i 3)
        (ebp-client--request client 'surface.update (list :n i)
                             (lambda (_r e) (push e concluded))))
      (should (= (ebp-client-outstanding client) 3))
      ;; Kill OUR transport; the sentinel must conclude all three.
      (delete-process (ebp-client-process client))
      (should (ebp-test--wait (lambda () (= (length concluded) 3))))
      (should (= (ebp-client-outstanding client) 0))
      (should (cl-every (lambda (e) (plist-get e :code)) concluded)))))

(ert-deftest ebp-test-inbound-flood-bounded-in-order ()
  "§24.6 item 14, intent class: a one-blob flood of `state.changed' is
dispatched completely, exactly once, in wire order — the parsed queue
drains faster than it grows, which IS the bounded behavior; and the
reader is running (unpaused) when the storm has passed."
  (let ((got '()))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :after-ready
                 (lambda (send)
                   ;; A 400-notification burst; the loopback socket
                   ;; coalesces them into few large reads.
                   (dotimes (i 400)
                     (funcall send
                              (list :jsonrpc "2.0"
                                    :method "state.changed"
                                    :params (list :surface "app:main"
                                                  :revision_seen 1
                                                  :id "field"
                                                  :value i))))))
                :state-changed-function
                (lambda (_c _s _rev _id value) (push value got)))
      (should (ebp-test--wait (lambda () (= (length got) 400)) 15))
      (should (equal (nreverse got) (number-sequence 0 399)))
      (should-not (ebp-client-inbound-paused client))
      (should-not (ebp-client-overloaded client)))))

(ert-deftest ebp-test-inbound-pause-resume-and-in-send-guard ()
  "The backpressure lever against a REAL connection: high-water pauses
the reader (stop-process), the drain side resumes it at the low-water
mark, and the A8 §1.5 invariant holds — no pause is ever taken inside a
send, and any send resumes a paused reader first."
  (ebp-test--with-companion
      (server client (ebp-test--kat-script))
    (should (ebp-test--wait (lambda () (eq (ebp-client-state client) 'ready))))
    (let ((proc (ebp-client-process client)))
      ;; High-water with a synthetic backlog: the reader stops.
      (cl-letf (((symbol-function 'ebp-client--backlog)
                 (lambda (_c) ebp-overload-hold)))
        (ebp-client--inbound-check client))
      (should (ebp-client-inbound-paused client))
      (should (eq (process-status proc) 'stop))
      ;; Dispatch with the backlog still high: stays paused.
      (cl-letf (((symbol-function 'ebp-client--backlog)
                 (lambda (_c) (1+ ebp-overload-resume))))
        (ebp--with-dispatch client nil))
      (should (ebp-client-inbound-paused client))
      ;; Dispatch at the low-water mark: resumes.
      (cl-letf (((symbol-function 'ebp-client--backlog)
                 (lambda (_c) ebp-overload-resume)))
        (ebp--with-dispatch client nil))
      (should-not (ebp-client-inbound-paused client))
      (should (eq (process-status proc) 'open))
      ;; Inside a send, the pause is refused outright.
      (let ((ebp--in-send t))
        (cl-letf (((symbol-function 'ebp-client--backlog)
                   (lambda (_c) (* 2 ebp-overload-hold))))
          (ebp-client--inbound-check client)))
      (should-not (ebp-client-inbound-paused client))
      ;; A send through the connection resumes a paused reader FIRST.
      (setf (ebp-client-inbound-paused client) t)
      (stop-process proc)
      (ebp-client-notify client 'log.error '(:code 1400 :message "x"))
      (should-not (ebp-client-inbound-paused client))
      (should (eq (process-status proc) 'open)))))

(ert-deftest ebp-test-inbound-exhaustion-1401-then-close ()
  "SPEC 22.3 exhaustion: one `log.error' 1401 reaches the peer, the
connection closes, and the latch makes a second report impossible.
Driven twice — once via the backlog trigger, once via dispatch depth."
  ;; Backlog past EXHAUST (only reachable while sends kept pausing
  ;; forbidden): report + close.
  (ebp-test--with-companion
      (server client (ebp-test--kat-script))
    (should (ebp-test--wait (lambda () (eq (ebp-client-state client) 'ready))))
    (cl-letf (((symbol-function 'ebp-client--backlog)
               (lambda (_c) ebp-overload-exhaust)))
      (ebp-client--inbound-check client))
    (should (eq (ebp-client-state client) 'closed))
    (should (equal (car (ebp-client-close-reason client)) 'overloaded))
    (should (ebp-test--wait
             (lambda ()
               (cl-find-if
                (lambda (m) (and (equal (alist-get 'method m) "log.error")
                                 (eql (alist-get 'code (alist-get 'params m))
                                      1401)))
                (funcall (plist-get server :received))))))
    ;; The latch: a second trigger neither reports nor errors.
    (ebp-client--overload-close client 'again)
    (should (= 1 (cl-count-if
                  (lambda (m) (equal (alist-get 'method m) "log.error"))
                  (funcall (plist-get server :received))))))
  ;; Depth past the #124 bound at dispatch entry: same terminal shape.
  (ebp-test--with-companion
      (server client (ebp-test--kat-script))
    (should (ebp-test--wait (lambda () (eq (ebp-client-state client) 'ready))))
    (let ((ebp--dispatch-depth ebp-max-dispatch-depth))
      (should-error
       (ebp-client--notification-dispatcher client nil 'state.changed nil)))
    (should (eq (ebp-client-state client) 'closed))
    (should (equal (ebp-client-close-reason client)
                   '(overloaded dispatch-depth)))))

(ert-deftest ebp-test-ordered-stream-flood-in-order ()
  "§24.6 item 14, ordered class: a one-blob editor stream (open + 200
deltas) mirrors to exactly the in-order concatenation, with no resync —
no gap was ever observed, so none may be invented under load."
  (let ((final nil))
    (ebp-test--with-companion
        (server client
                (ebp-test--kat-script
                 :after-ready
                 (lambda (send)
                   (funcall send '(:jsonrpc "2.0" :method "edit.open"
                                   :params (:document "doc:w10" :editor_id "e"
                                            :session "S" :seq 0 :text ""
                                            :cursor 0)))
                   (dotimes (i 200)
                     (funcall send
                              (list :jsonrpc "2.0" :method "edit.delta"
                                    :params
                                    (list :document "doc:w10" :editor_id "e"
                                          :session "S" :seq (1+ i)
                                          :start i :del 0
                                          :text (format "%c" (+ ?a (% i 26)))
                                          :len (1+ i))))))))
      (should (ebp-test--wait
               (lambda ()
                 (let ((text (ebp-client-editor-text client "doc:w10" "e")))
                   (and text (= (length text) 200) (setq final text))))
               15))
      (should (equal final
                     (apply #'concat
                            (cl-loop for i below 200
                                     collect (format "%c" (+ ?a (% i 26)))))))
      ;; No resync was provoked: the stream had no gap.
      (should-not (cl-find-if
                   (lambda (m) (equal (alist-get 'method m) "edit.resync"))
                   (funcall (plist-get server :received)))))))

(provide 'ebp-wire-test)
;;; ebp-wire-test.el ends here
