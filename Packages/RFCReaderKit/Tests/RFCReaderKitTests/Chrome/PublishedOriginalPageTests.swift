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

  /// The installed pack lists it as a pointer (#316), so the page needs no text,
  /// online or off. Original Text still shows the text as published.
  @Test func `a pointer the pack lists is its original without the text`() {
    let page = PublishedOriginalPage(
      .rfc(1119), formats: pointerFormats, showsOriginal: false, text: nil, pointerInPack: true)
    #expect(page?.original.format == .pdf)
    #expect(page?.explanation == "The text of RFC 1119 only says where its original is.")
    #expect(
      PublishedOriginalPage(
        .rfc(1119), formats: pointerFormats, showsOriginal: true, text: nil, pointerInPack: true)
        == nil)
  }

  @Test func `an original is offered by the name the Info pane gives its format`() {
    #expect(FileFormat.pdf.displayName == "PDF")
    #expect(FileFormat.postScript.displayName == "PostScript")
  }
}

/// What else changes for an RFC read as its original (#207): a scan has no text to
/// fetch, and neither kind is printed or exported, since the text is not the RFC.
@Suite("Published original: load, print and export")
struct PublishedOriginalActionsTests {
  private let pointer = RFCDocument(
    header: DocumentHeader(title: ""),
    sections: [
      Section(
        anchor: "section-1", title: "",
        blocks: [.paragraph(Paragraph(text: "Published in another form, in a file."))])
    ],
    source: .text)

  @Test func `the kind is the same in either mode`() {
    #expect(PublishedOriginalPage.Status(.rfc(8), formats: [.pdf], text: nil)?.kind == .scan)
    #expect(
      PublishedOriginalPage.Status(.rfc(1119), formats: [.text, .postScript, .pdf], text: pointer)?
        .kind == .pointer)
    #expect(
      PublishedOriginalPage.Status(.rfc(1119), formats: [.text, .postScript], text: nil) == nil)
    #expect(
      PublishedOriginalPage.Status(
        .rfc(1119), formats: [.text, .postScript], text: nil, pointerInPack: true)?.kind
        == .pointer)
  }

  /// What the panel says in place of its lists: why there are none, not that the
  /// RFC failed to load.
  @Test func `the panel says the RFC is its original`() {
    #expect(
      PublishedOriginalPage.Status(.rfc(8), formats: [.pdf], text: nil)?.panelExplanation
        == "RFC 8 is published only as PDF.")
    #expect(
      PublishedOriginalPage.Status(.rfc(8), formats: [.postScript], text: nil)?.panelExplanation
        == "RFC 8 is published only as PostScript.")
    #expect(
      PublishedOriginalPage.Status(.rfc(1119), formats: [.text, .postScript, .pdf], text: pointer)?
        .panelExplanation == "The text of RFC 1119 only says where its PDF original is.")
  }

  /// A scan has no text to fetch; an index that does not know the document yet, or
  /// lists a text, leaves the load to find out.
  @Test func `a scan skips the load`() {
    #expect(!PublishedOriginalPage.loadsText(.rfc(8), formats: [.pdf]))
    #expect(PublishedOriginalPage.loadsText(.rfc(8), formats: nil))
    #expect(PublishedOriginalPage.loadsText(.rfc(1119), formats: [.text, .postScript, .pdf]))
  }

  /// Nor does a text the installed pack lists as only pointing to its original
  /// (#316): the pack has no XML of it, and offline there would be no text either.
  @Test func `a pointer the pack lists skips the load`() {
    #expect(
      !PublishedOriginalPage.loadsText(
        .rfc(1119), formats: [.text, .postScript, .pdf], pointerInPack: true))
  }

  /// Only where the page can show the original instead: an index without the
  /// document yet, or one listing no original, leaves it to the fetch, rather than to
  /// a reader with neither a load nor a page.
  @Test func `a pointer the pack lists loads when there is no original to show`() {
    #expect(PublishedOriginalPage.loadsText(.rfc(1119), formats: nil, pointerInPack: true))
    #expect(PublishedOriginalPage.loadsText(.rfc(1119), formats: [.text], pointerInPack: true))
  }

  @Test func `a document read as its text is printed and exported`() {
    #expect(PublishedOriginalPage.offersPrintAndExport(hasDocument: true, kind: nil))
  }

  @Test func `nothing is printed or exported without a document`() {
    #expect(!PublishedOriginalPage.offersPrintAndExport(hasDocument: false, kind: nil))
    #expect(!PublishedOriginalPage.offersPrintAndExport(hasDocument: false, kind: .scan))
  }

  /// The pointer loaded, but printing it would print the line that says where the
  /// RFC is, not the RFC.
  @Test func `a pointer is neither printed nor exported`() {
    #expect(!PublishedOriginalPage.offersPrintAndExport(hasDocument: true, kind: .pointer))
  }
}
