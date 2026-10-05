import Testing

@testable import RFCReaderKit

/// When the list follows what is typed into search (#124): after a pause in typing,
/// so a word typed at speed changes the list once rather than once a letter, and at
/// once when the search is cleared.
@Suite("Applied search")
struct AppliedSearchTests {
  @Test func `a query is applied trimmed`() {
    #expect(AppliedSearch.query(for: "  http semantics ") == "http semantics")
  }

  @Test func `a new query waits for a pause in typing`() {
    #expect(
      AppliedSearch.step(applying: "http", over: "htt", pausing: true)
        == .search(query: "http", after: AppliedSearch.pause))
    #expect(
      AppliedSearch.step(applying: "quic ", over: "", pausing: true)
        == .search(query: "quic", after: AppliedSearch.pause))
  }

  @Test func `a query applied without pausing is searched at once`() {
    #expect(
      AppliedSearch.step(applying: "http", over: "", pausing: false)
        == .search(query: "http", after: .zero))
  }

  @Test func `clearing the search applies before returning`() {
    #expect(AppliedSearch.step(applying: "", over: "http", pausing: true) == .apply(query: ""))
    #expect(AppliedSearch.step(applying: "   ", over: "http", pausing: true) == .apply(query: ""))
  }

  /// A space typed between words asks for the query already applied, so the list
  /// has nothing to follow.
  @Test func `the query already applied is not applied again`() {
    #expect(AppliedSearch.step(applying: "http ", over: "http", pausing: true) == nil)
    #expect(AppliedSearch.step(applying: "", over: "", pausing: false) == nil)
  }

  @Test func `the pause is short enough to follow while reading`() {
    #expect(AppliedSearch.pause == .milliseconds(150))
  }

  /// The collection picker's own search waits as the list's does.
  @Test func `a query waits for the pause and no search waits for nothing`() {
    #expect(AppliedSearch.pause(before: "http") == AppliedSearch.pause)
    #expect(AppliedSearch.pause(before: "") == .zero)
  }
}
