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
  static func heading(
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
  static func collapsingDoubleSpacing(_ lines: [Line]) -> [Line] {
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
        anchor: SectionAnchor.anchor(forSectionNumber: number))
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
