import Foundation

/// Recovers document structure from the classic 72-column plain-text RFC format
/// used for everything before RFC 8650 (and still published for every RFC).
///
/// This is deliberately heuristic. It removes page furniture, detects headings,
/// distinguishes prose from ASCII art, re-joins paragraphs split across pages and
/// links `[RFC2119]`, `RFC 2119`, `Section 4.2` and URLs. The original text is always
/// kept available through `stripPagination(_:)` for an "as published" view.
public enum LegacyTextParser {
  public static func parse(_ data: Data) -> RFCDocument {
    parse(text(decoding: data))
  }

  /// The text of a legacy RFC file: UTF-8, or Windows-1252 for the 34 older documents
  /// that are not (accented names, curly quotes), and lossy UTF-8 for bytes that are
  /// neither. Every reader of the format decodes through here, so the parser, the
  /// original-text view and corpus-build agree on what a document says.
  public static func text(decoding bytes: Data) -> String {
    String(data: bytes, encoding: .utf8)
      ?? String(data: bytes, encoding: .windowsCP1252)
      ?? String(decoding: bytes, as: UTF8.self)
  }

  // MARK: - Parsing

  struct RawBlock {
    var lines: [String]
    var followedByPageBreak = false

    var indent: Int { lines.map(\.leadingSpaceCount).min() ?? 0 }
    var firstLine: String { lines.first ?? "" }
  }

  struct HeadingInfo {
    var number: String?
    var title: String
    var isAppendix: Bool
    var anchor: String
  }

  struct RawSection {
    var heading: HeadingInfo?
    var blocks: [RawBlock] = []
    /// The first line that took a heading's place but was refused as an unnumbered one,
    /// by its block and its place in that block: where omitted boilerplate ends, as it
    /// did when that line was a heading.
    var refusedHeadingLine: (block: Int, line: Int)?
  }

