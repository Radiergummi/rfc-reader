import Foundation
import RFCKit

/// One tab's back/forward stack.
///
/// A plain value type, which is the point. The reader used to keep its selection on a
/// process-wide singleton, so navigating in one tab moved every other tab with it;
/// giving each scene its own copy of this makes that impossible to express. It is
/// also why this lives in the package rather than the App target — it is a pure state
/// machine, and the App target has no test bundle.
public struct NavigationHistory: Sendable {
  public private(set) var current: HistoryEntry?
  private var backward: [HistoryEntry] = []
  private var forward: [HistoryEntry] = []
  /// Whether the last move struck out somewhere new, rather than stepping back or
  /// forward through what was already here.
  private var arrivedByGoing = false
  /// Whether `current` was put away with `hide()`.
  private var isHidden = false

  public init() {}

  /// What is on screen: `current`, unless it was hidden.
  ///
  /// This is what a list's selection reads, so it has to be able to say "nothing"
  /// while the history still holds where the reader was (#261).
  public var shown: HistoryEntry? { isHidden ? nil : current }

  public var canGoBack: Bool { !backward.isEmpty }
  public var canGoForward: Bool { !forward.isEmpty }

  /// Where Back would return to, straight after a jump within the document on
  /// screen (#254): the place left behind, when it is in the same document.
  ///
  /// Nil when Back would leave the document, after stepping back or forward, and
  /// once the offer is settled: it is for undoing a jump just made, not for
  /// walking the history.
  public var returnOffer: HistoryEntry? {
    guard arrivedByGoing, let current = shown, let previous = backward.last,
      previous.id == current.id
    else { return nil }
    return previous
  }

  /// Withdraws the return offer until the next jump, without moving.
  public mutating func settleReturnOffer() {
    arrivedByGoing = false
  }

  /// Go to `place`, recording `position` as the spot being left behind, and return
  /// the place to arrive at: nil when there is nowhere to move.
  ///
  /// Going to the current place while the reader is still there is not a
  /// navigation: clicking the same link twice must not stack two identical entries
  /// to walk back through, so the history does not move and the place is returned
  /// only to scroll to. Still there means `position`, where the reader is, not only
  /// where the tab was sent: sent to §4.2 and read on to §9, a link to §4.2 is a
  /// navigation, and Back returns to §9 (#482). Striking out in a new direction
  /// drops whatever was ahead, as a browser does.
  ///
  /// `places`, the document on screen's, resolves a section number and an anchor
  /// to one spelling, the anchor, which is the one compared and recorded.
  @discardableResult
  public mutating func go(
    to place: HistoryEntry, leaving position: String? = nil, in places: DocumentPlaces? = nil
  ) -> HistoryEntry? {
    defer { isHidden = false }
    let anchor = { (section: String) in places?.anchor(for: section) ?? section }
    let place = HistoryEntry(
      id: place.id, section: place.section.map(anchor), arrival: place.arrival)
    let position = position.map(anchor)
    if let current, place.id == current.id, place.section == current.section.map(anchor) {
      guard let section = place.section else { return nil }
      let reported = places?.section(of: section) ?? section
      if position == nil || position == section || position == reported {
        // Not a navigation, so not a new way of arriving either: a jump to where
        // the reader is must not reach back past an arrival from outside (#263).
        let arrived = HistoryEntry(id: place.id, section: section, arrival: current.arrival)
        self.current = arrived
        return arrived
      }
    }
    // Reopening the hidden document from its row, which names no section: back
    // where it was, and not a jump to offer a way back from.
    if isHidden, place.section == nil, place.id == current?.id {
      arrivedByGoing = false
      return nil
    }
    if var previous = current {
      previous.section = position ?? previous.section.map(anchor)
      backward.append(previous)
    }
    forward.removeAll()
    current = place
    arrivedByGoing = true
    return place
  }

  /// Step back, recording `position` as the spot being left behind so that going
  /// forward again returns to it.
  @discardableResult
  public mutating func goBack(leaving position: String? = nil) -> HistoryEntry? {
    step(from: \.backward, to: \.forward, leaving: position)
  }

