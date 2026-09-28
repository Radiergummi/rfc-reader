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

  /// What is typed now.
  public private(set) var query = ""
  private var exact: RFCLink?
  private var hits: [DocumentID] = []
  /// The query `hits` were found for, which lags `query` while a search runs.
  private var hitsQuery = ""
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

  /// Whether the hits on screen are still those of an earlier query.
  public var isSearching: Bool {
    hitsQuery != query
  }

  /// What ↵ opens now. Nothing while the selection is a hit found for what was
  /// typed a keystroke ago: opening it would open something the reader did not ask
  /// for. The exact row belongs to what is typed now, so it never waits.
  public var openable: RFCLink? {
    guard let selected, selected == exact || !isSearching else { return nil }
    return selected
  }

  /// What was just typed, and what it resolves to exactly, if anything. A new
  /// resolution is the reader's most direct request, so it takes the selection; the
  /// same one again, after a trailing space, leaves it where the reader put it.
  public mutating func show(query: String, exact: RFCLink?) {
    self.query = query
    if query.isEmpty {
      hits = []
      hitsQuery = query
    }
    let isNew = exact != self.exact
    self.exact = exact
    if isNew, let exact {
      selected = exact
    } else {
      keepSelection()
    }
  }

  /// What the search found for `query`. Ignored when the reader has typed on since:
  /// a newer search is on its way.
  public mutating func show(hits: [DocumentID], for query: String) {
    guard query == self.query else { return }
    self.hits = hits
    hitsQuery = query
    keepSelection()
  }

  /// Arrow keys: one row up or down, stopping at either end.
  public mutating func moveSelection(by offset: Int) {
    let rows = rows
    guard !rows.isEmpty else { return }
    let current = selected.flatMap { rows.firstIndex(of: $0) } ?? 0
    selected = rows[min(max(current + offset, 0), rows.count - 1)]
  }

  /// The selected row stays selected if it is still listed; otherwise the top one is.
  private mutating func keepSelection() {
    let rows = rows
    if let selected, rows.contains(selected) { return }
    selected = rows.first
  }
}
