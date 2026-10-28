#!/usr/bin/env python3
"""Checks that every string the compiler found in the source is in the string catalog,
so nothing ships in English only. Xcode writes what it found to .stringsdata files
under the derived data folder given as the argument; a string with no catalog entry
has no translations, and check_strings.py can't see it. Exits 1 and lists any."""

import json
import pathlib
import re
import sys

# The compiler writes every interpolation as %arg; the catalog has %@, %lld, %.1f…
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|f|\.\d+f|arg)")


def shape(key):
    return PLACEHOLDER.sub("%arg", key)

derived = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/dd")
with open("App/Resources/Localizable.xcstrings", encoding="utf-8") as file:
    catalog = {shape(key) for key in json.load(file)["strings"]}

found = {}
for path in derived.rglob("*.stringsdata"):
    if "VoiceOverAudioSplit" not in str(path) or "Tests" in path.name:
        continue
    with open(path, encoding="utf-8") as file:
        data = json.load(file)
    for key in data.get("tables", {}).get("Localizable", []):
        found.setdefault(shape(key["key"]), pathlib.Path(data.get("source", path.name)).name)

if not found:
    print(f"::error::No .stringsdata files under {derived}; build the app first.")
    sys.exit(1)

missing = sorted((key, source) for key, source in found.items() if key not in catalog)
for key, source in missing:
    print(f"::error::Not in Localizable.xcstrings ({source}): {key[:100]}")
print(f"{len(found)} strings in the source, {len(missing)} missing from the catalog.")
sys.exit(1 if missing else 0)
