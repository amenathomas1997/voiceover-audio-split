#!/usr/bin/env python3
"""Checks the string catalogs: every string that should be translated has Spanish,
French and German, marked translated, with the same placeholders (%@, %lld…) as
the original. Counted phrases ("1 minute", "5 minutes") keep one wording for one and
one for several, in English too; every wording is checked the same way.
Run from the repository root; exits 1 and lists problems if any."""

import json
import re
import sys

LANGUAGES = ("es", "fr", "de")
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|f|\.\d+f)")
POSITIONAL = re.compile(r"%\d+\$")
SUBSTITUTION = re.compile(r"%#@(\w+)@")
# In Siri phrases (AppShortcuts): ${applicationName}, ${command}.
TOKEN = re.compile(r"\$\{\w+\}")


def kinds(text):
    return [kind for _, kind in PLACEHOLDER.findall(text)]


def placeholders_match(source, translation):
    """Same placeholders, in the same order, unless the translation numbers every one
    (%1$@, %2$lld), which is the only safe way to reorder them."""
    if sorted(TOKEN.findall(source)) != sorted(TOKEN.findall(translation)):
        return False
    ours, theirs = kinds(source), kinds(translation)
    if sorted(ours) != sorted(theirs):
        return False
    if ours == theirs:
        return True
    return len(POSITIONAL.findall(translation)) == len(theirs)


def unit_problem(unit):
    """What's wrong with one piece of text, or None."""
    if not unit or not unit.get("value"):
        return "no text"
    if unit.get("state") != "translated":
        return f"is {unit.get('state')}"
    return None


def numbered(text, expected):
    """Whether every placeholder in the text is numbered and of the kind the original has
    in that place. Returns the numbers used, or None."""
    used = set()
    for number, kind in PLACEHOLDER.findall(text):
        if not number or not 1 <= int(number) <= len(expected) or expected[int(number) - 1] != kind:
            return None
        used.add(int(number))
    return used


def problems_in(key, localization, source):
    """Problems with one language's entry for a string."""
    if not localization:
        return ["no text"]
    expected = kinds(key)
    found = []
    if "substitutions" in localization:
        # A sentence that points to its counted parts: "%#@files@ in %#@folders@".
        main = localization.get("stringUnit")
        if unit_problem(main):
            return [unit_problem(main)]
        names = SUBSTITUTION.findall(main["value"])
        parts = localization["substitutions"]
        if sorted(set(names)) != sorted(parts):
            return ["counted parts don't match the sentence"]
        used = numbered(SUBSTITUTION.sub("", main["value"]), expected)
        if used is None:
            return ["placeholders in the sentence must be numbered and of the right kind"]
        for name, part in parts.items():
            number = part.get("argNum", 0)
            if not 1 <= number <= len(expected) or expected[number - 1] != part.get("formatSpecifier"):
                found.append(f"counted part {name} points to the wrong placeholder")
                continue
            used.add(number)
            forms = part.get("variations", {}).get("plural", {})
            if "other" not in forms or "one" not in forms:
                found.append(f"counted part {name} needs wording for one and for several")
            for form, value in forms.items():
                problem = unit_problem(value.get("stringUnit"))
                if problem:
                    found.append(f"counted part {name} ({form}) {problem}")
                    continue
                text = value["stringUnit"]["value"]
                inside = numbered(text.replace("%arg", ""), expected)
                if inside is None or text.count("%arg") > 1:
                    found.append(f"counted part {name} ({form}) has wrong placeholders")
                else:
                    used |= inside
        if not found and used != set(range(1, len(expected) + 1)):
            found.append("not every placeholder is used")
        return found
    if "variations" in localization:
        # One wording for one, one for several.
        forms = localization["variations"].get("plural", {})
        if "other" not in forms or "one" not in forms:
            return ["needs wording for one and for several"]
        for form, value in forms.items():
            problem = unit_problem(value.get("stringUnit"))
            if problem:
                found.append(f"({form}) {problem}")
            elif not placeholders_match(key, value["stringUnit"]["value"]):
                found.append(f"({form}) placeholders differ")
        return found
    unit = localization.get("stringUnit")
    if unit_problem(unit):
        return [unit_problem(unit)]
    if not placeholders_match(source, unit["value"]):
        return ["placeholders differ"]
    return []


problems = []

for name in ("Localizable", "InfoPlist", "AppShortcuts"):
    path = f"App/Resources/{name}.xcstrings"
    with open(path, encoding="utf-8") as file:
        catalog = json.load(file)
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        localizations = entry.get("localizations", {})
        english = localizations.get("en", {})
        source = english.get("stringUnit", {}).get("value", key)
        counted = any("variations" in localizations.get(language, {}) or "substitutions" in localizations.get(language, {})
                      for language in LANGUAGES + ("en",))
        for language in LANGUAGES + (("en",) if counted else ()):
            for problem in problems_in(key, localizations.get(language), key if counted else source):
                problems.append(f"{name}: {language} {problem} for: {key[:80]}")

for problem in problems:
    print(f"::error::{problem}")
print(f"{len(problems)} problems in the string catalogs.")
sys.exit(1 if problems else 0)
