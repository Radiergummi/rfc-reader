import Foundation

extension LegacyTextParser {
  private static let nonHeadingWords: Set<String> = [
    "rfc", "obsoletes", "updates", "category", "issn",
  ]

  /// Header lines, refused as a heading by what they say rather than by their first
  /// word: the body a header block names, and the number label, whose value is not
  /// always a number (`Request for Comments: DRAFT`, `Request for Comments: 17a`).
  /// Refusing every line that opens with `Network`, `Internet` or `Request` kept these
  /// out of the body, and refused about 120 real headings with them -- `NETWORK
  /// NUMBERS`, `Internet Protocol`, and RFC 796's only one.
  static let headerLinePrefixes = [
    "network working group", "internet engineering task force",
    "internet architecture board", "internet research task force",
    "request for comments:",
  ]

  /// True when the body sits at an indent and headings stand out at column 0, which is
  /// the layout `heading(from:)` assumes. A few hundred legacy RFCs (1142, 1305, 1247,
  /// 1034 and others) set their prose at column 0 as well; there the indent says nothing
  /// and every line would otherwise become an unnumbered heading.
  static func bodyIsIndented(_ body: ArraySlice<Line>) -> Bool {
    var counts: [Int: Int] = [:]
    for string in body.lazy.compactMap(\.string) where !string.isBlank {
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
  ///
  /// An unnumbered heading also has to pass `refusesUnnumberedHeading`, which
  /// `rawSections` asks rather than `heading(from:)`, whose other caller is the front
  /// matter's end: there the test is kept lax on purpose. The stricter one moved the
  /// front matter's end in 41 documents, most of them later, and what it ran on past was
  /// lost: RFC 783's summary. Omitted boilerplate ends at a refused line too, for the
  /// same reason.
  static func heading(at index: Int, in prelude: Prelude, startsBlock: Bool) -> HeadingInfo? {
    guard let string = prelude.lines[index].string, string.startsAtColumnZero else { return nil }
    guard prelude.bodyIsIndented || (startsBlock && isBlankOrEnd(prelude.lines, at: index + 1))
    else { return nil }
    return heading(from: string, separators: prelude.separators)
  }

  /// A contents entry's end: a leader of four dots or more, run on or spaced, or of
  /// three spaced after a space, then a page number. Four run on, because a range in a
  /// title is three, `0...255`, and a range is never spaced.
  private static let contentsEntryPattern = Pattern(
    #/(?:(?:\.\s?){4,}|\s(?:\.\s){3,})\s*(?<page>\d+|[ivx]+)\s*$/#)

  /// A contents entry, `2.  Overview ........ 5`, which reads as a heading at column
  /// 0 and never is one: RFC 791, 793 and the specifications set like them list their
  /// contents there, and each entry opened a section of its own (#403). `rawSections`
  /// asks this and `heading(from:)` does not, because the front matter's end is
  /// judged by that one, and it ends at such a listing. Stricter than the lead-in's
  /// `isContentsEntries`, which takes two dots: this one refuses a heading, and a
  /// title may hold a range, `1..5`.
  ///
  /// The leader is four dots, or three spaced, which no range is. RFC 5735's appendix
  /// entry has three, and took the appendix's anchor (#427): an entry taken for a
  /// heading claims its heading's anchor, and the heading is renamed `appendix-A-2`.
  static func isContentsEntry(_ line: String) -> Bool {
    guard let match = line.firstMatch(of: contentsEntryPattern) else { return false }
    return isPageNumber(match.page)
  }

  /// `isContentsEntry`, or an entry with no leader: a page number in a column of its
  /// own, after a word and a gap of two spaces or more, where the nearest line above
  /// or below, past blank lines, is an entry too (#427).
  ///
  /// RFC 1001, 1076, 1276 and 1305 list their contents so, and each entry opened a
  /// section that took its heading's anchor. The neighbor is what makes it an entry,
  /// because a listing is a run of them: RFC 707 sets its body's headings so too, the
  /// page number at the margin of each, and they stand alone between paragraphs. The
  /// word keeps a heading whose whole title is a number, RFC 4975's `10.1.  200` and
  /// RFC 4844's `A.1.  1992`. A column-0 table whose rows end in a figure is refused
  /// with the listings, and its rows were no headings either: each of RFC 391's
  /// traffic rows opened a section.
  static func isContentsEntry<Lines: RandomAccessCollection<String?>>(
    at index: Int, in lines: Lines
  ) -> Bool where Lines.Index == Int {
    guard let line = lines[index] else { return false }
    if isContentsEntry(line) { return true }
    guard endsInPageColumn(line) else { return false }
    return [-1, 1].contains { step in
      var neighbor = index + step
      while lines.indices.contains(neighbor), lines[neighbor]?.isBlank ?? true {
        neighbor += step
      }
      guard lines.indices.contains(neighbor), let string = lines[neighbor] else { return false }
      return isContentsEntry(string) || endsInPageColumn(string)
    }
  }

  static func isContentsEntry(at index: Int, in lines: [Line]) -> Bool {
    isContentsEntry(at: index, in: lines.lazy.map(\.string))
  }

  private static let pageColumnPattern = Pattern(#/\p{L}{2}.*\S {2,}(?<page>\d+|[ivx]+)\s*$/#)

  private static func endsInPageColumn(_ line: String) -> Bool {
    guard let match = line.firstMatch(of: pageColumnPattern) else { return false }
    return isPageNumber(match.page)
  }

  /// The numbered headings set off column 0, by line:
  /// RFC 791, 793 and the specifications set like them center a chapter's heading,
  /// `1.  INTRODUCTION`, on a line of its own, and set its subsections at column 0
  /// (#403). Off column 0 a numbered line is otherwise a list item, so it is a
  /// heading only where the next heading is its first subsection, and no nearer line
  /// of the same shape has its number: of a diagram's numbered rows and a chapter's
  /// heading, the heading is the one just above `4.1`. `rawSections` refuses one
  /// whose number a heading has already taken, so a list of one-line items under a
  /// heading of that number stays a list.
  ///
  /// Once a document has centered a chapter that way, a line after it centered on the
  /// page, in capitals and on its own, is a chapter heading as well (#550): one with
  /// no number, RFC 793's `GLOSSARY` and `REFERENCES`, or a numbered chapter with no
  /// numbered subsection to confirm it, RFC 753's `4.  EXAMPLES & SCENARIOS`
  /// (`centeredChapters`). A centered line in a body is otherwise a figure's title or
  /// a caption, which the document's centered chapters are what tell apart.
  ///
  /// One pass from the end, carrying the next heading down, because asking each line
  /// for the heading after it scanned the section for every one of them: RFC 1122's
  /// 266 indented numbered lines made its parse four times slower. A column-0 line is
  /// the next heading where `rawSections` would open a section at it. It asks whether
  /// the line starts a block, and that is whether the line above is blank: a heading
  /// directly above would need a blank line under it in a body at column 0, and in an
  /// indented body the position is not asked.
  static func centeredHeadings(in prelude: Prelude) -> [Int: HeadingInfo] {
    let lines = prelude.lines
    var headings: [Int: HeadingInfo] = [:]
    var next: (index: Int, number: String?)?
    var nearestOfNumber: [String: Int] = [:]
    for index in lines.indices[prelude.bodyStart...].reversed() {
      guard let string = lines[index].string, !string.isBlank else { continue }
      if string.startsAtColumnZero {
        if let heading = Self.heading(
          at: index, in: prelude, startsBlock: isBlankOrEnd(lines, at: index - 1)),
          heading.number != nil || !refusesUnnumberedHeading(heading.title),
          !isContentsEntry(at: index, in: lines)
        {
          next = (index, heading.number)
        }
        continue
      }
      guard isBlankOrEnd(lines, at: index - 1), isBlankOrEnd(lines, at: index + 1),
        let heading = heading(from: string, separators: prelude.separators),
        let number = heading.number, !isContentsEntry(at: index, in: lines)
      else { continue }
      let nearest = nearestOfNumber[number, default: .max]
      if let next, next.number == "\(number).1", nearest > next.index {
        headings[index] = heading
      }
      nearestOfNumber[number] = index
    }
    return centeredChapters(in: prelude, after: headings)
  }

  /// `headings`, the centered chapters a following subsection confirms, and every
  /// line after the first of them that is set like one: centered, in capitals and on
  /// its own, numbered as a chapter or with a title an unnumbered heading may have.
  private static func centeredChapters(in prelude: Prelude, after headings: [Int: HeadingInfo])
    -> [Int: HeadingInfo]
  {
    guard let first = headings.keys.min() else { return headings }
    let lines = prelude.lines
    var chapters = headings
    for index in lines.indices[first...] where chapters[index] == nil {
      guard let string = lines[index].string, !string.isBlank, !string.startsAtColumnZero,
        isCenteredOnPage(string), !string.contains(where: \.isLowercase),
        isBlankOrEnd(lines, at: index - 1), isBlankOrEnd(lines, at: index + 1),
        let heading = heading(from: string, separators: prelude.separators),
        !isContentsEntry(at: index, in: lines)
      else { continue }
      if let number = heading.number {
        guard !number.contains(".") else { continue }
      } else if refusesUnnumberedHeading(heading.title) {
        continue
      }
      chapters[index] = heading
    }
    return chapters
  }

  /// Whether a line is centered on the 72 columns of a page: as far from its left
  /// edge as from its right, within a few columns, and set in from both. Words spread
  /// across the line, as a diagram's labels or a table's row are, `TCP A` far left of
  /// `TCP B`, are not one centered line.
  static func isCenteredOnPage(_ line: String) -> Bool {
    let indent = line.prefix { $0 == " " }.count
    let text = line.trimmingCharacters(in: .whitespaces)
    let end = text.count + indent
    return indent >= 8 && end < 72 && abs(indent - (72 - end)) <= 3 && !text.contains("   ")
  }

  static func isBlankOrEnd(_ lines: [Line], at index: Int) -> Bool {
    guard lines.indices.contains(index) else { return true }
    switch lines[index] {
    case .pageBreak:
      return true
    case .text(let string), .sectionHeader(let string, _):
      return string.isBlank
    }
  }

  /// A couple of dozen documents (RFC 817, 813, 888, 827) are typeset double spaced: a
  /// blank line sits between every pair of lines, so no paragraph ever forms and every
  /// line stands alone. Drop those single blanks and keep the wider gaps, which are the
  /// real paragraph breaks. The "as published" view goes through `stripPagination(_:)`
  /// and is not touched.
  static func collapsingDoubleSpacing(_ lines: [Line]) -> [Line] {
    var content = 0
    var isolated = 0
    for (index, line) in lines.enumerated() {
      guard let string = line.string, !string.isBlank else { continue }
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

  static func heading(from line: String, separators: HeadingSeparators) -> HeadingInfo? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.count < 120 else { return nil }
    if let match = trimmed.firstMatch(of: numberedHeadingPattern) {
      switch match.separator {
      case ":": guard separators.contains(.colon) else { return nil }
      case ")": guard separators.contains(.parenthesis) else { return nil }
      default: break
      }
      let number = String(match.number)
      let title = String(match.title).trimmingTrailingDots().collapsingWhitespace()
      return HeadingInfo(
        number: number, title: title, isAppendix: false,
        anchor: SectionAnchor.anchor(forSectionNumber: number))
    }
    if let (number, matched) = appendixHeading(in: trimmed) {
      let title = matched.trimmingTrailingDots().collapsingWhitespace()
      return HeadingInfo(
        number: number, title: title, isAppendix: true,
        anchor: SectionAnchor.anchor(forAppendixNumber: number))
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
      number: nil, title: trimmed, isAppendix: false, anchor: "name-\(trimmed.slugified())")
  }

  /// How an appendix heading with no number opens: the word `Appendix` or `Annex`,
  /// capitalized or in capitals. Not a lower-case `appendix`, which is wrapped prose,
  /// and not followed by a number: a numbered appendix heading is read as one before
  /// this, so what is left is prose that names one, `Appendix B holds the drawings`.
  private static let appendixOpening = Pattern(
    #/A(?i:ppendix|nnex)\b(?!\s+(?:[A-Z]|[IVX]+|\d+)\b)/#)

  /// Punctuation that a heading does not have and code and drawings do: ASN.1 and ABNF
  /// definitions, braces, table rules and box drawing, arrows.
  private static let codePunctuation = ["::=", "{", "}", "|", "+--", "---", "===", "->"]

  /// Words a title-cased heading leaves in lower case: `Transmission of IP Datagrams
  /// over Ethernet` is title case all the same. Only words of four letters or more,
  /// because `isSentenceCase` looks at no shorter word.
  private static let minorWords: Set<String> = [
    "about", "above", "across", "after", "against", "along", "among", "around", "before",
    "behind", "below", "beneath", "beside", "besides", "between", "beyond", "despite",
    "down", "during", "except", "from", "inside", "into", "like", "near", "onto",
    "outside", "over", "past", "since", "than", "through", "throughout", "toward",
    "towards", "under", "underneath", "until", "unto", "upon", "versus", "with", "within",
    "without",
  ]

  /// True for a column-0 line that passed every other test for an unnumbered heading,
  /// but reads as something else: prose, a MIB line, a grammar or a drawing (#201).
  ///
  /// Measured over the legacy corpus, half of the 62,924 unnumbered headings the parser
  /// made were one of these, and every sample of them was wrong:
  ///
  /// - a lower-case start: MIB lines (`dot1qTpGroupLearnt OBJECT-TYPE`), wrapped prose,
  ///   `o` list items;
  /// - code or diagram punctuation (`codePunctuation`): ASN.1, ABNF, table rules, boxes;
  /// - a sentence's end, `.`, `;` or `,`: prose, protocol traces, data lines. `etc.`
  ///   ends a heading's list as often as a sentence, and is let through;
  /// - sentence case past 50 characters, where the samples turn from titles into prose.
  ///
  /// Title case, all capitals and short sentence case (`How to read this memo`) are
  /// where the real headings are. Their false positives, table rows and header-field
  /// lines, need the neighboring lines to judge, which is a second pass.
  static func refusesUnnumberedHeading(_ title: String) -> Bool {
    guard let first = title.first else { return true }
    // A numbered appendix is an appendix heading and never reaches this test. One with
    // no number lands here, and the rules would refuse four over the corpus for a full
    // stop or their length: `Appendix: Title.`, `Appendix - a long title in sentence
    // case`. What they start with says heading, whatever follows it.
    if title.prefixMatch(of: appendixOpening) != nil { return false }
    if first.isLowercase { return true }
    if codePunctuation.contains(where: { title.contains($0) }) { return true }
    if let last = title.last, ".;,".contains(last), !title.hasSuffix("etc.") { return true }
    return title.count > 50 && isSentenceCase(title)
  }

  /// Neither all capitals nor title case: some word of four letters or more that is not
  /// a minor word starts in lower case.
  private static func isSentenceCase(_ title: String) -> Bool {
    title.split(separator: " ").contains { word in
      let letters = word.filter(\.isLetter)
      guard letters.count >= 4, !minorWords.contains(letters.lowercased()) else { return false }
      return letters.first?.isLowercase == true
    }
  }

  static func isReferencesHeading(_ heading: HeadingInfo) -> Bool {
    isReferencesTitle(heading.title)
  }

  /// Whether a heading's title names references, as a word: `Priority for Domain
  /// Preferences` (RFC 6186) and `Router Preferences and More-Specific Routes` (RFC
  /// 7066) hold the letters and were read as bibliographies from their first
  /// bracketed line.
  ///
  /// What a title says in parentheses is an aside: `Simple Example (Signature, ...,
  /// and References)` in RFC 3275 is an example, and its lines of XML read as 26
  /// entries (#686).
  static func isReferencesTitle(_ title: String) -> Bool {
    withoutAsides(title).lowercased().contains(#/\breferences\b/#)
  }

  private static let aside = Pattern(#/\([^)]*\)/#)

  private static func withoutAsides(_ title: String) -> String {
    title.replacing(aside, with: "").collapsingWhitespace()
      .trimmingCharacters(in: .whitespaces)
  }

  /// A references section by its title alone: `References`, `Normative References:`,
  /// `Informative References (Alphabetical)`.
  private static let plainReferencesTitle = Pattern(
    #/(?i)(?:(?:normative|informative|informational|non-normative) )?references[.:]?/#)

  /// Whether a section whose title names references is a bibliography. A plain
  /// references title is one, whatever the parser makes of its entries: RFC 1716's
  /// and 2315's hold one each beside the text it could not split. Any other title only
  /// mentions references -- `References Section` in RFC 7322, a style guide's advice
  /// on writing one, or `Continuation References in the Search Result` in RFC 4511 --
  /// and is a bibliography when its entries outnumber the blocks before the first of
  /// them. Read as one, such a section's text was taken for a single entry's, and
  /// its subsections had no place in the XML (#686).
  static func isBibliography(
    title: String, entries: Int, blocksBefore: @autoclosure () -> Int
  ) -> Bool {
    if withoutAsides(title).wholeMatch(of: plainReferencesTitle) != nil { return true }
    return entries > blocksBefore()
  }

  static func nest(_ flat: [Section]) -> [Section] {
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
    return liftingOutOfBibliographies(roots)
  }

  /// A bibliography holds bibliographies and nothing else: `<references>` has no room
  /// for a section, so a section nested in one lost its text in the XML (#686). The
  /// numbering nests one there when an appendix's own heading is missing or not read
  /// as one -- RFC 2814's `A.1.` follows `9. References` with no `Appendix A` -- or
  /// when the author numbered it so, as RFC 2639's `4.1 Authors' Addresses` under `4
  /// References`. From the first subsection that is not a bibliography, they follow
  /// it instead, in the order they came.
  static func liftingOutOfBibliographies(_ sections: [Section]) -> [Section] {
    sections.flatMap { section -> [Section] in
      var section = section
      section.subsections = liftingOutOfBibliographies(section.subsections)
      let holdsEntries = section.blocks.contains {
        if case .references = $0 { true } else { false }
      }
      guard holdsEntries,
        let first = section.subsections.firstIndex(where: { !RFCXMLSerializer.isReferences($0) })
      else { return [section] }
      let lifted = Array(section.subsections[first...])
      section.subsections.removeSubrange(first...)
      return [section] + lifted
    }
  }
}
