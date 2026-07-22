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
              (let ((want (cdr (assoc (alist-get 'expect_error fx)
                                      ebp-test--error-map))))
                (should (eq err want))))))))))

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
  "SPEC 7.2: string identifiers, 1..64 octets."
  (should (ebp-valid-request-id-p "r1"))
  (should (ebp-valid-request-id-p (make-string 64 ?a)))
  (should-not (ebp-valid-request-id-p (make-string 65 ?a)))
  (should-not (ebp-valid-request-id-p ""))
  (should-not (ebp-valid-request-id-p 7))
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

;;;; W3: client engine against a scripted companion (SPEC 9-10)

(defconst ebp-test--kat-token (ebp-decode-pairing-token "AAECAwQFBgcICQoLDA0ODw"))
(defconst ebp-test--kat-pid "101112131415161718191a1b1c1d1e1f")
(defconst ebp-test--kat-cn "202122232425262728292a2b2c2d2e2f")
(defconst ebp-test--kat-sn "303132333435363738393a3b3c3d3e3f")

(defun ebp-test--harness ()
  "Return (CLIENT . OUTBOX) where OUTBOX is a closure returning the list
of decoded outbound messages so far, in send order."
  (let* ((bytes "")
         (client (ebp-client-create
                  :client-name "test-client" :client-version "0.0.1"
                  :pairing-id ebp-test--kat-pid
                  :token ebp-test--kat-token
                  :wants '("theme")
                  :client-nonce ebp-test--kat-cn
                  :outbound-fn (lambda (b) (setq bytes (concat bytes b))))))
    (cons client
          (lambda () (ebp-decoder-feed (ebp-make-decoder) bytes)))))

