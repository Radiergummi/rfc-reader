#!/usr/bin/env python3
"""Syncs the string catalogs with the strings the code uses.

    Tools/strings/sync.py --objroot <OBJROOT> --configuration Debug

`make strings` is the usual way in: it builds for macOS and the iOS Simulator
first, and passes the build's OBJROOT.

The compiler records every localizable string it type-checks in a .stringsdata
file per source file (SWIFT_EMIT_LOC_STRINGS, project.yml). `xcstringstool sync`
adds the strings it finds there to a catalog and marks the ones it does not find
stale; xcodebuild never does this itself, only Xcode's editor does. Both
platforms' builds are read, so a string inside `#if os(iOS)` is found too.

The App Shortcuts' phrases are not the compiler's: the App Intents metadata step
records them in a file of its own, ExtractedAppShortcutsMetadata.stringsdata, in
an AppShortcuts table that `xcstringstool sync` puts in AppShortcuts.xcstrings,
along with the intents' parameter summaries, which go in Localizable.xcstrings.
The sync reads it with the rest; each catalog takes the table it is named for.

Only the given configuration's files are read, and only those named after a
source file that still exists (and the App Shortcuts' file): DerivedData keeps
the .stringsdata of a deleted file, and of every other configuration ever built,
and either would keep a removed string from going stale.

Python 3.9 or later, standard library only.
"""

import argparse
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
        found += newest.values()
    return sorted(found)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--objroot", type=Path, required=True)
    parser.add_argument("--configuration", default="Debug")
    arguments = parser.parse_args()

    for catalog, target, sources in CATALOGS:
        files = strings_data(arguments.objroot, arguments.configuration, target, Path(sources))
        if not files:
            raise SystemExit(f"no .stringsdata for {target} under {arguments.objroot}: build first")
        command = ["xcrun", "xcstringstool", "sync", catalog]
        for file in files:
            command += ["--stringsdata", str(file)]
        subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
