# Glasspane

The Glasspane Emacs client — a Tier-1 app built on the **Jetpacs core** (vendored
here as the `jetpacs` git submodule). Pure elisp: it `(require 's the core and
drives the Android companion over the Jetpacs wire. **All Kotlin lives in the
[jetpacs] repo**; this repo is elisp only.

## Layout

- `emacs/apps/glasspane/` — the org app (reader, rich org, tables, journal,
  saved views, SRS, notes/backlinks, clock, demo tour…)
- `emacs/apps/jetpacs-*.el` — reference Tier-1 apps bundled with Glasspane
  (package browser, customize browser, tools hub, automations skin, magit pie)
- `emacs/build-bundle.el` — regenerates `glasspane.el` (app-only; the bundle
  opens with `(require 'jetpacs-core)`)
- `jetpacs/` — the Jetpacs core (foundation + companion), a git submodule
- `test/glasspane-tests.el` — the app's ERT suite, run against the submodule core

## Build & test

```sh
git submodule update --init
emacs --batch -l emacs/build-bundle.el        # regenerate glasspane.el
emacs -Q --batch -l test/glasspane-tests.el -f ert-run-tests-batch-and-exit
```

## Install

Load order matters — the core first (both bundles on `load-path`):

```elisp
(require 'jetpacs-core)   ; from jetpacs-core.el (the jetpacs repo / submodule)
(require 'glasspane)   ; from glasspane.el (this repo)
```

[jetpacs]: ../jetpacs
