#!/usr/bin/env python3
"""Generate emacs/jetpacs-vocabulary.el from ebp/contract.json (format 6).

The sibling of tools/gen-vocabulary.py, which does the same for the
Companion's Vocabulary.kt.  Same W0 rule: wire vocabulary is generated from
the authored contract, never hand-maintained; a drift test re-reads
contract.json and fails if the committed generated file disagrees.

SCOPE.  jetpacs-widgets.el already mirrors `node_types', `core_node_set',
`universal_node_attributes', `theme_roles' and `syntax_roles' by hand, and
the `jetpacs-widgets/catalog-*' tests already fail on drift for each -- so
those stay where they are.  What had NO mirror is `node_schema', the
per-node member table, which is 39 rows nobody should type.  That is what
this file generates.  Run from the llm-poc-2 root:

    python3 tools/gen-jetpacs-vocabulary.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
contract = json.loads((ROOT / "ebp" / "contract.json").read_text(encoding="utf-8"))

OUT = ROOT / "emacs" / "jetpacs-vocabulary.el"


def el_strings(values):
    return " ".join(f'"{v}"' for v in values)


rows = []
for name in contract["node_types"]:
    row = contract["node_schema"][name]
    rows.append(
        f'    ("{name}" ({el_strings(sorted(row["required"]))})'
        f' ({el_strings(sorted(row["optional"]))}))'
    )

body = f''';;; jetpacs-vocabulary.el --- the contract node schema -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; GENERATED from ebp/contract.json (format {contract["contract_format"]}, spec
;; {contract["spec_version"]}) by tools/gen-jetpacs-vocabulary.py -- DO NOT EDIT.
;; `jetpacs-widgets/catalog-node-schema' re-reads the contract and fails on
;; any disagreement, exactly as the other `catalog-*' mirrors do.
;;
;; The sibling of the Companion's generated Vocabulary.kt, and for the same
;; reason: an amendment that adds a member must not have to be remembered in
;; three places.  Emacs cannot read contract.json at run time -- the device
;; load-path holds only the .el files device/install.sh pushes -- so the
;; contract is compiled to Elisp here and drift-tested off-device.
;;
;; This is what lets the container constructors REFUSE an unknown trailing
;; option instead of silently dropping it, which is how `:padding 8' on a
;; row used to vanish (it is a SPEC 16.5 universal attribute and belongs on
;; `jetpacs-with-attrs').

;;; Code:

(defconst jetpacs-contract-format {contract["contract_format"]}
  "The `contract_format' this vocabulary was generated from.")

(defconst jetpacs-contract-spec-version "{contract["spec_version"]}"
  "The SPEC version this vocabulary was generated from.")

(defconst jetpacs-node-schema
  '(
{chr(10).join(rows)})
  "Contract members per node type: (TYPE (REQUIRED...) (OPTIONAL...)).
WIRE names, so the table compares directly against contract.json.  The
constructors spell a multi-word member with a hyphen (`:content-padding'
for `content_padding'); `jetpacs--wire-name' is the map between them.")

(provide 'jetpacs-vocabulary)
;;; jetpacs-vocabulary.el ends here
'''

OUT.write_text(body, encoding="utf-8")
print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} node types")
