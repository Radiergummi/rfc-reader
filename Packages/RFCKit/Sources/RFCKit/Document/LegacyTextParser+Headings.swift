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
  static func heading(
    at index: Int, in lines: [Line], bodyIsIndented: Bool, colonNumbered: Bool, startsBlock: Bool
  ) -> HeadingInfo? {
    guard let string = lines[index].string, string.startsAtColumnZero else { return nil }
    guard bodyIsIndented || (startsBlock && isBlankOrEnd(lines, at: index + 1)) else { return nil }
    return heading(from: string, colonNumbered: colonNumbered)
  }

  /// A contents entry's end: a leader of four dots or more, run on or spaced, then a
  /// page number. Four, because a range in a title is three, `0...255`.
  private static let contentsEntryPattern = Pattern(#/(?:\.\s?){4,}\s*(?<page>\d+|[ivx]+)\s*$/#)

  /// A contents entry, `2.  Overview ........ 5`, which reads as a heading at column
  /// 0 and never is one: RFC 791, 793 and the specifications set like them list their
  /// contents there, and each entry opened a section of its own (#403). `rawSections`
  /// asks this and `heading(from:)` does not, because the front matter's end is
  /// judged by that one, and it ends at such a listing. Stricter than the lead-in's
  /// `isContentsEntries`, which takes two dots: this one refuses a heading, and a
  /// title may hold a range, `1..5`.
  ///
  /// An entry ends in a leader of four dots, three spaced, or none at all and a page
  /// number set off in a column of its own. An entry taken for a heading claims its
  /// heading's anchor, and the heading itself is renamed `appendix-A-2` (#427).
  static func isContentsEntry(_ line: String) -> Bool {
    for pattern in [contentsEntryPattern, spacedLeaderPattern, pageColumnPattern] {
      if let match = line.firstMatch(of: pattern), isPageNumber(match.page) { return true }
    }
    return false
  }

  /// A spaced leader of three dots, `Title  . . . 10`, too short for
  /// `contentsEntryPattern`, and no range, which is never spaced. RFC 5735's appendix
  /// entry is set so, and took the appendix's anchor (#427).
  private static let spacedLeaderPattern = Pattern(#/\s(?:\.\s){3,}\s*(?<page>\d+|[ivx]+)\s*$/#)

  /// A page number set in a column of its own, with no leader: a word, a gap of two
  /// spaces or more, the number, `A   Summary of Widgets          14`. RFC 1001, 1076,
  /// 1276 and 1305 list their contents so, and an entry opened a section that took the
  /// heading's anchor (#427). The word is what makes it an entry: a heading whose
  /// whole title is a number, RFC 4975's `10.1.  200` and RFC 4844's `A.1.  1992`,
  /// has none, being a number and a status code or a year. A column-0 table row that
  /// ends in a figure is refused with them, and was no heading either: each of RFC
  /// 391's traffic rows opened a section.
  private static let pageColumnPattern = Pattern(#/\p{L}{2}.*\S {2,}(?<page>\d+|[ivx]+)\s*$/#)

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
  /// One pass from the end, carrying the next heading down, because asking each line
  /// for the heading after it scanned the section for every one of them: RFC 1122's
  /// 266 indented numbered lines made its parse four times slower. A column-0 line is
  /// the next heading where `rawSections` would open a section at it. It asks whether
  /// the line starts a block, and that is whether the line above is blank: a heading
  /// directly above would need a blank line under it in a body at column 0, and in an
  /// indented body the position is not asked.
  static func centeredHeadings(
    in lines: [Line], from start: Int, bodyIsIndented: Bool, colonNumbered: Bool
  ) -> [Int: HeadingInfo] {
    var headings: [Int: HeadingInfo] = [:]
    var next: (index: Int, number: String?)?
    var nearestOfNumber: [String: Int] = [:]
    for index in lines.indices[start...].reversed() {
      guard let string = lines[index].string, !string.isBlank else { continue }
      if string.startsAtColumnZero {
        if let heading = Self.heading(
          at: index, in: lines, bodyIsIndented: bodyIsIndented, colonNumbered: colonNumbered,
          startsBlock: isBlankOrEnd(lines, at: index - 1)),
          heading.number != nil || !refusesUnnumberedHeading(heading.title),
          !isContentsEntry(string)
        {
          next = (index, heading.number)
        }
        continue
      }
      guard isBlankOrEnd(lines, at: index - 1), isBlankOrEnd(lines, at: index + 1),
        let heading = heading(from: string, colonNumbered: colonNumbered),
        let number = heading.number, !isContentsEntry(string)
      else { continue }
      let nearest = nearestOfNumber[number, default: .max]
      if let next, next.number == "\(number).1", nearest > next.index {
        headings[index] = heading
      }
      nearestOfNumber[number] = index
    }
    return headings
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

  static func heading(from line: String, colonNumbered: Bool) -> HeadingInfo? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.count < 120 else { return nil }
    if let match = trimmed.firstMatch(of: numberedHeadingPattern) {
      guard colonNumbered || match.separator != ":" else { return nil }
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
  static func isReferencesTitle(_ title: String) -> Bool {
    title.lowercased().contains(#/\breferences\b/#)
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
    return roots
  }
}
