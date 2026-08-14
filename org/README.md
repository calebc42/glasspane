# Org Mode seed assets

`org-mode-walkthrough/` is the complete upstream Orgro manual bundle copied verbatim
from Orgro revision `add99f0ce2a2e50e0c75e9067271b6577856400b`. It remains
licensed under GPL-3.0; the upstream license is included beside the manual.

The manual describes Orgro itself, so its transclusion section is retained as
upstream documentation even though Jetpacs intentionally does not implement
transclusion. All other files in the bundle are kept so relative links,
citations, images, encryption, and attachment examples continue to work.

`inbox.org` is Jetpacs-authored starter content. At interactive startup these
assets are copied beneath `org-directory` only when the destination does not
already exist. User files are never overwritten.
