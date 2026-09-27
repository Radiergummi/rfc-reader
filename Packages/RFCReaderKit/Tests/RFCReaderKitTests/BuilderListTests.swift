import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: lists")
@MainActor
struct BuilderListTests {
  private let style = ReadingStyle()

  @Test func bulletMarkers() {
    #expect(DocumentTextBuilder.marker(for: .bullet, at: 0) == "•")
    #expect(DocumentTextBuilder.marker(for: .bare, at: 3) == "")
  }

  @Test func decimalMarkersRespectTheStart() {
    #expect(DocumentTextBuilder.marker(for: .numbered(format: nil, start: 1), at: 0) == "1.")
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "1", start: 5), at: 2) == "7.")
  }

  @Test func letterAndRomanMarkers() {
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "a", start: 1), at: 0) == "a.")
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "A", start: 1), at: 25) == "Z.")
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "i", start: 1), at: 3) == "iv.")
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "I", start: 1), at: 8) == "IX.")
  }

  @Test func templateMarkers() {
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "(%c)", start: 1), at: 1) == "(b)")
    #expect(DocumentTextBuilder.marker(for: .numbered(format: "%d)", start: 1), at: 2) == "3)")
  }

  @Test func listItemsAppearAsTextWithTheirMarkers() {
    let list = ListBlock(
      style: .bullet,
      items: [
        ListItem(text: "first"),
        ListItem(text: "second"),
      ])
    let document = Fixtures.document(.list(list))
    let built = DocumentTextBuilder.build(document, style: style)
    #expect(built.text.string.contains("•\tfirst"))
    #expect(built.text.string.contains("•\tsecond"))
  }

  @Test func definitionTermsAreBoldAndDefinitionsAreIndented() throws {
    let item = DefinitionItem(
      term: [.text("MUST")], definition: [.paragraph(Paragraph(text: "absolute requirement"))])
    let document = Fixtures.document(.definitionList([item]))
    let built = DocumentTextBuilder.build(document, style: style)
    let offset = try Fixtures.offset(of: "MUST", in: built.text)
    let font = built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
    #expect(font?.fontDescriptor.symbolicTraits.contains(RFCTraits.bold) == true)

    let definitionOffset = try Fixtures.offset(of: "absolute requirement", in: built.text)
    let paragraph =
      built.text.attribute(.paragraphStyle, at: definitionOffset, effectiveRange: nil)
      as? NSParagraphStyle
    #expect((paragraph?.headIndent ?? 0) > 0)
  }

  /// A definition's own anchor is indexed where its text starts, and an empty
  /// definition's at the end of its own term: after the newline would be the next
  /// item's term, and a link to it would land one item late (#166).
  @Test func aDefinitionsAnchorIsIndexedOnItsOwnItem() throws {
    let items = [
      DefinitionItem(
        term: [.text("MUST")], definition: [.paragraph(Paragraph(text: "absolute requirement"))],
        definitionAnchor: "must-definition"),
      DefinitionItem(term: [.text("SHALL")], definition: [], definitionAnchor: "shall-definition"),
      DefinitionItem(
        term: [.text("SHOULD")], definition: [.paragraph(Paragraph(text: "recommended"))]),
    ]
    let built = DocumentTextBuilder.build(Fixtures.document(.definitionList(items)), style: style)

    let definition = try #require(built.anchors.offset(of: "must-definition"))
    #expect(try Fixtures.offset(of: "absolute requirement", in: built.text) == definition)

    let empty = try #require(built.anchors.offset(of: "shall-definition"))
    let term = try Fixtures.offset(of: "SHALL", in: built.text)
    #expect(empty == term + "SHALL".utf16.count)
    #expect(try Fixtures.offset(of: "SHOULD", in: built.text) > empty)
  }

  @Test func aListItemHangsItsMarkerLeftOfItsText() throws {
    let list = ListBlock(style: .bullet, items: [ListItem(text: "first")])
    let document = Fixtures.document(.list(list))
    let built = DocumentTextBuilder.build(document, style: style)
    let offset = try Fixtures.offset(of: "first", in: built.text)
    let paragraph = try #require(
      built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    #expect(
      paragraph.firstLineHeadIndent < paragraph.headIndent,
      "the marker must start left of the wrapped text")
    #expect(
      paragraph.tabStops.contains { $0.location == paragraph.headIndent },
      "the marker's tab must land exactly on the wrapped-text column")
  }
}
