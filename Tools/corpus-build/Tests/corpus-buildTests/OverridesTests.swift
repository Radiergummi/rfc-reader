import Foundation
import RFCKit
import Testing
@testable import corpus_build

/// The committed overrides in `corpus/overrides/`, which `convert` publishes in place of
/// its own output. It checks them only during a corpus run, so this is what notices a
/// broken one before then. Whether a scripted override is still what its script makes
/// is `make overrides-check`, which needs the source text.
@Suite("Corpus overrides")
struct OverridesTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../corpus/overrides")

    private static let overrides: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".xml") }.sorted()
    }()

    private static func document(_ name: String) throws -> RFCDocument {
        try RFCXMLParser.parse(try Data(contentsOf: directory.appending(path: name)))
    }

    @Test func thereAreOverrides() {
        #expect(!Self.overrides.isEmpty)
    }

    @Test(arguments: overrides)
    func eachParsesWithNoKnownSchemaCause(name: String) throws {
        let data = try Data(contentsOf: Self.directory.appending(path: name))
        #expect(try !RFCXMLParser.parse(data).allSections.isEmpty)
        #expect(SchemaCheck.causes(in: data) == [])
    }

    /// RFC 1142's headings are recovered by `rfc1142.py`: every numbered heading of the
    /// standard, and none of the fragments a form feed used to cut a title into.
    @Test func rfc1142HasEveryNumberedHeading() throws {
        let sections = try Self.document("rfc1142.xml").allSections
        #expect(sections.count { $0.number != nil } == 255)
        let short = sections.map(\.titleText).filter { $0.count < 4 }
        #expect(short.isEmpty, "\(short)")
    }
}
