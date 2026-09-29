#!/usr/bin/env python3
"""Records a Time Profiler trace of the macOS app through a scripted session, and
prints what the app's signposts measured.

    Tools/trace/trace.py --app path/to/RFCReader.app --output traces/<name>.trace

`make trace` is the usual way in: it builds Release first and names the trace.

The app is launched from its executable rather than by xctrace, which refuses a
bundle identifier more than one copy of the app on this Mac carries, and the
recording therefore covers every process; only the app's own rows are printed.
The session is driven through the scripting dictionary, by process ID, so a copy
of the app that some other checkout is running is left alone.

What is printed is the app's signposts (see `Signposts.swift`): the events as
points in time since launch, the intervals with their durations, and which
thread each ran on, followed by any hangs Instruments detected. The trace stays
on disk for Instruments, where the same intervals sit in the Points of Interest
lane above the time profile.

Python 3.9 or later, standard library only.
"""

import argparse
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SUBSYSTEM = "me.mazetti.rfc-reader"

# What the session does, in order. Opening a document returns as soon as the app
# has taken the request, so each step is followed by a wait long enough for its
# load, build and layout to finish: those are what the signposts measure, and the
# waits only have to outlast them.
DEFAULT_SCENARIO = [
    ("wait", 6),
    ("open", "9110"),
    ("wait", 4),
    ("open", "9000"),
    ("wait", 4),
    ("open", "5661"),
    ("wait", 5),
    ("search", "http"),
    ("wait", 2),
    ("search", "author:fielding"),
    ("wait", 2),
    ("search", ""),
    ("wait", 2),
]


def main():
    arguments = parse_arguments()
    executable = arguments.app / "Contents" / "MacOS" / arguments.app.stem
    if not executable.is_file():
        sys.exit(f"no executable at {executable} -- did the build fail?")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    if arguments.output.exists():
        sys.exit(f"{arguments.output} exists already; name another trace")

    process_id = record(executable, arguments.output, parse_scenario(arguments.scenario))
    print(f"trace: {arguments.output}\n")
    print_signposts(arguments.output, process_id)
    print_hangs(arguments.output, process_id)


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--app", type=Path, required=True, help="the built RFCReader.app")
    parser.add_argument("--output", type=Path, required=True, help="the .trace to write")
    parser.add_argument(
        "--scenario",
        help="steps separated by ';', such as 'wait 6; open 9110; wait 4; search http'"
        " (default: open three large documents, then search)",
    )
    return parser.parse_args()


def parse_scenario(text):
    if text is None:
        return DEFAULT_SCENARIO
    steps = []
    for step in text.split(";"):
        action, _, argument = step.strip().partition(" ")
        if action == "wait":
            steps.append((action, float(argument)))
        elif action in ("open", "search"):
            steps.append((action, argument))
        else:
            sys.exit(f"unknown step '{step.strip()}': use wait, open or search")
    return steps


# MARK: - Recording


