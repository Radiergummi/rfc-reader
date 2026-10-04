#!/bin/sh
# The architecture review's inventory (.claude/skills/architecture-review/SKILL.md, step 2).
# Read-only; prints Markdown. Run from the repository root:
#   sh .claude/skills/architecture-review/inventory.sh > "$SCRATCHPAD/inventory.md"
# Portable between macOS and Linux: POSIX sh, grep -E, awk, git.
# CHURN_SINCE=2026-07-01 limits the churn section to recent history (default: all of it).

set -eu

SOURCES='App Packages Tools'
swift_sources() {
  find $SOURCES -name '*.swift' -not -name Package.swift -not -path '*/.build/*' -not -path '*/Tests/*' | sort
}
swift_tests() {
  find $SOURCES -name '*.swift' -not -path '*/.build/*' -path '*/Tests/*' | sort
}
module_of() {
  # App/RFCReader/X -> App/RFCReader/X; Packages/P/Sources/P/X -> P/X; Tools/T -> Tools/T
  awk -F/ '{
    if ($1 == "Packages") print $2 "/" $5
    else if ($1 == "App") print $1 "/" $3
    else print $1 "/" $2
  }'
}

echo "# Inventory"
echo
echo "Commit \`$(git rev-parse --short HEAD)\`, $(date +%Y-%m-%d)."

echo
echo "## Lines per module (sources, then tests)"
echo
echo '```'
swift_sources | while read -r f; do printf '%s %s\n' "$(wc -l < "$f")" "$(echo "$f" | module_of)"; done |
  awk '{ sum[$2] += $1 } END { for (m in sum) printf "%7d  %s\n", sum[m], m }' | sort -rn
echo '---'
swift_tests | while read -r f; do printf '%s %s\n' "$(wc -l < "$f")" "$(echo "$f" | awk -F/ '{print $1 "/" $2}')"; done |
  awk '{ sum[$2] += $1 } END { for (m in sum) printf "%7d  %s\n", sum[m], m }' | sort -rn
echo '```'

echo
echo "## The 30 longest source files"
echo
echo '```'
swift_sources | xargs wc -l | grep -v ' total$' | sort -rn | head -30
echo '```'

echo
echo "## The 30 longest functions (lines from \`func\` to its closing brace at the same indent)"
echo
echo '```'
swift_sources | while read -r f; do
  awk -v file="$f" '
    match($0, /^[ \t]*((@[A-Za-z]+|public|internal|private|fileprivate|static|nonisolated|override|mutating|final|@concurrent) +)*func /) {
      if (name == "") {
        indent = match($0, /[^ \t]/) - 1; start = NR
        name = $0; sub(/^[ \t]*/, "", name); sub(/\(.*/, "", name); sub(/.*func /, "", name)
      }
    }
    name != "" && NR > start && match($0, /^[ \t]*\}/) && (match($0, /[^ \t]/) - 1) == indent {
      printf "%5d  %s:%d  %s\n", NR - start + 1, file, start, name; name = ""
    }
  ' "$f"
done | sort -rn | head -30
echo '```'

echo
echo "## Type declarations with the most extensions across files"
echo
echo '```'
swift_sources | xargs grep -hE '^(public |internal |private |fileprivate )*extension [A-Z][A-Za-z0-9_.]*' |
  sed -E 's/^.*extension ([A-Za-z0-9_.]+).*/\1/' | sort | uniq -c | sort -rn | head -20
echo '```'

echo
echo "## Imports per module"
echo
echo '```'
swift_sources | while read -r f; do
  m=$(echo "$f" | module_of)
  grep -hE '^(@preconcurrency |@testable )?import ' "$f" | sed -E 's/^.*import ([A-Za-z0-9_]+).*/\1/' | sed "s|^|$m |"
done | sort | uniq -c | awk '{ printf "%-40s %s (%d)\n", $2, $3, $1 }'
echo '```'

echo
echo "## Public declarations per package"
echo
echo '```'
for package in RFCKit RFCReaderKit; do
  printf '%5d  %s\n' "$(find "Packages/$package/Sources" -name '*.swift' | xargs grep -cE '^[ \t]*(@[A-Za-z]+ +)*public ' | awk -F: '{ s += $2 } END { print s }')" "$package"
done
echo '```'

