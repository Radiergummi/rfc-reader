import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: completeness")
struct BuilderCompletenessTests {
  private let style = ReadingStyle()

  /// The guard on the central decision. An attachment character outside a chip's
  /// own run means a block kind quietly became a hosted view, which is the hole
  /// in the storage this design exists to avoid; the chip's leading doc.text
  /// symbol is the one sanctioned exception, and only inside its own `.rfcChip` run.
  @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
  func `nothing becomes an attachment`(fixture: String) throws {
    let document = fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
    let built = DocumentTextBuilder.build(document, style: style)
    // Walked as UTF-16, which is what `attribute(at:)` is indexed by; a
    // Character walk agrees only while the text stays in the BMP, and this
    // scans whole real RFCs.
    let text = built.text.string as NSString
    var searchStart = 0
    while searchStart < text.length {
      let found = text.range(
        of: "\u{FFFC}", range: NSRange(location: searchStart, length: text.length - searchStart))
      guard found.location != NSNotFound else { break }
      #expect(
        built.text.attribute(.rfcChip, at: found.location, effectiveRange: nil) != nil,
        "\(fixture) has an attachment character outside a chip run at offset \(found.location)"
      )
      searchStart = NSMaxRange(found)
    }
  }

  @Test func `a figure contributes artwork and a caption as text`() {
    let figure = Figure(
      title: "Packet layout",
      number: 3,
      blocks: [.preformatted(Preformatted(kind: .artwork, text: "+--+"))],
      anchor: "figure-3"
    )
    let document = Fixtures.document(.figure(figure))
    let built = DocumentTextBuilder.build(document, style: style)
    #expect(built.text.string.contains("+--+"))
    #expect(built.text.string.contains("Figure 3: Packet layout"))
    #expect(built.anchors.offset(of: "figure-3") != nil)
  }

  @Test func `a captioned figure tags its artwork with the caption`() throws {
    let figure = Figure(
      title: "Packet layout",
      number: 3,
      blocks: [.preformatted(Preformatted(kind: .artwork, text: "+--+"))],
      anchor: "figure-3"
    )
    let document = Fixtures.document(.figure(figure))
    let built = DocumentTextBuilder.build(document, style: style)
    let offset = try Fixtures.offset(of: "+--+", in: built.text)
    #expect(
      built.text.attribute(.rfcCaption, at: offset, effectiveRange: nil) as? String
        == "Figure 3: Packet layout")
  }

  @Test func `block quotes and asides are indented text with a decoration`() throws {
    let document = Fixtures.document(
      .blockQuote([.paragraph(Paragraph(text: "quoted"))]),
      .aside([.paragraph(Paragraph(text: "noted"))]))
    let built = DocumentTextBuilder.build(document, style: style)

    for (needle, expected) in [
      ("quoted", RFCDecoration.blockQuote), ("noted", RFCDecoration.aside),
    ] {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      #expect(
        RFCDecoration(
          attributeValue: built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil))
          == expected)
      let paragraph =
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
      #expect((paragraph?.headIndent ?? 0) > 0)
    }
  }

  /// `RFCXMLParser` wraps any unrecognised child element as `.aside(blocks)`, so an
  /// unrecognised element inside a `<blockquote>` nests an aside inside a quote for
  /// real documents, not just hypothetically. The more specific, inner decoration
  /// must survive; the outer one only fills what the inner call left unset.
  @Test func `a nested aside inside a block quote keeps its own decoration`() throws {
    let document = Fixtures.document(
      .blockQuote([
        .paragraph(Paragraph(text: "quoted")),
        .aside([.paragraph(Paragraph(text: "noted"))]),
      ]))
    let built = DocumentTextBuilder.build(document, style: style)

    for (needle, expected) in [
      ("quoted", RFCDecoration.blockQuote), ("noted", RFCDecoration.aside),
    ] {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      #expect(
        RFCDecoration(
          attributeValue: built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil))
          == expected)
    }
  }

  /// The bibliography is the panel's, not the body's. Its rows used to be four
  /// stacked indented paragraphs per entry; keeping them out is the point, so the
  /// assertion is that none of it reaches the storage.
  @Test func `a bibliography section contributes nothing to the body`() {
    let reference = Reference(
      anchor: "RFC9110",
      title: "HTTP Semantics",
      authors: ["R. Fielding", "M. Nottingham", "J. Reschke"],
      date: PublicationDate(year: 2022, month: 6),
      seriesInfo: [SeriesInfo(name: "RFC", value: "9110")]
    )
    let built = DocumentTextBuilder.build(
      RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [
          Section(
            anchor: "section-1", number: "1", title: "References",
            blocks: [
              .references(ReferenceList(title: "Normative References", entries: [reference]))
            ])
        ],
        source: .xml
      ),
      style: style
    )
    #expect(!built.text.string.contains("HTTP Semantics"))
    #expect(!built.text.string.contains("[RFC9110]"))
    #expect(!built.text.string.contains("References"), "the heading goes with the rows")
    #expect(built.anchors.offset(of: "ref-RFC9110") == nil)
  }

  @Test func `every anchor in the document is indexed`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: style)

    var expected: Set<String> = []
    for section in document.allSections where !section.holdsOnlyReferences {
      expected.insert(section.anchor)
      for block in section.blocks.flattened {
        // Bibliography entries are not in the body; they are the panel's.
        if case .references = block { continue }
        expected.formUnion(block.anchors)
      }
    }

    for anchor in expected {
      #expect(built.anchors.offset(of: anchor) != nil, "missing anchor \(anchor)")
    }
  }
}
