#!/usr/bin/env python3
"""Shared widget folder rules for the build, the manifest and PR validation.

Every script that reads a widget folder goes through here, so what gets compiled,
what gets hashed and what gets linted are always the same set of files.

CLI (used by build-widgets.sh):
    widget_rules.py build-info <widget_dir>
prints the bundle id, principal class and each source filename on its own line,
or exits non-zero with the rule violations.
"""
import hashlib
import json
import re
import struct
import sys
import zlib
from pathlib import Path

FOLDER_NAME = re.compile(r"^[A-Za-z0-9-]+$")
WIDGET_ID = re.compile(r"^[a-z0-9][a-z0-9.-]*$")
SWIFT_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SOURCE_FILENAME = re.compile(r"^[A-Za-z0-9_+-]+\.swift$")
VALID_ORIENTATIONS = {"horizontal", "vertical"}
VALID_SLOT_SPANS = (2, 3)
IGNORED_ENTRIES = {".DS_Store"}

# Optional marketplace artwork. Not part of the source hash: changing it never
# offers installed users an update.
PREVIEW_NAME = "preview.png"
PREVIEW_SIZE = (1080, 608)
PREVIEW_MAX_BYTES = 1_500_000
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ANIMATION_CHUNKS = {b"acTL", b"fcTL", b"fdAT"}

# Process spawning and dynamic code loading. Human review is the real boundary;
# this catches the obvious spellings, including the ones the old grep missed.
UNSAFE_PATTERNS = [
    (re.compile(r"\bProcess\s*\("), "Process()"),
    (re.compile(r"\bProcess\s*\.\s*(init|run|launchedProcess)\b"), "Process.init/run"),
    (re.compile(r"\bNSTask\b"), "NSTask"),
    (re.compile(r"\bposix_spawnp?\b"), "posix_spawn"),
    (re.compile(r"\bexec[lv]p?e?\s*\("), "exec*()"),
    (re.compile(r"\bv?fork\s*\("), "fork()"),
    (re.compile(r"(?<![.\w])system\s*\("), "system()"),
    (re.compile(r"\bpopen\s*\("), "popen()"),
    (re.compile(r"\bdlopen\b"), "dlopen"),
    (re.compile(r"\bdlsym\b"), "dlsym"),
]


class WidgetRuleError(Exception):
    """One or more rule violations for a widget folder."""

    def __init__(self, problems):
        super().__init__("; ".join(problems))
        self.problems = problems


