import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A heading that other sections refer to has a caption under it, which lists them
/// (#183, #584).
@Suite("Builder: backlinks")
struct BuilderBacklinkTests {
  private func refer(to anchor: String) -> Block {
    .paragraph(
      Paragraph([.text("see "), .crossReference(CrossReference(target: .anchor(anchor)))]))
  }

  /// Section 2 is referred to from the abstract, from Section 1 and from Section 3,
  /// twice; nothing refers to Sections 1 and 3.
  private var document: RFCDocument {
    RFCDocument(
      header: DocumentHeader(title: "T", abstract: [refer(to: "two")]),
      sections: [
        Section(anchor: "one", number: "1", title: "One", blocks: [refer(to: "two")]),
        Section(
          anchor: "two", number: "2", title: "Two", blocks: [.paragraph(Paragraph(text: "x"))]),
        Section(
          anchor: "three", number: "3", title: "Three",
          blocks: [refer(to: "two"), refer(to: "two")]),
      ],
      source: .xml)
  }

  private func captions(in text: NSAttributedString) -> [(range: NSRange, anchor: String)] {
    var found: [(range: NSRange, anchor: String)] = []
    text.enumerateAttribute(.rfcBacklinks, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      if let anchor = value as? String { found.append((range, anchor)) }
    }
    return found
  }

  @Test func `a heading referred to has one caption under it counting the sections`() throws {
    let style = ReadingStyle()
    let built = DocumentTextBuilder.build(document, style: style)
    let captions = captions(in: built.text)
    #expect(captions.map(\.anchor) == ["two"])
    let caption = try #require(captions.first)
    let string = built.text.string as NSString
    // The abstract, Section 1 and Section 3: an arrow back, and the count in words.
    #expect(string.substring(with: caption.range) == "\u{FFFC}\u{00A0}Three Backlinks\n")
    let heading = try Fixtures.offset(of: "2. Two\n", in: built.text)
    #expect(caption.range.location == heading + "2. Two\n".utf16.count, "right under the heading")
    // Not a chip: nothing tints it, and its symbol is not a reference's.
    for offset in caption.range.location..<NSMaxRange(caption.range) {
      #expect(built.text.attribute(.rfcChip, at: offset, effectiveRange: nil) == nil)
      let font = built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
      #expect(font == style.backlinksFont)
      let color = built.text.attribute(.foregroundColor, at: offset, effectiveRange: nil)
      #expect(color as? PlatformColor == RFCColors.secondaryLabel)
    }
    let link = built.text.attribute(.link, at: caption.range.location, effectiveRange: nil)
    let url = try #require(link as? URL)
    #expect(DocumentTextBuilder.backlinks(from: url) == "two")
    #expect(DocumentTextBuilder.anchor(from: url) == nil, "a backlink caption is not a jump")
  }

