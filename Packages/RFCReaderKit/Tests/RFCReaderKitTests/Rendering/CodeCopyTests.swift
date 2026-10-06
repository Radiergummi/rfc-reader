import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A code block is copied three ways -- its copy button, Copy Figure and a selection
/// over the whole block -- and all three give the same text: unfolded, its tabs
/// expanded as the reader sets them, and without the indent its lines share.
@Suite("Copying code")
struct CodeCopyTests {
  /// Folded once per RFC 8792 and indented by the text format's three spaces, with
  /// a tab inside a line.
  private static let indented = Preformatted(
    kind: .sourceCode,
    text: "   " + Fixtures.foldingHeader + "\n\n"
      + "   {\"key\": \"a long \\\n      value\",\n    \"b\":\t1}",
    type: "json")

  /// What all three copy: the fold undone, the tab as far as the eighth column, and
  /// the shared indent gone.
  private static let copied = "{\"key\": \"a long value\",\n \"b\":        1}"

  private static func built(measure: CGFloat) -> NSAttributedString {
    DocumentTextBuilder.build(
      Fixtures.document(.preformatted(indented)), style: ReadingStyle(measure: measure)
    ).text
  }

  /// The whole extent of the block that holds `locator`, its language label
  /// included, as a selection.
  private static func wholeBlock(
    holding locator: String = "value", of text: NSAttributedString
  ) throws -> NSAttributedString {
    let block = try #require(
      text.extent(ofBox: .rfcVerbatim, at: try Fixtures.offset(of: locator, in: text)))
    return text.attributedSubstring(from: block)
  }

  @Test func `copy figure copies the block unfolded without its shared indent`() {
    #expect(FigureCopy.pasteboardText(for: Self.indented) == Self.copied)
  }

  /// A column wide enough shows the block unfolded, a narrow one as published;
  /// either way a selection over all of it pastes what Copy Figure does. The storage
  /// ends the block with a line break.
  @Test(arguments: [(CGFloat(4000), false), (CGFloat(120), true)])
  func `a selection over the whole block copies as copy figure does`(
    measure: CGFloat, shownFolded: Bool
  ) throws {
    let text = Self.built(measure: measure)
    #expect(text.string.contains("line wrapping per RFC 8792") == shownFolded)
    #expect(SelectionText.plainText(of: try Self.wholeBlock(of: text)) == Self.copied + "\n")
  }

  #if !canImport(UIKit)
    @Test(arguments: [CGFloat(4000), CGFloat(120)])
    func `the copy button copies as copy figure does`(measure: CGFloat) throws {
      let text = Self.built(measure: measure)
      let button = (text.string as NSString).range(of: "\u{FFFC}").location
      try #require(button != NSNotFound)
      #expect(text.copyButton(at: button) != nil)
      #expect(text.code(ofCopyButtonAt: button) == Self.copied)
    }

    /// Where the pointer is the arrow (#724): each button in the range, whole, and
    /// none outside it.
    @Test func `the copy buttons in a range are found whole`() throws {
      let text = DocumentTextBuilder.build(
        Fixtures.document(.preformatted(Self.indented), .preformatted(Self.outdentedFolds)),
        style: ReadingStyle(measure: 4000)
      ).text
      let all = NSRange(location: 0, length: text.length)
      let buttons = text.copyButtons(in: all)
      #expect(buttons.count == 2)
      for button in buttons {
        #expect(text.copyButton(at: button.location) == button)
      }
      let second = try #require(buttons.last)
      #expect(
        text.copyButtons(
          in: NSRange(location: second.location, length: text.length - second.location))
          == [second])
      #expect(text.copyButtons(in: NSRange(location: 0, length: buttons[0].location)).isEmpty)
    }
  #endif

  /// `rfcfold` sets the header, and under `'\\'` each continuation's backslash, at
  /// the first column whatever the code's indent, so the folded lines share less
  /// indent than the unfolded ones.
  private static let outdentedFolds = Preformatted(
    kind: .sourceCode,
    text: Fixtures.doubleBackslashFoldingHeader + "\n\n"
      + "  {\"key\": \"a long \\\n\\value\"}\n  []",
    type: "json")

  @Test(arguments: [(CGFloat(4000), false), (CGFloat(120), true)])
  func `a block folded further left than its code copies without the code's indent`(
    measure: CGFloat, shownFolded: Bool
  ) throws {
    let copied = "{\"key\": \"a long value\"}\n[]"
    let text = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Self.outdentedFolds)), style: ReadingStyle(measure: measure)
    ).text
    #expect(text.string.contains("line wrapping per RFC 8792") == shownFolded)
    #expect(FigureCopy.pasteboardText(for: Self.outdentedFolds) == copied)
    #expect(SelectionText.plainText(of: try Self.wholeBlock(of: text)) == copied + "\n")
  }

  // MARK: - A block shown unfolded is not unfolded again

  /// The box says whether the text shown is still folded, and how: what a
  /// selection over it is unfolded by.
  @Test(
    arguments: [(4000, nil), (120, .singleBackslash)] as [(CGFloat, FoldedLines.Strategy?)])
  func `the box records whether the block is shown folded`(
    measure: CGFloat, folding: FoldedLines.Strategy?
  ) throws {
    let text = Self.built(measure: measure)
    let box = try #require(
      FigureCopy.box(at: try Fixtures.offset(of: "value", in: text), in: text))
    #expect(box.shownFolding == folding)
  }

  /// Under RFC 8792's `'\\'` strategy a line of the author's may end in a
  /// backslash: here one followed by a line that a tab indents before its own
  /// backslash, which unfolding leaves alone. Shown, the tab is spaces, so the pair
  /// reads as a fold a second unfolding would join.
  private static let ownBackslashes = Preformatted(
    kind: .sourceCode,
    text: Fixtures.doubleBackslashFoldingHeader + "\n\n"
      + "path\\\n\t\\more\nlong\\\n   \\tail")

  @Test func `a block shown unfolded is copied as it is shown`() throws {
    let text = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Self.ownBackslashes)), style: ReadingStyle(measure: 4000)
    ).text
    let shown = "path\\\n        \\more\nlongtail"
    #expect(text.string.contains(shown), "the block is shown unfolded")
    #expect(
      SelectionText.plainText(of: try Self.wholeBlock(holding: "longtail", of: text))
        == shown + "\n")
    #expect(FigureCopy.pasteboardText(for: Self.ownBackslashes) == shown)
  }
}
