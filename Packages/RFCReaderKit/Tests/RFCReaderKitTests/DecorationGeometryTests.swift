import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Artwork does not wrap, so TextKit 2 lays out one fragment per line, each as wide
/// as its own text. A decoration measured from the fragment therefore drew a
/// different-width rounded rect per line -- a staircase down the page instead of one
/// card. These pin the band to the column.
@Suite("Decoration geometry: the card spans the column")
struct DecorationGeometryTests {
  private let column: CGFloat = 600
  private let padding: CGFloat = 10

  /// Two lines of one artwork block: very different widths, laid out at the same
  /// left edge, one above the other.
  private let narrowLine = CGRect(x: 0, y: 100, width: 40, height: 20)
  private let wideLine = CGRect(x: 0, y: 120, width: 380, height: 20)

  private func placement(_ fragment: CGRect, indent: CGFloat = 0) -> FragmentGeometry.Placement {
    FragmentGeometry.Placement(
      origin: CGPoint(x: fragment.minX, y: fragment.minY),
      frame: fragment,
      containerWidth: column,
      indent: indent
    )
  }

  private func rect(
    _ fragment: CGRect, indent: CGFloat = 0, capTop: Bool = false, capBottom: Bool = false
  ) -> CGRect {
    placement(fragment, indent: indent).decorationRect(
      padding: padding, capTop: capTop, capBottom: capBottom)
  }

  @Test func linesOfDifferentWidthGetTheSameBand() {
    let narrow = rect(narrowLine)
    let wide = rect(wideLine)
    #expect(narrow.minX == wide.minX, "a staircase starts when the left edges disagree")
    #expect(narrow.width == wide.width, "a staircase starts when the widths disagree")
  }

  @Test func theBandSpansTheColumnNotTheText() {
    // The widest line here is 380pt in a 600pt column; the card still covers the
    // column, or short lines leave a notch in the block.
    #expect(rect(wideLine).width == column + padding * 2)
  }

  @Test func anIndentedBlockIsInsetAndNarrowedByTheSameAmount() {
    let plain = rect(wideLine)
    let indented = rect(wideLine, indent: 40)
    #expect(indented.minX == plain.minX + 40)
    #expect(indented.width == plain.width - 40)
  }

  /// Middle fragments must sit flush, or a translucent fill darkens every seam.
  @Test func onlyTheRunsOwnEndsCarryTheOuterPadding() {
    let middle = rect(wideLine)
    let first = rect(wideLine, capTop: true)
    let last = rect(wideLine, capBottom: true)
    #expect(middle.height == wideLine.height)
    #expect(first.height == wideLine.height + padding / 2)
    #expect(first.minY == wideLine.minY - padding / 2)
    #expect(last.height == wideLine.height + padding / 2)
    #expect(last.minY == wideLine.minY)
  }

  /// Consecutive fragments of one run must tile with no gap and no overlap.
  @Test func consecutiveFragmentsTileExactly() {
    let upper = rect(CGRect(x: 0, y: 100, width: 40, height: 20), capTop: true)
    let lower = rect(CGRect(x: 0, y: 120, width: 380, height: 20), capBottom: true)
    #expect(upper.maxY == lower.minY)
  }

  /// The block quote's rule hangs outside the band, beside the quoted text's own
  /// edge -- not the fragment's, or a short line would pull the rule inwards and it
  /// would zigzag down the quote. Consecutive fragments' rules meet end to end.
  @Test func theRuleHangsLeftOfTheTextAtAConstantOffset() {
    let narrow = placement(narrowLine, indent: 40).ruleRect(padding: 8, width: 3)
    let wide = placement(wideLine, indent: 40).ruleRect(padding: 8, width: 3)
    #expect(narrow.minX == wide.minX, "a zigzag starts when the left edges disagree")
    #expect(narrow.maxX == placement(narrowLine, indent: 40).columnLeft - 8)
    #expect(narrow.width == 3)
    #expect(narrow.maxY == wide.minY, "consecutive fragments' rules must meet with no gap")
  }

  @Test func theColumnLeftIgnoresHowWideTheFragmentIs() {
    let narrow = FragmentGeometry.Placement(
      origin: CGPoint(x: 24, y: 0), frame: narrowLine, containerWidth: column, indent: 0
    ).columnLeft
    let wide = FragmentGeometry.Placement(
      origin: CGPoint(x: 24, y: 0), frame: wideLine, containerWidth: column, indent: 0
    ).columnLeft
    #expect(narrow == wide)
  }

  /// A block that mixes indents -- an authors' block alternating affiliation and
  /// address lines -- must still draw one band, at the shallowest indent.
  @Test func theBandIndentIsTheShallowestInTheRun() {
    func para(_ indent: CGFloat) -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.headIndent = indent
      return style
    }
    let text = NSMutableAttributedString()
    text.append(
      NSAttributedString(string: "China Mobile\n", attributes: [.paragraphStyle: para(20)]))
    text.append(NSAttributedString(string: "Beijing\n", attributes: [.paragraphStyle: para(60)]))
    text.append(NSAttributedString(string: "China\n", attributes: [.paragraphStyle: para(60)]))

    let whole = NSRange(location: 0, length: text.length)
    #expect(FragmentGeometry.indent(in: text, over: whole) == 20)

    // Every fragment of the run therefore agrees on where the band starts.
    let deep = FragmentGeometry.indent(in: text, over: NSRange(location: 20, length: 1))
    #expect(deep == 60, "the deeper paragraph really is indented further")
    #expect(FragmentGeometry.indent(in: text, over: whole) < deep)
  }

  @Test func aRangeOutsideTheTextDoesNotTrap() {
    let text = NSAttributedString(string: "short")
    #expect(FragmentGeometry.indent(in: text, over: NSRange(location: 0, length: 9_999)) == 0)
    #expect(FragmentGeometry.indent(in: text, over: NSRange(location: 400, length: 10)) == 0)
  }

  @Test func theIndentComesFromTheParagraphStyle() {
    let style = NSMutableParagraphStyle()
    style.headIndent = 32
    let text = NSAttributedString(string: "quoted", attributes: [.paragraphStyle: style])
    #expect(FragmentGeometry.indent(in: text, over: NSRange(location: 0, length: 1)) == 32)
    #expect(
      FragmentGeometry.indent(
        in: NSAttributedString(string: "plain"), over: NSRange(location: 0, length: 1)) == 0)
    #expect(
      FragmentGeometry.indent(in: text, over: NSRange(location: 99, length: 1)) == 0,
      "an out-of-range offset must not trap")
  }
}
