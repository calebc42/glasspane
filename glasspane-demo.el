;;; glasspane-demo.el --- Guided-tour demo files for the mobile IDE -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Writes a set of small tour files into `glasspane-demo-directory' so the
;; phone editor's IDE features can be demoed on demand: completion,
;; eldoc signatures, and flymake squiggles today; each file also marks
;; what upgrades once the eglot phase lands.  A companion org corpus
;; (`glasspane-demo-setup-org') writes a de-personalized, namespaced set of
;; files exercising the current Glasspane surfaces and PARA model: TODO-stage
;; Projects, native Area-group intersections, Resources, sibling Archives,
;; every core Org parser form, dense backlinks, habits, and review cards.
;;
;; The files ship *inside the bundle* rather than as repo files because
;; Emacs's home on Android is app-private storage — adb can't push into
;; it, but Emacs itself can write there.  Run `M-x glasspane-demo-setup' for
;; the editor tour or `M-x glasspane-demo-setup-org' for the Org corpus; the
;; same commands are confirmed buttons in Glasspane Settings.  Setup always
;; overwrites its own namespaced files, so a mangled demo resets to pristine
;; without replacing ordinary names such as inbox.org or project.org.
;;
;; Ported against v1 with nothing on the retirement list landing here
;; (docs/PLAN-glasspane-app.md G8: the seeder KEEPS — it is the only
;; way to place files in the app-private Android home, and the corpus
;; doubles as the device-smoke fixture set).  The rewrites: the two
;; verbs answer the SPEC 14.4 statuses, a failed write notifying then
;; \\='rejected (S4); the trailing inline push rides the deferred
;; continuation (D2); the `fboundp' guards on shell notify/push are
;; dropped (T5, hard deps); `jetpacs-org-cache-invalidate' is
;; `ebp-org-cache-invalidate' (T1).  NEW v3 constraint (G8): both
;; write targets derive from owner configuration — the corpus directly
;; from `org-directory', the onboarding-selected Org root, and the tour
;; directory from `jetpacs-files-default-dir' inside `jetpacs-files-roots'
;; — never from hardcoded paths.

;;; Code:

