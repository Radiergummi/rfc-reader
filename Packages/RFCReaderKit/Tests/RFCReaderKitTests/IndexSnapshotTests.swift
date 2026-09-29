import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Index snapshot")
struct IndexSnapshotTests {
  private let index = Date(timeIntervalSince1970: 1_000)
  private let app = Date(timeIntervalSince1970: 2_000)

  @Test func `a snapshot decodes to the index it was made from`() throws {
    let parsed = try RFCIndexParser.parse(Fixtures.rfcKitData("rfc-index-sample.xml"))
    let decoded = try IndexSnapshot.decode(IndexSnapshot.encode(parsed))
    #expect(decoded.rfcs == parsed.rfcs)
    #expect(decoded.series == parsed.series)
    #expect(decoded.notIssued == parsed.notIssued)
  }

  @Test func `a snapshot written after the index and the app is current`() {
    let written = Date(timeIntervalSince1970: 3_000)
    #expect(IndexSnapshot.isCurrent(written: written, index: index, app: app))
  }

  @Test func `a snapshot older than the index is stale`() {
    let written = Date(timeIntervalSince1970: 500)
    #expect(!IndexSnapshot.isCurrent(written: written, index: index, app: Date.distantPast))
  }

  @Test func `a snapshot older than the app is stale`() {
    let written = Date(timeIntervalSince1970: 1_500)
    #expect(!IndexSnapshot.isCurrent(written: written, index: index, app: app))
  }

  @Test func `no snapshot is not current`() {
    #expect(!IndexSnapshot.isCurrent(written: nil, index: index, app: app))
  }
}
