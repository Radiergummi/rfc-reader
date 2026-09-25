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

    #if !canImport(UIKit)
    /// The reader turns AppKit's implicit link tooltips off, because they gave a
    /// reference its raw `rfc://` URL. An external link's destination is still worth
    /// reading before following it, so it carries its URL as an explicit tooltip; a
    /// reference, which has its preview, carries none.
    @Test func onlyAnExternalLinkCarriesATooltip() throws {
        let url = try #require(URL(string: "https://www.rfc-editor.org/"))
        let external = run([.link(url, [.text("the editor")])])
        #expect(external.attribute(.toolTip, at: 0, effectiveRange: nil) as? String == "https://www.rfc-editor.org/")

        let document = run([.crossReference(CrossReference(target: .document(.rfc(9110), section: "4.2")))])
        let anchor = run([.crossReference(CrossReference(target: .anchor("section-3"), text: "Section 3"))])
        for reference in [document, anchor] {
            reference.enumerateAttribute(.toolTip, in: NSRange(location: 0, length: reference.length)) { value, _, _ in
                #expect(value == nil)
            }
        }
    }
    #endif

    @Test func documentCrossReferencesLinkToTheAppScheme() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of [RFC 9110]")
        let attributed = run([.crossReference(xref)])
        #expect(attributed.string == "Section 4.2 of [RFC 9110]")
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.scheme == "rfc")
        #expect(url.absoluteString == "rfc://9110#section-4.2")
        #expect(attributed.attribute(.rfcReference, at: 0, effectiveRange: nil) is ReferenceBox)
    }

    @Test func anchorCrossReferencesUseThePrivateAnchorScheme() throws {
        let xref = CrossReference(target: .anchor("section-3"), text: "Section 3")
        let attributed = run([.crossReference(xref)])
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.absoluteString == "rfc-anchor:section-3")
    }

    /// A reference with no text of its own is one the source left to us, so the
    /// reader composes it and draws it as a chip. The plain form it composes -- what
    /// `label` gives, brackets and all -- is what goes out through the serializer.
    @Test func aCrossReferenceWithoutTextIsComposedAndChipped() {
        let chipPrefix = "\u{FFFC}\u{2060}"

        let withSection = CrossReference(target: .document(.rfc(2119), section: "2"))
        #expect(withSection.label == "Section\u{00A0}2 of [RFC\u{00A0}2119]")
        #expect(run([.crossReference(withSection)]).string == chipPrefix + "RFC\u{00A0}2119\u{00A0}§\u{00A0}2")

        let withoutSection = CrossReference(target: .document(.rfc(2119), section: nil))
        #expect(withoutSection.label == "[RFC\u{00A0}2119]")
        #expect(run([.crossReference(withoutSection)]).string == chipPrefix + "RFC\u{00A0}2119")
    }

    /// `bare` is the source asking for the section number on its own, which is a
    /// wording decision -- so it is left alone rather than composed over.
    @Test func aBareSectionFormatIsNotChipped() {
        let xref = CrossReference(target: .document(.rfc(2119), section: "2"), sectionFormat: .bare)
        #expect(xref.displayLabel == "2")
        #expect(run([.crossReference(xref)]).attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
    }

    @Test func lineBreaksBecomeNewlines() {
        #expect(run([.text("a"), .lineBreak, .text("b")]).string == "a\nb")
    }
}
