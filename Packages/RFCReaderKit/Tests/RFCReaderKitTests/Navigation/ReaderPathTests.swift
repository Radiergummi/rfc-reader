import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The readers stacked in a tab's detail column on iOS (#263): a projection of the
/// tab's history, so that the stack and the history cannot tell two stories. A
/// citation followed in a reader pushes a reader; a jump within a document does not;
/// anything from outside the reader starts the stack again.
@Suite("Reader path")
struct ReaderPathTests {
  /// A place arrived at from outside a reader: a row in the list, a deep link, Go to
  /// RFC.
  private func place(_ number: Int, _ section: String? = nil) -> HistoryEntry {
    HistoryEntry(id: .rfc(number), section: section)
  }

  /// A place arrived at by following a link inside a reader: a citation, or a jump
  /// within the document.
  private func cited(_ number: Int, _ section: String? = nil) -> HistoryEntry {
    HistoryEntry(id: .rfc(number), section: section, arrival: .citation)
  }

  private func documents(_ history: NavigationHistory) -> [DocumentID] {
    ReaderPath(history).readers.map(\.id)
  }

  /// RFC 9110, a citation of RFC 9111 in it, and a citation of RFC 9112 in that.
  private func chain() -> NavigationHistory {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: cited(9111))
    history.go(to: cited(9112))
    return history
  }

  // MARK: - What pushes a reader

  @Test func `each citation followed pushes a reader`() {
    let path = ReaderPath(chain())
    #expect(path.readers.map(\.id) == [.rfc(9110), .rfc(9111), .rfc(9112)])
    #expect(path.readers.map(\.depth) == [0, 1, 2])
  }

  @Test func `a jump within a document pushes no reader`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: cited(9111))
    history.go(to: cited(9111, "section-4"), leaving: "section-1")
    #expect(documents(history) == [.rfc(9110), .rfc(9111)])
  }

  /// A row in the list, Go to RFC, or a link from another app (#263, decision 1):
  /// a new task, not a step in the one on screen.
  @Test func `an arrival from outside starts the stack again`() {
    var history = chain()
    history.go(to: place(8446))
    let path = ReaderPath(history)
    #expect(path.readers.map(\.id) == [.rfc(8446)])
    #expect(path.readers.map(\.depth) == [0])
  }

  @Test func `an arrival from outside at a document in the stack starts it again too`() {
    var history = chain()
    history.go(to: place(9110))
    #expect(documents(history) == [.rfc(9110)])
  }

  /// Two readers of one document are two readers, each where it was left.
  @Test func `a document cited again is a reader of its own`() {
    var history = chain()
    history.go(to: cited(9110))
    let path = ReaderPath(history)
    #expect(path.readers.map(\.id) == [.rfc(9110), .rfc(9111), .rfc(9112), .rfc(9110)])
    #expect(path.readers.first != path.readers.last)
  }

  @Test func `a fresh history stacks no reader`() {
    #expect(ReaderPath(NavigationHistory()).readers.isEmpty)
  }

  /// An iPhone gone back to the list shows no reader, and the history still holds
  /// where it was.
  @Test func `nothing on screen stacks no reader`() {
    var history = chain()
    history.hide()
    #expect(ReaderPath(history).readers.isEmpty)
  }

  /// A row in the list is from outside the reader, even when it reopens the document
  /// put away to go back to the list: it comes back where it was, on a stack of its
  /// own.
  @Test func `a row reopening the hidden document starts the stack again`() {
    var history = chain()
    history.hide()
    #expect(history.go(to: place(9112)) == nil)
    #expect(documents(history) == [.rfc(9112)])
    #expect(history.canGoBack, "the history before it stays")
  }

  /// The stack keeps the views below the top for what they are: a reader is
  /// identified by its document and its place in the stack, so pushing another
  /// leaves every one below it the same reader.
  @Test func `pushing a reader leaves the ones below it as they were`() {
    var history = chain()
    let before = ReaderPath(history)
    history.go(to: cited(7230))
    let after = ReaderPath(history)
    #expect(Array(after.readers.prefix(before.readers.count)) == before.readers)
    #expect(after.root == before.root)
    #expect(after.pushed.count == 3)
  }

  // MARK: - Back and forward

  @Test func `back to the document below pops its reader`() {
    var history = chain()
    let before = ReaderPath(history)
    history.goBack()
    let after = ReaderPath(history)
    #expect(after.readers.map(\.id) == [.rfc(9110), .rfc(9111)])
    #expect(before.pops(to: after))
  }

  @Test func `forward after a pop pushes the same reader again`() {
    var history = chain()
    let before = ReaderPath(history)
    history.goBack()
    history.goForward()
    #expect(ReaderPath(history) == before)
  }

  /// Back past an arrival from outside returns to what was being read before it,
  /// the whole stack of it: not a pop, since the reader on screen is not on it.
  @Test func `back past an arrival from outside shows the stack it left`() {
    var history = chain()
    history.go(to: place(8446))
    let before = ReaderPath(history)
    history.goBack()
    let after = ReaderPath(history)
    #expect(after.readers.map(\.id) == [.rfc(9110), .rfc(9111), .rfc(9112)])
    #expect(!before.pops(to: after))
  }

  @Test func `back within a document is not a pop`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: cited(9111))
    history.go(to: cited(9111, "section-4"))
    let before = ReaderPath(history)
    history.goBack()
    #expect(ReaderPath(history) == before)
    #expect(!before.pops(to: ReaderPath(history)))
  }

  @Test func `a citation followed is not a pop`() {
    var history = chain()
    let before = ReaderPath(history)
    history.go(to: cited(7230))
    #expect(!before.pops(to: ReaderPath(history)))
  }

  // MARK: - The stack's own back

  /// The system back button, or a swipe from the edge: the reader goes, with every
  /// jump made in it, and forward returns to where it was left.
  @Test func `the stack's back pops a reader past the jumps made in it`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: cited(9111), leaving: "section-3")
    history.go(to: cited(9111, "section-4"), leaving: "section-1")
    let arrived = history.popReaders(to: 1, leaving: "section-6")
    #expect(arrived == place(9110, "section-3"))
    #expect(documents(history) == [.rfc(9110)])
    #expect(history.goForward() == cited(9111, "section-1"))
    #expect(history.goForward() == cited(9111, "section-6"))
  }

  @Test func `the stack's back pops as many readers as it is asked to`() {
    var history = chain()
    history.go(to: cited(7230))
    history.popReaders(to: 2)
    #expect(documents(history) == [.rfc(9110), .rfc(9111)])
  }

  /// What the stack hands back: its path, cut back by the readers it popped.
  @Test func `the stack's path cut back pops the readers cut`() {
    var history = chain()
    let path = ReaderPath(history)
    history.popReaders(toPushed: Array(path.pushed.prefix(1)))
    #expect(documents(history) == [.rfc(9110), .rfc(9111)])
    #expect(history.popReaders(toPushed: ReaderPath(history).pushed) == nil, "nothing cut")
  }

  @Test func `the stack's back stops at its root`() {
    var history = NavigationHistory()
    history.go(to: place(8446))
    history.go(to: place(9110))
    #expect(history.popReaders(to: 1) == nil)
    #expect(history.current == place(9110))
    #expect(history.popReaders(to: 0) == nil)
    #expect(history.current == place(9110))
  }

  // MARK: - Which reader is which

  @Test func `the top reader is the one on screen`() {
    let path = ReaderPath(chain())
    #expect(path.isTop(.rfc(9112), at: 2))
    #expect(!path.isTop(.rfc(9111), at: 1), "below the top")
    #expect(!path.isTop(.rfc(9111), at: 2), "another document at that depth")
    #expect(!ReaderPath(NavigationHistory()).isTop(.rfc(9112), at: 0))
  }

  @Test func `the stack holds the readers on it, on top or below`() {
    let path = ReaderPath(chain())
    #expect(path.holds(.rfc(9110), at: 0))
    #expect(path.holds(.rfc(9112), at: 2))
    #expect(!path.holds(.rfc(9110), at: 2))
    #expect(!path.holds(.rfc(9110), at: 3), "deeper than the stack")
    #expect(!path.holds(.rfc(9110), at: -1))
  }

  // MARK: - How it was arrived at

  /// Going to the place already on screen is not a navigation, and does not change
  /// how the reader got there: a jump to where the reader is, in a document opened
  /// from the list, must not reach back to the stack before it.
  @Test func `the same place again keeps how it was arrived at`() {
    var history = chain()
    history.go(to: place(8446, "section-4"))
    history.go(to: cited(8446, "section-4"), leaving: "section-4")
    #expect(history.current?.arrival == .root)
    #expect(documents(history) == [.rfc(8446)])
  }

  /// A row in the list names no section, so the document on top, cited without one,
  /// is the same place: still from outside the reader, and it starts the stack
  /// again as a row naming any other document does.
  @Test func `a row for the document on top starts the stack again`() {
    var history = chain()
    #expect(history.go(to: place(9112)) == nil)
    #expect(documents(history) == [.rfc(9112)])
    #expect(history.canGoBack, "the history before it stays")
  }

  @Test func `a restored history keeps its stack`() {
    let history = chain()
    #expect(ReaderPath(NavigationHistory(history.snapshot())) == ReaderPath(history))
  }

  /// A snapshot cut down to its limit may start partway into a stack: the stack
  /// then starts where the history does.
  @Test func `a history that starts partway into a stack starts the stack there`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    for number in 1...4 { history.go(to: cited(number)) }
    let restored = NavigationHistory(history.snapshot(limit: 3))
    #expect(documents(restored) == [.rfc(2), .rfc(3), .rfc(4)])
  }

  // MARK: - How many readers are kept (#263, decision 3)

  @Test func `a stack of eight keeps every reader`() {
    var history = NavigationHistory()
    history.go(to: place(1))
    for number in 2...8 { history.go(to: cited(number)) }
    let path = ReaderPath(history)
    #expect(path.readers.allSatisfy(path.retains))
  }

  /// Deeper than eight, the oldest readers are let go, and made again as the stack
  /// is popped back to them.
  @Test func `a deeper stack keeps the eight nearest the top`() {
    var history = NavigationHistory()
    history.go(to: place(1))
    for number in 2...10 { history.go(to: cited(number)) }
    let path = ReaderPath(history)
    #expect(path.readers.filter(path.retains).map(\.depth) == Array(2...9))

    history.goBack()
    let popped = ReaderPath(history)
    #expect(popped.readers.filter(popped.retains).map(\.depth) == Array(1...8))
  }
}
