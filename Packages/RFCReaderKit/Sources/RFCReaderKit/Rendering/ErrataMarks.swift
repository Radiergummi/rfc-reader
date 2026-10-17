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

  public init(_ summary: ErrataSummary) {
    self.init(items: summary.items)
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
  /// held errata", "2 errata, 1 held". English, as the body is (decision "The app's
  /// chrome is localized, the reader body is not").
  public static func bodyLabel(for items: [ErrataSummary.Item]) -> String {
    let held = items.count(where: \.isHeld)
    let verified = items.count - held
    switch (verified, held) {
    case (1, 0): return "Erratum"
    case (_, 0): return "\(verified) errata"
    case (0, 1): return "Held erratum"
    case (0, _): return "\(held) held errata"
    default: return "\(verified) errata, \(held) held"
    }
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
