import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The conversions between `NSTextLocation` and document-relative character offsets
/// every TextKit 2 site in the reader goes through. A layout fragment's locations are
/// relative to its own paragraph element in TextKit's model; these must hand back
/// offsets into the whole document, on every paragraph, not only the first — the
/// first being the one place a wrong base still looks right.
@Suite("Text layout offsets")
struct TextLayoutOffsetTests {
  /// Several paragraphs, so that every conversion below crosses element boundaries.
  private let text = NSAttributedString(
    string:
      "First paragraph.\nA second, somewhat longer paragraph.\n\nFourth, after an empty one.\nLast")

  /// Lays `text` out. The storage is returned because the layout manager holds it
  /// weakly. Written through `install`, never `attributedString`: see CLAUDE.md.
  private func layOut() -> (NSTextContentStorage, NSTextLayoutManager) {
    let storage = NSTextContentStorage()
    storage.install(text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: 100_000))
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    return (storage, layout)
  }

  @Test func `the attributed text is the content storage's string`() {
    let (storage, layout) = layOut()
    defer { withExtendedLifetime(storage) {} }

    #expect(layout.attributedText?.string == text.string)
  }

  @Test func `every offset survives a round trip through a location`() throws {
    let (storage, layout) = layOut()
    defer { withExtendedLifetime(storage) {} }

    for offset in 0...text.length {
      let location = try #require(layout.location(atOffset: offset))
      #expect(layout.offset(of: location) == offset)
    }
  }

  @Test func `every range survives a round trip through a text range`() throws {
    let (storage, layout) = layOut()
    defer { withExtendedLifetime(storage) {} }

    for start in 0...text.length {
      for end in start...text.length {
        let range = NSRange(location: start, length: end - start)
        let textRange = try #require(layout.textRange(for: range))
        #expect(layout.range(of: textRange) == range)
      }
    }
  }

  /// A text range that outlived the text it was made for, here by the document
  /// getting shorter, still converts to offsets, which are past the document's end.
  /// It has no range in the document: a fragment's lines built over it index text
  /// that is not there. The same guard turns away the `NSNotFound` that
  /// `offset(from:to:)` may answer, on which a fragment's arithmetic overflows.
  @Test func `a text range past the document's end has no range`() throws {
    let (storage, layout) = layOut()
    defer { withExtendedLifetime(storage) {} }

    let stale = try #require(layout.textRange(for: NSRange(location: 80, length: 4)))
    storage.install(NSAttributedString(string: "Short.\nTwo"))
    #expect(layout.range(of: stale) == nil)
  }

  /// What the reader's layout fragment asks for its own span: each fragment's
  /// range is its paragraph's range in the document, including on the paragraphs
  /// after the first.
  @Test func `a layout fragment's range is its paragraph's range in the document`() {
    let (storage, layout) = layOut()
    defer { withExtendedLifetime(storage) {} }

    let string = text.string as NSString
    var ranges: [NSRange] = []
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      if let range = layout.range(of: fragment.rangeInElement) {
        ranges.append(range)
      }
      return true
    }

    var paragraphs: [NSRange] = []
    var location = 0
    while location < string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      paragraphs.append(paragraph)
      location = NSMaxRange(paragraph)
    }

    #expect(ranges == paragraphs)
  }

  /// Whether a link is on a card, which decides its color (#694), asked of a
  /// layout manager by location, as TextKit asks: on either side of every
  /// decorated block's edges, across a whole document, the same answer as the
  /// built text's.
  @Test func `a location is on a card where its character is`() throws {
    let text = try LayoutFixture.built().text
    let fixture = LayoutFixture(text: text, width: 712)
    var edges: [Int] = []
    text.enumerateAttribute(.rfcDecoration, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard value != nil else { return }
      edges += [range.location - 1, range.location, NSMaxRange(range) - 1, NSMaxRange(range)]
    }
    #expect(edges.contains { FragmentGeometry.drawsCard(in: text, at: $0) })
    for offset in edges where offset >= 0 && offset < text.length {
      let location = try #require(fixture.layout.location(atOffset: offset))
      #expect(
        fixture.layout.drawsCard(at: location)
          == FragmentGeometry.drawsCard(in: text, at: offset), "offset \(offset)")
    }
  }
}
