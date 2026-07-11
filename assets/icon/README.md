# Glasspane icon

The volumetric glass-pane mark, moved here 2026-07-10 from the jetpacs
companion (which now ships a neutral Material rocket placeholder — a
distro's identity belongs to the distro).

- `glasspane-icon.svg` — the source: full-bleed art on the slate
  (`#334155`) background, 512×512 viewBox. Converted 1:1 from the
  original Android vector drawable.
- `glasspane-icon-adaptive.png` — 512×512 raster, art scaled 0.6 about
  the centre so it survives the adaptive-icon mask. This is the file to
  feed `jetpacs-device-shortcut-pin`:

  ```elisp
  (jetpacs-device-shortcut-pin
   "glasspane" "Glasspane"
   (jetpacs-action "app.open" :args '((app . "glasspane")))
   :icon-file "<path-to>/glasspane-icon-adaptive.png")
  ```

Regenerate the PNG from the SVG at 512×512 with the art group scaled
0.6 about (256, 256) — any SVG rasterizer or Android Studio's asset
tool works.
