#!/usr/bin/env python3
"""List the user-facing composable files in the resolved material3 AAR.

Prints an org table of |Component|Package| rows — the raw input for the
cross-reference table in M3-COMPONENT-LOOKUP.org, whose Status /
Wire Type / Elisp Function columns are maintained by hand.

The version is whatever Gradle actually resolves (material3 rides the
Compose BOM with no pinned version — see libs.versions.toml).  Confirm
it before regenerating, and record it in the org header:

    ./gradlew -q :app:dependencyInsight \
        --dependency androidx.compose.material3:material3 \
        --configuration debugCompileClasspath

Then pass that version so the right cached AAR is used:

    python3 generate-component-list.py 1.4.0

Never rely on "first AAR in the cache" — the cache holds every version
ever resolved, and the first hit is arbitrary.
"""

import glob
import io
import os
import re
import sys
import zipfile


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    version = sys.argv[1]
    pat = os.path.expanduser(
        "~/.gradle/caches/**/androidx.compose.material3/material3*/"
        f"{version}/**/material3*.aar")
    hits = glob.glob(pat, recursive=True)
    if not hits:
        sys.exit(f"error: material3 {version} not in the Gradle cache")
    rows = set()
    with zipfile.ZipFile(sorted(hits)[-1]) as aar:
        cj = zipfile.ZipFile(io.BytesIO(aar.read("classes.jar")))
        for n in cj.namelist():
            m = re.fullmatch(
                r"androidx/compose/material3/((?:[a-z0-9]+/)*)"
                r"([A-Z]\w*)Kt\.class", n)
            if not m or "$" in n:
                continue
            pkg, name = m.group(1).rstrip("/"), m.group(2)
            if pkg in ("internal", "tokens"):
                continue
            if re.search(r"_(android|jvm|skiko)$", name):
                continue
            rows.add((name, f"material3.{pkg}" if pkg else "material3"))
    print("| Component | Package |")
    print("|---+---|")
    for name, pkg in sorted(rows):
        print(f"| {name} | {pkg} |")
    print("|---+---|")


if __name__ == "__main__":
    main()
