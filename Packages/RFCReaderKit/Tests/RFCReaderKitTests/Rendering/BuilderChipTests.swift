import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Builder: reference chips")
struct BuilderChipTests {
  private let style = ReadingStyle()

  private func run(_ xref: CrossReference) -> NSAttributedString {
    Fixtures.inlineRun([.crossReference(xref)], style: style)
  }

  @Test func `a canonical label loses its brackets`() {
    let xref = CrossReference(target: .document(.rfc(9110), section: nil))
    #expect(run(xref).string == "\u{FFFC}\u{2060}RFC\u{00A0}9110")
  }

  /// A reference to a section of another document is one reference, so it reads as
  /// one chip with the section as a suffix -- not as a sentence fragment with the
  /// document buried in the middle of it.
  @Test func `a section reference becomes one chip with a section suffix`() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    #expect(run(xref).string == "\u{FFFC}\u{2060}RFC\u{00A0}9110\u{00A0}§\u{00A0}4.2")
  }

  /// Nothing in the label may break across a line: not the series word from its
  /// number, and not the section mark from its number.
  @Test func `a section label is bound together`() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    #expect(xref.display.text == "RFC\u{00A0}9110\u{00A0}§\u{00A0}4.2")
    #expect(!xref.display.text.contains(" "), "an ordinary space would let the chip wrap mid-label")
  }

  /// The screen and a copied selection say the same thing.
  @Test func `what is copied is what is shown`() {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    // The rendered run is the display text plus the chip's own symbol and joiner.
    #expect(run(xref).string == Self.chipPrefix + xref.display.text)
    #expect([Inline.crossReference(xref)].plainText == xref.display.text)
  }

  /// An author's own words for a link are not a composed label, so they are left
  /// exactly as written — no chip, no restyling.
  @Test func `an authors own link text is left alone`() {
    let xref = CrossReference(
      target: .document(.rfc(9110), section: "4.2"), text: "the caching rules")
    #expect(xref.display.text == "the caching rules")
    #expect(run(xref).string == "the caching rules")
    #expect(run(xref).attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
  }

  /// Links are not underlined unless the reader asks for it: the tint marks a
  /// chip, the color marks any other link, and an underline under a chip ran
  /// under its symbol too.
  @Test func `no link is underlined by default`() {
    let chip = run(CrossReference(target: .document(.rfc(9110), section: "4.2")))
    let authored = run(
      CrossReference(target: .document(.rfc(9110), section: "4.2"), text: "the caching rules"))
    for attributed in [chip, authored] {
      attributed.enumerateAttribute(
        .underlineStyle, in: NSRange(location: 0, length: attributed.length)
      ) { value, _, _ in
        #expect(value == nil)
      }
    }
  }

  /// Asked for, every link character is underlined, a chip's included: one rule
  /// for every link, rather than an exception the reader has to learn.
  @Test func `underlining links underlines chips as well`() {
    let underlining = ReadingStyle(underlinesLinks: true)
    let chip = Fixtures.inlineRun(
      [.crossReference(CrossReference(target: .document(.rfc(9110), section: nil)))],
      style: underlining)
    let external = Fixtures.inlineRun(
      [.link(URL(string: "https://example.com")!, [.text("example")])], style: underlining)
    for attributed in [chip, external] {
      var range = NSRange(location: 0, length: 0)
      let underline = attributed.attribute(
        .underlineStyle, at: 0, longestEffectiveRange: &range,
        in: NSRange(location: 0, length: attributed.length))
      #expect(underline as? Int == NSUnderlineStyle.single.rawValue)
      #expect(range.length == attributed.length, "every character of the link is underlined")
    }
  }

  /// A citation of a bibliography entry that names no RFC is still an anchor after
  /// parsing, but the body leaves the bibliography out, so the builder links it
  /// with a scheme of its own: the one `LinkDestination` sends to the panel.
  @Test func `a citation of a bibliography entry links to the entry`() throws {
    let entry = "IEEE.802.3_2018"
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .paragraph(Paragraph([.crossReference(CrossReference(target: .anchor(entry)))])),
        .paragraph(Paragraph([.crossReference(CrossReference(target: .anchor("section-1")))])),
        .references(ReferenceList(title: "R", entries: [Reference(anchor: entry, title: "E")]))),
      style: style)
    var links: [URL] = []
    built.text.enumerateAttribute(
      .link, in: NSRange(location: 0, length: built.text.length)
    ) { value, _, _ in
      if let url = value as? URL { links.append(url) }
    }
    #expect(links.compactMap(DocumentTextBuilder.reference(from:)) == [entry])
    #expect(links.compactMap(DocumentTextBuilder.anchor(from:)) == ["section-1"])
  }

  private static let chipPrefix = "\u{FFFC}\u{2060}"

  @Test func `the whole section reference is one chip run`() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"))
    let attributed = run(xref)
    var range = NSRange(location: 0, length: 0)
    let chip = attributed.attribute(
      .rfcChip, at: 0, longestEffectiveRange: &range,
      in: NSRange(location: 0, length: attributed.length))
    #expect(chip != nil, "the chip starts at the symbol, not part way through")
    #expect(range.length == attributed.length, "every character belongs to the one chip")
  }

  @Test func `an author tag keeps its brackets and gets no chip`() {
    let xref = CrossReference(target: .document(.rfc(9000), section: nil), text: "[QUIC-TRANSPORT]")
    let attributed = run(xref)
    #expect(attributed.string == "[QUIC-TRANSPORT]")
    #expect(attributed.attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
  }

  /// `NSAttributedString` merges contiguous runs whose attribute value compares
  /// equal, so two directly adjacent chips (`[RFC9110][RFC9111]`) sharing
  /// `.rfcChip == true` would report one `effectiveRange` spanning both and draw
  /// as a single rounded rect. Each chip carries its own serial number instead.
  @Test func `adjacent chips do not merge into one effective range`() throws {
    let first = CrossReference(target: .document(.rfc(9110), section: nil))
    let second = CrossReference(target: .document(.rfc(9111), section: nil))
    let attributed = Fixtures.inlineRun(
      [.crossReference(first), .crossReference(second)], style: style)

    // `enumerateAttribute` is what `RFCTextLayoutFragment.chipRects(at:)` uses to
    // find each chip's own piece to draw — unlike `attribute(at:effectiveRange:)`,
    // it computes the *longest* equal-value range, merging across the two chips'
    // separately-appended runs when their `.rfcChip` values compare equal.
    var pieces: [NSRange] = []
    attributed.enumerateAttribute(.rfcChip, in: NSRange(location: 0, length: attributed.length)) {
      value, range, _ in
      guard value != nil else { return }
      pieces.append(range)
    }
    #expect(
      pieces.count == 2,
      "two adjacent chips must draw as two pieces, not one merged blob: \(pieces)")
  }

  @Test func `the whole label stays a link either way`() throws {
    let xref = CrossReference(target: .document(.rfc(9110), section: nil))
    let attributed = run(xref)
    let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
    #expect(url.absoluteString == "rfc://9110")
  }

  /// An informative citation's chip is marked for its lighter tint; a normative one,
  /// and one whose kind no list says, is drawn as before (#184).
  @Test func `only an informative citation's chip is marked informative`() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
    var marks: [DocumentID: Bool] = [:]
    let whole = NSRange(location: 0, length: built.text.length)
    built.text.enumerateAttribute(.rfcChip, in: whole) { value, range, _ in
      guard value != nil,
        let box = built.text.attribute(.rfcReference, at: range.location, effectiveRange: nil)
          as? ReferenceBox,
        case .document(let id, _, _) = box.reference.target
      else { return }
      marks[id] =
        built.text.attribute(.rfcInformative, at: range.location, effectiveRange: nil) != nil
    }
    #expect(marks[.rfc(5116)] == true)
    #expect(marks[.rfc(2119)] == false)
  }
}
