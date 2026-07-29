#!/usr/bin/env python3
"""D-10 source of truth: parse the CSS custom properties out of
docs/prototype/v3-mockup.html and generate the OrbitDesign token file.
The mockup stays canonical; generated Swift carries a DO-NOT-EDIT header;
design lint diffs rendered values back against the JSON dump.

`--check`: regenerate in memory and diff against the committed files instead
of writing — exit 1 if either is stale (design_lint.py's D-10 gate).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SRC = ROOT / "docs" / "prototype" / "v3-mockup.html"
SWIFT_OUT = ROOT / "apps" / "OrbitApp" / "Sources" / "OrbitDesign" / "Tokens.gen.swift"
JSON_OUT = ROOT / "docs" / "evals" / "design" / "tokens.gen.json"

html = SRC.read_text()

def block(cls):
    m = re.search(r"\." + cls + r"\{(.*?)\}", html, re.S)
    props = {}
    for line in m.group(1).split(";"):
        line = re.sub(r"/\*.*?\*/", "", line, flags=re.S).strip()
        if line.startswith("--"):
            k, _, v = line.partition(":")
            props[k[2:].strip()] = v.strip()
    return props

day, night = block("day"), block("night")

def hex_to_rgba(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (r / 255, g / 255, b / 255, 1.0)

def parse_color(v):
    v = v.strip()
    if v.startswith("#"):
        return hex_to_rgba(v)
    m = re.match(r"rgba?\(([\d.]+),([\d.]+),([\d.]+)(?:,([\d.]+))?\)", v.replace(" ", ""))
    if m:
        r, g, b = (float(m.group(i)) / 255 for i in (1, 2, 3))
        a = float(m.group(4)) if m.group(4) else 1.0
        return (r, g, b, a)
    return None

COLOR_KEYS = ["room", "paper", "paper-edge", "note", "note-edge", "ink", "ink-muted",
              "ink-faint", "ember", "ember-wash", "ember-ink", "note-ink",
              "portrait-bg", "pill-bg", "pill-edge"]

def swift_name(key):
    parts = key.split("-")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])

lines = [
    "// GENERATED from docs/prototype/v3-mockup.html by scripts/dev/gen_tokens.py.",
    "// DO NOT EDIT — the mockup's CSS custom properties are canonical (DESIGN.md §3, D-10).",
    "import SwiftUI",
    "",
    "/// One conceptual token, two lights (§2: the ember continuum et al.).",
    "public struct RoomColor: Sendable {",
    "    public let day: Color",
    "    public let night: Color",
    "    public func callAsFunction(_ room: Room) -> Color { room == .day ? day : night }",
    "}",
    "",
    "public enum Room: String, Sendable { case day, night }",
    "",
    "public enum Tokens {",
]
data = {"day": {}, "night": {}}
for key in COLOR_KEYS:
    d = parse_color(day.get(key, "")) if day.get(key) else None
    n = parse_color(night.get(key, "")) if night.get(key) else None
    if d is None or n is None:
        continue
    data["day"][key] = day[key]
    data["night"][key] = night[key]
    lines.append(f"    public static let {swift_name(key)} = RoomColor(")
    lines.append(f"        day: Color(.sRGB, red: {d[0]:.4f}, green: {d[1]:.4f}, blue: {d[2]:.4f}, opacity: {d[3]:.3f}),")
    lines.append(f"        night: Color(.sRGB, red: {n[0]:.4f}, green: {n[1]:.4f}, blue: {n[2]:.4f}, opacity: {n[3]:.3f}))")

lines += [
    "",
    "    // Geometry constants (DESIGN.md §3.5) — from the mockup's --radius-* and layout CSS.",
    "    public static let radiusCard: CGFloat = 13",
    "    public static let radiusPortrait: CGFloat = 12",
    "    public static let radiusPill: CGFloat = 22",
    "    public static let screenPaddingTop: CGFloat = 24",
    "    public static let screenPaddingSide: CGFloat = 16",
    "    public static let gridGap: CGFloat = 9",
    "    public static let tilePaddingV: CGFloat = 13",
    "    public static let tilePaddingH: CGFloat = 14",
    "    public static let noteTiltDegrees: Double = 0.4   // day only; nothing tilts in the sky",
    "",
    "    // The two voices (§4): serif = memory, sans = interface.",
    "    public static let serifFamily = \"Iowan Old Style\"",
    "}",
]
swift_text = "\n".join(lines) + "\n"
json_text = json.dumps(data, indent=1) + "\n"

if "--check" in sys.argv:
    stale = []
    if not SWIFT_OUT.exists() or SWIFT_OUT.read_text() != swift_text:
        stale.append(str(SWIFT_OUT.relative_to(ROOT)))
    if not JSON_OUT.exists() or JSON_OUT.read_text() != json_text:
        stale.append(str(JSON_OUT.relative_to(ROOT)))
    if stale:
        print("tokens STALE vs v3-mockup.html: " + ", ".join(stale))
        sys.exit(1)
    print(f"tokens: {len(data['day'])} colors × 2 rooms — in sync with the mockup")
    sys.exit(0)

SWIFT_OUT.parent.mkdir(parents=True, exist_ok=True)
SWIFT_OUT.write_text(swift_text)
JSON_OUT.parent.mkdir(parents=True, exist_ok=True)
JSON_OUT.write_text(json_text)
print(f"tokens: {len(data['day'])} colors × 2 rooms → {SWIFT_OUT.relative_to(ROOT)}")
