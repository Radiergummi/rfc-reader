import Foundation

extension LegacyTextParser {
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

  private static let referenceStartPattern = Pattern(
    #/^\s*\[(?<anchor>[^\]\s][^\]]{0,39})\]\s*(?<text>.*)$/#)
  /// A page footer `depaginate` could not see. `footerPattern` is anchored to the
  /// end of the line, and the earliest RFCs set the footer the other way round --
  /// `[Page 0]` at the left margin with the author out at the right (RFC 753, 759,
  /// 767, 780) -- so those lines reach the references section intact and are the
  /// one bracket of an anchor's shape that never names a reference. Four documents,
  /// and without this each gains a `<reference anchor="Page 52">` whose title is
  /// whatever the footer's author column said.
  private static let pageFooterAnchorPattern = Pattern(#/Page\s+\d+/#)

  /// The anchor and the rest of the line, where `line` opens a reference entry.
  private static func entryStart(_ line: String) -> (anchor: String, text: Substring)? {
    guard let match = line.firstMatch(of: referenceStartPattern) else { return nil }
    let anchor = String(match.anchor).trimmingCharacters(in: .whitespaces)
    guard anchor.wholeMatch(of: pageFooterAnchorPattern) == nil else { return nil }
    return (anchor, match.text)
  }

  /// A references section's own text, ahead of its first entry: a note on where the
  /// documents can be had, why there are so few, or which of them are normative. It
  /// was dropped, because a references section kept only its entries (74 documents).
  /// A block the first entry starts inside is cut where the entry starts.
  static func blocksBeforeFirstEntry(_ rawBlocks: [RawBlock]) -> [RawBlock] {
    var leading: [RawBlock] = []
    for block in rawBlocks {
      guard let start = block.lines.firstIndex(where: { entryStart($0) != nil }) else {
        leading.append(block)
        continue
      }
      if start > 0 {
        leading.append(RawBlock(lines: Array(block.lines[..<start])))
      }
      return leading
    }
    return leading
  }

  static func parseReferences(_ rawBlocks: [RawBlock]) -> [Reference] {
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
        if let (anchor, text) = entryStart(line) {
          flush()
          currentAnchor = anchor
          currentLines = text.isEmpty ? [] : [String(text)]
        } else if currentAnchor != nil {
          currentLines.append(line.trimmingCharacters(in: .whitespaces))
        }
      }
    }
    flush()
    return references
  }

  /// What `reference(anchor:text:)` reads out of an entry, once per bibliography entry:
  /// hoisted, because a literal inside the function was a new `Regex` for every entry,
  /// compiled again on its first match (#146).
  private static let referenceRFCPattern = Pattern(#/\bRFC\s?(\d+)/#)
  private static let referenceOlderRFCPattern = Pattern(
    #/\b(?:RFC|(?i:Request for Comments):?)[\s\-#]*(\d+)/#)
  private static let referenceBCPPattern = Pattern(#/\bBCP\s?(\d+)/#)
  private static let referenceSTDPattern = Pattern(#/\bSTD\s?(\d+)/#)
  private static let referenceTitlePattern = Pattern(#/"([^"]+)"/#)
  private static let referenceURLPattern = Pattern(#/https?:\/\/[^\s>,]+/#)

  private static func reference(anchor label: String, text: String) -> Reference {
    var seriesInfo: [SeriesInfo] = []
    // `RFC 1495` first, and the older half of the series' `RFC-854`, `RFC- 826` and
    // `Request for Comments 796`, `Request For Comments 990` and `RFC #189` only when an
    // entry has none: once a bare `[1]` stopped naming RFC 1, an entry spelled so named
    // nothing at all. Not in one pattern, though, because a title names RFCs too -- RFC
    // 1494's `[1]` is "Mapping between X.400 and RFC-822 Message Bodies", RFC 1495 -- and
    // the first match would be the title's. `RFCs 1021-1024` is a range, and names none.
    if let match = text.firstMatch(of: referenceRFCPattern)
      ?? text.firstMatch(of: referenceOlderRFCPattern)
    {
      seriesInfo.append(SeriesInfo(name: "RFC", value: String(match.1)))
    } else if let id = DocumentID(label: label) {
      seriesInfo.append(SeriesInfo(id))
    }
    if let match = text.firstMatch(of: referenceBCPPattern) {
      seriesInfo.append(SeriesInfo(name: "BCP", value: String(match.1)))
    }
    if let match = text.firstMatch(of: referenceSTDPattern) {
      seriesInfo.append(SeriesInfo(name: "STD", value: String(match.1)))
    }
    let title = text.firstMatch(of: referenceTitlePattern).map { String($0.1) } ?? ""
    let date = text.firstMatch(of: monthYearPattern).map {
      PublicationDate(year: Int($0.2) ?? 0, month: PublicationDate.month(from: String($0.1)))
    }
    let url = text.firstMatch(of: referenceURLPattern).flatMap {
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
