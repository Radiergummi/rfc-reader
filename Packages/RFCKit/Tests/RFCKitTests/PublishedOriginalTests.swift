import Foundation
import Testing

@testable import RFCKit

/// When an RFC is its PDF or PostScript original rather than its text (#207): the
/// index lists no text to read, or the text only says where the original is.
@Suite("Published originals")
struct PublishedOriginalTests {
  private let pointerFormats: [FileFormat] = [.text, .postScript, .pdf, .html]

  @Test func `a document the index lists only as a PDF is its PDF`() {
    #expect(PublishedOriginal(.rfc(8), formats: [.pdf])?.format == .pdf)
  }

  @Test func `the PDF is preferred to the PostScript`() {
    #expect(PublishedOriginal(.rfc(8), formats: [.postScript, .pdf])?.format == .pdf)
    #expect(PublishedOriginal(.rfc(8), formats: [.postScript])?.format == .postScript)
  }

  @Test func `a document with a text or XML to read is not its original`() {
    #expect(PublishedOriginal(.rfc(12), formats: [.text, .postScript, .pdf]) == nil)
    #expect(PublishedOriginal(.rfc(9110), formats: [.xml, .pdf]) == nil)
  }

  /// No formats is an index that does not know the document, not one that says there
  /// is nothing to read.
  @Test func `no formats is no original`() {
    #expect(PublishedOriginal(.rfc(8), formats: []) == nil)
    #expect(PublishedOriginal(.rfc(8), formats: [.html]) == nil)
  }

  @Test func `the original is where the RFC Editor hosts it`() {
    #expect(
      PublishedOriginal(.rfc(8), formats: [.pdf])?.url.absoluteString
        == "https://www.rfc-editor.org/rfc/rfc8.pdf")
  }

  /// A pointer is one paragraph at most, beside a PostScript original; the shortest
  /// real documents with an original beside them have three blocks or more.
  @Test func `a text of one paragraph beside an original is a pointer to it`() {
    let pointer = RFCDocument(
      header: DocumentHeader(title: ""),
      sections: [
        Section(
          anchor: "section-1", title: "",
          blocks: [.paragraph(Paragraph(text: "Published in another form, in a file."))])
      ],
      source: .text)
    #expect(PublishedOriginal(.rfc(1119), formats: pointerFormats, text: pointer)?.format == .pdf)
    #expect(PublishedOriginal(.rfc(1119), formats: [.text], text: pointer) == nil)
    // PostScript is what marks the era: most RFCs list a PDF.
    #expect(PublishedOriginal(.rfc(1119), formats: [.text, .pdf, .html], text: pointer) == nil)

    var twoParagraphs = pointer
    twoParagraphs.sections[0].blocks.append(.paragraph(Paragraph(text: "And more.")))
    #expect(PublishedOriginal(.rfc(1119), formats: pointerFormats, text: twoParagraphs) == nil)
  }

  @Test func `an empty text beside an original is a pointer to it`() {
    let empty = RFCDocument(header: DocumentHeader(title: ""), sections: [], source: .text)
    #expect(PublishedOriginal(.rfc(570), formats: pointerFormats, text: empty)?.format == .pdf)
  }

  @Test func `a short RFC is its text, whatever else is published`() throws {
    let document = LegacyTextParser.parse(try Fixtures.data("rfc1149.txt"))
    #expect(PublishedOriginal(.rfc(1149), formats: pointerFormats, text: document) == nil)
  }
}

@Suite("Corpus-backed: published originals", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedPublishedOriginalTests {
  private let formats: [FileFormat] = [.text, .postScript, .pdf, .html]

  /// Every text in the corpus whose index entry lists a PDF or a PostScript original
  /// and that parses to one block or none, measured over the whole corpus: each only
  /// says where its original is.
  @Test(arguments: [570, 1119, 1124, 1128, 1129, 1131])
  func `a text that points to its original is not the document`(number: Int) throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc\(number)"))
    #expect(PublishedOriginal(.rfc(number), formats: formats, text: document)?.format == .pdf)
  }

  /// The next shortest with an original beside them, at three blocks each: real
  /// documents, read as their text.
  @Test(arguments: [270, 574])
  func `a short text with an original beside it is the document`(number: Int) throws {
    let document = LegacyTextParser.parse(try CorpusText.text("rfc\(number)"))
    #expect(PublishedOriginal(.rfc(number), formats: formats, text: document) == nil)
  }
}
