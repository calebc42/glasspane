# attic: the Aug-2 v2 sync bridge

Uncommitted work on `slop-fork/v2` (`llm-poc-2/`, 2026-08-02), caught by an
un-versioned Windows snapshot and recovered during the 2026-08-06 Windows-side
audit. Nothing here is on the load path; it is reference material.

- `jetpacs-sync.el` — the v2-era buffer bridge: session API riding
  `ebp-client-edit-open-functions`, `jetpacs-sync--role-for-face`, and the
  buffer-taking `jetpacs-sync--fontify-runs`. Behavioral predecessor of this
  line's `emacs/ebp-sync.el`.
- `jetpacs-sync-test.el` — its ERT suite (fontify runs sorted/half-open/disjoint,
  echo-loop prevention). Never existed on any ref before this commit.
- `ebp.el` + `ebp.el.vs-committed-v2.diff` — the drifted client: adds
  `ebp-client-diagnostics-show`, `ebp-client-fontify-show`,
  `ebp-client-eldoc-show` (SPEC 19 pushes). The diff is against the committed
  `slop-fork/v2` tip (which evolved through 2026-08-04 without absorbing this).
- `jetpacs-emacs-ui.el` + diff — the track-changes wiring for the bridge.

Supersession: diagnostics.show and fontify.show were rebuilt on this line as
ebp-sync riders (01d3cd7, 6786341), with equivalent coverage in
`test/ebp-sync-test.el`. **`ebp-client-eldoc-show` was not** — `emacs/ebp.el`
registers `eldoc.show` in its method table but no rider implements the push;
the version here is the only implementation and the reference for that rider
when it boards.
