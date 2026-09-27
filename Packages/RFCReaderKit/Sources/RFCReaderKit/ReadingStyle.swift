import Foundation

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
  public var bodySize: CGFloat
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

  public init(
    bodySize: CGFloat = 17, measure: CGFloat = 712, lineHeightMultiple: CGFloat = 1.25,
    underlinesLinks: Bool = false
  ) {
    self.bodySize = bodySize
    self.measure = measure
    self.lineHeightMultiple = lineHeightMultiple
    self.underlinesLinks = underlinesLinks
  }

  /// The same style at a different size — everything else about reading it is
  /// unchanged, so only the body size moves and the rest follows from it.
  public func scaled(by scale: CGFloat) -> ReadingStyle {
    ReadingStyle(
      bodySize: bodySize * scale, measure: measure, lineHeightMultiple: lineHeightMultiple,
      underlinesLinks: underlinesLinks)
  }

  public var bodyFont: PlatformFont { .systemFont(ofSize: bodySize) }
  public var boldBodyFont: PlatformFont { .boldSystemFont(ofSize: bodySize) }
  public var captionFont: PlatformFont { .systemFont(ofSize: bodySize * 0.88) }
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

  public func monospacedFont(scale: CGFloat) -> PlatformFont {
    .monospacedSystemFont(ofSize: bodySize * 0.82 * scale, weight: .regular)
  }

  /// `1.` is a title, `1.1.` a subtitle, deeper is a headline. Mirrors what
  /// `SectionView` did with `Font.title2` / `.title3` / `.headline`.
  public func headingFont(depth: Int) -> PlatformFont {
    switch depth {
    case 1: .systemFont(ofSize: bodySize * 1.3, weight: .semibold)
    case 2: .systemFont(ofSize: bodySize * 1.15, weight: .semibold)
    default: .systemFont(ofSize: bodySize, weight: .semibold)
    }
  }

  public var paragraphSpacing: CGFloat { bodySize * 0.7 }
  public var indentStep: CGFloat { bodySize * 1.4 }
}

/// How wide the text column is, given how wide the view is.
///
/// A function of the view's width and nothing else, which is why it lives here
/// rather than inside the text view: the reader has to know the column *before* it
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

  public static func gutter(forWidth width: CGFloat) -> CGFloat {
    max(margin, (width - idealMeasure) / 2)
  }

  public static func column(forWidth width: CGFloat) -> CGFloat {
    width - gutter(forWidth: width) * 2
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
