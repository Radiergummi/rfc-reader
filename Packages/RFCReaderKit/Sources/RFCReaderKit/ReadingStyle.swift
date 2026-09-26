import Foundation

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

  public init(bodySize: CGFloat = 17, measure: CGFloat = 712, lineHeightMultiple: CGFloat = 1.25) {
    self.bodySize = bodySize
    self.measure = measure
    self.lineHeightMultiple = lineHeightMultiple
  }

  /// The same style at a different size — everything else about reading it is
  /// unchanged, so only the body size moves and the rest follows from it.
  public func scaled(by scale: CGFloat) -> ReadingStyle {
    ReadingStyle(
      bodySize: bodySize * scale, measure: measure, lineHeightMultiple: lineHeightMultiple)
  }

  public var bodyFont: PlatformFont { .systemFont(ofSize: bodySize) }
  public var boldBodyFont: PlatformFont { .boldSystemFont(ofSize: bodySize) }
  public var captionFont: PlatformFont { .systemFont(ofSize: bodySize * 0.88) }
  public var codeFont: PlatformFont {
    .monospacedSystemFont(ofSize: bodySize * 0.92, weight: .regular)
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
}

/// How wide the window's own title is drawn, given the column it sits over.
///
/// The title is a toolbar item rather than AppKit's, so its width is ours to work
/// out — and it is a pure function of the text's width and the column's, which is
/// why it is here and not in the view that applies it.
public enum ToolbarTitleLayout {
  /// The leading padding the title is inset by, and as much again at the trailing
  /// edge so it stops short of the divider rather than against it.
  static let padding: CGFloat = 8

  /// Narrow enough to be worth drawing at all: below this the title is only an
  /// ellipsis, and the tab bar carries the same text anyway.
  static let minimumWidth: CGFloat = 80

  public static func width(forText text: CGFloat, inColumn column: CGFloat) -> CGFloat {
    min(text + padding * 2, max(minimumWidth, column - padding * 3))
  }
}
