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
}
