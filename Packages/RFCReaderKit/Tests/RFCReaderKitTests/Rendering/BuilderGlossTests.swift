import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Where the builder marks a defined term (#396): a gloss over its first use in each
/// paragraph, underlined dotted in the secondary color, and nowhere a gloss would be
/// wrong or noise.
@Suite("Builder: defined terms")
struct BuilderGlossTests {
  private let style = ReadingStyle()

  private static let relay = DefinedTerm(
    term: "relay", anchor: "def-relay",
    definition: [.paragraph(Paragraph(text: "A relay forwards what it is sent."))])

  /// A document of `blocks` that defines `relay`.
  private static func document(_ blocks: Block...) -> RFCDocument {
    var document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: blocks)],
      source: .xml)
    document.definedTerms = ["relay": relay]
    return document
  }

  /// The text of every gloss, in order.
  private static func glossed(_ text: NSAttributedString) -> [String] {
    var found: [String] = []
    var offset = 0
    while offset < text.length {
      if let gloss = text.gloss(at: offset) {
        found.append((text.string as NSString).substring(with: gloss.range))
        offset = NSMaxRange(gloss.range)
      } else {
        offset += 1
      }
    }
    return found
  }

  private func build(_ document: RFCDocument, style: ReadingStyle? = nil) -> NSAttributedString {
    DocumentTextBuilder.build(document, style: style ?? self.style).text
  }

  @Test func `the first use in each paragraph is glossed`() {
    let text = build(
      Self.document(
        .paragraph(Paragraph(text: "The relay waits, and the relay sends.")),
        .paragraph(Paragraph(text: "Then a relay stops."))))
    #expect(Self.glossed(text) == ["relay", "relay"])
  }

  @Test func `a gloss carries its term, and is underlined dotted in the secondary color`() throws {
    let text = build(Self.document(.paragraph(Paragraph(text: "The relay waits."))))
    let offset = try Fixtures.offset(of: "relay", in: text)
    let gloss = try #require(text.gloss(at: offset))
    #expect(gloss.box.gloss == .term(Self.relay))
    #expect(gloss.range == NSRange(location: offset, length: 5))
    let underline = text.attribute(.underlineStyle, at: offset, effectiveRange: nil) as? Int
    #expect(underline == NSUnderlineStyle.single.union(.patternDot).rawValue)
    let color = text.attribute(.underlineColor, at: offset, effectiveRange: nil) as? PlatformColor
    #expect(color == RFCColors.secondaryLabel)
  }

  @Test func `two uses in two paragraphs are two glosses`() throws {
    let text = build(
      Self.document(
        .paragraph(Paragraph(text: "A relay.")), .paragraph(Paragraph(text: "A relay."))))
    let ranges = (text.string as NSString)
    let first = try #require(text.gloss(at: ranges.range(of: "relay").location))
    let second = try #require(
      text.gloss(at: ranges.range(of: "relay", options: .backwards).location))
    #expect(first.box !== second.box)
  }

  @Test func `inline code, a link and a reference are not glossed`() throws {
    let link = try #require(URL(string: "https://example.com/relay"))
    let text = build(
      Self.document(
        .paragraph(
          Paragraph([
            .code("relay"), .text(" "), .link(link, [.text("relay")]), .text(" "),
            .crossReference(CrossReference(target: .anchor("def-relay"))),
          ]))))
    #expect(Self.glossed(text).isEmpty)
  }

  @Test func `emphasis is glossed like the text around it`() {
    let text = build(
      Self.document(.paragraph(Paragraph([.text("The "), .emphasis([.text("relay")])]))))
    #expect(Self.glossed(text) == ["relay"])
  }

  @Test func `a term is not glossed in its own definition`() {
    let document = Self.document(
      .definitionList(
        DefinitionList([DefinitionItem(term: [.text("relay")], definition: Self.relay.definition)])
      ))
    #expect(Self.glossed(build(document)).isEmpty)
  }

  @Test func `a heading is not glossed`() {
    var document = Self.document(.paragraph(Paragraph(text: "Nothing here.")))
    document.sections[0].title = [.text("A relay")]
    #expect(Self.glossed(build(document)).isEmpty)
  }

  @Test func `a list item and a definition are glossed`() {
    let text = build(
      Self.document(
        .list(ListBlock(style: .bullet, items: [ListItem(text: "A relay item.")])),
        .definitionList(
          DefinitionList([
            DefinitionItem(
              term: [.text("Hop")], definition: [.paragraph(Paragraph(text: "Past a relay."))])
          ]))))
    #expect(Self.glossed(text) == ["relay", "relay"])
  }

  @Test func `a page for paper glosses nothing`() {
    var paper = style
    paper.emitsLinks = false
    let text = build(Self.document(.paragraph(Paragraph(text: "The relay waits."))), style: paper)
    #expect(Self.glossed(text).isEmpty)
  }

  @Test func `a document without defined terms glosses nothing`() throws {
    let text = build(try Fixtures.rfc8999())
    #expect(Self.glossed(text).isEmpty)
  }

  /// RFC 9985's terminology section defines four terms; the prose after it uses them.
  @Test func `a committed document's defined terms are glossed where they are used`() throws {
    let document = try Fixtures.document(named: "rfc9985.xml")
    let text = build(document)
    let glossed = Self.glossed(text)
    #expect(!glossed.isEmpty)
    #expect(glossed.allSatisfy { document.definedTerms[$0] != nil })
  }
}
