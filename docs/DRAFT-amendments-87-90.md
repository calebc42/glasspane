# DRAFT amendments #87–#90

Drafted 2026-07-24 against `ebp/SPEC.md` @ amendments through **#86**.
Sources: `docs/AUDIT-jc-layer-2026-07-24.md` SPEC findings 8–10, plus the §21.3
hole verified during the same pass.

**Drafts for ratification, not applied edits.** Each gives the `SPEC-CHANGES.md`
row, the exact `SPEC.md` edits, and artifact changes.

**#87 needs a design decision** (the tile spec shape) — it is the one Caleb
deferred at "we are close to implementation of the quick settings tile". It is
now blocking real code: `jetpacs-shell.el` maps the `tile:` prefix to a profile
target and demands the `surfaces.tile` grant, but nothing tells it what to build.

Ratification order: **#88, #89, #90** (no design), then **#87** with the shape call.

---

## #87 — the `tile:*` SurfaceSpec variant (§13.4, §13.7)

**⚠ Design decision required: the tile spec shape.** Two candidates below;
option A is drafted, option B is the one-line alternative.

**SPEC-CHANGES row (option A):**

> | 87 | 2026-07-2X | §13.4, §13.7 (cross-ref §13.1, §10.2, §22.1) | **The `tile:*` SurfaceSpec variant, defined.** Amendment #39 registered `tile:<name>` as a capability-gated namespace (§13.1), added `tile` to §10.2's applicable targets, and registered `surfaces.tile` (§22.1) — describing it as "exactly parallel to notification/widget" and enumerating the §13 rules it inherits as "revision/tombstone/limit/update/remove". It never touched §13.4, whose sentence "The namespace determines the exact SurfaceSpec variant" makes that table the sole authority and whose closing sentence makes any unlisted combination `1201 content-invalid`. A granted `surfaces.tile` was therefore unusable: Emacs had no shape to author and a Companion had none to validate, so the same bytes are accepted by a Companion reading "unlisted means app-like" and rejected by one reading "parallel to widget". §13.4 gains a `tile:*` row defining the variant as a flat Quick-Settings metadata object `{label: string, icon?: identifier, subtitle?: string, active?: boolean, on_tap?: remote ActionDescriptor}` — a fixed platform slot, so no Node body and no stateful node — and its closing sentence now names every namespace that MUST NOT carry `views`. §13.7 records that a tile carries neither `header_action` nor `empty`. `on_tap` enters the §14 pipeline with no surface, dialog, or revision context, and the Companion injects the tile's `<name>`, parallel to §20.3 shortcuts. Additive: no tile `spec` was previously definable, so no previously valid frame is invalidated. | contract `surface_spec_variants.tile`; goldens/wire tile `surface.update` + an `on_tap` `event.action`; validate.py tile-variant check | |

**SPEC.md edits (option A):**

- §13.4 variant table — add a fourth row:
  > | `tile:*` | `{label: string, icon?: identifier, subtitle?: string, active?: boolean, on_tap?: ActionDescriptor}`; no Node body, no stateful node; multi-view prohibited |

- §13.4, replace the closing sentence:
  > `current_view` is valid only for a multi-view `app:*` spec. Any other
  > combination MUST receive `1201 content-invalid`.

  with:
  > `current_view` is valid only for a multi-view `app:*` spec; a
  > `notification:*`, `widget:*`, or `tile:*` spec MUST NOT carry `views`. Any
  > other combination MUST receive `1201 content-invalid`.

- §13.4, after the variant table — add:
  > A `tile:*` `spec` MUST NOT carry a Node, a `views` object, `current_view`, or
  > a stateful node; a Companion MUST reject any of these with
  > `1201 content-invalid`. `on_tap`, when present, enters the Section 14
  > remote-action pipeline with no surface, dialog, or revision context; the
  > Companion MUST inject the tile's `<name>` into a copy of `on_tap.args` as
  > `tile`, and an authored conflicting member makes the spec invalid (parallel
  > to Section 20.3 shortcuts).

- §13.7 — append:
  > A `tile:*` spec carries neither `header_action` nor `empty`; those are
  > notification and widget concepts.

**Option B (minimal, if tiles should render a Node body):** replace the row with

