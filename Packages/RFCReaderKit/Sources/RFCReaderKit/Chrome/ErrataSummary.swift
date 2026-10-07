import Foundation
import RFCKit

/// What the Info pane lists of a document's errata (#387).
///
/// The verified ones and those held for the next revision are listed, each with its
/// status, type, the place it names, and the original and corrected text: those
/// naming no section first, as the whole document's, then in the order they were
/// submitted. Reported and rejected ones are only counted, and the RFC Editor's page
/// lists them all (decision on #387).
public struct ErrataSummary: Equatable, Sendable {
  public struct Item: Equatable, Sendable, Identifiable {
    public let id: Int
    /// "Verified", "Held for Document Update".
    public let status: String
    /// "Technical", "Editorial".
    public let type: String
    /// "Section 4.1", "Sections 7.8 and 7.9", what the reporter wrote when it names no
    /// section ("Figure 15", "Abstract"), or "Whole document".
    public let place: String
    /// The first section it names that the document has, to go to; nil when it names
    /// none, or none the document has.
    public let anchor: String?
    public let original: String
    public let corrected: String
    public let notes: String
    /// The erratum's own page on the RFC Editor's site.
    public let page: URL
  }

  public let items: [Item]
  /// "2 not yet reviewed and 1 rejected": the errata not listed; nil when there are
  /// none.
  public let notListed: String?

  /// - Parameter sections: The document's top-level sections, which a section is
  ///   found in by its place, as a citation finds it (`Section.place`); empty before
  ///   its body has loaded.
  public init(errata: [Erratum], sections: [Section], locale: Locale = .interface) {
    var anchors: [String: String] = [:]
    func visit(_ section: Section) {
      if let place = section.place, anchors[place] == nil { anchors[place] = section.anchor }
      section.subsections.forEach(visit)
    }
    sections.forEach(visit)

    let marked = errata.filter(\.status.isMarked)
    let ordered = marked.filter(\.sections.isEmpty) + marked.filter { !$0.sections.isEmpty }
    items = ordered.map { erratum in
      Item(
        id: erratum.id,
        status: Self.name(of: erratum.status, locale: locale),
        type: Self.name(of: erratum.type, locale: locale),
        place: erratum.sections.isEmpty
          ? Self.place(written: erratum.section, locale: locale)
          : Self.place(of: erratum.sections, locale: locale),
        anchor: erratum.sections.lazy.compactMap { anchors[$0] }.first,
        original: erratum.original,
        corrected: erratum.corrected,
        notes: erratum.notes,
        page: erratum.page)
    }

    let reported = errata.count { $0.status == .reported }
    let rejected = errata.count { $0.status == .rejected }
    var counts: [String] = []
    if reported > 0 { counts.append(String(kit: "\(reported) not yet reviewed", locale: locale)) }
    if rejected > 0 { counts.append(String(kit: "\(rejected) rejected", locale: locale)) }
    notListed = counts.isEmpty ? nil : counts.formatted(.list(type: .and).locale(locale))
  }

  private static func name(of status: Erratum.Status, locale: Locale) -> String {
    switch status {
    case .verified: String(kit: "Verified", locale: locale)
    case .heldForDocumentUpdate: String(kit: "Held for Document Update", locale: locale)
    case .reported: String(kit: "Reported", locale: locale)
    case .rejected: String(kit: "Rejected", locale: locale)
    case .other(let written): written
    }
  }

  private static func name(of type: Erratum.Kind, locale: Locale) -> String {
    switch type {
    case .technical: String(kit: "Technical", locale: locale)
    case .editorial: String(kit: "Editorial", locale: locale)
    case .other(let written): written
    }
  }

  /// The place an erratum naming no section names, as the reporter wrote it,
  /// `Figure 15` or `Abstract`, without a colon after it; "Whole document" for none,
  /// or for the feed's `GLOBAL`.
  private static func place(written field: String, locale: Locale) -> String {
    var written = field.trimmingCharacters(in: .whitespacesAndNewlines)
    while written.last == ":" { written.removeLast() }
    guard !written.isEmpty, written.uppercased() != "GLOBAL" else {
      return String(kit: "Whole document", locale: locale)
    }
    return written
  }

  /// The place the sections are, as a reader names them: "Section 4.1", "Appendix
  /// A.2", "Appendix 1" for `appendix-1`, "Sections 7.8, 7.9, and 8.4.1", "Appendix B
  /// and Section 2".
  private static func place(of sections: [String], locale: Locale) -> String {
    // Each as an appendix or not, and the identifier it is named by.
    let named = sections.map { section -> (isAppendix: Bool, identifier: String) in
      if section.hasPrefix("appendix-") { return (true, String(section.dropFirst(9))) }
      return (section.first?.isLetter == true, section)
    }
    guard let first = named.first else { return String(kit: "Whole document", locale: locale) }
    if named.count == 1 {
      return first.isAppendix
        ? String(kit: "Appendix \(first.identifier)", locale: locale)
        : String(kit: "Section \(first.identifier)", locale: locale)
    }
    let list = named.map(\.identifier).formatted(.list(type: .and).locale(locale))
    if named.allSatisfy(\.isAppendix) { return String(kit: "Appendices \(list)", locale: locale) }
    if !named.contains(where: \.isAppendix) {
      return String(kit: "Sections \(list)", locale: locale)
    }
    return sections.map { place(of: [$0], locale: locale) }
      .formatted(.list(type: .and).locale(locale))
  }
}
