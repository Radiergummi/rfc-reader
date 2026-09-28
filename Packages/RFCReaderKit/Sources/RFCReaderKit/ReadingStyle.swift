import Foundation
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Everything the builder needs to know about presentation — and nothing about colour.
///
/// Colours are dynamic `PlatformColor` values stored straight into the attributed
/// string, so switching to dark mode or changing the accent redraws rather than
/// rebuilding. Only a change here costs a rebuild, and a rebuild loses the reader's
/// place until the anchor index puts it back.
public struct ReadingStyle: Sendable, Equatable {
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
  /// Width available to text: the reader's 760 pt frame less its horizontal padding.
  public var measure: CGFloat
  public var lineHeightMultiple: CGFloat
  /// Off by default: colour marks a link, and a chip's tint marks a reference.
  /// An underline is the reader's to ask for, and then it goes under every link,
  /// chips included.
  public var underlinesLinks: Bool

  /// Artwork is set tighter than prose, so a diagram's vertical strokes stay close
  /// to joined up. Source code keeps `lineHeightMultiple`: it is read as text.
  public var artworkLineHeightMultiple: CGFloat { 1.1 }

  /// - Parameter bodySize: the reader's own size, as it reads at the system's
  ///   default text size. The two multiply (#153): someone at an accessibility size
  ///   who nudges the reader up a step expects it to stay large, and larger.
  public init(
    bodySize: CGFloat = 17, measure: CGFloat = 712, lineHeightMultiple: CGFloat = 1.25,
    underlinesLinks: Bool = false, textSize: DynamicTypeSize = .large
  ) {
    self.bodySize = bodySize * TextSizeMetrics.body(textSize) / TextSizeMetrics.body(.large)
    self.textSize = textSize
    self.measure = measure
    self.lineHeightMultiple = lineHeightMultiple
    self.underlinesLinks = underlinesLinks
  }

  /// The same style at a different size — everything else about reading it is
  /// unchanged, so only the body size moves and the rest follows from it. The text
  /// size is already in `bodySize`, so it is carried over, not applied again.
  public func scaled(by scale: CGFloat) -> ReadingStyle {
    var scaled = self
    scaled.bodySize = bodySize * scale
    return scaled
  }

  public var bodyFont: PlatformFont { .systemFont(ofSize: bodySize) }
  public var boldBodyFont: PlatformFont { .boldSystemFont(ofSize: bodySize) }
  public var captionFont: PlatformFont { .systemFont(ofSize: bodySize * 0.88) }

