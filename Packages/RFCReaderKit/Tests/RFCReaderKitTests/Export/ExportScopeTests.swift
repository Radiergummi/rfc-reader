import CoreGraphics
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Exporting or printing the section the reader is in (#386).
@Suite("Export: the current section")
struct ExportScopeTests {
  @Test func `only a format made from the document narrows`() {
    #expect(ExportFormat.allCases.filter(\.narrows) == [.pdf, .epub, .html, .markdown])
  }

  @Test func `the scopes are named`() {
    #expect(ExportScope.wholeDocument.name(in: .english) == "Whole Document")
    #expect(ExportScope.currentSection.name(in: .english) == "Current Section")
  }

  @Test func `only the current section of a format that narrows is a section`() {
    #expect(ExportScope.currentSection.section("section-2", for: .pdf) == "section-2")
    #expect(ExportScope.currentSection.section("section-2", for: .text) == nil)
    #expect(ExportScope.wholeDocument.section("section-2", for: .pdf) == nil)
    #expect(ExportScope.currentSection.section(nil, for: .pdf) == nil)
  }

  @Test func `a part is the section narrowed out, linking out to the document`() throws {
    let document = try Fixtures.rfc8999()
    let section = try #require(document.sections.first { $0.number == "2" })
    let part = try ExportedPart(of: document, section: section.anchor)
    #expect(part.document.sections.map(\.anchor) == [section.anchor])
    #expect(part.outside == document.header.id)
    let whole = try ExportedPart(of: document, section: nil)
    #expect(whole.document == document)
    #expect(whole.outside == nil)
  }

  /// A section the document no longer has is an error: never the whole document
  /// saved under the section's name.
  @Test func `a section the document lacks is an error`() throws {
    #expect(throws: ExportedPart.SectionMissing.self) {
      try ExportedPart(of: try Fixtures.rfc8999(), section: "no-such-section")
    }
  }

  @Test func `a section's file is named by its anchor`() {
    #expect(
      ExportFormat.pdf.fileName(for: .rfc(9110), section: "section-4.2")
        == "RFC-9110-section-4.2.pdf")
    #expect(
      ExportFormat.markdown.fileName(for: .rfc(9110), section: "acknowledgments")
        == "RFC-9110-acknowledgments.md")
    #expect(ExportFormat.fileStem(for: .rfc(9110), section: "section-4") == "RFC-9110-section-4")
    #expect(ExportFormat.fileStem(for: .rfc(9110), section: nil) == "RFC-9110")
    #expect(ExportFormat.pdf.fileName(for: .rfc(9110), section: nil) == "RFC-9110.pdf")
  }

  /// A link to what a section's PDF leaves out goes to the document's page.
  @Test func `a link out of the file goes to rfc-editor.org`() {
    #expect(
      PDFExport.outside("section-1", of: .rfc(9110), references: [:])
        == .web(URL(string: "https://www.rfc-editor.org/rfc/rfc9110#section-1")!))
    #expect(PDFExport.outside("section-1", of: nil, references: [:]) == nil)
  }

  /// A section's PDF leaves the bibliography out with the rest, so a citation in it
  /// is a link to an anchor the file lacks; it goes where the whole document's does.
  @Test func `a citation out of the file goes where its bibliography entry does`() {
    let references = [
      "RFC2119": Reference(
        anchor: "RFC2119", title: "Key words", seriesInfo: [SeriesInfo(name: "RFC", value: "2119")]),
      "NOWHERE": Reference(anchor: "NOWHERE", title: "An Unpublished Note"),
    ]
    #expect(
      PDFExport.outside("RFC2119", of: .rfc(9110), references: references)
        == .web(RFCLink(id: .rfc(2119)).webURL))
    #expect(
      PDFExport.outside("NOWHERE", of: .rfc(9110), references: references)
        == .web(RFCLink(id: .rfc(9110), anchor: "NOWHERE").webURL))
  }

  @Test func `printed pages stack from the top, each fitted to the paper`() {
    let paper = CGSize(width: 600, height: 800)
    #expect(PrintedPages.size(count: 3, paper: paper) == CGSize(width: 600, height: 2400))
    #expect(
      PrintedPages.rect(forPage: 1, count: 3, paper: paper)
        == CGRect(x: 0, y: 1600, width: 600, height: 800))
    #expect(
      PrintedPages.rect(forPage: 3, count: 3, paper: paper)
        == CGRect(x: 0, y: 0, width: 600, height: 800))
    let fitted = PrintedPages.fitted(
      CGSize(width: 300, height: 300), in: CGRect(x: 0, y: 0, width: 600, height: 800))
    #expect(fitted == CGRect(x: 0, y: 100, width: 600, height: 600))
  }
}

/// A grammar asked for of a document without one says so, in words (#383).
@Suite("Export: no grammar")
struct NoGrammarTests {
  @Test func `the error names the document`() {
    #expect(
      ExportFormat.NoGrammar(document: .rfc(9110)).localizedDescription.contains("RFC 9110"))
  }
}
