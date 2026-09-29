import Foundation

extension LegacyTextParser {
  nonisolated(unsafe) private static let bulletPattern =
    #/^(?<indent>\s*)(?<marker>[o\-\*\u{2022}])\s+(?<text>\S.*)$/#
  /// A catalog entry: `NUMBER[letter]  - text`, the RFC index of RFC 1012, the
  /// standards summaries' `2352 - A Convention ...`, numbered steps and value tables
  /// (#204). The text may not start with a digit, or `3 - 2` would be an entry.
  nonisolated(unsafe) private static let catalogEntryPattern =
    #/^(?<indent> {0,8})(?<term>\d+[a-z]?) +- +(?<text>[^\d\s].*)$/#
  /// A column gap in a catalog entry's text: a run of three spaces or more after a
  /// word. After a colon it is no column: `3 - NAME:   description` is a name and its
  /// description, the spaces aligning the descriptions (RFC 5412, 5416, 8231).
  /// `internalGapPattern` counted four spaces after a colon and not three, so RFC
  /// 8231 came out as one row a list among rows kept as artwork.
  nonisolated(unsafe) private static let catalogGapPattern = #/[^.?!:\s]\s{3,}\S/#
  /// Arithmetic in an entry's text: a formula set on a line of its own opens with a
  /// number and a minus as well (RFC 5879's `1 - (1 - x / y) ^ 4 == ...`).
  nonisolated(unsafe) private static let formulaPattern = #/==|\s\^\s/#
  /// A second entry on the entry's line (RFC 3423's `1 - TCP, 2 - SCTP`), which is
  /// not the first one's text.
  nonisolated(unsafe) private static let secondEntryPattern = #/,\s*\d+[a-z]? +- +\S/#
  /// How far past an entry's text column a continuation may stand: a column or two
  /// either way is how a description under an entry is set, and a caption centered
  /// under a legend stands well past it (RFC 793's at 26 against 12).
  private static let catalogContinuationSlack = 2
  nonisolated(unsafe) private static let numberedItemPattern =
    #/^(?<indent>\s*)(?<marker>\(?(?:\d+|[a-z]|[ivx]+)[\.\)])\s+(?<text>\S.*)$/#
  /// `containsArtwork` answers the same question byte by byte; an alternative added
  /// here has to be added there, and `` `the byte scans agree with the regexes` `` is the guard.
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
  private static func digitGapDigit(_ bytes: Span<UInt8>, at index: Int) -> Bool {
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
  private static func withTrimmedASCII(_ line: String, _ body: (Span<UInt8>) -> Bool) -> Bool? {
    let bytes = line.utf8Span.span
    for index in bytes.indices where bytes[index] >= 0x80 || bytes[index] == UInt8(ascii: "\r") {
      return nil
    }
    var start = 0
    var end = bytes.count
    while start < end, bytes[start] == 0x20 || bytes[start] == 0x09 { start += 1 }
    while end > start, bytes[end - 1] == 0x20 || bytes[end - 1] == 0x09 { end -= 1 }
    return body(bytes.extracting(start..<end))
  }

  /// `\s` over ASCII: space, and tab through carriage return.
  private static func isSpace(_ byte: UInt8) -> Bool {
    byte == 0x20 || (0x09...0x0D).contains(byte)
  }

  static func blocks(from rawBlocks: [RawBlock], proseIndent: Int, linker: InlineLinker)
    -> [Block]
  {
    // Re-join paragraphs that a page break cut in half.
    var merged: [RawBlock] = []
    var index = 0
    while index < rawBlocks.count {
      var block = rawBlocks[index]
      while block.followedByPageBreak, index + 1 < rawBlocks.count,
        shouldJoinAcrossPage(block, rawBlocks[index + 1], proseIndent: proseIndent)
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
    // The same for a catalog: the column its numbers stand in, and the column the
    // text of its last entry starts in.
    var openCatalog: (indent: Int, textColumn: Int)?
    for block in merged {
      // Probed once: the continuation test needs to know the block opens with no
      // marker, and a list the block produces needs the column of its own.
      let marker = listMarker(of: block.lines)
      if let indent = openListIndent,
        attachContinuation(block, toListAt: indent, marker: marker, in: &result, linker: linker)
      {
        continue
      }
      if let catalog = openCatalog,
        attachContinuation(
          block, toCatalog: catalog, marker: marker, in: &result, linker: linker)
      {
        continue
      }
      // Probed once as well: `classify` builds a catalog from them, and the catalog
      // left open after it is this block's only if it had them.
      let entries = catalogEntries(block.lines)
      for parsed in classify(
        block, marker: marker, catalogEntries: entries, proseIndent: proseIndent, linker: linker)
      {
        // Merge adjacent list blocks of the same style into one list, and adjacent
        // catalog blocks into one catalog: RFC 1012 sets a blank line between
        // every entry, so each arrives as a block of its own. A numbered block
        // joins the list above only when its first marker is that list's next one:
        // RFC 1927 starts each of its lists at `1)`, a blank line apart.
        if case .list(let list) = parsed, case .list(var previous)? = result.last,
          list.continues(previous)
        {
          previous.items += list.items
          result[result.count - 1] = .list(previous)
        } else if case .definitionList(let items) = parsed,
          case .definitionList(let previous)? = result.last,
          let catalog = openCatalog,
          block.lines.first?.leadingSpaceCount == catalog.indent
            || block.lines.first.flatMap(catalogTextColumn(of:)) == catalog.textColumn
        {
          // At the same column only, of its numbers or of its text: a catalog set
          // deeper is not the one above, and right-aligned numbers (RFC 1140's `1006`
          // over `996`) move the number's column but not the text's.
          result[result.count - 1] = .definitionList(previous + items)
        } else {
          result.append(parsed)
        }
      }
      openListIndent = if case .list? = result.last { marker?.indent } else { nil }
      openCatalog =
        if case .definitionList? = result.last, entries != nil,
          let indent = block.lines.first?.leadingSpaceCount,
          let textColumn = block.lines.last(where: { catalogTextColumn(of: $0) != nil })
            .flatMap(catalogTextColumn(of:))
        {
          (indent, textColumn)
        } else if case .definitionList? = result.last {
          openCatalog
        } else {
          nil
        }
    }
    return result
  }

  /// A paragraph indented past a catalog entry's number and carrying no marker of
  /// its own is the rest of that entry: the standards summaries set an entry's
  /// description under it that way (RFC 2300's `This is an information document
  /// ...`), and it was preserved as artwork.
  ///
  /// The prose test, with one refusal excused for a short block. Most of those
  /// descriptions are a phrase in title case (`A Draft Standard protocol.`), set
  /// past the classic cap, and the prose test refuses a block there unless it reads
  /// as sentences. Kept as artwork, each one ended the catalog, and RFC 2300's
  /// summary came out as 131 lists. The entry above explains the indent, as a list
  /// item explains its continuation's; and at two lines at most, a block is too short
  /// to be the algorithm steps and grammar that refusal is there for. Every other
  /// refusal -- artwork punctuation, a column gap, a ragged indent -- still stands.
  private static func attachContinuation(
    _ block: RawBlock,
    toCatalog catalog: (indent: Int, textColumn: Int),
    marker: ListMarker?,
    in result: inout [Block],
    linker: InlineLinker
  ) -> Bool {
    guard case .definitionList(var items)? = result.last, var item = items.last else {
      return false
    }
    guard marker == nil,
      continuesCatalogEntry(
        block.lines, numberIndent: catalog.indent, textColumn: catalog.textColumn)
    else { return false }
    let inlines = linker.link(joinWrappedLines(block.lines))
    guard !inlines.isEmpty else { return false }
    item.definition.append(.paragraph(Paragraph(inlines)))
    items[items.count - 1] = item
    result[result.count - 1] = .definitionList(items)
    return true
  }

  /// Whether `lines`, with no marker of their own, are the rest of the catalog
  /// entry above them: `attachContinuation`'s test, without the document around it.
  /// They stand past the entry's number and no further past its text than a column
  /// or two (`catalogContinuationSlack`): a caption centered under a legend (RFC
  /// 793's figures, RFC 206's error tables) is short enough for the excuse below
  /// and was taken for the last entry's second paragraph, and in RFC 206 it kept
  /// the catalog open, so three tables ran into one. Internal, so the test can be
  /// pinned on hand-written lines.
  static func continuesCatalogEntry(_ lines: [String], numberIndent: Int, textColumn: Int)
    -> Bool
  {
    let indent = lines.map(\.leadingSpaceCount).min() ?? 0
    guard indent > numberIndent, indent <= textColumn + catalogContinuationSlack,
      catalogEntries(lines) == nil
    else { return false }
    let refusals = diagnose(lines, maxIndent: .max, thorough: true).rejections
    let excused = lines.count <= 2 ? [ProseDiagnostics.Rejection.deepIndentNotSentences] : []
    return refusals.allSatisfy(excused.contains)
  }

  /// A block indented past a list's marker and carrying no marker of its own is the
  /// previous item's second paragraph -- the shape a hanging list takes whenever an
  /// item runs to more than one paragraph (RFC 3712's Introduction, and a few
  /// thousand others).
  ///
  /// It arrives as its own block because a blank line separates it, and it is
  /// indented past the columns `looksLikeProse` allows a paragraph, so it used
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
    // The cap is the only test excused. `RawBlock.indent` is the smallest indent in
    // the block and the block is uniform by the time this passes, so the cap could
    // only ever be its own. Past the classic cap `diagnose` still refuses a MIB
    // module's text (#55), under an item as anywhere; the sentence share it asks
    // there too has already passed above.
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
  /// `blocks(from:proseIndent:linker:)` asks once per block and hands the answer down.
  static func listMarker(of lines: [String]) -> ListMarker? {
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
      // The first item's marker says how the list counts and where from: `(a)` is
      // letters in parentheses, and a list that resumes after an interruption starts
      // at its own `4.`, not at 1.
      let numbering = ListNumbering(marker: match.marker) ?? ListNumbering()
      return (.numbered(numbering), match.indent.count)
    }
    return nil
  }

  static func shouldJoinAcrossPage(_ first: RawBlock, _ second: RawBlock, proseIndent: Int)
    -> Bool
  {
    guard looksLikeProse(first.lines, maxIndent: proseIndent),
      looksLikeProse(second.lines, maxIndent: proseIndent)
    else { return false }
    guard first.indent == second.indent else { return false }
    let lastLine = first.lines.last?.trimmingCharacters(in: .whitespaces) ?? ""
    let nextLine = second.lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
    // A bullet opens an item, whatever the line above it ends with. RFC 1581's `o The
    // most recently ...` opens lower case, as the rest of a sentence does, and was read
    // into the `it is assumed that:` ending the page before it; RFC 6614's `o
    // Access-Request` into the unpunctuated `they send` before its own.
    //
    // A dash is the exception, because it can be the rest of a sentence: RFC 2123's
    // `- e.g. its SourcePeerAddress - is one of ...` continues the page above, as RFC
    // 1345's and 3860's do. It is refused only the lower-case shortcut, as a number is
    // (`... 2) develop ...`), unless the block above opens with a bullet of its own:
    // then it is a list that runs across the page (RFC 1943, 2421, 6258).
    if let marker = listMarker(of: second.lines) {
      let dash = nextLine.first == "-"
      if marker.style == .bullet, !dash || listMarker(of: first.lines)?.style == .bullet {
        return false
      }
    } else if nextLine.first?.isLowercase == true {
      return true
    }
    if let last = lastLine.last, ".:!?".contains(last) { return false }
    return true
  }

  /// `maxIndent` is the deepest a paragraph may start and still read as prose: the
  /// document's `proseIndent`, three columns past its body. Anything set deeper than
  /// that with no list above it to explain the indent is an example.
  static func looksLikeProse(_ lines: [String], maxIndent: Int) -> Bool {
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
  ///
  /// `maxIndent` defaults to the floor `proseIndent` never goes below, a body at column 3.
  static func diagnose(
    _ lines: [String], maxIndent: Int = classicProseIndent, thorough: Bool = true
  )
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

    // Past the classic cap the indent is excused only for sentences, as it is under a
    // list item: a document whose body sits deeper sets its one-line code there too
    // (`::= { ifMauEntry 4 }`, `END`), and a single line has no other guard. Nor for
    // a MIB module's text, whose `DESCRIPTION` clauses and comments are sentences: a
    // block with an assignment in it, or an ASN.1 comment, is the module's (RFC 8096's
    // `... obsoleted by IP-MIB::ipv6IpForwarding." ::= { ipv6MIBObjects 1 }`).
    if indent > maxIndent {
      diagnosis.rejections.append(.indentTooDeep)
    } else if indent > classicProseIndent,
      !readsLikeSentences(lines, share: (of: 1, in: 2)) || readsAsModuleText(lines)
    {
      diagnosis.rejections.append(.deepIndentNotSentences)
    }
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

  /// An ASN.1 assignment (`::=`), which ends every clause, or a comment of two lines or
  /// more, each opening `--`.
  ///
  /// Not a single line opening `--`, nor a block of several whose first line does
  /// alone: RFC 479 and 1343 mark the items of a list that way. And not an unbalanced
  /// quote, which a clause's string split by a blank line has, because a quotation
  /// running over several paragraphs has it as well (RFC 1127, 1207).
  private static func readsAsModuleText(_ lines: [String]) -> Bool {
    if lines.contains(where: { $0.contains("::=") }) { return true }
    return lines.count > 1
      && lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
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
  ///
  /// `minimumWords` is how many words it takes to say: a line of three says nothing
  /// about where a document's sentences are.
  static func readsLikeSentences(
    _ lines: [String], share: (of: Int, in: Int) = (of: 3, in: 5), minimumWords: Int = 1
  ) -> Bool {
    let counted = sentenceWords(lines)
    guard counted.total >= max(minimumWords, 1) else { return false }
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

  private static func classify(
    _ block: RawBlock, marker: ListMarker?, catalogEntries: [(term: String, text: String)]?,
    proseIndent: Int, linker: InlineLinker
  ) -> [Block] {
    let lines = block.lines
    guard !lines.isEmpty else { return [] }

    // Lists: the first line carries a marker and every further item shares its indent.
    if let list = parseList(lines, marker: marker, linker: linker) {
      return [.list(list)]
    }

    // Catalogs: every entry a number and a dash at one indent, anything else hung
    // past it. Before the prose test, which takes a one-line entry for a paragraph
    // and the rest of the block for artwork.
    if let entries = catalogEntries {
      return [
        .definitionList(
          entries.map { entry in
            DefinitionItem(
              term: [.text(entry.term)],
              definition: [.paragraph(Paragraph(linker.link(entry.text)))])
          })
      ]
    }

    if looksLikeProse(lines, maxIndent: proseIndent) {
      let inlines = linker.link(Self.joinWrappedLines(lines))
      return inlines.isEmpty ? [] : [.paragraph(Paragraph(inlines))]
    }

    // Anything else is preserved verbatim, minus the common indentation.
    let indent = block.indent
    let text = lines.map { line in
      String(line.dropFirst(min(indent, line.leadingSpaceCount)))
    }.joined(separator: "\n")
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

  /// The entries of a catalog block, each its number and its text with the lines
  /// hung under it joined, or nil when the block is not one: every entry has to stand
  /// at the first one's indent, and every other line has to hang past it. Internal,
  /// so the shape can be pinned on hand-written lines.
  static func catalogEntries(_ lines: [String]) -> [(term: String, text: String)]? {
    guard let first = lines.first, let head = first.firstMatch(of: catalogEntryPattern) else {
      return nil
    }
    let indent = head.indent.count
    var entries: [(term: String, lines: [String])] = []
    for line in lines {
      if let match = line.firstMatch(of: catalogEntryPattern) {
        // A column gap in the entry is a table with a column of its own after the
        // name (RFC 1058's `1 - request     A request ...`): joined as prose, the
        // columns would run together into one sentence. Artwork keeps them apart.
        // A formula, or a second entry on the line, is not an entry's text either.
        guard match.indent.count == indent, !match.text.contains(catalogGapPattern),
          !match.text.contains(formulaPattern), !match.text.contains(secondEntryPattern)
        else {
          return nil
        }
        entries.append((String(match.term), [String(match.text)]))
      } else if line.leadingSpaceCount > indent, !entries.isEmpty {
        entries[entries.count - 1].lines.append(line)
      } else {
        return nil
      }
    }
    return entries.map { ($0.term, joinWrappedLines($0.lines)) }
  }

  /// The column an entry line's text starts in, past its number and dash, or nil
  /// when the line is no entry. Internal, so it can be pinned on hand-written lines.
  static func catalogTextColumn(of line: String) -> Int? {
    guard let match = line.firstMatch(of: catalogEntryPattern) else { return nil }
    return line.distance(from: line.startIndex, to: match.text.startIndex)
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
  static func listItems(_ lines: [String], marker: ListMarker?) -> (
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
}

extension ListBlock {
  /// Whether this list, parsed from a block of its own, is more of `previous`: the
  /// same bullets, or numbering that picks up where `previous` stopped.
  fileprivate func continues(_ previous: ListBlock) -> Bool {
    switch (style, previous.style) {
    case (.numbered(let numbering), .numbered(let previousNumbering)):
      numbering.continues(previousNumbering, itemCount: previous.items.count)
    default:
      style == previous.style
    }
  }
}
