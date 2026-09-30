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

  /// Pressed on any of its characters, the chip answers with all of it but the
  /// space before it: what its list points at, which a heading wrapping at that
  /// space would otherwise stretch across two lines.
  @Test func `the chip is found whole from any of its characters`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let chip = try #require(chips(in: built.text).first)
    let drawn = NSRange(location: chip.range.location + 1, length: chip.range.length - 1)
    for offset in chip.range.location..<NSMaxRange(chip.range) {
      let found = try #require(built.text.backlinkChip(at: offset))
      #expect(found.anchor == "two" && found.range == drawn)
    }
    #expect(built.text.backlinkChip(at: chip.range.location - 1) == nil)
  }

  /// The headings rotor reads a heading's `.rfcAnchor` run as its label.
  @Test func `the chip is not part of the heading`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let chip = try #require(chips(in: built.text).first)
    var run = NSRange(location: 0, length: 0)
    let heading = built.text.attribute(
      .rfcAnchor, at: chip.range.location - 1, longestEffectiveRange: &run,
      in: NSRange(location: 0, length: built.text.length))
    #expect(heading as? String == "two")
    #expect(NSMaxRange(run) == chip.range.location)
    // Nor the line break after it, or the heading's run resumes there: a second
    // stop in the rotor, on an empty line.
    var headingRuns = 0
    built.text.enumerateAttribute(.rfcAnchor, in: NSRange(location: 0, length: built.text.length)) {
      value, _, _ in
      if value as? String == "two" { headingRuns += 1 }
    }
    #expect(headingRuns == 1)
    #if canImport(UIKit)
      #expect(
        built.text.attribute(
          .accessibilityTextHeadingLevel, at: chip.range.location, effectiveRange: nil) == nil)
    #endif
  }

  /// A rich paste gets the heading's own words too, not the chip's arrow and link.
  @Test func `a rich copy leaves the chip out`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let heading = try Fixtures.offset(of: "2. Two", in: built.text)
    let selection = built.text.attributedSubstring(
      from: NSRange(location: heading, length: "2. Two \u{FFFC}\u{2060}3\n".utf16.count))
    let copied = SelectionText.withoutBacklinkChips(of: selection)
    #expect(copied.string == "2. Two\n")
  }

  /// What VoiceOver says for the chip, in place of its arrow and its number.
  @Test func `the chip says to VoiceOver how many sections refer to the heading`() {
    #expect(AccessibleReading.backlinksLabel(count: 1) == "Referred to from 1 section")
    #expect(AccessibleReading.backlinksLabel(count: 3) == "Referred to from 3 sections")
  }

  /// Read a line at a time, the heading's line says the heading's words and then
  /// the chip's label, once; the chip's characters are not read out.
  @Test func `the chip is said as its label, and the links rotor lists it so`() throws {
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let run = try #require(chips(in: built.text).first)
    let chip = try #require(built.text.backlinkChip(at: run.range.location))
    let heading = try Fixtures.offset(of: "2. Two", in: built.text)
    let line = NSRange(location: heading, length: NSMaxRange(chip.range) + 1 - heading)
    let pieces = AccessibleReading.pieces(of: line, in: built.text)
    #expect(
      pieces == [
        .text(NSRange(location: heading, length: chip.range.location - heading)),
        .label("Referred to from 3 sections"),
        .text(NSRange(location: NSMaxRange(chip.range), length: 1)),
      ])
    let links = AccessibleReading.Rotors(built.text).links
    let stop = try #require(links.first { $0.range == chip.range })
    #expect(stop.label == "Referred to from 3 sections")
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
