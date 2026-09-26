import Foundation

/// Recovers document structure from the classic 72-column plain-text RFC format
/// used for everything before RFC 8650 (and still published for every RFC).
///
/// This is deliberately heuristic. It removes page furniture, detects headings,
/// distinguishes prose from ASCII art, re-joins paragraphs split across pages and
/// links `[RFC2119]`, `RFC 2119`, `Section 4.2` and URLs. The original text is always
/// kept available through `stripPagination(_:)` for an "as published" view.
public struct LegacyTextParser: Sendable {
  public init() {}

  public static func parse(_ text: String) -> RFCDocument {
    LegacyTextParser().parse(text)
  }

  public static func parse(_ data: Data) -> RFCDocument {
    parse(String(decoding: data, as: UTF8.self))
  }

  // MARK: - Pagination

  private enum Line: Sendable {
    case text(String)
    case pageBreak
  }

  nonisolated(unsafe) private static let footerPattern = #/\[Page \d+\]\s*$/#
  nonisolated(unsafe) private static let runningHeaderPattern =
    #/^(RFC|Request for Comments:?)\s*\d+\b.*\b\d{4}\s*$/#

  /// Removes form feeds, running headers and page footers, keeping everything else verbatim.
  public static func stripPagination(_ text: String) -> String {
    var output: [String] = []
    var pendingBlank = 0
    var breakOccurred = false
    for line in depaginate(text) {
      switch line {
      case .pageBreak:
        breakOccurred = true
      case .text(let string):
        if string.trimmingCharacters(in: .whitespaces).isEmpty {
          pendingBlank += 1
        } else {
          if !output.isEmpty {
            output += Array(
              repeating: "", count: breakOccurred ? min(pendingBlank, 1) : pendingBlank)
          }
          pendingBlank = 0
          breakOccurred = false
          output.append(string)
        }
      }
    }
    return output.joined(separator: "\n")
  }

  /// The lines `parse` drops as recurring page furniture, in document order.
  ///
  /// For the corpus report: a dropped line leaves no trace in the block counts, so
  /// without this a rule that deletes the body's own lines looks like a clean run.
  public static func recurringFurniture(in text: String) -> [String] {
    let lines = paginated(text)
    return recurringFurniture(lines).sorted().compactMap {
      if case .text(let string) = lines[$0] { return string }
      return nil
    }
  }

  private static func depaginate(_ text: String) -> [Line] {
    let lines = paginated(text)
    let furniture = recurringFurniture(lines)
    guard !furniture.isEmpty else { return lines }
    return lines.enumerated().compactMap { furniture.contains($0.offset) ? nil : $0.element }
  }

