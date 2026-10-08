import Foundation
import RegexBuilder

extension LegacyTextParser {
  /// The lead-in with the title page's leftovers taken out of its start (#76).
  ///
  /// The front matter ends at the first paragraph, or at the start of the run a heading
  /// sits in, so neither is lost (#74); what the title page has left between it and the
  /// body reaches the lead-in instead of being dropped. Whether a block is prose does
  /// not separate the two -- RFC 817 opens with a paragraph, RFC 783 with a justified
  /// summary the prose test refuses, RFC 394 with an underlined heading -- so it is what
  /// the block *is* that decides:
  ///
  /// - contents entries, a dot leader and a page number: RFC 780 and 821 leave the
  ///   last one, `REFERENCES ....... 42`, and RFC 1441 the whole listing;
  /// - a header block, which states the document's number in two columns: RFC 780
  ///   and 821 repeat theirs on the first page of the body, and RFC 674 sets its
  ///   under an NLS journal stamp. RFC 84's catalog states a number on every
  ///   entry, but indents the entry's lines under it, and stays;
  /// - a line with no letters in it, a phone number (RFC 757) or a page number
  ///   (RFC 674);
  /// - boilerplate under a heading set off column 0, as a centered `Status of this
  ///   Memo` is in RFC 1441 to 1452: the heading, and up to three paragraphs after it
  ///   that say what boilerplate says. A contents title goes alone, its entries after
  ///   it.
  ///
  /// Only up to the first paragraph or list the lead-in keeps, which is where the
  /// body has begun; past it, a line of those shapes is the body's.
  static func leadInWithoutFrontMatter(
    _ blocks: [RawBlock], title: String, proseIndent: Int, number: Int?
  ) -> [RawBlock] {
    let titleWords = words(title)
    var kept: [RawBlock] = []
    var index = blocks.startIndex
    while index < blocks.endIndex {
      let block = blocks[index]
      if let heading = standaloneTitle(block)?.lowercased(), isBoilerplateTitle(heading) {
        index += 1
        guard !heading.hasPrefix("table of contents") else { continue }
        // Status paragraphs run to one or two, the copyright statement to three, and
        // they are paragraphs: RFC 1144's author's note after its status is artwork.
        // And they say what boilerplate says, because otherwise only a heading ends the
        // run, and a short document can open its body straight after its status with
        // none. No legacy RFC is known to, but every paragraph the lead-in loses here
        // across the corpus says what boilerplate says.
        var paragraphs = 0
        while index < blocks.endIndex, paragraphs < 3, standaloneTitle(blocks[index]) == nil,
          looksLikeProse(blocks[index].lines, maxIndent: proseIndent),
          readsAsBoilerplate(blocks[index].lines)
        {
          index += 1
          paragraphs += 1
        }
        continue
      }
      if isContentsEntries(block.lines) || isHeaderBlock(block.lines, number: number)
        || (block.lines.count <= 2 && !block.lines.contains { $0.contains(where: \.isLetter) })
        || repeatsTitle(block.lines, titleWords) || isDateLine(block.lines)
      {
        index += 1
        continue
      }
      kept.append(block)
      index += 1
      if opensBody(block.lines, proseIndent: proseIndent) { break }
    }
    return kept + blocks[index...]
  }

  /// A paragraph or a list, which is where the body has begun and the title page
  /// has ended.
  static func opensBody(_ lines: [String], proseIndent: Int) -> Bool {
    listMarker(of: lines) != nil
      || (lines.count > 1 && looksLikeProse(lines, maxIndent: proseIndent))
  }

  /// What a status, copyright or IPR paragraph says and a body's opening does not: RFC
  /// 1441 to 1452 are `for the Internet community`, RFC 1147 `this memo`, RFC 905 `does
  /// not specify a standard`.
  private static let boilerplateWording = [
    "this memo", "distribution of this", "internet community", "standards track",
    "official protocol standards", "specify a standard", "specify an internet standard",
    "for information only", "copyright", "rights reserved", "internet society",
    "intellectual property",
  ]

  /// Whether a paragraph under a boilerplate heading says what boilerplate says.
  static func readsAsBoilerplate(_ lines: [String]) -> Bool {
    let text = lines.joined(separator: " ").lowercased()
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return boilerplateWording.contains { text.contains($0) }
  }

