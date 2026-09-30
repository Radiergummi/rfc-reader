import RFCKit
import Testing

@testable import RFCReaderKit

/// Which RFCs the reader shows as their PDF or PostScript original, and in which
/// mode (#207): a scan in either, since it has no text; a pointer only in place of
/// the rendered text, since Original Text shows the pointer as published.
@Suite("Published original page")
struct PublishedOriginalPageTests {
  private let pointerFormats: [FileFormat] = [.text, .postScript, .pdf, .html]
  private let pointer = RFCDocument(
    header: DocumentHeader(title: ""),
    sections: [
      Section(
        anchor: "section-1", title: "",
        blocks: [.paragraph(Paragraph(text: "Published in another form, in a file."))])
    ],
    source: .text)

  @Test func `a scan is its original in either mode, with or without a document`() {
    for showsOriginal in [false, true] {
      for document in [nil, pointer] {
        let page = PublishedOriginalPage(
          .rfc(8), formats: [.pdf], showsOriginal: showsOriginal, text: document)
        #expect(page?.original.format == .pdf)
        #expect(page?.explanation == "The RFC Editor publishes RFC 8 only as a scan.")
      }
    }
  }

  @Test func `a pointer is its original in place of the rendered text`() {
    let page = PublishedOriginalPage(
      .rfc(1119), formats: pointerFormats, showsOriginal: false, text: pointer)
    #expect(page?.original.format == .pdf)
    #expect(page?.explanation == "The text of RFC 1119 only says where its original is.")
  }

  @Test func `a pointer under Original Text is its text as published`() {
    #expect(
      PublishedOriginalPage(.rfc(1119), formats: pointerFormats, showsOriginal: true, text: pointer)
        == nil)
  }

  /// Until the text is here, nothing says it is a pointer.
  @Test func `a text still loading is not a pointer yet`() {
    #expect(
      PublishedOriginalPage(.rfc(1119), formats: pointerFormats, showsOriginal: false, text: nil)
        == nil)
  }

  @Test func `an original is offered by the name the Info pane gives its format`() {
    #expect(FileFormat.pdf.displayName == "PDF")
    #expect(FileFormat.postScript.displayName == "PostScript")
  }
}
