import RFCKit

/// The rows under the Go to RFC palette's field, and which one ↵ would open.
///
/// Two sources feed it at different speeds. What the text resolves to exactly
/// (`9110`, `BCP 14`, a link) and the registry values it names (`425`, `tls alert 70`,
/// #175) are known on the keystroke; what the search finds for it arrives a moment
/// later, off the main actor. Each replaces only its own part, so
/// the exact row never waits for the search, and the hits of the previous query stay
/// on screen until the next ones land rather than the list collapsing on every key.
public struct QuickOpenResults: Equatable, Sendable {
  /// As many rows as a palette shows before it stops being a glance.
  public static let limit = 8

  /// One row: what it opens, and the registry value it stands for, if it is one.
  ///
  /// A row rather than its link, because two registry values can open one place:
  /// every QUIC error is defined in RFC 9000, section 20.
  public struct Row: Hashable, Sendable {
    public let link: RFCLink
    public let entry: RegistryEntry?

    public init(link: RFCLink, entry: RegistryEntry? = nil) {
      self.link = link
      self.entry = entry
    }
  }

  /// What ↵ asked for: a row, and how to open it.
  public struct Opening: Equatable, Sendable {
    public let link: RFCLink
    public let activation: LinkActivation

    public init(link: RFCLink, activation: LinkActivation) {
      self.link = link
      self.activation = activation
    }
  }

  /// What a row says beside the number: the index's title for it, or why there is
  /// none. `9110` typed before the index has loaded resolves exactly, but nothing
  /// knows its title yet, and it is not missing from the index.
  ///
  /// - Parameters:
  ///   - title: The index's title for the row's document, if it has one.
  ///   - isIndexLoaded: Whether the index has loaded.
  public static func title(_ title: String?, isIndexLoaded: Bool) -> String {
    if let title { return title }
    return isIndexLoaded ? "Not in the index" : "The index is still loading"
  }

  /// What is typed now.
  public private(set) var query = ""
  /// What is typed, resolved exactly: one row, or one per member of a series.
  private var exact: [RFCLink] = []
  /// The registry values it names, each opening the current RFC that defines it.
  private var registry: [Row] = []
  private var hits: [DocumentID] = []
  /// The query `hits` were found for, which lags `query` while a search runs.
  private var hitsQuery = ""
  /// Held as the row, not its position: the rows change under it as hits arrive,
  /// and the reader's choice has to survive that.
  public private(set) var selected: Row?
  /// Whether the reader moved the selection with the arrow keys. Only then is it
  /// their choice to keep; otherwise it is the top row, whatever the top row is.
  private var isSelectionMoved = false
  /// ↵ was pressed while a search for what is typed was still running: the search
  /// opens what it selects when it lands, the way the key press asked for.
  private var pendingActivation: LinkActivation?

  public init() {}

  /// The exact resolution first, then the registry values, then every hit the
  /// exact resolution does not already name.
  public var rows: [Row] {
    var rows = current
    for id in hits where !exact.contains(where: { $0.id == id }) {
      rows.append(Row(link: RFCLink(id: id)))
    }
    return Array(rows.prefix(Self.limit))
  }

  /// The rows that belong to what is typed now: the exact resolution and the
  /// registry values, which never wait for a search.
  private var current: [Row] {
    exact.map { Row(link: $0) } + registry
  }

  /// Whether the hits on screen are still those of an earlier query.
  public var isSearching: Bool {
    hitsQuery != query
  }

  /// What ↵ opens now. Nothing while the selection is a hit found for what was
  /// typed a keystroke ago: opening it would open something the reader did not ask
  /// for. The exact and registry rows belong to what is typed now, so they never
  /// wait.
  public var openable: RFCLink? {
    guard let selected, current.contains(selected) || !isSearching else { return nil }
    return selected.link
  }

  /// What was just typed, and what it resolves to exactly, if anything. A new
  /// resolution is the reader's most direct request, so it takes the selection; the
  /// same one again, after a trailing space, leaves it where the reader put it.
  ///
  /// A series is listed as its members, each a row that opens what it names: `BCP 14`
  /// stands for RFC 2119 and RFC 8174, and a single row could only open one of them.
  ///
  /// - Parameters:
  ///   - members: The series' current members, empty for an RFC, or while the index
  ///     that knows them is still loading.
  ///   - registry: The registry values the query names. One that cites no RFC has
  ///     nowhere to open, and is not listed.
  ///   - isObsolete: Whether the index says an RFC is obsoleted, so that a registry
  ///     value citing several opens the current one.
  public mutating func show(
    query: String, exact: RFCLink?, members: [DocumentID] = [], registry: [RegistryEntry] = [],
    isObsolete: (DocumentID) -> Bool = { _ in false }
  ) {
    self.query = query
    // Typing on after ↵ is a change of mind.
    pendingActivation = nil
    if query.isEmpty {
      hits = []
      hitsQuery = query
    } else if let number = IndexSearch.number(in: query) {
      // Which of the earlier hits a number still matches is known without the
      // search, so those it does not go now rather than when its hits land: shown
      // for that moment, each pushed the rows below it down and back up. What stays
      // keeps its order.
      hits.removeAll { !IndexSearch.matches($0, number: number) }
    }
    let rows: [RFCLink]
    if let exact, !members.isEmpty {
      rows = members.map { RFCLink(id: $0, section: exact.section, anchor: exact.anchor) }
    } else {
      rows = exact.map { [$0] } ?? []
    }
    let registryRows = registry.compactMap { entry in
      entry.reference(isObsolete: isObsolete).map { Row(link: $0, entry: entry) }
    }
    let isNew = rows != self.exact || registryRows != self.registry
    self.exact = rows
    self.registry = registryRows
    if isNew, let first = current.first {
      selected = first
      isSelectionMoved = false
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
    let next = rows[min(max(current + offset, 0), rows.count - 1)]
    // A press that stops at either end chooses nothing.
    guard next != selected else { return }
    selected = next
    isSelectionMoved = true
  }

  /// A row the reader moved to stays selected if it is still listed; otherwise the
  /// top one is.
  private mutating func keepSelection() {
    let rows = rows
    if isSelectionMoved, let selected, rows.contains(selected) { return }
    selected = rows.first
    isSelectionMoved = false
  }
}
