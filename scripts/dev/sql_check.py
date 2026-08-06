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


def check_schema() -> None:
    sql_files = sorted(SCHEMA_DIR.glob("*.sql")) if SCHEMA_DIR.exists() else []
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
    for f in sorted(SCHEMA_DIR.glob("*.sql")):
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
    check_embedded_sql()
    print("sql fast-loop: OK")