  /// Strong text in `surrounding`: a step heavier than it and at least bold, at
  /// its size and slant. A bold trait added to the face is not enough — on a
  /// semibold face, which is what a heading is, it changes nothing, and strong
  /// text would read the same as the heading around it.
  public func strongFont(matching surrounding: PlatformFont) -> PlatformFont {
    let heavier = Self.heavier(than: surrounding.weight)
    let weight = heavier.rawValue > PlatformFont.Weight.bold.rawValue ? heavier : .bold
    let slant = surrounding.fontDescriptor.symbolicTraits.intersection(RFCTraits.italic)
    return PlatformFont.systemFont(ofSize: surrounding.pointSize, weight: weight)
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

  /// One step up the weights the reader uses: regular to semibold, semibold to
  /// bold, bold to heavy.
  private static func heavier(than weight: PlatformFont.Weight) -> PlatformFont.Weight {
    if weight.rawValue >= PlatformFont.Weight.bold.rawValue - 0.05 { return .heavy }
    if weight.rawValue >= PlatformFont.Weight.semibold.rawValue - 0.05 { return .bold }
    return .semibold
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

/// How wide the reader sets its text.
///
/// A setting, stored by its raw value — so the case names are what user defaults
/// hold, and renaming one resets everyone's choice. An enum rather than a flag, so
/// a third choice — an explicit measure — does not change every signature again.
public enum MeasurePreference: String, CaseIterable, Sendable {
  /// Capped at `ReaderLayout.idealMeasure`, the gutters growing beyond it.
  case recommended
  /// Out to the margins however wide the reader is, the way `less` does.
  case fullWidth
}

/// How wide the text column is, given how wide the view is and how wide the reader
/// wants its text.
///
/// A function of those two and nothing else, which is why it lives here rather
/// than inside the text view: the reader has to know the column *before* it
/// builds, because artwork scaling and table shape are measured against it, and a
/// document built against a guess has to be thrown away and built again.
public enum ReaderLayout {
  /// The design ceiling on the column: below this width the column tracks the view
  /// exactly (less `margin` on each side); above it the gutters grow instead, so
  /// the measure never exceeds what is comfortable to read.
  public static let idealMeasure = ReadingStyle().measure

  /// The smallest gutter beside the column, and the padding under the last line.
  public static let margin: CGFloat = 24

  /// The narrowest the reader's pane may be dragged to.
  ///
  /// The split view's other two columns declare their own minima; the detail
  /// column declared none, so it absorbed every pixel of a shrinking window and
  /// could be crushed to a few characters wide. This leaves a 372 pt column, a
  /// little wider than an iPhone's, and puts the window's floor at 900 pt with all
  /// three columns showing.
  public static let minimumPaneWidth: CGFloat = 420

  /// Both the build and the text view's inset ask this, with the same two inputs;
  /// the column is only ever what the gutters leave, so the two cannot drift.
  public static func gutter(forWidth width: CGFloat, measure: MeasurePreference) -> CGFloat {
    switch measure {
    case .recommended: max(margin, (width - idealMeasure) / 2)
    case .fullWidth: margin
    }
  }

  public static func column(forWidth width: CGFloat, measure: MeasurePreference) -> CGFloat {
    width - gutter(forWidth: width, measure: measure) * 2
  }

  /// Whether the reader's bar has room for Share beside Contents and More (#245).
  ///
  /// A regular width, which is an iPad, or a compact height, which is any iPhone
  /// held sideways. Most iPhones stay compact in width even in landscape, so width
  /// alone would keep them to the portrait bar.
  public static func toolbarHasRoom(isRegularWidth: Bool, isCompactHeight: Bool) -> Bool {
    isRegularWidth || isCompactHeight
  }
}

/// How wide the window's own title is drawn, given the column it sits over.
///
/// The title is a toolbar item rather than AppKit's, so its width is ours to work
/// out — and it is a pure function of the text's width and the column's, which is
/// why it is here and not in the view that applies it.
public enum ToolbarTitleLayout {
  /// The leading padding the title is inset by, and as much again at the trailing
  /// edge so it stops short of the divider rather than against it.
  public static let padding: CGFloat = 8

  /// Narrow enough to be worth drawing at all: below this the title is only an
  /// ellipsis, and the sidebar shows which collection is chosen anyway.
  static let minimumWidth: CGFloat = 80

  public static func width(forText text: CGFloat, inColumn column: CGFloat) -> CGFloat {
    min(text + padding * 2, max(minimumWidth, column - padding * 3))
  }

  /// Whether a title squeezed to this width still says anything. The reader's
  /// title flexes with the room between Back/Forward and the document's actions,
  /// and below this it draws nothing rather than a lone ellipsis.
  public static func isWorthDrawing(width: CGFloat) -> Bool {
    width >= minimumWidth
  }
}

/// How far the document's title has come into the reader's toolbar, from 0 to 1.
///
/// The header shows the title in full while it is on screen; as its heading scrolls
/// up under the toolbar, the toolbar's copy rises in to replace it, scrubbing with
/// the scroll rather than playing an animation. The transition runs over the
/// heading's last line — `distance` — so the toolbar's title arrives exactly as the
/// header's leaves: 0 while that line is wholly below the toolbar's bottom edge, 1
/// once it has passed wholly under it.
public enum ToolbarTitleReveal {
  /// `headingBottom` and `visibleTop` — the toolbar's bottom edge — are in the same
  /// coordinates, y growing down the document.
  public static func progress(
    headingBottom: CGFloat,
    visibleTop: CGFloat,
    distance: CGFloat
  ) -> CGFloat {
    guard distance > 0 else { return visibleTop >= headingBottom ? 1 : 0 }
    let travelled = (visibleTop - (headingBottom - distance)) / distance
    return min(1, max(0, travelled))
  }

  /// How opaque the toolbar's title is at a given progress: nothing for the first
  /// half of its travel, then fading in over the second. It rises from under the
  /// toolbar's bottom edge, and text faded in from the start is seen being cut by
  /// that edge; by halfway most of it is clear of it.
  public static func opacity(atProgress progress: CGFloat) -> CGFloat {
    min(1, max(0, (progress - 0.5) * 2))
  }
}

/// The system's text style sizes, in points, at each text size: Apple's Dynamic
/// Type tables for `.body`, `.title2` and `.title3` on iOS. (`.headline` is the
/// body's size throughout.)
///
/// Tabled rather than asked of `UIFontMetrics`, which exists only under UIKit: the
/// Mac has no Dynamic Type and always reports `.large`, and this package's tests
/// run there. The numbers are what `UIFontMetrics` scales to.
enum TextSizeMetrics {
  static func body(_ size: DynamicTypeSize) -> CGFloat {
    points(size, [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53])
  }

  static func title2(_ size: DynamicTypeSize) -> CGFloat {
    points(size, [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56])
  }

  static func title3(_ size: DynamicTypeSize) -> CGFloat {
    points(size, [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55])
  }

  /// `table` has one entry per size, from `.xSmall` to `.accessibility5`.
  private static func points(_ size: DynamicTypeSize, _ table: [CGFloat]) -> CGFloat {
    let index =
      switch size {
      case .xSmall: 0
      case .small: 1
      case .medium: 2
      case .large: 3
      case .xLarge: 4
      case .xxLarge: 5
      case .xxxLarge: 6
      case .accessibility1: 7
      case .accessibility2: 8
      case .accessibility3: 9
      case .accessibility4: 10
      case .accessibility5: 11
      @unknown default: 3
      }
    return table[index]
  }
}
