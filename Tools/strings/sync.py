#!/usr/bin/env python3
"""Syncs the string catalogs with the strings the code uses.

    Tools/strings/sync.py --objroot <OBJROOT> --configuration Debug
    Tools/strings/sync.py --check-translations de

`make strings` is the usual way in: it builds for macOS and the iOS Simulator
first, and passes the build's OBJROOT. `make strings-check` then runs the second
form, which syncs nothing and fails, naming each one, on a key without a
translation into that language: one that has none, one whose translation is not
yet in state "translated", and one with plural variants in English but not in
the translation.

The compiler records every localizable string it type-checks in a .stringsdata
file per source file (SWIFT_EMIT_LOC_STRINGS, project.yml). `xcstringstool sync`
adds the strings it finds there to a catalog, removes the untranslated ones it
does not find and marks the translated ones stale; xcodebuild never does this
itself, only Xcode's editor does. The sync then removes the stale keys too, so
`make strings-check` fails on a catalog that still has one (#863). Only a key
the sync extracted can go stale: a key added by hand ("manual") is left alone.
Both platforms' builds are read, so a string inside `#if os(iOS)` is found too,
and the Debug configuration's, so one inside `#if DEBUG` is.

The App Shortcuts' phrases are not the compiler's: the App Intents metadata step
records them in a file of its own, ExtractedAppShortcutsMetadata.stringsdata, in
an AppShortcuts table that `xcstringstool sync` puts in AppShortcuts.xcstrings,
along with the intents' parameter summaries, which go in Localizable.xcstrings.
The sync reads it with the rest; each catalog takes the table it is named for.

Only the given configuration's files are read, and only those named after a
source file that still exists (and the App Shortcuts' file): DerivedData keeps
the .stringsdata of a deleted file, and of every other configuration ever built,
and either would keep a removed string from going stale. Of one platform's files
for the same source, only the newest is read: an architecture an earlier build
had and the latest did not keeps its old file too.

Python 3.9 or later, standard library only.
"""

import argparse
import json
import re
import subprocess
from pathlib import Path

# Each catalog, the target whose strings it holds, and that target's sources.
CATALOGS = [
    ("App/RFCReader/Localizable.xcstrings", "RFCReader", "App/RFCReader"),
    ("App/RFCReader/AppShortcuts.xcstrings", "RFCReader", "App/RFCReader"),
    (
        "Packages/RFCReaderKit/Sources/RFCReaderKit/Resources/Localizable.xcstrings",
        "RFCReaderKit",
        "Packages/RFCReaderKit/Sources/RFCReaderKit",
    ),
]

# Catalogs no build extracts, kept by hand: checked for translations, never synced.
HAND_KEPT_CATALOGS = ["App/RFCReader/InfoPlist.xcstrings"]

# What the App Intents metadata step names its record of the App Shortcuts.
APP_SHORTCUTS_STRINGS = "ExtractedAppShortcutsMetadata"

# The platforms `make strings` builds, as the suffix of a configuration's
# directory: none for macOS.
PLATFORM_SUFFIXES = ["", "-iphonesimulator"]


def strings_data(objroot: Path, configuration: str, target: str, sources: Path) -> list[Path]:
    source_names = {path.stem for path in sources.rglob("*.swift")} | {APP_SHORTCUTS_STRINGS}
    found = []
    for suffix in PLATFORM_SUFFIXES:
        directory = objroot / f"{target}.build" / f"{configuration}{suffix}"
        newest: dict[str, Path] = {}
        for path in directory.glob("*.build/Objects-normal/*/*.stringsdata"):
            if path.stem not in source_names:
                continue
            kept = newest.get(path.name)
            if kept is None or path.stat().st_mtime > kept.stat().st_mtime:
                newest[path.name] = path
        if not newest:
            # Without one platform's strings, the sync would take its translated
            # keys for removed ones and delete them.
            raise SystemExit(f"no .stringsdata for {target} in {directory}: build first")
        found += newest.values()
    return sorted(found)


def remove_stale(catalog: Path) -> None:
    """Removes the keys `xcstringstool sync` marked stale from `catalog`, written
    back as the sync writes it."""
    text = catalog.read_text()
    document = json.loads(text)
    strings = document["strings"]
    stale = [key for key, entry in strings.items() if entry.get("extractionState") == "stale"]
    if not stale:
        return
    for key in stale:
        del strings[key]
    written = json.dumps(document, indent=2, separators=(",", " : "), ensure_ascii=False)
    # The sync writes an empty object, a key added but not yet translated, open
    # over a blank line: `"key" : {`, ``, `}`.
    written = re.sub(r"^( *)(.*) : \{\}(,?)$", r"\1\2 : {\n\n\1}\3", written, flags=re.MULTILINE)
    if text.endswith("\n"):
        written += "\n"
    catalog.write_text(written)


def untranslated(catalog: Path, language: str) -> list[str]:
    """The keys of `catalog` without a finished `language` translation."""
    document = json.loads(catalog.read_text())
    source = document["sourceLanguage"]
    missing = []
    for key, entry in document["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        translation = localizations.get(language)
        units = units_of(translation) if translation else []
        pluralized = "plural" in localizations.get(source, {}).get("variations", {})
        if (
            not units
            or any(unit.get("state") != "translated" for unit in units)
            or (pluralized and "plural" not in translation.get("variations", {}))
        ):
            missing.append(key)
    return missing


def units_of(localization: dict) -> list[dict]:
    """A localization's units: its string or string set, every variant's, and every
    substitution's."""
    units = [localization[kind] for kind in ("stringUnit", "stringSet") if kind in localization]
    for variants in localization.get("variations", {}).values():
        for variant in variants.values():
            units += units_of(variant)
    for substitution in localization.get("substitutions", {}).values():
        units += units_of(substitution)
    return units


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--objroot", type=Path)
    parser.add_argument("--configuration", default="Debug")
    parser.add_argument("--check-translations", metavar="LANGUAGE")
    arguments = parser.parse_args()

    if arguments.check_translations:
        missing = [
            f"{catalog}: {key}"
            for catalog in [catalog for catalog, _, _ in CATALOGS] + HAND_KEPT_CATALOGS
            for key in untranslated(Path(catalog), arguments.check_translations)
        ]
        for line in missing:
            print(line)
        if missing:
            raise SystemExit(
                f"{len(missing)} strings have no {arguments.check_translations} translation:"
                " translate them in the catalog."
            )
        return
    if arguments.objroot is None:
        parser.error("--objroot is required to sync")

    for catalog, target, sources in CATALOGS:
        files = strings_data(arguments.objroot, arguments.configuration, target, Path(sources))
        command = ["xcrun", "xcstringstool", "sync", catalog]
        for file in files:
            command += ["--stringsdata", str(file)]
        subprocess.run(command, check=True)
        remove_stale(Path(catalog))


if __name__ == "__main__":
    main()