(require 'org)
(require 'org-inlinetask)
(require 'subr-x)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-files)
(require 'jetpacs-org-settings nil t)
(require 'ebp-org)
(require 'glasspane-srs)               ; SRS registration in the knowledge file

(defvar glasspane-area-tag-group)
(declare-function jetpacs-org-settings-set-tag-group-members
                  "jetpacs-org-settings" (group members &optional variable))
(declare-function vulpea-db-sync-full-scan "ext:vulpea-db" (&optional arg))

(defcustom glasspane-demo-directory
  (expand-file-name "glasspane-demo" jetpacs-files-default-dir)
  "Directory `glasspane-demo-setup' writes the tour files into.
Must lie within `jetpacs-files-roots' to be reachable from the phone's
Files browser.  The default derives from `jetpacs-files-default-dir' —
the directory the Files view lands in, itself bound inside the roots —
so the tour appears exactly where the browser opens."
  :type 'directory :group 'jetpacs)

(defconst glasspane-demo--files
  `(("demo.el" . "\
;;; demo.el --- Glasspane mobile IDE tour -*- lexical-binding: t; -*-

;; Welcome!  This buffer is live-synced to your Emacs while you type.
;; Everything below runs against the real Emacs image on this device.

;; ── 1. Completion ────────────────────────────────────────────────
;; On the blank line below, type   (buffer-sub   and pause.
;; Chips appear above the keyboard; tap one to accept — mobile TAB.


;; ── 2. Signatures (eldoc) ────────────────────────────────────────
;; Tap to place the cursor inside the `concat' call below and pause.
;; Its signature appears in the doc line above the keyboard.

(defun demo-greet (name)
  \"Return a friendly greeting for NAME.\"
  (concat \"Hello, \" name \"!\"))

;; ── 3. Diagnostics (flymake) ─────────────────────────────────────
;; A few seconds after this file opens, the real byte-compiler flags
;; the two functions below with squiggles.  Tap inside one to read
;; its message in the doc line.

(defun demo-unused (thing)
  \"THING is never used, and the byte-compiler notices.\"
  42)

(defun demo-wrong-arity ()
  \"Calls `demo-greet' with one argument too many.\"
  (demo-greet \"world\" 'oops))

;; ── 4. Break something yourself ──────────────────────────────────
;; Delete the closing paren of any defun above and pause: a squiggle
;; appears.  Undo, pause, and it clears.

(provide 'demo)
;;; demo.el ends here
")
    ("demo.py" . "\
\"\"\"Glasspane mobile IDE tour - Python.

With pylsp installed in Termux (pip install python-lsp-server) and
the eglot bridge on, this file gets REAL language-server completion,
hover, and diagnostics.  Without a server it degrades gracefully to
same-buffer word completion.
\"\"\"


def fibonacci(n: int) -> int:
    \"\"\"Return the n-th Fibonacci number (naive on purpose).\"\"\"
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)


def fibonacci_sequence(count: int) -> list[int]:
    \"\"\"Return the first COUNT Fibonacci numbers.\"\"\"
    return [fibonacci(i) for i in range(count)]


# 1. Completion: on the line below, type   fib   and pause.
#    With pylsp: type   fibonacci_sequence(10).   for list methods.


# 2. Diagnostics (needs pyflakes: pip install pyflakes in Termux).
#    Both lines below earn squiggles from the server:
import os  # <- 'os' imported but unused


def uses_an_undefined_name():
    return undefined_name  # <- undefined name

if __name__ == \"__main__\":
    print(fibonacci_sequence(10))
")
    ("demo.sh" . "\
#!/data/data/com.termux/files/usr/bin/bash
# Glasspane mobile IDE tour - Shell.
#
# The most on-brand language here: sh-mode is built into Emacs, and
# bash-language-server installs straight into Termux
# (npm install -g bash-language-server) for full LSP via eglot.
# Without it: same-buffer word completion still works.

greet_user() {
    local name=\"$1\"
    echo \"Hello, ${name}!\"
}

count_greetings() {
    local total=\"$1\"
    for i in $(seq 1 \"$total\"); do
        greet_user \"friend #$i\"
    done
}

# 1. Completion: on the line below, type   gre   and pause.


count_greetings 3
")
    ("demo.c" . "\
/* Glasspane mobile IDE tour - C.
 *
 * Tree-sitter: with the c grammar installed and c-mode remapped to
 * c-ts-mode in your init, this file's colors come from tree-sitter,
 * pushed by Emacs (fontify.show) in your real theme.
 *
 * LSP: with clangd on the exec-path (Termux), eglot adds completion,
 * hover, and diagnostics. Without it: word completion still works.
 */

#include <stdio.h>

static long fibonacci(int n) {
    return n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2);
}

static void print_sequence(int count) {
    for (int i = 0; i < count; i++) {
        printf(\"%ld\\n\", fibonacci(i));
    }
}

/* 1. Completion: on the line below, type   fib   and pause.
 * 2. With clangd: add an undefined call like  missing();  inside
 *    main and pause for the squiggle. */


int main(void) {
    print_sequence(10);
    return 0;
}
")
    ("demo.org" . "\
#+title: Glasspane mobile IDE tour — Org

This file opens in the foldable reader; toggle to the raw editor
to try the features below.

* What works in org today
- Word completion from this buffer: type =comp= in the scratch
  section and pause.
- The org formatting toolbar sits under the editor.

* TODO Try tag completion                                    :server:
If your init opts =my/org-tag-completion= into shadow buffers via
=ebp-complete-shadow-setup-hook=, typing =:ser= at the end of a
headline completes your =:server:= tag from the phone.

* Scratch space
Type here — completion offers words already in this file, like
completion or formatting or headline.
"))
  "Alist of (FILENAME . CONTENT) written by `glasspane-demo-setup'.")

;; ─── Demo org corpus ─────────────────────────────────────────────────────────
;; A compact, de-personalized Org vault covering the complete core parser
;; vocabulary plus the phone's native tables, Babel, LaTeX, drawers,
;; footnotes, timestamps, Area intersections, sibling Archive, SRS cards,
;; and a balanced many-to-many ID graph.  Written into `org-directory' by
;; `glasspane-demo-setup-org' — same ship-inside-the-bundle rationale as
;; the tour files above.

(defconst glasspane-demo--org-file-prefix "glasspane-demo-"
  "Prefix shared by every resettable Org fixture file.
This is a safety boundary, not merely presentation: the setup command refuses
any corpus entry that could collide with an ordinary vault filename.")

(defconst glasspane-demo--retired-org-files
  '("glasspane-demo-guide.org"
    "glasspane-demo-health.org"
    "glasspane-demo-inbox.org"
    "glasspane-demo-projects.org"
    "glasspane-demo-notes.org"
    "glasspane-demo-quotes.org"
    "glasspane-demo-trackers.org"
    "glasspane-demo-flashcards.org"
    "glasspane-demo-projects.org_archive"
    "glasspane-demo-health.org_archive")
  "Exact generated filenames retired by the consolidated demo corpus.
The setup command may remove only these names and current corpus names; it
never treats the shared prefix as a deletion glob.")

(defconst glasspane-demo--org-files
  '(("glasspane-demo-hub.org" . "\
:PROPERTIES:
:ID:       25f40bb1-b008-46bd-bf12-5ad72456bb68
:END:
#+TITLE: Glasspane Demo Hub
#+SUBTITLE: A compact, connected Org vault
#+AUTHOR: Jetpacs
#+LANGUAGE: en
#+STARTUP: overview
#+OPTIONS: toc:2 num:nil
#+TODO: TODO(t) NEXT(n) WAITING(w@/!) IDEA(i) | DONE(d!) CANCELLED(c@)
#+TAGS: [ Area : House Auto Bills Work Health Learning Digital ]
#+FILETAGS: :demo:
#+PROPERTY: header-args :results replace
#+MACRO: product Glasspane
#+LINK: handbook https://orgmode.org/manual/%s
#+BIBLIOGRAPHY: references.bib

This five-file corpus is safe to reset.  It concentrates native Org syntax
and a deliberately dense note graph so {{{product}}} can exercise rendering,
navigation, Agenda, Projects, Areas, Resources, Archive, Review, and Vulpea.

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb69][Start here]] · [[id:933b2dfe-0b63-46ad-a4c4-6bfa8a847b2c][Offline queue soak]] · [[id:6c4b91a5-b4f6-43ea-8ad9-56d1ac8e8e03][Insurance claim]] · [[id:b19f4e73-2c60-4585-8aa1-64f0d3b7e2c9][Mass–energy card]]

* Start here                                                   :Learning:Digital:
:PROPERTIES:
:ID:       25f40bb1-b008-46bd-bf12-5ad72456bb69
:AREA:     Learning
:END:
PARA here follows Glasspane's native model:
- *Projects* are headings with an Org TODO keyword; no role tag is required.
- *Areas* are members of the non-exclusive =Area= tag group.  Native
  inheritance permits a note to belong to several Areas.
- *Resources* are the live Org files exposed through Files.
- *Archive* discovers ordinary sibling =.org_archive= files.

Run =M-x glasspane-demo-setup-org=, or use Settings → Glasspane → Demo
Content, whenever you want a pristine copy.

Connections: [[id:e372b40c-f1fe-490a-9832-3b517af0309c][Agenda inbox]] · [[id:71a8da2a-c295-4b30-807b-bb845bf72fd7][Graph browser]] · [[id:68fbf216-0000-41f1-b570-2b52ed092d14][HEPA filter]] · [[id:e4a8c1f6-97b2-4d3e-8c05-1f6a9d24b380][Computer bug card]]

* NEXT Triage the demo inbox                               :Work:Digital:
SCHEDULED: <2026-07-06 Mon>
:PROPERTIES:
:ID:       e372b40c-f1fe-490a-9832-3b517af0309c
:CATEGORY: Demo Inbox
:Effort:   20min
:END:
- [X] Open Agenda
- [ ] Reschedule an overdue item
- [ ] Open a linked note
- [ ] Inspect an Area intersection

Connections: [[id:a0a70496-49c8-475d-bbc6-b507e8c43d82][Org feature lab]] · [[id:86b18efc-f950-4c22-b006-5af19d0e1a74][Home server]] · [[id:2bf199b2-ab05-430d-a48c-81550252f6c3][Yoga challenge]] · [[id:ba4b6d51-efe5-44b7-a702-a302d5c3e27d][Knowledge map]]

* Org feature lab                                           :Learning:Digital:
:PROPERTIES:
:ID:       a0a70496-49c8-475d-bbc6-b507e8c43d82
:Effort:   30min
:OWNER:    Demo
:END:
:LOGBOOK:
CLOCK: [2026-07-03 Fri 08:20]--[2026-07-03 Fri 08:34] =>  0:14
:END:
This paragraph has *bold*, /italic/, _underlined_, +retired+, ~code~, and
=verbatim= text; H_{2}O and E=mc^{2}; the entity \\alpha; the fragment
\\(e^{i\\pi}+1=0\\); an export snippet @@html:<mark>native export</mark>@@;
inline source src_emacs-lisp{(+ 2 3)}; and an inline call call_double(n=21).

A hard line break follows this sentence.\\\\
This line resumes after it.  The macro expands to {{{product}}}.
A citation is parser-visible [cite/text:@lamport1978; @kleppmann2017, pp. 151--160].
The radio target <<<latency budget>>> makes later mentions of latency budget
addressable, while <<feature-anchor>> is a normal target.  Follow the
[[feature-anchor][fuzzy target]], [[file:glasspane-demo-knowledge.org::*Babel playground][file link]],
[[attachment:diagram.png][attachment]], [[https://orgmode.org][web link]], or
[[handbook:Markup-for-Rich-Contents][custom handbook link]].  See also
the coverage footnote[fn:coverage].

1. Ordered item
2. Another ordered item

- Unordered item
- Nested checklist [1/2]
  - [X] parsed
  - [ ] rendered

- term :: A descriptive-list term.
- facet :: One note may participate in several contexts.

#+CAPTION: Standalone remote image with alt text
#+ATTR_ORG: :width 640
[[https://picsum.photos/seed/glasspane-org/640/320.jpg]]

#+NAME: feature-matrix
| <18>               | <12>       | <24>                    |
| Feature            | State      | Surface                 |
|--------------------+------------+-------------------------|
| Dense ID links     | ready      | Vulpea backlinks        |
| Native TODO stages | ready      | Agenda and Projects     |
| Org parser forms   | ready      | Reader and raw editor   |
#+TBLFM: $2='(if (string-empty-p $1) \"missing\" \"ready\")

#+NAME: double
#+begin_src emacs-lisp :var n=4 :results value
(defun double (n) (* 2 n))
(double n)
#+end_src

#+RESULTS: double
: 8

#+call: double(n=5)

#+begin_src python :results value
sum(range(5))
#+end_src

#+RESULTS:
: 10

#+begin_quote
Org remains the source of truth; the phone presents its structure.
#+end_quote

#+begin_verse
One graph, many paths;
one note, many contexts.
#+end_verse

#+begin_center
Centered text exercises a dedicated block element.
#+end_center

#+begin_example
Literal examples keep *markup* and [[links]] untouched.
#+end_example

#+begin_details
Unknown affiliated block names become special blocks.
#+end_details

#+begin_comment
This whole block is intentionally hidden from normal export.
#+end_comment

#+begin_export html
<aside>Export-only demonstration</aside>
#+end_export

#+BEGIN: clocktable :scope file
#+END:

: Fixed-width content keeps spacing.
: second column -> aligned

# A standalone Org comment is an element too.
%%(org-anniversary 2024 7 6)

-----

\\begin{equation}
\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}
\\end{equation}

*************** TODO Inline checkpoint                             :Digital:
SCHEDULED: <2026-07-06 Mon>
A fifteen-star heading is an inlinetask when Org's extension is loaded.
*************** END

[fn:coverage] Footnote definitions and references are both represented.

Connections: [[id:68fbf216-c578-41f1-b570-2b52ed092d99][Capture and refile]] · [[id:eda8dcb1-0000-400a-b713-25b73941bcaf][Release notes]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc6][Life dashboard]] · [[id:5359bbea-6de3-4aba-bc86-fb46122005d3][Research notes]]

* TODO Capture and refile three loose notes                    :Learning:
SCHEDULED: <2026-07-07 Tue>
:PROPERTIES:
:ID:       68fbf216-c578-41f1-b570-2b52ed092d99
:END:
Capture stays the shared FAB; refile remains ordinary Org structure.

Connections: [[id:cff8c2b4-da5a-46c1-aab4-9661c6e65368][Weekly review]] · [[id:f95e563c-62e9-4c8a-bff6-eef9194f9660][Work map]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc7][Canyon hike]] · [[id:e372b40c-f1fe-490a-9832-3b517af0309d][Babel playground]]

* WAITING Run the weekly review                              :Learning:Digital:
SCHEDULED: <2026-07-13 Mon +1w>
:PROPERTIES:
:ID:       cff8c2b4-da5a-46c1-aab4-9661c6e65368
:END:
Review the TODO stages, Area facets, sibling Archive, and backlink fan-in.

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb68][Demo hub]] · [[id:9bfcf1a9-b6bb-48fd-9b21-898804c6036e][Companion beta]] · [[id:d825ffc9-1160-49cc-b2d0-113c7436deb7][Groceries]] · [[id:7c2e91d4-5a38-4f61-9b0e-3d84a2c6f106][Gaussian card]]
")
    ("glasspane-demo-work.org" . "\
:PROPERTIES:
:ID:       f95e563c-62e9-4c8a-bff6-eef9194f9660
:AREA:     Work
:END:
#+TITLE: Work & Engineering
#+STARTUP: overview
#+TODO: TODO NEXT WAITING IDEA | DONE CANCELLED
#+TAGS: [ Area : House Auto Bills Work Health Learning Digital ]
#+FILETAGS: :Work:Digital:

Every TODO heading below is a Project because of its workflow state, not a tag.
The file-level =AREA= declaration makes this file the Work Area note.

Connections: [[id:e372b40c-f1fe-490a-9832-3b517af0309c][Agenda inbox]] · [[id:9bfcf1a9-b6bb-48fd-9b21-898804c6036e][Companion beta]] · [[id:68fbf216-0000-41f1-b570-2b52ed092d14][HEPA filter]] · [[id:7c2e91d4-5a38-4f61-9b0e-3d84a2c6f106][Gaussian card]]

* NEXT Ship the companion beta                           :Work:Digital:software:
SCHEDULED: <2026-07-06 Mon> DEADLINE: <2026-07-12 Sun>
:PROPERTIES:
:ID:       9bfcf1a9-b6bb-48fd-9b21-898804c6036e
:Effort:   6h
:END:
:LOGBOOK:
CLOCK: [2026-07-02 Thu 09:00]--[2026-07-02 Thu 10:21] =>  1:21
:END:
- [X] Foldable reader
- [X] Offline action receipts
- [ ] Tablet layout
- [ ] Device smoke

Connections: [[id:a0a70496-49c8-475d-bbc6-b507e8c43d82][Feature lab]] · [[id:933b2dfe-0b63-46ad-a4c4-6bfa8a847b2c][Offline queue soak]] · [[id:2bf199b2-ab05-430d-a48c-81550252f6c3][Yoga challenge]] · [[id:b19f4e73-2c60-4585-8aa1-64f0d3b7e2c9][Mass–energy card]]

* WAITING Soak the offline queue [2/4]                   :Work:Digital:reliability:
SCHEDULED: <2026-07-05 Sun> DEADLINE: <2026-07-09 Thu>
:PROPERTIES:
:ID:       933b2dfe-0b63-46ad-a4c4-6bfa8a847b2c
:Effort:   2h
:END:
- [X] Airplane-mode acceptance
- [X] Reconnect replay
- [ ] Process-death replay
- [ ] Duplicate-event proof

Connections: [[id:68fbf216-c578-41f1-b570-2b52ed092d99][Capture and refile]] · [[id:71a8da2a-c295-4b30-807b-bb845bf72fd7][Graph browser]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc6][Life dashboard]] · [[id:e4a8c1f6-97b2-4d3e-8c05-1f6a9d24b380][Computer bug card]]

* IDEA Prototype a linked graph browser                    :Work:Digital:Learning:
:PROPERTIES:
:ID:       71a8da2a-c295-4b30-807b-bb845bf72fd7
:END:
Render backlinks, outgoing references, and shared neighbors without assuming
one folder owns a note.

Connections: [[id:cff8c2b4-da5a-46c1-aab4-9661c6e65368][Weekly review]] · [[id:86b18efc-f950-4c22-b006-5af19d0e1a74][Home server]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc7][Canyon hike]] · [[id:ba4b6d51-efe5-44b7-a702-a302d5c3e27d][Knowledge map]]

* TODO Harden the home server                         :House:Bills:Digital:
SCHEDULED: <2026-07-10 Fri>
:PROPERTIES:
:ID:       86b18efc-f950-4c22-b006-5af19d0e1a74
:CATEGORY: Home server
:END:
#+begin_src sh :results verbatim
df -h | head -3
#+end_src

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb68][Demo hub]] · [[id:eda8dcb1-0000-400a-b713-25b73941bcaf][Release notes]] · [[id:d825ffc9-1160-49cc-b2d0-113c7436deb7][Groceries]] · [[id:5359bbea-6de3-4aba-bc86-fb46122005d3][Research notes]]

* DONE Publish the release notes                         :Work:Learning:writing:
CLOSED: [2026-07-03 Fri 16:45]
:PROPERTIES:
:ID:       eda8dcb1-0000-400a-b713-25b73941bcaf
:END:
The release notes point readers back to the living project documents.

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb69][Start here]] · [[id:f95e563c-62e9-4c8a-bff6-eef9194f9660][Work map]] · [[id:6c4b91a5-b4f6-43ea-8ad9-56d1ac8e8e03][Insurance claim]] · [[id:e372b40c-f1fe-490a-9832-3b517af0309d][Babel playground]]

* CANCELLED Retire the duplicate navigation spike                   :Work:
CLOSED: [2026-07-01 Wed 11:00]
The experiment is retained in the live file so every configured workflow
stage remains available to the Projects filter.
")
    ("glasspane-demo-life.org" . "\
:PROPERTIES:
:ID:       8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc6
:END:
#+TITLE: Life & Operations
#+STARTUP: overview
#+TODO: TODO NEXT WAITING | DONE CANCELLED
#+TAGS: [ Area : House Auto Bills Work Health Learning Digital ]
#+FILETAGS: :demo:

Area membership comes from the named tag group.  The headings below declare
Health, House, Auto, and Bills while retaining ordinary many-to-many tags.

Connections: [[id:a0a70496-49c8-475d-bbc6-b507e8c43d82][Feature lab]] · [[id:86b18efc-f950-4c22-b006-5af19d0e1a74][Home server]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc7][Canyon hike]] · [[id:e372b40c-f1fe-490a-9832-3b517af0309d][Babel playground]]

* NEXT Train for a rim-to-rim canyon hike                   :Health:fitness:
SCHEDULED: <2026-07-06 Mon> DEADLINE: <2026-08-15 Sat>
:PROPERTIES:
:ID:       8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc7
:AREA:     Health
:Effort:   8h
:END:
Trip window: <2026-08-15 Sat>--<2026-08-17 Mon>.
Current maximum is /about twelve miles/.

Connections: [[id:68fbf216-c578-41f1-b570-2b52ed092d99][Capture and refile]] · [[id:eda8dcb1-0000-400a-b713-25b73941bcaf][Release notes]] · [[id:d825ffc9-1160-49cc-b2d0-113c7436deb7][Groceries]] · [[id:7c2e91d4-5a38-4f61-9b0e-3d84a2c6f106][Gaussian card]]

* TODO Weekly grocery run                              :House:Bills:errand:
SCHEDULED: <2026-07-07 Tue +1w>
:PROPERTIES:
:ID:       d825ffc9-1160-49cc-b2d0-113c7436deb7
:AREA:     House
:LAST_REPEAT: [2026-06-30 Tue 18:37]
:END:
- [ ] Vegetables
- [ ] Coffee
- [ ] Trail snacks

Connections: [[id:cff8c2b4-da5a-46c1-aab4-9661c6e65368][Weekly review]] · [[id:f95e563c-62e9-4c8a-bff6-eef9194f9660][Work map]] · [[id:6c4b91a5-b4f6-43ea-8ad9-56d1ac8e8e03][Insurance claim]] · [[id:b19f4e73-2c60-4585-8aa1-64f0d3b7e2c9][Mass–energy card]]

* WAITING Call the insurance company                    :Auto:Bills:phone:
SCHEDULED: <2026-07-06 Mon>
:PROPERTIES:
:ID:       6c4b91a5-b4f6-43ea-8ad9-56d1ac8e8e03
:AREA:     Auto
:END:
Claim reference: =GP-2048=.

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb68][Demo hub]] · [[id:9bfcf1a9-b6bb-48fd-9b21-898804c6036e][Companion beta]] · [[id:68fbf216-0000-41f1-b570-2b52ed092d14][HEPA filter]] · [[id:e4a8c1f6-97b2-4d3e-8c05-1f6a9d24b380][Computer bug card]]

* TODO Order a replacement HEPA filter               :House:Health:Bills:
SCHEDULED: <2026-07-05 Sun>
:PROPERTIES:
:ID:       68fbf216-0000-41f1-b570-2b52ed092d14
:AREA:     Bills
:END:
Budget: $45.  This single task belongs to three Areas without a role tag.

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb69][Start here]] · [[id:933b2dfe-0b63-46ad-a4c4-6bfa8a847b2c][Offline queue soak]] · [[id:2bf199b2-ab05-430d-a48c-81550252f6c3][Yoga challenge]] · [[id:ba4b6d51-efe5-44b7-a702-a302d5c3e27d][Knowledge map]]

* DONE Complete a thirty-day yoga challenge                    :Health:goal:
CLOSED: [2026-06-26 Fri 18:00]
:PROPERTIES:
:ID:       2bf199b2-ab05-430d-a48c-81550252f6c3
:END:
Measurement window: [2026-06-20 Sat]--[2026-06-27 Sat].

| Date             | Resting bpm |
|------------------+-------------|
| [2026-06-20 Sat] |          58 |
| [2026-06-27 Sat] |          54 |

Connections: [[id:e372b40c-f1fe-490a-9832-3b517af0309c][Agenda inbox]] · [[id:71a8da2a-c295-4b30-807b-bb845bf72fd7][Graph browser]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc6][Life dashboard]] · [[id:5359bbea-6de3-4aba-bc86-fb46122005d3][Research notes]]
")
    ("glasspane-demo-knowledge.org" . "\
:PROPERTIES:
:ID:       ba4b6d51-efe5-44b7-a702-a302d5c3e27d
:END:
#+TITLE: Knowledge & Review
#+STARTUP: overview
#+TAGS: [ Area : House Auto Bills Work Health Learning Digital ]
#+FILETAGS: :Learning:reference:

Research notes, executable examples, and review cards share one connected file.

Connections: [[id:68fbf216-c578-41f1-b570-2b52ed092d99][Capture and refile]] · [[id:71a8da2a-c295-4b30-807b-bb845bf72fd7][Graph browser]] · [[id:d825ffc9-1160-49cc-b2d0-113c7436deb7][Groceries]] · [[id:5359bbea-6de3-4aba-bc86-fb46122005d3][Research notes]]

* Research notes                                         :Learning:Digital:
:PROPERTIES:
:ID:       5359bbea-6de3-4aba-bc86-fb46122005d3
:AREA:     Digital
:END:
Distributed systems turn failures into ordinary state transitions.  Compare
the feature lab's citation and [[https://www.gnu.org/software/emacs/][Emacs]].

Connections: [[id:cff8c2b4-da5a-46c1-aab4-9661c6e65368][Weekly review]] · [[id:86b18efc-f950-4c22-b006-5af19d0e1a74][Home server]] · [[id:6c4b91a5-b4f6-43ea-8ad9-56d1ac8e8e03][Insurance claim]] · [[id:e372b40c-f1fe-490a-9832-3b517af0309d][Babel playground]]

* Babel playground                                       :Learning:Digital:code:
:PROPERTIES:
:ID:       e372b40c-f1fe-490a-9832-3b517af0309d
:END:
#+begin_src emacs-lisp :results value
(mapcar #'1+ '(1 2 3))
#+end_src

#+RESULTS:
| 2 | 3 | 4 |

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb68][Demo hub]] · [[id:eda8dcb1-0000-400a-b713-25b73941bcaf][Release notes]] · [[id:68fbf216-0000-41f1-b570-2b52ed092d14][HEPA filter]] · [[id:7c2e91d4-5a38-4f61-9b0e-3d84a2c6f106][Gaussian card]]

* What does the Gaussian integral evaluate to?                   :Learning:
:PROPERTIES:
:ID:       7c2e91d4-5a38-4f61-9b0e-3d84a2c6f106
:END:
The answer is √π.  The [[file:glasspane-demo-hub.org::*Org feature lab][feature lab]]
contains the polar-integral equation.

Connections: [[id:25f40bb1-b008-46bd-bf12-5ad72456bb69][Start here]] · [[id:f95e563c-62e9-4c8a-bff6-eef9194f9660][Work map]] · [[id:2bf199b2-ab05-430d-a48c-81550252f6c3][Yoga challenge]] · [[id:b19f4e73-2c60-4585-8aa1-64f0d3b7e2c9][Mass–energy card]]

* Mass–energy equivalence                                      :Learning:
:PROPERTIES:
:ID:       b19f4e73-2c60-4585-8aa1-64f0d3b7e2c9
:END:
Energy and mass are related by \\(E=mc^2\\).

Connections: [[id:e372b40c-f1fe-490a-9832-3b517af0309c][Agenda inbox]] · [[id:9bfcf1a9-b6bb-48fd-9b21-898804c6036e][Companion beta]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc6][Life dashboard]] · [[id:e4a8c1f6-97b2-4d3e-8c05-1f6a9d24b380][Computer bug card]]

* The first computer bug                                      :Learning:
:PROPERTIES:
:ID:       e4a8c1f6-97b2-4d3e-8c05-1f6a9d24b380
:END:
The famous debugging artifact was a moth taped into the Harvard Mark II
logbook in 1947.

Connections: [[id:a0a70496-49c8-475d-bbc6-b507e8c43d82][Feature lab]] · [[id:933b2dfe-0b63-46ad-a4c4-6bfa8a847b2c][Offline queue soak]] · [[id:8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc7][Canyon hike]] · [[id:ba4b6d51-efe5-44b7-a702-a302d5c3e27d][Knowledge map]]
")
    ("glasspane-demo-work.org_archive" . "\
#+TITLE: Work Archive
#+STARTUP: overview
#+TODO: TODO NEXT WAITING IDEA | DONE CANCELLED
#+TAGS: [ Area : House Auto Bills Work Health Learning Digital ]
#+FILETAGS: :Work:Digital:archive:

This ordinary sibling archive is discovered by its =.org_archive= suffix.

* DONE Prototype the first mobile screen                      :Work:Digital:
CLOSED: [2026-06-18 Thu 17:30]
:PROPERTIES:
:ARCHIVE_TIME: 2026-06-18 Thu 17:31
:END:
Moved out of the live Project walk after completion.  See
[[file:glasspane-demo-work.org][the current work file]].

* CANCELLED Replace the staging server                        :Work:Bills:
CLOSED: [2026-06-24 Wed 09:00]
:PROPERTIES:
:ARCHIVE_TIME: 2026-06-24 Wed 09:01
:END:
The existing server was retained.
"))
  "Five compact Org fixtures written by glasspane-demo-setup-org.
Together they exercise every core Org element and object type exposed by the
supported parser, plus a balanced 24-note ID graph for Vulpea stress tests.")

;; ─── SRS registration for the knowledge file ─────────────────────────────────

;; org-srs is NOT installed locally: the `ext:' pseudo-file idiom keeps
;; byte-compile-error-on-warn honest with it absent (glasspane-srs's
;; block is the precedent); the one call path hides behind
;; `glasspane-srs-available-p'.
(declare-function org-srs-item-new "ext:org-srs-item")
(declare-function org-srs-item-cloze-default "ext:org-srs-item-cloze")
(declare-function org-srs-item-cloze-update-entry "ext:org-srs-item-cloze")

(defconst glasspane-demo--srs-cards
  '("What does the Gaussian integral evaluate to?"
    "Mass–energy equivalence")
  "Demo flashcard headings the setup registers as `card' items.")

(defconst glasspane-demo--srs-clozes
  '(("The first computer bug" "a moth" "1947"))
  "(HEADING TARGET…) rows the demo registers as cloze items.
Each TARGET is clozed in place, then the entry's items are created.")

(defun glasspane-demo--srs-goto-heading (heading)
  "Move point to HEADING's line in the current org buffer."
  (goto-char (point-min))
  (re-search-forward (format org-complex-heading-regexp-format
                             (regexp-quote heading)))
  (beginning-of-line))

(defun glasspane-demo--register-srs-items (dir)
  "Register DIR's demo flashcard entries as org-srs review items.
A no-op without org-srs — the file reads as plain org either way.
Runs right after the corpus overwrote the files, so previously
registered drawers are gone and every item is created fresh.  Errors
cost the registration, never the demo setup."
  (when (glasspane-srs-available-p)
    (condition-case err
        (with-current-buffer
            (find-file-noselect
             (expand-file-name "glasspane-demo-knowledge.org" dir))
          ;; The buffer may predate the overwrite; the disk copy rules.
          (revert-buffer :ignore-auto :noconfirm)
          (org-with-wide-buffer
           (dolist (heading glasspane-demo--srs-cards)
             (glasspane-demo--srs-goto-heading heading)
             (org-srs-item-new 'card))
           (pcase-dolist (`(,heading . ,targets) glasspane-demo--srs-clozes)
             (dolist (target targets)
               ;; Re-locate per target: each cloze wrap shifts positions.
               (glasspane-demo--srs-goto-heading heading)
               (search-forward target (org-entry-end-position))
               (org-srs-item-cloze-default (match-beginning 0)
                                           (match-end 0)))
             (glasspane-demo--srs-goto-heading heading)
             (org-srs-item-cloze-update-entry)))
          (let ((save-silently t)) (save-buffer)))
      ;; Symbol only: `error-message-string' embeds the offending datum
      ;; — buffer text here — and SPEC 23.3 keeps that out of logs.
      (error (message "glasspane-demo: SRS registration failed: %s"
                      (jetpacs-error-label err))))))

;; ─── Relative dates ──────────────────────────────────────────────────────────

(defconst glasspane-demo--org-anchor "2026-07-06"
  "The \"today\" the org corpus above was authored against.
Setup shifts every timestamp by (today − anchor) days at write time,
so the corpus always lands with its authored spread — overdue items,
a today, a tomorrow, deadlines weeks out — relative to the day the
command runs.  Editing corpus dates means re-anchoring this to the
new authoring day.")

(defun glasspane-demo--noon (date)
  "Encoded noon of DATE (\"YYYY-MM-DD\"); noon dodges DST date flips."
  (encode-time 0 0 12
               (string-to-number (substring date 8 10))
               (string-to-number (substring date 5 7))
               (string-to-number (substring date 0 4))))

(defun glasspane-demo--shift-timestamps (content days)
  "CONTENT with every day-named \"YYYY-MM-DD Day\" date moved DAYS forward.
One rewrite covers every org form in the corpus — active and inactive
stamps, CLOCK ranges, CLOSED/LAST_REPEAT entries, table rows — because
all of them carry the day-named date; whatever follows it (a time, a
repeater cookie) rides along untouched.  Day names are recomputed in
the C locale to match the corpus style, and the fixed-width stamp
keeps table alignment intact."
  (if (zerop days) content
    (let ((system-time-locale "C"))
      (replace-regexp-in-string
       "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} \\(?:Mon\\|Tue\\|Wed\\|Thu\\|Fri\\|Sat\\|Sun\\)"
       (lambda (stamp)
         (format-time-string
          "%Y-%m-%d %a"
          (time-add (glasspane-demo--noon (substring stamp 0 10))
                    (days-to-time days))))
       content t t))))

(defun glasspane-demo--org-shift ()
  "Days from the corpus's authoring anchor to today."
  (- (time-to-days (current-time))
     (time-to-days (glasspane-demo--noon glasspane-demo--org-anchor))))

(defun glasspane-demo--org-target ()
  "The corpus target: `org-directory'.
Always seeds below `org-directory', which is the authoritative root for
user Org content selected during onboarding.  Returns `org-directory' as
an absolute, directory-formatted path."
  (file-name-as-directory (expand-file-name org-directory)))

(defun glasspane-demo--safe-org-filename-p (name)
  "Return non-nil when corpus NAME is one namespaced basename.
Reject directory components as well as unprefixed names so a future fixture
edit cannot silently widen what the reset command overwrites."
  (and (stringp name)
       (string-prefix-p glasspane-demo--org-file-prefix name)
       (equal name (file-name-nondirectory name))))

(defun glasspane-demo--remove-retired-org-files (dir)
  "Remove obsolete generated corpus files immediately below DIR.
Only the exact basenames in `glasspane-demo--retired-org-files' qualify.  If a
retired file is open, discard its buffer as part of the explicitly requested
demo reset; ordinary vault files and other namespaced files remain untouched."
  (dolist (name glasspane-demo--retired-org-files)
    (unless (glasspane-demo--safe-org-filename-p name)
      (error "Unsafe retired demo filename: %S" name))
    (let ((file (expand-file-name name dir)))
      (when-let* ((buffer (find-buffer-visiting file)))
        (with-current-buffer buffer
          (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (when (or (file-exists-p file) (file-symlink-p file))
        (delete-file file)))))

(defun glasspane-demo--write-and-refresh (content file)
  "Replace FILE with CONTENT and refresh any buffer already visiting it.
Reset is explicit, so an open modified demo buffer is deliberately reverted;
the device confirmation and interactive command both promise pristine fixtures."
  (write-region content nil file nil 'silent)
  (when-let* ((buffer (find-buffer-visiting file)))
    (with-current-buffer buffer
      (revert-buffer :ignore-auto :noconfirm))))

;;;###autoload
(defun glasspane-demo-setup-org (&optional dir)
  "Write the five-file demo Org corpus into DIR (default `org-directory').
Every filename is required to begin with `glasspane-demo--org-file-prefix';
ordinary vault files are never candidates.  Existing corpus files are reset,
and exact generated names retired by this version are removed.  Every other
file in the directory is untouched.  Timestamps land relative to today: the
authored dates shift as one block (see
`glasspane-demo--org-anchor'), so the agenda always opens onto the same mix of
overdue, due-today, and upcoming items.  Returns DIR."
  (interactive)
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir (glasspane-demo--org-target)))))
        (shift (glasspane-demo--org-shift))
        (coding-system-for-write 'utf-8))
    (dolist (spec glasspane-demo--org-files)
      (unless (glasspane-demo--safe-org-filename-p (car spec))
        (error "Unsafe demo filename: %S" (car spec))))
    (dolist (name glasspane-demo--retired-org-files)
      (unless (glasspane-demo--safe-org-filename-p name)
        (error "Unsafe retired demo filename: %S" name)))
    (make-directory dir t)
    (glasspane-demo--remove-retired-org-files dir)
    (dolist (spec glasspane-demo--org-files)
      (glasspane-demo--write-and-refresh
       (glasspane-demo--shift-timestamps (cdr spec) shift)
       (expand-file-name (car spec) dir)))
    ;; The knowledge-file cards become live review items when org-srs is around.
    (glasspane-demo--register-srs-items dir)
    ;; Seed the Area group in the persistent alist used by the PARA model.
    (when (fboundp 'jetpacs-org-settings-set-tag-group-members)
      (ignore-errors
        (jetpacs-org-settings-set-tag-group-members
         (or (bound-and-true-p glasspane-area-tag-group) "Area")
         '("House" "Auto" "Bills" "Work" "Health" "Learning" "Digital")
         'org-tag-persistent-alist)))
    ;; Agenda, Projects, Areas, Search, and Review span several namespaces;
    ;; the fixture set and its effective workflows just changed together.
    (ebp-org-cache-invalidate)
    ;; When Vulpea is present, trigger a full scan so the reset ID graph and
    ;; PARA declarations are indexed immediately.
    (when (and (featurep 'vulpea) (fboundp 'vulpea-db-sync-full-scan))
      (ignore-errors (vulpea-db-sync-full-scan)))
    (when (called-interactively-p 'interactive)
      (message "Demo org corpus written to %s" dir))
    dir))

;;;###autoload
(defun glasspane-demo-setup (&optional dir)
  "Write the mobile-IDE tour files into DIR (default `glasspane-demo-directory').
Existing copies are overwritten so the tour always starts pristine.
Returns the directory the files were written to."
  (interactive)
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir glasspane-demo-directory))))
        ;; The tour files contain non-ASCII (section rules, em-dashes);
        ;; pin utf-8 so no platform default can make write-region prompt.
        (coding-system-for-write 'utf-8))
    (make-directory dir t)
    (dolist (spec glasspane-demo--files)
      (glasspane-demo--write-and-refresh
       (cdr spec) (expand-file-name (car spec) dir)))
    (when (called-interactively-p 'interactive)
      (message "Jetpacs demo files written to %s" dir))
    dir))

;;;; The verbs

(defun glasspane-demo--on-setup (_args _params)
  "Write the tour files; the allowlisted `demo.setup' body.
Argument-free by design: always the fixed file set into
`glasspane-demo-directory' — nothing on the wire chooses paths or
content.  The write runs synchronously inside the dispatch (fast,
local, and \\='accepted must mean durable); a failed write notifies,
then answers \\='rejected — never a swallowed-error accept."
  (condition-case err
      (let ((dir (glasspane-demo-setup)))
        (jetpacs-shell-notify
         (format "Demo files in %s" (abbreviate-file-name dir)))
        'accepted)
    (error
     (jetpacs-shell-notify
      (format "Demo setup failed: %s" (jetpacs-error-label err)))
     'rejected)))

(defun glasspane-demo--on-setup-org (_args _params)
  "Write the org corpus; the allowlisted `demo.setup-org' body.
Same shape as `demo.setup': argument-free, fixed file set, derived
target.  It overwrites the five current fixtures and removes only exact
retired generated names — never ordinary vault files.  The re-render
rides the deferred continuation only (D2): the corpus just replaced
what any open surface shows, and zero-arg `jetpacs-shell-push'
resolves through the flow's owner."
  (condition-case err
      (let ((dir (glasspane-demo-setup-org)))
        (jetpacs-shell-notify
         (format "Demo org corpus in %s" (abbreviate-file-name dir)))
        (jetpacs-flow-continue #'jetpacs-shell-push)
        'accepted)
    (error
     (jetpacs-shell-notify
      (format "Demo org setup failed: %s" (jetpacs-error-label err)))
     'rejected)))

(defun glasspane-demo-register ()
  "Register the demo verbs.
Called from `glasspane-register', not at this file's load: the entry's
unregister must leave no glasspane handler behind, and its re-register
must restore every verb without a re-require (the G0 gate contract)."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "demo.setup" #'glasspane-demo--on-setup
                       :doc "Write the fixed Glasspane tour files")
    (jetpacs-defaction "demo.setup-org" #'glasspane-demo--on-setup-org
                       :doc "Reset the compact Glasspane Org demonstration corpus")))

(defun glasspane-demo-unregister ()
  "Drop the demo verbs."
  (jetpacs-undefaction "demo.setup")
  (jetpacs-undefaction "demo.setup-org"))

(defun glasspane-demo-unload-function ()
  "Unload hygiene: drop the verbs, wherever registration stands."
  (glasspane-demo-unregister)
  nil)

(provide 'glasspane-demo)
;;; glasspane-demo.el ends here
