import Foundation

/// The one citation a piece of selected text makes, as a link: what the Services
/// "Replace with RFC Link" and "Open in RFC Reader" act on (#195).
///
/// The document is read by `InlineLinker`, as the parsers read prose, so a citation
/// the reader links and one these Services link are the same citation. What the
/// linker leaves as text may still say where in that document: `RFC 9110 §8.3`,
/// `RFC 9110, section 8.3` and `RFC 9110, Appendix B` name the place beside the
/// document rather than in the `Section 8.3 of RFC 9110` shape the linker reads, so
/// the place is read from the rest of the selection here. The linker itself is left
/// alone: what it reads in prose is a parser change, with a corpus run of its own.
public enum CitationLink {
  /// Nil unless the selection cites exactly one document, at no more than one place:
  /// `RFC 9110 and RFC 9111`, or `RFC 9110 §8.3 and §8.4`, leave the link in doubt.
  public static func link(in selection: String) -> RFCLink? {
    citation(in: selection)?.link
  }

  /// What "Replace with RFC Link" puts in place of `selection`: the selection with
  /// its citation replaced by the link. The words the cursor caught around it, a
  /// comment's `// see` and the sentence's full stop, stay. Nil when `link(in:)` is.
  public static func replacement(for selection: String) -> String? {
    guard let citation = citation(in: selection) else { return nil }
    return selection.replacingCharacters(
      in: citation.range, with: citation.link.appURL.absoluteString)
  }

  private typealias Located = (link: RFCLink, range: Range<String.Index>)

  private static func citation(in selection: String) -> Located? {
    let inlines = InlineLinker(sectionNumbers: [], referenceTargets: [:]).link(selection)
    // The linker hands back the text it did not link verbatim, so the text before
    // the first reference and after the last is the selection's own prefix and
    // suffix, and the references lie between them.
    guard let first = inlines.firstIndex(where: { !$0.isText }),
      let last = inlines.lastIndex(where: { !$0.isText })
    else { return bareDocument(in: selection) }
    let utf8 = selection.utf8
    let start = utf8.index(utf8.startIndex, offsetBy: inlines[..<first].textLength)
    let end = utf8.index(utf8.endIndex, offsetBy: -inlines[(last + 1)...].textLength)

    var id: DocumentID?
    var section: String?
    var between = ""
    for inline in inlines[first...last] {
      switch inline {
      case .crossReference(let reference):
        guard case .document(let cited, let citedSection, _) = reference.target,
          id == nil || id == cited
        else { return nil }
        id = cited
        // The same document named twice is one citation, unless the two name
        // different places in it.
        if let citedSection {
          guard section == nil || section == citedSection else { return nil }
          section = citedSection
        }
      case .text(let text):
        between += text
      default:
        return nil
      }
    }
    guard let id else { return nil }

    let unlinked = [selection[..<start], between[...], selection[end...]]
    // A plural names more than one place, and the bare number of another series,
    // `BCP 14` beside `RFC 2119`, which the linker links only in brackets, is a
    // second document.
    guard
      unlinked.allSatisfy({
        $0.firstMatch(of: pluralPattern) == nil && $0.firstMatch(of: otherSeriesPattern) == nil
      })
    else { return nil }

    let before = places(in: unlinked[0])
    let inside = places(in: unlinked[1])
    let after = places(in: unlinked[2])
    guard before.count + inside.count + after.count <= 1 else { return nil }
    var range = start..<end
    if let place = before.first ?? inside.first ?? after.first {
      // A section the linker read already is one place more.
      guard section == nil else { return nil }
      section = place.name
    }
    // A place before or after the references is part of the citation only set
    // beside them, `§8.3 of RFC 9110` or `RFC 9110, Section 8.3`: in `Section 4 and
    // RFC 9110` it is a place of its own. Beside them, it widens what is replaced; one
    // between them is inside it already.
    if let place = before.first {
      guard selection[place.range.upperBound..<start].wholeMatch(of: placeBefore) != nil
      else { return nil }
      range = place.range.lowerBound..<end
    } else if let place = after.first {
      guard selection[end..<place.range.lowerBound].wholeMatch(of: placeAfter) != nil
      else { return nil }
      range = start..<place.range.upperBound
      // `RFC 9110 (Section 8.3)`: the parenthesis the citation opened, it closes.
      if selection[range].contains("("),
        let close = selection[range.upperBound...].firstMatch(of: closingParenthesis)
      {
        range = start..<close.range.upperBound
      }
    }
    return (RFCLink(id: id, section: section), range)
  }

  /// A document the linker reads only inside a bracket, `[BCP14]`, selected bare.
  private static func bareDocument(in selection: String) -> Located? {
    let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let id = DocumentID(label: trimmed), let range = selection.range(of: trimmed) else {
      return nil
    }
    return (RFCLink(id: id), range)
  }

  private static func places(in text: Substring) -> [(name: String, range: Range<String.Index>)] {
    let sections = text.matches(of: sectionPattern).map {
      (name: String($0.number), range: $0.range)
    }
    let appendices = text.matches(of: appendixPattern).map {
      (name: SectionAnchor.anchor(forAppendixNumber: $0.number.uppercased()), range: $0.range)
    }
    return sections + appendices
  }

  /// `§8.3`, `§ 8.3`, `Section 8.3`, `section 8.3`.
  private static let sectionPattern = Pattern(
    #/(?:§|\bsection)\s*(?<number>\d+(?:\.\d+)*)/#.ignoresCase())
  /// `Appendix B`, `appendix A.1`, and the `Appendix 1` of the older half of the
  /// series.
  private static let appendixPattern = Pattern(
    #/\bappendix\s+(?<number>[a-z](?:\.\d+)*|\d+(?:\.\d+)*)\b/#.ignoresCase())
  private static let pluralPattern = Pattern(#/§§|\bsections\b|\bappendices\b/#.ignoresCase())
  /// What may stand between a place and the document after it, and between the
  /// document and a place after it.
  private static let placeBefore = Pattern(#/\s+of\s+/#)
  private static let placeAfter = Pattern(#/[\s,(]*/#)
  private static let closingParenthesis = Pattern(#/^\s*\)/#)
  private static let otherSeriesPattern = Pattern(#/\b(?:BCP|STD|FYI)[\s\-]?\d+\b/#)
}

extension Inline {
  fileprivate var isText: Bool {
    if case .text = self { return true }
    return false
  }
}

extension ArraySlice<Inline> {
  /// The UTF-8 length of the text among these inlines.
  fileprivate var textLength: Int {
    reduce(0) { length, inline in
      guard case .text(let text) = inline else { return length }
      return length + text.utf8.count
    }
  }
}
