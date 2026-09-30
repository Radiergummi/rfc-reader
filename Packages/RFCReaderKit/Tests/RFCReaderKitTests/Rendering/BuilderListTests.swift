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
struct BuilderListTests {
  private let style = ReadingStyle()

  @Test func `bullet markers`() {
    #expect(DocumentTextBuilder.marker(for: .bullet, at: 0) == "•")
    #expect(DocumentTextBuilder.marker(for: .bare, at: 3) == "")
  }

  /// The counting itself is `ListNumbering`'s, and tested there; the builder draws
  /// what it says.
  @Test func `a numbered marker is drawn as its numbering says`() {
    let numbering = ListNumbering(type: "(%c)", start: 1)
    #expect(DocumentTextBuilder.marker(for: .numbered(numbering), at: 1) == "(b)")
  }

  /// `letter(_:)` used to index a string by `(number - 1) % 26`, which traps for a
  /// start of 0 or below: `<ol type="a" start="0">` is valid RFCXML.
  @Test func `a lettered list starting at zero draws`() {
    let numbering = ListNumbering(type: "a", start: 0)
    #expect(DocumentTextBuilder.marker(for: .numbered(numbering), at: 0) == "0.")
    #expect(DocumentTextBuilder.marker(for: .numbered(numbering), at: 1) == "a.")
  }

  @Test func `list items appear as text with their markers`() {
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

  @Test func `definition terms are bold and definitions are indented`() throws {
    let item = DefinitionItem(
      term: [.text("MUST")], definition: [.paragraph(Paragraph(text: "absolute requirement"))])
    let document = Fixtures.document(.definitionList([item]))
    let built = DocumentTextBuilder.build(document, style: style)
    let offset = try Fixtures.offset(of: "MUST", in: built.text)
    let font = built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
    // The font itself in the message: this failed twice under concurrent runs with
    // a 12 pt font that was not bold (#326), and which font it was decides the fix.
    #expect(
      font?.fontDescriptor.symbolicTraits.contains(RFCTraits.bold) == true,
      "\(font.map(Fixtures.describe) ?? "no font")")

    let definitionOffset = try Fixtures.offset(of: "absolute requirement", in: built.text)
    let paragraph =
      built.text.attribute(.paragraphStyle, at: definitionOffset, effectiveRange: nil)
      as? NSParagraphStyle
    #expect((paragraph?.headIndent ?? 0) > 0)
  }

  /// A definition's own anchor is indexed where its text starts, and an empty
  /// definition's at the end of its own term: after the newline would be the next
  /// item's term, and a link to it would land one item late (#166).
  @Test func `a definitions anchor is indexed on its own item`() throws {
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

  /// A prepped `<li><t pn="section-2-3.1">` is set on the item's first line, beside
  /// its marker, and a link to the paragraph lands where its text starts, as a
  /// second paragraph's would.
  @Test func `a list items first paragraph is indexed at its text`() throws {
    let item = ListItem(
      blocks: [
        .paragraph(Paragraph(text: "first paragraph", anchor: "section-1-1.1")),
        .paragraph(Paragraph(text: "second paragraph", anchor: "section-1-1.2")),
      ],
      anchor: "section-1-1")
    let list = ListBlock(style: .bullet, items: [item])
    let built = DocumentTextBuilder.build(Fixtures.document(.list(list)), style: style)

    let first = try #require(built.anchors.offset(of: "section-1-1.1"))
    #expect(try Fixtures.offset(of: "first paragraph", in: built.text) == first)
    let second = try #require(built.anchors.offset(of: "section-1-1.2"))
    #expect(try Fixtures.offset(of: "second paragraph", in: built.text) == second)
  }

  @Test func `a list item hangs its marker left of its text`() throws {
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
