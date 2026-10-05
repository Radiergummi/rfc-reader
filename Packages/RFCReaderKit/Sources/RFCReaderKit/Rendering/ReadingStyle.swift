import Foundation
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Everything the builder needs to know about presentation — and nothing about color.
///
/// Colors are dynamic `PlatformColor` values stored straight into the attributed
/// string, so switching to dark mode or changing the accent redraws rather than
/// rebuilding. Only a change here costs a rebuild, and a rebuild loses the reader's
/// place until the anchor index puts it back.
public struct ReadingStyle: Sendable, Hashable {
  /// The body text's point size: the reader's own size, scaled for the system's
  /// text size. Everything else measured from the body — captions, code, spacing,
  /// indents — follows from this.
  ///
  /// Set once, from the reader's size and `textSize` together; only `scaled(by:)`
  /// moves it afterwards, so the two cannot disagree.
  public private(set) var bodySize: CGFloat
  /// The system's text size, which headings are scaled for on their own curve:
  /// at the accessibility sizes a title grows less than the body does.
  public private(set) var textSize: DynamicTypeSize
  /// Width available to text: the column `ReaderLayout` derives from the view's
  /// width, `ReaderLayout.idealMeasure` unless given.
  public var measure: CGFloat
  public var lineHeightMultiple: CGFloat
  /// Off by default: color marks a link, and a chip's tint marks a reference.
  /// An underline is the reader's to ask for, and then it goes under every link,
  /// chips included. In a build with no live links (`emitsLinks`), where nothing
  /// else colors a link, the builder colors it too (`RFCColors.link`): an
  /// exported PDF's links look like links (#376).
  public var underlinesLinks: Bool
  /// Whether a link is a live `.link` run. On by default; off for paper, where a
  /// text layout manager with no text view to say otherwise underlines and
  /// recolors every `.link` run (#375). The text of a link stays, and where it
  /// goes is kept as `.rfcLinkTarget`, which an exported PDF makes a link of again
  /// (#376).
  public var emitsLinks: Bool
  /// How a cross reference's label is set: as a chip on screen, and as text on
  /// paper, where a chip breaks the line it sits in and there is nothing to tap.
  public var references: ReferenceStyle

  /// Artwork is set tighter than prose, so a diagram's vertical strokes stay close
  /// to joined up. Source code keeps `lineHeightMultiple`: it is read as text.
  public var artworkLineHeightMultiple: CGFloat { 1.1 }

  /// - Parameter bodySize: the reader's own size, as it reads at the system's
  ///   default text size. The two multiply (#153): someone at an accessibility size
  ///   who nudges the reader up a step expects it to stay large, and larger.
  public init(
    bodySize: CGFloat = CGFloat(ReaderPreferences.defaultFontSize),
    measure: CGFloat = ReaderLayout.idealMeasure,
    lineHeightMultiple: CGFloat = 1.25,
    underlinesLinks: Bool = false, emitsLinks: Bool = true, references: ReferenceStyle = .chip,
    textSize: DynamicTypeSize = .large
  ) {
    self.bodySize = bodySize * TextSizeMetrics.body(textSize) / TextSizeMetrics.body(.large)
    self.textSize = textSize
    self.measure = measure
    self.lineHeightMultiple = lineHeightMultiple
    self.underlinesLinks = underlinesLinks
    self.emitsLinks = emitsLinks
    self.references = references
  }

  /// The same style at a different size — everything else about reading it is
  /// unchanged, so only the body size moves and the rest follows from it. The text
  /// size is already in `bodySize`, so it is carried over, not applied again.
  public func scaled(by scale: CGFloat) -> ReadingStyle {
    var scaled = self
    scaled.bodySize = bodySize * scale
    return scaled
  }

  public var bodyFont: PlatformFont { .systemFont(ofSize: bodySize, weight: .regular) }
  /// The weight of the platform's bold system font, which on iOS is semibold. It is
  /// asked for by weight because the bold system font itself can come back as
  /// Helvetica 12 pt, the first time it is made on several threads at once (#326).
  public var boldBodyFont: PlatformFont {
    #if canImport(UIKit)
      .systemFont(ofSize: bodySize, weight: .semibold)
    #else
      .systemFont(ofSize: bodySize, weight: .bold)
    #endif
  }
  public var captionFont: PlatformFont { .systemFont(ofSize: bodySize * 0.88, weight: .regular) }
  /// A source code block's language: a tag on its card, small and tracked, so it
  /// does not read as a heading over a line or two of code.
  public var codeLabelFont: PlatformFont { .systemFont(ofSize: bodySize * 0.7, weight: .regular) }
  /// A heading's backlink caption (#584): smaller than a caption, because it is the
  /// reader's note about the section and not part of the document.
  public var backlinksFont: PlatformFont { .systemFont(ofSize: bodySize * 0.76, weight: .regular) }

