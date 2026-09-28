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

  public static func parse(_ text: String, title: String? = nil) -> RFCDocument {
    LegacyTextParser().parse(text, title: title)
  }

  public static func parse(_ data: Data) -> RFCDocument {
    parse(String(decoding: data, as: UTF8.self))
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
    var depth: Int
  }

  struct RawSection {
    var heading: HeadingInfo?
    var blocks: [RawBlock] = []
  }

  nonisolated(unsafe) static let numberedHeadingPattern =
    #/^(?<number>\d+(?:\.\d+)*)(?<separator>[.:])?\s+(?<title>\S.*)$/#
  nonisolated(unsafe) private static let appendixHeadingPattern =
    #/^(?:Appendix\s+)?(?<number>[A-Z](?:\.\d+)*)\.?\s+(?<title>[A-Z].*)$/#
  /// `Appendix A: Title`, the way about 150 legacy RFCs head an appendix (#200). A
  /// pattern of its own rather than a colon allowed in the one above, whose
  /// `Appendix` is optional: there a colon would admit a bare `A: Title`, which at
  /// column 0 is as often a question's answer.
  nonisolated(unsafe) private static let colonAppendixHeadingPattern =
    #/^Appendix\s+(?<number>[A-Z](?:\.\d+)*):\s+(?<title>[A-Z].*)$/#

  /// The number and title of an appendix heading, in any shape the parser reads one:
  /// `Appendix A. Title`, `Appendix A Title`, `A.1. Title` and `Appendix A: Title`.
  /// Nil for anything else. Internal, so the shapes can be pinned on hand-written
  /// lines rather than through a whole document.
  static func appendixHeading(in line: String) -> (number: String, title: String)? {
    if let match = line.firstMatch(of: appendixHeadingPattern) {
      return (String(match.number), String(match.title))
    }
    if let match = line.firstMatch(of: colonAppendixHeadingPattern) {
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
    return prepared.sections.flatMap { section in
      let anchor = section.heading?.anchor ?? ""
      return section.blocks.map { block in
        BlockDiagnostics(
          section: anchor,
          firstLine: String(block.firstLine.trimmingCharacters(in: .whitespaces).prefix(80)),
          lineCount: block.lines.count,
          // A catalogue is a list too, offered the block before the prose test.
          claimedByList: listItems(block.lines, marker: listMarker(of: block.lines)) != nil
            || catalogueEntries(block.lines) != nil,
          diagnosis: diagnose(block.lines, maxIndent: prepared.proseIndent)
        )
      }
    }
  }

  /// Everything between raw text and blocks: depagination, front matter, segmentation.
  ///
  /// Both entry points go through here so neither can normalise the text differently
  /// from the other. Extracting only `rawSections` left this prelude written twice,
  /// which is the same drift one level up.
  static func prepared(_ text: String, title: String? = nil) -> Prepared {
    let lines = collapsingDoubleSpacing(depaginate(text))
    let colonNumbered = numbersHeadingsWithAColon(lines)
    let proseIndent = proseIndent(lines)
    let (front, bodyStart) = splitFrontMatter(
      lines, colonNumbered: colonNumbered, proseIndent: proseIndent)
    let body = bodyIsIndented(lines[bodyStart...])
    var header = parseFrontMatter(front)
    var sections = rawSections(
      in: lines, from: bodyStart, bodyIsIndented: body, colonNumbered: colonNumbered)
    if let title, !title.isEmpty {
      // The title page is the front matter's runs and the lead-in's blocks up to the
      // one that opens the body, which is where a title set over several runs leaves
      // the rest. Up to and including it, because the rest can pass for a paragraph:
      // RFC 806 sets it in two lines of capitals.
      var titlePage = front.split(whereSeparator: \.isBlank).map(Array.init)
      if sections.first?.heading == nil {
        var leadIn = sections[0].blocks[...]
        let opening = leadIn.firstIndex { opensBody($0.lines, proseIndent: proseIndent) }
        if let opening {
          leadIn = leadIn[...opening]
        }
        titlePage += leadIn.map(\.lines)
      }
      header.title = Self.title(page: header.title, index: title, titlePage: titlePage)
    }
    // The lead-in, which is the only section with no heading, loses what the title page
    // left in it here rather than in `parse`, so the diagnosis never sees it either: a
    // report of blocks the parser dropped unread would count refusals it never made.
    if sections.first?.heading == nil {
      sections[0].blocks = leadInWithoutFrontMatter(
        sections[0].blocks, title: header.title, proseIndent: proseIndent,
        number: header.id?.number)
    }
    return Prepared(header: header, sections: sections, proseIndent: proseIndent)
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
    proseIndent(
      lines.compactMap { line in
        guard case .text(let string) = line else { return nil }
        return string
      })
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

  /// `title` is the document's title as the RFC index gives it, where the caller has
  /// it. The run of lines front matter takes for the title is a guess: in RFC 822 it
  /// is `Obsoletes:  RFC #733`, in RFC 1144 the first of the title's two lines (#170,
  /// #171), in RFC 5323 the author and date. Where the guess is not the title, the
  /// index's replaces it -- in 601 of the 8,457 legacy documents -- and the rest of the
  /// title the page sets is recognised in the lead-in and kept out of it.
  ///
  /// Where the guess is the title, the page's own stays, although the index recases
  /// and rewords it: it sets older titles in sentence case and drops their article
  /// (`Note on Reconnection Protocol` for RFC 671's `A Note on Reconnection
  /// Protocol`), and the page is what the author wrote. `title(page:index:titlePage:)`
  /// is where the two are told apart.
  public func parse(_ text: String, title: String? = nil) -> RFCDocument {
    let prepared = Self.prepared(text, title: title)
    let (sections, proseIndent) = (prepared.sections, prepared.proseIndent)
    var header = prepared.header

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
        let blocks = Self.blocks(from: raw.blocks, proseIndent: proseIndent, linker: linker)
        if !blocks.isEmpty {
          flat.append(Section(anchor: "preamble", title: "", blocks: blocks))
        }
        continue
      }
      let lowered = heading.title.lowercased()
      if heading.number == nil {
        let isAbstract = lowered == "abstract" && !abstractTaken
        if isAbstract || Self.isBoilerplateTitle(lowered) {
          let extent = Self.boilerplateExtent(
            of: raw.blocks, isContents: lowered.hasPrefix("table of contents"),
            proseIndent: proseIndent)
          if isAbstract {
            header.abstract = Self.blocks(
              from: Array(raw.blocks.prefix(extent)), proseIndent: proseIndent, linker: linker)
            abstractTaken = true
          }
          if extent < raw.blocks.count {
            let body = Self.blocks(
              from: Array(raw.blocks.dropFirst(extent)), proseIndent: proseIndent, linker: linker)
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
          section.blocks = Self.blocks(from: raw.blocks, proseIndent: proseIndent, linker: linker)
        }
      } else {
        section.blocks = Self.blocks(from: raw.blocks, proseIndent: proseIndent, linker: linker)
      }
      flat.append(section)
    }

    var document = RFCDocument(
      header: header, sections: Self.nest(Self.makingAnchorsUnique(flat)), source: .text)
    document.abbreviations = Abbreviations.defined(in: document)
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
  /// lone line is where the body's own unrecognised heading sits.
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
