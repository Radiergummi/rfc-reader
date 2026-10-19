#!/usr/bin/env python3
"""Exports a hand check's screenshots from its result bundle, named by step.

    Tools/hand-checks/export.py hand-checks/<check>.xcresult hand-checks/<check>

`make hand-check` runs it after the check, whether the check passed or not, so
the screenshots up to a failing step are there to look at. `xcresulttool export
attachments` writes each attachment under a UUID and lists them in a manifest;
this renames each to the name the check gave it ("2 pushed RFC 2119.png").
"""

import json
import os
import re
import subprocess
import sys


def main() -> None:
    bundle, destination = sys.argv[1], sys.argv[2]
    if not os.path.isdir(bundle):
        sys.exit(f"no result bundle at {bundle}: did the build fail?")
    os.makedirs(destination, exist_ok=True)
    subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments",
         "--path", bundle, "--output-path", destination],
        check=True, stdout=subprocess.DEVNULL)
    manifest_path = os.path.join(destination, "manifest.json")
    with open(manifest_path) as manifest:
        tests = json.load(manifest)
    for test in tests:
        for attachment in test["attachments"]:
            # "<name>_<index>_<UUID>.png", the name being the check's.
            name = re.sub(r"_\d+_[0-9A-F-]{36}(?=\.\w+$)", "",
                          attachment["suggestedHumanReadableName"])
            os.rename(os.path.join(destination, attachment["exportedFileName"]),
                      os.path.join(destination, name))
            print(os.path.join(destination, name))
    os.remove(manifest_path)


if __name__ == "__main__":
    main()
