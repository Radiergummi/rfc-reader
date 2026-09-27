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
    let document = try RFCXMLParser.parse(try Fixtures.data(name))
    return document.blocks.compactMap {
      guard case .preformatted(let content) = $0, FoldedLines.strategy(of: content.text) != nil
      else { return nil }
      return content
    }
  }

  /// A `'\'` continuation's leading spaces are indentation, so they go.
  @Test func rfc9985UnfoldsItsYANGExample() throws {
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
  @Test func rfc9783UnfoldsItsKey() throws {
    let folded = try #require(try Self.foldedBlocks(in: "rfc9783.xml").first)
    #expect(FoldedLines.strategy(of: folded.text) == .doubleBackslash)
    #expect(
      folded.unfoldedText.contains(
        "\"k\": \"3gOLNKyhJXaMXjNXq40Gs2e5qw1-i-Ek7cpH_gM6W7epPTB_8imqNv8kbBKVlk-s9xq3qm7E_WECt7OYMlWtkg\""
      ))
    #expect(!folded.unfoldedText.contains("line wrapping per RFC 8792"))
  }

  // MARK: - The header

  @Test func aBlockWithNoHeaderIsNotFolded() {
    let text = block("GET / HTTP/1.1", "Host: example.com \\")
    #expect(FoldedLines.strategy(of: text) == nil)
    #expect(FoldedLines.unfold(text) == nil)
    #expect(Preformatted(kind: .sourceCode, text: text).unfoldedText == text)
  }

  @Test func theHeaderNamesItsStrategy() {
    #expect(FoldedLines.strategy(of: block(Self.single, "", "a")) == .singleBackslash)
    #expect(FoldedLines.strategy(of: block(Self.double, "", "a")) == .doubleBackslash)
  }

  /// `rfcfold` pads the note to the block's width, so the padding is not measured.
  @Test func theHeaderIsReadHoweverItIsPadded() {
    #expect(FoldedLines.strategy(of: "NOTE: '\\' line wrapping per RFC 8792") == .singleBackslash)
    #expect(
      FoldedLines.strategy(of: "  ==== NOTE: '\\' line wrapping per RFC 8792 ====")
        == .singleBackslash)
  }

  /// A NOTE below the first line is the block talking about folding, which RFC 8792
  /// itself does, not announcing it.
  @Test func aHeaderThatDoesNotOpenTheBlockIsNotOne() {
    #expect(FoldedLines.unfold(block("An example:", Self.single, "", "a\\", "b")) == nil)
  }

  @Test func leadingBlankLinesDoNotHideTheHeader() {
    #expect(FoldedLines.unfold(block("", Self.single, "", "a\\", "b")) == "ab")
  }

  @Test func aStrategyTheRFCDoesNotDefineIsLeftAlone() {
    #expect(
      FoldedLines.unfold(
        block("==== NOTE: '\\\\\\\\' line wrapping per RFC 8792 ====", "", "a\\", "b")) == nil)
  }

  @Test func theHeaderAndItsBlankLineAreRemoved() {
    #expect(FoldedLines.unfold(block(Self.single, "", "first", "second")) == "first\nsecond")
  }

  /// The blank line is part of the header, but a block missing it still unfolds and
  /// keeps its first line.
  @Test func aMissingBlankLineAfterTheHeaderCostsNoContent() {
    #expect(FoldedLines.unfold(block(Self.single, "first", "second")) == "first\nsecond")
  }

  // MARK: - '\'

  /// Issue #64's example, from RFC 9985.
  @Test func aSingleBackslashJoinsTheNextLine() {
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

  @Test func aContinuationsIndentIsNotContent() {
    let text = block(Self.single, "", "{\"key\": \"a long \\", "      value\"}")
    #expect(FoldedLines.unfold(text) == "{\"key\": \"a long value\"}")
  }

  @Test func aLineFoldedTwiceComesBackWhole() {
    let text = block(Self.single, "", "one\\", "  two\\", "  three", "four")
    #expect(FoldedLines.unfold(text) == "onetwothree\nfour")
  }

  /// Only spaces are folding indentation; a tab was put there by the author.
  @Test func aTabAtTheStartOfAContinuationIsKept() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\", "\tb")) == "a\tb")
  }

  @Test func aBackslashOnTheLastLineHasNothingToJoin() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\")) == "a\\")
  }

  @Test func linesThatWereNotFoldedAreUntouched() {
    let text = block(Self.single, "", "  indented", "", "after a blank")
    #expect(FoldedLines.unfold(text) == "  indented\n\nafter a blank")
  }

  @Test func aTrailingNewlineSurvives() {
    #expect(FoldedLines.unfold(block(Self.single, "", "a\\", "b", "")) == "ab\n")
  }

  // MARK: - '\\'

  /// The point of the second strategy: spaces after the continuation's backslash
  /// are content, so a fold can fall just before a space.
  @Test func aDoubleBackslashKeepsTheSpacesAfterTheMarker() {
    let text = block(Self.double, "", "Subject: a long\\", "   \\ subject line")
    #expect(FoldedLines.unfold(text) == "Subject: a long subject line")
  }

  @Test func aDoubleBackslashFoldedTwiceComesBackWhole() {
    let text = block(Self.double, "", "one\\", "\\two\\", "  \\three")
    #expect(FoldedLines.unfold(text) == "onetwothree")
  }

  /// Text whose own lines end in a backslash is why this strategy exists: without a
  /// marked continuation, the backslash stays.
  @Test func anAuthorsOwnTrailingBackslashIsKept() {
    let text = block(Self.double, "", "#define X \\", "    1")
    #expect(FoldedLines.unfold(text) == "#define X \\\n    1")
  }
}
