# Plan: the org toolbar as elisp (data-driven toolbars, Glasspane side)

**STATUS (2026-07-10): approved; BLOCKED on the jetpacs side landing.**
This is the Glasspane half of the jetpacs plan
[PLAN-data-driven-toolbars.md](https://github.com/calebc42/jetpacs/blob/main/docs/PLAN-data-driven-toolbars.md)
— read that first; it is the single source of truth for the wire design
(the `editor.toolbar` array form, the snippet/line/on_tap/menu item
vocabulary, and the placeholder rules). Do not start here until the
jetpacs commit exists; then **bump the `jetpacs` submodule pin to it**
(the standing rule: pin → regen bundle → suite → commit).

## Why

Today Glasspane requests its keyboard toolbar by name (`:toolbar "org"`),
which only works because the reference companion compiled in an
`OrgEditToolbar.kt`. That Kotlin is being deleted from the foundation;
the toolbar becomes pure data this repo owns. After this plan, the org
toolbar is ~60 lines of elisp here, and every op behaves as before.

## Tasks

1. **NEW `emacs/apps/glasspane/glasspane-org-toolbar.el`** — a
   `glasspane-org-toolbar` function returning the item list (see the
   button inventory below — it is the spec of record; the Kotlin it
   reproduces will be gone). Add the file to `emacs/build-bundle.el`'s
   `app-files` (before `glasspane-ui.el`) and require it where dependency
   order needs it.
2. **`emacs/apps/glasspane/glasspane-ui.el`** — two sites return the
   items instead of the string `"org"`:
   - `:toolbar "org"` (~line 1297, the detail-view editor) →
     `:toolbar (glasspane-org-toolbar)`
   - `jetpacs-files-editor-toolbar-function` (~line 2696, .org files) →
     returns `(glasspane-org-toolbar)`
   The core seam passes strings and lists through identically.
3. **Tests** — lint the toolbar (`jetpacs-lint-spec` over an editor node
   carrying it, round-tripped via `jetpacs-render-to-json`); regen
   `glasspane.el` (`emacs --batch -l emacs/build-bundle.el`); suite green
   (`emacs -Q --batch -l test/glasspane-tests.el -f
   ert-run-tests-batch-and-exit`, 72 tests pre-plan).
4. **On-device**: add to [TESTING-ON-DEVICE.md](TESTING-ON-DEVICE.md) —
   org file in the phone editor: a `${selection}` wrap, a line op, the
   long-press timestamp, the src dialog with a custom language.

## The button inventory (the org toolbar, item by item)

| button | item |
|---|---|
| Heading (H) | `menu` of 6: label `"* Heading 1"`…, snippet `"* "`…`"****** "`, placement `line-start` |
| Promote ← | `line: "promote"` |
| Demote → | `line: "demote"` |
| Move up ↑ | `line: "move-up"` |
| Move down ↓ | `line: "move-down"` |
| Checkbox ☐ | snippet `"- [ ] "`, placement `line-start` |
| Progress `[/]` | snippet `"[/]"`; `long_press` snippet `"[%]"` |
| Bullet • | snippet `"- "`, placement `line-start` |
| Numbered 1. | snippet `"1. "`, placement `line-start` |
| Src block | `menu`: common languages each `"#+begin_src LANG\n${cursor}\n#+end_src"` placement `block`, plus one custom item `"#+begin_src ${input:Language}\n${cursor}\n#+end_src"` |
| Props drawer | snippet `":PROPERTIES:\n:END:"`, placement `block` |
| Bold B | snippet `"*${selection}*"` |
| Italic I | snippet `"/${selection}/"` |
| Code ~ | snippet `"~${selection}~"` |
| Strike S | snippet `"+${selection}+"` |
| Link | snippet `"[[${cursor}][${selection}]]"` |
| Timestamp TS | snippet `"[${date}]"`; `long_press` snippet `"<${date}>"` |

Icons/labels: reuse the ones from the deleted `OrgEditToolbar.kt`
(title/H, format_indent_decrease/←, format_indent_increase/→,
arrow_upward/↑, arrow_downward/↓, checklist/☐, data_object/[/],
format_list_bulleted/•, format_list_numbered/1., code/Src,
data_object/Props, format_bold/B, format_italic/I, code/~,
format_strikethrough/S, link/Link, schedule/TS).

## Verification

Suite green against the bumped submodule; `glasspane.el` regenerated and
contains `glasspane-org-toolbar`; the on-device spot-checks above pass.
