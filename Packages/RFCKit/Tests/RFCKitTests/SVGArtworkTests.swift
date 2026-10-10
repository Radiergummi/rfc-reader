import Foundation
import Testing

@testable import RFCKit

/// A figure the RFC Editor publishes only as SVG has no text to show: its block names
/// the gap and where the drawing is, as xml2rfc's text rendering does, and keeps its
/// type for a renderer to come (#768). Its SVG's text nodes, run together, read as
/// neither.
@Suite("SVG-only artwork")
struct SVGArtworkTests {
  static func artworks(_ document: RFCDocument) -> [Preformatted] {
    document.blocks.compactMap {
      if case .preformatted(let block) = $0, block.kind == .artwork { block } else { nil }
    }
  }

  /// An `<artset>` takes its ASCII alternative where it has one.
  @Test func `an artset shows its ASCII alternative`() throws {
    let artworks = Self.artworks(try Fixtures.document("rfc9783.xml"))
    #expect(!artworks.isEmpty)
    #expect(!artworks.contains { $0.type == "svg" })
  }

  /// An `<artset>` with only an SVG alternative names the gap, and source code that
  /// is SVG markup is code to read, kept as written. The document is hand-written in
  /// the shape of an RFC, quoting none.
  @Test func `an SVG-only artset names the gap and SVG source code stays`() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rfc number="9999" version="3"><front><title>Drawings</title></front>
      <middle><section anchor="s1"><name>Figures</name>
      <artset><artwork type="svg"><svg xmlns="http://www.w3.org/2000/svg"><text>A to B</text></svg></artwork></artset>
      <sourcecode type="svg">&lt;svg&gt;&lt;text&gt;C&lt;/text&gt;&lt;/svg&gt;</sourcecode>
      </section></middle></rfc>
      """
    let blocks = try RFCXMLParser.parse(Data(xml.utf8)).sections.first?.blocks ?? []
    let preformatted = blocks.compactMap {
      if case .preformatted(let block) = $0 { block } else { nil }
    }
    #expect(
      preformatted.map(\.kind) == [.artwork, .sourceCode]
        && preformatted.allSatisfy { $0.type == "svg" })
    #expect(
      preformatted.first?.text
        == "(Artwork only available as SVG: see https://www.rfc-editor.org/rfc/rfc9999.html)")
    #expect(preformatted.last?.text == "<svg><text>C</text></svg>")
  }
}

@Suite("Corpus-backed: SVG-only artwork", .enabled(if: CorpusText.isXMLAvailable))
struct CorpusBackedSVGArtworkTests {
  /// RFC 9692 sets three figures as bare `<artwork type="svg">`, with no `<artset>`.
  @Test func `a bare SVG artwork names the gap`() throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml("rfc9692"))
    let svg = SVGArtworkTests.artworks(document).filter { $0.type == "svg" }
    #expect(svg.count == 3)
    #expect(
      svg.allSatisfy {
        $0.text
          == "(Artwork only available as SVG: see https://www.rfc-editor.org/rfc/rfc9692.html)"
      })
  }
}
