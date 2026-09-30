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
    let place = HistoryEntry(id: place.id, section: place.section.map(anchor))
    let position = position.map(anchor)
    if let current, place == HistoryEntry(id: current.id, section: current.section.map(anchor)) {
      guard let section = place.section else { return nil }
      let reported = places?.section(of: section) ?? section
      if position == nil || position == section || position == reported {
        self.current = place
        return place
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
    guard let previous = backward.popLast() else { return nil }
    if var leaving = current {
      leaving.section = position ?? leaving.section
      forward.append(leaving)
    }
    current = previous
    arrivedByGoing = false
    isHidden = false
    return previous
  }

  /// The mirror of `goBack(leaving:)`.
  @discardableResult
  public mutating func goForward(leaving position: String? = nil) -> HistoryEntry? {
    guard let next = forward.popLast() else { return nil }
    if var leaving = current {
      leaving.section = position ?? leaving.section
      backward.append(leaving)
    }
    current = next
    arrivedByGoing = false
    isHidden = false
    return next
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
}
