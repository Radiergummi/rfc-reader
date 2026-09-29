# RFC Revisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show, in the reader's status banner and the inspector, which adopted Internet-Drafts intend to obsolete or update the RFC being read, and how far along each one is.

**Architecture:** A daily GitHub Action runs a new `corpus-build revisions` subcommand. It lists every active, adopted draft on datatracker, reads the header of each draft that changed, and publishes `revisions.json`, plus a scan record for its own next run, on the repository's `revisions` release. The app fetches that one file at launch and on activation, caches it beside the RFC index, and shows the drafts through pure functions in RFCReaderKit. Datatracker's vocabulary (states, adoption, stages) and the scan's bookkeeping are pure functions in `RFCCorpusKit`. The file format and the draft-header reading live in RFCKit, which both sides share.

**Tech Stack:** Swift 6 (strict concurrency), Foundation / FoundationXML / FoundationNetworking, swift-argument-parser, swift-log, SwiftUI + AppKit/UIKit, Swift Testing, GitHub Actions, `gh`.

**Spec:** `docs/superpowers/specs/2026-09-29-rfc-revisions-design.md`. Read it before starting; this plan argues from it.

## Global Constraints

- Work on a new branch `feat/rfc-revisions`, cut from `spec/rfc-revisions`, in the worktree `/Users/moritz/Projects/rfc-reader/.claude/worktrees/rfc-revisions`. Other sessions share the main checkout, so check `git branch --show-current` before every commit. Never use a bare `git stash`.
- **RFCKit stays Linux-clean**: `FoundationXML` and `FoundationNetworking` are imported only behind `#if canImport(…)`. Nothing SwiftUI in RFCKit, nothing XML in the app.
- **The App target has no test bundle.** Everything testable goes in RFCReaderKit, RFCKit or `RFCCorpusKit`. The App target only wires views and notifications.
- **On macOS a hosted root is outside the environment chain.** `StatusBanner` and `InfoView` reach `LibraryModel` through the properties they are handed, never through `@Environment(LibraryModel.self)`.
- **No RFC or draft text is committed.** Guard-level tests use hand-written lines *shaped* like a draft header, with made-up names and numbers (use 9990–9999 for RFC numbers), never quoted from a real draft.
- Tests use Swift Testing and raw-identifier names: ``@Test func `a thing that is pinned`()``.
- State rules compare `(type slug, state slug)` pairs, never display names. The table in Task 4 has every pair.
- Stage labels, verbatim: "In the RFC Editor queue", "Approved for publication", "Under IESG review", "In IETF Last Call", "Submitted for publication", "In working group last call", "In the working group", and "Under review" for an Independent draft in `inGroup`.
- Relation labels, verbatim: "Being replaced by" (obsoletes), "Being updated by" (updates).
- Staleness: `generatedAt` more than **3 days** before now. Dormancy: the revision was published more than **365 days** before now. Refresh: at launch, and on activation when the last successful fetch is more than **24 hours** old. Banner: at most **2** rows, then "and N more". Shrink guard: fails when the previous projection had **≥ 10** RFCs and the new one has fewer than half as many, unless `--allow-shrink`.
- File URL: `https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json`. User-Agent: `rfc-reader corpus-build (+https://github.com/Radiergummi/rfc-reader)`.
- `make lint` is clean with `--strict`; run `make fmt` before committing. Lines cap at 200.
- Commit with a signed commit. If signing fails because Secretive is locked, use `git -c gpg.format=openpgp -c user.signingkey=8F4ED9558B0722C0 commit …`. Messages are prose in the repository's style and end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Commands: `swift test --package-path Packages/RFCKit --filter <Suite>`, `swift test --package-path Tools/corpus-build --filter <Suite>`, `swift test --package-path Packages/RFCReaderKit --filter <Suite>`; `make check` before every commit that touches `Packages/` or `Tools/`; `make test-app` for RFCReaderKit; `make build-app` and `make ios-sim` for the app.

## Review Focus

The inputs most likely to bite a person, each pinned by a test in the task named:

1. **A draft whose read fails on its very first scan** is read again the next day, not forgotten until it next changes. Pinned in Task 6 (`a draft that failed on its first read is read again`).
2. **Datatracker's publish dates with and without fractional seconds** (`…41.095128+00:00` and `…29+00:00`) both decode. A failure would fail every draft. Pinned in Task 5.
3. **A text-only draft whose `Updates:` list runs onto a second, indented line, beside the author column** yields every number and none of the author text. Pinned in Task 2.
4. **An old file on an offline launch** shows "as of" on every row, and a 2014 draft shows its revision's date, so neither reads as current news. Pinned in Task 9.
5. **An RFC nothing revises, and a document that is not an RFC (BCP 14)** shows no row and no "no revisions" text. Pinned in Task 9 and Task 10.

---

## File Structure

**RFCKit (`Packages/RFCKit/Sources/RFCKit/`)**
- `Models/RFCRevisions.swift`: create. The shared file format, `RevisionStage`, and the JSON coders.
- `Index/XMLDriver.swift`: modify. `rootElement(of:)`, a parse that stops at the root element.
- `Document/RFCXMLParser.swift`: modify. `parseDocumentList` becomes an internal `static` on `RFCXMLParser`.
- `Document/DraftHeader.swift`: create. `obsoletes`/`updates` from a draft's XML root or its text front page.
- `Client/RevisionsClient.swift`: create. Fetches and decodes `revisions.json`.

**RFCKit tests (`Packages/RFCKit/Tests/RFCKitTests/`)**: create `RFCRevisionsTests.swift`, `DraftHeaderTests.swift`, `RevisionsClientTests.swift`.

**corpus-build (`Tools/corpus-build/`)**
- `Sources/RFCCorpusKit/DraftStates.swift`: create. `DraftState`, adoption, stage mapping.
- `Sources/RFCCorpusKit/Datatracker.swift`: create. The API's URLs and decoded shapes.
- `Sources/RFCCorpusKit/RevisionScan.swift`: create. The scan record, what to read, merge, projection, shrink guard.
- `Sources/corpus-build/RevisionsCommand.swift`: create. The network run.
- `Sources/corpus-build/CorpusBuild.swift`: modify. Register the subcommand; usage comment.
- Tests: create `DraftStatesTests.swift`, `DatatrackerTests.swift`, `RevisionScanTests.swift`; modify `CommandLineTests.swift`.

**Repository**
- `.github/workflows/revisions.yml`: create.
- `Makefile`: modify. A `revisions` target.
- `docs/DATA_PIPELINE.md`, `docs/ARCHITECTURE.md`: modify. The workflow and the decision.

**RFCReaderKit (`Packages/RFCReaderKit/`)**
- `Sources/RFCReaderKit/RevisionsSummary.swift`: create. Ordering, staleness, dormancy, lines, sentences.
- `Sources/RFCReaderKit/DocumentInfo.swift`: modify. The `.drafts` value; "Being replaced by" / "Being updated by" rows.
- Tests: create `RevisionsSummaryTests.swift`; modify `DocumentInfoTests.swift`.

**App (`App/RFCReader/`)**
- `Model/DocumentStore.swift`: the cached file.
- `Model/LibraryModel.swift`: `revisions`, load, refresh, the activation observer, `revisionsSummary(for:)`.
- `Views/DocumentView.swift`: `StatusBanner` rows; `deriveInfo` passes the summary and runs again when the file changes.
- `Views/Rendering/InfoView.swift`: draws `.drafts`.

---

### Task 1: The file format in RFCKit

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Models/RFCRevisions.swift`
- Test: `Packages/RFCKit/Tests/RFCKitTests/RFCRevisionsTests.swift`

**Interfaces:**
- Produces: `RFCRevisions` (`version`, `generatedAt`, `revisions: [Int: [Revision]]`, `init(generatedAt:revisions:)`, `static func decode(_: Data) throws -> RFCRevisions`, `func encoded() throws -> Data`, `static let currentVersion = 1`, `enum VersionError: Error, Equatable { case unknown(Int) }`), `RFCRevisions.Revision` (memberwise `init(relation:draft:revision:published:stream:group:intendedStatus:stage:)`), `RFCRevisions.Revision.Relation` (`.obsoletes`, `.updates`), `RevisionStage` (`inGroup, lastCall, submitted, ietfLastCall, iesgReview, approved, rfcEditorQueue`, `Comparable` in that order).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCKit

/// `revisions.json`, which the scanner writes and the app reads: one format, so both
/// sides go through the same coders.
@Suite("RFC revisions file")
struct RFCRevisionsTests {
  private let sample = RFCRevisions(
    generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
    revisions: [
      9999: [
        RFCRevisions.Revision(
          relation: .obsoletes, draft: "draft-ietf-example-rfc9999bis", revision: "04",
          published: Date(timeIntervalSince1970: 1_780_000_000), stream: "ietf",
          group: "example", intendedStatus: "Proposed Standard", stage: .rfcEditorQueue)
      ]
    ])

  @Test func `a file round-trips through its own coders`() throws {
    #expect(try RFCRevisions.decode(sample.encoded()) == sample)
  }

  /// JSON has no integer keys. The number is written as a string and read back as
  /// the number, which is what the app looks it up by.
  @Test func `an RFC number is a string key in the JSON`() throws {
    let json = String(decoding: try sample.encoded(), as: UTF8.self)
    #expect(json.contains("\"9999\""))
  }

  @Test func `a file of an unknown version is refused`() throws {
    var json = String(decoding: try sample.encoded(), as: UTF8.self)
    json = json.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
    #expect(throws: RFCRevisions.VersionError.unknown(2)) {
      try RFCRevisions.decode(Data(json.utf8))
    }
  }

  @Test func `stages are ordered from earliest to furthest along`() {
    #expect(
      RevisionStage.allCases.sorted() == [
        .inGroup, .lastCall, .submitted, .ietfLastCall, .iesgReview, .approved, .rfcEditorQueue,
      ])
    #expect(RevisionStage.rfcEditorQueue > .approved)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter RFCRevisionsTests`
Expected: FAIL to compile, "cannot find 'RFCRevisions' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// `revisions.json`: the adopted Internet-Drafts that intend to obsolete or update an
/// RFC, by the RFC's number. `corpus-build revisions` writes it daily and the app reads
/// it (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md). Both sides encode and
/// decode through `encoded()` and `decode(_:)`, so they agree on dates and keys.
public struct RFCRevisions: Codable, Sendable, Equatable {
  /// The only version this build reads. Bumped on any change a reader of an older
  /// version would misread.
  public static let currentVersion = 1

  public enum VersionError: Error, Equatable {
    case unknown(Int)
  }

  public var version: Int
  /// When the run that wrote the file started. A change made during the run may be in
  /// it or not, but never one from before this time.
  public var generatedAt: Date
  /// RFC number → the drafts that intend to obsolete or update it.
  public var revisions: [Int: [Revision]]

  public struct Revision: Codable, Sendable, Equatable {
    public enum Relation: String, Codable, Sendable {
      case obsoletes
      case updates
    }

    public var relation: Relation
    /// "draft-ietf-httpbis-rfc6265bis", without the revision.
    public var draft: String
    /// "22".
    public var revision: String
    /// When this revision was posted.
    public var published: Date
    /// "ietf", "irtf", "iab", "ise" or "editorial".
    public var stream: String
    /// "httpbis"; nil when the draft is in no group.
    public var group: String?
    /// "Proposed Standard".
    public var intendedStatus: String?
    public var stage: RevisionStage

    public init(
      relation: Relation, draft: String, revision: String, published: Date, stream: String,
      group: String?, intendedStatus: String?, stage: RevisionStage
    ) {
      self.relation = relation
      self.draft = draft
      self.revision = revision
      self.published = published
      self.stream = stream
      self.group = group
      self.intendedStatus = intendedStatus
      self.stage = stage
    }
  }

  public init(generatedAt: Date, revisions: [Int: [Revision]]) {
    self.version = Self.currentVersion
    self.generatedAt = generatedAt
    self.revisions = revisions
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case generatedAt
    case revisions
  }

  /// Reads `version` first, and refuses a version this build does not know: a newer
  /// file may mean something an older reader would misread.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == Self.currentVersion else { throw VersionError.unknown(version) }
    self.version = version
    self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    self.revisions = try container.decode([Int: [Revision]].self, forKey: .revisions)
  }

  public static func decode(_ data: Data) throws -> RFCRevisions {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RFCRevisions.self, from: data)
  }

  /// Sorted keys, so two runs over the same drafts write the same bytes.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}

/// How far along a draft is, from earliest to furthest. The scanner maps datatracker's
/// states onto it (`DraftStates` in RFCCorpusKit); the app words it
/// (`RevisionsSummary` in RFCReaderKit).
public enum RevisionStage: String, Codable, Sendable, CaseIterable, Comparable {
  case inGroup
  case lastCall
  case submitted
  case ietfLastCall
  case iesgReview
  case approved
  case rfcEditorQueue

  public static func < (lhs: RevisionStage, rhs: RevisionStage) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}
