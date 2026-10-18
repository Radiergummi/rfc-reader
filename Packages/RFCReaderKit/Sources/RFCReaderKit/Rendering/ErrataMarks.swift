import Foundation
import RFCKit

/// Where a document's marked errata go in the reader (#387): a chip after the heading
/// of each section one names, and by the title for those naming no section the
/// document has, which are never guessed onto one. The errata are the Info pane's
/// (`ErrataSummary`), so the two cannot disagree about which are marked.
///
/// An input to the build, as the reader's settings are: the chips are text.
public struct ErrataMarks: Equatable, Sendable {
  /// Each section's errata, by its anchor, in the summary's order. An erratum naming
  /// several sections is in each.
  public let bySection: [String: [ErrataSummary.Item]]
  /// The errata naming no section the document has: the whole document's.
  public let document: [ErrataSummary.Item]

  public static let none = ErrataMarks(items: [])

  /// `document`'s marks: on the sections the reader draws, so an erratum naming a
  /// bibliography, which the reader leaves to the inspector, is the whole document's,
  /// as the Info pane lists it from the same sections. With no document, an original
  /// shown without a body, every erratum is the whole document's.
  public init(errata: [Erratum], document: RFCDocument?, locale: Locale = .interface) {
    self.init(
      items: ErrataSummary(
        errata: errata, sections: document.map { Self.drawn($0.sections) } ?? [],
        locale: locale
      ).items)
  }

  /// `sections` less those the reader does not draw (`Section.holdsOnlyReferences`),
  /// with their subsections, as `DocumentTextBuilder` leaves them out: what the Info
  /// pane finds an erratum's section in too, so it links to no section the reader
  /// left out.
  public static func drawn(_ sections: [Section]) -> [Section] {
    sections.filter { !$0.holdsOnlyReferences }.map { section in
      var section = section
      section.subsections = drawn(section.subsections)
      return section
    }
  }

  private init(items: [ErrataSummary.Item]) {
    var bySection: [String: [ErrataSummary.Item]] = [:]
    var document: [ErrataSummary.Item] = []
    for item in items {
      if item.anchors.isEmpty { document.append(item) }
      for anchor in item.anchors { bySection[anchor, default: []].append(item) }
    }
    self.bySection = bySection
    self.document = document
  }

  /// What a chip in the reader body says: "Erratum", "2 errata", "Held erratum", "2
  /// held errata", "1 erratum, 1 held". `label`'s words in English, as the body is
  /// (decision "The app's chrome is localized, the reader body is not").
  public static func bodyLabel(for items: [ErrataSummary.Item]) -> String {
    label(for: items, locale: .english)
  }

  /// The same words for the chrome, by the title, in the interface's language.
  public static func label(for items: [ErrataSummary.Item], locale: Locale = .interface)
    -> String
  {
    let held = items.count(where: \.isHeld)
    let verified = items.count - held
    if held == 0 { return String(kit: "\(verified) errata", locale: locale) }
    if verified == 0 { return String(kit: "\(held) held errata", locale: locale) }
    return String(kit: "\(verified) errata, \(held) held", locale: locale)
  }
}
