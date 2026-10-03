import Foundation
import Testing

@testable import RFCKit

/// RFC 8792 unfolding. Through the parser, on the two strategies as published:
/// RFC 9985's YANG example (`'\'`, the one #64 was filed with) and RFC 9783's JSON
/// Web Key (`'\\'`). At the guard, `FoldedLines.unfold` is a pure function of one
/// block's text, so those tests hand it lines rather than a whole document.
@Suite("Folded lines (RFC 8792)")
struct FoldedLinesTests {
  private static let single =
    "=============== NOTE: '\\' line wrapping per RFC 8792 ================"
  private static let double =
    "============== NOTE: '\\\\' line wrapping per RFC 8792 ==============="

  private func block(_ lines: String...) -> String {
    lines.joined(separator: "\n")
  }

  // MARK: - Through the parser

  /// Every verbatim block the document folds, in document order.
  private static func foldedBlocks(in name: String) throws -> [Preformatted] {
    let document = try Fixtures.document(name)
    return document.blocks.compactMap {
      guard case .preformatted(let content) = $0, FoldedLines.strategy(of: content.text) != nil
      else { return nil }
      return content
    }
  }

  /// A `'\'` continuation's leading spaces are indentation, so they go.
  @Test func `rfc9985 unfolds its YANG example`() throws {
    let folded = try #require(try Self.foldedBlocks(in: "rfc9985.xml").first)
    #expect(FoldedLines.strategy(of: folded.text) == .singleBackslash)
    let unfolded = folded.unfoldedText
    #expect(
      unfolded.contains(
        "    xmlns:bfd-mki=\"urn:ietf:params:xml:ns:yang:ietf-bfd-met-keyed-isaac\">"))
    #expect(!unfolded.contains("line wrapping per RFC 8792"))
    #expect(!unfolded.contains("\\\n"), "no fold is left")
  }

  /// A `'\\'` continuation marks the fold with its own `\`, so the spaces before
  /// it go and the key reads as one unbroken value.
  @Test func `rfc9783 unfolds its key`() throws {
    let folded = try #require(try Self.foldedBlocks(in: "rfc9783.xml").first)
    #expect(FoldedLines.strategy(of: folded.text) == .doubleBackslash)
    #expect(
      folded.unfoldedText.contains(
        "\"k\": \"3gOLNKyhJXaMXjNXq40Gs2e5qw1-i-Ek7cpH_gM6W7epPTB_8imqNv8kbBKVlk-s9xq3qm7E_WECt7OYMlWtkg\""
      ))
    #expect(!folded.unfoldedText.contains("line wrapping per RFC 8792"))
  }

  // MARK: - The header

  @Test func `a block with no header is not folded`() {
    let text = block("GET / HTTP/1.1", "Host: example.com \\")
    #expect(FoldedLines.strategy(of: text) == nil)
    #expect(FoldedLines.unfold(text) == nil)
    #expect(Preformatted(kind: .sourceCode, text: text).unfoldedText == text)
  }

  @Test func `the header names its strategy`() {
    #expect(FoldedLines.strategy(of: block(Self.single, "", "a")) == .singleBackslash)
    #expect(FoldedLines.strategy(of: block(Self.double, "", "a")) == .doubleBackslash)
  }

  /// `rfcfold` pads the note to the block's width, so the padding is not measured.
  @Test func `the header is read however it is padded`() {
    #expect(FoldedLines.strategy(of: "NOTE: '\\' line wrapping per RFC 8792") == .singleBackslash)
    #expect(
      FoldedLines.strategy(of: "  ==== NOTE: '\\' line wrapping per RFC 8792 ====")
        == .singleBackslash)
  }

  /// A NOTE below the first line is the block talking about folding, which RFC 8792
  /// itself does, not announcing it.
  @Test func `a header that does not open the block is not one`() {
    #expect(FoldedLines.unfold(block("An example:", Self.single, "", "a\\", "b")) == nil)
  }

  @Test func `leading blank lines do not hide the header`() {
    #expect(FoldedLines.unfold(block("", Self.single, "", "a\\", "b")) == "ab")
  }

  @Test func `a strategy the RFC does not define is left alone`() {
    #expect(
      FoldedLines.unfold(
        block("==== NOTE: '\\\\\\\\' line wrapping per RFC 8792 ====", "", "a\\", "b")) == nil)
  }

  @Test func `the header and its blank line are removed`() {
    #expect(FoldedLines.unfold(block(Self.single, "", "first", "second")) == "first\nsecond")
  }

  /// The blank line is part of the header, but a block missing it still unfolds and
  /// keeps its first line.
  @Test func `a missing blank line after the header costs no content`() {
    #expect(FoldedLines.unfold(block(Self.single, "first", "second")) == "first\nsecond")
  }

  // MARK: - '\'

  /// Issue #64's example, from RFC 9985.
  @Test func `a single backslash joins the next line`() {
    let text = block(
      Self.single,
      "",
      "    xmlns:bfd-mki=\"urn:ietf:params:xml:ns:yang:ietf-bfd-met-keyed-i\\",
      "saac\">"
    )
    #expect(
      FoldedLines.unfold(text)
        == "    xmlns:bfd-mki=\"urn:ietf:params:xml:ns:yang:ietf-bfd-met-keyed-isaac\">")
  }

  @Test func `a continuations indent is not content`() {
    let text = block(Self.single, "", "{\"key\": \"a long \\", "      value\"}")
    #expect(FoldedLines.unfold(text) == "{\"key\": \"a long value\"}")
  }

  @Test func `a line folded twice comes back whole`() {
    let text = block(Self.single, "", "one\\", "  two\\", "  three", "four")
    #expect(FoldedLines.unfold(text) == "onetwothree\nfour")
  }

  /// Only spaces are folding indentation; a tab was put there by the author.
  @Test func `a tab at the start of a continuation is kept`() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\", "\tb")) == "a\tb")
  }

  /// A backslash that ends the block's last line, before the block's own newline,
  /// has no continuation to join: the empty line after it is the end of the block.
  @Test func `a backslash before a trailing newline is kept`() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\", "")) == "a\\\n")
  }

  @Test func `a backslash on the last line has nothing to join`() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\")) == "a\\")
  }

  @Test func `lines that were not folded are untouched`() {
    let text = block(Self.single, "", "  indented", "", "after a blank")
    #expect(FoldedLines.unfold(text) == "  indented\n\nafter a blank")
  }

  @Test func `a trailing newline survives`() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\", "b", "")) == "ab\n")
  }

  // MARK: - '\\'

  /// The point of the second strategy: spaces after the continuation's backslash
  /// are content, so a fold can fall just before a space.
  @Test func `a double backslash keeps the spaces after the marker`() {
    let text = block(Self.double, "", "Subject: a long\\", "   \\ subject line")
    #expect(FoldedLines.unfold(text) == "Subject: a long subject line")
  }

  @Test func `a double backslash folded twice comes back whole`() {
    let text = block(Self.double, "", "one\\", "\\two\\", "  \\three")
    #expect(FoldedLines.unfold(text) == "onetwothree")
  }

  /// Text whose own lines end in a backslash is why this strategy exists: without a
  /// marked continuation, the backslash stays.
  @Test func `an authors own trailing backslash is kept`() {
    let text = block(Self.double, "", "#define X \\", "    1")
    #expect(FoldedLines.unfold(text) == "#define X \\\n    1")
  }

  // MARK: - A selection (#212)

  /// The whole block selected is the block unfolded.
  @Test func `a selection of the whole block unfolds as the block does`() {
    let text = block(Self.single, "", "one\\", "  two", "three")
    #expect(FoldedLines.unfold(selection: text, strategy: .singleBackslash) == "onetwo\nthree")
  }

  @Test func `a selection inside one line is copied as it is`() {
    #expect(FoldedLines.unfold(selection: "ne tw", strategy: .singleBackslash) == "ne tw")
  }

  /// The edges are what was selected; the fold between them is undone.
  @Test func `a selection that crosses a fold joins it`() {
    let text = block("long \\", "      value\"}")
    #expect(FoldedLines.unfold(selection: text, strategy: .singleBackslash) == "long value\"}")
  }

  /// The label a code block's card carries comes before the header, and stays.
  @Test func `a selected header and its blank line are left out`() {
    let text = block("JSON", Self.double, "", "a long\\", "   \\ subject")
    #expect(
      FoldedLines.unfold(selection: text, strategy: .doubleBackslash) == "JSON\na long subject")
  }

  /// A fold whose continuation is not selected is not wholly in the selection, so
  /// it is copied as selected.
  @Test(arguments: [FoldedLines.Strategy.singleBackslash, .doubleBackslash])
  func `a fold cut off by the selection is kept`(strategy: FoldedLines.Strategy) {
    #expect(FoldedLines.unfold(selection: "abc\\\n   ", strategy: strategy) == "abc\\\n   ")
  }

  /// A block already shown unfolded has no fold left to undo.
  @Test func `a selection of an unfolded block is unchanged`() {
    let text = "{\"key\": \"a long value\"}\n"
    #expect(FoldedLines.unfold(selection: text, strategy: .singleBackslash) == text)
  }
}
