# Glasspane

Personal information applet for Jetpacs. Glasspane is entirely downstream: it
consumes `ebp-org`, the Jetpacs public app/surface APIs, and the optional
`glasspane-material3` renderer extension. It does not define EBP or Jetpacs
foundation behavior.

The `glasspane-ef.el` module owns the optional EF Themes integration and
registers EF as a Modus-family provider in Jetpacs' Theme Settings screen.

Read `NAVIGATION.org` before adding a document entry point and `RENDERER.org`
before adding a design-specific node. The focused suite is:

```sh
test/run-tests.sh
```