def record(executable, output, scenario):
    """Records while the app runs the scenario, and returns the app's process ID."""
    recorder = subprocess.Popen(
        [
            "xcrun", "xctrace", "record",
            "--template", "Time Profiler",
            "--all-processes",
            "--output", str(output),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    wait_for_line(recorder, "Ctrl-C to stop the recording")

    app = subprocess.Popen(
        [str(executable)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        for action, argument in scenario:
            if action == "wait":
                time.sleep(argument)
            elif action == "open":
                script(app.pid, f"app.openRfc('{argument}')")
            elif action == "search":
                script(app.pid, f"app.windows[0].searchText = '{argument}'")
    finally:
        app.terminate()
        app.wait()
        recorder.send_signal(signal.SIGINT)
        wait_for_line(recorder, "Output file saved")
        recorder.wait()
    return app.pid


def wait_for_line(process, text):
    for line in process.stdout:
        if text in line:
            return
    sys.exit(f"xctrace ended before saying '{text}'")


def script(process_id, statement):
    """Runs one JavaScript for Automation statement against the app by process ID."""
    subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", f"const app = Application({process_id}); {statement}"],
        check=True,
        stdout=subprocess.DEVNULL,
    )


# MARK: - Reading the trace


def export_rows(trace, schema):
    """The rows of one table, each a dictionary from column mnemonic to the cell's
    element, with xctrace's `ref` attributes resolved to the element they name."""
    exported = subprocess.run(
        [
            "xcrun", "xctrace", "export",
            "--input", str(trace),
            "--xpath", f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]',
        ],
        check=True,
        capture_output=True,
    ).stdout
    root = ElementTree.fromstring(exported)
    columns = [column.findtext("mnemonic") for column in root.iter("col")]
    elements_by_id = {}
    rows = []
    for row in root.iter("row"):
        cells = {}
        for mnemonic, cell in zip(columns, row):
            cells[mnemonic] = resolve(cell, elements_by_id)
        rows.append(cells)
    return rows


def resolve(element, elements_by_id):
    """Records every element that carries an id, and answers a ref with the element
    it refers to. xctrace writes each value once and refers back to it after."""
    for descendant in element.iter():
        if "id" in descendant.attrib:
            elements_by_id[descendant.attrib["id"]] = descendant
    reference = element.attrib.get("ref")
    return elements_by_id[reference] if reference else element


def pid_of(cells):
    """The process ID from the process cell's label, `RFCReader (41116)`: the label
    is on the element a reference resolves to, where its `pid` child may itself be
    a reference."""
    label = formatted(cells, "process")
    number = label.rpartition("(")[2].rstrip(")")
    return int(number) if number.isdigit() else None


def formatted(cells, mnemonic):
    cell = cells.get(mnemonic)
    if cell is None or cell.tag == "sentinel":
        return ""
    return cell.attrib.get("fmt", cell.text or "")


def thread_name(cells):
    name = formatted(cells, "thread")
    return "main" if name.startswith("Main Thread") else "background"


def print_signposts(trace, process_id):
    # Keyed on everything that tells two signposts apart, because the template
    # records Points of Interest into two tables, and the export has both.
    unique = {}
    for cells in export_rows(trace, "os-signpost"):
        if pid_of(cells) != process_id or formatted(cells, "subsystem") != SUBSYSTEM:
            continue
        key = tuple(formatted(cells, mnemonic) for mnemonic in ("time", "thread", "event-type", "identifier", "name"))
        unique.setdefault(key, cells)
    rows = list(unique.values())
    if not rows:
        print("no signposts from the app: was it built from a branch that has them?")
        return
    launch = min(int(cells["time"].text) for cells in rows)

    # A begin waits here for its end, keyed on name and signpost ID. A stack per
    # key, because an interval without an ID of its own shares the exclusive ID
    # with every other interval of that name.
    open_intervals = {}
    lines = []
    for cells in sorted(rows, key=lambda cells: int(cells["time"].text)):
        timestamp = int(cells["time"].text)
        name = formatted(cells, "name")
        key = (name, formatted(cells, "identifier"))
        kind = formatted(cells, "event-type")
        if kind == "Event":
            lines.append((timestamp, name, formatted(cells, "message"), None, thread_name(cells)))
        elif kind == "Begin":
            open_intervals.setdefault(key, []).append(cells)
        elif kind == "End" and open_intervals.get(key):
            begin = open_intervals[key].pop()
            start = int(begin["time"].text)
            lines.append(
                (start, name, formatted(begin, "message"), timestamp - start, thread_name(begin))
            )
    for key, begins in open_intervals.items():
        for begin in begins:
            lines.append((int(begin["time"].text), key[0], formatted(begin, "message"), -1, thread_name(begin)))

    print(f"{'at':>9}  {'duration':>10}  {'thread':<10}  what")
    for start, name, message, duration, thread in sorted(lines):
        at = f"{(start - launch) / 1e6:9.0f}"
        if duration is None:
            length = "event"
        elif duration < 0:
            length = "unended"
        else:
            length = f"{duration / 1e6:8.1f}ms"
        detail = f"{name} ({message})" if message else name
        print(f"{at}  {length:>10}  {thread:<10}  {detail}")
    print("\n'at' is milliseconds after the app's first signpost, which is Launched.")


def print_hangs(trace, process_id):
    hangs = [cells for cells in export_rows(trace, "potential-hangs") if pid_of(cells) == process_id]
    print()
    if not hangs:
        print("hangs: none detected")
        return
    print("hangs:")
    for cells in hangs:
        print(
            f"  {formatted(cells, 'hang-type')}: {formatted(cells, 'duration')}"
            f" at {formatted(cells, 'start')}"
        )


if __name__ == "__main__":
    main()
