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

    public var bodyFont: PlatformFont { .systemFont(ofSize: bodySize) }
    public var boldBodyFont: PlatformFont { .boldSystemFont(ofSize: bodySize) }
    public var captionFont: PlatformFont { .systemFont(ofSize: bodySize * 0.88) }
    public var codeFont: PlatformFont { .monospacedSystemFont(ofSize: bodySize * 0.92, weight: .regular) }

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
