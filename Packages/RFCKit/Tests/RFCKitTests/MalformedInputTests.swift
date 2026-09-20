import Foundation
import Testing
@testable import RFCKit

@Suite("Malformed input")
struct MalformedInputTests {
    @Test func truncatedIndexIsRejected() throws {
        let data = try Fixtures.data("rfc-index-sample.xml")
        let truncated = data.prefix(data.count / 2)
        #expect(throws: RFCIndexParser.ParseError.self) {
            try RFCIndexParser.parse(truncated)
        }
    }

    @Test func truncatedDocumentIsRejected() throws {
        let data = try Fixtures.data("rfc8999.xml")
        let truncated = data.prefix(data.count / 2)
        #expect(throws: RFCXMLParser.ParseError.self) {
            try RFCXMLParser.parse(truncated)
        }
    }

    @Test func emptyTextStillProducesADocument() {
        let document = LegacyTextParser.parse("")
        #expect(document.sections.isEmpty)
        #expect(document.header.id == nil)
    }
}