  static let numberedHeadingPattern = Pattern(
    #/^(?<number>\d+(?:\.\d+)*)(?<separator>[.:)])?\s+(?<title>\S.*)$/#)
  /// An appendix heading that names itself one (#201): `Appendix` or `Annex` in any case
  /// after its capital, then its number -- a letter, a Roman or an Arabic numeral, with
  /// any subsections -- and the title, set off by a full stop, a colon, dashes, or by
  /// spaces alone where it does not start in lower case, or no title at all:
  /// `Appendix A. Title`, `APPENDIX 1 - TITLE`, `Annex B (informative): Title`,
  /// `Appendix II.  Title`, `Appendix A--Title`, `Appendix A:`. A full stop or colon has
  /// a space or the line's end after it, so `Appendix A.12).` and a contents entry's
  /// `Appendix A.......35` are not one, and without a separator a lower-case word is
  /// prose, `Appendix A describes`. `Appendix IANA` has no number, and `Appendix: Title`
  /// none either: those stay unnumbered headings.
  private static let namedAppendixHeadingPattern = Pattern(
    #/^A(?i:ppendix|nnex)\s+(?<number>(?:[A-Z]|[IVX]+|\d+)(?:\.\d+)*)(?:\s*[.:](?=\s|$)|\s*-+|(?=\s+[^\s\p{Ll}])|$)\s*(?<title>.*)$/#
  )
  /// An appendix heading by its letter alone, `A.1. Title` or `B Title`, with a capital
  /// to start its title.
  private static let letteredAppendixHeadingPattern = Pattern(
    #/^(?<number>[A-Z](?:\.\d+)*)\.?\s+(?<title>[A-Z].*)$/#)
  /// A lettered subsection set off like a heading, by a full stop and a space or by two
  /// spaces, `B.1.2.  title` or `C.4  title`, whatever its title starts with: RFC 8011's
  /// status codes and RFC 1094's XDR types are in lower case. Not a number and a
  /// single space, which is a reference in prose (`A.2 for more`) or an ITU name
  /// (`X.25 switch`).
  private static let appendixSubsectionHeadingPattern = Pattern(
    #/^(?<number>[A-Z](?:\.\d+)+)(?:\.\s+|\s{2,})(?<title>\S.*)$/#)

  /// The number and title of an appendix heading, in any shape the parser reads one:
  /// named (`namedAppendixHeadingPattern`), by its letter, or as a lettered subsection.
  /// Nil for anything else. Internal, so the shapes can be pinned on hand-written
  /// lines rather than through a whole document.
  static func appendixHeading(in line: String) -> (number: String, title: String)? {
    if let match = line.firstMatch(of: namedAppendixHeadingPattern) {
      return (String(match.number), String(match.title))
    }
    if let match = line.firstMatch(of: letteredAppendixHeadingPattern) {
      return (String(match.number), String(match.title))
    }
    if let match = line.firstMatch(of: appendixSubsectionHeadingPattern) {
      return (String(match.number), String(match.title))
    }
    return nil
  }

  /// Diagnoses every block of a document without building one: what the prose test
  /// decided about each, and why.
  ///
  /// Shares `rawSections` with `parse`, so the blocks reported here are exactly the
  /// blocks the parser classifies — not a re-segmentation that might disagree. `title`
  /// is the index's title, as `parse` takes it: the lead-in loses what repeats the
  /// title, so a report given a different one diagnoses blocks the parser dropped.
  public static func proseDiagnostics(for text: String, title: String? = nil)
    -> [BlockDiagnostics]
  {
    let prepared = prepared(text, title: title)
    var locator = SourceLocator(text)
    return prepared.sections.flatMap { section in
      let anchor = section.heading?.anchor ?? ""
      return section.blocks.map { block in
        BlockDiagnostics(
          section: anchor,
          firstLine: String(block.firstLine.trimmingCharacters(in: .whitespaces).prefix(80)),
          lineCount: block.lines.count,
          // A catalog is a list too, offered the block before the prose test.
          claimedByList: listItems(block.lines, marker: listMarker(of: block.lines)) != nil
            || catalogEntries(block.lines) != nil,
          diagnosis: diagnose(block.lines, maxIndent: prepared.proseIndent),
          sourceLines: locator.locate(block.lines)
        )
      }
    }
  }

  /// Finds blocks in the source they came from, in document order.
  ///
  /// A block's lines are source lines, depaginated but otherwise as given: control
  /// characters removed, tabs expanded, trailing space trimmed, which is how each source
  /// line is read here too. Lines are numbered as the text splits at its newlines, before
  /// anything is removed, because that is how a reader of the source counts them: an
  /// overstrike can remove a newline, and numbering after it would put every later block
  /// a line early. Each block starts at the next source line equal to its first, and its
  /// other lines follow in order, past at most a page break's furniture between two of
  /// them. Found once per diagnosis, rather than carried through depagination and
  /// segmentation, which are the parser's hot path.
  private struct SourceLocator {
    /// The most lines a page break puts between two lines of a block: the edge lines
    /// `recurringFurniture` drops at the foot and the head of a page, up to four each,
    /// the footer, the form feed, the running header and the blanks around them.
    private static let furnitureSpan = 24

    private let lines: [String]
    private var cursor = 0

    init(_ text: String) {
      lines = text.replacingOccurrences(of: "\r\n", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
          removingControlCharacters(String(line))
            .replacingOccurrences(of: "\u{0C}", with: "")
            .expandingTabs()
            .trimmingTrailingWhitespace()
        }
    }

    /// The 1-based source lines of `block`, or nil when one of its lines is not where
    /// it should be. Nothing is guessed: a block not found leaves the cursor where it
    /// was, so the blocks after it are still found.
    mutating func locate(_ block: [String]) -> ClosedRange<Int>? {
      guard let first = block.first,
        let start = lines[cursor...].firstIndex(of: first)
      else { return nil }
      var end = start
      for line in block.dropFirst() {
        let window = lines[(end + 1)..<min(end + 1 + Self.furnitureSpan, lines.count)]
        guard let next = window.firstIndex(of: line) else { return nil }
        end = next
      }
      cursor = end + 1
      return (start + 1)...(end + 1)
    }
  }

  /// Everything between raw text and blocks: depagination, front matter, segmentation.
  ///
  /// Both entry points go through here so neither can normalize the text differently
  /// from the other. Extracting only `rawSections` left this prelude written twice,
  /// which is the same drift one level up.
  static func prepared(_ text: String, title: String? = nil) -> Prepared {
    let prelude = Prelude(depaginate(text))
    var header = parseFrontMatter(prelude.front)
    var sections = rawSections(of: prelude.omittingHeadedSectionHeaders)
    if let title, !title.isEmpty {
      // The title page is the front matter's runs and the lead-in's blocks up to the
      // one that opens the body, which is where a title set over several runs leaves
      // the rest. Up to and including it, because the rest can pass for a paragraph:
      // RFC 806 sets it in two lines of capitals.
      var titlePage = prelude.front.split(whereSeparator: \.isBlank).map(Array.init)
      if sections.first?.heading == nil {
        var leadIn = sections[0].blocks[...]
        let opening = leadIn.firstIndex { opensBody($0.lines, proseIndent: prelude.proseIndent) }
        if let opening {
          leadIn = leadIn[...opening]
        }
        titlePage += leadIn.map(\.lines)
      }
      // The words, not the columns the title page set them in (#683).
      header.title = Self.title(page: header.title, index: title, titlePage: titlePage)
        .collapsingWhitespace()
    }
    // The lead-in, which is the only section with no heading, loses what the title page
    // left in it here rather than in `parse`, so the diagnosis never sees it either: a
    // report of blocks the parser dropped unread would count refusals it never made.
    if sections.first?.heading == nil {
      sections[0].blocks = leadInWithoutFrontMatter(
        sections[0].blocks, title: header.title, proseIndent: prelude.proseIndent,
        number: header.id?.number)
    }
    return Prepared(header: header, sections: sections, proseIndent: prelude.proseIndent)
  }

  /// What `prepared` hands both entry points.
  struct Prepared {
    var header: DocumentHeader
    var sections: [RawSection]
    /// The document's prose cap, which every prose test in it is asked against.
    var proseIndent: Int
  }

  /// The prose cap for a body at column 3: the three columns a paragraph may indent
  /// past it, as a first-line indent or a nested paragraph.
  static let classicProseIndent = 6

  /// The deepest a paragraph may start in this document and still read as prose: three
  /// columns past its body, and never less than `classicProseIndent`.
  ///
  /// The cap used to be six everywhere, which is right for a body at column 3 and wrong
  /// for the few hundred documents set deeper (#55). RFC 1178 sets its body at 9 under
  /// headings at 6, and every one of its paragraphs failed the cap and was kept as
  /// artwork, which is never linked; RFC 1122 lost most of its requirements text the
  /// same way. The floor keeps every body at column 3 or less exactly where it was.
  ///
  /// The body is where the sentences are, so only a line that reads as one is counted:
  /// four words or more, three fifths of them ordinary. Counting every line put the
  /// body wherever the document keeps most of its code -- RFC 5545's iCalendar
  /// examples, a MIB module's `::= { ifMauEntry 4 }`.
  ///
  /// And the body is the outermost of them, so it is the indent a quarter of those
  /// lines sit at or left of, rather than the commonest. A MIB module's `DESCRIPTION`
  /// clauses read as sentences too: RFC 3635 has 632 such lines at column 23 against
  /// 354 of body at 3, and the commonest indent put its cap at 26.
  ///
  /// Nor is a MIB module's quoted text counted at all, because the quarter is not
  /// enough where the module is most of the document. RFC 8096 is mostly its module,
  /// and its `DESCRIPTION` clauses at 6 to 10 outnumber the body at 3 so far that the
  /// quarter landed at 7: the cap rose to 10, and 37 of the module's blocks, `::= {
  /// ipv6MIBObjects 1 }` and all, became paragraphs. RFC 1657 has 175 such lines at 28
  /// against 22 of body. A clause is its keyword's quoted string, open until the line
  /// that closes the quote.
  ///
  /// Over the whole document rather than the body, because the front matter's own
  /// prose test runs before the body's start is known. The front matter is a few
  /// dozen lines against the hundreds the indent is taken from.
  static func proseIndent(_ lines: [Line]) -> Int {
    proseIndent(lines.compactMap(\.string))
  }

  static func proseIndent(_ lines: [String]) -> Int {
    var counts: [Int: Int] = [:]
    var insideClause = false
    var followsClauseKeyword = false
    for string in lines {
      let trimmed = string.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      let keyword = trimmed.prefix { !$0.isWhitespace }
      let opensClause =
        mibClauseKeywords.contains(keyword) || (followsClauseKeyword && trimmed.hasPrefix("\""))
      followsClauseKeyword = mibClauseKeywords.contains(trimmed[...])
      if insideClause || opensClause {
        // A clause's string holds no quote of its own, so an odd count opens or
        // closes it.
        if !trimmed.count(where: { $0 == "\"" }).isMultiple(of: 2) { insideClause.toggle() }
        continue
      }
      if readsLikeSentences([string], minimumWords: 4) {
        counts[string.leadingSpaceCount, default: 0] += 1
      }
    }
    let total = counts.values.reduce(0, +)
    var seen = 0
    for (indent, count) in counts.sorted(by: { $0.key < $1.key }) {
      seen += count
      if seen * 4 >= total { return max(classicProseIndent, indent + 3) }
    }
    return classicProseIndent
  }

  /// The SMI clauses whose quoted string is text: what a MIB module says about an
  /// object in sentences, set as deep as the module sets it.
  private static let mibClauseKeywords: Set<Substring> = [
    "DESCRIPTION", "REFERENCE", "CONTACT-INFO", "ORGANIZATION",
  ]

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
  static func numbersHeadingsWithAColon(_ lines: [String]) -> Bool {
    var colonNumbers: Set<Substring> = []
    var fullStopNumbers: Set<Substring> = []
    var numbers: Set<Substring> = []
    for string in lines where string.startsAtColumnZero {
      // `1)` is the weaker sign: a colon number vetoes it, never the other way round.
      guard let match = string.firstMatch(of: numberedHeadingPattern), match.separator != ")"
      else { continue }
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

  /// Whether `1)` at column 0 is a heading in this document. RFC 1136, 1927 and 2122
  /// number their sections that way (#199), and some forty documents set the same shape
  /// as list items: RFC 77's run on past their first line, RFC 751 starts two lists at
  /// `1)`, and RFC 3116's eight test cases repeat its `1.` headings' numbers.
  ///
  /// So, as with the colon, a parenthesis number has to follow from another, and may not
  /// be another heading's too, `1.`, `1:` or `1` with no separator. And each is a title: it starts its block, which
  /// is two lines at most, a title wrapped once. No number may come twice.
  ///
  /// That still passes RFC 234, a one-page agenda whose six items carry a paragraph
  /// each. What it lacks is any other sign of sections, which the three have: a column-0
  /// line, or a parenthesis title, that names a section every RFC has, `Status of this
  /// Memo` or `Security Considerations`. Across the corpus RFC 234 is the only document
  /// this test decides, but an override cannot take its place: a patch has no operation
  /// that makes a section a list item without restating the section's text.
  static func numbersHeadingsWithAParenthesis(_ lines: [String]) -> Bool {
    var parenthesisNumbers: [Substring] = []
    var otherHeadingNumbers: Set<Substring> = []
    var numbers: Set<Substring> = []
    var namesASection = false
    for (index, string) in lines.enumerated() where string.startsAtColumnZero {
      guard let match = string.firstMatch(of: numberedHeadingPattern) else {
        namesASection = namesASection || namesAStandardSection(string)
        continue
      }
      numbers.insert(match.number)
      guard match.separator == ")" else {
        otherHeadingNumbers.insert(match.number)
        continue
      }
      let startsBlock = index == 0 || lines[index - 1].isBlank
      guard startsBlock, lines[index...].prefix(while: { !$0.isBlank }).count <= 2 else {
        return false
      }
      parenthesisNumbers.append(match.number)
      namesASection = namesASection || namesAStandardSection(String(match.title))
    }
    guard !parenthesisNumbers.isEmpty, namesASection,
      Set(parenthesisNumbers).count == parenthesisNumbers.count,
      otherHeadingNumbers.isDisjoint(with: parenthesisNumbers)
    else { return false }
    return parenthesisNumbers.allSatisfy { follows($0, in: numbers) }
  }

  /// Titles every RFC has a section of. Matched whole, a colon after them allowed, so
  /// that prose opening with `Abstraction` or `References to` names none.
  private static let standardSectionTitles: Set<String> = [
    "status of this memo", "status of memo", "abstract", "introduction",
    "security considerations", "references", "acknowledgment", "acknowledgement",
    "acknowledgments", "acknowledgements", "author's address", "authors' addresses",
  ]

  private static func namesAStandardSection(_ title: String) -> Bool {
    var lowered = title.trimmingCharacters(in: .whitespaces).lowercased()
    if lowered.hasSuffix(":") { lowered.removeLast() }
    return standardSectionTitles.contains(lowered)
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
  private static func rawSections(of prelude: Prelude) -> [RawSection] {
    let lines = prelude.lines
    var sections: [RawSection] = [RawSection(heading: nil)]
    var current: [String] = []
    var pendingBreak = false
    // The numbers headings have taken, which a centered heading may not take again.
    var numbers: Set<String> = []
    let centered = centeredHeadings(in: prelude)

    func flushBlock() {
      if !current.isEmpty {
        sections[sections.count - 1].blocks.append(
          RawBlock(lines: current, followedByPageBreak: pendingBreak))
        current = []
      }
      pendingBreak = false
    }

    for index in lines.indices[prelude.bodyStart...] {
      switch lines[index] {
      case .pageBreak:
        if current.isEmpty, var last = sections[sections.count - 1].blocks.popLast() {
          last.followedByPageBreak = true
          sections[sections.count - 1].blocks.append(last)
        } else {
          pendingBreak = true
          flushBlock()
        }
      // A section running header still here is the only thing saying where its
      // section starts; `prepared` has taken out those the document heads itself.
      case .text(let string), .sectionHeader(let string, _):
        if string.isBlank {
          flushBlock()
        } else if let heading = Self.heading(at: index, in: prelude, startsBlock: current.isEmpty),
          !isContentsEntry(at: index, in: lines)
        {
          if heading.number == nil, refusesUnnumberedHeading(heading.title) {
            let last = sections.count - 1
            sections[last].refusedHeadingLine =
              sections[last].refusedHeadingLine ?? (sections[last].blocks.count, current.count)
            current.append(string)
          } else {
            flushBlock()
            sections.append(RawSection(heading: heading))
            if let number = heading.number { numbers.insert(number) }
          }
        } else if let heading = centered[index], let number = heading.number,
          !numbers.contains(number)
        {
          flushBlock()
          sections.append(RawSection(heading: heading))
          numbers.insert(number)
        } else {
          current.append(string)
        }
      }
    }
    flushBlock()
    return sections
  }

  /// The separators after a heading's number that head sections in some documents and
  /// are something else in the rest, `1:` and `1)`, as far as a document numbers its
  /// headings with them. The full stop, and no separator at all, head sections in any.
  struct HeadingSeparators: OptionSet {
    let rawValue: Int

    static let colon = HeadingSeparators(rawValue: 1 << 0)
    static let parenthesis = HeadingSeparators(rawValue: 1 << 1)
  }

  /// What every reading of the depaginated lines starts from: the lines, double
  /// spacing collapsed, and what the front matter's end and the headings are judged
  /// by. `prepared` goes on from here, and `stripPagination` and the corpus report ask
  /// it which section running headers the document heads itself, so all three agree.
  /// Segmentation takes it whole, rather than its fields one by one.
  struct Prelude {
    let lines: [Line]
    let separators: HeadingSeparators
    let proseIndent: Int
    let front: [String]
    let bodyStart: Int
    let bodyIsIndented: Bool

    /// The sightings of the section running headers in the body that the document
    /// heads itself nearby; see `headsNearby`.
    var headedSectionHeaders: Set<Int> {
      var headed: Set<Int> = []
      for index in lines.indices[bodyStart...] {
        guard case .sectionHeader(_, let sighting) = lines[index], headsNearby(at: index, in: self)
        else { continue }
        headed.insert(sighting)
      }
      return headed
    }

    /// The prelude without the section running headers' first sightings the document
    /// heads itself, now that the headings they are judged by are known (#291): what
    /// `rawSections` segments. They are only ever in the body, so `bodyStart` still is
    /// where it was, and the rest is judged by the lines as they were.
    var omittingHeadedSectionHeaders: Prelude {
      let headed = headedSectionHeaders
      return Prelude(
        lines: lines.filter { line in
          guard case .sectionHeader(_, let sighting) = line else { return true }
          return !headed.contains(sighting)
        },
        separators: separators, proseIndent: proseIndent, front: front, bodyStart: bodyStart,
        bodyIsIndented: bodyIsIndented)
    }
  }

  /// The sightings of the section running headers in the depaginated lines that the
  /// document heads itself, and which neither the body nor the as-published
  /// view keeps.
  static func headedSectionHeaders(in depaginated: [Line]) -> Set<Int> {
    guard depaginated.contains(where: \.isSectionHeader) else { return [] }
    return Prelude(depaginated).headedSectionHeaders
  }

  /// Whether the document heads the section the running header's first sighting at
  /// `index` names, nearby: with a heading of the same words, as `headingText` reads
  /// them, on the header's own page or the two before it, in the body (#291). A section's
  /// running header first appears on the page after the one it starts on, which carries
  /// the last section's name, or two pages on where the headers alternate between facing
  /// pages: RFC 793 starts `2.  PHILOSOPHY` at the head of a page headed `Introduction`,
  /// and first runs `Philosophy` on the next. Where the document heads it, the first
  /// sighting is a second, empty heading beside the document's own; where it doesn't, it
  /// is the only thing saying where the section starts (RFC 770's `References`).
  ///
  /// A heading is one `rawSections` would emit, or a numbered one at any indent, because
  /// RFC 793 centers `2.  PHILOSOPHY`. The header is read as a heading too, so one that
  /// carries its section's number matches the heading that does, and only that one.
  /// Local, and answered by the headings themselves: asking whether any numbered heading
  /// anywhere in the document had the words compared two normalizations that never agreed
  /// on a number, and let an `Introduction` at one end of a document speak for a running
  /// header at the other (#57).
  static func headsNearby(at index: Int, in prelude: Prelude) -> Bool {
    let (lines, bodyStart, separators) = (prelude.lines, prelude.bodyStart, prelude.separators)
    guard let header = lines[index].string else { return false }
    func isBreak(_ line: Line) -> Bool {
      if case .pageBreak = line { true } else { false }
    }
    // Back over this page and the two before it, not into the front matter, and on
    // to the end of this one.
    var start = index
    for page in 0..<3 {
      if page > 0, start > bodyStart { start -= 1 }
      while start > bodyStart, !isBreak(lines[start - 1]) { start -= 1 }
    }
    var end = index + 1
    while end < lines.endIndex, !isBreak(lines[end]) { end += 1 }

    let stated = header.trimmingCharacters(in: .whitespaces)
    let headerHeading = heading(from: stated, separators: separators)
    let title = headingText(headerHeading?.title ?? stated)
    // The same words, and the same number where both have one: `5.  Retry Handling`
    // is not `4.  Retry Handling`. A header with no title, `Appendix B`, is told by
    // its number alone, and never matches a heading that has no number either.
    func names(_ heading: HeadingInfo) -> Bool {
      guard headingText(heading.title) == title else { return false }
      if let number = headerHeading?.number, let other = heading.number {
        return number == other
      }
      return !title.isEmpty
    }
    for candidate in start..<end {
      guard case .text(let string) = lines[candidate] else { continue }
      // Where `rawSections` starts a block: after a blank line or a page break, and
      // after a section running header, which it reads past.
      let previous = candidate - 1
      let startsBlock =
        candidate == bodyStart || isBlankOrEnd(lines, at: previous)
        || lines[previous].isSectionHeader
      if let heading = Self.heading(at: candidate, in: prelude, startsBlock: startsBlock),
        heading.number != nil || !refusesUnnumberedHeading(heading.title)
      {
        if names(heading) { return true }
        continue
      }
      let indented = string.drop { $0 == " " }
      if indented.first?.isNumber == true,
        let heading = Self.heading(from: String(indented), separators: separators),
        heading.number != nil, names(heading)
      {
        return true
      }
    }
    return false
  }

  /// `title` is the document's title as the RFC index gives it, where the caller has
  /// it. The run of lines front matter takes for the title is a guess: in RFC 822 it
  /// is `Obsoletes:  RFC #733`, in RFC 1144 the first of the title's two lines (#170,
  /// #171), in RFC 5323 the author and date. Where the guess is not the title, the
  /// index's replaces it -- in 601 of the 8,457 legacy documents -- and the rest of the
  /// title the page sets is recognized in the lead-in and kept out of it.
  ///
  /// Where the guess is the title, the page's own stays, although the index recases
  /// and rewords it: it sets older titles in sentence case and drops their article
  /// (`Note on Reconnection Protocol` for RFC 671's `A Note on Reconnection
  /// Protocol`), and the page is what the author wrote. `title(page:index:titlePage:)`
  /// is where the two are told apart.
  public static func parse(_ text: String, title: String? = nil) -> RFCDocument {
    let prepared = Self.prepared(text, title: title)
    var header = prepared.header
    let bibliographies = Self.bibliographies(in: prepared.sections)
    let context = ParseContext(
      proseIndent: prepared.proseIndent,
      linker: Self.linker(sections: prepared.sections, bibliographies: bibliographies))

    var flat: [Section] = []
    // A document has one abstract, the first: RFC 2371's appendix embeds a second
    // protocol's, and a catalog (RFC 1292, 1632, 2116) gives every entry one (#72).
    // A later one is the body's, and stays where it is.
    var abstractTaken = false
    for (index, raw) in prepared.sections.enumerated() {
      guard let heading = raw.heading else {
        // Text before the first heading that is not front matter: keep as an unnumbered lead-in.
        let blocks = Self.blocks(from: raw.blocks, in: context)
        if !blocks.isEmpty {
          flat.append(Section(anchor: "preamble", title: "", blocks: blocks))
        }
        continue
      }
      let lowered = heading.title.lowercased()
      if heading.number == nil {
        let isAbstract = lowered == "abstract" && !abstractTaken
        if isAbstract || Self.isBoilerplateTitle(lowered) {
          let omitted = Self.omittingBoilerplate(
            raw, heading: heading, isAbstract: isAbstract, in: context)
          if let abstract = omitted.abstract {
            header.abstract = abstract
            abstractTaken = true
          }
          if let rest = omitted.rest {
            flat.append(rest)
          }
          continue
        }
      }
      flat.append(
        Self.section(from: raw, heading: heading, references: bibliographies[index], in: context))
    }
    return Self.finished(flat, header: header)
  }

  /// The entries of each references section that is a bibliography, by the section's
  /// index, with their anchors settled against each other and against the sections'.
  private static func bibliographies(in sections: [RawSection]) -> [Int: [Reference]] {
    Self.settlingEntryAnchors(
      sections.indices.reduce(into: [Int: [Reference]]()) { lists, index in
        guard let heading = sections[index].heading, Self.isReferencesHeading(heading) else {
          return
        }
        let blocks = sections[index].blocks
        let entries = Self.parseReferences(blocks)
        guard
          Self.isBibliography(
            title: heading.title, entries: entries.count,
            blocksBefore: Self.blocksBeforeFirstEntry(blocks).count)
        else { return }
        lists[index] = entries
      },
      reserved: Self.reservedAnchors(Self.sectionAnchorCandidates(sections))
    )
  }

  /// The linker for the document's prose: the section numbers it may cite, and the
  /// labels of its bibliographies' entries.
  private static func linker(sections: [RawSection], bibliographies: [Int: [Reference]])
    -> InlineLinker
  {
    // An appendix numbered like a section, `Appendix 2`, is not what `Section 2` cites.
    let sectionNumbers = Set(
      sections.compactMap { $0.heading.flatMap { $0.isAppendix ? nil : $0.number } })
    var referenceTargets: [String: CrossReference.Target] = [:]
    // Keyed by the label, which is what the prose cites; pointing at the anchor, which
    // is what the entry is declared under. Pointing at `ref-<label>` instead, which no
    // entry ever was, left 30,368 citations in 3,708 documents linking nowhere (#81).
    // A label listed twice is cited as its first entry, whichever kind of target it is.
    for index in bibliographies.keys.sorted() {
      for reference in bibliographies[index] ?? []
      where referenceTargets[reference.displayAnchor] == nil {
        referenceTargets[reference.displayAnchor] =
          reference.documentID.map { .document($0, section: nil, entry: reference.anchor) }
          ?? .anchor(reference.anchor)
      }
    }
    return InlineLinker(sectionNumbers: sectionNumbers, referenceTargets: referenceTargets)
  }

  /// An abstract, or a section of boilerplate the RFCXML path omits too: the abstract's
  /// blocks for the header, and what follows the omitted part as a section of its own,
  /// where anything does.
  private static func omittingBoilerplate(
    _ raw: RawSection, heading: HeadingInfo, isAbstract: Bool, in context: ParseContext
  ) -> (abstract: [Block]?, rest: Section?) {
    var extent = Self.boilerplateExtent(
      of: raw.blocks, isContents: heading.title.lowercased().hasPrefix("table of contents"),
      proseIndent: context.proseIndent)
    // Omitted boilerplate ends where a heading's place is taken, whether or not
    // the line there is a heading: refused as prose, RFC 1198's sentence at column
    // 0 took the list of standards under it into its `Status of this Memo`. Where
    // the line continues a block, the lines before it are the boilerplate's.
    var blocks = raw.blocks
    if !isAbstract, let refused = raw.refusedHeadingLine, refused.block < extent {
      blocks[refused.block].lines.removeFirst(refused.line)
      extent = refused.block
    }
    let abstract =
      isAbstract ? Self.blocks(from: Array(raw.blocks.prefix(extent)), in: context) : nil
    guard extent < blocks.count else { return (abstract, nil) }
    let body = Self.blocks(from: Array(blocks.dropFirst(extent)), in: context)
    guard !body.isEmpty else { return (abstract, nil) }
    return (abstract, Section(anchor: "after-\(heading.anchor)", title: "", blocks: body))
  }

  /// An ordinary section: its heading, linked, and its blocks, ending in its entries
  /// where it is a bibliography.
  private static func section(
    from raw: RawSection, heading: HeadingInfo, references: [Reference]?,
    in context: ParseContext
  ) -> Section {
    var section = Section(
      anchor: heading.anchor,
      number: heading.number,
      // A heading cites like any other prose -- "Changes from RFC 3066",
      // "Differences from RFC 793" -- and roughly 3,500 headings in the
      // corpus name a document. The number is not part of the words, so
      // the linker never sees it and cannot mistake it for a section
      // cross reference. The words, not the columns they were set in: a classifier
      // reads a heading's gaps, a title does not (#683).
      title: context.linker.link(heading.title.collapsingWhitespace()),
      isAppendix: heading.isAppendix
    )
    if let references, !references.isEmpty {
      let leading = Self.blocks(from: Self.blocksBeforeFirstEntry(raw.blocks), in: context)
      section.blocks =
        leading + [.references(ReferenceList(title: heading.title, entries: references))]
    } else {
      section.blocks = Self.blocks(from: raw.blocks, in: context)
    }
    return section
  }

  /// The document the sections make: nested by their numbers, their anchors made
  /// unique, and its abbreviations and defined terms collected.
  private static func finished(_ sections: [Section], header: DocumentHeader) -> RFCDocument {
    var document = RFCDocument(
      header: header, sections: Self.nest(Self.makingAnchorsUnique(sections)), source: .text)
    document.abbreviations = Abbreviations.defined(in: document)
    document.definedTerms = DefinedTerms.defined(in: document)
    return document
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
  /// lone line is where the body's own unrecognized heading sits.
  static func boilerplateExtent(of blocks: [RawBlock], isContents: Bool, proseIndent: Int)
    -> Int
  {
    guard blocks.count > 20 else { return blocks.count }
    // Looser than the lead-in's `isContentsEntries`: under a contents heading an entry
    // needs only a leader or a page number, because not every listing sets both.
    func isEntry(_ line: String) -> Bool {
      line.trimmingCharacters(in: .whitespaces).last?.isNumber == true || line.contains("..")
        || line.contains(". .")
    }
    return 1
      + blocks.dropFirst().prefix { block in
        isContents
          ? block.lines.count(where: isEntry) * 2 >= block.lines.count
          : block.lines.count > 1 && looksLikeProse(block.lines, maxIndent: proseIndent)
      }.count
  }

  /// Headings of boilerplate that the RFCXML path also omits; the original text view
  /// still has it.
  private static let boilerplateTitles = [
    "table of contents", "status of this memo", "status of memo", "copyright notice",
    "full copyright statement", "intellectual property", "disclaimer of validity",
  ]

  static func isBoilerplateTitle(_ lowered: String) -> Bool {
    boilerplateTitles.contains { lowered.hasPrefix($0) }
  }
}

// In an extension, so that the struct keeps its memberwise initializer, which
// `omittingHeadedSectionHeaders` and the segmentation guards' tests make one with.
extension LegacyTextParser.Prelude {
  init(_ depaginated: [LegacyTextParser.Line]) {
    let lines = LegacyTextParser.collapsingDoubleSpacing(depaginated)
    let separators = LegacyTextParser.HeadingSeparators(lines)
    let proseIndent = LegacyTextParser.proseIndent(lines)
    let (front, bodyStart) = LegacyTextParser.splitFrontMatter(
      lines, separators: separators, proseIndent: proseIndent)
    self.init(
      lines: lines, separators: separators, proseIndent: proseIndent, front: front,
      bodyStart: bodyStart, bodyIsIndented: LegacyTextParser.bodyIsIndented(lines[bodyStart...]))
  }
}

extension LegacyTextParser.HeadingSeparators {
  init(_ lines: [LegacyTextParser.Line]) {
    // A page break reads as a blank line, which ends a `1)` heading's block.
    let strings = lines.map { $0.string ?? "" }
    self = []
    if LegacyTextParser.numbersHeadingsWithAColon(strings) { insert(.colon) }
    if LegacyTextParser.numbersHeadingsWithAParenthesis(strings) { insert(.parenthesis) }
  }
}
