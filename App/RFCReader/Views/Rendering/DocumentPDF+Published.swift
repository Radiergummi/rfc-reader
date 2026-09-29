import CoreGraphics
import CoreText
import Foundation
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

nonisolated extension DocumentPDF {
  /// The RFC as published, each of its pages on one sheet of paper, set in a
  /// fixed-width font with no running header or footer: the published page's own
  /// header, footer and `[Page n]` are what it has. How the text divides into pages,
  /// and the size that fits the longest page and widest line, is `PublishedPages`.
  ///
  /// Drawn as lines rather than laid out: a published page is already set, a line
  /// of text to a line of paper, and nothing on it may wrap.
  static func publishedPDF(_ source: String, layout: PrintLayout) -> Data {
    let published = PublishedPages(source)
    let preferred = PlatformFont.monospacedSystemFont(
      ofSize: PrintLayout.originalTextSize, weight: .regular)
    // Lines are spaced by the measurements the size was worked out from, so a
    // page that was found to fit does.
    let metrics = PublishedPages.Metrics(preferred)
    let size = published.fontSize(in: layout.contentRect.size, metrics: metrics)
    let lineHeight = metrics.lineHeight * size
    let attributes: [NSAttributedString.Key: Any] = [
      .font: PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular),
      NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    var ascent: CGFloat = 0
    CTLineGetTypographicBounds(
      CTLineCreateWithAttributedString(NSAttributedString(string: "0", attributes: attributes)),
      &ascent, nil, nil)

    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: layout.paperSize)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { return Data() }
    for page in published.pages {
      context.beginPDFPage(nil)
      // Black on the white paper, whatever the screen's appearance.
      context.setFillColor(CGColor(gray: 0, alpha: 1))
      for (index, text) in page.enumerated() where !text.isEmpty {
        let line = CTLineCreateWithAttributedString(
          NSAttributedString(string: text, attributes: attributes))
        // A PDF's origin is the page's bottom-left corner; the layout's is its top.
        let top = layout.contentRect.minY + CGFloat(index) * lineHeight
        context.textPosition = CGPoint(
          x: layout.contentRect.minX, y: layout.paperSize.height - top - ascent)
        CTLineDraw(line, context)
      }
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }
}
