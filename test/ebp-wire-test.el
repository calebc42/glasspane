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

(provide 'ebp-wire-test)
;;; ebp-wire-test.el ends here
