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

  @Test func `the current section is the document narrowed to it`() throws {
    let document = try Fixtures.rfc8999()
    let section = try #require(document.sections.first { $0.number == "2" })
    #expect(ExportScope.wholeDocument.document(document, section: section.anchor) == document)
    let narrowed = try #require(
      ExportScope.currentSection.document(document, section: section.anchor))
    #expect(narrowed.sections.map(\.anchor) == [section.anchor])
    #expect(ExportScope.currentSection.document(document, section: nil) == nil)
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
  }

  /// A link to what a section's PDF leaves out goes to the document's page.
  @Test func `a link out of the file goes to rfc-editor.org`() {
    #expect(
      PDFExport.outside("section-1", of: .rfc(9110))
        == .web(URL(string: "https://www.rfc-editor.org/rfc/rfc9110#section-1")!))
    #expect(PDFExport.outside("section-1", of: nil) == nil)
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