  /// The mirror of `goBack(leaving:)`.
  @discardableResult
  public mutating func goForward(leaving position: String? = nil) -> HistoryEntry? {
    step(from: \.forward, to: \.backward, leaving: position)
  }

  /// One step through what was already here: the place on top of `source` becomes
  /// current, and the one left, at `position`, goes on top of `destination`.
  private mutating func step(
    from source: WritableKeyPath<Self, [HistoryEntry]>,
    to destination: WritableKeyPath<Self, [HistoryEntry]>, leaving position: String?
  ) -> HistoryEntry? {
    guard let arrived = self[keyPath: source].popLast() else { return nil }
    if var leaving = current {
      leaving.section = position ?? leaving.section
      self[keyPath: destination].append(leaving)
    }
    current = arrived
    arrivedByGoing = false
    isHidden = false
    return arrived
  }

  // MARK: - The readers stacked on iOS (#263)

  /// The documents of the readers stacked for what is on screen, oldest first: one
  /// for each run of places in one document since the tab last arrived somewhere
  /// from outside, and none while nothing is on screen. `ReaderPath` makes the
  /// stack of them.
  ///
  /// From the history rather than beside it, so that the system back button and
  /// Back cannot disagree about where they go.
  public var stackedDocuments: [DocumentID] {
    guard let shown else { return [] }
    var documents = [shown.id]
    var arrival = shown.arrival
    for entry in backward.reversed() {
      guard arrival == .citation else { break }
      if entry.id != documents.last { documents.append(entry.id) }
      arrival = entry.arrival
    }
    return documents.reversed()
  }

  /// Steps back until `count` readers are stacked, recording `position` as the spot
  /// left in the reader on top, and returns the place arrived at: nil when there
  /// were no more than that, or no fewer than one is asked for.
  ///
  /// The stack's own back, the system back button or a swipe from the edge: a reader
  /// popped goes with every jump made in it, and forward returns to it, where it was
  /// left.
  @discardableResult
  public mutating func popReaders(to count: Int, leaving position: String? = nil)
    -> HistoryEntry?
  {
    guard count >= 1 else { return nil }
    var arrived: HistoryEntry?
    var position = position
    while stackedDocuments.count > count, let place = goBack(leaving: position) {
      arrived = place
      // Only the reader on top was somewhere other than where its entry says.
      position = nil
    }
    return arrived
  }

  /// Put the current place away without leaving it: going back to the list on an
  /// iPhone, or deselecting the row on a Mac.
  ///
  /// The place stays current, so Back and Forward work from the list, and going
  /// to a new place records it as the one left behind, as it would had it stayed
  /// on screen.
  public mutating func hide() {
    isHidden = true
  }

  // MARK: - Across launches

  /// The history as a tab keeps it across launches (#155): the places on either
  /// side of the current one, and whether it is hidden.
  public struct Snapshot: Codable, Equatable, Sendable {
    /// Oldest first, as `backward` and `forward` are: each is a stack whose last
    /// entry is the place next to the current one.
    var backward: [HistoryEntry]
    var current: HistoryEntry?
    var forward: [HistoryEntry]
    var isHidden: Bool
  }

  /// Restores a history from `snapshot`. Restoring is not arriving, so there is no
  /// jump to offer a way back from.
  public init(_ snapshot: Snapshot) {
    backward = snapshot.backward
    current = snapshot.current
    forward = snapshot.forward
    isHidden = snapshot.isHidden
  }

  /// At most `limit` places, the current one and those nearest it: as many ahead as
  /// fit beside half the rest behind, and the rest behind. A tab read in all day
  /// keeps a snapshot of the same size as one opened a minute ago.
  public func snapshot(limit: Int = SceneSnapshot.historyLimit) -> Snapshot {
    let room = max(limit - (current == nil ? 0 : 1), 0)
    let ahead = min(forward.count, max(room - backward.count, room / 2))
    let behind = min(backward.count, room - ahead)
    return Snapshot(
      backward: Array(backward.suffix(behind)), current: current,
      forward: Array(forward.suffix(ahead)), isHidden: isHidden)
  }
}
