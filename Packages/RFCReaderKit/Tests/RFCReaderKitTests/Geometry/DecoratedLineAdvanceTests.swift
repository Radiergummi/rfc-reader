import Foundation
import RFCKit
import SwiftUI
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Every fragment inside a decorated run advances by a whole number of device
/// pixels, at 2x and at 3x (#273).
///
/// UITextView draws each fragment on the pixel at or above its own top. When a
/// run's fragments are a fractional number of pixels apart (RFC 9000's Figure 13
/// advanced 29.25 pt a line), each is moved by a different fraction, and two
/// neighbors that tile in points are drawn up to a pixel apart: a light hairline
/// across a translucent card. When every advance in the run is whole, every
/// fragment is moved by the same fraction, and `snappingJoins` meets them.
///
/// Laid out for real: what a fragment's height comes to is TextKit's answer, not
/// this suite's.
@Suite("Decoration geometry: a decorated run advances in whole pixels")
struct DecoratedLineAdvanceTests {
  /// The heights of every decorated fragment that has a neighbor below it in the
  /// same run: the advances a join depends on.
  private func advances(_ document: RFCDocument, style: ReadingStyle) -> [CGFloat] {
    let text = DocumentTextBuilder.build(document, style: style).text
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    defer { withExtendedLifetime(storage) {} }
    let container = NSTextContainer(size: CGSize(width: style.measure, height: 0))
    container.lineFragmentPadding = 0
    layout.textContainer = container

    var advances: [CGFloat] = []
    layout.enumerateTextLayoutFragments(
      from: layout.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      let start = layout.offset(
        from: layout.documentRange.location, to: fragment.rangeInElement.location)
      let end = layout.offset(
        from: layout.documentRange.location, to: fragment.rangeInElement.endLocation)
      if let span = FragmentGeometry.decorationSpan(
        in: text, fragment: NSRange(location: start, length: end - start)), !span.isLast
      {
        advances.append(fragment.layoutFragmentFrame.height)
      }
      return true
    }
    return advances
  }

  private static let styles: [ReadingStyle] = [
    ReadingStyle(),
    ReadingStyle(bodySize: 15),
    ReadingStyle(bodySize: 19.5, textSize: .xxxLarge),
  ]

  private func expectWholePixels(_ advances: [CGFloat], _ what: String) {
    for scale in [2, 3] as [CGFloat] {
      for advance in advances {
        let pixels = advance * scale
        #expect(
          abs(pixels - pixels.rounded()) < 1e-6,
          "\(what): an advance of \(advance) pt is \(pixels) px at \(scale)x")
      }
    }
  }

  /// Committed RFCs with every kind of decorated run: artwork, source code with
  /// its label, tables, asides and block quotes, and chips inside them.
  @Test(arguments: ["rfc9271.xml", "rfc9601.xml", "rfc9290.xml", "rfc793.txt"])
  func `every decorated fragment of a committed RFC advances in whole pixels`(name: String) throws {
    let document = try Fixtures.document(named: name)
    for style in Self.styles {
      let advances = advances(document, style: style)
      try #require(!advances.isEmpty, "\(name) has no decorated run to measure")
      expectWholePixels(advances, "\(name) at \(style.bodySize) pt")
    }
  }

  /// A paragraph that wraps inside an aside, and a list inside a quote: fragments
  /// of more than one line, and spacing between blocks inside the run.
  @Test func `a wrapped paragraph and a list inside a card advance in whole pixels`() {
    let long = Paragraph(text: String(repeating: "A line that wraps in the column. ", count: 12))
    let document = Fixtures.document(
      .aside([.paragraph(long), .paragraph(Paragraph(text: "After it."))]),
      .blockQuote([
        .paragraph(long),
        .list(
          ListBlock(
            style: .bullet,
            items: [
              ListItem(blocks: [.paragraph(Paragraph(text: "One"))]),
              ListItem(blocks: [.paragraph(long)]),
            ])),
      ])
    )
    for style in Self.styles {
      expectWholePixels(advances(document, style: style), "at \(style.bodySize) pt")
    }
  }
}
