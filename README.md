# Glasspane

Personal information applet for Jetpacs. Glasspane is entirely downstream: it
consumes `ebp-org`, the Jetpacs public app/surface APIs, and the optional
`jetpacs-material3` renderer extension. It does not define EBP or Jetpacs
foundation behavior.

The `glasspane-ef.el` module owns the optional EF Themes integration and
registers EF as a Modus-family provider in Jetpacs' Theme Settings screen.

Switching to Projects or Areas sends only the selected screen, without an
intermediate Agenda frame. The previous destination and its drills leave the
stack; Agenda remains the Back destination beneath the new peer screen.

## Org outline

The document reader keeps the TODO keyword inline with the bold heading title,
using the source buffer's Org keyword face and custom Emacs colors. Area chips
share the root Projects styling: elevated, with configured icons, right-aligned
beside the heading on medium and expanded windows and stacked beneath it on a
phone. Membership includes inherited and file-level Areas; ordinary
tags stay below the heading without duplicating Area chips.
Glasspane reads native group vocabulary and heading membership through
`ebp-org`. PARA membership includes inheritance even when agenda inheritance
is disabled, while honoring `org-tags-exclude-from-inheritance`. The reader
queries its current source buffer directly; changing group settings does not
require editing a heading to refresh membership.
Tap the disclosure header to expand content; a long press, or **Open** in the
overflow menu, opens the existing detail view. The header carries no separate
open icon. Archive lives only in the leftward swipe, not in the overflow menu.
Tag search and the remaining overflow actions stay available. The header
row carries only the title and the overflow menu: Properties and Logbook
ride the rightward swipe beside Cycle as revealed actions that use Jetpacs's
shared drawer visibility state. The shown drawer's action carries the primary
accent, and tapping it hides the drawer without editing the file.
The actions directly open or close the rendered contents beneath the heading;
only one drawer per heading is open at a time. Revealing the other action
switches the panel; revealing the shown one closes it. An outlined panel
repeats the drawer's icon and label at the left in the primary accent.
There are no separate disclosure rows. Visible contents
omit Org's drawer delimiters. Properties use muted name labels beside selectable
values; IDs retain monospace styling, and empty values show a dash. Local property
order and repeated keys are preserved. Logbook clocks show a timer, readable time range,
and duration (or Running), preserving other entries in source order.
The detail view reads as a page. Its top bar names the document (the file's
`#+TITLE`, else its base name) on one line and carries only the read/edit
toggle, a tonal clock-out light while the heading is clocked in, and an
overflow menu: Clock in/out, Priority…, Log note…, Duplicate, Delete
(confirmed), Copy link, Copy text, Share…, Open in file, File properties…,
and Org actions… (Jetpacs's heading sheet). Refile and Archive keep the
floating toolbar; Prev · Log note · Next keep the bottom bar. Ancestors form
a tappable caption line above the headline; a top-level heading has none.

The TODO state is a Material split button in front of the headline: the
leading half shows the keyword and cycles the buffer's sequence on tap, the
chevron lists every keyword plus **No state**. An open keyword is filled, a
done one tonal, and a heading with no state shows an outlined ring. Beneath
the headline, set facts appear as tinted pills: Scheduled and Deadline in
words (“Today · 09:00 · weekly”, “Due Friday”, “3 days overdue”, colored
error/warning by urgency and muted once done), Priority (colored by rank),
and Clocking. A date pill opens its drawer; long-press opens Jetpacs's
timestamp dialog; the priority pill opens the priority dialog. A line of
Area chips and the heading's own tags follows; inherited tags stay out of
the resting view.

Below that, a start-aligned row of tooltipped drawer icons: Tags (`label`),
Scheduled (`event`), Deadline (`flag`), Properties (`tune`), Logbook
(`history`), and Connections (`link`) when the notes layer contributes
backlinks, outgoing links and unlinked mentions. Icons carry count badges;
the open drawer's icon is tonal in the primary accent, and only one drawer
is open at a time. A drawer is a filled card headed by its name and one edit
action (Edit tags, Edit timestamp, Add property, Log note). The date
drawers show a summary row (tap for the full dialog with time, repeater and
delay cookies) and quick chips — Today, Tomorrow, Next week, a native date
picker, Clear — that move only the day: time of day, repeater and delay
survive, for deadlines as well as schedules. The Tags drawer shows each
declared tag group as toggle chips (the Area group with its icons) so known
tags are one tap away and exclusive groups swap by construction; inherited
members show selected but disabled; **Add tag…** opens Jetpacs's grouped
picker for anything free-form.

Glasspane renders actual Org list checkboxes as native three-state controls.
Tap the box or item text to toggle complete; long-press to mark in progress.
Org owns statistics and parent/child updates, and the action saves before
acceptance. Source-block examples remain text. Jetpacs's stock Org view keeps
its interactive plain-text presentation.
Org tables render with emphasized headers, horizontal rules, aligned columns,
and horizontal scrolling for wide content. Formatting-only width/alignment
rows are hidden; formulas and surrounding source stay visible. Code examples
and tables that exceed the negotiated native budget remain plain text.
Rendering never evaluates formulas or modifies table contents.
Prose, heading titles, and checkbox labels hide Org emphasis delimiters.
Bold, italic, underline, code, and verbatim retain native text styling; nested
emphasis combines styles. Inline code and verbatim use a subtle translucent
background and the theme’s secondary text color to stand apart from prose.
Source blocks and literal punctuation stay unchanged. Strikethrough delimiters are hidden, but the current RichSpan
vocabulary has no line-through decoration. The plain editor retains all
original Org markup.
Org links render as underlined spans without their bracket syntax: a
described link shows its description with any nested emphasis, and a bare
link shows a readable label instead of its target, so `[[id:…]]` names the
linked heading (from the note database or Org's ID index), `file:` links show
the file name and target heading, and web links drop their scheme. Links into
Org content use the primary color; links that leave Emacs use the secondary
color. Tapping lets Org follow the link, then a file-backed destination opens
through Glasspane's one document route, while web and mail addresses are
handed to the system and acknowledged with a snackbar. Links inside examples,
source blocks and other literal contexts keep their source text. Beneath a
heading, a small connections caption counts the links its title and body
render and, when the note database is available and the heading has an ID,
the notes that link to it; tapping that caption opens the detail view, whose
Outgoing links and Linked references sections manage the connections.
Footnote references are underlined links that open a dialog with the note's
rendered text. Edit switches to a compact Org text field that fits above the
keyboard. Save commits synchronously after
checking the original buffer and disk; Cancel leaves the source untouched.
Normal, named inline, and anonymous inline footnotes use Org's own parser.
The rendered outline hides Footnote/Footnotes sections (and Org's configured
footnote section name), along with local definitions; plain editing retains
them. Missing or oversized definitions report a message when tapped.
Quote blocks render with a slim theme-colored left rule. Verse lines are
centered and italic; center blocks center each authored line. Examples and fixed-width sections keep
literal monospace text on the same subtle background as inline code/verbatim,
with fixed-width `:` prefixes hidden and content spacing preserved.
Block and line comments use smaller muted text. Export blocks use outlined
code cards with a folding format header and prepared Emacs face colors. Export
content stays literal; HTML is never executed or loaded as a webpage. The block delimiters are hidden in these presentations.
Arbitrary special blocks such as `#+begin_callout` and `#+begin_details`
use outlined cards with the block name as a folding title. Body emphasis is
rendered, parameters remain visible as muted text, and outer delimiters are hidden.
Blank lines, indentation, and emphasis inside quote/verse/center content are
preserved. Unsupported, incomplete, or oversized blocks retain their source.
Standalone image links render inline with a subdued caption. HTTPS images
load on the Companion; local files and Org attachments use Jetpacs's existing
allowlisted, bounded image reader. Unsupported images and source-block
examples retain their original text.
Source blocks use compact outlined cards with a language/name header,
monospace code carrying Emacs's prepared fontification, and Jetpacs's Play
button. Tap the header to fold the code and its adjacent results together.
Results use native tables and images where supported. Edit opens a multiline
code field inside the card, with a language dropdown populated from Emacs
Babel configuration and the current block language. Save updates the body and
language together, preserving the name, header arguments, and existing results;
Cancel discards the draft. One inline draft may be open at a time, up to 65,536
characters. Save checks source and disk freshness before writing. Header
arguments stay visible in the rendered view. Play uses Org Babel and saves results
before acknowledging execution; stale rendered blocks cannot execute after
their source changes. Merely rendering a block never executes it.
Babel `#+call:` lines render as compact Call cards with the referenced block
name, literal arguments, and Play/Edit buttons. Edit opens a native argument
field (for example `n=5, other=2`) with Save and Cancel. Saving changes only
the text inside the call parentheses; it never evaluates the arguments.
The target, header options, and previous results stay intact. Arguments are
limited to 8,192 characters on one line and validated with Org’s parser;
stale source or disk revisions reject Save. Code and call editors share one
active draft. After saving, Play runs the updated call. Adjacent results stay inside the
call card; call-specific header options and names remain visible. Play asks
Org to resolve and execute the call, then saves its results before acceptance.
Rendering never resolves calls or evaluates their argument expressions.
Narrowing into a heading with children keeps each fold control unique across
the retained file and detail views, preserving the file view's fold identity.
The outline filter accepts text and expressions such as `todo:TODO` and
`tags:work`.

## Agenda

Agenda pages render the same card Projects uses, so a heading's Area chips
appear elevated beside (or, on a phone, beneath) its title in both places. An
Area rail above the Day / Week / Month tabs narrows every page to one Area or
restores the full set with **All Areas**; the filter persists across pages and
date navigation. The rail and the fallback mode chips scroll sideways on one
line.

Saved Views cards, Search results, and the Archive screen share the same
Area presentation: Area chips elevate beside or beneath a headline, ordinary
tags keep the bottom row, and the Archive filter is the same Area rail as
Projects. On a compact window the Search row trades its labeled Search and
Save buttons for icon buttons so the query field keeps its width.

## Projects

The Projects screen treats every live heading with a TODO keyword as a
Project. Its first chip rail filters by workflow state, while the second filters
to one native Area or restores the complete set with **All Areas**. Both rails
scroll sideways on one line rather than wrapping, so a phone shows its first
cards without a stack of chips above them. A Project
belonging to several Areas matches each of those Area filters. The
**By File** / **By Area** grouping changes independently of both filters, and
filtering happens before navigation tokens are allocated. On medium and
expanded windows the grouping is a segmented control trailing the workflow
rail; on a compact window it is a top-bar icon button showing the current
grouping (folder or category) whose tap switches to the other.
Opening an Area mirrors the workflow-state rail beneath that Area's
**Projects** heading, and its intersection chips scroll the same way. This filter is independent per Area and offers the TODO
states represented by its actionable Projects.

Project cards place elevated Area chips to the right of the heading on medium
and expanded windows; a compact window stacks them beneath the heading so the
title keeps the card's full width. Ordinary tags have the full bottom row. Both
chip groups wrap when space is limited; Area icons and tag-search actions are
retained.

## Area icons

Settings → Glasspane → Area Icons assigns a bundled Material icon to each
member of the native `Area` tag group. The dialog provides common choices and
also accepts any `snake_case` Material icon name; blanking the field restores
the `category` default. Unknown catalog names render a help-outline placeholder
instead of breaking the screen. The preference affects Area rows and chips but
does not alter Org tags, Area membership, or vault files.

The same presentation-only mapping can be configured from Elisp:

```elisp
(setq glasspane-area-icons
      '(("House" . "home")
        ("Auto" . "directions_car")
        ("Bills" . "payments")
        ("Work" . "work")
        ("Health" . "health_and_safety")
        ("Learning" . "school")
        ("Digital" . "devices")))
```

Append `_filled` to request a filled icon variant, such as `home_filled`.
The renderer's generated [Material icon reference](../jetpacs-poc/docs/material3/lookup-tables/M3-ICON-REFERENCE.org)
lists the accepted `snake_case` catalog names.

## Demo Org corpus

`M-x glasspane-demo-setup-org` (also available under Settings → Glasspane →
Demo Content) writes a compact five-file vault into `org-directory`:
`glasspane-demo-hub.org`, `glasspane-demo-work.org`,
`glasspane-demo-life.org`, `glasspane-demo-knowledge.org`, and the sibling
`glasspane-demo-work.org_archive`.

The fixtures follow the current PARA implementation. A Project is any heading
with a TODO keyword; Areas are members of the native non-exclusive `Area` tag
group; Resources are live Org files; Archive discovers sibling `.org_archive`
files. The corpus therefore has no `:project:` or `:area:` role tags. Area
members such as `House`, `Bills`, and `Health` remain ordinary tags and can
overlap on one note.

The hub's feature lab covers every core element and object type exposed by the
supported Org parser. Across the four live files, 24 file/heading notes form a
balanced graph of 96 unique `id:` links: every note has four outbound and four
inbound edges, with 72 edges crossing file boundaries. This keeps Vulpea's
many-to-many paths busy without scattering the demonstration across dozens of
files.

Reset overwrites only the five current fixture names and removes a fixed list
of retired generated names. It never globs the `glasspane-demo-` prefix or
touches ordinary vault files.

Read `NAVIGATION.org` before adding a document entry point and `RENDERER.org`
before adding a design-specific node. The focused suite is:

```sh
test/run-tests.sh
```
