import Foundation

/// A request to scroll somewhere, carrying its own identity.
///
/// Not a bare `String?`: a reader can navigate to the same section twice in a row
/// — back, then forward again, or the same contents row clicked twice — and an
/// `onChange` watching the section alone would see no change and never scroll.
public struct ScrollRequest: Equatable, Sendable {
  public let section: String
  /// A place in the document on screen, which has no entry in the history yet:
  /// the reader gives it one if its document holds the place, and otherwise moves
  /// nothing (#276). Only the reader can tell, having the build, and only it can
  /// say that `4.2` and `section-4.2` are the same place (#482).
  public let isUnrecorded: Bool
  /// A return to a reader the stack on iOS kept below its top, which is where it
  /// was left (#263): only a reader made again, having been let go, goes there.
  public let isToKeptReader: Bool
  private let issue = UUID()

  public init(section: String, isUnrecorded: Bool = false, isToKeptReader: Bool = false) {
    self.section = section
    self.isUnrecorded = isUnrecorded
    self.isToKeptReader = isToKeptReader
  }
}

/// One tab's scroll request, and whoever waits for the jump it asked for (#482).
///
/// A script's `jump to section` waits until its next command can find the jump in
/// the history: until the reader has recorded it, which replaces the request with
/// the one to scroll there, until anything else replaces the request before the
/// reader got to it, or until the reader settles that very request, having done
/// what else it will with the place.
///
/// Every change returns the waiter whose wait it ended, for the caller to call once
/// the change is published. `Waiter` is what the caller runs; a test passes a name.
public struct ScrollRequests<Waiter> {
  /// What the reader on screen is asked to scroll to.
  public private(set) var current: ScrollRequest?
  private var waiting: (request: ScrollRequest, waiter: Waiter)?

  public init() {}

  /// Arrived at a place in the history: scroll to its section, if it names one.
  /// `inKeptReader` for a reader the stack on iOS kept below its top (#263).
  public mutating func arrive(at section: String?, inKeptReader: Bool = false) -> Waiter? {
    replace(with: section.map { ScrollRequest(section: $0, isToKeptReader: inKeptReader) })
  }

  /// A jump within the document on screen, handed to the reader unrecorded, which
  /// `waiter` waits for. With no document on screen there is nothing to jump in: the
  /// request stays as it was, and the wait is over at once.
  public mutating func jump(
    to section: String, inDocumentOnScreen: Bool, waiter: Waiter
  ) -> Waiter? {
    guard inDocumentOnScreen else { return waiter }
    let request = ScrollRequest(section: section, isUnrecorded: true)
    let ended = replace(with: request)
    waiting = (request, waiter)
    return ended
  }

  /// Goes `history` to `place`, as `NavigationHistory.go(to:leaving:in:)` does, and
  /// asks the reader to scroll to where it arrived. Returns the place arrived at,
  /// nil when the history did not move, and the waiter whose wait that ended.
  ///
  /// Where the history did not move, there is nothing to scroll to. If that was the
  /// hidden document reopened from its row, the last request is an earlier
  /// arrival's, and the reader made again for the document would take it over its
  /// reading position, so it is cleared (#508). A reader still on screen keeps its
  /// own, which may be a jump a script waits on.
  public mutating func go(
    to place: HistoryEntry, in history: inout NavigationHistory, leaving position: String?,
    places: DocumentPlaces? = nil
  ) -> (arrived: HistoryEntry?, ended: Waiter?) {
    let reopening = history.shown == nil
    if let arrived = history.go(to: place, leaving: position, in: places) {
      return (arrived, arrive(at: arrived.section))
    }
    return (nil, reopening ? replace(with: nil) : nil)
  }

  /// The reader has done what it will with `request`, where that recorded nothing:
  /// a bibliography entry shown, a place the document does not hold, or a document
  /// that failed to load. A request already replaced settles nothing.
  public mutating func settle(_ request: ScrollRequest) -> Waiter? {
    guard let waiting, waiting.request == request else { return nil }
    self.waiting = nil
    return waiting.waiter
  }

  private mutating func replace(with request: ScrollRequest?) -> Waiter? {
    current = request
    guard let waiting, waiting.request != request else { return nil }
    self.waiting = nil
    return waiting.waiter
  }
}
