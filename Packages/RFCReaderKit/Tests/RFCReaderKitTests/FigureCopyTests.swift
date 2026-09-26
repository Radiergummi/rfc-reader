import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Copy Figure")
@MainActor
struct FigureCopyTests {
  private let style = ReadingStyle()

  private static let folded = Preformatted(
    kind: .sourceCode,
    text:
      "=============== NOTE: '\\' line wrapping per RFC 8792 ================\n\n{\"key\": \"a long \\\n      value\"}",
    type: "json"
  )
  private static let diagram = Preformatted(kind: .artwork, text: "+---+\n| A |\n+---+")

  private func built() -> BuiltDocument {
    DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph(text: "Before the figures.")),
        .preformatted(Self.folded),
        .paragraph(Paragraph(text: "Between them.")),
        .preformatted(Self.diagram)
      ),
      style: style
    )
  }

  @Test func aMenuOnAFigureFindsIt() throws {
    let text = built().text
    let figure = try #require(
      FigureCopy.figure(at: try Fixtures.offset(of: "| A |", in: text), in: text))
    #expect(figure.text == Self.diagram.text)
  }

  /// The language label is drawn inside the card, so it is part of the figure a
  /// click on it means.
  @Test func theLanguageLabelBelongsToItsFigure() throws {
    let text = built().text
    let figure = try #require(
      FigureCopy.figure(at: try Fixtures.offset(of: "JSON", in: text), in: text))
    #expect(figure.type == "json")
  }

  @Test func proseIsNoFigure() throws {
    let text = built().text
    #expect(FigureCopy.figure(at: try Fixtures.offset(of: "Between", in: text), in: text) == nil)
    #expect(FigureCopy.figure(at: -1, in: text) == nil)
    #expect(FigureCopy.figure(at: text.length, in: text) == nil)
  }

  /// A selection that strays into the prose around one figure still means that
  /// figure; one across two cannot say which.
  @Test func aSelectionMeansAFigureOnlyWhenItTouchesExactlyOne() throws {
    let text = built().text
    let between = try Fixtures.offset(of: "Between", in: text)
    let diagram = try Fixtures.offset(of: "| A |", in: text)

    let aroundOne = NSRange(location: between, length: diagram + 2 - between)
    #expect(FigureCopy.figure(in: aroundOne, of: text)?.text == Self.diagram.text)
    #expect(FigureCopy.figure(in: NSRange(location: 0, length: text.length), of: text) == nil)
    #expect(FigureCopy.figure(in: NSRange(location: between, length: 7), of: text) == nil)
    #expect(
      FigureCopy.figure(in: NSRange(location: diagram, length: 0), of: text)?.text
        == Self.diagram.text)
  }

  /// The reader lays the block out as the page printed it, header and all; the
  /// pasteboard gets what the author wrote (issue #64).
  @Test func aFoldedFigureIsCopiedUnfolded() throws {
    let text = built().text
    #expect(
      text.string.contains("NOTE: '\\' line wrapping"),
      "the reader still shows the block as published")
    let figure = try #require(
      FigureCopy.figure(at: try Fixtures.offset(of: "a long", in: text), in: text))
    #expect(FigureCopy.pasteboardText(for: figure) == "{\"key\": \"a long value\"}")
  }

  @Test func anUnfoldedFigureIsCopiedAsItIs() {
    #expect(FigureCopy.pasteboardText(for: Self.diagram) == Self.diagram.text)
  }
}
