import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("RFC Editor formats")
struct ClientFormatsTests {
  /// The text is the document only when the formats given hold no XML: then the
  /// reader's load and Original Text fetch the same `.txt`, and share one download
  /// (#324). With no formats given, the XML is tried first.
  @Test func `the text is all there is only when the formats hold no XML`() {
    #expect(RFCEditorClient.textIsTheDocument(availableFormats: [.text, .pdf]))
    #expect(!RFCEditorClient.textIsTheDocument(availableFormats: [.xml, .text]))
    #expect(!RFCEditorClient.textIsTheDocument(availableFormats: nil))
  }

  @Test func `recent feed`() throws {
    let recent = try RecentFeedParser.parse(try Fixtures.data("rfcrss.xml"))
    #expect(recent.count > 5)
    let first = try #require(recent.first)
    #expect(first.id == .rfc(10050))
    #expect(first.title == "Protocol-Specific Profiles for JSContact")
    #expect(first.link?.absoluteString == "https://www.rfc-editor.org/info/rfc10050/")
    #expect(first.summary.hasPrefix("This document defines"))
  }

  /// RFC 822 dates, pinned before the parse moved from a `DateFormatter` to a
  /// `Date.ParseStrategy` (#148): every item has one, and they are the feed's instants.
  @Test func `every recent RFC has the date the feed gives`() throws {
    let recent = try RecentFeedParser.parse(try Fixtures.data("rfcrss.xml"))
    #expect(recent.allSatisfy { $0.publishedAt != nil })
    #expect(recent.first?.publishedAt == Date(timeIntervalSince1970: 1_789_776_000))
    #expect(recent.contains { $0.publishedAt == Date(timeIntervalSince1970: 1_786_665_600) })
  }

  /// A date that does not exist is no date, as it was with the `DateFormatter`,
  /// rather than rolling over into the next month.
  @Test func `an impossible feed date does not parse`() {
    #expect(
      (try? Date("Thu, 31 Sep 2026 00:00:00 GMT", strategy: RecentFeedParser.dateStrategy)) == nil)
    #expect(
      (try? Date("Wed, 30 Sep 2026 00:00:00 GMT", strategy: RecentFeedParser.dateStrategy))
        == Date(timeIntervalSince1970: 1_790_726_400))
  }

  @Test func `endpoints`() {
    let id = DocumentID.rfc(9110)
    #expect(
      RFCEditorEndpoints.document(id, format: .xml).absoluteString
        == "https://www.rfc-editor.org/rfc/rfc9110.xml")
    #expect(
      RFCEditorEndpoints.infoPage(id).absoluteString == "https://www.rfc-editor.org/info/rfc9110")
    #expect(
      RFCEditorEndpoints.datatracker(id, section: "4.2").absoluteString
        == "https://datatracker.ietf.org/doc/html/rfc9110#section-4.2")
  }

  @Test func `client falls back to text`() async throws {
    struct FakeTransport: HTTPTransport {
      let text: Data
      func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let status = url.pathExtension == "xml" ? 404 : 200
        let response = HTTPURLResponse(
          url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (status == 200 ? text : Data(), response)
      }
    }
    let client = RFCEditorClient(transport: FakeTransport(text: try Fixtures.data("rfc1149.txt")))
    let document = try await client.fetchPreferredDocument(.rfc(1149)).document
    #expect(document.source == .text)
    #expect(document.header.id == .rfc(1149))
  }
}
