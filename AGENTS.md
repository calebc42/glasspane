# Glasspane applet implementation guide

This directory is the downstream Glasspane applet. Follow the workspace
[`../AGENTS.md`](../AGENTS.md), then the applet contract in
[`../jetpacs-applet-mcp/APPLET-GUIDE.md`](../jetpacs-applet-mcp/APPLET-GUIDE.md)
and [`../jetpacs-applet-mcp/DETERMINISM.md`](../jetpacs-applet-mcp/DETERMINISM.md).

Glasspane deliberately targets the optional Material renderer. Read
[`RENDERER.org`](RENDERER.org) before changing its app registration or using a
new design-specific node.

`glasspane-ef.el` is Glasspane-owned package policy. It may contribute its EF
row only through Jetpacs' Modus-family Theme Settings registry; Jetpacs must
not name EF or register its actions. Keep registration and teardown symmetric
with `glasspane-register` and `glasspane-unregister`.

## Non-negotiable navigation invariant

Read [`NAVIGATION.org`](NAVIGATION.org) before adding any tap, link, search
result, notification, widget, deep link, or menu item that opens a document.

- Builders may name a heading with an `ebp-org` token or a document with a
  path. They do not choose a screen, reader mode, Back behavior, or FAB.
- Build token-backed descriptors with
  `glasspane-navigation-heading-action`.
- Build path-backed descriptors with
  `glasspane-navigation-document-action`.
- After resolving an authority, call
  `glasspane-navigation-open-document`. Do not call
  `jetpacs-files-open-path`, `jetpacs-navigate-buffer`, or a Files action from
  a feature module.
- `glasspane-navigation.el` is the applet's only low-level Files boundary.
  `glasspane-navigation-open-files-path` exists only for non-document cases
  such as the explicit vault directory browser.
- A new entry point is incomplete until the convergence test names it.

Different wire actions are not automatically duplicate routes. A durable
heading token and a path have different validation and stale semantics. They
become a bug only when their handlers select different presentation policy.

## Change workflow

1. Use the static `jetpacs-applets` MCP to inspect and validate this directory
   before executing it. Static PASS is structural evidence, not proof of the
   navigation invariant.
2. Identify the entry point's authority: token, path, or a new explicitly
   documented type.
3. Reuse the navigation descriptor and presenter above. Keep builders pure and
   handlers status-returning.
4. Add or update focused ERT under `test/` and update `NAVIGATION.org` if the
   entry-point table changes.
5. Re-run static validation, Checkdoc, warning-as-error byte compilation into a
   temporary output directory, and the trusted determinism check. Loading this
   applet executes arbitrary Elisp; trusted mode is appropriate only when the
   user has explicitly placed Glasspane in scope.

From this repository, the focused offline suite is:

```sh
test/run-tests.sh
```

Do not compile over the neighboring `.elc` files or alter `.el~` backups.
Those are pre-existing user artifacts, not source authority.
Development loads must set `load-prefer-newer` as the commands above do; a
packaged deployment must rebuild or omit stale bytecode so ordinary `require`
cannot mask newer applet source.
