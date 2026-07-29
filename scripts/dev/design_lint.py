#!/usr/bin/env python3
"""Design-law lint — the static tier of D-1..D-11 (EVALS §4.2).

The law is about rendered output; the full census (D-4 pixel coverage, D-5
star-dust counts, D-6 tilt/glow, D-7 emphasis nodes) needs snapshots and runs
on macOS CI / device. This script is the pre-gate that runs everywhere Python
runs (same T1 posture as the SQL fast-loop): it catches every violation that
is decidable from source — a red hex literal, a badge modifier, a forbidden
word — before a simulator ever boots. Checks it cannot decide are REPORTED as
deferred, never silently skipped (EVALS "no silent gaps").

Exit nonzero on any static violation.
"""
from __future__ import annotations

import colorsys
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP_SOURCES = ROOT / "apps" / "OrbitApp" / "Sources"
TOKENS_JSON = ROOT / "docs" / "evals" / "design" / "tokens.gen.json"
TOKENS_SWIFT = APP_SOURCES / "OrbitDesign" / "Tokens.gen.swift"

failures: list[str] = []
deferred: list[str] = []


def fail(check: str, msg: str) -> None:
    failures.append(f"{check}: {msg}")


def defer(check: str, msg: str) -> None:
    deferred.append(f"{check}: {msg}")


def swift_files() -> list[Path]:
    # user-facing strings also live in the recall/search modules (deck tags,
    # ranking reasons, answer bands) — the copy law follows them
    extra = [ROOT / "Sources" / "OrbitRecall", ROOT / "Sources" / "OrbitSearch"]
    files = sorted(APP_SOURCES.rglob("*.swift"))
    for d in extra:
        files += sorted(d.rglob("*.swift"))
    return files


def strip_comment(line: str) -> str:
    """Drop a trailing // comment when the // isn't inside a string literal
    (approximation: even count of unescaped quotes before it)."""
    idx = 0
    while (idx := line.find("//", idx)) != -1:
        before = line[:idx]
        if len(re.findall(r'(?<!\\)"', before)) % 2 == 0:
            return line[:idx]
        idx += 2
    return line


def strings_in(line: str) -> list[str]:
    # Swift string literals on a code line (comments excluded); good enough
    # for a copy lint.
    return re.findall(r'"((?:[^"\\]|\\.)*)"', strip_comment(line))


# ---------------------------------------------------------------- color maths

def parse_color(value: str):
    """Return (r, g, b, a) in 0..1 from #hex or rgba() token values."""
    value = value.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{6})", value)
    if m:
        h = m.group(1)
        return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (1.0,)
    m = re.fullmatch(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)", value)
    if m:
        r, g, b = (int(m.group(i)) / 255 for i in (1, 2, 3))
        return (r, g, b, float(m.group(4) or 1.0))
    return None


def is_forbidden_red(rgba) -> bool:
    """D-1 forbidden hue band: red-family hues (345°..15°) at meaningful
    saturation/opacity. Warm ambers/oranges (the ember family, hue ≳ 20°)
    stay legal — the ban is on red, not warmth."""
    r, g, b, a = rgba
    if a < 0.05:
        return False
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    hue = h * 360
    return (hue >= 345 or hue <= 15) and s > 0.25 and l > 0.15


# ---------------------------------------------------------------- D-1 no red

def check_d1() -> None:
    tokens = json.loads(TOKENS_JSON.read_text())
    for room, entries in tokens.items():
        for name, value in entries.items():
            rgba = parse_color(value)
            if rgba is None:
                fail("D-1", f"unparseable token color {room}/{name} = {value!r}")
            elif is_forbidden_red(rgba):
                fail("D-1", f"token {room}/{name} = {value} is in the forbidden red band")
    # source-level: no system red, no red-band literals anywhere in app code
    for f in swift_files():
        text = f.read_text()
        for i, line in enumerate(text.splitlines(), 1):
            if re.search(r"\.red\b|Color\.red\b|systemRed", line):
                fail("D-1", f"{f.relative_to(ROOT)}:{i} references a system red color")
            for hexlit in re.findall(r"#([0-9a-fA-F]{6})\b", line):
                rgba = parse_color("#" + hexlit)
                if rgba and is_forbidden_red(rgba):
                    fail("D-1", f"{f.relative_to(ROOT)}:{i} red-band hex literal #{hexlit}")
    defer("D-1", "rendered-pixel sweep runs in the snapshot job (macOS CI)")


# ------------------------------------------------------------- D-2 no badges

