#!/usr/bin/env python3
"""Generate manifest.json from all widget.json files."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from widget_rules import WidgetRuleError, source_hash, validate


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def first_published(widget_json: Path) -> str | None:
    """ISO date of the commit that added the widget, from git history."""
    try:
        out = subprocess.run(
            ["git", "log", "--diff-filter=A", "--format=%cI", "--", str(widget_json)],
            capture_output=True, text=True, check=True,
        ).stdout.split()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return out[-1] if out else None


def main():
    root = Path(__file__).parent.parent
    widgets_dir = root / "Widgets"
    build_dir = root / "build"
    manifest = {"schemaVersion": 2, "widgets": []}

    if not widgets_dir.exists():
        print("No Widgets directory found")
        return

    failed = False
    for widget_dir in sorted(widgets_dir.iterdir()):
        if not (widget_dir / "widget.json").exists():
            continue

        try:
            meta, sources = validate(widget_dir)
        except WidgetRuleError as error:
            for problem in error.problems:
                print(f"  {widget_dir.name}: {problem}")
            failed = True
            continue

        bundle_name = widget_dir.name + ".bundle"
        bundle_zip = build_dir / (bundle_name + ".zip")

        entry = {
            "id": meta["id"],
            "name": meta["name"],
            "author": meta.get("author", "unknown"),
            "description": meta.get("description", ""),
            "iconSymbol": meta.get("iconSymbol", "puzzlepiece"),
            "orientations": meta["orientations"],
            # Slot spans beyond 2 are opt-in; absent means the pre-3x default.
            "maxSlotSpan": meta.get("maxSlotSpan", 2),
            "bundleFilename": bundle_name + ".zip",
            "sourceDirectory": widget_dir.name,
        }

        added_at = first_published(widget_dir / "widget.json")
        if added_at:
            entry["addedAt"] = added_at

        # Feature-level gate: absent means the level-1 baseline every client
        # supports. Declared only when the widget uses newer SDK surface.
        requires_level = meta.get("requiresFeatureLevel")
        if requires_level is not None:
            entry["requiresFeatureLevel"] = requires_level

        entry["sourceHash"] = source_hash(widget_dir, sources)

        if bundle_zip.exists():
            entry["sha256"] = sha256_of_file(bundle_zip)
            entry["bundleSize"] = bundle_zip.stat().st_size

        manifest["widgets"].append(entry)

    if failed:
        print("Manifest not written: fix the widget rule violations above")
        sys.exit(1)

    with open(root / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"Generated manifest with {len(manifest['widgets'])} widget(s)")


if __name__ == "__main__":
    main()