echo
echo "## Platform forks per file (#if os / #if canImport)"
echo
echo '```'
swift_sources | xargs grep -cE '^[ \t]*#(if|elseif) .*(os\(|canImport\()' | grep -v ':0$' | sort -t: -k2 -rn | head -25
echo '```'

echo
echo "## Concurrency escape hatches"
echo
for pattern in '@unchecked Sendable' 'nonisolated\(unsafe\)' '@preconcurrency' 'assumeIsolated' 'DispatchQueue' 'Task\.detached' 'NSLock|OSAllocatedUnfairLock|Mutex<|os_unfair_lock'; do
  echo "### \`$pattern\`"
  echo
  echo '```'
  swift_sources | xargs grep -nE "$pattern" || echo "(none)"
  echo '```'
  echo
done

echo "## Workaround markers"
echo
echo '```'
{
  swift_sources | xargs grep -niE '(workaround|work around|\bhack|radar|swiftlint:disable|as of (iOS|macOS)|(iOS|macOS) 2[0-9]\b|#available)' || true
  swift_sources | xargs grep -nE '(\bFB[0-9]{6,}|\bTODO\b|\bFIXME\b|\bXXX\b)' || true
} | sort -u | head -200
echo '```'

echo
echo "## Home-grown candidates (types that may re-implement a library or platform API)"
echo
echo '```'
swift_sources | xargs grep -nE '^[ \t]*(public |internal |private |fileprivate |final |nonisolated )*(struct|class|actor|enum) [A-Za-z]*(Lexer|Parser|Tree|Cache|Store|Debounce|Throttle|Queue|Pool|Diff|Distance|Alignment|Partition|Formatter|Tokenizer|Scanner|Heap|LRU)[A-Za-z]*\b' | head -80
echo '---'
swift_sources | xargs grep -lE '^import (SQLite3|CoreText|AppleArchive|CryptoKit|System)' || true
echo '```'

echo
CHURN_SINCE=${CHURN_SINCE:-1970-01-01}
echo "## Churn: files changed most since $CHURN_SINCE (all commits, then commits whose subject reads as a fix)"
echo
echo '```'
git log --since="$CHURN_SINCE" --name-only --format= -- $SOURCES | grep '\.swift$' | grep -v '/Tests/' | sort | uniq -c | sort -rn | head -25
echo '---'
git log --since="$CHURN_SINCE" --name-only --format= -i -E --grep='fix|bug|crash|regress|wrong|broke' -- $SOURCES | grep '\.swift$' | grep -v '/Tests/' | sort | uniq -c | sort -rn | head -25
echo '```'

echo
echo "## Fan-in: files outside its own that name each of the 25 largest types"
echo
echo '```'
swift_sources | xargs grep -hoE '^[ \t]*(public |internal |final |nonisolated )*(struct|class|actor|enum) [A-Z][A-Za-z0-9]+' |
  awk '{ print $NF }' | sort -u > "${TMPDIR:-/tmp}/arch-review-types.$$"
swift_sources | xargs wc -l | grep -v ' total$' | sort -rn | head -40 | awk '{ print $2 }' | while read -r f; do
  basename "$f" .swift | sed 's/+.*//'
done | sort -u | while read -r t; do
  grep -qx "$t" "${TMPDIR:-/tmp}/arch-review-types.$$" || continue
  n=$(swift_sources | xargs grep -lw "$t" | grep -vE "/$t(\+[A-Za-z]*)?\.swift$" | wc -l)
  printf '%5d  %s\n' "$n" "$t"
done | sort -rn | head -25
rm -f "${TMPDIR:-/tmp}/arch-review-types.$$"
echo '```'

app_sources() {
  find App Packages/RFCReaderKit/Sources -name '*.swift' | sort
}
# signal LABEL PATTERN: the number of matching lines, then the files with the most.
signal() {
  printf '### %s\n\n```\n' "$1"
  app_sources | xargs grep -cE "$2" | grep -v ':0$' | sort -t: -k2 -rn > "${TMPDIR:-/tmp}/arch-review-signal.$$" || true
  printf '%d lines in %d files\n' \
    "$(awk -F: '{ s += $2 } END { print s + 0 }' "${TMPDIR:-/tmp}/arch-review-signal.$$")" \
    "$(wc -l < "${TMPDIR:-/tmp}/arch-review-signal.$$" | tr -d ' ')"
  head -8 "${TMPDIR:-/tmp}/arch-review-signal.$$"
  rm -f "${TMPDIR:-/tmp}/arch-review-signal.$$"
  printf '```\n\n'
}