```

If SwiftLint flags the two force unwraps in `<`, replace them with `(allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCKit --filter RFCRevisionsTests`
Expected: PASS, 4 tests. (The sample's dates are whole seconds; `.iso8601` drops fractions.)

- [ ] **Step 5: Commit**

```bash
make fmt && make check
git add Packages/RFCKit/Sources/RFCKit/Models/RFCRevisions.swift Packages/RFCKit/Tests/RFCKitTests/RFCRevisionsTests.swift
git commit -m "Add the revisions file format, shared by the scanner and the app"
```

---

### Task 2: Reading a draft's header in RFCKit

**Files:**
- Modify: `Packages/RFCKit/Sources/RFCKit/Index/XMLDriver.swift` (add below `run`)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/RFCXMLParser.swift:148-149, 169-174`
- Create: `Packages/RFCKit/Sources/RFCKit/Document/DraftHeader.swift`
- Test: `Packages/RFCKit/Tests/RFCKitTests/DraftHeaderTests.swift`

**Interfaces:**
- Produces: `public struct DraftHeader: Equatable, Sendable { obsoletes: [Int]; updates: [Int]; unreadable: [String] }` with `init(obsoletes:updates:unreadable:)` (all defaulted), `public static func parse(xml: Data) throws(XMLSyntaxError) -> DraftHeader`, `public static func parse(text: Data) -> DraftHeader`, `static func parse(frontPage: [String]) -> DraftHeader` (internal, for guard-level tests). `XMLDriver.rootElement(of:) throws(XMLSyntaxError) -> (name: String, attributes: [String: String])`. `RFCXMLParser.parseDocumentList(_: String?) -> [DocumentID]` (internal static).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCKit

/// What a draft says it will do to published RFCs, from the attributes of its XML
/// root or the left column of its text front page. Every input is hand-written in
/// the shape of a draft header, with made-up names and numbers.
@Suite("Draft header")
struct DraftHeaderTests {
  private func xml(_ attributes: String, prologue: String = "") -> Data {
    Data("\(prologue)<rfc docName=\"draft-example-thing-03\" \(attributes)><front/></rfc>".utf8)
  }

  @Test func `a root that declares both lists yields both`() throws {
    let header = try DraftHeader.parse(xml: xml(#"obsoletes="9990, 9991" updates="9992""#))
    #expect(header == DraftHeader(obsoletes: [9990, 9991], updates: [9992]))
  }

  @Test func `a root with neither attribute revises nothing, and is not unreadable`() throws {
    #expect(try DraftHeader.parse(xml: xml("")) == DraftHeader())
  }

  /// `parseDocumentList` drops what is not a number; a present attribute that
  /// yields none is kept aside so the scanner can log the lost entry.
  @Test func `an attribute that names no number is unreadable`() throws {
    let header = try DraftHeader.parse(xml: xml(#"obsoletes="RFC9990""#))
    #expect(header.obsoletes.isEmpty)
    #expect(header.unreadable == ["RFC9990"])
  }

  /// A v2 draft declares external entities its body uses. Parsing stops at the
  /// root, so they are never resolved.
  @Test func `a DOCTYPE with an external entity does not stop the reading`() throws {
    let prologue = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE rfc SYSTEM "rfc2629.dtd" [
      <!ENTITY RFC9990 SYSTEM "https://example.invalid/reference.RFC.9990.xml">
      ]>
      """
    let data = Data(
      "\(prologue)<rfc obsoletes=\"9990\"><back><references>&RFC9990;</references></back></rfc>"
        .utf8)
    #expect(try DraftHeader.parse(xml: data).obsoletes == [9990])
  }

  @Test func `a single number on the front page is read`() {
    let lines = [
      "",
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Obsoletes: 9990 (if approved)                                 B. Writer",
      "Intended status: Standards Track                           Example Inc",
      "Expires: 1 April 2027                                   28 September 2026",
      "",
      "                   An Example Protocol, Revised",
    ]
    #expect(DraftHeader.parse(frontPage: lines) == DraftHeader(obsoletes: [9990]))
  }

  @Test func `several numbers and both labels are read`() {
    let lines = [
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Obsoletes: 9990, 9991 (if approved)                           B. Writer",
      "Updates: 9992 (if approved)                                Example Inc",
      "Intended status: Standards Track",
    ]
    #expect(
      DraftHeader.parse(frontPage: lines)
        == DraftHeader(obsoletes: [9990, 9991], updates: [9992]))
  }

  @Test func `a list continued on the next indented line is read whole`() {
    let lines = [
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Updates: 9990, 9991, 9992,                                    B. Writer",
      "         9993 (if approved)                                Example Inc",
      "Intended status: Standards Track                           C. Somebody",
    ]
    #expect(DraftHeader.parse(frontPage: lines).updates == [9990, 9991, 9992, 9993])
  }

  @Test func `an RFC prefix on the front page is read past`() {
    let lines = ["Internet-Draft", "Obsoletes: RFC 9990 (if approved)", "Intended status: Informational"]
    #expect(DraftHeader.parse(frontPage: lines).obsoletes == [9990])
  }

  @Test func `a front page with neither label revises nothing`() {
    let lines = [
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Intended status: Informational                            28 September 2026",
    ]
    #expect(DraftHeader.parse(frontPage: lines) == DraftHeader())
  }

  /// The header block ends at its first blank line: an "Updates:" in the prose
  /// below is not the header's.
  @Test func `a label below the header block is not read`() {
    let lines = [
      "Internet-Draft                                             Example Corp",
      "Intended status: Informational",
      "",
      "Updates: 9990",
    ]
    #expect(DraftHeader.parse(frontPage: lines) == DraftHeader())
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter DraftHeaderTests`
Expected: FAIL to compile, "cannot find 'DraftHeader' in scope".

- [ ] **Step 3: Make `parseDocumentList` static on `RFCXMLParser`**

In `RFCXMLParser.swift`, delete the `private func parseDocumentList` from `Builder` (lines 169–174) and add it beside `relation(_:includes:)` (line 63), on `RFCXMLParser` itself:

```swift
  /// The RFC numbers in an `obsoletes` or `updates` attribute, "2616, 7230". Anything
  /// that is not a number is dropped. Shared with `DraftHeader`, which reads a draft's
  /// root the same way.
  static func parseDocumentList(_ value: String?) -> [DocumentID] {
    guard let value else { return [] }
    return value.split(whereSeparator: { $0 == "," || $0 == " " })
      .compactMap { Int($0) }
      .map { DocumentID.rfc($0) }
  }
```

Change lines 148–149 of `parseHeader` to:

```swift
      header.obsoletes = RFCXMLParser.parseDocumentList(rfc["obsoletes"])
      header.updates = RFCXMLParser.parseDocumentList(rfc["updates"])
```

- [ ] **Step 4: Add `XMLDriver.rootElement(of:)`**

In `XMLDriver.swift`, inside `enum XMLDriver`, after `run(_:into:)`:

```swift
  /// The root element's name and attributes, and nothing after them. A draft's header
  /// is all `DraftHeader` reads, and a v2 draft's DOCTYPE often declares external
  /// entities its body uses. They are never resolved, and a full parse would stop on
  /// them.
  static func rootElement(of data: Data) throws(XMLSyntaxError) -> (
    name: String, attributes: [String: String]
  ) {
    let delegate = RootDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    _ = parser.parse()
    // Stopping at the root is reported as an error; with the root read, it is not one.
    if let root = delegate.root { return root }
    throw XMLSyntaxError(
      line: parser.lineNumber, column: parser.columnNumber,
      message: parser.parserError?.localizedDescription ?? "empty document")
  }

  private final class RootDelegate: NSObject, XMLParserDelegate {
    private(set) var root: (name: String, attributes: [String: String])?

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      root = (elementName, attributeDict)
      parser.abortParsing()
    }
  }
```

- [ ] **Step 5: Write `DraftHeader`**

```swift
import Foundation

/// What an Internet-Draft says it will do to published RFCs, read from its header:
/// the `obsoletes` and `updates` attributes of its XML root, or the `Obsoletes:` and
/// `Updates:` lines of its text front page. Datatracker records neither relation
/// until the draft is published, so the revisions scanner reads them here
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md).
public struct DraftHeader: Equatable, Sendable {
  public var obsoletes: [Int]
  public var updates: [Int]
  /// Attributes or lines that were there but named no RFC number, such as
  /// `obsoletes="RFC6265"`. Worth logging: the entry is lost.
  public var unreadable: [String]

  public init(obsoletes: [Int] = [], updates: [Int] = [], unreadable: [String] = []) {
    self.obsoletes = obsoletes
    self.updates = updates
    self.unreadable = unreadable
  }

  public static func parse(xml data: Data) throws(XMLSyntaxError) -> DraftHeader {
    let attributes = try XMLDriver.rootElement(of: data).attributes
    var unreadable: [String] = []
    let obsoletes = numbers(in: attributes["obsoletes"], reading: xmlNumbers, unreadable: &unreadable)
    let updates = numbers(in: attributes["updates"], reading: xmlNumbers, unreadable: &unreadable)
    return DraftHeader(obsoletes: obsoletes, updates: updates, unreadable: unreadable)
  }

  public static func parse(text data: Data) -> DraftHeader {
    parse(frontPage: String(decoding: data, as: UTF8.self).components(separatedBy: .newlines))
  }

  /// The header block is the lines from the first that is not blank to the next blank
  /// one. Its left column, up to the first run of two spaces, carries the labels; a
  /// list that runs on continues on the next line, indented, starting with a number.
  static func parse(frontPage lines: [String]) -> DraftHeader {
    enum Label {
      case obsoletes
      case updates
    }

    let block = lines.drop(while: isBlank).prefix(while: { !isBlank($0) })
    var obsoletes: [Int] = []
    var updates: [Int] = []
    var unreadable: [String] = []
    var label: Label?
    var collected = ""

    func flush() {
      let found = numbers(in: collected, reading: textNumbers, unreadable: &unreadable)
      switch label {
      case .obsoletes: obsoletes += found
      case .updates: updates += found
      case nil: break
      }
      label = nil
      collected = ""
    }

    for line in block {
      let left = leftColumn(line)
      if let rest = value(of: "Obsoletes:", in: left) {
        flush()
        label = .obsoletes
        collected = rest
      } else if let rest = value(of: "Updates:", in: left) {
        flush()
        label = .updates
        collected = rest
      } else if label != nil, line.first?.isWhitespace == true,
        left.first?.isNumber == true || left.uppercased().hasPrefix("RFC")
      {
        collected += " " + left
      } else {
        flush()
      }
    }
    flush()
    return DraftHeader(obsoletes: obsoletes, updates: updates, unreadable: unreadable)
  }

  /// The numbers in `value`, read by `read`. A value that is there and not blank but
  /// yields none goes to `unreadable`.
  private static func numbers(
    in value: String?, reading read: (String) -> [Int], unreadable: inout [String]
  ) -> [Int] {
    guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    let numbers = read(value)
    if numbers.isEmpty { unreadable.append(value) }
    return numbers
  }

  /// "2616, 7230", read as the RFC parser reads its own header.
  private static func xmlNumbers(_ value: String) -> [Int] {
    RFCXMLParser.parseDocumentList(value).map(\.number)
  }

  /// "9990, RFC 9991, RFC9992 (if approved)": the numbers, past an "RFC" before any.
  private static func textNumbers(_ value: String) -> [Int] {
    value.replacingOccurrences(of: "(if approved)", with: "", options: .caseInsensitive)
      .split(whereSeparator: { $0 == "," || $0.isWhitespace })
      .compactMap { token -> Int? in
        var token = Substring(token)
        if token.uppercased().hasPrefix("RFC") { token = token.dropFirst(3) }
        return Int(token)
      }
  }

  private static func isBlank(_ line: String) -> Bool {
    line.allSatisfy(\.isWhitespace)
  }

  /// The line's text up to its first run of two spaces, past its indent: the author
  /// column on the right never reaches it.
  private static func leftColumn(_ line: String) -> String {
    let trimmed = line.drop(while: \.isWhitespace)
    guard let gap = trimmed.range(of: "  ") else {
      return String(trimmed).trimmingCharacters(in: .whitespaces)
    }
    return String(trimmed[..<gap.lowerBound])
  }

  private static func value(of label: String, in left: String) -> String? {
    guard left.hasPrefix(label) else { return nil }
    return String(left.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
  }
}
```

Both readers collect into locals and build the header once at the end, so no access to one value overlaps another.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCKit --filter "DraftHeaderTests|RFCXMLParserTests|XMLDriverTests"`
Expected: PASS. The existing parser and driver suites still pass, so moving `parseDocumentList` changed nothing.

- [ ] **Step 7: Commit**

```bash
make fmt && make check
git add Packages/RFCKit/Sources/RFCKit/Index/XMLDriver.swift Packages/RFCKit/Sources/RFCKit/Document/RFCXMLParser.swift Packages/RFCKit/Sources/RFCKit/Document/DraftHeader.swift Packages/RFCKit/Tests/RFCKitTests/DraftHeaderTests.swift
git commit -m "Read what a draft obsoletes and updates from its header"
```

---

### Task 3: The client in RFCKit

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Client/RevisionsClient.swift`
- Test: `Packages/RFCKit/Tests/RFCKitTests/RevisionsClientTests.swift`

**Interfaces:**
- Consumes: `RFCRevisions.decode(_:)`, `RFCRevisions.VersionError` (Task 1); `HTTPTransport`, `RFCEditorClient.ClientError.httpStatus` (existing).
- Produces: `public struct RevisionsClient: Sendable` with `static let url: URL`, `init(transport: any HTTPTransport = URLSession.shared)`, `func fetch() async throws -> (revisions: RFCRevisions, data: Data)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("Revisions client")
struct RevisionsClientTests {
  /// One answer for every request.
  private struct Answer: HTTPTransport {
    let status: Int
    let body: Data

    func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
      (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
  }

  private let file = RFCRevisions(generatedAt: Date(timeIntervalSince1970: 1_790_000_000), revisions: [:])

  @Test func `a published file is decoded, and its bytes come with it`() async throws {
    let data = try file.encoded()
    let fetched = try await RevisionsClient(transport: Answer(status: 200, body: data)).fetch()
    #expect(fetched.revisions == file)
    #expect(fetched.data == data)
  }

  /// `--clobber` deletes the asset before it uploads the new one.
  @Test func `a missing file is an error, not an empty file`() async throws {
    await #expect(throws: RFCEditorClient.ClientError.self) {
      try await RevisionsClient(transport: Answer(status: 404, body: Data())).fetch()
    }
  }

  @Test func `a file of an unknown version is an error`() async throws {
    let json = String(decoding: try file.encoded(), as: UTF8.self)
      .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
    await #expect(throws: RFCRevisions.VersionError.unknown(2)) {
      try await RevisionsClient(transport: Answer(status: 200, body: Data(json.utf8))).fetch()
    }
  }

  @Test func `the file is fetched from the revisions release`() {
    #expect(
      RevisionsClient.url.absoluteString
        == "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter RevisionsClientTests`
Expected: FAIL to compile, "cannot find 'RevisionsClient' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Fetches `revisions.json`, which the revisions workflow publishes daily on the
/// repository's `revisions` release. A plain GET: every run writes a new
/// `generatedAt`, so a conditional request would never be answered 304.
public struct RevisionsClient: Sendable {
  public static let url = URL(
    string: "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json")!

  private let transport: any HTTPTransport

  public init(transport: any HTTPTransport = URLSession.shared) {
    self.transport = transport
  }

  /// The decoded file and the bytes it came as, which the caller keeps.
  public func fetch() async throws -> (revisions: RFCRevisions, data: Data) {
    let (data, response) = try await transport.data(for: Self.url)
    guard (200..<300).contains(response.statusCode) else {
      throw RFCEditorClient.ClientError.httpStatus(response.statusCode, Self.url)
    }
    return (try RFCRevisions.decode(data), data)
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCKit --filter RevisionsClientTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
make fmt && make check
git add Packages/RFCKit/Sources/RFCKit/Client/RevisionsClient.swift Packages/RFCKit/Tests/RFCKitTests/RevisionsClientTests.swift
git commit -m "Fetch the revisions file from its release"
```

---

### Task 4: Datatracker's states: adoption and stage

**Files:**
- Create: `Tools/corpus-build/Sources/RFCCorpusKit/DraftStates.swift`
- Test: `Tools/corpus-build/Tests/RFCCorpusKitTests/DraftStatesTests.swift`

**Interfaces:**
- Consumes: `RevisionStage` (Task 1).
- Produces: `public struct DraftState: Hashable, Sendable, Codable { type: String; slug: String; init(_ type: String, _ slug: String); var isStreamState: Bool }`; `public enum DraftStates { static func isAdopted(_: [DraftState]) -> Bool; static func stage(_: [DraftState]) -> RevisionStage; static func stage(of: DraftState) -> RevisionStage }`.

Every pair, from `doc/state/` on 29 September 2026 (type slug / state slug → name):

| Rule | Pairs |
|---|---|
| not adopted | `draft-stream-ietf`: `wg-cand` Candidate for WG Adoption, `c-adopt` Call For Adoption By WG Issued, `info` Adopted for WG Info Only, `parked` Parked WG Document, `dead` Dead WG Document · `draft-stream-irtf`: `candidat`, `parked`, `dead`, `repl` · `draft-stream-iab`: `candidat`, `parked`, `dead`, `repl`, `diff-org` · `draft-stream-ise`: `receive` Submission Received, `repl`, `dead` No Longer In Independent Submission Stream · `draft-stream-editorial`: `repl`, `dead` · `draft-iesg`: `dead`, `nopubadw`, `nopubanw` |
| nothing happened (IESG) | `draft-iesg`: `idexists` I-D Exists, `watching` AD is watching |
| `rfcEditorQueue` | `draft-iesg/rfcqueue`; any `draft-rfceditor/*`; any `draft-stream-*/rfc-edit` |
| `approved` | `draft-iesg/approved`, `draft-iesg/ann`, `draft-stream-iab/approved` |
| `iesgReview` | `draft-iesg/writeupw`, `draft-iesg/goaheadw`, `draft-iesg/iesg-eva`, `draft-iesg/defer`; any `draft-stream-*/iesg-rev` |
| `ietfLastCall` | `draft-iesg/lc-req`, `draft-iesg/lc` |
| `submitted` | `draft-iesg/pub-req`, `draft-iesg/ad-eval`, `draft-iesg/review-e`; `draft-stream-ietf/sub-pub`; `draft-stream-irtf/chair-w`, `irsg-w`, `irsg_review`, `irsgpoll`; `draft-stream-iab/review-c`, `review-i`; `draft-stream-ise/find-rev`, `ise-rev`, `need-res`; `draft-stream-editorial/rsabpoll` |
| `lastCall` | `draft-stream-ietf/wg-lc`, `draft-stream-irtf/rg-lc` |
| `inGroup` | everything else |

- [ ] **Step 1: Write the failing tests**

```swift
import RFCCorpusKit
import RFCKit
import Testing

/// Datatracker's states, by their slugs: which make a draft adopted, and how far
/// along each says it is (spec, "Adopted" and "Stages").
@Suite("Draft states")
struct DraftStatesTests {
  private static let active = DraftState("draft", "active")

  @Test(arguments: [
    DraftState("draft-stream-ietf", "wg-cand"), DraftState("draft-stream-ietf", "c-adopt"),
    DraftState("draft-stream-ietf", "info"), DraftState("draft-stream-ietf", "parked"),
    DraftState("draft-stream-ietf", "dead"), DraftState("draft-stream-irtf", "candidat"),
    DraftState("draft-stream-irtf", "parked"), DraftState("draft-stream-irtf", "dead"),
    DraftState("draft-stream-irtf", "repl"), DraftState("draft-stream-iab", "candidat"),
    DraftState("draft-stream-iab", "parked"), DraftState("draft-stream-iab", "dead"),
    DraftState("draft-stream-iab", "repl"), DraftState("draft-stream-iab", "diff-org"),
    DraftState("draft-stream-ise", "receive"), DraftState("draft-stream-ise", "repl"),
    DraftState("draft-stream-ise", "dead"), DraftState("draft-stream-editorial", "repl"),
    DraftState("draft-stream-editorial", "dead"), DraftState("draft-iesg", "dead"),
    DraftState("draft-iesg", "nopubadw"), DraftState("draft-iesg", "nopubanw"),
  ])
  func `a state that means not adopted or stopped excludes the draft`(state: DraftState) {
    #expect(!DraftStates.isAdopted([Self.active, DraftState("draft-iesg", "pub-req"), state]))
  }

  @Test func `a working group document is adopted`() {
    #expect(DraftStates.isAdopted([Self.active, DraftState("draft-stream-ietf", "wg-doc"), DraftState("draft-iesg", "idexists")]))
  }

  /// An AD-sponsored draft has no stream state, only an IESG state that has moved.
  @Test func `a draft with no stream state counts once the IESG has it`() {
    #expect(DraftStates.isAdopted([Self.active, DraftState("draft-iesg", "pub-req")]))
  }

  /// Measured: every active IETF-stream draft in no group had exactly these.
  @Test(arguments: ["idexists", "watching"])
  func `a draft with no stream state and an untouched IESG state is not adopted`(slug: String) {
    #expect(!DraftStates.isAdopted([Self.active, DraftState("draft-iesg", slug)]))
  }

  @Test func `a draft with no states beyond active is not adopted`() {
    #expect(!DraftStates.isAdopted([Self.active]))
  }

  /// States and stream need not agree: an IETF-stream draft can carry an ISE state.
  @Test func `an excluded state counts whatever the draft's stream`() {
    #expect(!DraftStates.isAdopted([Self.active, DraftState("draft-stream-ise", "dead"), DraftState("draft-iesg", "pub-req")]))
  }

  @Test(arguments: [
    (DraftState("draft-iesg", "rfcqueue"), RevisionStage.rfcEditorQueue),
    (DraftState("draft-rfceditor", "auth48"), .rfcEditorQueue),
    (DraftState("draft-rfceditor", "missref"), .rfcEditorQueue),
    (DraftState("draft-stream-ise", "rfc-edit"), .rfcEditorQueue),
    (DraftState("draft-stream-editorial", "rfc-edit"), .rfcEditorQueue),
    (DraftState("draft-iesg", "approved"), .approved),
    (DraftState("draft-iesg", "ann"), .approved),
    (DraftState("draft-stream-iab", "approved"), .approved),
    (DraftState("draft-iesg", "iesg-eva"), .iesgReview),
    (DraftState("draft-iesg", "defer"), .iesgReview),
    (DraftState("draft-iesg", "writeupw"), .iesgReview),
    (DraftState("draft-iesg", "goaheadw"), .iesgReview),
    (DraftState("draft-stream-irtf", "iesg-rev"), .iesgReview),
    (DraftState("draft-iesg", "lc-req"), .ietfLastCall),
    (DraftState("draft-iesg", "lc"), .ietfLastCall),
    (DraftState("draft-iesg", "pub-req"), .submitted),
    (DraftState("draft-iesg", "ad-eval"), .submitted),
    (DraftState("draft-iesg", "review-e"), .submitted),
    (DraftState("draft-stream-ietf", "sub-pub"), .submitted),
    (DraftState("draft-stream-irtf", "irsg_review"), .submitted),
    (DraftState("draft-stream-iab", "review-c"), .submitted),
    (DraftState("draft-stream-ise", "ise-rev"), .submitted),
    (DraftState("draft-stream-editorial", "rsabpoll"), .submitted),
    (DraftState("draft-stream-ietf", "wg-lc"), .lastCall),
    (DraftState("draft-stream-irtf", "rg-lc"), .lastCall),
    (DraftState("draft-stream-ietf", "wg-doc"), .inGroup),
    (DraftState("draft-iesg", "idexists"), .inGroup),
  ])
  func `each state maps to its stage`(state: DraftState, stage: RevisionStage) {
    #expect(DraftStates.stage(of: state) == stage)
  }

  @Test func `the furthest stage of a draft's states wins`() {
    let states = [
      Self.active, DraftState("draft-stream-ietf", "sub-pub"), DraftState("draft-iesg", "rfcqueue"),
      DraftState("draft-rfceditor", "edit"),
    ]
    #expect(DraftStates.stage(states) == .rfcEditorQueue)
  }

  /// A state datatracker adds later degrades to the vaguest true answer.
  @Test func `an unknown state falls back to in the group`() {
    #expect(DraftStates.stage([DraftState("draft-stream-ietf", "something-new")]) == .inGroup)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Tools/corpus-build --filter DraftStatesTests`
Expected: FAIL to compile, "cannot find 'DraftState' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import RFCKit

/// A datatracker document state, by the two names datatracker keeps stable: its
/// type's slug, `draft-iesg`, and its own, `idexists`. The display names ("I-D
/// Exists") are for people.
public struct DraftState: Hashable, Sendable, Codable {
  public var type: String
  public var slug: String

  public init(_ type: String, _ slug: String) {
    self.type = type
    self.slug = slug
  }

  /// A state of the stream a draft is in: IETF, IRTF, IAB, Independent or Editorial.
  public var isStreamState: Bool { type.hasPrefix("draft-stream-") }
}

/// Which drafts count as revisions under way, and how far along each is
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "Adopted" and "Stages").
/// The pairs are datatracker's, from `doc/state/` on 29 September 2026.
public enum DraftStates {
  /// A state that means "not adopted yet" or "stopped". Checked whatever the draft's
  /// stream: states and stream need not agree.
  static let notAdopted: Set<DraftState> = [
    DraftState("draft-stream-ietf", "wg-cand"),
    DraftState("draft-stream-ietf", "c-adopt"),
    // Adopted without publication: the working group keeps it for reference.
    DraftState("draft-stream-ietf", "info"),
    DraftState("draft-stream-ietf", "parked"),
    DraftState("draft-stream-ietf", "dead"),
    DraftState("draft-stream-irtf", "candidat"),
    DraftState("draft-stream-irtf", "parked"),
    DraftState("draft-stream-irtf", "dead"),
    DraftState("draft-stream-irtf", "repl"),
    DraftState("draft-stream-iab", "candidat"),
    DraftState("draft-stream-iab", "parked"),
    DraftState("draft-stream-iab", "dead"),
    DraftState("draft-stream-iab", "repl"),
    DraftState("draft-stream-iab", "diff-org"),
    DraftState("draft-stream-ise", "receive"),
    DraftState("draft-stream-ise", "repl"),
    DraftState("draft-stream-ise", "dead"),
    DraftState("draft-stream-editorial", "repl"),
    DraftState("draft-stream-editorial", "dead"),
    DraftState("draft-iesg", "dead"),
    DraftState("draft-iesg", "nopubadw"),
    DraftState("draft-iesg", "nopubanw"),
  ]

  /// IESG states that say nothing has happened yet.
  static let untouched: Set<DraftState> = [
    DraftState("draft-iesg", "idexists"),
    DraftState("draft-iesg", "watching"),
  ]

  /// Adopted: no state excludes it, and it has a stream state or, when it has none
  /// (AD-sponsored), an IESG state past the untouched ones.
  public static func isAdopted(_ states: [DraftState]) -> Bool {
    if states.contains(where: notAdopted.contains) { return false }
    if states.contains(where: \.isStreamState) { return true }
    return states.contains { $0.type == "draft-iesg" && !untouched.contains($0) }
  }

  /// The furthest stage any of the states reaches.
  public static func stage(_ states: [DraftState]) -> RevisionStage {
    states.map(stage(of:)).max() ?? .inGroup
  }

  public static func stage(of state: DraftState) -> RevisionStage {
    switch (state.type, state.slug) {
    case ("draft-iesg", "rfcqueue"), ("draft-rfceditor", _):
      .rfcEditorQueue
    case (_, "rfc-edit") where state.isStreamState:
      .rfcEditorQueue
    case ("draft-iesg", "approved"), ("draft-iesg", "ann"), ("draft-stream-iab", "approved"):
      .approved
    case ("draft-iesg", "writeupw"), ("draft-iesg", "goaheadw"), ("draft-iesg", "iesg-eva"),
      ("draft-iesg", "defer"):
      .iesgReview
    case (_, "iesg-rev") where state.isStreamState:
      .iesgReview
    case ("draft-iesg", "lc-req"), ("draft-iesg", "lc"):
      .ietfLastCall
    case ("draft-iesg", "pub-req"), ("draft-iesg", "ad-eval"), ("draft-iesg", "review-e"),
      ("draft-stream-ietf", "sub-pub"),
      ("draft-stream-irtf", "chair-w"), ("draft-stream-irtf", "irsg-w"),
      ("draft-stream-irtf", "irsg_review"), ("draft-stream-irtf", "irsgpoll"),
      ("draft-stream-iab", "review-c"), ("draft-stream-iab", "review-i"),
      ("draft-stream-ise", "find-rev"), ("draft-stream-ise", "ise-rev"),
      ("draft-stream-ise", "need-res"),
      ("draft-stream-editorial", "rsabpoll"):
      .submitted
    case ("draft-stream-ietf", "wg-lc"), ("draft-stream-irtf", "rg-lc"):
      .lastCall
    default:
      .inGroup
    }
  }
}
```

The `where` clauses sit on single-pattern cases on purpose: in a multi-pattern case, `where` guards only the last pattern.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Tools/corpus-build --filter DraftStatesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
make fmt && make check
git add Tools/corpus-build/Sources/RFCCorpusKit/DraftStates.swift Tools/corpus-build/Tests/RFCCorpusKitTests/DraftStatesTests.swift
git commit -m "Decide from datatracker's states which drafts are adopted and how far along"
```

---

### Task 5: Datatracker's API shapes

**Files:**
- Create: `Tools/corpus-build/Sources/RFCCorpusKit/Datatracker.swift`
- Test: `Tools/corpus-build/Tests/RFCCorpusKitTests/DatatrackerTests.swift`

**Interfaces:**
- Consumes: `DraftState` (Task 4).
- Produces: `public enum Datatracker` with `static let draftsFirstPage: URL`, `static let statesFirstPage: URL`, `static func next(_ next: String?) -> URL?`, `static func record(_ name: String) -> URL`, `static func draft(_ name: String, rev: String, extension: String) -> URL`, `static func decoder() -> JSONDecoder`, `static func stateTable(_ pages: [StatePage]) -> [Int: DraftState]`; `Datatracker.DraftPage` (`meta.next: String?`, `objects: [ListedDraft]`); `Datatracker.ListedDraft` (`name`, `rev`, `states: [String]`, `stream: String?`, `stateIDs: [Int]` sorted, `streamSlug: String?`, `func states(in: [Int: DraftState]) -> [DraftState]`, memberwise `init(name:rev:states:stream:)`); `Datatracker.StatePage` (`meta`, `objects: [State]`, `State { id: Int; type: String; slug: String }`); `Datatracker.DraftRecord` (`group: Group?`, `intendedStatus: String?`, `revHistory: [Posted]`, `groupAcronym: String?`, `func published(rev:) -> Date?`).

- [ ] **Step 1: Write the failing tests**

The JSON is hand-written in the API's shape, with made-up names.

```swift
import Foundation
import RFCCorpusKit
import Testing

/// The pieces of datatracker's API the scanner reads, decoded as the API sends them.
@Suite("Datatracker")
struct DatatrackerTests {
  @Test func `a listing page decodes, with state IDs and the stream's slug`() throws {
    let json = """
      {"meta": {"next": "/api/v1/doc/document/?format=json&limit=100&offset=100", "total_count": 150},
       "objects": [{"name": "draft-ietf-example-thing", "rev": "07",
                    "states": ["/api/v1/doc/state/150/", "/api/v1/doc/state/1/", "/api/v1/doc/state/38/"],
                    "stream": "/api/v1/name/streamname/ietf/", "time": "2026-09-01T10:00:00Z"}]}
      """
    let page = try Datatracker.decoder().decode(Datatracker.DraftPage.self, from: Data(json.utf8))
    let draft = try #require(page.objects.first)
    #expect(draft.name == "draft-ietf-example-thing")
    #expect(draft.rev == "07")
    #expect(draft.stateIDs == [1, 38, 150])
    #expect(draft.streamSlug == "ietf")
    #expect(
      Datatracker.next(page.meta.next)?.absoluteString
        == "https://datatracker.ietf.org/api/v1/doc/document/?format=json&limit=100&offset=100")
  }

  @Test func `the last page has no next`() {
    #expect(Datatracker.next(nil) == nil)
  }

  @Test func `the state table keys each state by ID, with its type's slug`() throws {
    let json = """
      {"meta": {"next": null},
       "objects": [{"id": 150, "type": "/api/v1/doc/statetype/draft-iesg/", "slug": "idexists", "name": "I-D Exists"}]}
      """
    let page = try Datatracker.decoder().decode(Datatracker.StatePage.self, from: Data(json.utf8))
    #expect(Datatracker.stateTable([page]) == [150: DraftState("draft-iesg", "idexists")])
  }

  /// Datatracker writes microseconds for recent revisions and none for old ones.
  @Test func `a record decodes publish dates with and without fractional seconds`() throws {
    let json = """
      {"name": "draft-example-thing", "rev": "05",
       "group": {"name": "Individual Submissions", "type": "Individual", "acronym": "none"},
       "intended_std_level": "Informational", "stream": "IETF",
       "rev_history": [{"name": "draft-example-thing", "rev": "04", "published": "2014-04-14T13:39:29+00:00"},
                       {"name": "draft-example-thing", "rev": "05", "published": "2025-12-01T18:27:41.095128+00:00"}]}
      """
    let record = try Datatracker.decoder().decode(Datatracker.DraftRecord.self, from: Data(json.utf8))
    #expect(record.published(rev: "04") == Date(timeIntervalSince1970: 1_397_482_769))
    #expect(record.published(rev: "05") == Date(timeIntervalSince1970: 1_764_613_661))
    #expect(record.intendedStatus == "Informational")
    #expect(record.groupAcronym == nil, "\"none\" is no group")
  }

  @Test func `a record in a working group names it`() throws {
    let json = """
      {"group": {"name": "Example", "type": "WG", "acronym": "example"}, "intended_std_level": null, "rev_history": []}
      """
    let record = try Datatracker.decoder().decode(Datatracker.DraftRecord.self, from: Data(json.utf8))
    #expect(record.groupAcronym == "example")
    #expect(record.intendedStatus == nil)
  }

  @Test func `a draft's header is fetched from the archive`() {
    #expect(
      Datatracker.draft("draft-example-thing", rev: "05", extension: "xml").absoluteString
        == "https://www.ietf.org/archive/id/draft-example-thing-05.xml")
    #expect(
      Datatracker.record("draft-example-thing").absoluteString
        == "https://datatracker.ietf.org/doc/draft-example-thing/doc.json")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Tools/corpus-build --filter DatatrackerTests`
Expected: FAIL to compile, "cannot find 'Datatracker' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// The pieces of datatracker's API the revisions scanner reads, and where. Measured
/// against the live API on 29 September 2026; none needs authentication.
public enum Datatracker {
  static let base = URL(string: "https://datatracker.ietf.org")!

  /// Every active draft in a stream, a hundred at a time. The rest follow `meta.next`.
  public static let draftsFirstPage = URL(
    string: "https://datatracker.ietf.org/api/v1/doc/document/?format=json&limit=100"
      + "&type=draft&states__type=draft&states__slug=active&stream__isnull=false")!

  /// Every document state, about 180 of them: one or two pages.
  public static let statesFirstPage = URL(
    string: "https://datatracker.ietf.org/api/v1/doc/state/?format=json&limit=500")!

  /// The page after this one, from `meta.next`, which is a path and query.
  public static func next(_ next: String?) -> URL? {
    next.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
  }

  /// A draft's record: group, intended status, and when each revision was posted.
  public static func record(_ name: String) -> URL {
    base.appending(path: "doc/\(name)/doc.json")
  }

  /// A revision in the archive: `xml` where the draft was submitted as XML, `txt`
  /// always.
  public static func draft(_ name: String, rev: String, extension: String) -> URL {
    URL(string: "https://www.ietf.org/archive/id/\(name)-\(rev).\(`extension`)")!
  }

  /// Datatracker writes dates as `2025-12-01T18:27:41.095128+00:00`, and without
  /// the fraction for old revisions. The fraction is dropped: a second is precise
  /// enough to date a revision.
  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: string.replacing(/\.\d+/, with: "")) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "not an ISO 8601 date: \(string)")
      }
      return date
    }
    return decoder
  }

  public struct Meta: Decodable, Sendable {
    public var next: String?
  }

  public struct DraftPage: Decodable, Sendable {
    public var meta: Meta
    public var objects: [ListedDraft]
  }

  /// A draft as the listing has it: enough to decide what to read again.
  public struct ListedDraft: Decodable, Sendable, Equatable {
    public var name: String
    public var rev: String
    /// Resource URIs, "/api/v1/doc/state/150/".
    public var states: [String]
    /// "/api/v1/name/streamname/ietf/".
    public var stream: String?

    public init(name: String, rev: String, states: [String], stream: String?) {
      self.name = name
      self.rev = rev
      self.states = states
      self.stream = stream
    }

    /// Sorted, so two listings of the same states compare equal.
    public var stateIDs: [Int] {
      states.compactMap { Int(Datatracker.lastComponent(of: $0)) }.sorted()
    }

    /// "ietf", "irtf", "iab", "ise" or "editorial".
    public var streamSlug: String? {
      stream.map(Datatracker.lastComponent(of:))
    }

    /// The states the table knows. One it does not know is left out, and the stage
    /// falls back as it would for any unknown state.
    public func states(in table: [Int: DraftState]) -> [DraftState] {
      stateIDs.compactMap { table[$0] }
    }
  }

  public struct StatePage: Decodable, Sendable {
    public struct State: Decodable, Sendable {
      public var id: Int
      /// "/api/v1/doc/statetype/draft-iesg/".
      public var type: String
      public var slug: String
    }

    public var meta: Meta
    public var objects: [State]
  }

  public static func stateTable(_ pages: [StatePage]) -> [Int: DraftState] {
    var table: [Int: DraftState] = [:]
    for state in pages.flatMap(\.objects) {
      table[state.id] = DraftState(lastComponent(of: state.type), state.slug)
    }
    return table
  }

  /// `doc/<name>/doc.json`, the parts the scanner keeps.
  public struct DraftRecord: Decodable, Sendable {
    public struct Group: Decodable, Sendable {
      public var acronym: String
    }

    public struct Posted: Decodable, Sendable {
      public var rev: String
      public var published: Date
    }

    public var group: Group?
    public var intendedStatus: String?
    public var revHistory: [Posted]

    enum CodingKeys: String, CodingKey {
      case group
      case intendedStatus = "intended_std_level"
      case revHistory = "rev_history"
    }

    /// Nil for a draft in no group, which datatracker calls "none".
    public var groupAcronym: String? {
      group.flatMap { $0.acronym == "none" ? nil : $0.acronym }
    }

    public func published(rev: String) -> Date? {
      revHistory.last { $0.rev == rev }?.published
    }
  }

  /// "/api/v1/doc/state/150/" → "150".
  static func lastComponent(of uri: String) -> String {
    uri.split(separator: "/").last.map(String.init) ?? uri
  }
}
```

`DraftRecord` also has `init(from:)` synthesized from `CodingKeys`. `ListedDraft` ignores `time` and the listing's other fields, which JSONDecoder allows.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Tools/corpus-build --filter DatatrackerTests`
Expected: PASS. If `1_764_613_661` is off, recompute it with `date -u -j -f "%Y-%m-%dT%H:%M:%S" "2025-12-01T18:27:41" +%s` and fix the test's constant, not the decoder.

- [ ] **Step 5: Commit**

```bash
make fmt && make check
git add Tools/corpus-build/Sources/RFCCorpusKit/Datatracker.swift Tools/corpus-build/Tests/RFCCorpusKitTests/DatatrackerTests.swift
git commit -m "Decode the parts of datatracker's API the revisions scanner reads"
```

---

### Task 6: The scan record, merge and projection

**Files:**
- Create: `Tools/corpus-build/Sources/RFCCorpusKit/RevisionScan.swift`
- Test: `Tools/corpus-build/Tests/RFCCorpusKitTests/RevisionScanTests.swift`

**Interfaces:**
- Consumes: `RFCRevisions`, `RevisionStage`, `DraftHeader` (Tasks 1–2); `DraftState`, `DraftStates` (Task 4); `Datatracker.ListedDraft`, `Datatracker.DraftRecord` (Task 5).
- Produces:
  - `public struct RevisionScan: Codable, Sendable, Equatable { drafts: [String: Entry]; init(drafts:) }`
  - `RevisionScan.Entry { rev: String; stateIDs: [Int]; stage: RevisionStage; stream: String; reading: Reading?; failed: Bool }` with memberwise init.
  - `RevisionScan.Reading { rev; obsoletes: [Int]; updates: [Int]; published: Date; group: String?; intendedStatus: String? }` with `init(rev:header:record:) throws` and `func refreshed(with record:) throws -> Reading`.
  - `RevisionScan.Work` (`.none`, `.record`, `.full`); `static func work(for: Datatracker.ListedDraft, previous: Entry?) -> Work`.
  - `static func next(adopted:states:previous:readings:failures:) -> RevisionScan`.
  - `func revisions(generatedAt: Date) -> RFCRevisions`.
  - `static func mayPublish(_ next: RFCRevisions, replacing previous: RFCRevisions?, allowShrink: Bool) -> Bool`.
  - `static func decode(_: Data) throws -> RevisionScan`, `func encoded() throws -> Data`.
  - `enum ReadingError: Error { case noSuchRevision(String) }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// The scanner's memory: what it reads again, what it keeps, and what it publishes.
/// Everything is built in code; nothing touches the network.
@Suite("Revision scan")
struct RevisionScanTests {
  private static let states: [Int: DraftState] = [
    1: DraftState("draft", "active"),
    38: DraftState("draft-stream-ietf", "wg-doc"),
    41: DraftState("draft-stream-ietf", "wg-lc"),
    17: DraftState("draft-iesg", "rfcqueue"),
  ]

  private static func listed(_ name: String, rev: String = "03", states: [Int] = [1, 38]) -> Datatracker.ListedDraft {
    Datatracker.ListedDraft(
      name: name, rev: rev, states: states.map { "/api/v1/doc/state/\($0)/" },
      stream: "/api/v1/name/streamname/ietf/")
  }

  private static func reading(rev: String = "03", obsoletes: [Int] = [9990], updates: [Int] = []) -> RevisionScan.Reading {
    RevisionScan.Reading(
      rev: rev, obsoletes: obsoletes, updates: updates,
      published: Date(timeIntervalSince1970: 1_780_000_000), group: "example",
      intendedStatus: "Proposed Standard")
  }

  private static func entry(rev: String = "03", stateIDs: [Int] = [1, 38], reading: RevisionScan.Reading? = RevisionScanTests.reading(), failed: Bool = false) -> RevisionScan.Entry {
    RevisionScan.Entry(rev: rev, stateIDs: stateIDs, stage: .inGroup, stream: "ietf", reading: reading, failed: failed)
  }

  // MARK: What to read

  @Test func `a new draft is read in full`() {
    #expect(RevisionScan.work(for: Self.listed("draft-a"), previous: nil) == .full)
  }

  @Test func `a new revision is read in full`() {
    #expect(RevisionScan.work(for: Self.listed("draft-a", rev: "04"), previous: Self.entry()) == .full)
  }

  @Test func `a draft whose last read failed is read in full`() {
    #expect(RevisionScan.work(for: Self.listed("draft-a"), previous: Self.entry(failed: true)) == .full)
  }

  @Test func `a changed state alone reads only the record`() {
    #expect(RevisionScan.work(for: Self.listed("draft-a", states: [1, 41]), previous: Self.entry()) == .record)
  }

  @Test func `an unchanged draft reads nothing`() {
    #expect(RevisionScan.work(for: Self.listed("draft-a", states: [38, 1]), previous: Self.entry()) == .none)
  }

  // MARK: Merge

  @Test func `a draft that left the listing is dropped`() {
    let previous = RevisionScan(drafts: ["draft-gone": Self.entry()])
    let next = RevisionScan.next(adopted: [], states: Self.states, previous: previous, readings: [:], failures: [])
    #expect(next.drafts.isEmpty)
  }

  @Test func `a read draft takes its new reading, revision and stage`() {
    let previous = RevisionScan(drafts: ["draft-a": Self.entry()])
    let next = RevisionScan.next(
      adopted: [Self.listed("draft-a", rev: "04", states: [1, 17])], states: Self.states,
      previous: previous, readings: ["draft-a": Self.reading(rev: "04", obsoletes: [9991])],
      failures: [])
    let entry = next.drafts["draft-a"]
    #expect(entry?.rev == "04")
    #expect(entry?.reading?.obsoletes == [9991])
    #expect(entry?.stage == .rfcEditorQueue)
    #expect(entry?.failed == false)
  }

  @Test func `a failed read keeps the previous entry and is marked for another try`() {
    let previous = RevisionScan(drafts: ["draft-a": Self.entry()])
    let next = RevisionScan.next(
      adopted: [Self.listed("draft-a", rev: "04")], states: Self.states, previous: previous,
      readings: [:], failures: ["draft-a"])
    #expect(next.drafts["draft-a"]?.reading == Self.reading())
    #expect(next.drafts["draft-a"]?.rev == "03")
    #expect(next.drafts["draft-a"]?.failed == true)
  }

  /// The case a filter on datatracker's `time` would lose: nothing about the draft
  /// changes, so nothing would select it again.
  @Test func `a draft that failed on its first read is read again`() {
    let first = RevisionScan.next(
      adopted: [Self.listed("draft-a")], states: Self.states, previous: nil, readings: [:],
      failures: ["draft-a"])
    #expect(first.drafts["draft-a"]?.reading == nil)
    #expect(RevisionScan.work(for: Self.listed("draft-a"), previous: first.drafts["draft-a"]) == .full)
  }

  @Test func `an unchanged draft is kept, with its stage from today's states`() {
    let previous = RevisionScan(drafts: ["draft-a": Self.entry()])
    let next = RevisionScan.next(
      adopted: [Self.listed("draft-a")], states: Self.states, previous: previous, readings: [:],
      failures: [])
    #expect(next.drafts["draft-a"]?.reading == Self.reading())
    #expect(next.drafts["draft-a"]?.stage == .inGroup)
  }

  // MARK: Projection

  @Test func `a draft that revises nothing stays in the record and out of the file`() {
    let scan = RevisionScan(drafts: ["draft-a": Self.entry(reading: Self.reading(obsoletes: []))])
    #expect(scan.revisions(generatedAt: .now).revisions.isEmpty)
  }

  @Test func `a draft that never read successfully is not in the file`() {
    let scan = RevisionScan(drafts: ["draft-a": Self.entry(reading: nil, failed: true)])
    #expect(scan.revisions(generatedAt: .now).revisions.isEmpty)
  }

  @Test func `each relation becomes a revision under its RFC`() {
    let scan = RevisionScan(drafts: ["draft-a": Self.entry(reading: Self.reading(obsoletes: [9990], updates: [9991]))])
    let file = scan.revisions(generatedAt: Date(timeIntervalSince1970: 1_790_000_000))
    #expect(file.revisions[9990]?.map(\.relation) == [.obsoletes])
    #expect(file.revisions[9991]?.map(\.relation) == [.updates])
    #expect(file.revisions[9990]?.first?.draft == "draft-a")
    #expect(file.revisions[9990]?.first?.revision == "03")
    #expect(file.generatedAt == Date(timeIntervalSince1970: 1_790_000_000))
  }

  // MARK: Shrink guard

  private static func file(rfcs count: Int) -> RFCRevisions {
    let revision = RFCRevisions.Revision(
      relation: .obsoletes, draft: "draft-a", revision: "01", published: .now, stream: "ietf",
      group: nil, intendedStatus: nil, stage: .inGroup)
    return RFCRevisions(generatedAt: .now, revisions: Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, [revision]) }))
  }

  @Test func `the guard trips at more than half gone`() {
    #expect(!RevisionScan.mayPublish(Self.file(rfcs: 9), replacing: Self.file(rfcs: 20), allowShrink: false))
    #expect(RevisionScan.mayPublish(Self.file(rfcs: 10), replacing: Self.file(rfcs: 20), allowShrink: false))
  }

  @Test func `the guard does not trip below ten`() {
    #expect(RevisionScan.mayPublish(Self.file(rfcs: 1), replacing: Self.file(rfcs: 9), allowShrink: false))
  }

  @Test func `the guard gives way when told to`() {
    #expect(RevisionScan.mayPublish(Self.file(rfcs: 0), replacing: Self.file(rfcs: 50), allowShrink: true))
  }

  @Test func `a first run has nothing to shrink from`() {
    #expect(RevisionScan.mayPublish(Self.file(rfcs: 0), replacing: nil, allowShrink: false))
  }

  // MARK: Format

  @Test func `a scan record round-trips`() throws {
    let scan = RevisionScan(drafts: ["draft-a": Self.entry(), "draft-b": Self.entry(reading: nil, failed: true)])
    #expect(try RevisionScan.decode(scan.encoded()) == scan)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Tools/corpus-build --filter RevisionScanTests`
Expected: FAIL to compile, "cannot find 'RevisionScan' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import RFCKit

/// `revisions-scan.json`: what the revisions scanner has read, one entry per adopted
/// draft, including drafts that revise nothing, so a daily run reads only what
/// changed. `revisions.json` is a pure function of it. The app never reads it
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "The scan record").
public struct RevisionScan: Codable, Sendable, Equatable {
  public var drafts: [String: Entry]

  public init(drafts: [String: Entry]) {
    self.drafts = drafts
  }

  public struct Entry: Codable, Sendable, Equatable {
    /// The revision the listing had when this entry was written.
    public var rev: String
    public var stateIDs: [Int]
    public var stage: RevisionStage
    public var stream: String
    /// Nil until a read has succeeded.
    public var reading: Reading?
    /// The last read failed; the next run reads the draft again in full.
    public var failed: Bool

    public init(
      rev: String, stateIDs: [Int], stage: RevisionStage, stream: String, reading: Reading?,
      failed: Bool
    ) {
      self.rev = rev
      self.stateIDs = stateIDs
      self.stage = stage
      self.stream = stream
      self.reading = reading
      self.failed = failed
    }
  }

  public enum ReadingError: Error, Equatable {
    /// The record has no posting of the revision that was read.
    case noSuchRevision(String)
  }

  /// What a draft's header and its record said, at `rev`.
  public struct Reading: Codable, Sendable, Equatable {
    public var rev: String
    public var obsoletes: [Int]
    public var updates: [Int]
    public var published: Date
    public var group: String?
    public var intendedStatus: String?

    public init(
      rev: String, obsoletes: [Int], updates: [Int], published: Date, group: String?,
      intendedStatus: String?
    ) {
      self.rev = rev
      self.obsoletes = obsoletes
      self.updates = updates
      self.published = published
      self.group = group
      self.intendedStatus = intendedStatus
    }

    public init(rev: String, header: DraftHeader, record: Datatracker.DraftRecord) throws {
      guard let published = record.published(rev: rev) else {
        throw ReadingError.noSuchRevision(rev)
      }
      self.init(
        rev: rev, obsoletes: header.obsoletes, updates: header.updates, published: published,
        group: record.groupAcronym, intendedStatus: record.intendedStatus)
    }

    /// The same header, with what a newer record says about the group and status.
    public func refreshed(with record: Datatracker.DraftRecord) throws -> Reading {
      try Reading(
        rev: rev, header: DraftHeader(obsoletes: obsoletes, updates: updates), record: record)
    }
  }

  public enum Work: Equatable, Sendable {
    /// Nothing changed.
    case none
    /// The states changed: read `doc.json` again.
    case record
    /// New, a new revision, or the last read failed: read the header and `doc.json`.
    case full
  }

  public static func work(for draft: Datatracker.ListedDraft, previous: Entry?) -> Work {
    guard let previous, previous.reading != nil, !previous.failed, previous.rev == draft.rev
    else { return .full }
    return previous.stateIDs == draft.stateIDs ? .none : .record
  }

  /// The next record, from this run's adopted drafts and what it read. A draft in
  /// `readings` was read; one in `failures` failed; any other was not due and keeps its
  /// entry. A draft no longer listed is left out: it expired, was replaced, or was
  /// published.
  public static func next(
    adopted: [Datatracker.ListedDraft], states: [Int: DraftState], previous: RevisionScan?,
    readings: [String: Reading], failures: Set<String>
  ) -> RevisionScan {
    var drafts: [String: Entry] = [:]
    for draft in adopted {
      let stage = DraftStates.stage(draft.states(in: states))
      let stream = draft.streamSlug ?? "ietf"
      let old = previous?.drafts[draft.name]
      if let reading = readings[draft.name] {
        drafts[draft.name] = Entry(
          rev: draft.rev, stateIDs: draft.stateIDs, stage: stage, stream: stream,
          reading: reading, failed: false)
      } else if failures.contains(draft.name) {
        var kept =
          old
          ?? Entry(
            rev: draft.rev, stateIDs: draft.stateIDs, stage: stage, stream: stream,
            reading: nil, failed: true)
        kept.failed = true
        drafts[draft.name] = kept
      } else if var kept = old {
        kept.stateIDs = draft.stateIDs
        kept.stage = stage
        drafts[draft.name] = kept
      }
    }
    return RevisionScan(drafts: drafts)
  }

  /// `revisions.json`: every relation of every draft read successfully, under its RFC,
  /// in draft-name order so two runs write the same bytes.
  public func revisions(generatedAt: Date) -> RFCRevisions {
    var byRFC: [Int: [RFCRevisions.Revision]] = [:]
    for name in drafts.keys.sorted() {
      guard let entry = drafts[name], let reading = entry.reading else { continue }
      let relations: [(RFCRevisions.Revision.Relation, [Int])] = [
        (.obsoletes, reading.obsoletes), (.updates, reading.updates),
      ]
      for (relation, numbers) in relations {
        for number in Set(numbers).sorted() {
          byRFC[number, default: []].append(
            RFCRevisions.Revision(
              relation: relation, draft: name, revision: reading.rev,
              published: reading.published, stream: entry.stream, group: reading.group,
              intendedStatus: reading.intendedStatus, stage: entry.stage))
        }
      }
    }
    return RFCRevisions(generatedAt: generatedAt, revisions: byRFC)
  }

  /// False when `next` has lost more than half the RFCs of a `previous` that had at
  /// least ten: a real change in the drafts does not do that, a broken query does.
  public static func mayPublish(
    _ next: RFCRevisions, replacing previous: RFCRevisions?, allowShrink: Bool
  ) -> Bool {
    guard let previous, !allowShrink, previous.revisions.count >= 10 else { return true }
    return next.revisions.count * 2 >= previous.revisions.count
  }

  public static func decode(_ data: Data) throws -> RevisionScan {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RevisionScan.self, from: data)
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Tools/corpus-build --filter RevisionScanTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
make fmt && make check
git add Tools/corpus-build/Sources/RFCCorpusKit/RevisionScan.swift Tools/corpus-build/Tests/RFCCorpusKitTests/RevisionScanTests.swift
git commit -m "Keep a scan record so the revisions scanner reads only what changed"
```

---

### Task 7: The `revisions` command

**Files:**
- Create: `Tools/corpus-build/Sources/corpus-build/RevisionsCommand.swift`
- Modify: `Tools/corpus-build/Sources/corpus-build/CorpusBuild.swift` (usage comment, `subcommands`)
- Modify: `Tools/corpus-build/Tests/RFCCorpusKitTests/CommandLineTests.swift` (one test)
- Modify: `Makefile` (a `revisions` target, and `.PHONY`)

**Interfaces:**
- Consumes: everything in Tasks 2 and 4–6; `FetchCommand.download(_:)`, `PipelineError.http`, `Logger(command:)` (existing).
- Produces: `corpus-build revisions [--scan <path>] --out <directory> [--allow-shrink]`, writing `<directory>/revisions.json` and `<directory>/revisions-scan.json`; exit status non-zero when the listing fails or the shrink guard trips.

- [ ] **Step 1: Write the failing command-line test**

Add to `CommandLineTests`:

```swift
  /// `--out` is where both files go; without it there is nowhere to write, and
  /// nothing may be fetched first.
  @Test func `revisions requires out`() throws {
    let result = try Self.run(["revisions"])
    #expect(result.status == 64, "EX_USAGE")
    #expect(result.standardError.contains("--out"), "\(result.standardError)")
  }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Tools/corpus-build --filter "revisions requires out"`
Expected: FAIL. `revisions` is an unknown subcommand, so the error does not mention `--out`.

- [ ] **Step 3: Write the command**

```swift
import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// The revisions scanner (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md):
/// lists every active, adopted draft on datatracker, reads the header of each one that
/// changed, and writes `revisions.json` for the app and `revisions-scan.json` for its
/// own next run. Requests go one at a time, with a pause between them.
struct RevisionsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "revisions",
    abstract: "Find the adopted Internet-Drafts that intend to obsolete or update an RFC."
  )

  private static let logger = Logger(command: "revisions")
  private static let pause = Duration.milliseconds(250)

  @Option(help: "The previous run's revisions-scan.json. Without it, every adopted draft is read.")
  var scan: String?

  @Option(help: "The directory to write revisions.json and revisions-scan.json into.")
  var out: String

  @Flag(help: "Publish even when more than half the RFCs are gone since the previous run.")
  var allowShrink = false

  func run() async throws {
    let startedAt = Date.now
    let previous = try scan.map { try RevisionScan.decode(Data(contentsOf: URL(fileURLWithPath: $0))) }

    let states = Datatracker.stateTable(
      try await Self.pages(from: Datatracker.statesFirstPage, as: Datatracker.StatePage.self) {
        $0.meta.next
      })
    let listed = try await Self.pages(from: Datatracker.draftsFirstPage, as: Datatracker.DraftPage.self) {
      $0.meta.next
    }.flatMap(\.objects)
    let adopted = listed.filter { DraftStates.isAdopted($0.states(in: states)) }
    Self.logger.info("listed", metadata: ["active": "\(listed.count)", "adopted": "\(adopted.count)"])

    var readings: [String: RevisionScan.Reading] = [:]
    var failures: Set<String> = []
    for draft in adopted {
      let old = previous?.drafts[draft.name]
      let work = RevisionScan.work(for: draft, previous: old)
      guard work != .none else { continue }
      do {
        let record = try Datatracker.decoder().decode(
          Datatracker.DraftRecord.self, from: try await Self.fetch(Datatracker.record(draft.name)))
        if work == .record, let reading = old?.reading {
          readings[draft.name] = try reading.refreshed(with: record)
        } else {
          let header = try await Self.header(draft)
          if !header.unreadable.isEmpty {
            Self.logger.warning(
              "unreadable relation",
              metadata: ["draft": "\(draft.name)", "value": "\(header.unreadable)"])
          }
          readings[draft.name] = try RevisionScan.Reading(rev: draft.rev, header: header, record: record)
        }
      } catch {
        failures.insert(draft.name)
        Self.logger.error("read failed", error: error, metadata: ["draft": "\(draft.name)"])
      }
    }
    Self.logger.info("read", metadata: ["read": "\(readings.count)", "failures": "\(failures.count)"])

    let next = RevisionScan.next(
      adopted: adopted, states: states, previous: previous, readings: readings, failures: failures)
    let revisions = next.revisions(generatedAt: startedAt)
    let before = previous?.revisions(generatedAt: startedAt)
    guard RevisionScan.mayPublish(revisions, replacing: before, allowShrink: allowShrink) else {
      Self.logger.error(
        "refusing to publish: more than half the RFCs are gone",
        metadata: ["before": "\(before?.revisions.count ?? 0)", "after": "\(revisions.revisions.count)"])
      throw ExitCode.failure
    }

    let directory = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try revisions.encoded().write(to: directory.appending(path: "revisions.json"), options: .atomic)
    try next.encoded().write(to: directory.appending(path: "revisions-scan.json"), options: .atomic)
    Self.logger.info("done", metadata: ["rfcs": "\(revisions.revisions.count)", "drafts": "\(next.drafts.count)"])
  }

  /// The XML where the draft was submitted as XML, the text otherwise.
  private static func header(_ draft: Datatracker.ListedDraft) async throws -> DraftHeader {
    do {
      return try DraftHeader.parse(
        xml: try await fetch(Datatracker.draft(draft.name, rev: draft.rev, extension: "xml")))
    } catch PipelineError.http(404, _) {
      return DraftHeader.parse(
        text: try await fetch(Datatracker.draft(draft.name, rev: draft.rev, extension: "txt")))
    }
  }

  /// Every page, following `next` until there is none. A failure on any page fails the
  /// run: a partial listing would drop every draft on the missing pages.
  private static func pages<Page: Decodable>(
    from first: URL, as type: Page.Type, next: (Page) -> String?
  ) async throws -> [Page] {
    var pages: [Page] = []
    var url: URL? = first
    while let current = url {
      let page = try Datatracker.decoder().decode(Page.self, from: try await fetch(current))
      pages.append(page)
      url = Datatracker.next(next(page))
    }
    return pages
  }

  private static func fetch(_ url: URL) async throws -> Data {
    try await Task.sleep(for: pause)
    return try await FetchCommand.download(url)
  }
}
```

`FetchCommand.download` already sends the project's User-Agent and throws `PipelineError.http(status, url)` on a non-2xx answer.

- [ ] **Step 4: Register it**

In `CorpusBuild.swift`, add `RevisionsCommand.self` to `subcommands` after `QueriesCommand.self`. Add to the usage comment after the `queries` lines:

```swift
//   corpus-build revisions --out corpus/revisions [--scan corpus/revisions/revisions-scan.json] [--allow-shrink]
```

In the `Makefile`, add `revisions` to `.PHONY` and, after the `corpus-queries` target:

```make
## Scan datatracker for adopted drafts revising an RFC, into corpus/revisions
revisions: corpus-tool
	$(CORPUS_BIN) revisions --out corpus/revisions $(if $(wildcard corpus/revisions/revisions-scan.json),--scan corpus/revisions/revisions-scan.json)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Tools/corpus-build --filter "Command line"`
Expected: PASS, including `revisions requires out`.

- [ ] **Step 6: Run it for real, once**

Run: `make revisions` (about 970 headers with a 250 ms pause each: ten to fifteen minutes).
Expected: `corpus/revisions/revisions.json` exists; `jq '.revisions["6265"]' corpus/revisions/revisions.json` lists `draft-ietf-httpbis-rfc6265bis` with `"stage" : "rfcEditorQueue"`; the log's `failures` is a handful at most. Then run `make revisions` again at once: its `read` count should be close to 0. `corpus/` is gitignored; nothing here is committed.

- [ ] **Step 7: Commit**

```bash
make fmt && make check
git add Tools/corpus-build/Sources/corpus-build/RevisionsCommand.swift Tools/corpus-build/Sources/corpus-build/CorpusBuild.swift Tools/corpus-build/Tests/RFCCorpusKitTests/CommandLineTests.swift Makefile
git commit -m "Add corpus-build revisions, which scans datatracker for drafts revising an RFC"
```

---

### Task 8: The workflow and the decision record

**Files:**
- Create: `.github/workflows/revisions.yml`
- Modify: `docs/DATA_PIPELINE.md` ("Automation" section)
- Modify: `docs/ARCHITECTURE.md` (a dated decision, beside the existing ones)

**Interfaces:**
- Consumes: `make corpus-tool`, `corpus-build revisions` (Task 7).
- Produces: the `revisions` prerelease with `revisions.json` and `revisions-scan.json`.

- [ ] **Step 1: Write the workflow**

Copy the container digest and the pinned `actions/checkout` SHA from `.github/workflows/corpus.yml` exactly. Pick a schedule minute that is neither 0 nor 30.

```yaml
name: Revisions

# Scans datatracker daily for adopted drafts that intend to obsolete or update an RFC,
# and publishes revisions.json on the `revisions` release, where the app fetches it
# (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md). The scan record beside
# it lets the next run read only what changed.
on:
  schedule:
    - cron: "17 5 * * *"
  workflow_dispatch:
    inputs:
      allow-shrink:
        description: Publish even when more than half the RFCs are gone since the last run
        type: boolean
        default: false

jobs:
  scan:
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    container: swift:6.3@sha256:8de8ea332a61e961ead4ef41029c2552b18e1a70dd5942d25ecf7d8de2eec5b5
    # write only for uploading to the `revisions` release.
    permissions:
      contents: write
    env:
      GH_TOKEN: ${{ github.token }}
      GH_REPO: ${{ github.repository }}
      ALLOW_SHRINK: ${{ inputs.allow-shrink && '--allow-shrink' || '' }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # make for the Makefile, gh for the release. The image carries neither.
      - name: Install tools
        run: apt-get update -qq && apt-get install -y -qq make gh >/dev/null

      - name: Build corpus-build
        run: make corpus-tool

      # Nothing to download on the first run: the release does not exist yet.
      - name: Download the previous scan
        run: |
          mkdir -p out
          if gh release view revisions >/dev/null 2>&1; then
            gh release download revisions --pattern revisions-scan.json --dir previous
            echo "SCAN=--scan previous/revisions-scan.json" >> "$GITHUB_ENV"
          fi

      - name: Scan
        run: Tools/corpus-build/.build/release/corpus-build revisions --out out $SCAN $ALLOW_SHRINK

      # A prerelease, so it never becomes the repository's "Latest release".
      # --clobber deletes before it uploads: the app treats the moment between as a
      # failed fetch and keeps its copy.
      - name: Publish
        run: |
          if ! gh release view revisions >/dev/null 2>&1; then
            gh release create revisions --prerelease --title "Revisions" \
              --notes "Adopted drafts revising an RFC, refreshed daily by the revisions workflow."
          fi
          gh release upload revisions out/revisions.json out/revisions-scan.json --clobber
```

- [ ] **Step 2: Lint it**

Run: `actionlint .github/workflows/revisions.yml` if `actionlint` is installed (`brew install actionlint` otherwise). Expected: no findings. Also check that `git diff main -- .github/workflows/corpus.yml` is empty: the two workflows are independent.

- [ ] **Step 3: Record it in the docs**

In `docs/DATA_PIPELINE.md`, under "## Automation", add a paragraph:

```markdown
`revisions.yml` runs daily and on demand. It builds corpus-build and runs `corpus-build
revisions`, which lists every active, adopted Internet-Draft on datatracker and reads
the header of each one that changed. It uploads `revisions.json` (adopted drafts that
intend to obsolete or update an RFC, which the app fetches) and `revisions-scan.json`
(the scanner's record for its next run) to the `revisions` prerelease. A run that loses
more than half the RFCs of the previous one fails instead of publishing; the
`allow-shrink` input overrides that. See
`docs/superpowers/specs/2026-09-29-rfc-revisions-design.md`.
```

In `docs/ARCHITECTURE.md`, add a decision, in the style and position of the existing dated ones:

```markdown
### Decision: datatracker data reaches the app as a published file (29 September 2026)

Which drafts are revising an RFC cannot be asked of datatracker one document at a time:
it records the relation only once a draft is published, so the answer means reading the
header of every adopted draft. One scheduled GitHub Action does that for every user and
publishes one small JSON file on a release; the app fetches it, caches it beside the
index, and works offline from the cached copy. A snapshot shipped in a pack would be as
stale as the pack, and drafts change weekly. Later datatracker features that need
refreshed data reuse this path.
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/revisions.yml docs/DATA_PIPELINE.md docs/ARCHITECTURE.md
git commit -m "Publish the revisions file daily from a scheduled workflow"
```

The first `workflow_dispatch` run and its review happen after merge (Task 12). A scheduled workflow only runs from the default branch.

---

### Task 9: `RevisionsSummary` in RFCReaderKit

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/RevisionsSummary.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/RevisionsSummaryTests.swift`

**Interfaces:**
- Consumes: `RFCRevisions`, `RevisionStage` (Task 1); `RFCEditorEndpoints.datatrackerBase` (existing).
- Produces: `public struct RevisionsSummary: Equatable, Sendable` with `init(_ file: RFCRevisions?, rfc: Int, now: Date, locale: Locale = .current, timeZone: TimeZone = .current)`, `revisions: [RFCRevisions.Revision]` (ordered), `isStale: Bool`, `isEmpty: Bool`, `bannerLines: [Line]`, `moreText: String?`, `inspectorLines(_ relation: RFCRevisions.Revision.Relation) -> [Line]`, `static func stageName(_: RevisionStage, stream: String) -> String`, `static func relationLabel(_: RFCRevisions.Revision.Relation) -> String`; `RevisionsSummary.Line: Equatable, Sendable, Identifiable` with `relation: String`, `title: String`, `url: URL`, `detail: String`, `accessibilityLabel: String`, `id: String`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the banner and the inspector say about drafts revising an RFC. Dates in
/// en_GB and UTC, so "25 September" reads the same on any machine.
@Suite("Revisions summary")
struct RevisionsSummaryTests {
  private static let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21T14:13:20Z
  private static let day: TimeInterval = 86_400
  private static let locale = Locale(identifier: "en_GB")
  private static let utc = TimeZone(identifier: "UTC")!

  private static func revision(
    _ draft: String, _ relation: RFCRevisions.Revision.Relation = .obsoletes,
    stage: RevisionStage = .inGroup, stream: String = "ietf", revision: String = "22",
    published: Date = now - 30 * day
  ) -> RFCRevisions.Revision {
    RFCRevisions.Revision(
      relation: relation, draft: draft, revision: revision, published: published, stream: stream,
      group: "example", intendedStatus: "Proposed Standard", stage: stage)
  }

  private static func summary(
    _ revisions: [RFCRevisions.Revision], generated: Date = now - day
  ) -> RevisionsSummary {
    RevisionsSummary(
      RFCRevisions(generatedAt: generated, revisions: [9990: revisions]), rfc: 9990, now: now,
      locale: locale, timeZone: utc)
  }

  @Test func `drafts are ordered by stage, then obsoletes before updates, then name`() {
    let summary = Self.summary([
      Self.revision("draft-c", .updates, stage: .rfcEditorQueue),
      Self.revision("draft-b", .obsoletes, stage: .inGroup),
      Self.revision("draft-a", .updates, stage: .inGroup),
      Self.revision("draft-d", .obsoletes, stage: .rfcEditorQueue),
    ])
    #expect(summary.revisions.map(\.draft) == ["draft-d", "draft-c", "draft-b", "draft-a"])
  }

  @Test func `a banner line names the relation, the draft and its stage`() throws {
    let line = try #require(
      Self.summary([Self.revision("draft-ietf-example-rfc9990bis", stage: .rfcEditorQueue)])
        .bannerLines.first)
    #expect(line.relation == "Being replaced by")
    #expect(line.title == "draft-ietf-example-rfc9990bis-22")
    #expect(line.detail == "In the RFC Editor queue")
    #expect(line.url.absoluteString == "https://datatracker.ietf.org/doc/draft-ietf-example-rfc9990bis/")
    #expect(line.accessibilityLabel == "Being replaced by draft-ietf-example-rfc9990bis, revision 22, in the RFC Editor queue")
  }

  @Test func `an update is being updated by`() {
    #expect(Self.summary([Self.revision("draft-a", .updates)]).bannerLines.first?.relation == "Being updated by")
  }

  @Test func `a file three days old is current, and one older is stale`() {
    #expect(!Self.summary([Self.revision("draft-a")], generated: Self.now - 3 * Self.day).isStale)
    let stale = Self.summary([Self.revision("draft-a", stage: .rfcEditorQueue)], generated: Self.now - 4 * Self.day)
    #expect(stale.isStale)
    #expect(stale.bannerLines.first?.detail == "In the RFC Editor queue, as of 17 September")
    #expect(stale.bannerLines.first?.accessibilityLabel.hasSuffix(", as of 17 September") == true)
  }

  /// An active draft can sit in one state for years.
  @Test func `a revision over a year old carries its date`() {
    let old = Self.revision(
      "draft-a", stage: .iesgReview, revision: "05",
      published: Date(timeIntervalSince1970: 1_397_482_769))  // May 2014
    let line = Self.summary([old]).bannerLines.first
    #expect(line?.detail == "Under IESG review, revision of May 2014")
    #expect(line?.accessibilityLabel == "Being replaced by draft-a, revision 5 from May 2014, under IESG review")
  }

  @Test func `a stale file and a dormant draft say both`() {
    let old = Self.revision("draft-a", stage: .iesgReview, published: Date(timeIntervalSince1970: 1_397_482_769))
    #expect(
      Self.summary([old], generated: Self.now - 5 * Self.day).bannerLines.first?.detail
        == "Under IESG review, revision of May 2014, as of 16 September")
  }

  @Test func `the banner shows two drafts and counts the rest`() {
    let summary = Self.summary(["draft-a", "draft-b", "draft-c", "draft-d"].map { Self.revision($0) })
    #expect(summary.bannerLines.count == 2)
    #expect(summary.moreText == "and 2 more")
    #expect(Self.summary(["draft-a", "draft-b"].map { Self.revision($0) }).moreText == nil)
  }

  @Test func `an RFC nothing revises has no lines`() {
    let summary = RevisionsSummary(
      RFCRevisions(generatedAt: Self.now, revisions: [9991: [Self.revision("draft-a")]]), rfc: 9990,
      now: Self.now)
    #expect(summary.isEmpty)
    #expect(summary.bannerLines.isEmpty)
    #expect(summary.moreText == nil)
  }

  @Test func `no file has no lines`() {
    #expect(RevisionsSummary(nil, rfc: 9990, now: Self.now).isEmpty)
  }

  @Test func `an inspector line lists everything`() {
    let line = Self.summary([
      Self.revision("draft-a", stage: .rfcEditorQueue, published: Date(timeIntervalSince1970: 1_764_613_661))
    ]).inspectorLines(.obsoletes).first
    #expect(line?.title == "draft-a-22")
    #expect(line?.detail == "1 December 2025 · EXAMPLE · intended Proposed Standard · In the RFC Editor queue")
  }

  @Test func `an inspector list holds only its relation`() {
    let summary = Self.summary([Self.revision("draft-a", .obsoletes), Self.revision("draft-b", .updates)])
    #expect(summary.inspectorLines(.updates).map(\.title) == ["draft-b-22"])
  }

  @Test(arguments: [
    (RevisionStage.rfcEditorQueue, "In the RFC Editor queue"),
    (.approved, "Approved for publication"),
    (.iesgReview, "Under IESG review"),
    (.ietfLastCall, "In IETF Last Call"),
    (.submitted, "Submitted for publication"),
    (.lastCall, "In working group last call"),
    (.inGroup, "In the working group"),
  ])
  func `each stage has its words`(stage: RevisionStage, words: String) {
    #expect(RevisionsSummary.stageName(stage, stream: "ietf") == words)
  }

  @Test func `an Independent draft in no group is under review`() {
    #expect(RevisionsSummary.stageName(.inGroup, stream: "ise") == "Under review")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter RevisionsSummaryTests`
Expected: FAIL to compile, "cannot find 'RevisionsSummary' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import RFCKit

/// What the reader says about drafts revising one RFC: the banner's rows and the
/// inspector's, in the order and words of
/// docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "The interface".
public struct RevisionsSummary: Equatable, Sendable {
  /// Furthest stage first, then obsoletes before updates, then by name.
  public let revisions: [RFCRevisions.Revision]
  /// The file is more than three days old, so every stage says "as of".
  public let isStale: Bool
  private let generatedAt: Date?
  private let now: Date
  private let locale: Locale
  private let timeZone: TimeZone

  public struct Line: Equatable, Sendable, Identifiable {
    /// "Being replaced by".
    public let relation: String
    /// "draft-ietf-httpbis-rfc6265bis-22".
    public let title: String
    /// The draft's datatracker page.
    public let url: URL
    public let detail: String
    /// One sentence, "Being replaced by draft-…, revision 22, in the RFC Editor queue".
    public let accessibilityLabel: String
    public var id: String { relation + title }
  }

  private static let staleAfter: TimeInterval = 3 * 86_400
  private static let dormantAfter: TimeInterval = 365 * 86_400
  private static let bannerLimit = 2

  public init(
    _ file: RFCRevisions?, rfc number: Int, now: Date, locale: Locale = .current,
    timeZone: TimeZone = .current
  ) {
    revisions = (file?.revisions[number] ?? []).sorted { lhs, rhs in
      if lhs.stage != rhs.stage { return lhs.stage > rhs.stage }
      if lhs.relation != rhs.relation { return lhs.relation == .obsoletes }
      return lhs.draft < rhs.draft
    }
    generatedAt = file?.generatedAt
    isStale = file.map { now.timeIntervalSince($0.generatedAt) > Self.staleAfter } ?? false
    self.now = now
    self.locale = locale
    self.timeZone = timeZone
  }

  public var isEmpty: Bool { revisions.isEmpty }

  public var bannerLines: [Line] {
    revisions.prefix(Self.bannerLimit).map(bannerLine)
  }

  /// "and 2 more", past the banner's two rows; the inspector lists them all.
  public var moreText: String? {
    revisions.count > Self.bannerLimit ? "and \(revisions.count - Self.bannerLimit) more" : nil
  }

  /// Every draft of one relation, in full, for the inspector.
  public func inspectorLines(_ relation: RFCRevisions.Revision.Relation) -> [Line] {
    revisions.filter { $0.relation == relation }.map { revision in
      var parts = [format(revision.published, .dateTime.day().month(.wide).year())]
      if let group = revision.group { parts.append(group.uppercased()) }
      if let status = revision.intendedStatus { parts.append("intended \(status)") }
      parts.append(stageWithAsOf(revision))
      return line(revision, detail: parts.joined(separator: " · "))
    }
  }

  public static func relationLabel(_ relation: RFCRevisions.Revision.Relation) -> String {
    switch relation {
    case .obsoletes: "Being replaced by"
    case .updates: "Being updated by"
    }
  }

  public static func stageName(_ stage: RevisionStage, stream: String) -> String {
    switch stage {
    case .rfcEditorQueue: "In the RFC Editor queue"
    case .approved: "Approved for publication"
    case .iesgReview: "Under IESG review"
    case .ietfLastCall: "In IETF Last Call"
    case .submitted: "Submitted for publication"
    case .lastCall: "In working group last call"
    // The Independent stream has no group to be in.
    case .inGroup: stream == "ise" ? "Under review" : "In the working group"
    }
  }

  private func bannerLine(_ revision: RFCRevisions.Revision) -> Line {
    var detail = Self.stageName(revision.stage, stream: revision.stream)
    if let month = dormantMonth(revision) { detail += ", revision of \(month)" }
    if let asOf { detail += ", as of \(asOf)" }
    return line(revision, detail: detail)
  }

  private func line(_ revision: RFCRevisions.Revision, detail: String) -> Line {
    let relation = Self.relationLabel(revision.relation)
    let number = Int(revision.revision).map(String.init) ?? revision.revision
    var sentence = "\(relation) \(revision.draft), revision \(number)"
    if let month = dormantMonth(revision) { sentence += " from \(month)" }
    sentence += ", " + Self.lowercasingFirst(Self.stageName(revision.stage, stream: revision.stream))
    if let asOf { sentence += ", as of \(asOf)" }
    return Line(
      relation: relation, title: "\(revision.draft)-\(revision.revision)",
      url: RFCEditorEndpoints.datatrackerBase.appending(path: "doc/\(revision.draft)/"),
      detail: detail, accessibilityLabel: sentence)
  }

  private func stageWithAsOf(_ revision: RFCRevisions.Revision) -> String {
    let stage = Self.stageName(revision.stage, stream: revision.stream)
    return asOf.map { "\(stage), as of \($0)" } ?? stage
  }

  /// "17 September", when the file is stale.
  private var asOf: String? {
    guard isStale, let generatedAt else { return nil }
    return format(generatedAt, .dateTime.day().month(.wide))
  }

  /// "May 2014", when the revision is more than a year old.
  private func dormantMonth(_ revision: RFCRevisions.Revision) -> String? {
    guard now.timeIntervalSince(revision.published) > Self.dormantAfter else { return nil }
    return format(revision.published, .dateTime.month(.wide).year())
  }

  private func format(_ date: Date, _ style: Date.FormatStyle) -> String {
    var style = style
    style.locale = locale
    style.timeZone = timeZone
    return date.formatted(style)
  }

  /// "In the RFC Editor queue" → "in the RFC Editor queue", for the middle of a sentence.
  private static func lowercasingFirst(_ string: String) -> String {
    string.prefix(1).lowercased() + string.dropFirst()
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter RevisionsSummaryTests`
Expected: PASS. If a date string is off by a day, the test's constant is wrong, not the code: recompute it with `date -u -r <seconds>` and fix the expectation. `1_790_000_000` is 21 September 2026, so four days earlier is the 17th and five is the 16th.

- [ ] **Step 5: Commit**

```bash
make fmt && make test-app
git add Packages/RFCReaderKit/Sources/RFCReaderKit/RevisionsSummary.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/RevisionsSummaryTests.swift
git commit -m "Say which drafts are revising an RFC, how far along, and as of when"
```

---

### Task 10: The inspector's rows in `DocumentInfo`

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentInfo.swift` (`Value`, `init`, `relationships`)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/DocumentInfoTests.swift`

**Interfaces:**
- Consumes: `RevisionsSummary`, `RevisionsSummary.Line` (Task 9).
- Produces: `DocumentInfo.Value.drafts([RevisionsSummary.Line])`; `DocumentInfo.init(_:authors:in:revisions:)` with `revisions: RevisionsSummary? = nil`.

- [ ] **Step 1: Write the failing tests**

Add to `DocumentInfoTests`:

```swift
  private func revisions(for metadata: RFCMetadata) -> RevisionsSummary {
    let revision = { (draft: String, relation: RFCRevisions.Revision.Relation) in
      RFCRevisions.Revision(
        relation: relation, draft: draft, revision: "03", published: .now, stream: "ietf",
        group: "httpbis", intendedStatus: "Proposed Standard", stage: .inGroup)
    }
    let file = RFCRevisions(
      generatedAt: .now,
      revisions: [
        metadata.id.number: [revision("draft-ietf-example-bis", .obsoletes), revision("draft-ietf-example-ext", .updates)]
      ])
    return RevisionsSummary(file, rfc: metadata.id.number, now: .now)
  }

  @Test func `drafts revising the document follow Updated by`() {
    let info = DocumentInfo(rich, in: index, revisions: revisions(for: rich))
    let labels = info.sections.first { $0.title == "Relationships" }?.rows.map(\.label)
    #expect(labels == ["Obsoletes", "Updated by", "Being replaced by", "Being updated by", "Part of STD 97"])
  }

  @Test func `a draft row lists the draft in full`() {
    let info = DocumentInfo(rich, in: index, revisions: revisions(for: rich))
    let row = info.sections.first { $0.title == "Relationships" }?.rows.first { $0.label == "Being replaced by" }
    guard case .drafts(let lines) = row?.value else {
      Issue.record("expected drafts, got \(String(describing: row?.value))")
      return
    }
    #expect(lines.map(\.title) == ["draft-ietf-example-bis-03"])
  }

  /// BCP 14 is not RFC 14: the app asks only for an RFC's number, and a summary
  /// with nothing in it adds no row.
  @Test func `no drafts add no rows`() {
    let empty = RevisionsSummary(nil, rfc: 1149, now: .now)
    #expect(section("Relationships", of: bare) == nil)
    #expect(DocumentInfo(bare, in: index, revisions: empty).sections.first { $0.title == "Relationships" } == nil)
  }
```

Check `DocumentInfoTests` for how `rich`'s Relationships labels read today, and make the first test's expected list the existing labels with the two new ones inserted after "Updated by".

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter DocumentInfoTests`
Expected: FAIL to compile, "extra argument 'revisions' in call".

- [ ] **Step 3: Implement**

In `DocumentInfo.Value`, after `case documents([DocumentID])`:

```swift
    /// Internet-Drafts, each opening its datatracker page in the browser.
    case drafts([RevisionsSummary.Line])
```

Change the initializer's signature and its Relationships line:

```swift
  /// - Parameter revisions: the drafts revising this document, from `revisions.json`;
  ///   nil or empty adds no rows.
  public init(
    _ metadata: RFCMetadata, authors: [Author]? = nil, in index: RFCIndex?,
    revisions: RevisionsSummary? = nil
  ) {
```

```swift
      Self.section(
        "Relationships", .list, Self.relationships(metadata, index: index, revisions: revisions)),
```

In `relationships`, change the signature to `(_ metadata: RFCMetadata, index: RFCIndex?, revisions: RevisionsSummary?)` and insert this after the loop over the four published relations, before the loop over `metadata.isAlso`:

```swift
    for relation in [RFCRevisions.Revision.Relation.obsoletes, .updates] {
      let lines = revisions?.inspectorLines(relation) ?? []
      if !lines.isEmpty {
        rows.append(Row(label: RevisionsSummary.relationLabel(relation), value: .drafts(lines)))
      }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter DocumentInfoTests`
Expected: PASS, the existing tests included.

- [ ] **Step 5: Commit**

```bash
make fmt && make test-app
git add Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentInfo.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/DocumentInfoTests.swift
git commit -m "List the drafts revising a document in the inspector's Relationships"
```

---

### Task 11: The app: cache, refresh, banner, inspector

**Files:**
- Modify: `App/RFCReader/Model/DocumentStore.swift` (after "// MARK: - Index")
- Modify: `App/RFCReader/Model/LibraryModel.swift` (properties, `init`, `bootstrap`, a new "Revisions" section)
- Modify: `App/RFCReader/Views/DocumentView.swift:228` (`onChange`), `:499-503` (`deriveInfo`), `:778-826` (`StatusBanner`)
- Modify: `App/RFCReader/Views/Rendering/InfoView.swift:170-215` (`SectionRows.rowView`)

**Interfaces:**
- Consumes: `RevisionsClient` (Task 3), `RevisionsSummary` (Task 9), `DocumentInfo.Value.drafts`, `DocumentInfo.init(…, revisions:)` (Task 10).
- Produces: `LibraryModel.revisions: RFCRevisions?`, `LibraryModel.revisionsSummary(for: DocumentID) -> RevisionsSummary?`, `LibraryModel.refreshRevisions(ifOlderThan: TimeInterval) async`.

The App target has no test bundle. This task is wiring only: every decision it shows was pinned in Tasks 9–10. Verify by building and by hand.

- [ ] **Step 1: Cache the file in `DocumentStore`**

After `storeIndex(_:)`:

```swift
  // MARK: - Revisions

  private var revisionsURL: URL { directory.appending(path: "revisions.json") }

  /// The last good `revisions.json` and when it was fetched. Nil when there is none,
  /// or it no longer decodes (a newer version, after a downgrade).
  func cachedRevisions() -> (revisions: RFCRevisions, fetchedAt: Date)? {
    guard let data = try? Data(contentsOf: revisionsURL),
      let revisions = try? RFCRevisions.decode(data)
    else { return nil }
    let fetchedAt =
      (try? revisionsURL.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate) ?? .distantPast
    return (revisions, fetchedAt)
  }

  func storeRevisions(_ data: Data) throws {
    try data.write(to: revisionsURL, options: .atomic)
  }
```

`DocumentCacheIndex` scans this directory for documents; `rfc-index.xml` already sits in it, so a file not named for a document is ignored. Confirm in `DocumentCacheIndex.scan` before moving on.

- [ ] **Step 2: Hold, load and refresh it in `LibraryModel`**

Beside `recent`:

```swift
  /// `revisions.json`: adopted drafts that intend to obsolete or update an RFC. Nil
  /// until the cached copy or a fetch has arrived.
  private(set) var revisions: RFCRevisions?
  @ObservationIgnored private var revisionsFetchedAt = Date.distantPast
  @ObservationIgnored private var isRefreshingRevisions = false
  @ObservationIgnored private var activations: (any NSObjectProtocol)?
  private let revisionsClient = RevisionsClient()
```

At the end of `private init()`:

```swift
    // On activation, not `scenePhase`: on macOS the reader's roots are hosted, outside
    // SwiftUI's scene environment.
    #if os(macOS)
      let didBecomeActive = NSApplication.didBecomeActiveNotification
    #else
      let didBecomeActive = UIApplication.didBecomeActiveNotification
    #endif
    activations = NotificationCenter.default.addObserver(
      forName: didBecomeActive, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        Task(name: "Refresh revisions") { await self.refreshRevisions(ifOlderThan: 86_400) }
      }
    }
```

and add `import UIKit` under `#else` of the existing `#if os(macOS) import AppKit` at the top of the file.

In `bootstrap()`, next to the "Fetch recent RFCs" task:

```swift
    Task(name: "Refresh revisions") { await refreshRevisions(ifOlderThan: 0) }
```

A new section, after `apply(_:updatedAt:)`:

```swift
  // MARK: - Revisions

  /// Loads the cached file first, so the banner is right offline. Then fetches when
  /// the last successful fetch is older than `interval`: every launch passes 0, an
  /// activation a day. A failure keeps the cached copy and is logged, not shown (#125).
  func refreshRevisions(ifOlderThan interval: TimeInterval) async {
    guard !isRefreshingRevisions else { return }
    isRefreshingRevisions = true
    defer { isRefreshingRevisions = false }
    if revisions == nil, let cached = await store.cachedRevisions() {
      revisions = cached.revisions
      revisionsFetchedAt = cached.fetchedAt
    }
    guard Date.now.timeIntervalSince(revisionsFetchedAt) >= interval else { return }
    do {
      let fetched = try await revisionsClient.fetch()
      try await store.storeRevisions(fetched.data)
      revisionsFetchedAt = .now
      if fetched.revisions != revisions { revisions = fetched.revisions }
    } catch {
      libraryLog.error(
        "fetching revisions failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The drafts revising `id`, for an RFC. Other series have no revisions: BCP 14 is
  /// not RFC 14.
  func revisionsSummary(for id: DocumentID) -> RevisionsSummary? {
    guard id.series == .rfc else { return nil }
    return RevisionsSummary(revisions, rfc: id.number, now: .now)
  }
```

- [ ] **Step 3: Pass the summary to the inspector**

In `DocumentView.deriveInfo()`:

```swift
    reader.info = metadata.map {
      DocumentInfo(
        $0, authors: document?.header.authors, in: library.index,
        revisions: library.revisionsSummary(for: $0.id))
    }
```

After `.onChange(of: library.indexState) { deriveInfo() }` (line 228):

```swift
      .onChange(of: library.revisions) { deriveInfo() }
```

- [ ] **Step 4: Draw `.drafts` in the inspector**

In `InfoView.swift`, `SectionRows.rowView(_:)`, add a case after `.documents`:

```swift
    case .drafts(let lines):
      VStack(alignment: .leading, spacing: 4) {
        caption(row.label)
        ForEach(lines) { line in
          // A draft opens its datatracker page, as the errata link does: drafts are
          // not read in the app (VISION.md, Tier 2).
          Link(destination: line.url) {
            VStack(alignment: .leading, spacing: 1) {
              Text(line.title).foregroundStyle(.tint)
              Text(line.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(line.accessibilityLabel)
          .accessibilityAddTraits(.isLink)
        }
      }
```

Build (`make build-app`) and add `.drafts` to any other exhaustive `switch` over `DocumentInfo.Value` the compiler names, as an empty case where that switch draws card rows.

- [ ] **Step 5: Add the banner rows**

In `StatusBanner`, compute the summary once per body, extend the condition, and add the rows after the errata link:

```swift
  var body: some View {
    let revisions = library.revisionsSummary(for: metadata.id)
    let hasRevisions = revisions.map { !$0.isEmpty } ?? false
    if metadata.isObsolete || !metadata.updatedBy.isEmpty || metadata.hasErrata || hasRevisions {
      VStack(alignment: .leading, spacing: 6) {
        // … the existing obsoleted, updated and errata rows, unchanged …
        if let revisions, hasRevisions {
          ForEach(revisions.bannerLines) { line in
            revisionRow(line)
          }
          if let more = revisions.moreText {
            Text(more)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      // … the existing padding and background, unchanged …
    }
  }

  /// News, not a warning: a secondary symbol, unlike the red and orange rows above.
  /// The whole row is the link to the draft's datatracker page.
  private func revisionRow(_ line: RevisionsSummary.Line) -> some View {
    Link(destination: line.url) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "doc.badge.clock").foregroundStyle(.secondary)
        Text(line.relation).fontWeight(.medium).foregroundStyle(.primary)
        Text(line.title).foregroundStyle(.tint)
        Text(line.detail).foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
    .font(.subheadline)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(line.accessibilityLabel)
    .accessibilityAddTraits(.isLink)
  }
```

`StatusBanner` reads `library.revisions` through `revisionsSummary(for:)`, so Observation redraws it when the file arrives. It reads nothing from `@Environment`.

- [ ] **Step 6: Build both platforms**

Run: `make xcodeproj && make build-app && make ios-sim`
Expected: both build with no warnings from the changed files. Then `make lint`: clean.

- [ ] **Step 7: Check it by hand**

With the file from Task 7's local run published nowhere yet, check against a locally served copy:
1. Temporarily point `RevisionsClient.url` at `http://localhost:8765/revisions.json`, serve `corpus/revisions/` with `python3 -m http.server 8765 --directory corpus/revisions`, and `make run`. Do not commit the URL change. On macOS, allow the plain-HTTP load if ATS refuses it; if that needs an Info.plist change, copy the file to `~/Library/Application Support/RFCReader/revisions.json` instead and launch offline.
2. Open RFC 6265: the banner shows "Being replaced by draft-ietf-httpbis-rfc6265bis-22 · In the RFC Editor queue", and clicking it opens `https://datatracker.ietf.org/doc/draft-ietf-httpbis-rfc6265bis/` in the browser. The Info pane's Relationships has "Being replaced by" with the full line.
3. Open RFC 1149: no extra row, no "no revisions" text.
4. Quit, set the cached file's `generatedAt` five days back (`jq '.generatedAt = "…"'`), block the network (or keep the local URL with the server stopped), launch: the RFC 6265 row ends "as of <date>".
5. With VoiceOver on, the row reads as one sentence and activates the link.
6. Revert the URL.

- [ ] **Step 8: Commit**

```bash
git branch --show-current   # feat/rfc-revisions
make fmt && make check && make test-app
git add App/RFCReader/Model/DocumentStore.swift App/RFCReader/Model/LibraryModel.swift App/RFCReader/Views/DocumentView.swift App/RFCReader/Views/Rendering/InfoView.swift
git commit -m "Show drafts revising an RFC in the status banner and the inspector"
```

---

### Task 12: Ship and switch on

This happens after the branch is merged. The spec's "By hand" section requires it before the schedule counts as enabled.

- [ ] **Step 1:** Run the workflow once by hand: `gh workflow run revisions.yml`, then `gh run watch`. Expected: success; the `revisions` release exists, marked as a prerelease, with both assets.
- [ ] **Step 2:** Review the output: `gh release download revisions --pattern revisions.json --dir /tmp/rev && jq '.revisions | length' /tmp/rev/revisions.json` gives a plausible count (dozens to a couple of hundred), and `jq '.revisions["6265"]'` shows 6265bis. Spot-check three entries against their datatracker pages.
- [ ] **Step 3:** The next day, open the scheduled run's log: `read` is a few dozen, not about 970. If it is about 970, the scan record was not passed in: check the "Download the previous scan" step.
- [ ] **Step 4:** Launch the released app build and repeat Task 11, Step 7, items 2–5 against the real URL.
