import Foundation
import RFCKit

/// Somewhere the reader can be: a document, and optionally a spot inside it.
///
/// The spot is an anchor or a section number — whatever `DocumentView` can hand to
/// `scroll(to:)`. It serves two purposes at once: on the way in it is the deep link's
/// target section, and on the way out it is where the reader had scrolled to, so
/// coming back does not dump them at the top of a 200-page RFC.
public struct Place: Hashable, Sendable {
  public let id: DocumentID
  public var section: String?

  public init(id: DocumentID, section: String? = nil) {
    self.id = id
    self.section = section
  }
}

/// One tab's back/forward stack.
///
/// A plain value type, which is the point. The reader used to keep its selection on a
/// process-wide singleton, so navigating in one tab moved every other tab with it;
/// giving each scene its own copy of this makes that impossible to express. It is
/// also why this lives in the package rather than the App target — it is a pure state
/// machine, and the App target has no test bundle.
public struct NavigationHistory: Sendable {
  public private(set) var current: Place?
  private var backward: [Place] = []
  private var forward: [Place] = []
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
  public var shown: Place? { isHidden ? nil : current }

  public var canGoBack: Bool { !backward.isEmpty }
  public var canGoForward: Bool { !forward.isEmpty }

  /// Where Back would return to, straight after a jump within the document on
  /// screen (#254): the place left behind, when it is in the same document.
  ///
  /// Nil when Back would leave the document, after stepping back or forward, and
  /// once the offer is settled: it is for undoing a jump just made, not for
  /// walking the history.
  public var returnOffer: Place? {
    guard arrivedByGoing, let current = shown, let previous = backward.last,
      previous.id == current.id
    else { return nil }
    return previous
  }

  /// Withdraws the return offer until the next jump, without moving.
  public mutating func settleReturnOffer() {
    arrivedByGoing = false
  }

  /// Go to `place`, recording `position` as the spot being left behind.
  ///
  /// Re-opening the document and section already on screen is not a navigation:
  /// clicking the same link twice must not stack two identical entries to walk back
  /// through. Striking out in a new direction drops whatever was ahead, as a browser
  /// does.
  public mutating func go(to place: Place, leaving position: String? = nil) {
    defer { isHidden = false }
    guard place != current else { return }
    // Reopening the hidden document from its row, which names no section: back
    // where it was, and not a jump to offer a way back from.
    if isHidden, place.section == nil, place.id == current?.id {
      arrivedByGoing = false
      return
    }
    if var previous = current {
      previous.section = position ?? previous.section
      backward.append(previous)
    }
    forward.removeAll()
    current = place
    arrivedByGoing = true
  }

  /// Step back, recording `position` as the spot being left behind so that going
  /// forward again returns to it.
  @discardableResult
  public mutating func goBack(leaving position: String? = nil) -> Place? {
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
  public mutating func goForward(leaving position: String? = nil) -> Place? {
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
