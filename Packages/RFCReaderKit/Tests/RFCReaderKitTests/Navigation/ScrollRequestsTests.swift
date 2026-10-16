import RFCKit
import Testing

@testable import RFCReaderKit

/// A tab's scroll request, and the script waiting for the jump it asked for (#482):
/// whose wait each change ends.
@Suite("Scroll requests")
struct ScrollRequestsTests {
  @Test func `an arrival asks the reader to scroll to its section`() throws {
    var requests = ScrollRequests<String>()
    _ = requests.arrive(at: "section-4.2")
    let request = try #require(requests.current)
    #expect(request.section == "section-4.2")
    #expect(!request.isUnrecorded)
    #expect(!request.isToKeptReader)
  }

  @Test func `an arrival without a section asks nothing`() {
    var requests = ScrollRequests<String>()
    _ = requests.arrive(at: "section-4.2")
    _ = requests.arrive(at: nil)
    #expect(requests.current == nil)
  }

  /// The same section asked for twice is two requests, so the reader scrolls twice.
  @Test func `the same section asked for again is a new request`() {
    var requests = ScrollRequests<String>()
    _ = requests.arrive(at: "section-4.2")
    let first = requests.current
    _ = requests.arrive(at: "section-4.2")
    #expect(requests.current != first)
  }

  @Test func `a return to a kept reader says so`() {
    var requests = ScrollRequests<String>()
    _ = requests.arrive(at: "section-4.2", inKeptReader: true)
    #expect(requests.current?.isToKeptReader == true)
  }

  // MARK: - The jump a script waits on (#482)

  @Test func `a jump is handed over unrecorded and its wait goes on`() {
    var requests = ScrollRequests<String>()
    #expect(requests.jump(to: "4.2", inDocumentOnScreen: true, waiter: "script") == nil)
    #expect(requests.current?.section == "4.2")
    #expect(requests.current?.isUnrecorded == true)
  }

  /// The reader records the jump through the history, whose arrival replaces the
  /// request with the one to scroll there: the script's next command finds it.
  @Test func `a jump recorded ends the wait`() {
    var requests = ScrollRequests<String>()
    _ = requests.jump(to: "4.2", inDocumentOnScreen: true, waiter: "script")
    #expect(requests.arrive(at: "section-4.2") == "script")
    #expect(requests.arrive(at: "section-5") == nil, "a wait ends once")
  }

  @Test func `a jump replaced by another ends the first wait only`() {
    var requests = ScrollRequests<String>()
    _ = requests.jump(to: "4.2", inDocumentOnScreen: true, waiter: "first")
    #expect(requests.jump(to: "5", inDocumentOnScreen: true, waiter: "second") == "first")
    #expect(requests.arrive(at: "section-5") == "second")
  }

  @Test func `a jump settled by the reader ends the wait`() throws {
    var requests = ScrollRequests<String>()
    _ = requests.jump(to: "page-12", inDocumentOnScreen: true, waiter: "script")
    let request = try #require(requests.current)
    #expect(requests.settle(request) == "script")
    #expect(requests.current == request, "settling leaves the request")
    #expect(requests.settle(request) == nil, "a wait ends once")
  }

  /// A reader settling a request that has since been replaced ends no wait: not
  /// the one for the jump asked for after it.
  @Test func `a stale settle ends nothing`() throws {
    var requests = ScrollRequests<String>()
    _ = requests.jump(to: "4.2", inDocumentOnScreen: true, waiter: "first")
    let stale = try #require(requests.current)
    _ = requests.jump(to: "5", inDocumentOnScreen: true, waiter: "second")
    #expect(requests.settle(stale) == nil)
    #expect(requests.settle(try #require(requests.current)) == "second")
  }

  @Test func `a jump with no document on screen ends its wait at once`() {
    var requests = ScrollRequests<String>()
    _ = requests.arrive(at: "section-2")
    let before = requests.current
    #expect(requests.jump(to: "4.2", inDocumentOnScreen: false, waiter: "script") == "script")
    #expect(requests.current == before, "the request stays as it was")
  }

  // MARK: - Going somewhere in the history

  @Test func `a move in the history asks to scroll to where it arrived`() {
    var history = NavigationHistory()
    var requests = ScrollRequests<String>()
    let went = requests.go(
      to: HistoryEntry(id: .rfc(9110), section: "section-4.2"), in: &history, leaving: nil)
    #expect(went.arrived == HistoryEntry(id: .rfc(9110), section: "section-4.2"))
    #expect(requests.current?.section == "section-4.2")
  }

  // MARK: - Reopening the hidden document (#508)

  /// The hidden document reopened from its row: the history does not move, and
  /// the reader made again for it opens at its reading position, not at the place
  /// an earlier arrival asked for.
  @Test func `reopening the hidden document clears the request`() {
    var history = NavigationHistory()
    var requests = ScrollRequests<String>()
    _ = requests.go(
      to: HistoryEntry(id: .rfc(9110), section: "section-4.2"), in: &history, leaving: nil)
    history.hide()
    let went = requests.go(to: HistoryEntry(id: .rfc(9110)), in: &history, leaving: nil)
    #expect(went.arrived == nil)
    #expect(requests.current == nil)
  }

  /// The row of the document on screen picked again: the reader is still there,
  /// and a jump a script waits on in it goes on.
  @Test func `a reader still on screen keeps its request`() {
    var history = NavigationHistory()
    var requests = ScrollRequests<String>()
    _ = requests.go(to: HistoryEntry(id: .rfc(9110)), in: &history, leaving: nil)
    _ = requests.jump(to: "4.2", inDocumentOnScreen: true, waiter: "script")
    let jump = requests.current
    let went = requests.go(to: HistoryEntry(id: .rfc(9110)), in: &history, leaving: nil)
    #expect(went.arrived == nil)
    #expect(went.ended == nil)
    #expect(requests.current == jump)
  }

  /// A jump waited on whose document was then hidden, by deselecting its row or
  /// going back to the list: its reader went before it could settle it, so hiding
  /// ends the wait, rather than leaving the script suspended until a reopen.
  @Test func `hiding the document ends the wait of a jump its reader never settled`() {
    var history = NavigationHistory()
    var requests = ScrollRequests<String>()
    _ = requests.go(to: HistoryEntry(id: .rfc(9110)), in: &history, leaving: nil)
    _ = requests.jump(to: "4.2", inDocumentOnScreen: true, waiter: "script")
    #expect(requests.hide(in: &history) == "script")
    #expect(history.shown == nil)
    let went = requests.go(to: HistoryEntry(id: .rfc(9110)), in: &history, leaving: nil)
    #expect(went.ended == nil, "a wait ends once")
  }

  @Test func `hiding with no jump waited on ends nothing`() {
    var history = NavigationHistory()
    var requests = ScrollRequests<String>()
    _ = requests.go(
      to: HistoryEntry(id: .rfc(9110), section: "section-4.2"), in: &history, leaving: nil)
    #expect(requests.hide(in: &history) == nil)
  }
}
