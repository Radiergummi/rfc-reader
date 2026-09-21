import Foundation
import RFCKit
import Testing

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// RFCXML v3: structured sections, tables, cross references with derivedContent.
    static func rfc8999() throws -> RFCDocument {
        try RFCXMLParser.parse(try data("rfc8999.xml"))
    }

    /// Legacy plain text: structure recovered heuristically, labels verbatim.
    static func rfc2119() throws -> RFCDocument {
        LegacyTextParser.parse(try data("rfc2119.txt"))
    }
}
