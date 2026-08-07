#!/usr/bin/env python3
"""SQL fast-loop verifier.

The schema, triggers, and read-model SQL in Sources/OrbitStore/Resources/ are the
trust core of Orbit. This rig executes them against the *same engine* (SQLite)
without needing a Swift toolchain, so ledger correctness has a fast local loop.
The Swift test suite (OrbitInvariantTests) re-runs the same properties through
the production code path in CI — this file is a developer accelerator, never the
gate of record.

Grows with Phase 2: schema load, trigger denial tests, bitemporal queries,
read-model rebuild equivalence.
"""
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCHEMA_DIR = ROOT / "Sources" / "OrbitStore" / "Resources"


def check_engine() -> None:
    con = sqlite3.connect(":memory:")
    ver = con.execute("select sqlite_version()").fetchone()[0]
    fts5 = bool(
        con.execute(
            "select count(*) from pragma_compile_options where compile_options='ENABLE_FTS5'"
        ).fetchone()[0]
    )
    if not fts5:
        # Some builds omit the compile-option row; probe directly.
        try:
            con.execute("create virtual table _f using fts5(x)")
            fts5 = True
        except sqlite3.OperationalError:
            fts5 = False
    print(f"sqlite {ver}, fts5={'yes' if fts5 else 'NO'}")
    if not fts5:
        sys.exit("FATAL: FTS5 unavailable in this SQLite build")


def schema_files() -> list:
    """Base schema only. Migrations are applied to databases that already have
    data, never to a fresh one (a fresh database is born at latestVersion), so
    they must not be swept into the plain load."""
    if not SCHEMA_DIR.exists():
        return []
    return sorted(f for f in SCHEMA_DIR.glob("*.sql") if not f.name.startswith("migration_"))


def migration_files() -> list:
    if not SCHEMA_DIR.exists():
        return []
    return sorted(SCHEMA_DIR.glob("migration_*.sql"))


def check_schema() -> None:
    sql_files = schema_files()
    if not sql_files:
        print("schema: no .sql resources yet (pre-Phase-2)")
        return
    con = sqlite3.connect(":memory:")
    con.executescript("PRAGMA foreign_keys=ON;")
    for f in sql_files:
        try:
            con.executescript(f.read_text())
        except sqlite3.Error as e:
            sys.exit(f"FATAL: {f.name}: {e}")
    n = con.execute("select count(*) from sqlite_master where type='table'").fetchone()[0]
    print(f"schema: {len(sql_files)} file(s) loaded cleanly, {n} tables")

    # Phase-2+ property checks live in scripts/dev/sql_properties.py
    props = ROOT / "scripts" / "dev" / "sql_properties.py"
    if props.exists():
        import subprocess
        subprocess.run([sys.executable, str(props)], check=True)


def check_migrations() -> None:
    """Migrations must work on a database that does NOT yet have what they add,
    be safe to re-run on one that does, and leave the INV-4 rebuild intact
    (FIELD-NOTES FN-17). Abdoul's phone holds real memos, so a migration that
    only works on a fresh database is worse than no migration at all.

    A fresh database already contains everything the migrations add, so each is
    tested against a database with its objects dropped first — the closest
    faithful stand-in for the older database it will actually meet."""
    import re

    migrations = migration_files()
    if not migrations:
        print("migrations: none")
        return

    for f in migrations:
        sql = f.read_text()
        created = re.findall(r"CREATE\s+(TABLE|INDEX)\s+(?:IF NOT EXISTS\s+)?(\w+)", sql, re.I)
        if not created:
            sys.exit(f"FATAL: {f.name} creates nothing — a migration that adds no object "
                     f"needs its check written by hand")

        con = sqlite3.connect(":memory:")
        con.executescript("PRAGMA foreign_keys=ON;")
        for s in schema_files():
            con.executescript(s.read_text())

        # stand in for the older database: remove what this migration adds
        for kind, name in created:
            con.executescript(f"DROP {kind} IF EXISTS {name};")
        try:
            con.executescript(sql)
        except sqlite3.Error as e:
            sys.exit(f"FATAL: {f.name} does not apply to a database without it: {e}")
        for kind, name in created:
            row = con.execute(
                "SELECT COUNT(*) FROM sqlite_master WHERE type=? AND name=?",
                (kind.lower(), name)).fetchone()[0]
            if row != 1:
                sys.exit(f"FATAL: {f.name} claims to create {kind} {name}, and did not")

        # re-running it must be a no-op, because a version bump that fails
        # mid-way will be retried on next launch
        try:
            con.executescript(sql)
        except sqlite3.Error as e:
            sys.exit(f"FATAL: {f.name} is not idempotent: {e}")

        # and the read models must still rebuild from the log afterwards (INV-4)
        rebuild = SCHEMA_DIR / "004_rebuild_readmodels.sql"
        if rebuild.exists():
            try:
                con.executescript(rebuild.read_text())
            except sqlite3.Error as e:
                sys.exit(f"FATAL: INV-4 rebuild broken after {f.name}: {e}")
        print(f"  ✓ {f.name}: applies, is idempotent, INV-4 rebuild intact")
    print(f"migrations: {len(migrations)} checked")


