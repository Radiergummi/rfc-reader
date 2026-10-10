# Contents Tab Filter and A–Z Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The inspector's Contents tab gets a filter field and a choice between document order and A–Z, the latter grouped by letter under pinned headers.

**Architecture:** What the tab lists is a pure function, `ContentsOutline.groups(of:filter:order:)` in RFCReaderKit, under test, after the pattern of `RequirementList.Filter`. `TableOfContentsView` in the App target only draws its result: a `List` in document order, as today, and a `ScrollView` with a `LazyVStack` pinning section headers in A–Z. The order is remembered app-wide through `@AppStorage` under a key in `ReaderPreferences`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, the RFCReaderKit package.

**Spec:** `docs/superpowers/specs/2026-10-05-document-index-design.md`, part 1. This plan's pull request carries the spec and this plan as well.

## Global Constraints

- The App target has no test bundle: everything decided about what the tab lists lives in RFCReaderKit, under test; the view only draws it.
- Tests use Swift Testing with raw-identifier names that say what they pin: ``@Test func `a number matches from its start`()``.
- Layout is swift-format's (`make fmt`); SwiftLint `--strict` is clean (`make lint`); lines stay under 200 characters.
- American spelling in identifiers, comments and UI strings.
- No RFC text in tests; section titles are made up.
- Z–A is not offered. Index terms are not listed in the Contents tab.
- Commits are signed, as every commit in this repository is; each ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Work in a worktree on its own branch: other sessions share the main checkout.

## Review Focus

