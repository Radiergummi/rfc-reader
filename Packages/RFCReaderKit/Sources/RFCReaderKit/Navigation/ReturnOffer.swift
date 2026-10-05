import Foundation
import RFCKit

/// What the offer to return from a jump within a document says (#254).
public enum ReturnOffer {
  /// "Back to § 4.2" for a numbered section, "Back to Appendix 1" for an appendix
  /// numbered like one (#429), "Back to Top" before the reader had scrolled
  /// anywhere, and plain "Back" for a place without a number, such as the abstract,
  /// or in a document not yet loaded.
  ///
  /// A place's section is whatever the history recorded: usually the anchor the
  /// reader had scrolled to, but a deep link or a section link can record the
  /// number itself. Resolved through `RFCDocument.anchor(forPlace:)`, which is how
  /// the reader jumps to it, so the label names the section a tap on it goes to.
  public static func title(
    for place: HistoryEntry, in document: RFCDocument?, locale: Locale = .interface
  ) -> String {
    guard let section = place.section else { return String(kit: "Back to Top", locale: locale) }
    guard let document,
      let sectionPlace = document.section(anchor: document.anchor(forPlace: section))?.place
    else { return String(kit: "Back", locale: locale) }
    return String(kit: "Back to \(PlaceName.abbreviated(sectionPlace))", locale: locale)
  }
}
