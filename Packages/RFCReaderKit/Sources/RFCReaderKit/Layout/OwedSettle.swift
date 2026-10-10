/// Whether the end of a live resize settles the reader's place or only pins it (#542).
///
/// A live resize pins on estimates, and the rebuild for the new column settles. A
/// rebuild that lands while the resize still runs is pinned too, and has no later
/// settle of its own: the window resized while the inspector's closing animation is
/// one, which left the reader in section 1. That settle is owed until any settle is
/// made. A change of column owes nothing by itself, since its rebuild follows, and the
/// end of a resize that owes nothing pins, so the rebuild after it is not settled
/// twice.
public struct OwedSettle: Sendable, Equatable {
  public enum ResizeEnd: Sendable, Equatable {
    case pin
    case settle
  }

  public private(set) var isOwed = false

  public init() {}

  /// A rebuild or a refold was pinned on estimates during a live resize.
  public mutating func pinnedRebuild() {
    isOwed = true
  }

  /// The place was settled, whoever settled it.
  public mutating func settled() {
    isOwed = false
  }

  /// What the end of a live resize does with the place.
  public var atResizeEnd: ResizeEnd { isOwed ? .settle : .pin }
}