SQL_START = r"(SELECT|INSERT|UPDATE|DELETE|WITH)\b"
# ...and a real statement also carries a second clause keyword. Without this a
# bare English word in a Swift literal ("with" lives in the search stopword set)
# is harvested as SQL and fails to prepare.
SQL_BODY = r"\b(FROM|INTO|SET|VALUES|AS|WHERE)\b"
# A Swift single-line string literal, escapes handled: "…\"…"
SINGLE_LINE_LITERAL = r'"((?:[^"\\\n]|\\.)*)"'


def looks_like_sql(body: str) -> bool:
    import re
    return bool(re.match(SQL_START, body, re.I) and re.search(SQL_BODY, body, re.I))


def harvest_sql(text: str):
    """Yield every SQL statement embedded in one Swift source.

    Both literal forms are harvested — triple-quoted blocks AND single-line
    literals. Only harvesting the former checked 23% of the SQL in the tree
    (FIELD-NOTES FN-4): most of StoreReader and every ad-hoc app lookup is
    written on one line, so a typo there reached the device untouched.

    Interpolated SQL is skipped by construction: `\\(` cannot be prepared, and
    it is skipped up front rather than after a failure so the reported count
    means what it says.
    """
    import re

    # take triple-quoted blocks first, then blank them so the single-line pass
    # cannot re-match fragments of their contents
    for m in re.finditer(r'"""\n(.*?)"""', text, re.S):
        body = m.group(1).strip()
        if looks_like_sql(body) and "\\(" not in body:
            yield body
    text = re.sub(r'""".*?"""', '""', text, flags=re.S)

    for m in re.finditer(SINGLE_LINE_LITERAL, text):
        body = m.group(1).strip()
        if looks_like_sql(body) and "\\(" not in body:
            yield body


def check_embedded_sql() -> None:
    """Every SQL statement embedded in Swift sources must at least PREPARE
    against the real schema — catches phantom columns/tables at T1 (this class
    of bug has appeared twice: a query against a `reconstructed` column that
    doesn't exist, and the single-line blind spot of FN-4). EXPLAIN compiles
    without executing."""
    con = sqlite3.connect(":memory:")
    con.executescript("PRAGMA foreign_keys=ON;")
    for f in schema_files():
        if "rebuild" not in f.name:
            con.executescript(f.read_text())

    swift_files = sorted((ROOT / "Sources").rglob("*.swift")) \
        + sorted((ROOT / "apps").rglob("*.swift"))
    checked = failed = 0
    for f in swift_files:
        for body in harvest_sql(f.read_text()):
            checked += 1
            try:
                con.execute("EXPLAIN " + body, tuple([None] * body.count("?")))
            except sqlite3.Error as e:
                failed += 1
                print(f"  EMBEDDED-SQL FAIL {f.relative_to(ROOT)}: {e}\n    {body.splitlines()[0]}…")
    print(f"embedded sql: {checked} statement(s) prepared, {failed} failed")
    if failed:
        sys.exit("FATAL: embedded SQL does not prepare against the schema")


if __name__ == "__main__":
    check_engine()
    check_schema()
    check_migrations()
    check_embedded_sql()
    print("sql fast-loop: OK")
