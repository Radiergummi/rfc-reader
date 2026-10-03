import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The collected grammar a document exports as one `.abnf` file (#185).
@Suite("Export: grammar")
struct GrammarExportTests {
  private static func rfc9682() throws -> RFCDocument {
    try Fixtures.document(named: "rfc9682.xml")
  }

  private static func grammarBlocks(of document: RFCDocument) -> [String] {
    document.blocks.compactMap { block in
      guard case .preformatted(let content) = block,
        ArtworkType.canonical(content.type).map({ ABNFPresentation.types.contains($0.name) })
          == true
      else { return nil }
      return content.text
    }
  }

  @Test func `a document with no grammar has nothing to export`() throws {
    #expect(GrammarExport.text(for: try Fixtures.rfc8999()) == nil)
    #expect(ExportFormat.available(for: try Fixtures.rfc8999()) == [.pdf])
  }

  @Test func `a document with a grammar offers it`() throws {
    #expect(ExportFormat.available(for: try Self.rfc9682()) == [.pdf, .abnf])
  }

  /// Every grammar block, in document order, its rules starting at the column ABNF
  /// asks of them.
  @Test func `every rule is in the file, in document order`() throws {
    let document = try Self.rfc9682()
    let text = try #require(GrammarExport.text(for: document))
    let rules = try #require(ABNF.parse(text))
    let expected = Self.grammarBlocks(of: document).flatMap { ABNF.parse($0) ?? [] }
    #expect(rules.map(\.name) == expected.map(\.name))
  }

  /// Each block is headed by the section it is in, as a comment.
  @Test func `each block is headed by its section`() throws {
    let document = try Self.rfc9682()
    let text = try #require(GrammarExport.text(for: document))
    let headings = text.split(separator: "\n").filter { $0.hasPrefix("; Section ") }
    #expect(headings.count >= 1)
    for heading in headings {
      let number = heading.dropFirst("; Section ".count).prefix { $0 != " " }
      #expect(
        document.allSections.contains {
          ($0.number ?? "") + "." == number || $0.number == String(number)
        },
        "\(heading)")
    }
  }

  /// RFC 5234's core rules are named and pointed to, not copied: their definitions are
  /// that RFC's text.
  @Test func `the core rules are named, not defined`() throws {
    let text = try #require(GrammarExport.text(for: try Self.rfc9682()))
    let line = try #require(text.split(separator: "\n").first { $0.contains("RFC 5234") })
    #expect(line.hasPrefix(";"))
    #expect(line.contains("Appendix B.1"))
    #expect(!text.contains("%x41-5A"), "no core rule is defined in the file")
  }

  @Test func `the file is named for the document, as abnf`() {
    #expect(ExportFormat.abnf.fileName(for: .rfc(9682)) == "RFC-9682.abnf")
    #expect(ExportFormat.abnf.source == .rendered)
  }

  /// Changing the format in the save panel changes `.abnf`, which no system type
  /// declares, as it changes any other format's extension.
  @Test func `a grammar's extension is changed with the format`() {
    #expect(ExportFormat.pdf.renaming("RFC-9682.abnf") == "RFC-9682.pdf")
    #expect(ExportFormat.abnf.renaming("RFC-9682.pdf") == "RFC-9682.abnf")
  }

  /// A format remembered for one document, but not offered for this one, falls
  /// back to the first offered.
  @Test func `a remembered format not offered falls back`() {
    #expect(ExportFormat(remembered: "abnf", offered: [.pdf]) == .pdf)
    #expect(ExportFormat(remembered: "abnf", offered: [.pdf, .abnf]) == .abnf)
  }
}
