import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A decorated block's facts are worked out once, as the build ends, and carried on
/// every character of the block (#766): a fragment reads them with one lookup
/// instead of walking the block three times.
///
/// What a fragment reads has to be what the walk would have found at the
/// fragment's own place, on every paragraph of every block. A pass that boxed the
/// wrong range, or an attribute written after it, shows up here as one paragraph
/// whose box disagrees with the walk.
@Suite("Decoration facts")
struct DecorationFactsTests {
  private let style = ReadingStyle()

  /// Tables, asides, artwork, code and grammars, in both source formats.
  @Test(arguments: ["rfc8999.xml", "rfc9290.xml", "rfc793.txt", "rfc5234.txt"])
  func `every decorated paragraph carries the facts the walk finds there`(fixture: String) throws {
    let built = DocumentTextBuilder.build(try Fixtures.document(named: fixture), style: style)
    let text = built.text
    let string = text.string as NSString

    var checked = 0
    var location = 0
    while location < text.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      defer { location = NSMaxRange(paragraph) }
      guard text.decoration(at: paragraph.location) != nil else { continue }
      let carried = try #require(
        text.attribute(.rfcDecorationFacts, at: paragraph.location, effectiveRange: nil)
          as? DecorationFacts,
        "\(fixture): no facts on the decorated paragraph at \(paragraph.location)")
      let walked = try #require(FragmentGeometry.decorationFacts(in: text, at: paragraph.location))
      #expect(carried.range == walked.range, "\(fixture) at \(paragraph.location)")
      #expect(carried.indent == walked.indent, "\(fixture) at \(paragraph.location)")
      #expect(carried.cardInset == walked.cardInset, "\(fixture) at \(paragraph.location)")
      #expect(carried.contentWidth == walked.contentWidth, "\(fixture) at \(paragraph.location)")
      checked += 1
    }
    #expect(checked > 0, "\(fixture) has no decorated paragraph to check")
  }

  @Test func `two adjacent verbatim blocks carry a box each`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .preformatted(Preformatted(kind: .artwork, text: "AAAA\nAAAA")),
        .preformatted(Preformatted(kind: .artwork, text: "BBBB\nBBBB"))),
      style: style)
    let first = try Fixtures.offset(of: "AAAA", in: built.text)
    let second = try Fixtures.offset(of: "BBBB", in: built.text)
    let firstFacts = try #require(
      built.text.attribute(.rfcDecorationFacts, at: first, effectiveRange: nil) as? DecorationFacts)
    let secondFacts = try #require(
      built.text.attribute(.rfcDecorationFacts, at: second, effectiveRange: nil) as? DecorationFacts
    )
    #expect(firstFacts.range.location == first)
    #expect(NSMaxRange(firstFacts.range) <= second)
    #expect(secondFacts.range.location == second)
    #expect(NSMaxRange(secondFacts.range) > second + "BBBB\nBBBB".utf16.count - 1)
  }

  /// The facts' range is an offset into the build's text, so a copy cut out of it
  /// carries ranges that point elsewhere: there the block is walked, as text
  /// without facts is.
  @Test func `a substring's spans are those of its text walked`() throws {
    let built = DocumentTextBuilder.build(try Fixtures.document(named: "rfc8999.xml"), style: style)
    let text = built.text
    let string = text.string as NSString
    var start = 0
    while start < text.length, text.decoration(at: start) == nil { start += 1 }
    let paragraphStart = string.paragraphRange(for: NSRange(location: max(start - 1, 0), length: 0))
    let cut = text.attributedSubstring(
      from: NSRange(
        location: paragraphStart.location, length: text.length - paragraphStart.location))
    let walked = NSMutableAttributedString(attributedString: cut)
    walked.removeAttribute(.rfcDecorationFacts, range: NSRange(location: 0, length: walked.length))

    var checked = 0
    var location = 0
    let cutString = cut.string as NSString
    while location < cut.length {
      let paragraph = cutString.paragraphRange(for: NSRange(location: location, length: 0))
      defer { location = NSMaxRange(paragraph) }
      guard cut.decoration(at: paragraph.location) != nil else { continue }
      #expect(
        FragmentGeometry.decorationSpan(in: cut, fragment: paragraph)
          == FragmentGeometry.decorationSpan(in: walked, fragment: paragraph),
        "at \(paragraph.location)")
      checked += 1
    }
    #expect(checked > 0)
  }

  /// A copy cut inside a block, with text after it, carries a range that still
  /// contains most of its fragments' offsets and still fits the copy: only the box's
  /// own extent in the copy says the range is not this text's.
  @Test func `a copy cut inside a block walks it`() throws {
    let lines = (0..<40).map { "line \($0)" }.joined(separator: "\n")
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .preformatted(Preformatted(kind: .artwork, text: lines)),
        .paragraph(Paragraph(text: String(repeating: "word ", count: 200)))),
      style: style)
    let start = try Fixtures.offset(of: "line 2\n", in: built.text)
    let cut = built.text.attributedSubstring(
      from: NSRange(location: start, length: built.text.length - start))
    let walked = NSMutableAttributedString(attributedString: cut)
    walked.removeAttribute(.rfcDecorationFacts, range: NSRange(location: 0, length: walked.length))

    var checked = 0
    var location = 0
    let cutString = cut.string as NSString
    while location < cut.length {
      let paragraph = cutString.paragraphRange(for: NSRange(location: location, length: 0))
      defer { location = NSMaxRange(paragraph) }
      guard cut.decoration(at: paragraph.location) != nil else { continue }
      #expect(
        FragmentGeometry.decorationSpan(in: cut, fragment: paragraph)
          == FragmentGeometry.decorationSpan(in: walked, fragment: paragraph),
        "at \(paragraph.location)")
      checked += 1
    }
    #expect(checked == 38)
  }
}
