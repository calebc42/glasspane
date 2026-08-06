;;; ebp-path.el --- The path sandbox: containment for a name a peer sent -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The containment guard every rung shares that opens a file some remote
;; peer named.  `ebp-' by the ratified rule (2026-08-06, bed8ef4):
;; `jetpacs-' names what cannot exist without Kotlin, Android, and
;; Compose; `ebp-' names what only ever touches the wire and Emacs.
;; Nothing here has ever touched the first list.  The whole vocabulary of
;; this file is file names, root sets, and `file-truename' — Emacs — and
;; the refusal it raises is a bare reason symbol precisely so that it can
;; be answered toward the wire without leaking a path.  It requires
;; `cl-lib' and nothing else.
;;
;; Three things live here and their ORDER is the design.  `ebp-local-paths'
;; drops remote names before anyone stats them, because for a remote name
;; the stat IS the connection.  `ebp-check-path' then resolves both sides
;; and compares path COMPONENTS, so neither a symlink nor a shared string
;; prefix can straddle the boundary.  `ebp-path-refused' carries the
;; reason and only the reason.

;;; Code:

(require 'cl-lib)

(define-error 'ebp-path-refused "ebp: path refused by policy")

(defun ebp-local-paths (paths)
  "PATHS with every remote name dropped, tested on the RAW strings.
The filter runs BEFORE any caller stats, truenames, or opens a member,
because for a remote name the stat IS the connection: `file-truename',
`file-directory-p' or `file-readable-p' on /ssh:host:… dials the host,
inside whatever extent the caller occupies.  `tramp-connection-timeout'
is 60 seconds and a dispatch extent has no business waiting on one.

Callers deriving a root or file set from user configuration MUST route
it through here first (JA-4 audit P1-7: the guard below inspected the
ref's own name correctly and then handed unfiltered configuration to
`file-directory-p', so one remote agenda entry dialled TRAMP on every
single resolve)."
  (delq nil (mapcar (lambda (p)
                      (and (stringp p) (not (string-empty-p p))
                           (not (file-remote-p p)) p))
                    paths)))

(cl-defun ebp-check-path (file roots &key (require 'readable))
  "FILE validated against ROOTS, returned as a truename, or signal.
Signals `ebp-path-refused' with a one-symbol data list — `not-absolute',
`remote', `no-roots', `outside-roots', `unreadable', `not-a-directory' or
`exists'.  The symbol travels alone ON PURPOSE: an error raised here is
answered toward the device, and a path in its data is a §23.1 leak
\(the application layer's error labeller prints symbols).

REQUIRE selects the existence test applied AFTER containment, which is
the only part that differs between callers:
  `readable'  (default) an existing readable file or directory;
  `directory' an accessible directory — the browse case;
  `absent'    a path that does NOT exist — a rename/create TARGET, whose
              parent must still be inside a root, which containment
              already established because `file-truename' resolves the
              existing prefix and keeps the new tail literal;
  nil         containment only.
Containment never varies: widening the sandbox is not something a caller
should be able to ask for by passing a flag.

Guard order is load-bearing and is the whole point of this function:

  1. absolute-string shape, on the raw argument;
  2. `file-remote-p' on the RAW name — first, see `ebp-local-paths';
  3. truename BOTH sides, so a symlink cannot straddle the boundary;
  4. containment by `file-in-directory-p', which compares path COMPONENTS
     — /home/u/org-evil does not sit under /home/u/org, which a string
     prefix test would admit;
  5. readability last, since it is the only stat that must touch the file.

ROOTS is the caller's allowlist; an EMPTY root set refuses everything and
says so distinctly (`no-roots'), because \"unconfigured\" and \"out of
policy\" are different conditions and only the second is the caller's
fault.  ROOTS is filtered and truenamed here — callers pass raw
configuration.

Promoted to the floor at JA-6: the org engine had the only copy, and the
files rung was about to grow a second one.  A guard that exists twice is
a guard that is correct once.

Promoted a SECOND time here, out of the floor entirely.  The floor is the
application's registry — owners, actions, surfaces, state — and this
function names none of those things; it reads strings and stats a
filesystem, which is Emacs, on behalf of a name that arrived over the
wire.  Living on the floor made every consumer of a sandbox take a
dependency on an application layer to get one.  The sandbox is nobody's
application: the engine and the application both require it now, and
neither one owns it."
  (unless (and (stringp file) (not (string-empty-p file))
               (file-name-absolute-p file))
    (signal 'ebp-path-refused (list 'not-absolute)))
  (when (file-remote-p file)
    (signal 'ebp-path-refused (list 'remote)))
  (let ((true (file-truename file))
        (dirs (delq nil (mapcar (lambda (d)
                                  (and (file-directory-p d) (file-truename d)))
                                (ebp-local-paths roots)))))
    (unless dirs
      (signal 'ebp-path-refused (list 'no-roots)))
    (unless (cl-some (lambda (root) (file-in-directory-p true root)) dirs)
      (signal 'ebp-path-refused (list 'outside-roots)))
    (pcase require
      ('readable (unless (file-readable-p true)
                   (signal 'ebp-path-refused (list 'unreadable))))
      ('directory (unless (file-accessible-directory-p true)
                    (signal 'ebp-path-refused (list 'not-a-directory))))
      ('absent (when (file-exists-p true)
                 (signal 'ebp-path-refused (list 'exists))))
      ('nil nil)
      (_ (error "ebp-check-path: unknown :require %S" require)))
    true))

(provide 'ebp-path)
;;; ebp-path.el ends here