  /// Strong text in `surrounding`: bold, or heavy where the surrounding text is
  /// already bold, at its size and slant. A bold trait added to the face is not
  /// enough — on a semibold face, which is what a heading is, it changes nothing,
  /// and strong text would read the same as the heading around it.
  public func strongFont(matching surrounding: PlatformFont) -> PlatformFont {
    let isBold = surrounding.weight.rawValue >= PlatformFont.Weight.bold.rawValue - 0.05
    let weight: PlatformFont.Weight = isBold ? .heavy : .bold
    let slant = surrounding.fontDescriptor.symbolicTraits.intersection(RFCTraits.italic)
    return PlatformFont.systemFont(ofSize: surrounding.pointSize, weight: weight)
      .adding(traits: slant)
  }
  /// A reference set as text (`ReferenceStyle.plainText`) in `surrounding`: medium,
  /// or the surrounding weight where that is already heavier, as in a heading, at
  /// its size and slant.
  public func referenceFont(matching surrounding: PlatformFont) -> PlatformFont {
    let weight = max(surrounding.weight.rawValue, PlatformFont.Weight.medium.rawValue)
    let slant = surrounding.fontDescriptor.symbolicTraits.intersection(RFCTraits.italic)
    return PlatformFont.systemFont(
      ofSize: surrounding.pointSize, weight: PlatformFont.Weight(rawValue: weight)
    )
    .adding(traits: slant)
  }

  /// Inline code set in `surrounding` prose: monospaced, a little smaller, and at
  /// the surrounding weight and slant, so code in a heading stays heading-sized and
  /// code in emphasis stays italic (#154).
  public func codeFont(matching surrounding: PlatformFont) -> PlatformFont {
    let slant = surrounding.fontDescriptor.symbolicTraits.intersection(RFCTraits.italic)
    return PlatformFont.monospacedSystemFont(
      ofSize: surrounding.pointSize * 0.92, weight: surrounding.weight
    )
    .adding(traits: slant)
  }

  /// Verbatim blocks — artwork and source code. Bold Text is the system's to apply
  /// (#153): UIKit makes its proportional system font heavier by itself, and was
  /// seen on a device to leave this one regular, which suits a diagram — a heavier
  /// stroke would close up its box-drawing without making it easier to read.
  public func monospacedFont(scale: CGFloat) -> PlatformFont {
    .monospacedSystemFont(ofSize: bodySize * 0.82 * scale, weight: .regular)
  }

  /// `1.` is a title, `1.1.` a subtitle, deeper is a headline: the system's
  /// `.title2`, `.title3` and `.headline`, in proportion to the body, so they keep
  /// the platform's own relationship to it. On iOS that relationship changes with
  /// the text size; the Mac has no Dynamic Type, and its titles are 17 and 15 pt
  /// against a 13 pt body, which the reader has always rounded to 1.3 and 1.15.
  public func headingFont(depth: Int) -> PlatformFont {
    // A headline is the body's size on both platforms and at every text size, so
    // the deepest headings need no ratio of their own.
    #if os(macOS)
      let ratio: CGFloat =
        switch depth {
        case 1: 1.3
        case 2: 1.15
        default: 1
        }
    #else
      let ratio: CGFloat =
        switch depth {
        case 1: TextSizeMetrics.title2(textSize) / TextSizeMetrics.body(textSize)
        case 2: TextSizeMetrics.title3(textSize) / TextSizeMetrics.body(textSize)
        default: 1
        }
    #endif
    return .systemFont(ofSize: bodySize * ratio, weight: .semibold)
  }

  public var paragraphSpacing: CGFloat { bodySize * 0.7 }
  /// One level of indent: the body's size and a bit, until that would take more
  /// than a small share of the column. At the accessibility sizes the body grows to
  /// three times its default and the column does not, and a step that grew with it
  /// set a deeply nested paragraph on an iPhone in past the column's width (#153).
  /// Bounded here, five levels never take more than two fifths of the column.
  public var indentStep: CGFloat { min(bodySize * 1.4, measure * Self.indentShare) }

  /// The most of the column one indent step may take.
  static let indentShare: CGFloat = 0.08
}
