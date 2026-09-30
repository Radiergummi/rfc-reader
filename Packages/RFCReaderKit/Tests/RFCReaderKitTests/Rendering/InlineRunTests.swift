import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Inline runs")
struct InlineRunTests {
  private let style = ReadingStyle()

  @Test func `plain text survives`() {
    #expect(Fixtures.inlineRun([.text("hello")]).string == "hello")
  }

  @Test func `emphasis and strong change the font`() throws {
    let emphasized = Fixtures.inlineRun([.emphasis([.text("x")])])
    let font = try #require(
      emphasized.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.italic))

    let strong = Fixtures.inlineRun([.strong([.text("x")])])
    let boldFont = strong.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
    #expect(boldFont?.fontDescriptor.symbolicTraits.contains(RFCTraits.bold) == true)
  }

  @Test func `code uses the monospaced font`() {
    let code = Fixtures.inlineRun([.code("GET")])
    let font = code.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
    #expect(font == .monospacedSystemFont(ofSize: style.bodySize * 0.92, weight: .regular))
  }

  /// Code, superscript and subscript each replaced the font with one sized from the
  /// body, whatever surrounded them: `code` in a heading dropped to body size, and a
  /// superscript inside strong text lost its weight (#154). Each is now made from the
  /// font in effect.
  @Test func `code in a heading is scaled from the heading`() throws {
    let heading = style.headingFont(depth: 1)
    let run = DocumentTextBuilder(style: style).inlineRuns(
      [.text("Changes to "), .code("foo")], base: [.font: heading])
    let offset = try Fixtures.offset(of: "foo", in: run)
    let font = try #require(run.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
    #expect(font.pointSize == heading.pointSize * 0.92)
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.monospace))
    #expect(font.weight == heading.weight)
  }

  @Test func `code in emphasis stays italic`() throws {
    let emphasized = Fixtures.inlineRun([.emphasis([.text("see "), .code("foo")])])
    let offset = try Fixtures.offset(of: "foo", in: emphasized)
    let font = try #require(
      emphasized.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.italic))
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.monospace))
  }

  /// A bold italic face states no weight in its descriptor, only the bold trait, so
  /// code inside strong emphasis came out regular italic.
  @Test func `code in strong emphasis stays bold and italic`() throws {
    let text = Fixtures.inlineRun([.strong([.emphasis([.text("see "), .code("foo")])])])
    let offset = try Fixtures.offset(of: "foo", in: text)
    let font = try #require(text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.bold))
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.italic))
    #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.monospace))
  }

  @Test func `a superscript or subscript keeps the traits around it`() throws {
    let strong = Fixtures.inlineRun([.strong([.text("x"), .superscript("2"), .subscript("i")])])
    for script in ["2", "i"] {
      let offset = try Fixtures.offset(of: script, in: strong)
      let font = try #require(
        strong.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
      #expect(font.fontDescriptor.symbolicTraits.contains(RFCTraits.bold), "\(script) lost bold")
      #expect(font.pointSize == style.bodySize * 0.75)
    }
  }

  @Test func `links carry their URL`() throws {
    let url = try #require(URL(string: "https://example.org"))
    let link = Fixtures.inlineRun([.link(url, [.text("example")])])
    #expect(link.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
  }

  #if !canImport(UIKit)
    /// The reader turns AppKit's implicit link tooltips off, because they gave a
    /// reference its raw `rfc://` URL. An external link's destination is still worth
    /// reading before following it, so it carries its URL as an explicit tooltip; a
    /// reference, which has its preview, carries none.
    @Test func `only an external link carries a tooltip`() throws {
      let url = try #require(URL(string: "https://www.rfc-editor.org/"))
      let external = Fixtures.inlineRun([.link(url, [.text("the editor")])])
      #expect(
        external.attribute(.toolTip, at: 0, effectiveRange: nil) as? String
          == "https://www.rfc-editor.org/")

      let document = Fixtures.inlineRun([
        .crossReference(CrossReference(target: .document(.rfc(9110), section: "4.2")))
      ])
      let anchor = Fixtures.inlineRun([
        .crossReference(CrossReference(target: .anchor("section-3"), text: "Section 3"))
      ])
      for reference in [document, anchor] {
        reference.enumerateAttribute(.toolTip, in: NSRange(location: 0, length: reference.length)) {
          value, _, _ in
          #expect(value == nil)
        }
      }
    }
  #endif

  @Test func `document cross references link to the app scheme`() throws {
    let xref = CrossReference(
      target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of [RFC 9110]")
    let attributed = Fixtures.inlineRun([.crossReference(xref)])
    #expect(attributed.string == "Section 4.2 of [RFC 9110]")
    let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
    #expect(url.scheme == "rfc")
    #expect(url.absoluteString == "rfc://9110#section-4.2")
    #expect(attributed.attribute(.rfcReference, at: 0, effectiveRange: nil) is ReferenceBox)
  }

  @Test func `anchor cross references use the private anchor scheme`() throws {
    let xref = CrossReference(target: .anchor("section-3"), text: "Section 3")
    let attributed = Fixtures.inlineRun([.crossReference(xref)])
    let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
    #expect(url.absoluteString == "rfc-anchor:section-3")
  }

  /// A section of an entry outside the series opens the section's own page, as the
  /// RFC Editor's rendering does, or the entry where the source gives no page
  /// (#473). It is link text, not a chip: the chip is a document of ours.
  @Test func `a section of an entry outside the series links to its page or to the entry`()
    throws
  {
    let page = try #require(URL(string: "https://fetch.spec.whatwg.org/#cors-check"))
    let linked = CrossReference(
      target: .entrySection(entry: "FETCH", tag: "FETCH", section: "4.9", url: page))
    let attributed = Fixtures.inlineRun([.crossReference(linked)])
    #expect(attributed.string == "Section\u{00A0}4.9 of [FETCH]")
    #expect(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL == page)

    let unlinked = CrossReference(
      target: .entrySection(entry: "FETCH", tag: "FETCH", section: "4.9", url: nil))
    let fallback = Fixtures.inlineRun([.crossReference(unlinked)])
    #expect(
      (fallback.attribute(.link, at: 0, effectiveRange: nil) as? URL)?.absoluteString
        == "\(DocumentTextBuilder.referenceScheme):FETCH")
  }

  /// A reference with no text of its own is one the source left to us, so the
  /// reader composes it and draws it as a chip. The plain form it composes -- what
  /// `label` gives, brackets and all -- is what goes out through the serializer.
  @Test func `a cross reference without text is composed and chipped`() {
    let chipPrefix = "\u{FFFC}\u{2060}"

    let withSection = CrossReference(target: .document(.rfc(2119), section: "2"))
    #expect(withSection.label == "Section\u{00A0}2 of [RFC\u{00A0}2119]")
    #expect(
      Fixtures.inlineRun([.crossReference(withSection)]).string == chipPrefix
        + "RFC\u{00A0}2119\u{00A0}§\u{00A0}2"
    )

    let withoutSection = CrossReference(target: .document(.rfc(2119), section: nil))
    #expect(withoutSection.label == "[RFC\u{00A0}2119]")
    #expect(
      Fixtures.inlineRun([.crossReference(withoutSection)]).string == chipPrefix + "RFC\u{00A0}2119"
    )
  }

  /// `bare` is the source asking for the section number on its own, which is a
  /// wording decision -- so it is left alone rather than composed over.
  @Test func `a bare section format is not chipped`() {
    let xref = CrossReference(target: .document(.rfc(2119), section: "2"), sectionFormat: .bare)
    #expect(xref.displayLabel == "2")
    #expect(
      Fixtures.inlineRun([.crossReference(xref)]).attribute(.rfcChip, at: 0, effectiveRange: nil)
        == nil)
  }

  @Test func `line breaks become newlines`() {
    #expect(Fixtures.inlineRun([.text("a"), .lineBreak, .text("b")]).string == "a\nb")
  }
}
