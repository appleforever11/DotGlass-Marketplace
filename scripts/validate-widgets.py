#!/usr/bin/env python3
"""Validate every widget folder against the shared rules in widget_rules.py.

Runs in CI before anything is compiled. Prints GitHub error annotations and
exits non-zero on any violation.
"""
import sys
from pathlib import Path

from widget_rules import WidgetRuleError, validate


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    widgets_dir = root / "Widgets"
    failed = False
    ids: dict[str, str] = {}

    for widget_dir in sorted(widgets_dir.iterdir()):
        if widget_dir.name in (".DS_Store",):
            continue
        relative = widget_dir.relative_to(root)
        if widget_dir.is_symlink() or not widget_dir.is_dir():
            print(f"::error file={relative}::Widgets/ may only contain widget folders")
            failed = True
            continue
        if not (widget_dir / "widget.json").exists():
            if any(entry.name != ".DS_Store" for entry in widget_dir.iterdir()):
                print(f"::error file={relative}::Widget folder has no widget.json")
                failed = True
            continue
        try:
            meta, _ = validate(widget_dir)
        except WidgetRuleError as error:
            for problem in error.problems:
                print(f"::error file={relative}/widget.json::{problem}")
            failed = True
            continue
        widget_id = meta["id"]
        if widget_id in ids:
            print(f"::error file={relative}/widget.json::id '{widget_id}' is already used by {ids[widget_id]}")
            failed = True
        ids[widget_id] = widget_dir.name
        print(f"ok  {widget_dir.name} ({widget_id})")

    if failed:
        return 1
    print(f"All {len(ids)} widgets pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
