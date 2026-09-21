import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: reference chips")
@MainActor
struct BuilderChipTests {
    private let style = ReadingStyle()

    private func run(_ xref: CrossReference) -> NSAttributedString {
        DocumentTextBuilder.inlineRuns([.crossReference(xref)], style: style, base: [.font: style.bodyFont])
    }

    @Test func aCanonicalLabelLosesItsBrackets() {
        let xref = CrossReference(target: .document(.rfc(9110), section: nil), text: "[RFC\u{00A0}9110]", isCanonicalLabel: true)
        #expect(run(xref).string == "\u{FFFC}RFC\u{00A0}9110")
    }

    @Test func aCanonicalLabelInsideASectionPhraseLosesOnlyItsOwnBrackets() {
        let xref = CrossReference(
            target: .document(.rfc(9110), section: "4.2"),
            text: "Section\u{00A0}4.2 of [RFC\u{00A0}9110]",
            isCanonicalLabel: true
        )
        #expect(run(xref).string == "Section\u{00A0}4.2 of \u{FFFC}RFC\u{00A0}9110")
    }

    @Test func onlyThePreviouslyBracketedRunIsAChip() throws {
        let xref = CrossReference(
            target: .document(.rfc(9110), section: "4.2"),
            text: "Section\u{00A0}4.2 of [RFC\u{00A0}9110]",
            isCanonicalLabel: true
        )
        let attributed = run(xref)
        let chipStart = try #require(attributed.string.range(of: "RFC\u{00A0}9110"))
        let offset = attributed.string.distance(from: attributed.string.startIndex, to: chipStart.lowerBound)
        #expect(attributed.attribute(.rfcChip, at: offset, effectiveRange: nil) != nil)
        #expect(attributed.attribute(.rfcChip, at: 0, effectiveRange: nil) == nil, "\"Section 4.2 of \" is plain link text")
    }

    @Test func anAuthorTagKeepsItsBracketsAndGetsNoChip() {
        let xref = CrossReference(target: .document(.rfc(9000), section: nil), text: "[QUIC-TRANSPORT]", isCanonicalLabel: false)
        let attributed = run(xref)
        #expect(attributed.string == "[QUIC-TRANSPORT]")
        #expect(attributed.attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
    }

    @Test func theWholeLabelStaysALinkEitherWay() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: nil), text: "[RFC\u{00A0}9110]", isCanonicalLabel: true)
        let attributed = run(xref)
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.absoluteString == "rfc://9110")
    }
}
