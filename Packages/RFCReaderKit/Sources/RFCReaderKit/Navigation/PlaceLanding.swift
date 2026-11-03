import RFCKit

/// Where a place handed to the reader lands -- a deep link's section, Back or
/// Forward's, or a script's `jump to section` -- given what the reader shows.
public enum PlaceLanding: Equatable, Sendable {
  /// The reader shows no text that holds the place: an RFC read as its original
  /// (#1031). A pointer's loaded text holds places, but is not the RFC, and its
  /// original-only page does not show it, so nothing scrolls there, nor is a jump
  /// recorded into it.
  case notShown
  /// Where `LinkDestination.landing(at:in:bibliography:anchors:)` puts the place in
  /// the text shown.
  case inText(LinkDestination)

  /// `kind` is why the RFC is read as its original, nil when it is read as its text:
  /// the condition under which the reader offers no sections either
  /// (`PublishedOriginalPage.offersSections(kind:)`). Nil while an RFC read as its
  /// text has no build, `places`, to find the place in; one read as its original
  /// needs none to say the place is not shown.
  public static func landing(
    at place: String, in places: DocumentPlaces?, bibliography: [ReferenceGroup],
    readAsOriginal kind: PublishedOriginalPage.Kind?
  ) -> PlaceLanding? {
    guard PublishedOriginalPage.offersSections(kind: kind) else { return .notShown }
    guard let places else { return nil }
    return .inText(
      LinkDestination.landing(
        at: place, in: places.document, bibliography: bibliography, anchors: places.anchors))
  }
}
