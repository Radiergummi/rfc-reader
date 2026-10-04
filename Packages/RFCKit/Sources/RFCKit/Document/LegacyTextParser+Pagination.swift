import Foundation

extension LegacyTextParser {
  enum Line: Sendable {
    case text(String)
    case pageBreak
    /// The first sighting of a section's running header: page furniture that may be
    /// the only thing saying where its section starts (RFC 770's `References`), or a
    /// copy of a heading the document sets itself (RFC 793's `Philosophy`). Which one
    /// is a structure decision, made by what the document heads nearby once its
    /// headings can be told (#291); see `LegacyTextParser.headsNearby`. Until then it
    /// reads as the line of text it is. The sighting is where `paginated` put it,
    /// which names it through double spacing collapsed and back.
    case sectionHeader(String, sighting: Int)

    /// The line's text, or nil for a page break.
    var string: String? {
      switch self {
      case .text(let string), .sectionHeader(let string, _): string
      case .pageBreak: nil
      }
    }

    var isSectionHeader: Bool {
      if case .sectionHeader = self { true } else { false }
    }
  }

  private static let footerPattern = Pattern(#/\[Page (?<number>[0-9ivx]+)\]\s*$/#)

  /// Whether a line ends in a page footer: `[Page 12]`, or `[Page ii]` on a front
  /// section numbered in roman numerals (#549).
  private static func endsInFooter(_ line: String) -> Bool {
    guard let match = line.firstMatch(of: footerPattern) else { return false }
    return match.number.allSatisfy { $0.isASCII && $0.isNumber } || isRomanPageNumber(match.number)
  }

  private static let runningHeaderPattern = Pattern(
    #/^(RFC|Request for Comments:?)\s*\d+\b.*\b\d{4}\s*$/#)

  /// Removes form feeds, running headers and page footers, keeping everything else verbatim.
  ///
  /// A section running header's first sighting goes where `parse` drops it, the
  /// document heading that section itself, and stays where it is the only thing
  /// saying where the section starts.
  public static func stripPagination(_ text: String) -> String {
    var output: [String] = []
    var pendingBlank = 0
    var breakOccurred = false
    let lines = depaginate(text)
    let headed = headedSectionHeaders(in: lines)
    for line in lines {
      switch line {
      case .sectionHeader(_, let sighting) where headed.contains(sighting):
        continue
      case .pageBreak:
        breakOccurred = true
      case .text(let string), .sectionHeader(let string, _):
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
  ///
  /// A section running header's first sighting is among them where `parse` drops it,
  /// the document heading that section itself (#291).
  public static func recurringFurniture(in text: String) -> [String] {
    let lines = paginated(text)
    let furniture = recurringFurniture(lines)
    let headed = headedSectionHeaders(in: depaginate(lines, furniture: furniture))
    return furniture.dropped.union(headed).sorted().compactMap { lines[$0].string }
  }

  static func depaginate(_ text: String) -> [Line] {
    let lines = paginated(text)
    return depaginate(lines, furniture: recurringFurniture(lines))
  }

  private static func depaginate(
    _ lines: [Line], furniture: (dropped: Set<Int>, sectionHeaders: Set<Int>)
  ) -> [Line] {
    guard !furniture.dropped.isEmpty || !furniture.sectionHeaders.isEmpty else { return lines }
    return lines.enumerated().compactMap { offset, line in
      if furniture.dropped.contains(offset) { return nil }
      if furniture.sectionHeaders.contains(offset), let string = line.string {
        return .sectionHeader(string, sighting: offset)
      }
      return line
    }
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

      if firstContentSeen, endsInFooter(trimmed) {
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
  typealias ListMarker = (style: ListBlock.Style, indent: Int)

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
  /// where its section starts, so it is not dropped here but returned apart, and
  /// `Prelude.headedSectionHeaders` drops it where the document heads that section
  /// itself nearby (#291).
  private static func recurringFurniture(_ lines: [Line]) -> (
    dropped: Set<Int>, sectionHeaders: Set<Int>
  ) {
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
    guard later.count >= 3 else { return ([], []) }

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
    guard !recurring.isEmpty else { return ([], []) }
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
    var sectionHeaders: Set<Int> = []
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
      furniture.formUnion(found.lines.dropFirst())
      if let first = found.lines.first { sectionHeaders.insert(first) }
    }
    return (furniture, sectionHeaders)
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
  static func headingText<S: StringProtocol>(_ string: S) -> String {
    string.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
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
}
