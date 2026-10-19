import Testing

@testable import RFCKit

/// What changed between two texts, word by word (#729). Guard-level: hand-written
/// sentences in the shape of a revision's, quoted from none.
@Suite("Word diff")
struct WordDiffTests {
  @Test func `the same text is one run kept`() {
    #expect(
      WordDiff.runs(from: "A client sends a request.", to: "A client sends a request.")
        == [.same("A client sends a request.")])
  }

  @Test func `a word replaced is deleted before its replacement is inserted`() {
    #expect(
      WordDiff.runs(from: "A client MAY retry.", to: "A client SHOULD retry.")
        == [.same("A client "), .deleted("MAY"), .inserted("SHOULD"), .same(" retry.")])
  }

  @Test func `words added and removed are runs of their own`() {
    #expect(
      WordDiff.runs(from: "The server closes the connection.", to: "The server closes it.")
        == [.same("The server closes "), .deleted("the connection."), .inserted("it.")])
    #expect(
      WordDiff.runs(from: "Send the header", to: "Send the new header first")
        == [.same("Send the "), .inserted("new "), .same("header"), .inserted(" first")])
  }

  /// The spaces two rewritten sentences share are no common ground: kept, they cut
  /// the change into a struck word, an inserted one, and so on, word by word.
  @Test func `a sentence rewritten is deleted whole before its replacement`() {
    #expect(
      WordDiff.runs(from: "A client sends one request.", to: "The server returns two answers.")
        == [.deleted("A client sends one request."), .inserted("The server returns two answers.")])
    #expect(
      WordDiff.runs(from: "Send the old header now", to: "Send a new field now")
        == [.same("Send "), .deleted("the old header"), .inserted("a new field"), .same(" now")])
  }

  /// A paragraph rewrapped at another width is the same paragraph.
  @Test func `whitespace is compared as one space`() {
    let runs = WordDiff.runs(from: "one two\n   three", to: "one two three")
    #expect(runs == [.same("one two three")])
    #expect(!WordDiff.changes(runs))
  }

  @Test func `a text from nothing is all inserted, and to nothing all deleted`() {
    #expect(WordDiff.runs(from: "", to: "new words") == [.inserted("new words")])
    #expect(WordDiff.runs(from: "old words", to: "") == [.deleted("old words")])
    #expect(WordDiff.runs(from: "", to: "").isEmpty)
  }

  /// Including where words go on only one side of a kept space, which stays the
  /// newer text's: a copy of the redline is that text.
  @Test func `the runs read back as either text`() {
    let pairs = [
      (
        "Each field is sent once, unless the sender splits it.",
        "Each field is sent at most once, unless a sender combines it."
      ),
      ("to to send to it now", "send now to"),
      ("to it now to to it", "it it send"),
      ("send it now", "it to to to now send"),
    ]
    for (old, new) in pairs {
      let runs = WordDiff.runs(from: old, to: new)
      #expect(WordDiff.changes(runs))
      let newText = runs.compactMap { if case .deleted = $0 { nil } else { $0.text } }.joined()
      let oldText = runs.compactMap { if case .inserted = $0 { nil } else { $0.text } }.joined()
      #expect(newText == new)
      #expect(oldText.split(separator: " ") == old.split(separator: " "))
    }
  }
}