> | `tile:*` | The `widget:*` schema; multi-view is prohibited |

and drop the "no Node body" sentence. Cheaper to spec, but it gives a
Quick-Settings slot a full widget body it cannot present, and leaves `active`
(the on/off state a tile *is*) unexpressible.

**Recommendation: option A.** A QS tile is a fixed slot with a label, an icon,
and a boolean state; reusing the widget wrapper would model it as something it
is not. Option A is also what `jetpacs-shell` can gate today without new
machinery.

**Until ratified:** `jetpacs-shell-push` should refuse a `tile:` push outright
rather than guess a shape (currently it maps the prefix and gates the capability,
then sends whatever the builder produced).

---

## #88 — a registry for profile `features` (§22.2 new, §10.2, §24.2)

**SPEC-CHANGES row:**

> | 88 | 2026-07-2X | §22.2 (new), §10.2, §24.2, §17.2, §17.7 (contract) | **The feature registry.** §10.2 requires each profile to carry a `features` array and requires Emacs to "gate every emitted node, builtin, and constraining feature against the target profile", and §24.2 lists "explicit capability and per-target node, builtin, and feature gating" as an Emacs core-conformance duty — but the document never enumerated the feature namespace. Normative feature names appear in exactly two places (`image.https`/`image.data` in §17.2, `toolbar.<identifier>` in §17.7); §22.1 registers protocol capabilities, §20.3 device capabilities, §21.5 trigger types, and `contract.json` projects `capabilities`, `trigger_types`, `state_types`, `theme_roles`, `syntax_roles` — but nothing projects features. A sender therefore could not write the gate §24.2 requires: it could only hard-code today's two families, leaving any later or vendor feature ungatable by construction and leaving two senders free to disagree about which constructs are "constraining". A new §22.2 registers the vocabulary the spec already relies on, giving each entry the construct it constrains and the sender's rule when it is absent; §10.2 and §24.2 cross-reference it, and it is projected as `features` in `contract.json` so senders and conformance tooling share one list. This is amendment #57's genre (enumerate the vocabulary the spec already assumes). Additive: the two existing feature names and their §17.2/§17.7 rules are unchanged, so no previously valid profile or frame is invalidated. | contract `features`; validate.py features projection check | |

**SPEC.md edits:**

- New **§22.2 Feature registry** (renumbering the present §22.2/§22.3 to §22.3/§22.4):

  > A profile's `features` array (Section 10.2) advertises the *constraining
  > features* the Companion honors on that target. A constraining feature gates a
  > construct an ignoring receiver would over-accept, so Section 12's
  > constraining-member rule applies: the sender skips the whole construct when the
  > feature is absent.
  >
  > | Feature | Constrains | Sender rule when absent |
  > |---|---|---|
  > | `image.https` | an `image` whose `url` has an `https:` scheme (§17.2) | omit the `image` node |
  > | `image.data` | an `image` whose `url` has a `data:image/*` scheme (§17.2) | omit the `image` node |
  > | `toolbar.<identifier>` | an `editor.toolbar` naming a registered toolbar identifier (§17.7) | omit `toolbar`, or supply an inline ToolbarItem array |
  >
  > A feature name is a Section 4.4 identifier. A receiver MUST ignore an
  > unrecognized `features` entry. A future feature MUST be registered here with
  > its constrained construct and its sender rule before any section relies on it,
  > and MUST be projected into `contract.json`.

- §10.2, after "…MUST NOT interpret a missing profile or list as support for
  everything." — append:
  > The registered feature vocabulary is Section 22.2.

- §24.2, the "explicit capability and per-target node, builtin, and feature
  gating" bullet — append "(Section 22.2)".

**Artifacts:** `contract.json` gains a top-level `features` array
`["image.https", "image.data", "toolbar.*"]` (the toolbar family projected as a
prefix, since its suffix is open); `validate.py` checks that every §22.2 row is
projected.

---

## #89 — snackbar presentation lifetime (§17.6)

**SPEC-CHANGES row:**

