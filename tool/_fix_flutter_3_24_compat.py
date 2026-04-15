#!/usr/bin/env python3
"""Compat Flutter 3.24 (FVM): withOpacity vs withValues, Color.value vs toARGB32,
DropdownButtonFormField value vs initialValue."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def _match_paren_block(text: str, open_idx: int) -> tuple[int, int] | None:
    """open_idx points at '('. Returns (start, end_exclusive) of outer call, or None."""
    depth = 0
    i = open_idx
    n = len(text)
    in_sq = in_dq = in_tri = False
    escape = False
    while i < n:
        c = text[i]
        if escape:
            escape = False
            i += 1
            continue
        if c == "\\" and (in_sq or in_dq or in_tri):
            escape = True
            i += 1
            continue
        if not in_sq and not in_dq and not in_tri:
            if c == "'" and text.startswith("'''", i):
                in_tri = True
                i += 3
                continue
            if c == '"':
                in_dq = True
                i += 1
                continue
            if c == "'":
                in_sq = True
                i += 1
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return (open_idx, i + 1)
            i += 1
            continue
        if in_tri:
            if text.startswith("'''", i):
                in_tri = False
                i += 3
            else:
                i += 1
            continue
        if in_dq:
            if c == '"':
                in_dq = False
            i += 1
            continue
        if in_sq:
            if c == "'":
                in_sq = False
            i += 1
            continue
        i += 1
    return None


def fix_dropdown_initial_value_blocks(text: str) -> str:
    key = "DropdownButtonFormField"
    out: list[str] = []
    pos = 0
    pat = re.compile(r"DropdownButtonFormField\s*(?:<[^>]*>)?\s*\(")
    while True:
        m = pat.search(text, pos)
        if not m:
            out.append(text[pos:])
            break
        out.append(text[pos : m.start()])
        open_paren = m.end() - 1
        span = _match_paren_block(text, open_paren)
        if not span:
            out.append(text[m.start() :])
            break
        _, end = span
        block = text[m.start() : end]
        if "initialValue:" in block:
            block = block.replace("initialValue:", "value:")
        out.append(block)
        pos = end
    return "".join(out)


def main() -> int:
    root = Path(__file__).resolve().parents[1] / "lib"
    if not root.is_dir():
        print("lib/ not found", file=sys.stderr)
        return 1
    changed_files = 0
    for path in sorted(root.rglob("*.dart")):
        raw = path.read_text(encoding="utf-8")
        t = raw
        t = re.sub(r"\.withValues\(\s*alpha:\s*([^)]+)\)", r".withOpacity(\1)", t)
        t = t.replace(".toARGB32()", ".value")
        t = fix_dropdown_initial_value_blocks(t)
        if t != raw:
            path.write_text(t, encoding="utf-8")
            changed_files += 1
            print(path.relative_to(root.parent))
    print(f"Done. Updated {changed_files} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
