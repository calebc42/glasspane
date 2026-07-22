#!/usr/bin/env python3
"""Generate companion/wire Vocabulary.kt from ebp/contract.json (format 6).

The W0 pattern: wire vocabulary is generated from the authored contract,
never hand-maintained; a drift test re-reads contract.json and fails if the
committed generated file disagrees. Run from the llm-poc-2 root:

    python3 tools/gen-vocabulary.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
contract = json.loads((ROOT / "ebp" / "contract.json").read_text(encoding="utf-8"))

OUT = ROOT / "companion/wire/src/main/kotlin/com/calebc42/ebp/wire/Vocabulary.kt"


def kt_set(values):
    inner = ", ".join(f"\"{v}\"" for v in values)
    return f"setOf({inner})"


rows = []
for name in contract["node_types"]:
    row = contract["node_schema"][name]
    rows.append(
        f"    \"{name}\" to NodeRow({kt_set(row['required'])}, "
        f"{kt_set(row['optional'])}),"
    )

action_rows = []
for name, row in contract["actions"]["schema"].items():
    action_rows.append(
        f"    \"{name}\" to ActionRow({kt_set(row['required'])}, "
        f"{kt_set(row['optional'])}),"
    )

body = f"""// SPDX-License-Identifier: GPL-3.0-or-later
// GENERATED from ebp/contract.json (format {contract["contract_format"]},
// spec {contract["spec_version"]}) by tools/gen-vocabulary.py — DO NOT EDIT.
// VocabularyDriftTest re-reads the contract and fails on any disagreement.
package com.calebc42.ebp.wire

data class NodeRow(val required: Set<String>, val optional: Set<String>)
data class ActionRow(val required: Set<String>, val optional: Set<String>)

const val CONTRACT_FORMAT = {contract["contract_format"]}
const val SPEC_VERSION = "{contract["spec_version"]}"

val CORE_NODE_SET: Set<String> = {kt_set(contract["core_node_set"])}

val UNIVERSAL_NODE_ATTRIBUTES: Set<String> = {kt_set(contract["universal_node_attributes"])}

/** SPEC 14.6: node types whose id/value participate in input state. */
val STATEFUL_NODE_TYPES: Set<String> = setOf(
    "text_input", "checkbox", "switch", "enum_list", "slider", "editor")

val ACTION_HOOK_KEYS: Set<String> = {kt_set(contract["actions"]["hook_keys"])}

val OFFLINE_POLICIES: Set<String> = {kt_set(contract["actions"]["offline_policies"])}
const val OFFLINE_DEFAULT = "{contract["actions"]["offline_default"]}"

val NODE_SCHEMA: Map<String, NodeRow> = mapOf(
{chr(10).join(rows)}
)

val ACTION_SCHEMA: Map<String, ActionRow> = mapOf(
{chr(10).join(action_rows)}
)
"""

OUT.write_text(body, encoding="utf-8")
print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} nodes, {len(action_rows)} action rows")
