import Foundation

/// The one citation a piece of selected text makes, as a link: what the Services
/// "Replace with RFC Link" and "Open in RFC Reader" act on (#195).
///
/// The document is read by `InlineLinker`, as the parsers read prose, so a citation
/// the reader links and one these Services link are the same citation. What the
/// linker leaves as text may still say where in that document: `RFC 9110 §8.3`,
/// `RFC 9110, Section 8.3` and `RFC 9110, Appendix B` name the place beside the
/// document rather than in the `Section 8.3 of RFC 9110` shape the linker reads, so
/// the place is read from the rest of the selection here. The linker itself is left
/// alone: what it reads in prose is a parser change, with a corpus run of its own.
public enum CitationLink {
  /// Nil unless the selection cites exactly one document, at no more than one place:
  /// `RFC 9110 and RFC 9111`, or `RFC 9110 §8.3 and §8.4`, leave the link in doubt.
  public static func link(in selection: String) -> RFCLink? {
    let inlines = InlineLinker(sectionNumbers: [], referenceTargets: [:]).link(selection)
    var cited: Set<RFCLink> = []
    var rest = ""
    for inline in inlines {
      switch inline {
      case .crossReference(let reference):
        guard case .document(let id, let section, _) = reference.target else { return nil }
        cited.insert(RFCLink(id: id, section: section))
      case .text(let text):
        rest += text
      default:
        continue
      }
    }

    // A document the linker reads only inside a bracket, `[BCP14]`, selected bare.
    if cited.isEmpty, let id = DocumentID(label: selection) {
      cited.insert(RFCLink(id: id))
    }
    guard cited.count == 1, var link = cited.first else { return nil }

    // A plural names more than one place, and a section the linker read already
    // is one place more.
    guard rest.firstMatch(of: pluralPattern) == nil else { return nil }
    let sections = rest.matches(of: sectionPattern).map { String($0.number) }
    let appendices = rest.matches(of: appendixPattern).map {
      SectionAnchor.anchor(forAppendixNumber: String($0.number))
    }
    let places = sections + appendices
    guard places.count <= 1 else { return nil }
    if let place = places.first {
      guard link.section == nil else { return nil }
      link.section = place
    }
    return link
  }

  /// What "Replace with RFC Link" puts in place of `selection`: the link, between
  /// whatever white space the selection began and ended with, which the cursor caught
  /// and the text around it still needs. Nil when `link(in:)` is.
  public static func replacement(for selection: String) -> String? {
    guard let link = link(in: selection) else { return nil }
    let leading = selection.prefix { $0.isWhitespace }
    let trailing = selection.reversed().prefix { $0.isWhitespace }.reversed()
    return leading + link.appURL.absoluteString + String(trailing)
  }

  /// `§8.3`, `§ 8.3`, `Section 8.3`.
  private static let sectionPattern = Pattern(#/(?:§|\bSection)\s*(?<number>\d+(?:\.\d+)*)/#)
  /// `Appendix B`, `Appendix A.1`, and the `Appendix 1` of the older half of the
  /// series.
  private static let appendixPattern = Pattern(
    #/\bAppendix\s+(?<number>[A-Z](?:\.\d+)*|\d+(?:\.\d+)*)\b/#)
  private static let pluralPattern = Pattern(#/§§|\bSections\b|\bAppendices\b/#)
}
