import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What the builder measures of one paragraph, so its height can be estimated at
/// any column without laying it out: its width set on a single line, its line
/// height and the spacing around it.
public struct ParagraphMetrics: Sendable, Equatable {
  public let length: Int
  public let naturalWidth: CGFloat
  public let indent: CGFloat
  public let lineHeight: CGFloat
  public let spacing: CGFloat
  /// False for a verbatim line, which is never wrapped.
  public let wraps: Bool

  // No public initializer: only `measure` makes one, through the memberwise one,
  // whose six parameters SwiftLint would refuse on a public signature.

  /// Every paragraph of `text`, in order, split as `NSTextContentStorage` splits them.
  public static func measure(_ text: NSAttributedString) -> [ParagraphMetrics] {
    let string = text.string as NSString
    var metrics: [ParagraphMetrics] = []
    var start = 0
    while start < string.length {
      let range = string.paragraphRange(for: NSRange(location: start, length: 0))
      metrics.append(measure(range, of: text))
      start = NSMaxRange(range)
    }
    return metrics
  }

  private static func measure(_ range: NSRange, of text: NSAttributedString) -> ParagraphMetrics {
    let line = CTLineCreateWithAttributedString(
      text.attributedSubstring(from: range) as CFAttributedString)
    let font =
      text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
      ?? PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
    let style =
      text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
      ?? NSParagraphStyle.default
    let natural = font.ascender - font.descender + font.leading
    let multiple = style.lineHeightMultiple > 0 ? style.lineHeightMultiple : 1
    return ParagraphMetrics(
      length: range.length,
      naturalWidth: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
      indent: max(style.headIndent, style.firstLineHeadIndent),
      lineHeight: natural * multiple + style.lineSpacing,
      spacing: style.paragraphSpacing + style.paragraphSpacingBefore,
      wraps: style.lineBreakMode != .byClipping)
  }

  public func estimatedHeight(atColumn column: CGFloat) -> CGFloat {
    guard wraps else { return lineHeight + spacing }
    let lines = max(1, (naturalWidth / max(1, column - indent)).rounded(.up))
    return lines * lineHeight + spacing
  }
}

/// The document's height, paragraph by paragraph: estimated from `ParagraphMetrics`
/// at the column, and exact for every paragraph TextKit has laid out and reported
/// through `measure(_:)`. What the scroller reads, since TextKit's own estimate
/// swings by up to the whole document's height as it lays out (see the spec).
public struct HeightModel: Sendable {
  public private(set) var column: CGFloat
  private let paragraphs: [ParagraphMetrics]
  private let starts: [Int]
  private var heights: [CGFloat]
  /// Each paragraph's top, and the total last: one more than `paragraphs`.
  private var tops: [CGFloat] = [0]

  public init(paragraphs: [ParagraphMetrics], column: CGFloat) {
    self.paragraphs = paragraphs
    self.column = column
    var starts: [Int] = []
    starts.reserveCapacity(paragraphs.count)
    var offset = 0
    for paragraph in paragraphs {
      starts.append(offset)
      offset += paragraph.length
    }
    self.starts = starts
    heights = paragraphs.map { $0.estimatedHeight(atColumn: column) }
    recomputeTops()
  }

  public var count: Int { paragraphs.count }
  public var total: CGFloat { tops.last ?? 0 }

  /// Estimates every paragraph again at `column`; what was measured at the old
  /// column is forgotten, since a re-wrap changed it.
  public mutating func setColumn(_ column: CGFloat) {
    guard column != self.column else { return }
    self.column = column
    heights = paragraphs.map { $0.estimatedHeight(atColumn: column) }
    recomputeTops()
  }

  /// Replaces the estimates of the paragraphs TextKit has laid out.
  public mutating func measure(_ measured: [(paragraph: Int, height: CGFloat)]) {
    guard !measured.isEmpty else { return }
    for entry in measured where heights.indices.contains(entry.paragraph) {
      heights[entry.paragraph] = entry.height
    }
    recomputeTops()
  }

  public func top(ofParagraph index: Int) -> CGFloat {
    tops[min(max(index, 0), tops.count - 1)]
  }

  public func characterOffset(ofParagraph index: Int) -> Int {
    starts.isEmpty ? 0 : starts[min(max(index, 0), starts.count - 1)]
  }

  public func paragraph(containing characterOffset: Int) -> Int {
    max(0, starts.partitioningIndex { $0 > characterOffset } - 1)
  }

  /// The paragraph at `height`, clamped to the first and the last.
  public func paragraph(atHeight height: CGFloat) -> Int {
    guard !paragraphs.isEmpty else { return 0 }
    return min(max(0, tops.partitioningIndex { $0 > height } - 1), paragraphs.count - 1)
  }

  /// The scroller's knob when the viewport's top is `within` points into
  /// `paragraph`: its position, 0 at the top and 1 at the last screen, and its
  /// size, against the height the scroller shows (`ScrollerHeight.shown`). Nil
  /// with nothing to scroll through; a document shorter than the viewport fills
  /// the track.
  public func knob(
    paragraph: Int, within: CGFloat, visible: CGFloat, shown: CGFloat
  ) -> (position: Double, proportion: CGFloat)? {
    guard count > 0, shown > 0 else { return nil }
    let range = shown - visible
    guard range > 0 else { return (0, 1) }
    let height = top(ofParagraph: paragraph) + max(0, within)
    return (Double(min(1, max(0, height / range))), visible / shown)
  }

  /// Where the viewport's top goes for the knob dragged to `fraction`: the
  /// paragraph at that height and how far into it. The inverse of `knob`, so the
  /// knob stays under the pointer once the jump lands.
  public func target(
    atFraction fraction: Double, visible: CGFloat, shown: CGFloat
  ) -> (paragraph: Int, within: CGFloat) {
    let height = CGFloat(min(1, max(0, fraction))) * max(0, shown - visible)
    let paragraph = paragraph(atHeight: height)
    return (paragraph, max(0, height - top(ofParagraph: paragraph)))
  }

  private mutating func recomputeTops() {
    var tops: [CGFloat] = [0]
    tops.reserveCapacity(heights.count + 1)
    var running: CGFloat = 0
    for height in heights {
      running += height
      tops.append(running)
    }
    self.tops = tops
  }
}
