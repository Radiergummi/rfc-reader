import Foundation
import Testing
@testable import corpus_build

/// What `SchemaCheck.causes(in:)` finds, one cause at a time. The cause finder is a
/// guard over a document's shape, not a parser of RFCs, so each case is the smallest
/// document that has exactly that cause; the controls are two RFCs as the RFC Editor
/// published them, which `make corpus-schema-control` has xmllint accept.
@Suite("Schema check: causes")
struct SchemaCheckTests {
    /// A front with an author and a middle with a section, around `middle`.
    private static func document(front: String = "<author/>", middle: String = "<section><t>x</t></section>", back: String = "") -> String {
        #"<rfc><front><title>t</title>\#(front)</front><middle>\#(middle)</middle>\#(back.isEmpty ? "" : "<back>\(back)</back>")</rfc>"#
    }

    private static func causes(_ xml: String) -> [SchemaCheck.Cause] {
        SchemaCheck.causes(in: Data(xml.utf8))
    }

    @Test func aMinimalDocumentHasNoCause() {
        #expect(Self.causes(Self.document()) == [])
    }

    @Test(arguments: [
        (document(front: ""), SchemaCheck.Cause.frontWithoutAuthor),
        (document(middle: #"<section anchor="section-1" pn="section-1"><t>x</t></section>"#), .anchorEqualsPartNumber),
        (document(middle: #"<section anchor="1"><t>x</t></section>"#), .idNotNCName),
        (document(middle: "<section><ul><li>x<t>y</t></li></ul></section>"), .inlineBesideBlocks),
        (document(middle: #"<section anchor="a"><t anchor="a">x</t></section>"#), .duplicateID),
        (document(middle: #"<section><t><xref target="nowhere"/></t></section>"#), .danglingTarget),
        (document(middle: #"<section><t><relref target="nowhere"/></t></section>"#), .danglingTarget),
        (document(middle: #"<section><name slugifiedName="n">x</name></section><section anchor="n"><t>y</t></section>"#), .duplicateID),
        (document(middle: #"<section><references><name>R</name></references></section>"#), .misplacedReferences),
        (document(middle: ""), .emptyMiddle),
        (document(front: "<author/><abstract><artwork>x</artwork></abstract>"), .blockInAbstract),
    ])
    func eachCauseIsFoundAlone(xml: String, cause: SchemaCheck.Cause) {
        #expect(Self.causes(xml) == [cause], "\(xml)")
    }

    @Test func aReferencesListBesideEntriesIsMisplaced() {
        let back = #"<references><reference anchor="r"><front><title>t</title><author/></front></reference><references/></references>"#
        #expect(Self.causes(Self.document(back: back)) == [.misplacedReferences])
    }

    @Test func aReferenceFrontNeedsAnAuthorToo() {
        let back = #"<references><reference anchor="r"><front><title>t</title></front></reference></references>"#
        #expect(Self.causes(Self.document(back: back)) == [.frontWithoutAuthor])
    }

    @Test func causesComeInDeclarationOrder() {
        #expect(Self.causes(Self.document(front: "", middle: "")) == [.frontWithoutAuthor, .emptyMiddle])
    }

    @Test(arguments: ["rfc8999.xml", "rfc9220.xml"])
    func publishedRFCsHaveNoCause(fixture: String) throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appending(path: "../../../../Packages/RFCKit/Tests/RFCKitTests/Fixtures/\(fixture)")
        #expect(SchemaCheck.causes(in: try Data(contentsOf: url)) == [])
    }
}