def load_meta(widget_dir: Path) -> dict:
    """Parses widget.json, requiring a JSON object."""
    widget_json = widget_dir / "widget.json"
    if widget_json.is_symlink() or not widget_json.is_file():
        raise WidgetRuleError(["widget.json is missing or not a regular file"])
    try:
        meta = json.loads(widget_json.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise WidgetRuleError([f"widget.json is not valid JSON: {error}"])
    if not isinstance(meta, dict):
        raise WidgetRuleError(["widget.json must be a JSON object"])
    return meta


def source_names(widget_dir: Path, meta: dict) -> list[str]:
    """The `sources` list, each entry a plain .swift filename that is a regular
    file at the top level of the widget folder. No paths, no symlinks."""
    sources = meta.get("sources")
    if not isinstance(sources, list) or not sources:
        raise WidgetRuleError(["'sources' must be a non-empty list of .swift filenames"])
    problems = []
    seen = set()
    for name in sources:
        if not isinstance(name, str) or not SOURCE_FILENAME.match(name):
            problems.append(f"source {name!r} must be a plain .swift filename (no folders or '..')")
            continue
        if name in seen:
            problems.append(f"source {name!r} is listed twice")
            continue
        seen.add(name)
        path = widget_dir / name
        if path.is_symlink():
            problems.append(f"source {name!r} is a symlink")
        elif not path.is_file():
            problems.append(f"source {name!r} does not exist")
    if problems:
        raise WidgetRuleError(problems)
    return list(sources)


def check_metadata(widget_dir: Path, meta: dict) -> list[str]:
    """Fields that end up in Info.plist, the manifest or the client's decoder."""
    problems = []
    if not FOLDER_NAME.match(widget_dir.name):
        problems.append("folder name may only contain letters, numbers and hyphens")
    widget_id = meta.get("id")
    if not isinstance(widget_id, str) or not WIDGET_ID.match(widget_id):
        problems.append("'id' must be lowercase letters, numbers, dots and hyphens")
    principal = meta.get("principalClass")
    if not isinstance(principal, str) or not SWIFT_IDENTIFIER.match(principal):
        problems.append("'principalClass' must be a Swift type name")
    for field in ("name", "description", "author", "iconSymbol"):
        if field in meta and not isinstance(meta[field], str):
            problems.append(f"'{field}' must be a string")
    if not isinstance(meta.get("name"), str) or not meta["name"].strip():
        problems.append("'name' is required")
    orientations = meta.get("orientations")
    if not isinstance(orientations, list) or not orientations:
        problems.append("'orientations' must list at least one of: horizontal, vertical")
    elif any(value not in VALID_ORIENTATIONS for value in orientations):
        problems.append("'orientations' may only contain 'horizontal' and 'vertical'")
    if meta.get("maxSlotSpan", 2) not in VALID_SLOT_SPANS:
        problems.append("'maxSlotSpan' must be 2 or 3")
    level = meta.get("requiresFeatureLevel")
    if level is not None and (not isinstance(level, int) or isinstance(level, bool) or level < 1):
        problems.append("'requiresFeatureLevel' must be a positive integer")
    return problems


def check_folder_contents(widget_dir: Path, sources: list[str]) -> list[str]:
    """Only widget.json, the listed sources and preview.png may live in a widget folder."""
    allowed = {"widget.json", PREVIEW_NAME, *sources}
    problems = []
    for entry in sorted(widget_dir.iterdir()):
        if entry.name in IGNORED_ENTRIES:
            continue
        if entry.is_symlink():
            problems.append(f"{entry.name} is a symlink")
        elif entry.is_dir():
            problems.append(f"{entry.name}/ is a folder; widgets may not contain folders")
        elif entry.name not in allowed:
            problems.append(f"{entry.name} is not widget.json, {PREVIEW_NAME} or a listed source")
    return problems


def lint_sources(widget_dir: Path, sources: list[str]) -> list[str]:
    """Flags unsafe API use in exactly the files that get compiled."""
    problems = []
    for name in sources:
        text = (widget_dir / name).read_text(errors="replace")
        for number, line in enumerate(text.splitlines(), start=1):
            for pattern, label in UNSAFE_PATTERNS:
                if pattern.search(line):
                    problems.append(f"{name}:{number} uses {label}")
    return problems


def check_png(path: Path, size: tuple[int, int] = PREVIEW_SIZE, max_bytes: int = PREVIEW_MAX_BYTES) -> list[str]:
    """Structural PNG check without decoding pixels: signature, IHDR first, every
    chunk CRC, no animation chunks, IEND last with nothing after it, exact size."""
    name = path.name
    if path.is_symlink() or not path.is_file():
        return [f"{name} is not a regular file"]
    data = path.read_bytes()
    if len(data) > max_bytes:
        return [f"{name} is {len(data)} bytes; the limit is {max_bytes}"]
    if not data.startswith(PNG_SIGNATURE):
        return [f"{name} is not a PNG file"]
    position = len(PNG_SIGNATURE)
    dimensions = None
    ended = False
    while position + 12 <= len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        body_end = position + 8 + length
        if body_end + 4 > len(data):
            return [f"{name} is truncated inside a {kind!r} chunk"]
        body = data[position + 8:body_end]
        crc = struct.unpack(">I", data[body_end:body_end + 4])[0]
        if zlib.crc32(kind + body) & 0xFFFFFFFF != crc:
            return [f"{name} has a corrupt {kind!r} chunk"]
        if dimensions is None:
            if kind != b"IHDR" or length != 13:
                return [f"{name} does not start with an IHDR chunk"]
            dimensions = struct.unpack(">II", body[:8])
        if kind in ANIMATION_CHUNKS:
            return [f"{name} is animated; previews must be a still image"]
        position = body_end + 4
        if kind == b"IEND":
            ended = True
            break
    if not ended:
        return [f"{name} has no IEND chunk"]
    if position != len(data):
        return [f"{name} has data after its IEND chunk"]
    if dimensions != size:
        return [f"{name} is {dimensions[0]}x{dimensions[1]}; it must be {size[0]}x{size[1]} pixels"]
    return []


def check_preview(widget_dir: Path) -> list[str]:
    """Validates preview.png when the widget ships one."""
    path = widget_dir / PREVIEW_NAME
    if not path.exists() and not path.is_symlink():
        return []
    return check_png(path)


def validate(widget_dir: Path) -> tuple[dict, list[str]]:
    """Runs every rule; returns the metadata and the ordered source list."""
    if widget_dir.is_symlink():
        raise WidgetRuleError(["widget folder is a symlink"])
    meta = load_meta(widget_dir)
    problems = check_metadata(widget_dir, meta)
    try:
        sources = source_names(widget_dir, meta)
    except WidgetRuleError as error:
        raise WidgetRuleError(problems + error.problems)
    problems += check_folder_contents(widget_dir, sources)
    problems += check_preview(widget_dir)
    problems += lint_sources(widget_dir, sources)
    if problems:
        raise WidgetRuleError(problems)
    return meta, sources


def source_hash(widget_dir: Path, sources: list[str]) -> str:
    """SHA-256 over widget.json and the compiled sources, in filename order.

    Byte-identical to the previous top-level `.swift`/`.json` digest for every
    folder that passes `check_folder_contents`, so switching to it badges nothing.
    """
    h = hashlib.sha256()
    for name in sorted(["widget.json", *sources]):
        h.update(name.encode())
        h.update((widget_dir / name).read_bytes())
    return h.hexdigest()


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "build-info":
        print("usage: widget_rules.py build-info <widget_dir>", file=sys.stderr)
        return 2
    widget_dir = Path(argv[2])
    try:
        meta, sources = validate(widget_dir)
    except WidgetRuleError as error:
        for problem in error.problems:
            print(f"  RULE: {problem}", file=sys.stderr)
        return 1
    print(meta["id"])
    print(meta["principalClass"])
    for name in sources:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
