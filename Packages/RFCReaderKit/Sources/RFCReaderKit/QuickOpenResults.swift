import RFCKit

/// The rows under the Go to RFC palette's field, and which one ↵ would open.
///
/// Two sources feed it at different speeds. What the text resolves to exactly
/// (`9110`, `BCP 14`, a link) is known on the keystroke; what the search finds for it
/// arrives a moment later, off the main actor. Each replaces only its own part, so
/// the exact row never waits for the search, and the hits of the previous query stay
/// on screen until the next ones land rather than the list collapsing on every key.
public struct QuickOpenResults: Equatable, Sendable {
  /// As many rows as a palette shows before it stops being a glance.
  public static let limit = 8

  private var exact: RFCLink?
  private var hits: [DocumentID] = []
  /// Held as the row, not its position: the rows change under it as hits arrive,
  /// and the reader's choice has to survive that.
  public private(set) var selected: RFCLink?

  public init() {}

  /// The exact resolution first, then every hit it does not already name.
  public var rows: [RFCLink] {
    var rows = exact.map { [$0] } ?? []
    for id in hits where id != exact?.id {
      rows.append(RFCLink(id: id))
    }
    return Array(rows.prefix(Self.limit))
  }

  /// What was just typed resolves to this, or to nothing. A resolution is the
  /// reader's most direct request, so it takes the selection.
  public mutating func show(exact: RFCLink?) {
    self.exact = exact
    if let exact {
      selected = exact
    } else {
      keepSelection()
    }
  }

  public mutating func show(hits: [DocumentID]) {
    self.hits = hits
    keepSelection()
  }

  /// Arrow keys: one row up or down, stopping at either end.
  public mutating func moveSelection(by offset: Int) {
    let rows = rows
    guard !rows.isEmpty else { return }
    let current = selected.flatMap { rows.firstIndex(of: $0) } ?? 0
    selected = rows[min(max(current + offset, 0), rows.count - 1)]
  }

  /// The pointer: a row it is over, when it is one of the rows.
  public mutating func select(_ link: RFCLink) {
    guard rows.contains(link) else { return }
    selected = link
  }

  /// The selected row stays selected if it is still listed; otherwise the top one is.
  private mutating func keepSelection() {
    let rows = rows
    if let selected, rows.contains(selected) { return }
    selected = rows.first
  }
}
