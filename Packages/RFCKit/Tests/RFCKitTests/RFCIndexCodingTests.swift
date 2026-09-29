import Foundation
import Testing

@testable import RFCKit

@Suite("RFC index coding")
struct RFCIndexCodingTests {
  @Test func `an index survives a round trip through JSON`() throws {
    let index = try Fixtures.sampleIndex()
    let decoded = try JSONDecoder().decode(RFCIndex.self, from: JSONEncoder().encode(index))
    #expect(decoded.rfcs == index.rfcs)
    #expect(decoded.series == index.series)
    #expect(decoded.notIssued == index.notIssued)
  }

  @Test func `a decoded index answers lookups by number`() throws {
    let index = try Fixtures.sampleIndex()
    let decoded = try JSONDecoder().decode(RFCIndex.self, from: JSONEncoder().encode(index))
    #expect(decoded[9110]?.title == "HTTP Semantics")
    #expect(decoded.latestNumber == index.latestNumber)
  }
}
