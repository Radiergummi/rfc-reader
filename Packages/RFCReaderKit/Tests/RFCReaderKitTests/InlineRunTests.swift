import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Inline runs")
@MainActor
struct InlineRunTests {
    private let style = ReadingStyle()

    private func run(_ inlines: [Inline]) -> NSAttributedString {
        Fixtures.inlineRun(inlines, style: style)
    }

    @Test func plainTextSurvives() {
        #expect(run([.text("hello")]).string == "hello")
    }

    @Test func emphasisAndStrongChangeTheFont() {
        let emphasised = run([.emphasis([.text("x")])])
        let font = try? #require(emphasised.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
        #expect(font?.fontDescriptor.symbolicTraits.contains(RFCTraits.italic) == true)

        let strong = run([.strong([.text("x")])])
        let boldFont = strong.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(RFCTraits.bold) == true)
    }

    @Test func codeUsesTheMonospacedFont() {
        let code = run([.code("GET")])
        let font = code.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(font == style.codeFont)
    }

    @Test func linksCarryTheirURL() throws {
        let url = try #require(URL(string: "https://example.org"))
        let link = run([.link(url, [.text("example")])])
        #expect(link.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
    }

    @Test func documentCrossReferencesLinkToTheAppScheme() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of [RFC 9110]")
        let attributed = run([.crossReference(xref)])
        #expect(attributed.string == "Section 4.2 of [RFC 9110]")
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.scheme == "rfc")
        #expect(url.absoluteString == "rfc://9110/section/4.2")
        #expect(attributed.attribute(.rfcReference, at: 0, effectiveRange: nil) is ReferenceBox)
    }

    @Test func anchorCrossReferencesUseThePrivateAnchorScheme() throws {
        let xref = CrossReference(target: .anchor("section-3"), text: "Section 3")
        let attributed = run([.crossReference(xref)])
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.absoluteString == "rfc-anchor:section-3")
    }

    @Test func aCrossReferenceWithoutTextFallsBackToADerivedLabel() {
        let withSection = CrossReference(target: .document(.rfc(2119), section: "2"))
        #expect(run([.crossReference(withSection)]).string == "Section 2 of RFC 2119")

        let withoutSection = CrossReference(target: .document(.rfc(2119), section: nil))
        #expect(run([.crossReference(withoutSection)]).string == "[RFC2119]")
    }

    @Test func lineBreaksBecomeNewlines() {
        #expect(run([.text("a"), .lineBreak, .text("b")]).string == "a\nb")
    }
}