  private static func paginated(_ text: String) -> [Line] {
    let rawLines = removingControlCharacters(text).replacingOccurrences(of: "\r\n", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
    var lines: [Line] = []
    var expectingHeader = false
    var firstContentSeen = false

    for rawLine in rawLines {
      var line = String(rawLine)
      var sawFormFeed = false
      if line.contains("\u{0C}") {
        line = line.replacingOccurrences(of: "\u{0C}", with: "")
        sawFormFeed = true
      }
      // Before anything reads a column: every indent heuristic below counts
      // spaces, and a tab-indented line would otherwise read as indent 0 (#40).
      line = line.expandingTabs()
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if firstContentSeen, trimmed.contains(footerPattern) {
        lines.append(.pageBreak)
        expectingHeader = true
        continue
      }
      if sawFormFeed {
        if case .pageBreak? = lines.last {} else { lines.append(.pageBreak) }
        expectingHeader = true
        if trimmed.isEmpty { continue }
      }
      if expectingHeader {
        if trimmed.isEmpty { continue }
        expectingHeader = false
        if trimmed.contains(runningHeaderPattern) { continue }
      }
      if !trimmed.isEmpty { firstContentSeen = true }
      lines.append(.text(line.trimmingTrailingWhitespace()))
    }
    return lines
  }

  private enum Side { case head, foot }

  /// What a block's first line opens with, where a list is concerned: the style it
  /// implies and the column it sits in. Probed once per block and handed down.
  private typealias ListMarker = (style: ListBlock.Style, indent: Int)

  /// The lines that recur at the edges of the pages (#52). The running-header
  /// pattern knows one shape, `RFC nnnn ... yyyy`; plenty of documents set a header
  /// that names no RFC at all -- RFC 793 opens 62 pages with `September 1981`,
  /// `Transmission Control Protocol`, `Functional Specification` -- and the one
  /// thing every header has in common is that it recurs, in the same place, page
  /// after page.
  ///
  /// A page's edge is the block of up to four lines at its top and at its bottom,
  /// and lines are compared with whitespace collapsed and whole numbers masked, so
  /// `Page 7` and `Page 8` are one line. Only edge lines are dropped, never the same words
  /// elsewhere, and never on the first page, where the title block would otherwise
  /// match its own running header.
  ///
  /// Recurring is not enough on its own, because the body recurs too: a MIB module
  /// ends every object in `STATUS current`, and some of those land at a page edge.
  /// Furniture is set off from the body by a blank line on most of the pages it sits
  /// on, and it is seen at the edges more often than anywhere else in the pages;
  /// a line that fails either is the body's, and stays. RFC 3591 lost 89
  /// `DESCRIPTION` clauses to a rule that asked only whether a line recurred.
  ///
  /// There are two kinds, and they differ in what the first one means. A line at the
  /// edge of half the pages or more names the document, and every copy goes -- half
  /// the pages of its parity, for a line on every other page: RFC 821 alternates its
  /// header between facing pages, the last two carry none, and on 34 of 70 the first
  /// copy was kept as the start of a section. A line
  /// at the head of three pages or more, but fewer than half, names the section those
  /// pages are in -- RFC 793's `Philosophy` -- and its first copy is where that section
  /// starts. It is on every page of that section, or every other one where headers
  /// alternate between facing pages, so a line seen with a longer gap is not one;
  /// nor is one only ever at the foot, which is where a record or a table running
  /// over a page break ends; nor is one below a blank line, because a section's name
  /// is part of the page's header block -- RFC 770's `References` directly under its
  /// `RFC 770 ... September 1980` -- where the body starts after the blank lines that
  /// follow the header, and RFC 6208's `Additional information:` at the head of five
  /// pages is the body's. In RFC 770 the first copy is the only thing that says
  /// where its section starts, so the first copy stays, unless the document heads the section itself somewhere with
  /// a numbered heading of the same words (`2.  PHILOSOPHY`), which sections start
  /// at quite well without a second, empty one beside it.
  private static func recurringFurniture(_ lines: [Line]) -> Set<Int> {
    var pages: [Range<Int>] = []
    var start = 0
    for (index, line) in lines.enumerated() {
      if case .pageBreak = line {
        pages.append(start..<index)
        start = index + 1
      }
    }
    pages.append(start..<lines.count)
    let later = pages.dropFirst()
    guard later.count >= 3 else { return [] }

    /// The edge's lines, whether a blank line sets them off from the rest of the
    /// page -- looking one line past a full edge, because RFC 793's header is three
    /// lines and a section's running header the fourth -- and whether they are the
    /// page's very first lines, with no blank line before them.
    struct Edge {
      let lines: [(index: Int, key: String)]
      let setOff: Bool
      let flush: Bool
    }
    func edge<Indices: Sequence<Int>>(_ indices: Indices) -> Edge {
      var found: [(index: Int, key: String)] = []
      var flush = true
      var setOff = false
      for index in indices {
        guard case .text(let string) = lines[index] else { continue }
        if string.isBlank {
          if found.isEmpty {
            flush = false
            continue
          }
          setOff = true
          break
        }
        if found.count == 4 { break }
        found.append((index, furnitureKey(string)))
      }
      return Edge(lines: found, setOff: setOff, flush: flush)
    }

    // Keyed by which edge it sits at as well as what it says, because furniture
    // recurs in the same place: a line at the foot of one page and a line at the
    // head of the next are two sightings of two lines, not one of a header.
    struct Sighting: Hashable {
      let side: Side
      let key: String
    }
    struct Seen {
      var lines: [Int] = []
      var pages: [Int] = []
      var setOff = 0
      var flush = 0
    }
    var seen: [Sighting: Seen] = [:]
    var edgeLines: Set<Int> = []
    for (ordinal, page) in later.enumerated() {
      for (side, edges) in [(Side.head, edge(page)), (Side.foot, edge(page.reversed()))] {
        for (index, key) in edges.lines {
          edgeLines.insert(index)
          func tally(_ found: inout Seen) {
            found.lines.append(index)
            if edges.setOff { found.setOff += 1 }
            if edges.flush { found.flush += 1 }
            // Appended in page order, so a key twice at one page's edge is one
            // page and two lines.
            if found.pages.last != ordinal { found.pages.append(ordinal) }
          }
          tally(&seen[Sighting(side: side, key: key), default: Seen()])
        }
      }
    }

    // Two pages in a row are enough only for a line at the edge of half of them.
    let recurring = seen.filter { _, found in
      found.pages.count >= 3
        || (found.pages.count * 2 >= later.count
          && zip(found.pages, found.pages.dropFirst()).contains { $1 == $0 + 1 })
    }
    guard !recurring.isEmpty else { return [] }
    // How often each recurring line is seen away from the edges, keying the body
    // only when something recurs and counting only what does.
    let candidates = Set(recurring.keys.map(\.key))
    var elsewhere: [String: Int] = [:]
    for page in later {
      for index in page where !edgeLines.contains(index) {
        guard case .text(let string) = lines[index], !string.isBlank else { continue }
        let key = furnitureKey(string)
        if candidates.contains(key) { elsewhere[key, default: 0] += 1 }
      }
    }

    var furniture: Set<Int> = []
    var statedHeadings: Set<String>?
    for (sighting, found) in recurring {
      guard found.setOff * 2 >= found.lines.count,
        elsewhere[sighting.key, default: 0] < found.pages.count
      else { continue }
      // A line on alternate pages is counted against the pages of its parity. One
      // break in the rhythm is allowed where it is long enough to be a rhythm:
      // RFC 908's header skips a page once in 29.
      let gaps = zip(found.pages, found.pages.dropFirst()).map { $1 - $0 }
      let breaks = gaps.count { $0 != 2 }
      let parity = breaks == 0 || (breaks == 1 && gaps.count > 2) ? 2 : 1
      if found.pages.count * parity * 2 >= later.count {
        furniture.formUnion(found.lines)
        continue
      }
      guard sighting.side == .head, found.flush * 2 >= found.lines.count,
        gaps.allSatisfy({ $0 <= 2 })
      else { continue }
      let titles = statedHeadings ?? numberedHeadingTitles(lines)
      statedHeadings = titles
      // Against the key, which has its numbers masked, where the titles do not:
      // the two sides do not normalise alike, so a running header holding a
      // number cannot match its own stated heading and its first copy survives.
      // Both repairs lose content and are measured in #57 -- masking the titles
      // too makes `Chapter 3` and `Chapter 4` one heading and drops a field's
      // value in RFC 1570; comparing the unmasked line drops RFC 783's footnote
      // marker and four others. Keeping a heading too many is the safe side of
      // it, and which way it should fall is that issue's to answer.
      if titles.contains(sighting.key.lowercased()) {
        furniture.formUnion(found.lines)
      } else {
        furniture.formUnion(found.lines.dropFirst())
      }
    }
    return furniture
  }

  /// What two lines are compared as when asking whether they are the same piece of
  /// furniture: whitespace collapsed, and a word that is a whole number masked,
  /// because the page number is the one thing that varies from page to page and it
  /// is a word of its own. Masking digits wherever they fall would make `[RFC-1522]`
  /// and `[RFC-1524]` the same line, and a bibliography sets one anchor per entry.
  private static func furnitureKey<S: StringProtocol>(_ string: S) -> String {
    string.split(whereSeparator: \.isWhitespace)
      .map { $0.utf8.allSatisfy { byte in byte >= 0x30 && byte <= 0x39 } ? "#" : String($0) }
      .joined(separator: " ")
  }

  /// How a heading title reads for the purpose of comparing it: whitespace collapsed,
  /// lowercased, and numbers left alone, because in a heading a number is content.
  private static func headingText<S: StringProtocol>(_ string: S) -> String {
    string.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }

  /// The titles of the numbered headings: what a section running header is compared
  /// against to learn whether the document already heads that section itself. At any
  /// indent, because RFC 793 centres `2.  PHILOSOPHY`; numbered only, because RFC 770
  /// centres an unnumbered `REFERENCES` that is no heading, and its running header is
  /// all it has.
  ///
  /// `1:` counts here in every document, not only where `numbersHeadingsWithAColon`
  /// says so: this runs while the page furniture is found, before the lines that fact is
  /// judged on exist. A colon title taken wrongly can only drop a running header's first
  /// copy along with the rest, and over the corpus none does.
  private static func numberedHeadingTitles(_ lines: [Line]) -> Set<String> {
    var titles: Set<String> = []
    for case .text(let line) in lines {
      let string = line.drop { $0 == " " }
      guard string.first?.isNumber == true,
        let match = string.firstMatch(of: numberedHeadingPattern)
      else { continue }
      titles.insert(headingText(match.title))
    }
    return titles
  }

  /// Resolves nroff overstrikes (`T\bT` for bold, `_\bT` for underline) and drops the
  /// NUL padding and escape bytes found in a few dozen 1970s and 1980s RFCs.
  static func removingControlCharacters(_ text: String) -> String {
    guard
      text.unicodeScalars.contains(where: {
        $0.value < 0x20 && $0 != "\n" && $0 != "\t" && $0 != "\r" && $0 != "\u{0C}"
      })
    else {
      return text
    }
    var result: [Unicode.Scalar] = []
    result.reserveCapacity(text.unicodeScalars.count)
    var iterator = text.unicodeScalars.makeIterator()
    while let scalar = iterator.next() {
      if scalar == "\u{08}" {
        guard let previous = result.popLast(), let next = iterator.next() else { continue }
        result.append(next == "_" ? previous : next)
      } else if scalar.value < 0x20, scalar != "\n", scalar != "\t", scalar != "\r",
        scalar != "\u{0C}"
      {
        continue
      } else {
        result.append(scalar)
      }
    }
    var output = ""
    output.unicodeScalars.append(contentsOf: result)
    return output
  }

  // MARK: - Parsing

  private struct RawBlock {
    var lines: [String]
    var followedByPageBreak = false

    var indent: Int { lines.map(\.leadingSpaceCount).min() ?? 0 }
    var firstLine: String { lines.first ?? "" }
  }

  private struct HeadingInfo {
    var number: String?
    var title: String
    var isAppendix: Bool
    var anchor: String
    var depth: Int
  }

  private struct RawSection {
    var heading: HeadingInfo?
    var blocks: [RawBlock] = []
  }

  nonisolated(unsafe) private static let numberedHeadingPattern =
    #/^(?<number>\d+(?:\.\d+)*)(?<separator>[.:])?\s+(?<title>\S.*)$/#
  nonisolated(unsafe) private static let appendixHeadingPattern =
    #/^(?:Appendix\s+)?(?<number>[A-Z](?:\.\d+)*)\.?\s+(?<title>[A-Z].*)$/#

  /// Diagnoses every block of a document without building one: what the prose test
  /// decided about each, and why.
  ///
  /// Shares `rawSections` with `parse`, so the blocks reported here are exactly the
  /// blocks the parser classifies — not a re-segmentation that might disagree.
  public static func proseDiagnostics(for text: String) -> [BlockDiagnostics] {
    prepared(text).sections.flatMap { section in
      let anchor = section.heading?.anchor ?? ""
      return section.blocks.map { block in
        BlockDiagnostics(
          section: anchor,
          firstLine: String(block.firstLine.trimmingCharacters(in: .whitespaces).prefix(80)),
          lineCount: block.lines.count,
          claimedByList: listItems(block.lines, marker: listMarker(of: block.lines)) != nil,
          diagnosis: diagnose(block.lines)
        )
      }
    }
  }

  /// Everything between raw text and blocks: depagination, front matter, segmentation.
  ///
  /// Both entry points go through here so neither can normalise the text differently
  /// from the other. Extracting only `rawSections` left this prelude written twice,
  /// which is the same drift one level up.
  private static func prepared(_ text: String) -> (front: [String], sections: [RawSection]) {
    let lines = collapsingDoubleSpacing(depaginate(text))
    let colonNumbered = numbersHeadingsWithAColon(lines)
    let (front, bodyStart) = splitFrontMatter(lines, colonNumbered: colonNumbered)
    let body = bodyIsIndented(lines[bodyStart...])
    return (
      front,
      rawSections(in: lines, from: bodyStart, bodyIsIndented: body, colonNumbered: colonNumbered)
    )
  }

  /// Whether `1:` and `2.4.12:` at column 0 are headings in this document. RFC 2078, 2743
  /// and 2130 number every heading that way (#71), and 1308, 1309, 1913, 2025 and 2479
  /// a few among their `1.` ones. But the same shape is a field label (RFC 2301's `10:
  /// ITU-T Rec. T.43 representation`), a line-numbered listing (RFC 2626 quotes grep
  /// output as `140:      Chuck Rose`), and a second numbering (RFC 705 lists its
  /// commands as `1.  BEGIN Command` and describes each again under `1:  BEGIN   4b`,
  /// `4b` being its own label for that part). A document numbers each section once, so
  /// the colon form counts only where none of its numbers is also the number of a `1.`
  /// heading. In 2301, 2626 and 705 some are; in the eight that number headings with a
  /// colon, none is.
  ///
  /// That alone passes a document with a single colon number and nothing to repeat:
  /// RFC 526's agenda sets a time as `11: 00   Group discussion continuation`, and it
  /// is no heading there only because the line after it is not blank. So each colon
  /// number also has to follow from one: the number before it (`2.4.11` for `2.4.12`,
  /// `10` for `11`) or one it is under (`2.4`) must be a heading number too, however it
  /// is set. Only `0` and `1` open a numbering on their own.
  private static func numbersHeadingsWithAColon(_ lines: [Line]) -> Bool {
    numbersHeadingsWithAColon(
      lines.compactMap { line in
        guard case .text(let string) = line else { return nil }
        return string
      })
  }

  static func numbersHeadingsWithAColon(_ lines: [String]) -> Bool {
    var colonNumbers: Set<Substring> = []
    var fullStopNumbers: Set<Substring> = []
    var numbers: Set<Substring> = []
    for string in lines where string.startsAtColumnZero {
      guard let match = string.firstMatch(of: numberedHeadingPattern) else { continue }
      numbers.insert(match.number)
      switch match.separator {
      case ":": colonNumbers.insert(match.number)
      case ".": fullStopNumbers.insert(match.number)
      default: break
      }
    }
    guard !colonNumbers.isEmpty, colonNumbers.isDisjoint(with: fullStopNumbers) else {
      return false
    }
    return colonNumbers.allSatisfy { follows($0, in: numbers) }
  }

  /// Whether heading `number` follows from one of `numbers`: the one before it at its
  /// own level, or any it is under. RFC 2130 skips a level, `3.1:` to `3.1.1.1:`, and
  /// RFC 1309 numbers `2  MODELS` with no separator before `3: THE X.500 MODEL`.
  private static func follows(_ number: Substring, in numbers: Set<Substring>) -> Bool {
    var parts = number.split(separator: ".")
    guard let last = parts.popLast().flatMap({ Int($0) }) else { return false }
    if parts.isEmpty, last <= 1 { return true }
    if last >= 1, numbers.contains(Substring((parts + ["\(last - 1)"]).joined(separator: "."))) {
      return true
    }
    return parts.indices.contains {
      numbers.contains(Substring(parts[...$0].joined(separator: ".")))
    }
  }

  /// Splits the body into raw sections at column-0 headings, and each section into
  /// blocks at blank lines.
  ///
  /// Extracted from `parse` so that the diagnostic entry point can report on exactly
  /// the blocks the parser classifies. A second segmentation written alongside this
  /// one would drift, and a diagnosis of blocks the parser never saw is worse than
  /// none.
  private static func rawSections(
    in lines: [Line], from bodyStart: Int, bodyIsIndented: Bool, colonNumbered: Bool
  ) -> [RawSection] {
    var sections: [RawSection] = [RawSection(heading: nil)]
    var current: [String] = []
    var pendingBreak = false

    func flushBlock() {
      if !current.isEmpty {
        sections[sections.count - 1].blocks.append(
          RawBlock(lines: current, followedByPageBreak: pendingBreak))
        current = []
      }
      pendingBreak = false
    }

    for index in lines.indices[bodyStart...] {
      switch lines[index] {
      case .pageBreak:
        if current.isEmpty, var last = sections[sections.count - 1].blocks.popLast() {
          last.followedByPageBreak = true
          sections[sections.count - 1].blocks.append(last)
        } else {
          pendingBreak = true
          flushBlock()
        }
      case .text(let string):
        if string.isBlank {
          flushBlock()
        } else if let heading = Self.heading(
          at: index, in: lines, bodyIsIndented: bodyIsIndented, colonNumbered: colonNumbered,
          startsBlock: current.isEmpty)
        {
          flushBlock()
          sections.append(RawSection(heading: heading))
        } else {
          current.append(string)
        }
      }
    }
    flushBlock()
    return sections
  }

  public func parse(_ text: String) -> RFCDocument {
    let (frontLines, sections) = Self.prepared(text)
    var header = Self.parseFrontMatter(frontLines)

    // Collect known section numbers and reference anchors for link resolution.
    let sectionNumbers = Set(sections.compactMap { $0.heading?.number })
    let bibliographies = Self.settlingEntryAnchors(
      sections.indices.reduce(into: [Int: [Reference]]()) { lists, index in
        guard let heading = sections[index].heading, Self.isReferencesHeading(heading) else {
          return
        }
        lists[index] = Self.parseReferences(sections[index].blocks)
      },
      reserved: Self.reservedAnchors(Self.sectionAnchorCandidates(sections))
    )
    var referenceTargets: [String: CrossReference.Target] = [:]
    // Keyed by the label, which is what the prose cites; pointing at the anchor, which
    // is what the entry is declared under. Pointing at `ref-<label>` instead, which no
    // entry ever was, left 30,368 citations in 3,708 documents linking nowhere (#81).
    // A label listed twice is cited as its first entry, whichever kind of target it is.
    for index in bibliographies.keys.sorted() {
      for reference in bibliographies[index] ?? []
      where referenceTargets[reference.displayAnchor] == nil {
        referenceTargets[reference.displayAnchor] =
          reference.documentID.map { .document($0, section: nil) }
          ?? .anchor(reference.anchor)
      }
    }
    let linker = InlineLinker(sectionNumbers: sectionNumbers, referenceTargets: referenceTargets)

    // Convert raw sections into structured ones.
    var flat: [Section] = []
    // A document has one abstract, the first: RFC 2371's appendix embeds a second
    // protocol's, and a catalogue (RFC 1292, 1632, 2116) gives every entry one (#72).
    // A later one is the body's, and stays where it is.
    var abstractTaken = false
    for (index, raw) in sections.enumerated() {
      guard let heading = raw.heading else {
        // Text before the first heading that is not front matter: keep as an unnumbered lead-in.
        let blocks = Self.blocks(from: raw.blocks, linker: linker)
        if !blocks.isEmpty {
          flat.append(Section(anchor: "preamble", title: "", blocks: blocks))
        }
        continue
      }
      let lowered = heading.title.lowercased()
      if heading.number == nil {
        // Boilerplate that the RFCXML path also omits; the original text view still has it.
        let boilerplate = [
          "table of contents", "status of this memo", "status of memo", "copyright notice",
          "full copyright statement", "intellectual property", "disclaimer of validity",
        ]
        let isAbstract = lowered == "abstract" && !abstractTaken
        if isAbstract || boilerplate.contains(where: { lowered.hasPrefix($0) }) {
          let extent = Self.boilerplateExtent(
            of: raw.blocks, isContents: lowered.hasPrefix("table of contents"))
          if isAbstract {
            header.abstract = Self.blocks(from: Array(raw.blocks.prefix(extent)), linker: linker)
            abstractTaken = true
          }
          if extent < raw.blocks.count {
            let body = Self.blocks(from: Array(raw.blocks.dropFirst(extent)), linker: linker)
            if !body.isEmpty {
              flat.append(Section(anchor: "after-\(heading.anchor)", title: "", blocks: body))
            }
          }
          continue
        }
      }
      var section = Section(
        anchor: heading.anchor,
        number: heading.number,
        // A heading cites like any other prose -- "Changes from RFC 3066",
        // "Differences from RFC 793" -- and roughly 3,500 headings in the
        // corpus name a document. The number is not part of the words, so
        // the linker never sees it and cannot mistake it for a section
        // cross reference.
        title: linker.link(heading.title),
        isAppendix: heading.isAppendix
      )
      if let references = bibliographies[index] {
        if !references.isEmpty {
          section.blocks = [.references(ReferenceList(title: heading.title, entries: references))]
        } else {
          section.blocks = Self.blocks(from: raw.blocks, linker: linker)
        }
      } else {
        section.blocks = Self.blocks(from: raw.blocks, linker: linker)
      }
      flat.append(section)
    }

    return RFCDocument(
      header: header, sections: Self.nest(Self.makingAnchorsUnique(flat)), source: .text)
  }

  /// Every anchor a section can be declared under, so no entry is: each a section can start
  /// with, and each `makingAnchorsUnique` can rename a repeat to. That rename runs after
  /// the prose is linked, and an entry settled onto `section-1-2` beside two sections
  /// numbered 1 was renamed off it, away from its citations. A repeat takes the first free
  /// `-n`, and what can hold one before it is an earlier repeat or another heading
  /// spelled so (`name-foo-2`, for `Foo 2`), so for an anchor that can appear `c` times,
  /// with `r` headings spelling `-n` of it, the rename lands within `-2` to `-(c + r)`.
  static func reservedAnchors(_ candidates: [String]) -> Set<String> {
    let counts = candidates.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    var reserved = Set(candidates)
    for (anchor, count) in counts where count > 1 {
      let spelled = counts.keys.count {
        $0.hasPrefix("\(anchor)-") && $0.dropFirst(anchor.count + 1).allSatisfy(\.isNumber)
      }
      for suffix in 2...(count + spelled) { reserved.insert("\(anchor)-\(suffix)") }
    }
    return reserved
  }

  /// `reservedAnchors` for the sections `parse` would read from `text`.
  static func reservedAnchors(in text: String) -> Set<String> {
    reservedAnchors(sectionAnchorCandidates(prepared(text).sections))
  }

  /// Every anchor a section can start with, in document order: the lead-in, then each
  /// heading's own and the one its body after the boilerplate takes.
  private static func sectionAnchorCandidates(_ sections: [RawSection]) -> [String] {
    ["preamble"] + sections.compactMap(\.heading).flatMap { [$0.anchor, "after-\($0.anchor)"] }
  }

  /// Each entry's anchor as it will be declared, settled before any prose is linked so a
  /// citation points at the anchor its entry ends with. Renaming repeats afterwards, as
  /// `makingAnchorsUnique` does sections, moved entries out from under the citations
  /// already pointing at them: `[X]`, `[X]`, `[X-2]` made the second `X-2` and the third
  /// `X-2-2`, so `[X-2]` opened the second `[X]`; `[ECMA TR 53]` and `[ECMA TR/53]` spell
  /// one name, and one of them is renamed. The first holder of an anchor keeps it; a
  /// repeat takes the first `-2`, `-3` that no entry is declared under and no section can
  /// take, so none is renamed again.
  static func settlingEntryAnchors(_ lists: [Int: [Reference]], reserved: Set<String>) -> [Int:
    [Reference]]
  {
    var lists = lists
    let declared = Set(lists.values.joined().map(\.anchor))
    var taken = reserved
    for index in lists.keys.sorted() {
      var list = lists[index] ?? []
      for entry in list.indices {
        let anchor = list[entry].anchor
        if taken.insert(anchor).inserted { continue }
        var suffix = 2
        while taken.contains("\(anchor)-\(suffix)") || declared.contains("\(anchor)-\(suffix)") {
          suffix += 1
        }
        list[entry].anchor = "\(anchor)-\(suffix)"
        taken.insert(list[entry].anchor)
      }
      lists[index] = list
    }
    return lists
  }

  /// An anchor is what a deep link, the table of contents and a reading position key off,
  /// and the XML declares each one as an ID, sections and bibliography entries alike.
  /// Headings that repeat -- two `Introduction`s in RFC 1, two sections numbered 1 in RFC
  /// 19 -- and a bibliography listing one label twice gave two elements one anchor in 526
  /// documents (#65), and a link landed on whichever came first. A repeat takes the next
  /// free `-2`, `-3`, the way xml2rfc numbers them; the first keeps its anchor, so every
  /// link that landed on it still does. An entry keeps its label as `displayAnchor`, and
  /// arrives here unique already (`settlingEntryAnchors`), clear of every anchor a
  /// section's repeat can be renamed to (`reservedAnchors`).
  private static func makingAnchorsUnique(_ sections: [Section]) -> [Section] {
    var taken: Set<String> = []
    func unique(_ anchor: String) -> String {
      var candidate = anchor
      var suffix = 2
      while !taken.insert(candidate).inserted {
        candidate = "\(anchor)-\(suffix)"
        suffix += 1
      }
      return candidate
    }
    return sections.map { section in
      var section = section
      section.anchor = unique(section.anchor)
      section.blocks = section.blocks.map { block in
        guard case .references(var list) = block else { return block }
        for index in list.entries.indices {
          list.entries[index].anchor = unique(list.entries[index].anchor)
        }
        return .references(list)
      }
      return section
    }
  }

  /// How many of an omitted section's blocks are its own: all of them, unless it has run
  /// on far past what boilerplate is, and then its first block and those after it that
  /// are still boilerplate-shaped -- paragraphs, or for a table of contents, entries.
  ///
  /// Such a section ends at the next heading, and where the document's headings are of a
  /// shape the parser does not know -- `1)` in RFC 1927, `1:` in RFC 2743, indented in
  /// RFC 908 -- no heading ends it, and it takes the body (#60). Of the 29,856 omitted
  /// sections in the corpus, 446 of the 552 over 60 lines are two or three blocks, none
  /// that is boilerplate is more than 16, and every one that swallowed its body is 22 or
  /// more. Past the gap a single line ends it, because boilerplate is paragraphs and a
  /// lone line is where the body's own unrecognised heading sits.
  private static func boilerplateExtent(of blocks: [RawBlock], isContents: Bool) -> Int {
    guard blocks.count > 20 else { return blocks.count }
    func isEntry(_ line: String) -> Bool {
      line.trimmingCharacters(in: .whitespaces).last?.isNumber == true || line.contains("..")
        || line.contains(". .")
    }
    return 1
      + blocks.dropFirst().prefix { block in
        isContents
          ? block.lines.count(where: isEntry) * 2 >= block.lines.count
          : block.lines.count > 1 && looksLikeProse(block.lines)
      }.count
  }

  // MARK: Front matter

  /// Front matter is the header block (first run of lines), the title (second run, which
  /// may start at column 0 when it fills the line), and the runs after it up to the first
  /// that is the body's: one holding a heading, or a paragraph before it. Where no heading
  /// comes at all, the front matter ends after the title.
  ///
  /// A paragraph is the body's even before any heading: `parse` keeps it as the lead-in,
  /// where front matter has nowhere to put it and it is lost. Ending the front matter only
  /// at a heading lost everything above the first column-0 heading that came -- in RFC 809
  /// the one opening its appendix, in RFC 796 `References` (#60). And the run a heading
  /// sits in is the body's from its start: in RFC 105 and a hundred more, the first
  /// paragraph indents its first line and sets its second at the margin, and ending at the
  /// second line left the first behind in the front matter. So the front matter ends where
  /// it used to or sooner, never later.
  private static func splitFrontMatter(_ lines: [Line], colonNumbered: Bool) -> (
    front: [String], bodyStart: Int
  ) {
    var front: [String] = []
    var run = 0
    // Where the current run starts, and how much front matter there was before it: the
    // front matter is only ever appended to, so its length is all a split needs.
    var runStart: (offset: Int, frontCount: Int)?
    // A few dozen 1970s and 1980s RFCs indent their headings like the body (RFC 775,
    // RFC 1144), so no heading ever arrives. Ending the front matter after the title
    // keeps the prose; swallowing the whole file would leave an empty document.
    var afterTitle: (offset: Int, frontCount: Int)?
    // Noted, not stopped at: with no heading to come, after the title is sooner.
    var firstParagraph: (offset: Int, frontCount: Int)?
    func split(_ at: (offset: Int, frontCount: Int)) -> (front: [String], bodyStart: Int) {
      (Array(front.prefix(at.frontCount)), at.offset)
    }
    // Runs are counted from the one that states the number: RFC 873 opens with an NLS
    // journal stamp in two runs ahead of its header, and "after the title" counted from
    // the stamp fell before the number line (#60).
    let skipped = (numberRun(in: lines) ?? 1) - 1
    for (offset, line) in lines.enumerated() {
      guard case .text(let string) = line else { continue }
      if string.isBlank {
        if firstParagraph == nil, let start = runStart, run - skipped > 2 {
          let runLines = Array(front[start.frontCount...])
          if runLines.count > 1, looksLikeProse(runLines) { firstParagraph = start }
        }
        runStart = nil
        front.append("")
        continue
      }
      let startsRun = runStart == nil
      let start = runStart ?? (offset, front.count)
      if startsRun {
        run += 1
        runStart = start
      }
      // RFC 651 sets no blank line after its title, so the title run is the whole
      // document. The body's first section ends it, unless it is the run's first
      // line. First means numbered 1: any number would take RFC 551's `251 Mercer
      // Street` for a section, and an appendix would not do either, since `A
      // Standard for ...` reads as appendix A.
      if run - skipped == 2, !startsRun, string.startsAtColumnZero,
        let heading = heading(from: string, colonNumbered: colonNumbered), !heading.isAppendix,
        heading.number?.split(separator: ".").first == "1"
      {
        return (front, offset)
      }
      if run - skipped > 2 {
        if afterTitle == nil { afterTitle = start }
        // Deliberately laxer than the body's rule: the stand-alone test needs the
        // body's indent, which is not known until this scan has finished. Stopping
        // early only leaves a line in the body that turns out not to be a heading;
        // stopping late would swallow it into the front matter and lose it.
        if string.startsAtColumnZero, heading(from: string, colonNumbered: colonNumbered) != nil {
          return split(firstParagraph ?? start)
        }
      }
      front.append(string)
    }
    return afterTitle.map(split) ?? (front, lines.count)
  }

  /// Which run of lines states the document's number, among the first four.
  private static func numberRun(in lines: [Line]) -> Int? {
    var run = 0
    var previousWasBlank = true
    for case .text(let string) in lines {
      if string.isBlank {
        previousWasBlank = true
        continue
      }
      if previousWasBlank {
        run += 1
        if run > 4 { return nil }
      }
      previousWasBlank = false
      if statedNumber(in: string) != nil { return run }
    }
    return nil
  }

  nonisolated(unsafe) private static let monthYearPattern =
    #/(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/#
  nonisolated(unsafe) private static let authorPattern =
    #/^(?:[A-Z]\.\s?)+\s*[A-Z][\w'\-]+(?:,\s*Ed(?:itor)?\.?)?$/#

  /// The line that states the document's number, in any of the spellings the series has
  /// used (#51): `Request for Comments: 793`, `RFC # 64`, `NWG/RFC# 276`, `NWG RFC 103`, `RFC-811`,
  /// `Request For Comment: 4801`, the source's own `Request for Commments: 2347`. Tried
  /// against the whole line, at its start or where a column begins, because the number
  /// is not always in the left column (RFC 811 sets it on the right) and a label spaced
  /// widely enough from its number is split from it by the column split
  /// (`Request for Comments:    50`).
  nonisolated(unsafe) private static let numberLinePattern =
    #/(?:^|\s{2})(?:NWG\s*/?\s*)?(?:RFC|Requests?\s+(?:for\s+)?Comm+ents?)\s*(?:(?:#|:|-|No\.)\s*)*(?:RFC\s*)?(\d+)\b/#
    .ignoresCase()

  private static func parseFrontMatter(_ lines: [String]) -> DocumentHeader {
    var header = DocumentHeader(title: "")
    var index = 0
    while index < lines.count, lines[index].isEmpty { index += 1 }

    // Header block: two-column lines up to the first blank line. Usually the first run
    // of lines, but a few documents open with something else -- a date (RFC 753), a
    // title (RFC 609), a report number (RFC 987) -- and state their number in the run
    // after it. The first run that states a number is the header; with none, the first
    // run is.
    var runStart = index
    while runStart < lines.count {
      var runEnd = runStart
      while runEnd < lines.count, !lines[runEnd].isEmpty { runEnd += 1 }
      if lines[runStart..<runEnd].contains(where: { statedNumber(in: $0) != nil }) {
        index = runStart
        break
      }
      runStart = runEnd
      while runStart < lines.count, lines[runStart].isEmpty { runStart += 1 }
    }
    while index < lines.count, !lines[index].isEmpty {
      let line = lines[index]
      index += 1
      let columns = line.components(separatedBy: "   ").map {
        $0.trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
      guard let left = columns.first else { continue }
      let right = columns.count > 1 ? columns.last! : nil

      if left.hasPrefix("Obsoletes:") {
        header.obsoletes = documentIDs(in: left)
      } else if left.hasPrefix("Updates:") {
        header.updates = documentIDs(in: left)
      } else if left.hasPrefix("Category:") {
        header.category = left.dropFirst("Category:".count).trimmingCharacters(in: .whitespaces)
      } else if header.id == nil, let number = statedNumber(in: line) {
        // The first one wins: a continuation line under `Obsoletes:` is set as
        // `            RFC #680` (RFC 733), and must not replace the number above it.
        header.id = .rfc(number)
      }

      for candidate in [left, right].compactMap({ $0 }) {
        if let match = candidate.firstMatch(of: monthYearPattern) {
          header.date = PublicationDate(
            year: Int(match.2) ?? 0, month: PublicationDate.month(from: String(match.1)))
        } else if candidate == right, candidate.contains(authorPattern) {
          header.authors.append(
            Author(
              name: candidate.replacingOccurrences(of: ", Ed.", with: ""),
              role: candidate.contains(", Ed") ? "Editor" : nil))
        }
      }
    }

    // Title: the next run of non-blank lines, whatever their indentation.
    var titleLines: [String] = []
    while index < lines.count {
      let line = lines[index]
      if line.isEmpty {
        if !titleLines.isEmpty { break }
      } else {
        titleLines.append(line.trimmingCharacters(in: .whitespaces))
      }
      index += 1
    }
    header.title = titleLines.joined(separator: " ")
    return header
  }

  private static func statedNumber(in line: String) -> Int? {
    line.trimmingCharacters(in: .whitespaces).firstMatch(of: numberLinePattern).flatMap {
      Int($0.1)
    }
  }

  private static func documentIDs(in text: String) -> [DocumentID] {
    text.matches(of: #/\d+/#).compactMap { Int($0.output) }.map { DocumentID.rfc($0) }
  }

  // MARK: Headings

  private static let nonHeadingWords: Set<String> = [
    "rfc", "obsoletes", "updates", "category", "issn",
  ]

  /// Header lines, refused as a heading by what they say rather than by their first
  /// word: the body a header block names, and the number label, whose value is not
  /// always a number (`Request for Comments: DRAFT`, `Request for Comments: 17a`).
  /// Refusing every line that opens with `Network`, `Internet` or `Request` kept these
  /// out of the body, and refused about 120 real headings with them -- `NETWORK
  /// NUMBERS`, `Internet Protocol`, and RFC 796's only one.
  private static let headerLinePrefixes = [
    "network working group", "internet engineering task force",
    "internet architecture board", "internet research task force",
    "request for comments:",
  ]

  /// True when the body sits at an indent and headings stand out at column 0, which is
  /// the layout `heading(from:)` assumes. A few hundred legacy RFCs (1142, 1305, 1247,
  /// 1034 and others) set their prose at column 0 as well; there the indent says nothing
  /// and every line would otherwise become an unnumbered heading.
  private static func bodyIsIndented(_ body: ArraySlice<Line>) -> Bool {
    var counts: [Int: Int] = [:]
    for case .text(let string) in body where !string.isBlank {
      counts[string.leadingSpaceCount, default: 0] += 1
    }
    guard !counts.isEmpty else { return true }
    // A heading standing out at column 0 only says anything where column 0 is the
    // exception, and the mode alone cannot say that: RFC 1540 sets 395 lines at
    // each of column 0 and column 3, and a tie used to resolve to an indented body
    // and turn its 300-row protocol table into 300 headings (#56).
    //
    // A quarter more, which is where the corpus separates. Below it are the
    // standards lists and port registries that are a column-0 table with a little
    // prose around it -- RFC 1540 at 1.00, 1500 at 1.02, 1410 at 1.16, 34 documents
    // in all. The nearest document above is RFC 2060 at 1.46, IMAP4rev1, which is
    // ordinary numbered prose and loses every heading if it is read the other way.
    // The corpus is otherwise nowhere near this line: the median document has 12.5
    // times as much body as column 0.
    let indented = counts.lazy.filter { $0.key > 0 }.map(\.value).max() ?? 0
    return indented * 4 > counts[0, default: 0] * 5
  }

  /// Where a heading is allowed to sit. It starts at column 0, and in a document whose
  /// body starts there too — so that the indent says nothing — it also has to stand alone
  /// between blank lines. `heading(from:)` judges the text; this judges the position.
  private static func heading(
    at index: Int, in lines: [Line], bodyIsIndented: Bool, colonNumbered: Bool, startsBlock: Bool
  ) -> HeadingInfo? {
    guard case .text(let string) = lines[index], string.startsAtColumnZero else { return nil }
    guard bodyIsIndented || (startsBlock && isBlankOrEnd(lines, at: index + 1)) else { return nil }
    return heading(from: string, colonNumbered: colonNumbered)
  }

  private static func isBlankOrEnd(_ lines: [Line], at index: Int) -> Bool {
    guard lines.indices.contains(index) else { return true }
    switch lines[index] {
    case .pageBreak:
      return true
    case .text(let string):
      return string.isBlank
    }
  }

  /// A couple of dozen documents (RFC 817, 813, 888, 827) are typeset double spaced: a
  /// blank line sits between every pair of lines, so no paragraph ever forms and every
  /// line stands alone. Drop those single blanks and keep the wider gaps, which are the
  /// real paragraph breaks. The "as published" view goes through `stripPagination(_:)`
  /// and is not touched.
  private static func collapsingDoubleSpacing(_ lines: [Line]) -> [Line] {
    var content = 0
    var isolated = 0
    for (index, line) in lines.enumerated() {
      guard case .text(let string) = line, !string.isBlank else { continue }
      content += 1
      if isBlankOrEnd(lines, at: index - 1), isBlankOrEnd(lines, at: index + 1) { isolated += 1 }
    }
    guard content > 20, isolated * 5 >= content * 3 else { return lines }

    var result: [Line] = []
    for (index, line) in lines.enumerated() {
      if case .text(let string) = line, string.isBlank,
        !isBlankOrEnd(lines, at: index - 1), !isBlankOrEnd(lines, at: index + 1)
      {
        continue
      }
      result.append(line)
    }
    return result
  }

  private static func heading(from line: String, colonNumbered: Bool) -> HeadingInfo? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.count < 120 else { return nil }
    if let match = trimmed.firstMatch(of: numberedHeadingPattern) {
      guard colonNumbered || match.separator != ":" else { return nil }
      let number = String(match.number)
      let title = String(match.title).trimmingTrailingDots().collapsingWhitespace()
      return HeadingInfo(
        number: number, title: title, isAppendix: false, anchor: "section-\(number)",
        depth: number.split(separator: ".").count)
    }
    if let match = trimmed.firstMatch(of: appendixHeadingPattern) {
      let number = String(match.number)
      let title = String(match.title).trimmingTrailingDots().collapsingWhitespace()
      return HeadingInfo(
        number: number, title: title, isAppendix: true, anchor: "appendix-\(number)",
        depth: number.split(separator: ".").count)
    }
    // Unnumbered heading: "Abstract", "Security Considerations", "Author's Address".
    let firstWord = trimmed.split(separator: " ").first.map { String($0).lowercased() } ?? ""
    // A number line opens with its label (`RFC: 791`, `NWG/RFC# 732`). Asked anywhere in
    // the line, the pattern also finds `RFC 399` after a sentence's double space, and
    // prose at column 0 that mentions a document stops ending the front matter: RFC
    // 431 lost a line of its first paragraph that way.
    guard !nonHeadingWords.contains(firstWord), trimmed.first?.isLetter == true,
      trimmed.prefixMatch(of: numberLinePattern) == nil
    else { return nil }
    let lowered = trimmed.lowercased()
    guard !headerLinePrefixes.contains(where: { lowered.hasPrefix($0) }) else { return nil }
    return HeadingInfo(
      number: nil, title: trimmed, isAppendix: false, anchor: "name-\(trimmed.slugified())",
      depth: 1)
  }

  private static func isReferencesHeading(_ heading: HeadingInfo) -> Bool {
    heading.title.lowercased().contains("references")
  }

  private static func nest(_ flat: [Section]) -> [Section] {
    var roots: [Section] = []
    var stack: [(depth: Int, section: Section)] = []

    func attach(_ finished: Section) {
      if let parentIndex = stack.indices.last {
        stack[parentIndex].section.subsections.append(finished)
      } else {
        roots.append(finished)
      }
    }

    for section in flat {
      let depth = section.number == nil ? 1 : section.depth
      while let top = stack.last, top.depth >= depth {
        stack.removeLast()
        attach(top.section)
      }
      stack.append((depth, section))
    }
    while let top = stack.popLast() {
      attach(top.section)
    }
    return roots
  }

  // MARK: Blocks

  nonisolated(unsafe) private static let bulletPattern =
    #/^(?<indent>\s*)(?<marker>[o\-\*\u{2022}])\s+(?<text>\S.*)$/#
  nonisolated(unsafe) private static let numberedItemPattern =
    #/^(?<indent>\s*)(?<marker>\(?(?:\d+|[a-z]|[ivx]+)[\.\)])\s+(?<text>\S.*)$/#
  /// `containsArtwork` answers the same question byte by byte; an alternative added
  /// here has to be added there, and `theByteScansAgreeWithTheRegexes` is the guard.
  nonisolated(unsafe) static let artworkPattern =
    #/\+-|-\+|\|\s|\s\||[\/\\]_|_[\/\\]|\.\.\.\.|={3,}|-{3,}|<-|->|\d\s{2,}\d/#
  /// A run of three or more spaces between two non-space characters, not following
  /// sentence punctuation: a column gap rather than the gap after a full stop.
  nonisolated(unsafe) static let internalGapPattern = #/[^.?!:]\s{3,}\S/#

  /// `artworkPattern` and `internalGapPattern` as existence tests, asked of every line
  /// of every block the prose test sees. Swift's regex engine tries each alternative
  /// at each character, and `diagnose` was about half of `parse`. On an ASCII line --
  /// nearly every line of the corpus -- a pass over the trimmed bytes answers the same
  /// question; any other line goes to the regex. So does a line holding `\r`, because
  /// the regex reads `\r\n` as one character and would count one space where the
  /// bytes count two.
  ///
  /// The report's count of artwork matches still comes from the regex: which
  /// alternative claims an overlap decides that count, and it is offline.
  static func containsArtwork(_ line: String) -> Bool {
    if let found = withTrimmedASCII(
      line,
      { bytes in
        for index in bytes.indices {
          let found =
            switch Unicode.Scalar(bytes[index]) {
            case "+": bytes.holds("+-", at: index)
            case "-":
              bytes.holds("-+", at: index) || bytes.holds("->", at: index)
                || bytes.holds("---", at: index)
            case "/": bytes.holds("/_", at: index)
            case "\\": bytes.holds("\\_", at: index)
            case "_": bytes.holds("_/", at: index) || bytes.holds("_\\", at: index)
            case ".": bytes.holds("....", at: index)
            case "=": bytes.holds("===", at: index)
            case "<": bytes.holds("<-", at: index)
            case "|": index + 1 < bytes.count && isSpace(bytes[index + 1])
            case "0"..."9": digitGapDigit(bytes, at: index)
            default: isSpace(bytes[index]) && bytes.holds("|", at: index + 1)
            }
          if found { return true }
        }
        return false
      })
    {
      return found
    }
    return line.trimmingCharacters(in: .whitespaces).contains(artworkPattern)
  }

  /// A digit, a run of two or more spaces, a digit: `1   2` in a table.
  private static func digitGapDigit(_ bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
    var end = index + 1
    while end < bytes.count, isSpace(bytes[end]) { end += 1 }
    return end - index - 1 >= 2 && end < bytes.count
      && (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[end])
  }

  /// Three or more spaces before a non-space, where what precedes the run is not
  /// sentence punctuation. The regex's `[^.?!:]` also admits a space, so a run of four
  /// needs nothing before it: its first space is that character.
  static func hasInternalGap(_ line: String) -> Bool {
    if let found = withTrimmedASCII(
      line,
      { bytes in
        var index = 0
        while index < bytes.count {
          guard isSpace(bytes[index]) else {
            index += 1
            continue
          }
          let start = index
          while index < bytes.count, isSpace(bytes[index]) { index += 1 }
          guard index < bytes.count else { return false }
          let run = index - start
          if run >= 4 { return true }
          if run == 3, start > 0, !".?!:".utf8.contains(bytes[start - 1]) { return true }
        }
        return false
      })
    {
      return found
    }
    return line.trimmingCharacters(in: .whitespaces).contains(internalGapPattern)
  }

  /// `line` trimmed as `.whitespaces` trims it -- spaces and tabs, in ASCII -- when every
  /// byte is ASCII and none is `\r`; nil otherwise, for the caller to use the regex.
  private static func withTrimmedASCII(_ line: String, _ body: (UnsafeBufferPointer<UInt8>) -> Bool)
    -> Bool?
  {
    var line = line
    return line.withUTF8 { bytes in
      guard bytes.allSatisfy({ $0 < 0x80 && $0 != UInt8(ascii: "\r") }) else { return nil }
      var start = bytes.startIndex
      var end = bytes.endIndex
      while start < end, bytes[start] == 0x20 || bytes[start] == 0x09 { start += 1 }
      while end > start, bytes[end - 1] == 0x20 || bytes[end - 1] == 0x09 { end -= 1 }
      return body(UnsafeBufferPointer(rebasing: bytes[start..<end]))
    }
  }

  /// `\s` over ASCII: space, and tab through carriage return.
  private static func isSpace(_ byte: UInt8) -> Bool {
    byte == 0x20 || (0x09...0x0D).contains(byte)
  }

  private static func blocks(from rawBlocks: [RawBlock], linker: InlineLinker) -> [Block] {
    // Re-join paragraphs that a page break cut in half.
    var merged: [RawBlock] = []
    var index = 0
    while index < rawBlocks.count {
      var block = rawBlocks[index]
      while block.followedByPageBreak, index + 1 < rawBlocks.count,
        shouldJoinAcrossPage(block, rawBlocks[index + 1])
      {
        block.lines += rawBlocks[index + 1].lines
        block.followedByPageBreak = rawBlocks[index + 1].followedByPageBreak
        index += 1
      }
      merged.append(block)
      index += 1
    }

    var result: [Block] = []
    // The marker indent of the list `result.last` holds, while it holds one.
    var openListIndent: Int?
    for block in merged {
      // Probed once: the continuation test needs to know the block opens with no
      // marker, and a list the block produces needs the column of its own.
      let marker = listMarker(of: block.lines)
      if let indent = openListIndent,
        attachContinuation(block, toListAt: indent, marker: marker, in: &result, linker: linker)
      {
        continue
      }
      for parsed in classify(block, marker: marker, linker: linker) {
        // Merge adjacent list blocks of the same style into one list.
        if case .list(let list) = parsed, case .list(var previous)? = result.last,
          previous.style == list.style
        {
          previous.items += list.items
          result[result.count - 1] = .list(previous)
        } else {
          result.append(parsed)
        }
      }
      openListIndent = if case .list? = result.last { marker?.indent } else { nil }
    }
    return result
  }

  /// A block indented past a list's marker and carrying no marker of its own is the
  /// previous item's second paragraph -- the shape a hanging list takes whenever an
  /// item runs to more than one paragraph (RFC 3712's Introduction, and a few
  /// thousand others).
  ///
  /// It arrives as its own block because a blank line separates it, and it is
  /// indented past the six columns `looksLikeProse` allows a paragraph, so it used
  /// to be preserved as artwork: the item lost its prose, the list was cut into one
  /// single-item list per item, and every reference in the continuation went
  /// unlinked, because artwork is never linkified.
  ///
  /// The indent is only excused here, where the list above it says what the
  /// continuation indent means. Every other test of prose still has to pass, so a
  /// genuine example block under an item is still artwork.
  private static func attachContinuation(
    _ block: RawBlock,
    toListAt markerIndent: Int,
    marker: ListMarker?,
    in result: inout [Block],
    linker: InlineLinker
  ) -> Bool {
    guard case .list(var list)? = result.last, var item = list.items.last else { return false }
    guard block.indent > markerIndent, marker == nil else { return false }
    // A list above a block says what its indent means; it says nothing about
    // whether the block is prose, and the deep indents under a list item are full
    // of algorithm steps (`c = OS2IP (C).`), grammar productions and tagged
    // values that pass every other test by being short and uniform. Measured, this
    // is also twenty times cheaper than the prose test and rejects most of what
    // reaches here, so it is asked first.
    guard readsLikeSentences(block.lines, share: (of: 1, in: 2)) else { return false }
    // The indent is the only test excused, and it is the only one that consulted
    // it. `RawBlock.indent` is the smallest indent in the block and the block is
    // uniform by the time this passes, so the cap could only ever be its own.
    guard looksLikeProse(block.lines, maxIndent: .max) else { return false }
    let inlines = linker.link(joinWrappedLines(block.lines))
    guard !inlines.isEmpty else { return false }
    item.blocks.append(.paragraph(Paragraph(inlines)))
    list.items[list.items.count - 1] = item
    result[result.count - 1] = .list(list)
    return true
  }

  /// The marker a block opens with: its style, and the column it sits in. Nil when
  /// the block opens with no marker at all.
  ///
  /// One probe for both facts, because `parseList` needs the style and continuation
  /// attachment needs the column, and two copies of "does this line open an item"
  /// drift: a third marker shape added to one of them would leave the other blind
  /// to it, and lists of that shape would quietly lose their second paragraphs.
  /// `parseBlocks` asks once per block and hands the answer down.
  private static func listMarker(of lines: [String]) -> ListMarker? {
    guard let first = lines.first else { return nil }
    // Both patterns want one of these in the first column that is not a space, and
    // this runs on every block: a character test rejects ordinary prose before
    // either regex starts.
    guard let opener = first.first(where: { $0 != " " }),
      opener == "o" || opener == "-" || opener == "*" || opener == "\u{2022}" || opener == "("
        || opener.isNumber || (opener.isLetter && opener.isLowercase)
    else { return nil }
    if let match = first.firstMatch(of: bulletPattern) {
      return (.bullet, match.indent.count)
    }
    if let match = first.firstMatch(of: numberedItemPattern) {
      let marker = String(match.marker)
      let format = marker.first == "(" ? "(%d)" : (marker.first?.isLetter == true ? "%c." : "%d.")
      return (.numbered(format: format, start: 1), match.indent.count)
    }
    return nil
  }

  private static func shouldJoinAcrossPage(_ first: RawBlock, _ second: RawBlock) -> Bool {
    guard looksLikeProse(first.lines), looksLikeProse(second.lines) else { return false }
    guard first.indent == second.indent else { return false }
    let lastLine = first.lines.last?.trimmingCharacters(in: .whitespaces) ?? ""
    let nextLine = second.lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
    if nextLine.first?.isLowercase == true { return true }
    if let last = lastLine.last, ".:!?".contains(last) { return false }
    return true
  }

  /// `maxIndent` is the deepest a paragraph may start and still read as prose.
  /// Six columns by default: body text sits at three or four, and anything set
  /// deeper than that with no list above it to explain the indent is an example.
  private static func looksLikeProse(_ lines: [String], maxIndent: Int = 6) -> Bool {
    // `thorough: false` stops at the first guard that refuses, exactly as the guards
    // used to when they were written as early returns. The verdict is identical — a
    // conjunction of absolute vetoes cannot change once one has fired — and it is
    // what this path costs that matters: measured over 300 documents, computing the
    // full diagnosis for every block of every document made parsing 1.67x slower.
    diagnose(lines, maxIndent: maxIndent, thorough: false).isProse
  }

  /// The prose test, reporting its working.
  ///
  /// `looksLikeProse` is this function and nothing else, so a report can never
  /// describe a decision other than the one actually taken. The guards are absolute
  /// and independent — any one of them rejects the block on its own — so the useful
  /// thing to record is not just *that* a block was refused but which guard refused
  /// it and by what margin.
  ///
  /// Unlike the predicate it backs, this evaluates every guard rather than returning
  /// at the first failure: a block refused on its indent still has an artwork count
  /// and a sentence ratio worth knowing.
  static func diagnose(_ lines: [String], maxIndent: Int = 6, thorough: Bool = true)
    -> ProseDiagnostics
  {
    var diagnosis = ProseDiagnostics()
    guard let first = lines.first else {
      diagnosis.rejections = [.noLines]
      return diagnosis
    }
    // Most pre-1990 RFCs indent the first line of a paragraph and set the rest at the
    // margin (RFC 722, 891, 904), so the block's indent comes from the second line.
    let indent = (lines.count > 1 ? lines[1] : first).leadingSpaceCount
    diagnosis.indent = indent
    diagnosis.firstLineIndent = first.leadingSpaceCount - indent

    if indent > maxIndent { diagnosis.rejections.append(.indentTooDeep) }
    if !(0...8).contains(diagnosis.firstLineIndent) {
      diagnosis.rejections.append(.firstLineIndentOutOfRange)
    }
    if !thorough, !diagnosis.rejections.isEmpty { return diagnosis }

    diagnosis.justification = justificationTells(lines, thorough: thorough)
    if thorough { diagnosis.sentenceRatio = sentenceRatio(lines) }

    let justified = diagnosis.justification.agreed
    var ragged = false
    var gapped = false
    for (offset, line) in lines.enumerated() {
      if offset > 0, line.leadingSpaceCount != indent {
        ragged = true
        if !thorough { break }
      }
      if thorough {
        diagnosis.artworkMatches +=
          line.trimmingCharacters(in: .whitespaces).matches(of: artworkPattern).count
      } else if containsArtwork(line) {
        diagnosis.artworkMatches = 1
        break
      }
      if !justified, hasInternalGap(line) {
        gapped = true
        if !thorough { break }
      }
    }
    if ragged { diagnosis.rejections.append(.raggedIndent) }
    if diagnosis.artworkMatches > 0 { diagnosis.rejections.append(.artworkPattern) }
    if gapped { diagnosis.rejections.append(.internalGap) }
    return diagnosis
  }

  /// The early RFCs typeset with justified text (757, 806, 841, 909, 1341) pad the gaps
  /// between words until every line reaches a common right margin. Those runs of spaces
  /// are what marks artwork everywhere else, so all of their prose was preformatted.
  ///
  /// Four tells have to agree, because a table, a definition list or a block of code
  /// satisfies any one of them on its own: every line but the last ends at the same
  /// margin, no gutter of blank columns runs through the block, the padding is spread
  /// over most of the lines rather than sitting in one column, and the words read like
  /// sentences rather than identifiers.
  /// `thorough: false` stops at the first tell that dissents. Only `agreed` is readable
  /// afterwards, which is all the prose test wants; the report asks for everything.
  private static func justificationTells(_ lines: [String], thorough: Bool = true)
    -> JustificationTells
  {
    var tells = JustificationTells()
    tells.enoughLines = lines.count >= 3
    guard tells.enoughLines else { return tells }
    let widths = lines.map { $0.reversed().drop(while: \.isWhitespace).count }
    if let margin = widths.first, let last = widths.last, margin >= 60 {
      tells.commonRightMargin = widths.dropLast().allSatisfy { $0 == margin } && last <= margin
    }
    guard thorough || tells.commonRightMargin else { return tells }
    tells.noColumnGutter = !hasColumnGutter(lines)
    guard thorough || tells.noColumnGutter else { return tells }
    let padded = lines.dropLast().count { internalGapCount($0) >= 2 }
    tells.paddingSpread = padded * 2 >= lines.count - 1
    guard thorough || tells.paddingSpread else { return tells }
    tells.readsLikeSentences = readsLikeSentences(lines)
    return tells
  }

  /// A run of two or more columns left blank by every line: the gutter of a two-column
  /// layout. Justified prose has its gaps in a different place on every line.
  private static func hasColumnGutter(_ lines: [String]) -> Bool {
    let rows = lines.map(Array.init)
    let start = rows.map { $0.prefix(while: \.isWhitespace).count }.min() ?? 0
    let end = rows.map { $0.reversed().drop(while: \.isWhitespace).count }.min() ?? 0
    guard start < end else { return false }
    var run = 0
    for column in start..<end {
      guard rows.allSatisfy({ column >= $0.count || $0[column].isWhitespace }) else {
        run = 0
        continue
      }
      run += 1
      if run >= 2 { return true }
    }
    return false
  }

  /// Runs of two or more spaces sitting between two non-space characters.
  private static func internalGapCount(_ line: String) -> Int {
    var count = 0
    var run = 0
    var seenText = false
    for character in line {
      if character.isWhitespace {
        if seenText { run += 1 }
      } else {
        if run >= 2 { count += 1 }
        run = 0
        seenText = true
      }
    }
    return count
  }

  /// Mostly ordinary lower-case words, which a listing of identifiers, addresses or
  /// numbers does not have however neatly its columns happen to line up.
  ///
  /// `share` is how much of the block has to be ordinary words, as a fraction.
  /// Three fifths for justified prose, where the question is whether a block that
  /// already lines up at both margins is text or a table. A half for a list
  /// item's continuation, where the answer has to hold for acronym-heavy prose:
  /// measured over 18,832 continuation blocks in the corpus, everything below a
  /// half is ABNF (`reply = nickname [ "*" ] "=" ...`), pseudocode (`z =
  /// RandomInteger (0, n-1)`) or a stray page number, and everything above it
  /// reads as sentences. RFC 3712's own paragraph sits at 0.56, held down by
  /// `UTF-8`, `IRI` and `[W3C-IRI]`, which is why three fifths was too strict.
  private static func readsLikeSentences(
    _ lines: [String], share: (of: Int, in: Int) = (of: 3, in: 5)
  ) -> Bool {
    let counted = sentenceWords(lines)
    guard counted.total > 0 else { return false }
    // Kept as an exact integer comparison rather than a threshold on `sentenceRatio`:
    // the two agree everywhere, but only this one is free of rounding at the boundary.
    return counted.ordinary * share.in >= counted.total * share.of
  }

  /// The same quantity `readsLikeSentences` tests, reported rather than judged.
  private static func sentenceRatio(_ lines: [String]) -> Double {
    let counted = sentenceWords(lines)
    guard counted.total > 0 else { return 0 }
    return Double(counted.ordinary) / Double(counted.total)
  }

  /// Words that read as ordinary lower-case prose, against words in total.
  private static func sentenceWords(_ lines: [String]) -> (ordinary: Int, total: Int) {
    let words = lines.flatMap { $0.split(separator: " ") }
    let ordinary = words.count { word in
      guard word.first?.isLowercase == true else { return false }
      return word.allSatisfy { $0.isLetter || "'-.,;:)".contains($0) }
    }
    return (ordinary, words.count)
  }

  private static func classify(_ block: RawBlock, marker: ListMarker?, linker: InlineLinker)
    -> [Block]
  {
    let lines = block.lines
    guard !lines.isEmpty else { return [] }

    // Lists: the first line carries a marker and every further item shares its indent.
    if let list = parseList(lines, marker: marker, linker: linker) {
      return [.list(list)]
    }

    if looksLikeProse(lines) {
      let inlines = linker.link(Self.joinWrappedLines(lines))
      return inlines.isEmpty ? [] : [.paragraph(Paragraph(inlines))]
    }

    // Anything else is preserved verbatim, minus the common indentation.
    let indent = block.indent
    let text = lines.map { line in
      String(line.dropFirst(min(indent, line.leadingSpaceCount)))
    }.joined(separator: "\n")
    // "Figure 3: Title" captions directly under artwork are common; keep them attached.
    return [.preformatted(Preformatted(kind: .artwork, text: text))]
  }

  /// Joins wrapped lines with spaces, except after a trailing hyphen, which in the
  /// RFC text format always marks a compound word broken at the hyphen (`point-` / `to-point`).
  private static func joinWrappedLines(_ lines: [String]) -> String {
    var result = ""
    for line in lines {
      let trimmed = line.collapsingWhitespace()
      if result.isEmpty {
        result = trimmed
      } else if result.hasSuffix("-"), trimmed.first?.isLowercase == true {
        result += trimmed
      } else {
        result += " " + trimmed
      }
    }
    return result
  }

  private static func parseList(_ lines: [String], marker: ListMarker?, linker: InlineLinker)
    -> ListBlock?
  {
    guard let (style, items) = listItems(lines, marker: marker) else { return nil }
    let listItems = items.map { itemLines -> ListItem in
      var text = Self.joinWrappedLines(itemLines)
      if let match = text.firstMatch(of: bulletPattern) {
        text = String(match.text)
      } else if let match = text.firstMatch(of: numberedItemPattern) {
        text = String(match.text)
      }
      return ListItem(blocks: [.paragraph(Paragraph(linker.link(text)))])
    }
    return ListBlock(style: style, items: listItems)
  }

  /// Whether these lines are a list, and how they divide into items — the shape
  /// decision alone, with no rendering and so no linker.
  ///
  /// Split out because `classify` offers every block to the list parser before it asks
  /// the prose test, and the diagnostics have to know which branch a block took. Asking
  /// this function is asking the same question `classify` asks; re-deriving it from the
  /// line patterns would be a second copy free to drift.
  private static func listItems(_ lines: [String], marker: ListMarker?) -> (
    style: ListBlock.Style, items: [[String]]
  )? {
    guard let (style, itemIndent) = marker else { return nil }

    var items: [[String]] = []
    for line in lines {
      let isItemStart: Bool
      if line.leadingSpaceCount == itemIndent {
        switch style {
        case .bullet: isItemStart = line.contains(bulletPattern)
        default: isItemStart = line.contains(numberedItemPattern)
        }
      } else {
        isItemStart = false
      }
      if isItemStart {
        items.append([line])
      } else if !items.isEmpty, line.leadingSpaceCount > itemIndent {
        items[items.count - 1].append(line)
      } else {
        return nil
      }
    }
    guard !items.isEmpty else { return nil }
    return (style, items)
  }

  // MARK: References

  /// The line that opens a reference entry, and the anchor the prose cites it by.
  ///
  /// The anchor may hold spaces: the RFC Editor sets `[RFC 2119]` as readily as
  /// `[RFC2119]`, and the older documents cite by author and year
  /// (`[Cheswick and Bellovin, 1994]`). A class that admitted no whitespace started
  /// no entry on those lines and swallowed them as the previous entry's
  /// continuation -- 782 entries across 205 documents, and RFC 2290 and RFC 2535
  /// produced no bibliography at all.
  ///
  /// Forty characters, because this runs over every line of a references section
  /// and not every bracket in one opens an entry. Measured over the corpus, the
  /// longest real anchor is 38 (`[Ermann, Willians, and Gutierrez, 1990]`), while
  /// the brackets that are not anchors are sentences: `[54 additional burst
  /// segments deleted for brevity]`, `[Supersedes FIPS PUB 180 dated 11 May
  /// 1993.]`. Leading whitespace is excluded for the same reason -- `[ ]` and
  /// `[ a:defaultValue = "" ]` are schema fragments, not citations.

  nonisolated(unsafe) private static let referenceStartPattern =
    #/^\s*\[(?<anchor>[^\]\s][^\]]{0,39})\]\s*(?<text>.*)$/#
  /// A page footer `depaginate` could not see. `footerPattern` is anchored to the
  /// end of the line, and the earliest RFCs set the footer the other way round --
  /// `[Page 0]` at the left margin with the author out at the right (RFC 753, 759,
  /// 767, 780) -- so those lines reach the references section intact and are the
  /// one bracket of an anchor's shape that never names a reference. Four documents,
  /// and without this each gains a `<reference anchor="Page 52">` whose title is
  /// whatever the footer's author column said.
  nonisolated(unsafe) private static let pageFooterAnchorPattern = #/Page\s+\d+/#

  private static func parseReferences(_ rawBlocks: [RawBlock]) -> [Reference] {
    var references: [Reference] = []
    var currentAnchor: String?
    var currentLines: [String] = []

    func flush() {
      guard let anchor = currentAnchor else { return }
      let text = currentLines.joined(separator: " ").collapsingWhitespace()
      references.append(reference(anchor: anchor, text: text))
      currentAnchor = nil
      currentLines = []
    }

    for block in rawBlocks {
      for line in block.lines {
        if let match = line.firstMatch(of: referenceStartPattern),
          case let anchor = String(match.anchor).trimmingCharacters(in: .whitespaces),
          anchor.wholeMatch(of: pageFooterAnchorPattern) == nil
        {
          flush()
          currentAnchor = anchor
          currentLines = match.text.isEmpty ? [] : [String(match.text)]
        } else if currentAnchor != nil {
          currentLines.append(line.trimmingCharacters(in: .whitespaces))
        }
      }
    }
    flush()
    return references
  }

  private static func reference(anchor label: String, text: String) -> Reference {
    var seriesInfo: [(name: String, value: String)] = []
    // `RFC 1495` first, and the older half of the series' `RFC-854`, `RFC- 826` and
    // `Request for Comments 796`, `Request For Comments 990` and `RFC #189` only when an
    // entry has none: once a bare `[1]` stopped naming RFC 1, an entry spelled so named
    // nothing at all. Not in one pattern, though, because a title names RFCs too -- RFC
    // 1494's `[1]` is "Mapping between X.400 and RFC-822 Message Bodies", RFC 1495 -- and
    // the first match would be the title's. `RFCs 1021-1024` is a range, and names none.
    if let match = text.firstMatch(of: #/\bRFC\s?(\d+)/#)
      ?? text.firstMatch(of: #/\b(?:RFC|(?i:Request for Comments):?)[\s\-#]*(\d+)/#)
    {
      seriesInfo.append((name: "RFC", value: String(match.1)))
    } else if let id = DocumentID(label: label) {
      seriesInfo.append((name: id.series.rawValue, value: String(id.number)))
    }
    if let match = text.firstMatch(of: #/\bBCP\s?(\d+)/#) {
      seriesInfo.append((name: "BCP", value: String(match.1)))
    }
    if let match = text.firstMatch(of: #/\bSTD\s?(\d+)/#) {
      seriesInfo.append((name: "STD", value: String(match.1)))
    }
    let title = text.firstMatch(of: #/"([^"]+)"/#).map { String($0.1) } ?? ""
    let date = text.firstMatch(of: monthYearPattern).map {
      PublicationDate(year: Int($0.2) ?? 0, month: PublicationDate.month(from: String($0.1)))
    }
    let url = text.firstMatch(of: #/https?:\/\/[^\s>,]+/#).flatMap {
      URL(string: String($0.output).trimmingTrailingPunctuation())
    }
    var reference = Reference(
      anchor: label, title: title, date: date, seriesInfo: seriesInfo, url: url, rawText: text)
    reference.anchor = entryAnchor(label: label, documentID: reference.documentID)
    return reference
  }

  /// What an entry is declared under, which the XML requires to be a name (`NCName`):
  /// no leading digit, no spaces. `[1]`, `[RFC 2119]` and `[Cheswick and Bellovin,
  /// 1994]` are not, and gave 2,361 documents an anchor the schema refuses (#65). A
  /// label that is a name stays the anchor, as `MIP-OPTIM` does in the published
  /// series; one that is not becomes the document it cites -- the series writes
  /// `anchor="RFC0791" derivedAnchor="1"` -- or else `ref-` and the label spelled as a
  /// name. The label itself stays `displayAnchor`, which is what the entry reads as.
  static func entryAnchor(label: String, documentID: DocumentID?) -> String {
    func isNameCharacter(_ character: Character) -> Bool {
      character.isLetter || ("0"..."9").contains(character) || "-._".contains(character)
    }
    if let first = label.first, first.isLetter || first == "_", label.allSatisfy(isNameCharacter) {
      return label
    }
    if let documentID { return documentID.description }
    var name = ""
    for character in label {
      if isNameCharacter(character) {
        name.append(character)
      } else if !name.isEmpty, !name.hasSuffix("-") {
        name.append("-")
      }
    }
    while name.hasSuffix("-") { name.removeLast() }
    // `[*]` and `[**]` mark notes (RFC 2130, RFC 906) and spell no name at all; they
    // were `ref-`, and a second one `ref--2`.
    return "ref-\(name.isEmpty ? "note" : name)"
  }
}

// MARK: - Inline linking

/// Turns plain prose into inlines with cross references and links.
struct InlineLinker: Sendable {
  var sectionNumbers: Set<String>
  var referenceTargets: [String: CrossReference.Target]

  private struct Candidate {
    var range: Range<String.Index>
    var inline: Inline
  }

  /// A pattern and the literal it cannot match without, defined together: `link`
  /// reaches a pattern only through `matches(in:given:)`, so no pass can run under
  /// another pattern's gate.
  struct Gated<Output> {
    let regex: Regex<Output>
    let gate: KeyPath<Literals, Bool>

    func matches(in text: String, given literals: Literals) -> [Regex<Output>.Match] {
      literals[keyPath: gate] ? text.matches(of: regex) : []
    }
  }

  nonisolated(unsafe) static let sectionOfRFCPattern = Gated(
    regex: #/\bSection\s+(?<section>\d+(?:\.\d+)*)\s+of\s+\[?RFC\s?(?<number>\d+)\]?/#,
    gate: \.sectionOfRFC
  )
  /// A bracket holding a single citation tag. The tag may carry internal spaces,
  /// because roughly a seventh of the corpus sets its citations as `[RFC 2211]`
  /// rather than `[RFC2211]`; a class that admitted no space left those matching
  /// neither this pattern nor the bare one. Anything that is not a document once
  /// parsed -- `[Page 3]`, `[see RFC 2119 and others]` -- is discarded below, and
  /// the bare pattern picks up whatever RFC sits inside it.
  nonisolated(unsafe) static let bracketPattern = Gated(
    regex: #/\[(?<anchor>[A-Za-z0-9][A-Za-z0-9.\-_ ]*)\]/#, gate: \.bracket)
  /// Deliberately blind to a preceding `[`. A multi-anchor citation
  /// (`[RFC2582,FF96,Hoe96]`) is not a bracket this parser may eat -- the tags
  /// beside the RFC are the author's -- so its RFC is linked where it stands and
  /// the brackets stay as text. Where the bracket *is* ours, `bracketPattern`
  /// starts a character earlier and wins the overlap outright.
  ///
  /// The separator may be a hyphen: the older half of the series writes `RFC-1156`
  /// as its ordinary prose spelling, and `DocumentID` has always read the hyphen as
  /// a separator. Prose held 2,223 of those against 1,640 plain ones, so it was the
  /// larger of the two shapes going unlinked.
  nonisolated(unsafe) static let bareRFCPattern = Gated(
    regex: #/\bRFC[\s\-]?(?<number>\d+)\b/#, gate: \.rfc)
  /// One list, written once: `RFCs 734, 736, 747 and 749`. Each number is its own
  /// reference but only the first carries the word, so the numbers are linked where
  /// they stand and the sentence is left to read as it was set.
  nonisolated(unsafe) static let rfcListPattern = Gated(
    regex: #/\bRFCs\s+\d{1,5}(?:\s*,\s*(?:and\s+)?\d{1,5}|\s+and\s+\d{1,5})*/#, gate: \.rfcs)
  nonisolated(unsafe) private static let listNumberPattern = #/\d{1,5}/#
  nonisolated(unsafe) static let sectionPattern = Gated(
    regex: #/\bSections?\s+(?<section>\d+(?:\.\d+)*)\b/#, gate: \.section)
  nonisolated(unsafe) static let urlPattern = Gated(regex: #/https?:\/\/[^\s<>"]+/#, gate: \.http)

  /// What a matched mention reads as: nil when the document spelled the reference
  /// the way the series spells itself, so the label composes back identically, and
  /// the matched words verbatim when it did not. `[RFC2119]` and `RFC 1156` are the
  /// series' own spelling; `[QUIC-TRANSPORT]` is this document's name for the
  /// reference and the hyphen in `RFC-1156` is the author's, and neither is ours to
  /// take out.
  private static func label(_ matched: String, canonicalFor id: DocumentID?) -> String? {
    let canonical = id.map { CrossReference.isCanonicalTag(matched, for: $0) } ?? false
    return canonical ? nil : CrossReference.nonBreakingLabel(matched)
  }

  /// Which of the literals the patterns open with a fragment holds, byte for byte.
  /// Each is necessary for its pattern to match -- the patterns are case-sensitive,
  /// and a grapheme the regex reads as `C` is the byte `C` -- so a pattern whose
  /// literal is absent is skipped without changing what `link` returns.
  /// A pattern above that stops needing its literal -- a `(?i)`, a lowercase
  /// `section`, a `www.` URL -- has to change this too, or its matches are dropped
  /// without a word; `theLiteralGateSkipsNoMatch` is the guard.
  struct Literals {
    var bracket = false, rfc = false, rfcs = false, section = false, http = false
    var any: Bool { bracket || rfc || section || http }
    var sectionOfRFC: Bool { rfc && section }

    init(in text: String) {
      var text = text
      text.withUTF8 { bytes in
        for index in bytes.indices {
          switch Unicode.Scalar(bytes[index]) {
          case "[": bracket = true
          case "R" where bytes.holds("RFC", at: index):
            rfc = true
            if bytes.holds("RFCs", at: index) { rfcs = true }
          case "S" where bytes.holds("Section", at: index): section = true
          case "h" where bytes.holds("http", at: index): http = true
          default: continue
          }
          // `rfcs` implies `rfc`: nothing later in the fragment can change the answer.
          if bracket, rfcs, section, http { return }
        }
      }
    }
  }

  func link(_ text: String) -> [Inline] {
    // Every pattern below needs a literal to match at all -- `[`, `RFC`, `RFCs`,
    // `Section`, `http` -- and a pass over the UTF-8 does not start the regex
    // engine. Most fragments carry no citation, and the XML parser runs this over
    // every text node of every document. The pass used to test first bytes only,
    // and one of them was `h`, which nearly every sentence holds: all six patterns
    // ran on nearly every fragment.
    guard !text.isEmpty else { return [] }
    let literals = Literals(in: text)
    guard literals.any else { return [.text(text)] }

    var candidates: [Candidate] = []

    for match in Self.sectionOfRFCPattern.matches(in: text, given: literals) {
      guard let number = Int(match.number) else { continue }
      candidates.append(
        Candidate(
          range: match.range,
          inline: .crossReference(
            // The matched prose *is* the label we compose, so it is left to be
            // composed rather than copied: "Section 4.2 of [RFC9110]" reads back
            // out the same, and the reader is free to draw it as one chip.
            CrossReference(
              target: .document(.rfc(number), section: String(match.section)), sectionFormat: .of)
          )))
    }
    for match in Self.bracketPattern.matches(in: text, given: literals) {
      let anchor = String(match.anchor)
      // Parsed once: the label needs it on every path, so the hit path's is free.
      let parsed = DocumentID(parsing: anchor)
      let target: CrossReference.Target
      if let known = referenceTargets[anchor] {
        target = known
      } else if let id = parsed,
        id.series != .rfc || anchor.prefix(3).caseInsensitiveCompare("RFC") == .orderedSame
      {
        target = .document(id, section: nil)
      } else {
        continue
      }
      candidates.append(
        Candidate(
          range: match.range,
          inline: .crossReference(
            CrossReference(
              target: target, text: Self.label(String(text[match.range]), canonicalFor: parsed))
          )))
    }
    for match in Self.bareRFCPattern.matches(in: text, given: literals) {
      guard let number = Int(match.number) else { continue }
      candidates.append(
        Candidate(
          range: match.range,
          inline: .crossReference(
            CrossReference(
              target: .document(.rfc(number), section: nil),
              text: Self.label(String(text[match.range]), canonicalFor: .rfc(number)))
          )))
    }
    // Only the plural opens a list, and this is the dearest of the six patterns.
    for list in Self.rfcListPattern.matches(in: text, given: literals) {
      for match in text[list.range].matches(of: Self.listNumberPattern) {
        guard let number = Int(match.output) else { continue }
        candidates.append(
          Candidate(
            range: match.range,
            inline: .crossReference(
              CrossReference(
                target: .document(.rfc(number), section: nil), text: String(match.output))
            )))
      }
    }
    // Skipped outright when there are no section numbers to match, which is how
    // the XML parser runs: `<xref>` is how authored XML points at a section, so
    // every match of this pass would be filtered out again.
    if !sectionNumbers.isEmpty {
      for match in Self.sectionPattern.matches(in: text, given: literals)
      where sectionNumbers.contains(String(match.section)) {
        candidates.append(
          Candidate(
            range: match.range,
            inline: .crossReference(
              CrossReference(
                target: .anchor("section-\(match.section)"),
                text: CrossReference.nonBreakingLabel(String(text[match.range])))
            )))
      }
    }
    for match in Self.urlPattern.matches(in: text, given: literals) {
      let raw = String(match.output).trimmingTrailingPunctuation()
      guard let url = URL(string: raw) else { continue }
      let end = text.index(match.range.lowerBound, offsetBy: raw.count)
      candidates.append(
        Candidate(range: match.range.lowerBound..<end, inline: .link(url, [.text(raw)])))
    }

    // Earliest start wins; on ties the longer match wins. Overlaps are dropped.
    candidates.sort {
      if $0.range.lowerBound != $1.range.lowerBound {
        return $0.range.lowerBound < $1.range.lowerBound
      }
      return $0.range.upperBound > $1.range.upperBound
    }
    var inlines: [Inline] = []
    var cursor = text.startIndex
    for candidate in candidates where candidate.range.lowerBound >= cursor {
      if candidate.range.lowerBound > cursor {
        inlines.append(.text(String(text[cursor..<candidate.range.lowerBound])))
      }
      inlines.append(candidate.inline)
      cursor = candidate.range.upperBound
    }
    if cursor < text.endIndex {
      inlines.append(.text(String(text[cursor...])))
    }
    return inlines
  }
}

// MARK: - String helpers

extension UnsafeBufferPointer<UInt8> {
  /// Whether `literal`'s bytes start at `index`: a substring test that does not start
  /// the regex engine or break graphemes, for literals the caller knows are ASCII.
  fileprivate func holds(_ literal: StaticString, at index: Int) -> Bool {
    let count = literal.utf8CodeUnitCount
    guard index >= 0, index + count <= self.count else { return false }
    return (0..<count).allSatisfy { self[index + $0] == literal.utf8Start[$0] }
  }
}

extension String {
  var isBlank: Bool { allSatisfy(\.isWhitespace) }

  /// Whitespace rather than a space: `depaginate` expands tabs before any line reaches
  /// the heuristics (RFC 1142's contents listing is tab-indented, and every entry
  /// otherwise matched the numbered-heading pattern), and this stays general so a
  /// caller that has not been through it cannot read a tab as column zero.
  var startsAtColumnZero: Bool { first?.isWhitespace == false }

  var leadingSpaceCount: Int {
    var count = 0
    for character in self {
      if character == " " { count += 1 } else { break }
    }
    return count
  }

  /// Tabs replaced by spaces to the next multiple-of-eight column, which is what the
  /// line printers and terminals these documents were typed for did with them.
  func expandingTabs() -> String {
    // Over UTF-8: this runs on every line of every document, and `contains` over
    // Characters is an order of magnitude dearer for a test that almost always fails.
    guard utf8.contains(9) else { return self }
    var result = ""
    result.reserveCapacity(count + 8)
    var column = 0
    for character in self {
      if character == "\t" {
        let width = 8 - column % 8
        result.append(contentsOf: repeatElement(" ", count: width))
        column += width
      } else {
        result.append(character)
        column += 1
      }
    }
    return result
  }

  func trimmingTrailingWhitespace() -> String {
    var result = self
    while let last = result.last, last.isWhitespace { result.removeLast() }
    return result
  }

  func trimmingTrailingDots() -> String {
    var result = trimmingTrailingWhitespace()
    // Table-of-contents style "Title ....... 7" leaders.
    if let match = result.firstMatch(of: #/\s*\.{3,}\s*\d*$/#) {
      result.removeSubrange(match.range)
    }
    return result
  }

  func trimmingTrailingPunctuation() -> String {
    var result = self
    while let last = result.last, ".,;:)]>\"'".contains(last) { result.removeLast() }
    return result
  }

  func slugified() -> String {
    var result = ""
    var lastWasDash = false
    for scalar in lowercased().unicodeScalars {
      if scalar.properties.isAlphabetic || (scalar.value >= 48 && scalar.value <= 57) {
        result.unicodeScalars.append(scalar)
        lastWasDash = false
      } else if !lastWasDash, !result.isEmpty {
        result.append("-")
        lastWasDash = true
      }
    }
    if result.hasSuffix("-") { result.removeLast() }
    return result
  }
}
