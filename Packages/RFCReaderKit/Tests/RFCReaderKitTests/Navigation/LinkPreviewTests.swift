import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a force click or a long press on a reference previews (#29): the document
/// it names, at the place it names, the way Safari previews a link — or, for a
/// bibliography entry that names no RFC, the card, because there is no web view.
@Suite("Link preview")
struct LinkPreviewTests {
  private let current = DocumentID.rfc(9110)
  private let other = DocumentID.rfc(8446)
  private let bcp14 = DocumentID(series: .bcp, number: 14)

  private func resolve(_ string: String) -> LinkPreview? {
    LinkPreview.resolve(
      URL(string: string)!, from: current,
      in: RFCIndex(
        rfcs: [], series: [SeriesEntry(id: bcp14, members: [.rfc(2119), .rfc(8174)])]))
  }

  @Test func `another RFC previews that RFC from the top`() {
    #expect(resolve(RFCLink(id: other).appURL.absoluteString) == .document(other, place: nil))
  }

  /// A click on a series reference opens its first member (`NavigationModel.open`),
  /// so the preview shows that one too: the series has no document of its own.
  @Test func `a series previews its first member RFC`() {
    #expect(resolve(RFCLink(id: bcp14).appURL.absoluteString) == .document(.rfc(2119), place: nil))
  }

  @Test func `a section of another RFC previews it at that section`() {
    #expect(
      resolve(RFCLink(id: other, section: "4.2").appURL.absoluteString)
        == .document(other, place: "4.2"))
  }

  /// The reader underneath stays where it is; the preview is a second view of the
  /// same document, opened at the target.
  @Test func `an anchor in this document previews this document there`() {
    #expect(
      resolve("\(DocumentTextBuilder.anchorScheme):section-4.2")
        == .document(current, place: "section-4.2"))
  }

  @Test func `a section of this document by number previews this document there`() {
    #expect(
      resolve(RFCLink(id: current, section: "8.3").appURL.absoluteString)
        == .document(current, place: "8.3"))
  }

  @Test func `a bibliography entry that names no RFC keeps its card`() {
    #expect(
      resolve("\(DocumentTextBuilder.referenceScheme):IEEE.802.3_2018")
        == .card("IEEE.802.3_2018"))
  }

  @Test func `a link to the web previews nothing`() {
    #expect(resolve("https://www.iana.org/assignments/") == nil)
  }

  /// A section of an entry outside the series links to the web, and previews the
  /// entry's card all the same: the entry is what the reader knows of it (#473).
  @Test func `a section of an entry outside the series previews the entry's card`() throws {
    let page = try #require(URL(string: "https://fetch.spec.whatwg.org/#cors-check"))
    let reference = CrossReference(
      target: .entrySection(entry: "FETCH", tag: "FETCH", section: "4.9", url: page))
    #expect(
      LinkPreview.resolve(reference, linkedTo: page, from: current, in: nil) == .card("FETCH"))
  }

  /// macOS's popover gets the whole preview; a phone's context menu gets what its
  /// screen leaves beside the gutters, and room under it for the menu.
  @Test func `the document preview is its full size where it fits`() {
    let large = CGSize(width: 1_200, height: 1_200)
    #expect(LinkPreview.documentSize(fitting: large) == LinkPreview.documentSize)
  }

  @Test func `on a phone the document preview keeps its gutters and leaves room for the menu`() {
    let phone = CGSize(width: 393, height: 852)
    #expect(LinkPreview.documentSize(fitting: phone) == CGSize(width: 361, height: 511))
  }
}
