import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("RFC Editor formats")
struct ClientFormatsTests {
  @Test func perDocumentJSON() throws {
    let record = try JSONDecoder().decode(
      RFCEditorMetadataRecord.self, from: try Fixtures.data("rfc9110.json"))
    #expect(record.id == .rfc(9110))
    #expect(record.currentStatus == .internetStandard)
    #expect(record.obsoletes.count == 9)
    #expect(record.pubDate == "June 2022")
    #expect(record.errataURL == "https://www.rfc-editor.org/errata/rfc9110")
  }

  @Test func recentFeed() throws {
    let recent = try RecentFeedParser.parse(try Fixtures.data("rfcrss.xml"))
    #expect(recent.count > 5)
    let first = try #require(recent.first)
    #expect(first.id == .rfc(10050))
    #expect(first.title == "Protocol-Specific Profiles for JSContact")
    #expect(first.link?.absoluteString == "https://www.rfc-editor.org/info/rfc10050/")
    #expect(first.publishedAt != nil)
    #expect(first.summary.hasPrefix("This document defines"))
  }

  @Test func endpoints() {
    let id = DocumentID.rfc(9110)
    #expect(
      RFCEditorEndpoints.document(id, format: .xml).absoluteString
        == "https://www.rfc-editor.org/rfc/rfc9110.xml")
    #expect(
      RFCEditorEndpoints.metadata(id).absoluteString
        == "https://www.rfc-editor.org/rfc/rfc9110.json")
    #expect(
      RFCEditorEndpoints.infoPage(id).absoluteString == "https://www.rfc-editor.org/info/rfc9110")
    #expect(
      RFCEditorEndpoints.datatracker(id, section: "4.2").absoluteString
        == "https://datatracker.ietf.org/doc/html/rfc9110#section-4.2")
  }

  @Test func clientFallsBackToText() async throws {
    struct FakeTransport: HTTPTransport {
      let text: Data
      func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
        let status = url.pathExtension == "xml" ? 404 : 200
        let response = HTTPURLResponse(
          url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (status == 200 ? text : Data(), response)
      }
    }
    let client = RFCEditorClient(transport: FakeTransport(text: try Fixtures.data("rfc1149.txt")))
    let document = try await client.fetchDocument(.rfc(1149))
    #expect(document.source == .text)
    #expect(document.header.id == .rfc(1149))
  }
}