> | 89 | 2026-07-2X | §17.6 | **Snackbar presentation lifetime and re-show semantics.** §17.6 defines the member as `snackbar: string` and pins exactly one behavior — "The Companion MUST dispatch a snackbar action only on a user tap, never on timeout" — saying nothing about when a snackbar is presented, for how long, or whether a later accepted snapshot carrying the same string presents it again. Because a snapshot is a complete replacement (§13.2), a Companion treating `snackbar` as snapshot state dismisses it as soon as the next snapshot omits the member, so a message can vanish before it is read; one treating every accepted snapshot with a non-empty `snackbar` as a fresh presentation re-flashes a builder-constant string on every push. Both readings are conformant and the divergence is reachable within a second of any debounced re-push. §17.6 now states that presentation is keyed to CHANGE under Section 4.3 equality against the previously accepted snapshot for that surface, that an unchanged value MUST NOT re-present, that an absent or empty value dismisses a visible snackbar, that a presented snackbar SHOULD remain visible at least 4 seconds and MUST be user-dismissible, and that `snackbar` carries no Section 16.1 presentation identity. This is the #59/#60 genre (pin a presentation behavior the vocabulary already implies). Clarifying prose; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §17.6, after "The Companion MUST dispatch a snackbar action only on a user tap,
  never on timeout." — insert:
  > The Companion presents `snackbar` when an accepted snapshot introduces a value
  > that differs under Section 4.3 equality from the value in the previously
  > accepted snapshot for that surface. An unchanged value MUST NOT re-present. An
  > absent or empty `snackbar` dismisses any snackbar currently visible for that
  > surface. A presented snackbar SHOULD remain visible for at least 4 seconds and
  > MUST be dismissible by the user. `snackbar` carries no Section 16.1
  > presentation identity: it is not a node and never retains local state.

---

## #90 — §21.3: what happens to the rest of an unauthorable trigger set

**SPEC-CHANGES row:**

> | 90 | 2026-07-2X | §21.3, §21.1 | **A trigger omitted for an unadvertised gate type, and the set it came from.** §21.3 says "If a non-predicate-only type is absent, Emacs MUST omit the entire trigger; it MUST NOT remove the unsupported predicate and install a weaker trigger" — a per-trigger rule. But `triggers.set` (§21.1) atomically replaces the WHOLE set for the pairing identity, and the SPEC never said what becomes of the other entries, nor whether the omission must be visible to the application: one sender silently drops the offending trigger and installs the rest, so the app believes it registered N registrations while N-1 can fire and only the returned `count` betrays it; another refuses to send at all, so one unauthorable trigger costs every other registration. Both satisfy §21.3's letter. §21.3 now states that omission is per trigger — the remaining entries are still sent — and that Emacs MUST surface the omission to the application rather than drop it silently, since the accepted `count` is the only wire evidence and nothing requires a caller to read it. §21.1 cross-references. Clarifying prose resolving a genuine sender divergence; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §21.3, replace:
  > If a non-predicate-only type is absent, Emacs MUST omit the entire trigger;
  > it MUST NOT remove the unsupported predicate and install a weaker trigger.

  with:
  > If a non-predicate-only type is absent, Emacs MUST omit the entire trigger; it
  > MUST NOT remove the unsupported predicate and install a weaker trigger. The
  > omission is per trigger: the remaining entries of the same `triggers.set` are
  > still sent, and the accepted `count` (Section 21.1) reflects only those.
  > Because that count is the sole wire evidence of the omission and no rule
  > requires a caller to read it, Emacs MUST surface an omitted trigger to the
  > application rather than drop it silently.

- §21.1, after the `{count}` sentence — append:
  > `count` also reflects any trigger Emacs omitted under Section 21.3.

**Implementation note:** `ebp-client-triggers-set` currently signals on a
violating set — a stricter reading that satisfies §21.3's letter (no weaker
trigger is ever installed) but not this amendment's "the remaining entries are
still sent". Under #90 it should omit the offending entries, send the rest, and
report the omission to the caller.

---

## Roll-up

| # | Hole | Sections | Needs a decision? | Artifacts |
|---|---|---|---|---|
| 87 | `tile:*` has no SurfaceSpec variant | §13.4, §13.7 | **yes — the tile shape** | contract + goldens |
| 88 | no `features` registry | §22.2 new, §10.2, §24.2 | no | contract `features` |
| 89 | snackbar lifetime undefined | §17.6 | no | none |
| 90 | omit-vs-refuse for a trigger set | §21.3, §21.1 | no | none |