(defun ebp-test--respond (client id result)
  "Feed CLIENT a framed success response for ID carrying RESULT."
  (ebp-client-feed client (ebp-encode-frame
                           (ebp--json-serialize
                            `(:jsonrpc "2.0" :id ,id :result ,result)))))

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

(defun ebp-test--run-handshake (client outbox)
  "Drive CLIENT through nonce and welcome; return the outbox messages."
  (ebp-client-start client)
  (ebp-test--respond client "c1" `(:server_nonce ,ebp-test--kat-sn))
  (ebp-test--respond client "c2" (ebp-test--welcome-result))
  (funcall outbox))

(ert-deftest ebp-test-client-handshake-to-ready ()
  "The full SPEC 10.3 barrier: hello, auth, replay, ready — in order,
with the KAT proof on the wire and READY only after the ready result."
  (pcase-let* ((`(,client . ,outbox) (ebp-test--harness))
               (ready-ran nil))
    (push (lambda (_c) (setq ready-ran t))
          (ebp-client-ready-functions client))
    (ebp-test--run-handshake client outbox)
    ;; Barrier order on the wire (SPEC 10.3): replay concluded before ready.
    (should (equal (mapcar (lambda (m) (alist-get 'method m)) (funcall outbox))
                   '("session.hello" "auth.response" "queue.replay")))
    (should (eq (ebp-client-state client) 'syncing))
    (should-not ready-ran)
    (ebp-test--respond client "c3"
                       '(:delivered 0 :rejected 0 :expired 0 :remaining 0
                         :blocked_by :null))
    (should (equal (alist-get 'method (car (last (funcall outbox))))
                   "session.ready"))
    (should (eq (ebp-client-state client) 'syncing))
    (ebp-test--respond client "c4" ebp--empty-object)
    (should (eq (ebp-client-state client) 'ready))
    (should ready-ran)
    ;; The auth request carried the exact KAT client proof.
    (let ((auth (nth 1 (funcall outbox))))
      (should (equal (alist-get 'client_proof (alist-get 'params auth))
                     (ebp-client-proof ebp-test--kat-token ebp-test--kat-pid
                                       ebp-test--kat-cn ebp-test--kat-sn))))
    ;; Welcome absorption (SPEC 10.3 steps 1-2).
    (should (equal (ebp-client-granted client) '("theme")))
    (should (= (alist-get 'max_frame_bytes (ebp-client-limits client))
               4194304))))

(ert-deftest ebp-test-client-rejects-bad-server-proof ()
  "SPEC 9.3: Emacs MUST verify server_proof before trusting the welcome."
  (pcase-let* ((`(,client . ,_outbox) (ebp-test--harness)))
    (ebp-client-start client)
    (ebp-test--respond client "c1" `(:server_nonce ,ebp-test--kat-sn))
    (ebp-test--respond client "c2"
                       (ebp-test--welcome-result
                        (ebp-client-proof ebp-test--kat-token ebp-test--kat-pid
                                          ebp-test--kat-cn ebp-test--kat-sn)))
    (should (eq (ebp-client-state client) 'closed))
    (should (equal (ebp-client-close-reason client) '(server-proof-invalid)))))

(ert-deftest ebp-test-client-rejects-incomplete-welcome ()
  "SPEC 10.2: the welcome MUST contain the required members."
  (pcase-let* ((`(,client . ,_outbox) (ebp-test--harness)))
    (ebp-client-start client)
    (ebp-test--respond client "c1" `(:server_nonce ,ebp-test--kat-sn))
    (ebp-test--respond client "c2" (ebp-test--welcome-result nil :limits))
    (should (eq (ebp-client-state client) 'closed))
    (should (equal (ebp-client-close-reason client) '(welcome-incomplete)))))

(ert-deftest ebp-test-client-answers-unknown-request ()
  "SPEC 7.3: an unknown request receives -32601."
  (pcase-let* ((`(,client . ,outbox) (ebp-test--harness)))
    (ebp-test--run-handshake client outbox)
    (ebp-client-feed client
                     (ebp-encode-frame
                      (ebp--json-serialize
                       `(:jsonrpc "2.0" :id "srv1" :method "no.such"
                         :params ,ebp--empty-object))))
    (let ((last-msg (car (last (funcall outbox)))))
      (should (equal (alist-get 'id last-msg) "srv1"))
      (should (= (alist-get 'code (alist-get 'error last-msg)) -32601)))
    ;; Still alive: unknown methods never kill the session.
    (should-not (eq (ebp-client-state client) 'closed))))

(ert-deftest ebp-test-client-ignores-unknown-notification-and-id ()
  (pcase-let* ((`(,client . ,outbox) (ebp-test--harness)))
    (ebp-test--run-handshake client outbox)
    (let ((before (length (funcall outbox))))
      (ebp-client-feed client
                       (ebp-encode-frame
                        (ebp--json-serialize
                         `(:jsonrpc "2.0" :method "no.such"
                           :params ,ebp--empty-object))))
      (ebp-test--respond client "never-sent" ebp--empty-object)
      ;; SPEC 7.3: both are logged and ignored, nothing emitted.
      (should (= (length (funcall outbox)) before))
      (should-not (eq (ebp-client-state client) 'closed)))))

(ert-deftest ebp-test-client-closes-on-frame-error ()
  "SPEC 6.2: framing failures are transport-fatal."
  (pcase-let* ((`(,client . ,_outbox) (ebp-test--harness)))
    (ebp-client-start client)
    (ebp-client-feed client "X-No-Length: 1\r\n\r\n")
    (should (eq (ebp-client-state client) 'closed))
    (should (eq (car (ebp-client-close-reason client)) 'frame-error))))

(ert-deftest ebp-test-client-handler-registry ()
  "Registered handlers receive inbound traffic; the registry mechanism
is ebp.el's, its content the application's (REWRITE-PLAN boundary)."
  (pcase-let* ((`(,client . ,outbox) (ebp-test--harness))
               (seen nil))
    (ebp-test--run-handshake client outbox)
    (ebp-client-register-handler
     client "event.action"
     (lambda (c id params)
       (setq seen (alist-get 'action params))
       (ebp-client--send c (ebp-result-response id '(:status "accepted")))))
    (ebp-client-feed client
                     (ebp-encode-frame
                      (ebp--json-serialize
                       '(:jsonrpc "2.0" :id "ev1" :method "event.action"
                         :params (:event_id "00112233445566778899aabbccddeeff"
                                  :action "demo.tap"
                                  :occurred_at_ms 1784700000000)))))
    (should (equal seen "demo.tap"))
    (let ((last-msg (car (last (funcall outbox)))))
      (should (equal (alist-get 'id last-msg) "ev1"))
      (should (equal (alist-get 'status (alist-get 'result last-msg))
                     "accepted")))))

;;;; W4: the surface push path (SPEC 13.1-13.3, client half)

(defun ebp-test--run-handshake-with-floors (client outbox)
  "Handshake with a welcome reporting app:main at revision 41 (present)
and a tombstone for app:old at 9."
  (ebp-client-start client)
  (ebp-test--respond client "c1" `(:server_nonce ,ebp-test--kat-sn))
  (ebp-test--respond
   client "c2"
   (ebp-test--welcome-result nil nil
                             '(:app:main (:revision 41 :present t)
                               :app:old (:revision 9 :present :false))))
  (ebp-test--respond client "c3"
                     '(:delivered 0 :rejected 0 :expired 0 :remaining 0
                       :blocked_by :null))
  (ebp-test--respond client "c4" ebp--empty-object)
  (funcall outbox))

(ert-deftest ebp-test-client-surface-revisions-above-floors ()
  "SPEC 10.3 step 3 + 13.1: pushes use revisions above the reported
floors — including tombstone floors — and absorb stale results."
  (pcase-let* ((`(,client . ,outbox) (ebp-test--harness)))
    (ebp-test--run-handshake-with-floors client outbox)
    (should (eq (ebp-client-state client) 'ready))
    ;; First push climbs past the welcome floor.
    (should (= (ebp-client-surface-update client "app:main"
                                          '(:t "text" :text "hi"))
               42))
    (let ((update (car (last (funcall outbox)))))
      (should (equal (alist-get 'method update) "surface.update"))
      (should (= (alist-get 'revision (alist-get 'params update)) 42)))
    (ebp-test--respond client "c5" '(:status "applied" :revision 42 :present t))
    ;; The tombstoned surface's floor is honored on reuse.
    (should (= (ebp-client-surface-update client "app:old"
                                          '(:t "text" :text "back"))
               10))
    ;; A second push while one is in flight still gets a newer revision.
    (should (= (ebp-client-surface-update client "app:main"
                                          '(:t "text" :text "again"))
               43))
    ;; A stale result absorbs the Companion's higher floor (SPEC 13.2).
    (ebp-test--respond client "c7" '(:status "stale" :revision 50 :present t))
    (should (= (ebp-client-surface-update client "app:main"
                                          '(:t "text" :text "newest"))
               51))))

(ert-deftest ebp-test-client-surface-remove-is-revisioned ()
  "SPEC 13.3: removal claims a fresh revision like any mutation."
  (pcase-let* ((`(,client . ,outbox) (ebp-test--harness))
               (status-seen nil))
    (ebp-test--run-handshake-with-floors client outbox)
    (should (= (ebp-client-surface-remove
                client "app:main"
                :callback (lambda (status _err) (setq status-seen status)))
               42))
    (let ((remove (car (last (funcall outbox)))))
      (should (equal (alist-get 'method remove) "surface.remove"))
      (should (= (alist-get 'revision (alist-get 'params remove)) 42))
      (should-not (assq 'spec (alist-get 'params remove))))
    (ebp-test--respond client "c5" '(:status "applied" :revision 42 :present :false))
    (should (equal status-seen "applied"))
    ;; Recreating the surface climbs past the tombstone.
    (should (= (ebp-client-surface-update client "app:main"
                                          '(:t "text" :text "reborn"))
               43))))

(provide 'ebp-wire-test)
;;; ebp-wire-test.el ends here