def check_d2() -> None:
    for f in swift_files():
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if re.search(r"\.badge\(", line):
                fail("D-2", f"{f.relative_to(ROOT)}:{i} uses .badge() — badges do not exist in Orbit")
            if re.search(r"applicationIconBadgeNumber|setBadgeCount", line):
                fail("D-2", f"{f.relative_to(ROOT)}:{i} sets an app icon badge")
    defer("D-2", "view-hierarchy absence assertion runs in J-3 (XCUITest)")


# ---------------------------------------------------- D-3 two-voices (static)

def check_d3() -> None:
    """Serif may enter the tree only through the memory-voice channel:
    memoryVoice(...) or Tokens.serifFamily. A hard-coded font family name is a
    voice violation waiting to happen."""
    for f in swift_files():
        if f.name == "Tokens.gen.swift":
            continue
        for i, line in enumerate(f.read_text().splitlines(), 1):
            m = re.search(r'\.custom\(\s*"([^"]+)"', line)
            if m:
                fail("D-3", f"{f.relative_to(ROOT)}:{i} hard-codes font family {m.group(1)!r} — go through Tokens")
    defer("D-3", "per-node serif census runs in the snapshot job (macOS CI)")


# --------------------------------------------------------- D-9 true counts

def check_d9() -> None:
    for f in swift_files():
        for i, line in enumerate(f.read_text().splitlines(), 1):
            for s in strings_in(line):
                if re.search(r"\d\+\b", s):
                    fail("D-9", f"{f.relative_to(ROOT)}:{i} string {s!r} looks like a rounded count")
            if re.search(r"min\(\s*\d+\s*,\s*\w*[cC]ount", line):
                fail("D-9", f"{f.relative_to(ROOT)}:{i} clamps a displayed count")


# ---------------------------------------------------- D-10 token conformance

def check_d10() -> None:
    # 1) Tokens.gen.swift must be exactly what gen_tokens.py produces from the
    #    canonical mockup — a hand-edit that drifts from v3-mockup.html fails.
    with tempfile.TemporaryDirectory() as td:
        out = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "dev" / "gen_tokens.py"), "--check"],
            capture_output=True, text=True, cwd=ROOT,
        )
        if out.returncode != 0:
            fail("D-10", "Tokens.gen.swift is stale vs v3-mockup.html — rerun gen_tokens.py\n"
                 + out.stdout + out.stderr)
    # 2) No color literals outside the generated file.
    for f in swift_files():
        if f.name == "Tokens.gen.swift":
            continue
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if re.search(r"Color\(\s*(red:|\.sRGB|hue:|white:)", line):
                fail("D-10", f"{f.relative_to(ROOT)}:{i} constructs a literal Color — use Tokens")
            if re.search(r'Color\(\s*"#', line) or re.search(r'"#[0-9a-fA-F]{6}"', line):
                fail("D-10", f"{f.relative_to(ROOT)}:{i} hex color literal — use Tokens")
    defer("D-10", "rendered radius/font conformance runs in the snapshot job (macOS CI)")


# ------------------------------------------------------------ D-11 copy lint

FORBIDDEN_LEXICON = ["remaining", "overdue", "pending review", "streak"]
# debt-language patterns beyond the four ratified words: guilt framings that
# turn memory into administration (ORBIT.md P10)
DEBT_PATTERNS = [r"you haven'?t\b", r"days since you", r"don'?t forget", r"falling behind"]


def check_d11() -> None:
    for f in swift_files():
        for i, line in enumerate(f.read_text().splitlines(), 1):
            for s in strings_in(line):
                low = s.lower()
                for word in FORBIDDEN_LEXICON:
                    if word in low:
                        fail("D-11", f"{f.relative_to(ROOT)}:{i} forbidden lexicon {word!r} in {s!r}")
                for pat in DEBT_PATTERNS:
                    if re.search(pat, low):
                        fail("D-11", f"{f.relative_to(ROOT)}:{i} debt language in {s!r}")
    defer("D-11", "hedge-preservation half of D-11 is graded at L1 (PIPE-6), already measured")


# ----------------------------------------------------------------- reporting

def main() -> int:
    if not APP_SOURCES.exists():
        print("design_lint: no app sources found", file=sys.stderr)
        return 2
    check_d1()
    check_d2()
    check_d3()
    check_d9()
    check_d10()
    check_d11()
    for name in ("D-4", "D-5", "D-6", "D-7"):
        defer(name, "snapshot/pixel census — macOS CI snapshot job (T2)")
    defer("D-8", "absence-of-placeholder asserted at view-model level (DesignLawTests) + J-6")

    print(f"design_lint: {len(failures)} violation(s)")
    for f in failures:
        print(f"  FAIL {f}")
    print(f"design_lint: {len(deferred)} check(s) graded elsewhere:")
    for d in deferred:
        print(f"  ELSEWHERE {d}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
