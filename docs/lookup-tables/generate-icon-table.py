#!/usr/bin/env python3
"""Regenerate the icon rows of M3-ICON-REFERENCE.org.

Reads BOTH icon artifacts from the local Gradle cache —
material-icons-core (the ~50 common icons: arrow_back, menu, close,
search...) and material-icons-extended (everything else).  The first
cut of the table read only the extended AAR and therefore reported the
most common icons in Material as nonexistent (18 of IconMap's 66
pre-seeded names were missing).

Emits the org table between the BEGIN/END markers in the org file when
run with --update; prints the table to stdout otherwise.  Portable:
python3 + a populated ~/.gradle/caches (run ./gradlew build first).

Validation: every name IconMap.kt pre-seeds MUST appear in the
generated set, or this script fails loudly — that invariant is what
catches a missing artifact.
"""

import glob
import io
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ORG = os.path.join(HERE, "M3-ICON-REFERENCE.org")
ICONMAP = os.path.normpath(os.path.join(
    HERE, "..", "..", "companion", "app", "src", "main", "kotlin",
    "com", "calebc42", "ebp", "companion", "render", "IconMap.kt"))
BEGIN = "# BEGIN GENERATED ICON TABLE"
END = "# END GENERATED ICON TABLE"


def find_aar(artifact):
    pat = os.path.expanduser(
        f"~/.gradle/caches/**/{artifact}-release.aar")
    hits = glob.glob(pat, recursive=True)
    if not hits:
        sys.exit(f"error: {artifact} not in the Gradle cache — "
                 "run ./gradlew build in companion/ first")
    return sorted(hits)[-1]


def snake(name):
    """PascalCase -> snake_case, matching IconMap's inverse mapping."""
    s = re.sub(r"(?<!^)(?=[A-Z])", "_", name)
    s = re.sub(r"([a-z])(\d)", r"\1_\2", s)
    s = re.sub(r"(\d)([A-Z])", r"\1_\2", s)
    return s.lower()


def icon_classes(aar_path):
    """(outlined, automirrored) sets of PascalCase icon names."""
    outlined, auto = set(), set()
    with zipfile.ZipFile(aar_path) as aar:
        cj = zipfile.ZipFile(io.BytesIO(aar.read("classes.jar")))
        for n in cj.namelist():
            m = re.fullmatch(
                r"androidx/compose/material/icons/"
                r"(automirrored/outlined|outlined)/([A-Z]\w*)Kt\.class", n)
            if m:
                (auto if "automirrored" in m.group(1)
                 else outlined).add(m.group(2))
    return outlined, auto


def iconmap_preseed():
    with open(ICONMAP, encoding="utf-8") as f:
        return set(re.findall(r'cache\["([a-z_0-9]+)"\]', f.read()))


def main():
    outlined, auto = set(), set()
    for artifact in ("material-icons-core", "material-icons-extended"):
        o, a = icon_classes(find_aar(artifact))
        outlined |= o
        auto |= a

    rows = {}
    for name in outlined:
        rows[snake(name)] = (f"~Icons.Outlined.{name}~", "Outlined")
    for name in auto:
        # IconMap tries Outlined first, then AutoMirrored: a name in both
        # resolves Outlined, so only AutoMirrored-exclusive names get the
        # AutoMirrored row.
        rows.setdefault(
            snake(name),
            (f"~Icons.AutoMirrored.Outlined.{name}~", "AutoMirrored"))

    missing = iconmap_preseed() - set(rows)
    if missing:
        sys.exit(f"error: IconMap pre-seeds {sorted(missing)} but the "
                 "generated set lacks them — an artifact is missing")

    n_auto = sum(1 for _, c in rows.values() if c == "AutoMirrored")
    lines = [BEGIN,
             f"# {len(rows)} names ({len(rows) - n_auto} Outlined + "
             f"{n_auto} AutoMirrored-only), core + extended merged.",
             "| snake_case name | Compose Reference | Category |",
             "|---+---+---|"]
    for name in sorted(rows):
        ref, cat = rows[name]
        lines.append(f"| {name} | {ref} | {cat} |")
    lines += ["|---+---+---|", END]
    table = "\n".join(lines)

    if "--update" in sys.argv:
        with open(ORG, encoding="utf-8") as f:
            org = f.read()
        pre, _, rest = org.partition(BEGIN)
        _, _, post = rest.partition(END)
        if not rest:
            sys.exit(f"error: {BEGIN} marker not found in {ORG}")
        with open(ORG, "w", encoding="utf-8") as f:
            f.write(pre + table + post)
        print(f"updated {ORG}: {len(rows)} names")
    else:
        print(table)


if __name__ == "__main__":
    main()
