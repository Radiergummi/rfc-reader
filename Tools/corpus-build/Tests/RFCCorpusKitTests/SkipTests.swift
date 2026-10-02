import Foundation
import RFCKit
import Testing

@testable import RFCCorpusKit

/// The documents a convert run writes no XML for, and says why (#316): a text that only
/// says where the RFC's PDF or PostScript original is.
@Suite("Conversion: skipped documents")
struct SkipTests {
  private static let pointerFormats: [FileFormat] = [.text, .postScript, .pdf, .html]

  private static func metadata(_ number: Int, formats: [FileFormat]) -> RFCMetadata {
    RFCMetadata(
      id: .rfc(number), title: "", date: PublicationDate(year: 1990), formats: formats)
  }

  /// A model of what such a text parses to: one paragraph, beside a listed PostScript
  /// original. `PublishedOriginal` decides, as it does in the app.
  private static let pointer = RFCDocument(
    header: DocumentHeader(title: ""),
    sections: [
      Section(
        anchor: "section-1", title: "",
        blocks: [.paragraph(Paragraph(text: "Published in another form, in a file."))])
    ],
    source: .text)

  @Test func `a text that points to its original is skipped`() {
    let skip = DocumentConverter.skip(
      Self.pointer, metadata: Self.metadata(1119, formats: Self.pointerFormats))
    #expect(skip == .publishedOnlyAsPDF)
    #expect(skip?.rawValue == "published-only-as-pdf")
  }

  /// Whether the RFC has an original is the index's to say, so a run without one
  /// converts everything, and so does one whose entry lists no PostScript.
  @Test func `without an index entry listing an original, nothing is skipped`() {
    #expect(DocumentConverter.skip(Self.pointer, metadata: nil) == nil)
    #expect(
      DocumentConverter.skip(
        Self.pointer, metadata: Self.metadata(1119, formats: [.text, .pdf]))
        == nil)
  }

  /// A real document converts, whatever else is published of it.
  @Test func `a short RFC with an original beside it is converted`() throws {
    let text = LegacyTextParser.text(decoding: try Data(contentsOf: Fixtures.url("rfc1149.txt")))
    let conversion = DocumentConverter().convert(
      text: text, stem: "rfc1149", metadata: Self.metadata(1149, formats: Self.pointerFormats))
    #expect(conversion.xml != nil)
    #expect(conversion.report.skipped == nil)
  }

  /// The field is left out of a converted document's entry, so a report of a run that
  /// skipped nothing reads as it did before there was one.
  @Test func `a converted document's report has no skipped field`() throws {
    let text = LegacyTextParser.text(decoding: try Data(contentsOf: Fixtures.url("rfc1149.txt")))
    let report = DocumentConverter().convert(text: text, stem: "rfc1149", metadata: nil).report
    let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
    #expect(!json.contains("skipped"))
  }
}

@Suite("Corpus-backed: skipped documents", .enabled(if: CorpusText.isAvailable))
struct CorpusBackedSkipTests {
  private static let formats: [FileFormat] = [.text, .postScript, .pdf, .html]

  /// Every text in the corpus that only says where its original is (#316). Each is
  /// skipped with no XML, and with no warning about the document it is not.
  @Test(arguments: [570, 1119, 1124, 1128, 1129, 1131])
  func `a text that points to its original converts to nothing`(number: Int) throws {
    let metadata = RFCMetadata(
      id: .rfc(number), title: "", date: PublicationDate(year: 1990), formats: Self.formats)
    let conversion = DocumentConverter().convert(
      text: try CorpusText.text("rfc\(number)"), stem: "rfc\(number)", metadata: metadata)
    #expect(conversion.xml == nil)
    #expect(conversion.report.skipped == .publishedOnlyAsPDF)
    #expect(conversion.report.warnings == [])
  }

  /// The next shortest texts with an original beside them are documents, and convert.
  @Test(arguments: [270, 574])
  func `a short text with an original beside it converts`(number: Int) throws {
    let metadata = RFCMetadata(
      id: .rfc(number), title: "", date: PublicationDate(year: 1970), formats: Self.formats)
    let conversion = DocumentConverter().convert(
      text: try CorpusText.text("rfc\(number)"), stem: "rfc\(number)", metadata: metadata)
    #expect(conversion.xml != nil)
    #expect(conversion.report.skipped == nil)
  }
}
