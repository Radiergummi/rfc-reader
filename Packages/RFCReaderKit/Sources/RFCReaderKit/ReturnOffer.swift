import RFCKit

/// What the offer to return from a jump within a document says (#254).
public enum ReturnOffer {
  /// "Back to §4.2" for a numbered section, "Back to Top" before the reader had
  /// scrolled anywhere, and plain "Back" for a place without a number, such as the
  /// abstract, or in a document not yet loaded.
  ///
  /// A place's section is whatever the history recorded: usually the anchor the
  /// reader had scrolled to, but a deep link or a section link can record the
  /// number itself. Resolved through `RFCDocument.anchor(forPlace:)`, which is how
  /// the reader jumps to it, so the label names the section a tap on it goes to.
  public static func title(for place: Place, in document: RFCDocument?) -> String {
    guard let section = place.section else { return "Back to Top" }
    guard let document,
      let number = document.section(anchor: document.anchor(forPlace: section))?.number
    else { return "Back" }
    return "Back to §\(number)"
  }
}
