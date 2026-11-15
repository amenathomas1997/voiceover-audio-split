#!/usr/bin/env python3
"""Checks the string catalogs: every string that should be translated has Spanish,
French and German, marked translated, with the same placeholders (%@, %lld…) as
the original. Run from the repository root; exits 1 and lists problems if any."""

import json
import re
import sys

LANGUAGES = ("es", "fr", "de")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(@|lld|ld|d|f|\.\d+f)")
POSITIONAL = re.compile(r"%\d+\$")


def placeholders_match(source, translation):
    """Same placeholders, in the same order, unless the translation numbers every one
    (%1$@, %2$lld), which is the only safe way to reorder them."""
    ours, theirs = PLACEHOLDER.findall(source), PLACEHOLDER.findall(translation)
    if sorted(ours) != sorted(theirs):
        return False
    if ours == theirs:
        return True
    return len(POSITIONAL.findall(translation)) == len(theirs)
problems = []

for name in ("Localizable", "InfoPlist"):
    path = f"App/Resources/{name}.xcstrings"
    with open(path, encoding="utf-8") as file:
        catalog = json.load(file)
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        localizations = entry.get("localizations", {})
        source = localizations.get("en", {}).get("stringUnit", {}).get("value", key)
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit")
            if not unit or not unit.get("value"):
                problems.append(f"{name}: no {language} for: {key[:80]}")
            elif unit.get("state") != "translated":
                problems.append(f"{name}: {language} is {unit.get('state')} for: {key[:80]}")
            elif not placeholders_match(source, unit["value"]):
                problems.append(f"{name}: {language} placeholders differ for: {key[:80]}")

for problem in problems:
    print(f"::error::{problem}")
print(f"{len(problems)} problems in the string catalogs.")
sys.exit(1 if problems else 0)