echo
echo "## Platform signals (App and RFCReaderKit)"
echo
echo "### Files"
echo
echo '```'
for name in '*.xcprivacy' '*.xcstrings' '*.strings' '*.stringsdict' '*.entitlements' '*.xctestplan'; do
  printf '%-16s %s\n' "$name" "$(find . -name "$name" -not -path '*/.build/*' -not -path './corpus/*' | tr '\n' ' ')"
done
printf '%-16s %s\n' 'UI test target' "$(grep -nE 'bundle\.ui-testing|UITests' project.yml | tr '\n' ' ')"
printf '%-16s %s\n' 'entitlements' "$(grep -nE 'com\.apple\.(security|developer)' project.yml | sed 's/^ *//' | tr '\n' ' ')"
echo '```'
echo
signal 'Required-reason APIs: UserDefaults' 'UserDefaults|@AppStorage'
signal 'Required-reason APIs: file timestamps' 'contentModificationDate|creationDate|modificationDate|attributesOfItem|fileModificationDate'
signal 'Required-reason APIs: disk space, boot time' 'volumeAvailableCapacity|systemUptime|mach_absolute_time'
signal 'Interface string literals (SwiftUI takes a literal as a localization key; without a String Catalog none is translated)' '(Text|Button|Label|Toggle|Picker|Section|Menu)\("[^"]*[A-Za-z][^"]*"|Text\(verbatim:'
signal 'Localized lookups' 'String\(localized:|LocalizedStringKey|LocalizedStringResource|NSLocalizedString'
signal 'Fixed formats (dates, numbers, plurals)' 'DateFormatter|dateFormat *=|String\(format:|== 1 \?|count == 1'
signal 'Logging' 'Logger\(|os_log|OSSignposter|\bprint\('
signal 'MetricKit' 'MetricKit|MXMetricManager'
signal 'Memory pressure' 'didReceiveMemoryWarning|makeMemoryPressureSource|NSCache'
signal 'State restoration and Handoff' '@SceneStorage|NSUserActivity|userActivity\(|onContinueUserActivity|restorationIdentifier'
signal 'Undo' 'UndoManager|undoManager'
signal 'Swallowed errors' 'try\?|catch *\{ *\}'
signal 'Network conditions' 'NWPathMonitor|isConstrained|isExpensive|allowsExpensiveNetworkAccess'
signal 'Schema versions and migration' 'VersionedSchema|SchemaMigrationPlan|MigrationStage'

echo "## Interface signals (App and RFCReaderKit)"
echo
signal 'Keyboard shortcuts' 'keyboardShortcut\(|UIKeyCommand|keyEquivalent'
signal 'Menu commands' 'CommandMenu|CommandGroup|NSMenuItem\('
signal 'Tooltips' '\.help\(|toolTip'
signal 'Context menus and swipe actions' 'contextMenu|swipeActions|UIContextMenuInteraction|menuForEvent'
signal 'Empty and unavailable states' 'ContentUnavailableView|overlay.*isEmpty|if .*isEmpty'
signal 'Accessibility modifiers' 'accessibility(Label|Hint|Value|Action|AddTraits|Element|RotorEntry|Rotor|SortPriority|Hidden)|isAccessibilityElement'
signal 'Fixed font sizes' '\.system\(size:|Font\.system\(size:|NSFont\(name:|UIFont\(name:|systemFont\(ofSize:|\.font\(\.custom'
signal 'Literal colors' 'Color\((red|white|hue):|UIColor\((red|white):|NSColor\((red|white|calibrated|srgb)|Color\(#'
signal 'Custom controls (ButtonStyle, gestures)' 'ButtonStyle|onTapGesture|onLongPressGesture|DragGesture|MagnifyGesture'
signal 'TipKit' 'import TipKit|TipView|popoverTip'
signal 'Animation and Reduce Motion' 'withAnimation|\.animation\(|accessibilityReduceMotion|reduceMotion'

echo "## Source files no test names (by file name's type)"
echo
echo '```'
swift_sources | grep '^Packages/' | while read -r f; do
  t=$(basename "$f" .swift | sed 's/+.*//')
  swift_tests | xargs grep -qw "$t" || echo "$f"
done
echo '```'
