import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A heading that other sections refer to ends in a chip, which lists them (#183).
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

  private func chips(in text: NSAttributedString) -> [(range: NSRange, anchor: String)] {
    var found: [(range: NSRange, anchor: String)] = []
    text.enumerateAttribute(.rfcBacklinks, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      if let anchor = value as? String { found.append((range, anchor)) }
    }
    return found
  }

  @Test func `a heading referred to ends in one chip counting the sections`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let chips = chips(in: built.text)
    #expect(chips.map(\.anchor) == ["two"])
    let chip = try #require(chips.first)
    let heading = try Fixtures.offset(of: "2. Two", in: built.text)
    let lineEnd = (built.text.string as NSString).range(
      of: "\n", range: NSRange(location: heading, length: built.text.length - heading))
    #expect(NSMaxRange(chip.range) == lineEnd.location, "the chip ends the heading's line")
    // The space before it goes with it, so a copy leaves no trailing space.
    #expect(
      (built.text.string as NSString).substring(with: chip.range) == " \u{FFFC}\u{2060}3",
      "the abstract, Section 1 and Section 3")
    #expect(built.text.attribute(.rfcChip, at: chip.range.location, effectiveRange: nil) == nil)
    #expect(built.text.attribute(.rfcChip, at: chip.range.location + 1, effectiveRange: nil) != nil)
    let link = built.text.attribute(.link, at: NSMaxRange(chip.range) - 1, effectiveRange: nil)
    let url = try #require(link as? URL)
    #expect(DocumentTextBuilder.backlinks(from: url) == "two")
    #expect(DocumentTextBuilder.anchor(from: url) == nil, "a backlink chip is not a jump")
  }

  /// On paper there is nothing to press.
  @Test func `a build without live links has no backlink chips`() {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(emitsLinks: false))
    #expect(chips(in: built.text).isEmpty)
  }

  /// The chip is the reader's, not the document's words.
  @Test func `a copied heading leaves the chip out`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let heading = try Fixtures.offset(of: "2. Two", in: built.text)
    let lineEnd = (built.text.string as NSString).range(
      of: "\n", range: NSRange(location: heading, length: built.text.length - heading))
    let selection = built.text.attributedSubstring(
      from: NSRange(location: heading, length: NSMaxRange(lineEnd) - heading))
    #expect(SelectionText.plainText(of: selection) == "2. Two\n")
  }

  /// What the chip's popover lists: each citing section by its heading, in document
  /// order, and the abstract by name.
  @Test func `the chip lists the citing sections by heading`() {
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
