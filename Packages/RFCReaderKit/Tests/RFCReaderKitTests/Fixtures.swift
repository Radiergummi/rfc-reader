import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

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

    /// A one-section document around `blocks` — the shell almost every builder test
    /// needs and none of them is testing.
    static func document(_ blocks: Block...) -> RFCDocument {
        RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: blocks)],
            source: .xml
        )
    }

    /// Where `needle` starts, in the UTF-16 offsets `NSAttributedString.attribute(at:)`
    /// is indexed by. `String.distance` counts Characters, which is the same number
    /// only while the text stays in the BMP with no combining marks — not a property
    /// of RFCs worth relying on once per assertion.
    static func offset(of needle: String, in text: NSAttributedString) throws -> Int {
        let found = (text.string as NSString).range(of: needle)
        try #require(found.location != NSNotFound, "\(needle) is not in the storage")
        return found.location
    }

    /// One run of inlines, rendered against the body font.
    static func inlineRun(_ inlines: [Inline], style: ReadingStyle = ReadingStyle()) -> NSAttributedString {
        DocumentTextBuilder(style: style).inlineRuns(inlines, base: [.font: style.bodyFont])
    }
}
