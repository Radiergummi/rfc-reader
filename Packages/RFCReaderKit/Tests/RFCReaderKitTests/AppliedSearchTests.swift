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
    #expect(AppliedSearch.delay(applying: "http", over: "htt") == AppliedSearch.pause)
    #expect(AppliedSearch.delay(applying: "quic", over: "") == AppliedSearch.pause)
  }

  @Test func `clearing the search applies at once`() {
    #expect(AppliedSearch.delay(applying: "", over: "http") == .zero)
    #expect(AppliedSearch.delay(applying: "   ", over: "http") == .zero)
  }

  /// A space typed between words asks for the query already applied, so the list
  /// has nothing to follow.
  @Test func `the query already applied is not applied again`() {
    #expect(AppliedSearch.delay(applying: "http ", over: "http") == nil)
    #expect(AppliedSearch.delay(applying: "", over: "") == nil)
  }

  @Test func `the pause is short enough to follow while reading`() {
    #expect(AppliedSearch.pause == .milliseconds(150))
  }
}
