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

  public init() {}

  public var canGoBack: Bool { !backward.isEmpty }
  public var canGoForward: Bool { !forward.isEmpty }

  /// Go to `place`, recording `position` as the spot being left behind.
  ///
  /// Re-opening the document and section already on screen is not a navigation:
  /// clicking the same link twice must not stack two identical entries to walk back
  /// through. Striking out in a new direction drops whatever was ahead, as a browser
  /// does.
  public mutating func go(to place: Place, leaving position: String? = nil) {
    guard place != current else { return }
    if var previous = current {
      previous.section = position ?? previous.section
      backward.append(previous)
    }
    forward.removeAll()
    current = place
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
    return next
  }
}
