#!/usr/bin/env python3
"""Generate SQLITE-DRIVER-REFERENCE.org from the local androidx clone.

Constraint-oriented, not coverage-oriented: it derives (1) the
androidx.sqlite driver surface `ebp-sqlite` will sit on, (2) the bundled
driver's flags/threading/version facts, (3) the declared Kotlin targets
of `sqlite` vs `sqlite-bundled` — the web-target distinction spelled
precisely — and (4) the Room 3 boundary: grep-located citations for the
four properties that bar Room from the schema-generic layer (audit
P1-6 / PLAN-refound Decision 2).  The claims prose is reviewed once,
here in the generator; every citation is located at generation time so
it cannot silently rot.

PINNED to the clone SHA the 2026-07-31 audit verified against.  The
generator refuses to run against any other checkout unless --sha=<sha>
is passed explicitly, in which case the output records the override.

    python3 docs/lookup-tables/generate-sqlite-table.py
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "SQLITE-DRIVER-REFERENCE.org")
CLONE = os.environ.get(
    "ANDROIDX_CLONE", os.path.expanduser("~/pkb/resources/android/androidx"))
PINNED = "d69c96e6bc402016899904d66646816a62ebff4d"

SQ = "sqlite/sqlite"
SB = "sqlite/sqlite-bundled"
SW = "sqlite/sqlite-web"
R3 = "room3/room3-runtime"

IFACES = [
    ("SQLiteDriver", [
        ("commonMain", f"{SQ}/src/commonMain/kotlin/androidx/sqlite/SQLiteDriver.kt"),
        ("nonWebMain", f"{SQ}/src/nonWebMain/kotlin/androidx/sqlite/SQLiteDriver.nonWeb.kt"),
        ("webMain", f"{SQ}/src/webMain/kotlin/androidx/sqlite/SQLiteDriver.web.kt")]),
    ("SQLiteConnection", [
        ("commonMain", f"{SQ}/src/commonMain/kotlin/androidx/sqlite/SQLiteConnection.kt"),
        ("nonWebMain", f"{SQ}/src/nonWebMain/kotlin/androidx/sqlite/SQLiteConnection.nonWeb.kt"),
        ("webMain", f"{SQ}/src/webMain/kotlin/androidx/sqlite/SQLiteConnection.web.kt")]),
    ("SQLiteStatement", [
        ("commonMain", f"{SQ}/src/commonMain/kotlin/androidx/sqlite/SQLiteStatement.kt"),
        ("nonWebMain", f"{SQ}/src/nonWebMain/kotlin/androidx/sqlite/SQLiteStatement.nonWeb.kt"),
        ("webMain", f"{SQ}/src/webMain/kotlin/androidx/sqlite/SQLiteStatement.web.kt")]),
    ("SQLite helpers", [
        ("commonMain", f"{SQ}/src/commonMain/kotlin/androidx/sqlite/SQLite.kt"),
        ("nonWebMain", f"{SQ}/src/nonWebMain/kotlin/androidx/sqlite/SQLite.nonWeb.kt"),
        ("webMain", f"{SQ}/src/webMain/kotlin/androidx/sqlite/SQLite.web.kt")]),
]

TARGET_CALLS = ["androidLibrary", "ios", "js", "jvm", "linux", "mac",
                "tvos", "wasmJs", "watchos"]


def clone_sha():
    return subprocess.run(["git", "-C", CLONE, "rev-parse", "HEAD"],
                          capture_output=True, text=True,
                          check=True).stdout.strip()


def read(rel):
    return open(os.path.join(CLONE, rel), encoding="utf-8").read()


MEMBER_RE = re.compile(
    r"\s*public ((?:suspend |inline |open |override |actual |expect )*)"
    r"(fun|val) (.+)")


def members(rel):
    """(signature, line) for every public member; signatures may wrap."""
    out = []
    lines = read(rel).splitlines()
    for i, line in enumerate(lines, 1):
        m = MEMBER_RE.match(line)
        if not m:
            continue
        sig = (m.group(1) + m.group(3)).strip()
        j = i
        while sig.count("(") > sig.count(")") and j < len(lines) and j < i + 3:
            sig += " " + lines[j].strip()
            j += 1
        sig = re.sub(r"\s+", " ", sig).rstrip("{").strip()
        sig = re.sub(r"[:=]\s*$", "", sig).strip()
        out.append((sig, i))
    return out


def grep(rel, pattern):
    return [(i, line.strip())
            for i, line in enumerate(read(rel).splitlines(), 1)
            if re.search(pattern, line)]


def targets(rel):
    src = read(rel)
    m = re.search(r"androidXMultiplatform\s*\{(.*)", src, re.S)
    if not m:
        sys.exit(f"FATAL: no androidXMultiplatform block in {rel}")
    block = m.group(1)
    found = []
    for t in TARGET_CALLS:
        if re.search(rf"^\s*{t}\s*[({{]", block, re.M):
            found.append(t)
    return found


def esc(s):
    return s.replace("|", "\\vert{}")


def main():
    override = next((a.split("=", 1)[1] for a in sys.argv[1:]
                     if a.startswith("--sha=")), None)
    sha = clone_sha()
    if override:
        if sha != override:
            sys.exit(f"FATAL: clone is at {sha}, --sha says {override}")
        pin_note = f"OVERRIDE {sha[:7]} (pin is {PINNED[:7]})"
    elif sha != PINNED:
        sys.exit(f"FATAL: clone is at {sha[:12]}, pinned to {PINNED[:12]}.\n"
                 f"Pass --sha={sha} only if you mean to regenerate against "
                 f"a moved clone — and update LIBRARY-LEDGER.md's citation "
                 f"with it.")
    else:
        pin_note = sha[:7]

    sq_targets = targets(f"{SQ}/build.gradle")
    sb_targets = targets(f"{SB}/build.gradle")
    version = grep(f"{SB}/build.gradle", r"sqliteVersion\.set")
    threadsafe = grep(f"{SB}/build.gradle", r"SQLITE_THREADSAFE")
    flags = grep(f"{SB}/src/commonMain/kotlin/androidx/sqlite/driver/"
                 "bundled/BundledSQLite.kt", r"public const val SQLITE_OPEN_")
    opens = grep(f"{SB}/src/commonMain/kotlin/androidx/sqlite/driver/"
                 "bundled/BundledSQLiteDriver.kt",
                 r"fun (open|addExtension)")
    web_open = grep(f"{SW}/src/webMain/kotlin/androidx/sqlite/driver/"
                    "WebSQLiteDriver.kt", r"suspend fun open|fun open") \
        if os.path.exists(os.path.join(
            CLONE, SW, "src/webMain/kotlin/androidx/sqlite/driver/"
            "WebSQLiteDriver.kt")) else []

    boundary = [
        ("Opening requires generated code",
         "`createOpenDelegate` is `protected actual open` and implemented "
         "only by KSP-generated database classes — a runtime-declared, "
         "wire-received schema has no way to open a Room database at all.",
         [(f"{R3}/src/androidMain/kotlin/androidx/room3/"
           "RoomDatabase.android.kt", r"fun createOpenDelegate\(")]),
        ("Room writes into any database it opens",
         "The connection manager inserts and validates its schema identity "
         "hash in the master table — it *mutates* a foreign artifact and "
         "refuses one whose hash disagrees.",
         [(f"{R3}/src/commonMain/kotlin/androidx/room3/"
           "RoomConnectionManager.kt",
           r"createInsertQuery\(openDelegate\.identityHash\)"),
          (f"{R3}/src/commonMain/kotlin/androidx/room3/"
           "RoomConnectionManager.kt",
           r"openDelegate\.identityHash != identityHash")]),
        ("No-flags open under an exclusive file lock",
         "Room opens through the flagless `delegate.open(fileName)` overload "
         "and serializes access behind `ExclusiveMutex(useFileLock = …)` — "
         "no read-only open, no URI parameters, and a lock a second process "
         "cannot share.",
         [(f"{R3}/src/commonMain/kotlin/androidx/room3/"
           "RoomConnectionManager.kt", r"delegate\.open\(resolvedFileName\)"),
          (f"{R3}/src/commonMain/kotlin/androidx/room3/"
           "RoomConnectionManager.kt", r"ExclusiveMutex\(")]),
        ("The migration ladder is compile-time",
         "Migrations are authored classes keyed (from, to) and registered on "
         "the builder — schema evolution cannot be driven by data received "
         "at runtime.",
         [(f"{R3}/src/commonMain/kotlin/androidx/room3/migration/"
           "Migration.kt", r"class Migration")]),
    ]

    w = []
    w.append("# -*- mode: org; coding: utf-8 -*-")
    w.append("#+TITLE: androidx.sqlite Driver Reference (and the Room 3 boundary)")
    w.append("#+AUTHOR: GENERATED by generate-sqlite-table.py — do not edit")
    w.append("#+STARTUP: showall")
    w.append("#+OPTIONS: ^:nil")
    w.append("")
    w.append("* androidx.sqlite Driver Reference")
    w.append("")
    w.append(f"GENERATED from the local androidx clone @ ={pin_note}= (the SHA")
    w.append("the 2026-07-31 audit verified against; the generator refuses any")
    w.append("other checkout without an explicit override).  Constraint-oriented:")
    w.append("this is the API =ebp-sqlite= sits on (PLAN-refound RF-4c) and the")
    w.append("Room 3 boundary it must never cross (Decision 2, audit P1-6).")
    w.append("LIBRARY-LEDGER.md's androidx.sqlite and Room 3 citations are")
    w.append("reproducible from this file.  The clone is the authority; this")
    w.append("table is orientation (SPEC §24.4).")
    w.append("")
    w.append("** 1. The driver surface (=androidx.sqlite:sqlite=)")
    w.append("")
    w.append("The interfaces are *target-split at the source-set level*: the")
    w.append("blocking members live in =nonWebMain=, the web family gets")
    w.append("=suspend= counterparts in =webMain=, and =commonMain= holds only")
    w.append("the family-neutral rump.  Design consequence for =ebp-sqlite=:")
    w.append("code written against the synchronous =open=/=prepare= seam is")
    w.append("=nonWebMain=-shaped, not common — the web port is an async")
    w.append("re-plumbing, not a recompile.")
    w.append("")
    for name, srcs in IFACES:
        w.append(f"*** {name}")
        w.append("")
        w.append("| Member | Source set | Line |")
        w.append("|---|---|---|")
        rows = 0
        for sset, rel in srcs:
            if not os.path.exists(os.path.join(CLONE, rel)):
                continue
            for sig, line in members(rel):
                w.append(f"| ={esc(sig)}= | {sset} | {line} |")
                rows += 1
        if not rows:
            sys.exit(f"FATAL: no members parsed for {name}")
        w.append("")
    w.append("** 2. The bundled driver (=androidx.sqlite:sqlite-bundled=)")
    w.append("")
    v = re.search(r'"([\d.]+)"', version[0][1]).group(1) if version else "?"
    w.append(f"- Bundles SQLite *{v}* "
             f"(build.gradle:{version[0][0] if version else '?'}).")
    if threadsafe:
        w.append(f"- Compiled ={threadsafe[0][1].strip(',').strip()}= "
                 f"(build.gradle:{threadsafe[0][0]}) — serialized mutex mode;"
                 " thread confinement is the caller's design choice, not a"
                 " library gift.")
    w.append("- Open entry points and extension hook (BundledSQLiteDriver.kt):")
    for line_no, text in opens:
        w.append(f"  - ={esc(re.sub(r'\\s+', ' ', text))}= (:{line_no})")
    w.append("- =@OpenFlag= constants (BundledSQLite.kt) — the flags overload is")
    w.append("  what makes read-only and URI opens *possible* at this layer,")
    w.append("  which Room's own open path never uses:")
    w.append("")
    w.append("| Constant | Value | Line |")
    w.append("|---|---|---|")
    for line_no, text in flags:
        m = re.match(r"public const val (\w+): Int = (\S+)", text)
        w.append(f"| ={m.group(1)}= | ={m.group(2)}= | {line_no} |")
    w.append("")
    w.append("** 3. Declared Kotlin targets — the web distinction, precisely")
    w.append("")
    w.append("| Module | Targets (from =androidXMultiplatform=) | js / wasmJs |")
    w.append("|---|---|---|")
    w.append(f"| =sqlite= (interfaces) | {', '.join(sq_targets)} | "
             f"*declared* |")
    w.append(f"| =sqlite-bundled= | {', '.join(sb_targets)} | *absent* |")
    w.append("")
    w.append("The *interface artifact* is universal; the *bundled engine* is")
    w.append("not — and §1 shows the deeper cut: even inside the interface,")
    w.append("=open= is synchronous only in =nonWebMain= while =webMain='s is")
    w.append("=suspend=, so =ebp-sqlite='s synchronous open seam does not port")
    w.append("unchanged (PLAN-refound non-goals). A web target pairs the")
    w.append("=webMain= interface with =sqlite-web='s driver.")
    w.append("")
    w.append("** 4. The Room 3 boundary (what =ebp-sqlite= must never depend on)")
    w.append("")
    w.append("Room 3 remains the right materializer for the Companion-*owned*")
    w.append("typed database (=jetpacs-vroom3=) — every property below is")
    w.append("harmless there and fatal for a schema-generic, wire-declared")
    w.append("layer.  Citations located at generation time:")
    w.append("")
    for title, claim, cites in boundary:
        w.append(f"*** {title}")
        w.append("")
        w.append(claim)
        w.append("")
        for rel, pattern in cites:
            hits = grep(rel, pattern)
            if not hits:
                sys.exit(f"FATAL: boundary citation vanished — {pattern!r} "
                         f"not found in {rel}; re-verify before regenerating")
            for line_no, text in hits[:2]:
                w.append(f"- ={esc(re.sub(r'\\s+', ' ', text))[:90]}=")
                w.append(f"  ={rel.split('/')[-1]}:{line_no}=")
        w.append("")
    open(OUT, "w", encoding="utf-8").write("\n".join(w) + "\n")
    print(f"wrote {OUT} @ {pin_note}")


if __name__ == "__main__":
    main()
