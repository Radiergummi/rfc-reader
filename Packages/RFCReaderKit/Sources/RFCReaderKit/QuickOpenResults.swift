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

  /// What ↵ asked for: a row, and how to open it.
  public struct Opening: Equatable, Sendable {
    public let link: RFCLink
    public let activation: LinkActivation

    public init(link: RFCLink, activation: LinkActivation) {
      self.link = link
      self.activation = activation
    }
  }

  /// What is typed now.
  public private(set) var query = ""
  /// What is typed, resolved exactly: one row, or one per member of a series.
  private var exact: [RFCLink] = []
  private var hits: [DocumentID] = []
  /// The query `hits` were found for, which lags `query` while a search runs.
  private var hitsQuery = ""
  /// Held as the row, not its position: the rows change under it as hits arrive,
  /// and the reader's choice has to survive that.
  public private(set) var selected: RFCLink?
  /// ↵ was pressed while a search for what is typed was still running: the search
  /// opens what it selects when it lands, the way the key press asked for.
  private var pendingActivation: LinkActivation?

  public init() {}

  /// The exact resolution first, then every hit it does not already name.
  public var rows: [RFCLink] {
    var rows = exact
    for id in hits where !exact.contains(where: { $0.id == id }) {
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
    guard let selected, exact.contains(selected) || !isSearching else { return nil }
    return selected
  }

  /// What was just typed, and what it resolves to exactly, if anything. A new
  /// resolution is the reader's most direct request, so it takes the selection; the
  /// same one again, after a trailing space, leaves it where the reader put it.
  ///
  /// A series is listed as its members, each a row that opens what it names: `BCP 14`
  /// stands for RFC 2119 and RFC 8174, and a single row could only open one of them.
  ///
  /// - Parameter members: The series' current members, empty for an RFC, or while
  ///   the index that knows them is still loading.
  public mutating func show(query: String, exact: RFCLink?, members: [DocumentID] = []) {
    self.query = query
    // Typing on after ↵ is a change of mind.
    pendingActivation = nil
    if query.isEmpty {
      hits = []
      hitsQuery = query
    }
    let rows: [RFCLink]
    if let exact, !members.isEmpty {
      rows = members.map { RFCLink(id: $0, section: exact.section) }
    } else {
      rows = exact.map { [$0] } ?? []
    }
    let isNew = rows != self.exact
    self.exact = rows
    if isNew, let first = rows.first {
      selected = first
    } else {
      keepSelection()
    }
  }

  /// What the search found for `query`. Ignored when the reader has typed on since:
  /// a newer search is on its way.
  ///
  /// - Returns: What to open now, when ↵ was waiting for these hits.
  @discardableResult
  public mutating func show(hits: [DocumentID], for query: String) -> Opening? {
    guard query == self.query else { return nil }
    self.hits = hits
    hitsQuery = query
    keepSelection()
    guard let activation = pendingActivation else { return nil }
    pendingActivation = nil
    return openable.map { Opening(link: $0, activation: activation) }
  }

  /// ↵: the selection, if it can be opened now. If it is a hit of an earlier query
  /// instead, the key press is kept for the search still running, and
  /// `show(hits:for:)` returns it once that search lands.
  public mutating func activate(_ activation: LinkActivation) -> Opening? {
    if let openable {
      return Opening(link: openable, activation: activation)
    }
    if isSearching {
      pendingActivation = activation
    }
    return nil
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