  /// A short block whose words run, in order, somewhere inside the title: a title page
  /// sets a long title over several runs -- RFC 1144's `for Low-Speed Serial Links`,
  /// RFC 822's `ARPA INTERNET TEXT MESSAGES` -- and the front matter holds only one.
  /// Compared as words, because the page sets the title in capitals, with its own
  /// punctuation, and the index does not.
  private static func repeatsTitle(_ lines: [String], _ titleWords: [Substring]) -> Bool {
    guard lines.count <= 3 else { return false }
    let blockWords = words(lines.joined(separator: " "))
    guard !blockWords.isEmpty, blockWords.count <= titleWords.count else { return false }
    return (0...(titleWords.count - blockWords.count)).contains {
      titleWords[$0..<($0 + blockWords.count)].elementsEqual(blockWords)
    }
  }

  private static func words(_ text: String) -> [Substring] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }
  }

  /// A title's words without a leading article, which the index drops.
  private static func titleWords(_ title: String) -> ArraySlice<Substring> {
    let all = words(title)
    return ["a", "an", "the"].contains(all.first) ? all.dropFirst() : all[...]
  }

  /// The document's title: the one the page sets, or the RFC index's where the page's
  /// is not the title at all (#170).
  ///
  /// The page's stays where it has most of the index's words, in order -- four in
  /// five -- and they are at least half its own. The index rewords titles: RFC 1801's
  /// `X.400-MHS` is its `MHS`, RFC 6527 loses `the`, RFC 1915's `Connection Control
  /// Protocol` is its `Compression`, and none of those misses more than one of the
  /// index's words. Four in five keeps a title the index rewords by a word or
  /// two, where a title from a header line, an author or a paragraph shares a few
  /// words by chance. Half its own, because a title that has an author, a date or
  /// the opening paragraph run on after it has all the index's words and many more:
  /// RFC 815 and 816 run on through the author and his affiliation, and RFC 21's
  /// `Network meeting` is in its first sentence.
  ///
  /// A page title that is part of the index's, and nothing else, stays too, unless
  /// the rest of the index's title is on the title page as well. Then it is a title
  /// set over several runs, of which the front matter took the first: RFC 1144's
  /// `for Low-Speed Serial Links` is on the line below. Where the rest is not on the
  /// page, the index has named the document more fully than its author did: RFC 766
  /// is `Internet Protocol Handbook`, and only the index adds `: Table of contents`.
  ///
  /// A page title set in capitals gives way to the index's whatever its words, as a
  /// typewriter's emphasis rather than a spelling.
  ///
  /// Where the index's title is the one taken and the index sets it in capitals, and
  /// so does the page, neither says how it is spelled, and it is title-cased (#219).
  /// The page is the front matter's title or, where the front matter took another
  /// line, the title page's runs that repeat the index's: RFC 822 sets its title in
  /// capitals over two of them, under a header the front matter took instead.
  static func title(page: String, index: String, titlePage: [[String]]) -> String {
    let chosen = chosenTitle(page: page, index: index, titlePage: titlePage)
    guard chosen == index, !index.contains(where: \.isLowercase),
      setsInCapitals(index, page: page) || setsInCapitals(index, titlePage: titlePage)
    else { return chosen }
    return titleCased(index)
  }

  /// Whether the page's title is the index's, or part of it, set in capitals: a page
  /// with no title, or with another line in capitals, says nothing of this one.
  private static func setsInCapitals(_ title: String, page: String) -> Bool {
    let pageWords = titleWords(page)
    return !pageWords.isEmpty && !page.contains(where: \.isLowercase)
      && sharedWordCount(titleWords(title), pageWords) == pageWords.count
  }

  /// Whether the title page sets `title` in capitals: some of its runs repeat the
  /// title's words, and none of those has a lower-case letter.
  private static func setsInCapitals(_ title: String, titlePage: [[String]]) -> Bool {
    let titleWords = words(title)
    let runs = titlePage.filter { repeatsTitle($0, titleWords) }
    return !runs.isEmpty && !runs.joined().contains { $0.contains(where: \.isLowercase) }
  }

  /// Which of the two `title` takes, by the rules its comment gives, as they come.
  private static func chosenTitle(page: String, index: String, titlePage: [[String]]) -> String {
    guard page.contains(where: \.isLowercase) else { return index }
    let indexWords = titleWords(index)
    let pageWords = titleWords(page)
    let shared = sharedWordCount(indexWords, pageWords)
    if shared * 5 >= indexWords.count * 4, shared * 2 >= pageWords.count {
      return page
    }
    guard shared == pageWords.count else { return index }
    let allIndexWords = words(index)
    var onTitlePage = Set(pageWords)
    for run in titlePage where repeatsTitle(run, allIndexWords) {
      onTitlePage.formUnion(words(run.joined(separator: " ")))
    }
    let found = indexWords.count { onTitlePage.contains($0) }
    return found * 5 >= indexWords.count * 4 ? index : page
  }

  /// The acronyms a title set in capitals keeps in capitals: a fixed list, not a
  /// length rule, because the words to keep are names, and `TIP` and `TOP` are the
  /// same length (#219).
  private static let titleAcronyms: Set<String> = [
    "ARPA", "ARPANET", "BBN", "FTP", "HTTP", "IANA", "IMP", "IP", "MIT", "NCP", "NIC",
    "NICNAME", "TCP", "TENEX", "TIP", "TIPUG", "UCLA", "WHOIS",
  ]

  /// The words a title sets lower case but at the start of it or of a part.
  private static let titleSmallWords: Set<String> = [
    "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor", "of",
    "on", "or", "over", "the", "to", "via", "with",
  ]

  /// A title set in capitals, in title case: each word with a capital and the rest
  /// lower case, except the acronyms of `titleAcronyms`, the small words of
  /// `titleSmallWords` past the start, a number's suffix (`21st`), and initials
  /// (`M.I.T`). Each side of a slash or hyphen is a word, and a spaced dash, single
  /// or double, or a colon starts the title again.
  private static func titleCased(_ title: String) -> String {
    var startsPart = true
    return title.split(separator: " ", omittingEmptySubsequences: false).map { word in
      if word == "-" || word == "--" {
        startsPart = true
        return String(word)
      }
      var cased = ""
      var piece = ""
      func flush() {
        guard !piece.isEmpty else { return }
        cased += titleCasedWord(piece, startsPart: startsPart)
        startsPart = false
        piece = ""
      }
      for character in word {
        if character == "/" || character == "-" {
          flush()
          cased.append(character)
        } else {
          piece.append(character)
        }
      }
      flush()
      // A colon ends a part, as a dash does: `FTP: The Example`.
      if word.hasSuffix(":") { startsPart = true }
      return cased
    }
    .joined(separator: " ")
  }

  /// One word, cased, with the punctuation around it -- a parenthesis, a comma, a
  /// closing period -- left where it is.
  private static func titleCasedWord(_ word: String, startsPart: Bool) -> String {
    let isWordCharacter = { (character: Character) in character.isLetter || character.isNumber }
    guard let first = word.firstIndex(where: isWordCharacter),
      let last = word.lastIndex(where: isWordCharacter)
    else { return word }
    let core = String(word[first...last])
    let cased: String
    if titleAcronyms.contains(core) || core.contains(".") {
      cased = core
    } else if core.first?.isNumber == true {
      cased = core.lowercased()
    } else if !startsPart, titleSmallWords.contains(core.lowercased()) {
      cased = core.lowercased()
    } else {
      cased = core.prefix(1).uppercased() + core.dropFirst().lowercased()
    }
    return word[..<first] + cased + word[word.index(after: last)...]
  }

  /// How many words the two have in common, in the same order: the longest run of
  /// words both contain, not necessarily side by side.
  private static func sharedWordCount(
    _ first: ArraySlice<Substring>, _ second: ArraySlice<Substring>
  ) -> Int {
    var previousRow = [Int](repeating: 0, count: second.count + 1)
    for word in first {
      var row = [0]
      for (offset, other) in second.enumerated() {
        row.append(
          word == other ? previousRow[offset] + 1 : max(previousRow[offset + 1], row[offset]))
      }
      previousRow = row
    }
    return previousRow[second.count]
  }

  /// A month's full name, as a title page and a references entry spell it: the one
  /// list both month patterns are built on. `PublicationDate.month(from:)` numbers
  /// every one of them, which a test holds it to.
  private static let monthName = Pattern(
    Regex {
      ChoiceOf {
        "January"
        "February"
        "March"
        "April"
        "May"
        "June"
        "July"
        "August"
        "September"
        "October"
        "November"
        "December"
      }
    })

  /// `August 13, 1982`, `13 August 1982`, `July 1984`.
  private static let dateLinePattern = Pattern(
    Regex {
      Optionally {
        Repeat(.digit, 1...2)
        OneOrMore(.whitespace)
      }
      monthName
      OneOrMore(.whitespace)
      Optionally {
        Repeat(.digit, 1...2)
        Optionally(",")
        OneOrMore(.whitespace)
      }
      Repeat(.digit, count: 4)
    })

  /// A line that is a date and nothing else, as a title page sets its publication date:
  /// RFC 822's `August 13, 1982`, RFC 907's `July 1984`.
  static func isDateLine(_ lines: [String]) -> Bool {
    lines.count == 1
      && lines[0].trimmingCharacters(in: .whitespaces).wholeMatch(of: dateLinePattern) != nil
  }

  /// A one-line block that reads as a heading, trimmed of a trailing colon: short,
  /// and not the end of a sentence. What ends a run of boilerplate paragraphs.
  private static func standaloneTitle(_ block: RawBlock) -> String? {
    guard block.lines.count == 1 else { return nil }
    var title = block.lines[0].trimmingCharacters(in: .whitespaces)
    if title.hasSuffix(":") { title.removeLast() }
    guard !title.isEmpty, title.count <= 60, title.last != "." else { return nil }
    return title
  }

  /// Half the lines or more are contents entries: a dot leader, then a page number in
  /// arabic or lower-case roman numerals (RFC 822's `PREFACE .......   ii`), which may
  /// run straight on from the leader (RFC 2295's `Terminology.......5`). Half, because
  /// an entry too long for its line wraps, and only its last line has both.
  private static func isContentsEntries(_ lines: [String]) -> Bool {
    let entries = lines.count { line in
      guard line.contains("..") || line.contains(". ."),
        let page = line.split(whereSeparator: { $0 == " " || $0 == "." }).last
      else { return false }
      return isPageNumber(page)
    }
    return entries > 0 && entries * 2 >= lines.count
  }

  /// A page number in arabic or lower-case roman numerals.
  static func isPageNumber(_ word: Substring) -> Bool {
    word.allSatisfy(\.isNumber) || isRomanPageNumber(word)
  }

  private static let romanPageNumberPattern = Pattern(#/x{0,3}(?:ix|iv|v?i{0,3})/#)

  /// A lower-case roman numeral up to `xxxix`, further than any front section's pages
  /// run. Spelt out rather than taken as any run of the letters, because `ill` and
  /// `civil` are made of them too.
  static func isRomanPageNumber(_ word: Substring) -> Bool {
    !word.isEmpty && word.wholeMatch(of: romanPageNumberPattern) != nil
  }

  /// A block of a title page's header: some line states the document's own number or
  /// has a header line's left column (RFC 821's is `Request for Comments: DRAFT`), and
  /// every line is two columns, or one column set flush right. The document's own
  /// number, because a table of RFCs is two columns stating numbers too. The whole
  /// column, because RFC 160's catalog lists `Network Working Group Meeting`. Two
  /// lines to a handful: a line of RFC 84's catalog is `NWG/RFC 14    (never issued)`
  /// on its own.
  static func isHeaderBlock(_ lines: [String], number: Int?) -> Bool {
    guard (2...8).contains(lines.count),
      lines.contains(where: { line in
        let left = line.trimmingCharacters(in: .whitespaces).lowercased()
          .components(separatedBy: "   ")[0]
        return (number != nil && statedNumber(in: line) == number)
          || headerLinePrefixes.contains { $0.hasSuffix(":") ? left.hasPrefix($0) : left == $0 }
      })
    else { return false }
    return lines.allSatisfy { line in
      let indent = line.leadingSpaceCount
      return line.dropFirst(indent).contains("   ") || (indent >= 40 && line.count >= 64)
    }
  }

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
  static func splitFrontMatter(_ lines: [Line], separators: HeadingSeparators, proseIndent: Int)
    -> (front: [String], bodyStart: Int)
  {
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
    func split(_ boundary: (offset: Int, frontCount: Int)) -> (front: [String], bodyStart: Int) {
      (Array(front.prefix(boundary.frontCount)), boundary.offset)
    }
    // Runs are counted from the one that states the number: RFC 873 opens with an NLS
    // journal stamp in two runs ahead of its header, and "after the title" counted from
    // the stamp fell before the number line (#60).
    let skipped = (numberRun(in: lines) ?? 1) - 1
    for (offset, line) in lines.enumerated() {
      guard let string = line.string else { continue }
      if string.isBlank {
        if firstParagraph == nil, let start = runStart, run - skipped > 2 {
          let runLines = Array(front[start.frontCount...])
          if runLines.count > 1, looksLikeProse(runLines, maxIndent: proseIndent) {
            firstParagraph = start
          }
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
        let heading = heading(from: string, separators: separators), !heading.isAppendix,
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
        if string.startsAtColumnZero, heading(from: string, separators: separators) != nil {
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
    for string in lines.lazy.compactMap(\.string) {
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

  /// A month and a year, `May 2008`, each captured.
  static let monthYearPattern = Pattern(
    Regex {
      Capture { monthName }
      OneOrMore(.whitespace)
      Capture { Repeat(.digit, count: 4) }
    })
  private static let authorPattern = Pattern(
    #/^(?<name>(?:[A-Z]\.\s?)+\s*[A-Z][\w'\-]+)(?<editor>,\s*Ed(?:itor)?\.?)?$/#)

  /// The author a title page's right-hand column names, if it names one: initials and
  /// a surname, and an editor's suffix in any spelling the pattern accepts -- `, Ed.`,
  /// `, Ed`, `, Editor`, `,Ed.` -- which is taken off the name and becomes the role.
  static func author(in column: String) -> Author? {
    guard let match = column.firstMatch(of: authorPattern) else { return nil }
    return Author(name: String(match.name), role: match.editor == nil ? nil : .editor)
  }

  /// The line that states the document's number, in any of the spellings the series has
  /// used (#51): `Request for Comments: 793`, `RFC # 64`, `NWG/RFC# 276`, `NWG RFC 103`, `RFC-811`,
  /// `Request For Comment: 4801`, the source's own `Request for Commments: 2347`. Tried
  /// against the whole line, at its start or where a column begins, because the number
  /// is not always in the left column (RFC 811 sets it on the right) and a label spaced
  /// widely enough from its number is split from it by the column split
  /// (`Request for Comments:    50`).
  static let numberLinePattern = Pattern(
    #/(?:^|\s{2})(?:NWG\s*/?\s*)?(?:RFC|Requests?\s+(?:for\s+)?Comm+ents?)\s*(?:(?:#|:|-|No\.)\s*)*(?:RFC\s*)?(\d+)\b/#
      .ignoresCase())

  /// The indent from which a header line that holds one column holds the right one:
  /// past the middle of a 72-column line, where no left-column continuation reaches.
  static let rightColumnIndent = 36

  static func parseFrontMatter(_ lines: [String]) -> DocumentHeader {
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
    // What it obsoletes and updates, read as a draft's are: a list continued on an
    // indented line, and `BCP 14` not read as RFC 14 (#767).
    let lists = DraftHeader.parse(frontPage: Array(lines[index...]))
    header.obsoletes = lists.obsoletes.map(DocumentID.rfc)
    header.updates = lists.updates.map(DocumentID.rfc)
    while index < lines.count, !lines[index].isEmpty {
      let line = lines[index]
      index += 1
      let columns = line.components(separatedBy: "   ").map {
        $0.trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
      guard let first = columns.first else { continue }
      // A line set in the right half alone is the right column, its left one having run
      // out: an author past the last line of the left column's labels (#767). An
      // indented continuation of a left-column label sits well left of it.
      let isRightOnly =
        columns.count == 1
        && line.prefix(while: { $0 == " " }).count >= rightColumnIndent
      let left = isRightOnly ? "" : first
      let right = isRightOnly ? first : columns.count > 1 ? columns.last! : nil

      if left.hasPrefix("Obsoletes:") || left.hasPrefix("Updates:") {
        // Read below, with the lines that continue them.
      } else if left.hasPrefix("Category:") {
        header.category = DocumentHeader.Category(
          parsing: String(left.dropFirst("Category:".count)))
      } else if header.id == nil, let number = statedNumber(in: line) {
        // The first one wins: a continuation line under `Obsoletes:` is set as
        // `            RFC #680` (RFC 733), and must not replace the number above it.
        header.id = .rfc(number)
      }

      for candidate in [left, right].compactMap({ $0 }) {
        if let match = candidate.firstMatch(of: monthYearPattern) {
          header.date = PublicationDate(
            year: Int(match.2) ?? 0, month: PublicationDate.month(from: String(match.1)))
        } else if candidate == right, let author = author(in: candidate) {
          header.authors.append(author)
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
    header.title = titleLines.joined(separator: " ").collapsingWhitespace()
    return header
  }

  private static func statedNumber(in line: String) -> Int? {
    line.trimmingCharacters(in: .whitespaces).firstMatch(of: numberLinePattern).flatMap {
      Int($0.1)
    }
  }
}
