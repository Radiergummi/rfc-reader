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
@MainActor
struct TextLayoutOffsetTests {
  /// Several paragraphs, so that every conversion below crosses element boundaries.
  private let text = NSAttributedString(
    string:
      "First paragraph.\nA second, somewhat longer paragraph.\n\nFourth, after an empty one.\nLast")

  /// Lays `text` out. The storage is returned because the layout manager holds it
  /// weakly. Written through `textStorage`, never `attributedString`: see CLAUDE.md.
  private func layOut() -> (NSTextContentStorage, NSTextLayoutManager) {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(text)
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
}