- **A number is matched from its start:** `4.2` finds 4.2 and 4.2.1, never 14.2. Pinned in Task 2.
- **Titles that do not start with a Latin letter** (`3GPP …`, Greek, CJK) gather under one `#` group at the end, never split around the letters. Pinned in Task 3.
- **A section without words in its title** (`5.` alone, #683) still shows, by its number, under `#`. Pinned in Task 3.
- **A filter of only spaces** shows everything rather than nothing. Pinned in Task 2.
- **Equal titles** (two sections called `Overview`) keep the document's order in A–Z, told apart by their number captions. Pinned in Task 3.

---

### Task 1: Worktree, with the spec and this plan committed

**Files:**
- Move: `docs/superpowers/specs/2026-10-05-document-index-design.md` (untracked in the main checkout)
- Move: `docs/superpowers/plans/2026-10-05-contents-outline.md` (untracked in the main checkout)

**Interfaces:**
- Consumes: nothing.
- Produces: the branch `contents-outline` in `.claude/worktrees/contents-outline`, where every later task runs.

- [ ] **Step 1: Create the worktree from an up-to-date main**

```bash
cd /Users/moritz/Projects/rfc-reader
git fetch origin
git worktree add .claude/worktrees/contents-outline -b contents-outline origin/main
```

- [ ] **Step 2: Move the spec and the plan into it**

```bash
cd /Users/moritz/Projects/rfc-reader
mkdir -p .claude/worktrees/contents-outline/docs/superpowers/specs .claude/worktrees/contents-outline/docs/superpowers/plans
mv docs/superpowers/specs/2026-10-05-document-index-design.md .claude/worktrees/contents-outline/docs/superpowers/specs/
mv docs/superpowers/plans/2026-10-05-contents-outline.md .claude/worktrees/contents-outline/docs/superpowers/plans/
git status --short   # expect: clean
```

- [ ] **Step 3: Commit them**

```bash
cd /Users/moritz/Projects/rfc-reader/.claude/worktrees/contents-outline
git add docs/superpowers/specs/2026-10-05-document-index-design.md docs/superpowers/plans/2026-10-05-contents-outline.md
git commit -m "A document's index and a searchable Contents tab: the design, and part 1's plan

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

All later paths are relative to `/Users/moritz/Projects/rfc-reader/.claude/worktrees/contents-outline`.

---

### Task 2: `ContentsOutline` in document order, with the filter

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/ContentsOutline.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/ContentsOutlineTests.swift`

**Interfaces:**
- Consumes: `RFCKit.Section` (`anchor`, `number`, `titleText`, `displayTitle`, `depth`, `isAppendix`). The tab is given the flat list of every section the storage holds, in document order, each with its `depth`.
- Produces:

```swift
public enum ContentsOutline {
  public enum Order: String, CaseIterable, Sendable { case document, alphabetical }
  public struct Row: Identifiable, Equatable, Sendable {
    public let anchor: String
    public let title: String
    public let caption: String?
    public let depth: Int
    public let isContext: Bool
    public var id: String { anchor }
  }
  public struct Group: Identifiable, Equatable, Sendable {
    public let label: String?
    public let rows: [Row]
    public var id: String { label ?? "" }
  }
  public static func groups(of sections: [Section], filter: String, order: Order) -> [Group]
}
```

In document order the result is one group, labeled `nil`, or no group at all when nothing matches.

- [ ] **Step 1: Write the failing tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/ContentsOutlineTests.swift`:

```swift
import RFCKit
import Testing

@testable import RFCReaderKit

/// The Contents tab: a document's sections in its own order or A–Z, narrowed by
/// words in a title or the start of a number.
@Suite("Contents outline")
struct ContentsOutlineTests {
  /// Flat, in document order, as `DocumentView` hands the tab its sections.
  static let sections = [
    Section(anchor: "section-1", number: "1", title: "Introduction"),
    Section(anchor: "section-1.1", number: "1.1", title: "Requirements Language"),
    Section(anchor: "section-4", number: "4", title: "Résumé Handling"),
    Section(anchor: "section-4.2", number: "4.2", title: "Caching"),
    Section(anchor: "section-4.2.1", number: "4.2.1", title: "Freshness"),
    Section(anchor: "section-14", number: "14", title: "Security Considerations"),
    Section(anchor: "section-14.2", number: "14.2", title: "Cache Poisoning"),
    Section(anchor: "appendix-A", number: "A", title: "Collected ABNF", isAppendix: true),
    Section(anchor: "acknowledgments", title: "Acknowledgments"),
  ]

  static func rows(_ filter: String) -> [ContentsOutline.Row] {
    ContentsOutline.groups(of: sections, filter: filter, order: .document).flatMap(\.rows)
  }

  @Test func `with no filter, document order lists every section at its depth`() {
    let groups = ContentsOutline.groups(of: Self.sections, filter: "", order: .document)
    #expect(groups.count == 1)
    #expect(groups[0].label == nil)
    #expect(groups[0].rows.map(\.anchor) == Self.sections.map(\.anchor))
    #expect(groups[0].rows.map(\.depth) == [1, 2, 1, 2, 3, 1, 2, 1, 1])
    #expect(groups[0].rows.map(\.title)[3] == "4.2. Caching")
    #expect(groups[0].rows.allSatisfy { !$0.isContext && $0.caption == nil })
  }

  @Test func `a filter keeps a match's ancestors, as context`() {
    let rows = Self.rows("fresh")
    #expect(rows.map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
    #expect(rows.map(\.isContext) == [true, true, false])
  }

  @Test func `matches in two branches each bring their own ancestors`() {
    let rows = Self.rows("cach")
    #expect(rows.map(\.anchor) == ["section-4", "section-4.2", "section-14", "section-14.2"])
    #expect(rows.map(\.isContext) == [true, false, true, false])
  }

  @Test func `an ancestor that matches is a match, not context`() {
    let rows = Self.rows("4")
    #expect(rows.map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
    #expect(rows.allSatisfy { !$0.isContext })
  }

  @Test func `a title matches without regard to case or diacritics`() {
    #expect(Self.rows("RESUME").map(\.anchor) == ["section-4"])
  }

  @Test func `a number matches from its start`() {
    #expect(Self.rows("4.2").map(\.anchor) == ["section-4", "section-4.2", "section-4.2.1"])
  }

  @Test func `whitespace around the filter is ignored`() {
    #expect(Self.rows("  fresh ").map(\.anchor).last == "section-4.2.1")
    #expect(Self.rows("   ").count == Self.sections.count)
  }

  @Test func `a filter that matches nothing leaves no group`() {
    #expect(ContentsOutline.groups(of: Self.sections, filter: "zzz", order: .document).isEmpty)
  }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter ContentsOutlineTests`
Expected: a build failure, `cannot find 'ContentsOutline' in scope`.

- [ ] **Step 3: Write the implementation**

`Packages/RFCReaderKit/Sources/RFCReaderKit/ContentsOutline.swift`:

```swift
import Foundation
import RFCKit

/// What the Contents tab shows: a document's sections in its own order or A–Z,
/// narrowed by words in a title or the start of a number.
///
/// What is listed is decided here, under test; `TableOfContentsView` only draws it.
public enum ContentsOutline {
  /// How the tab orders the sections. Remembered app-wide by its raw value.
  public enum Order: String, CaseIterable, Sendable {
    case document
    case alphabetical
  }

  /// One section, as the tab lists it.
  public struct Row: Identifiable, Equatable, Sendable {
    public let anchor: String
    /// `4.2. Caching` in document order; the title alone in A–Z, where the number
    /// is the caption.
    public let title: String
    /// The number, or `Appendix A`, set beside an A–Z title; nil in document order.
    public let caption: String?
    /// How far the row is indented: the section's depth in document order, 1 in A–Z.
    public let depth: Int
    /// An ancestor shown only so a match keeps its place in the hierarchy.
    public let isContext: Bool

    public var id: String { anchor }
  }

  /// Rows under a letter in A–Z; the single, unlabeled group of document order.
  public struct Group: Identifiable, Equatable, Sendable {
    /// `A` to `Z`, or `#` for every title that does not start with a Latin letter;
    /// nil in document order.
    public let label: String?
    public let rows: [Row]

    public var id: String { label ?? "" }
  }

  /// What the tab lists of `sections`, which are flat and in document order, for
  /// `filter` and `order`. No group at all when nothing matches.
  public static func groups(of sections: [Section], filter: String, order: Order) -> [Group] {
    let text = filter.trimmingCharacters(in: .whitespaces)
    switch order {
    case .document:
      let rows = inDocumentOrder(sections, matching: text)
      return rows.isEmpty ? [] : [Group(label: nil, rows: rows)]
    case .alphabetical:
      return alphabetically(sections, matching: text)
    }
  }

  /// Whether `section` matches `text`: words anywhere in its title, ignoring case
  /// and diacritics, or the start of its number, so `4.2` does not find 14.2.
  static func matches(_ section: Section, _ text: String) -> Bool {
    if text.isEmpty { return true }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    if section.titleText.range(of: text, options: options) != nil { return true }
    guard let number = section.number else { return false }
    return number.range(of: text, options: options.union(.anchored)) != nil
  }

  /// Each match, after those of its ancestors not already listed, which are context.
  private static func inDocumentOrder(_ sections: [Section], matching text: String) -> [Row] {
    var rows: [Row] = []
    // The open path to the current section: each ancestor, and whether it is listed.
    var path: [(section: Section, isListed: Bool)] = []
    for section in sections {
      while let last = path.last, last.section.depth >= section.depth { path.removeLast() }
      let isMatch = matches(section, text)
      if isMatch {
        for index in path.indices where !path[index].isListed {
          rows.append(documentRow(path[index].section, isContext: true))
          path[index].isListed = true
        }
        rows.append(documentRow(section, isContext: false))
      }
      path.append((section, isMatch))
    }
    return rows
  }

  private static func documentRow(_ section: Section, isContext: Bool) -> Row {
    Row(
      anchor: section.anchor, title: section.displayTitle, caption: nil,
      depth: section.depth, isContext: isContext)
  }

  /// Filled in by Task 3.
  private static func alphabetically(_ sections: [Section], matching text: String) -> [Group] {
    []
  }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter ContentsOutlineTests`
Expected: all 8 pass.

- [ ] **Step 5: Format, lint and commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/ContentsOutline.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/ContentsOutlineTests.swift
git commit -m "The Contents tab's outline, filtered in document order

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `ContentsOutline` in A–Z

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/ContentsOutline.swift` (replace the stub `alphabetically`)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/ContentsOutlineTests.swift` (add to the suite)

**Interfaces:**
- Consumes: `ContentsOutline.matches(_:_:)`, `Row`, `Group` from Task 2.
- Produces: `groups(of:filter:order: .alphabetical)`: groups `A`…`Z` in order, then `#`; rows with the title alone, the number as caption, depth 1, never context.

- [ ] **Step 1: Write the failing tests**

Add to `ContentsOutlineTests`:

```swift
  static func alphabetical(
    _ sections: [Section] = sections, _ filter: String = ""
  ) -> [ContentsOutline.Group] {
    ContentsOutline.groups(of: sections, filter: filter, order: .alphabetical)
  }

  @Test func `A–Z sorts by title and sets the number aside as a caption`() {
    let rows = Self.alphabetical().flatMap(\.rows)
    #expect(
      rows.map(\.title) == [
        "Acknowledgments", "Cache Poisoning", "Caching", "Collected ABNF", "Freshness",
        "Introduction", "Requirements Language", "Résumé Handling", "Security Considerations",
      ])
    #expect(
      rows.map(\.caption) == [nil, "14.2", "4.2", "Appendix A", "4.2.1", "1", "1.1", "4", "14"])
    #expect(rows.allSatisfy { $0.depth == 1 && !$0.isContext })
  }

  @Test func `A–Z groups by first letter, folding diacritics`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Élan"),
      Section(anchor: "b", number: "2", title: "Echo"),
      Section(anchor: "c", number: "3", title: "alpha"),
    ])
    #expect(groups.map(\.label) == ["A", "E"])
    #expect(groups[1].rows.map(\.title) == ["Echo", "Élan"])
  }

  @Test func `titles that do not start with a Latin letter gather under # at the end`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Ωmega Handling"),
      Section(anchor: "b", number: "2", title: "Zebra"),
      Section(anchor: "c", number: "3", title: "3GPP Interworking"),
      Section(anchor: "d", number: "4", title: "Alpha"),
    ])
    #expect(groups.map(\.label) == ["A", "Z", "#"])
    #expect(groups[2].rows.map(\.anchor) == ["c", "a"])
  }

  @Test func `leading punctuation is set aside for sorting, not for showing`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Zone Files"),
      Section(anchor: "b", number: "2", title: "\"Quoted\" Strings"),
    ])
    #expect(groups.map(\.label) == ["Q", "Z"])
    #expect(groups[0].rows[0].title == "\"Quoted\" Strings")
  }

  @Test func `numbers in titles sort by value`() {
    let rows = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Step 10"),
      Section(anchor: "b", number: "2", title: "Step 2"),
    ]).flatMap(\.rows)
    #expect(rows.map(\.anchor) == ["b", "a"])
  }

  @Test func `equal titles keep the document's order, told apart by their numbers`() {
    let rows = Self.alphabetical([
      Section(anchor: "a", number: "3.1", title: "Overview"),
      Section(anchor: "b", number: "2.1", title: "Overview"),
    ]).flatMap(\.rows)
    #expect(rows.map(\.anchor) == ["a", "b"])
    #expect(rows.map(\.caption) == ["3.1", "2.1"])
  }

  @Test func `a section without words in its title shows by its number, under #`() {
    let groups = Self.alphabetical([
      Section(anchor: "a", number: "1", title: "Alpha"),
      Section(anchor: "b", number: "5", title: ""),
    ])
    #expect(groups.map(\.label) == ["A", "#"])
    #expect(groups[1].rows[0].title == "5.")
    #expect(groups[1].rows[0].caption == nil)
  }

  @Test func `the filter applies in A–Z too, with no context rows`() {
    let rows = Self.alphabetical(Self.sections, "cach").flatMap(\.rows)
    #expect(rows.map(\.anchor) == ["section-14.2", "section-4.2"])
    #expect(Self.alphabetical(Self.sections, "zzz").isEmpty)
  }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter ContentsOutlineTests`
Expected: the 8 new tests fail (the stub returns no groups); Task 2's 8 still pass.

- [ ] **Step 3: Replace the stub with the implementation**

In `ContentsOutline.swift`, replace the stub `alphabetically` with:

```swift
  /// The matches by title, under `A` to `Z` and then `#`. Equal titles keep the
  /// document's order.
  private static func alphabetically(_ sections: [Section], matching text: String) -> [Group] {
    let keyed = sections.filter { matches($0, text) }.map { section in
      let key = sortKey(section)
      return (key: key, label: groupLabel(key), section: section)
    }
    // `sorted` is not stable, so the document's order is the last comparison.
    let sorted = keyed.enumerated().sorted { first, second in
      let (a, b) = (first.element, second.element)
      if (a.label == "#") != (b.label == "#") { return b.label == "#" }
      let order = a.key.compare(
        b.key, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
      return order == .orderedSame ? first.offset < second.offset : order == .orderedAscending
    }.map(\.element)
    var groups: [(label: String, rows: [Row])] = []
    for item in sorted {
      let row = alphabeticalRow(item.section)
      if groups.last?.label == item.label {
        groups[groups.count - 1].rows.append(row)
      } else {
        groups.append((item.label, [row]))
      }
    }
    return groups.map { Group(label: $0.label, rows: $0.rows) }
  }

  private static func alphabeticalRow(_ section: Section) -> Row {
    let hasWords = !section.titleText.isEmpty
    let caption = section.number.map { section.isAppendix ? "Appendix \($0)" : $0 }
    return Row(
      anchor: section.anchor, title: hasWords ? section.titleText : section.displayTitle,
      caption: hasWords ? caption : nil, depth: 1, isContext: false)
  }

  /// What a section sorts by: its title from its first letter or digit, or, with no
  /// words in it, the number it is shown by.
  private static func sortKey(_ section: Section) -> String {
    let title = section.titleText.drop { !$0.isLetter && !$0.isNumber }
    return title.isEmpty ? section.displayTitle : String(title)
  }

  /// `A` to `Z` for a key that starts with a Latin letter, diacritics folded, and `#`
  /// for anything else.
  private static func groupLabel(_ key: String) -> String {
    let first = key.prefix(1).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .uppercased()
    return first.count == 1 && ("A"..."Z").contains(first) ? first : "#"
  }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter ContentsOutlineTests`
Expected: all 16 pass.

- [ ] **Step 5: Format, lint and commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/ContentsOutline.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/ContentsOutlineTests.swift
git commit -m "The Contents tab's outline in A–Z, grouped by letter

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The Contents tab draws the outline

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/UserData/ReaderPreferences.swift` (add one key)
- Modify: `App/RFCReader/Views/Rendering/TableOfContentsView.swift` (rewrite the body)

**Interfaces:**
- Consumes: `ContentsOutline.groups(of:filter:order:)`, `ContentsOutline.Order`, `Row`, `Group`.
- Produces: `ReaderPreferences.contentsOrderKey`. `TableOfContentsView`'s initializer is unchanged (`sections:current:select:`), so `DocumentInspector` and its `ScrollViewReader`, which scrolls to `current` by the row's anchor id, need no change.

- [ ] **Step 1: Add the preference key**

In `ReaderPreferences`, beside the other keys:

```swift
  /// The order the Contents tab lists sections in: a `ContentsOutline.Order`'s raw
  /// value.
  public static let contentsOrderKey = "contentsOrder"
```

- [ ] **Step 2: Rewrite `TableOfContentsView`**

`App/RFCReader/Views/Rendering/TableOfContentsView.swift`:

```swift
import RFCKit
import RFCReaderKit
import SwiftUI

/// The document panel's Contents tab: the sections in the document's order or A–Z,
/// narrowed by a filter.
///
/// What is listed is `ContentsOutline`'s, under test; this only draws it.
struct TableOfContentsView: View {
  /// Only the sections the storage holds; see `DocumentView.rebuild()`.
  let sections: [RFCKit.Section]
  let current: String?
  let select: (String) -> Void

  @State private var filter = ""
  @AppStorage(ReaderPreferences.contentsOrderKey) private var order = ContentsOutline.Order.document

  var body: some View {
    let groups = ContentsOutline.groups(of: sections, filter: filter, order: order)
    VStack(spacing: 0) {
      controls
      Group {
        switch order {
        case .document: documentList(groups.flatMap(\.rows))
        case .alphabetical: alphabeticalList(groups)
        }
      }
      .overlay {
        if groups.isEmpty, !sections.isEmpty {
          ContentUnavailableView.search
        }
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      Picker("Order", selection: $order) {
        Text("Document Order").tag(ContentsOutline.Order.document)
        Text("A–Z").tag(ContentsOutline.Order.alphabetical)
      }
      .labelsHidden()
      .fixedSize()
      TextField("Filter", text: $filter)
        .textFieldStyle(.roundedBorder)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func documentList(_ rows: [ContentsOutline.Row]) -> some View {
    List {
      ForEach(rows) { row in
        button(row) {
          Text(row.title)
            .lineLimit(2)
            .padding(.leading, CGFloat(max(0, row.depth - 1)) * 12)
        }
      }
    }
    .listStyle(.sidebar)
    // A sidebar list is announced as "Sidebar", which is the window's own (#300).
    .accessibilityLabel("Contents")
  }

  /// A–Z under letter headers that stay at the top while their rows scroll, as
  /// Contacts' do: a `LazyVStack` pins them the same way on both platforms.
  private func alphabeticalList(_ groups: [ContentsOutline.Group]) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        ForEach(groups) { group in
          SwiftUI.Section {
            ForEach(group.rows) { row in
              button(row) {
                HStack(alignment: .firstTextBaseline) {
                  Text(row.title)
                    .lineLimit(2)
                  Spacer(minLength: 8)
                  if let caption = row.caption {
                    Text(caption)
                      .font(.caption)
                      .monospacedDigit()
                      .foregroundStyle(.secondary)
                  }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
              }
            }
          } header: {
            Text(group.label ?? "")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(.bar)
              .accessibilityAddTraits(.isHeader)
          }
        }
      }
    }
    .accessibilityLabel("Contents")
  }

  private func button(
    _ row: ContentsOutline.Row, @ViewBuilder label: () -> some View
  ) -> some View {
    Button {
      select(row.anchor)
    } label: {
      label()
        .fontWeight(row.anchor == current ? .semibold : .regular)
        .foregroundStyle(row.isContext ? .secondary : .primary)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    // Weight alone marks the current section only for someone who can see it
    // (#156).
    .accessibilityAddTraits(row.anchor == current ? .isSelected : [])
    .id(row.anchor)
  }
}
```

- [ ] **Step 3: Build for both platforms**

Run: `make build-app && make ios-sim`
Expected: both succeed with no new warnings. If the compiler reads `Group` as `ContentsOutline.Group`, write `SwiftUI.Group` at the one place the view uses it.

- [ ] **Step 4: Run the package tests and lint**

Run: `make fmt && make lint && make test-app`
Expected: clean lint; every RFCReaderKit suite passes.

- [ ] **Step 5: See it in the Mac app**

Run: `make run`, open RFC 9110, open the inspector's Contents tab. By screenshots and AX reads only — no synthetic keystrokes or clicks into fields, since focus moves while the maintainer works:
- document order looks as it did before this change, with the filter and the order picker above it;
- set the order to A–Z through AX (`AXPress` on the picker's menu item), and check the letter header stays pinned while the list scrolls;
- the current section is semibold in both orders.

Typing into the filter is the maintainer's to try: say so in the pull request, with what to type (`cach`, `4.2`, `résumé`).

- [ ] **Step 6: See it on iOS**

Run: `make run-sim`, open RFC 9110 through `xcrun simctl openurl booted rfc://9110` (accept the prompt), open the panel, and `xcrun simctl io booted screenshot contents.png` in document order. Check the controls fit the panel's width.

- [ ] **Step 7: Commit**

```bash
git add Packages/RFCReaderKit/Sources/RFCReaderKit/UserData/ReaderPreferences.swift App/RFCReader/Views/Rendering/TableOfContentsView.swift
git commit -m "The Contents tab filters, and lists A–Z under pinned letters

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The gate and the pull request

**Files:** none new.

**Interfaces:**
- Consumes: the branch as Tasks 1–4 leave it.
- Produces: an open pull request.

- [ ] **Step 1: Run the gate**

Run: `make check`
Expected: lint, build, test and test-app all pass.

- [ ] **Step 2: Check the branch, then push**

```bash
git branch --show-current   # expect: contents-outline
git push -u origin contents-outline
```

- [ ] **Step 3: Open the pull request**

```bash
gh pr create --title "The Contents tab filters, and lists A–Z under pinned letters" --body "$(cat <<'EOF'
Part 1 of the design in `docs/superpowers/specs/2026-10-05-document-index-design.md`, which this pull request adds together with its plan.

- `ContentsOutline` (RFCReaderKit) decides what the Contents tab lists: the document's order, where a filter keeps each match's ancestors as dimmed context, or A–Z, by title with the number as a caption, under `A`–`Z` and then `#`. A filter matches words in a title, ignoring case and diacritics, or the start of a number, so `4.2` does not find 14.2.
- `TableOfContentsView` draws it: the list as before in document order, a `LazyVStack` pinning letter headers in A–Z. The order is remembered app-wide.

Not offered: Z–A, and index terms in this tab; both are reasoned in the spec.

To try by hand: open RFC 9110's Contents tab and filter for `cach`, `4.2` and `résumé`, in both orders.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
