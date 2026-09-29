import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The RFC as published, a page at a time: what prints when the reader is showing
/// Original Text (#375).
///
/// A published RFC is paginated already. Its pages end at form feeds, and each one
/// carries its own running header, footer and `[Page n]`, so each prints as one
/// sheet of paper with nothing of the app's around it, and is never broken anywhere
/// else. A page that does not fit the paper at the preferred size makes the whole
/// document smaller rather than being split, so that every sheet is still one page
/// as published, and every page is set at the same size.
public struct PublishedPages: Equatable, Sendable {
  /// Each page's lines, top to bottom, with tabs expanded and trailing spaces and
  /// the blank lines at the page's foot removed. Pages with no text are left out.
  public let pages: [[String]]

  /// How often a tab stops: every eighth column, as the terminals the text was
  /// written for set it.
  static let tabWidth = 8

  public init(_ source: String) {
    pages = source.split(separator: "\u{0C}", omittingEmptySubsequences: false)
      .enumerated()
      .map { index, page in Self.lines(ofPage: page, followsFormFeed: index > 0) }
      .filter { !$0.isEmpty }
  }

  /// One page's lines. The line break that ends a form feed's line is not a line
  /// of the page after it; the blank lines at a page's top are part of how it is
  /// set, and the ones at its foot are not.
  private static func lines(ofPage page: Substring, followsFormFeed: Bool) -> [String] {
    var text = page
    if followsFormFeed, let first = text.first, first.isNewline {
      text = text.dropFirst()
    }
    var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map(expandingTabs)
      .map(droppingTrailingSpaces)
    while let last = lines.last, last.isEmpty {
      lines.removeLast()
    }
    return lines
  }

  private static func expandingTabs(_ line: Substring) -> String {
    guard line.contains("\t") else { return String(line) }
    var expanded = ""
    for character in line {
      if character == "\t" {
        let spaces = tabWidth - expanded.count % tabWidth
        expanded += String(repeating: " ", count: spaces)
      } else {
        expanded.append(character)
      }
    }
    return expanded
  }

  private static func droppingTrailingSpaces(_ line: String) -> String {
    var trimmed = Substring(line)
    while let last = trimmed.last, last.isWhitespace {
      trimmed = trimmed.dropLast()
    }
    return String(trimmed)
  }

  /// A fixed-width font's measurements, per point of its size, so a size to fit
  /// can be worked out without setting the font at every size to try.
  public struct Metrics: Equatable, Sendable {
    /// From one line's top to the next one's.
    public let lineHeight: CGFloat
    /// One column's width.
    public let advance: CGFloat

    public init(lineHeight: CGFloat, advance: CGFloat) {
      self.lineHeight = lineHeight
      self.advance = advance
    }

    /// `font`'s measurements, taken from one column of it set as a line.
    public init(_ font: PlatformFont) {
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "0", attributes: [.font: font]))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
      self.init(
        lineHeight: (ascent + descent + leading) / font.pointSize,
        advance: width / font.pointSize)
    }
  }

  /// The size every page is set at, so that the longest page's lines and the
  /// widest line fit `size`: `PrintLayout.originalTextSize`, unless something is
  /// too long or too wide for it, and then as much smaller as that needs.
  public func fontSize(in size: CGSize, metrics: Metrics) -> CGFloat {
    let preferred = PrintLayout.originalTextSize
    let lineCount = pages.map(\.count).max() ?? 0
    let columnCount = pages.flatMap { $0 }.map(\.count).max() ?? 0
    var fitting = preferred
    if lineCount > 0 {
      fitting = min(fitting, size.height / (CGFloat(lineCount) * metrics.lineHeight))
    }
    if columnCount > 0 {
      fitting = min(fitting, size.width / (CGFloat(columnCount) * metrics.advance))
    }
    return fitting
  }
}