  /// A paragraph of its own, not a line of the heading's: the running heading
  /// hands over as the heading's last line passes, and a jump lands on the
  /// heading, which a line inside its paragraph would move.
  @Test func `the caption is a paragraph of its own`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let caption = try #require(captions(in: built.text).first)
    let heading = try Fixtures.offset(of: "2. Two\n", in: built.text)
    let string = built.text.string as NSString
    let headingParagraph = string.paragraphRange(for: NSRange(location: heading, length: 0))
    #expect(NSMaxRange(headingParagraph) == caption.range.location)
    #expect(
      string.paragraphRange(for: NSRange(location: caption.range.location, length: 0))
        == caption.range)
    #expect(built.anchors.offset(of: "two") == heading)
  }

  /// "One Backlink" to "Three Backlinks" in words, and figures from there on.
  @Test func `the caption counts in words up to three`() {
    #expect(DocumentTextBuilder.backlinksCaption(count: 1) == "One Backlink")
    #expect(DocumentTextBuilder.backlinksCaption(count: 2) == "Two Backlinks")
    #expect(DocumentTextBuilder.backlinksCaption(count: 3) == "Three Backlinks")
    #expect(DocumentTextBuilder.backlinksCaption(count: 4) == "4 Backlinks")
    #expect(DocumentTextBuilder.backlinksCaption(count: 391_511) == "391511 Backlinks")
  }

  /// On paper there is nothing to press.
  @Test func `a build without live links has no backlink captions`() {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(emitsLinks: false))
    #expect(captions(in: built.text).isEmpty)
  }

  /// The caption is the reader's, not the document's words: a copy of the heading
  /// and what follows it has no line where the caption was.
  @Test func `a copied heading leaves the caption out`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let heading = try Fixtures.offset(of: "2. Two\n", in: built.text)
    let end = try Fixtures.offset(of: "3. Three", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: heading, length: end - heading))
    #expect(SelectionText.plainText(of: selection) == "2. Two\nx\n")
  }

  /// A rich paste gets the heading's own words too, not the caption's arrow and link.
  @Test func `a rich copy leaves the caption out`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let caption = try #require(captions(in: built.text).first)
    let heading = try Fixtures.offset(of: "2. Two\n", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: heading, length: NSMaxRange(caption.range) - heading))
    let copied = SelectionText.withoutReaderText(of: selection)
    #expect(copied.string == "2. Two\n")
  }

  /// Pressed on any of its characters, the caption answers with all of it but its
  /// line break: what its list points at.
  @Test func `the caption is found whole from any of its characters`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let caption = try #require(captions(in: built.text).first)
    let drawn = NSRange(location: caption.range.location, length: caption.range.length - 1)
    for offset in caption.range.location..<NSMaxRange(caption.range) {
      let found = try #require(built.text.backlinkCaption(at: offset))
      #expect(found.anchor == "two" && found.range == drawn)
    }
    #expect(built.text.backlinkCaption(at: caption.range.location - 1) == nil)
  }

  /// The headings rotor reads a heading's `.rfcAnchor` run as its label.
  @Test func `the caption is not part of the heading`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let caption = try #require(captions(in: built.text).first)
    var run = NSRange(location: 0, length: 0)
    let heading = built.text.attribute(
      .rfcAnchor, at: caption.range.location - 1, longestEffectiveRange: &run,
      in: NSRange(location: 0, length: built.text.length))
    #expect(heading as? String == "two")
    #expect(NSMaxRange(run) == caption.range.location)
    var headingRuns = 0
    built.text.enumerateAttribute(.rfcAnchor, in: NSRange(location: 0, length: built.text.length)) {
      value, _, _ in
      if value as? String == "two" { headingRuns += 1 }
    }
    #expect(headingRuns == 1)
    #if canImport(UIKit)
      #expect(
        built.text.attribute(
          .accessibilityTextHeadingLevel, at: caption.range.location, effectiveRange: nil) == nil)
    #endif
  }

  /// Read a line at a time, the caption's line says its words, once; its arrow is
  /// not read out.
  @Test func `the caption is said as its words, and the links rotor lists it so`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let run = try #require(captions(in: built.text).first)
    let caption = try #require(built.text.backlinkCaption(at: run.range.location))
    let pieces = AccessibleReading.pieces(of: run.range, in: built.text)
    #expect(
      pieces == [
        .label("Three Backlinks"),
        .text(NSRange(location: NSMaxRange(caption.range), length: 1)),
      ])
    let links = AccessibleReading.Rotors(built.text).links
    let stop = try #require(links.first { $0.range == caption.range })
    #expect(stop.label == "Three Backlinks")
  }

  /// The text view colors a link itself, over what the storage says; the caption
  /// keeps its own secondary color, and every other link the text view's.
  @Test func `the caption's link keeps the caption's color`() throws {
    let defaults: [NSAttributedString.Key: Any] = [
      .foregroundColor: RFCColors.accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
    let caption = try #require(
      DocumentTextBuilder.url("two", scheme: DocumentTextBuilder.backlinksScheme))
    let kept = DocumentTextBuilder.linkRenderingAttributes(for: caption, defaults: defaults)
    #expect(kept[.foregroundColor] == nil)
    #expect(kept[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    let jump = try #require(
      DocumentTextBuilder.url("two", scheme: DocumentTextBuilder.anchorScheme))
    let other = DocumentTextBuilder.linkRenderingAttributes(for: jump, defaults: defaults)
    #expect(other[.foregroundColor] as? PlatformColor == RFCColors.accent)
  }

  /// A link on a card is drawn in the link color for a card, which clears the
  /// minimum contrast on the card's fill where the text view's may not (#694); the
  /// caption keeps its own color there too.
  @Test func `a link on a card is drawn in the card's link color`() throws {
    let defaults: [NSAttributedString.Key: Any] = [
      .foregroundColor: RFCColors.accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
    let jump = try #require(
      DocumentTextBuilder.url("two", scheme: DocumentTextBuilder.anchorScheme))
    let onCard = DocumentTextBuilder.linkRenderingAttributes(
      for: jump, defaults: defaults, onCard: true)
    let color = try #require(onCard[.foregroundColor] as? PlatformColor)
    let dark = try #require(Self.resolvedInDark(color))
    #expect(abs(dark.red - AccentContrast.cardLink.dark.red) < 0.002)
    #expect(abs(dark.green - AccentContrast.cardLink.dark.green) < 0.002)
    #expect(abs(dark.blue - AccentContrast.cardLink.dark.blue) < 0.002)
    #expect(onCard[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    let caption = try #require(
      DocumentTextBuilder.url("two", scheme: DocumentTextBuilder.backlinksScheme))
    let kept = DocumentTextBuilder.linkRenderingAttributes(
      for: caption, defaults: defaults, onCard: true)
    #expect(kept[.foregroundColor] == nil)
  }

  private static func resolvedInDark(_ color: PlatformColor) -> SRGBColor? {
    var resolved: SRGBColor?
    #if canImport(UIKit)
      UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
        resolved = SRGBColor(resolving: color)
      }
    #else
      NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
        resolved = SRGBColor(resolving: color)
      }
    #endif
    return resolved
  }

  /// The caption is drawn with its own attributes on top of the text view's, which
  /// on macOS is the ordinary pointer in place of a link's pointing hand; every
  /// other link keeps the text view's. Stand-in values: the merge is what is
  /// pinned, and a test process cannot make a cursor.
  @Test func `the caption's link is drawn with its own attributes on top`() throws {
    let cursor = NSAttributedString.Key("cursor")
    let defaults: [NSAttributedString.Key: Any] = [cursor: "pointing hand"]
    let caption = try #require(
      DocumentTextBuilder.url("two", scheme: DocumentTextBuilder.backlinksScheme))
    let kept = DocumentTextBuilder.linkRenderingAttributes(
      for: caption, defaults: defaults, caption: [cursor: "arrow"])
    #expect(kept[cursor] as? String == "arrow")
    let jump = try #require(
      DocumentTextBuilder.url("two", scheme: DocumentTextBuilder.anchorScheme))
    let other = DocumentTextBuilder.linkRenderingAttributes(
      for: jump, defaults: defaults, caption: [cursor: "arrow"])
    #expect(other[cursor] as? String == "pointing hand")
  }

  /// What the caption's popover lists: each citing section by its heading, in
  /// document order, and the abstract by name.
  @Test func `the caption lists the citing sections by heading`() {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    #expect(
      built.backlinks(of: "two") == [
        BacklinkEntry(anchor: "abstract", heading: "Abstract", count: 1),
        BacklinkEntry(anchor: "one", heading: "1. One", count: 1),
        BacklinkEntry(anchor: "three", heading: "3. Three", count: 2),
      ])
    #expect(built.backlinks(of: "one").isEmpty)
  }
}
