#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension PlatformFont {
  /// The monospaced system font, made only once one is kept alive for good (#732).
  /// While no monospaced system font is alive in a process, monospaced fonts made on
  /// many threads at once can crash CoreText when it measures them: a `CTLine` raises
  /// an uncaught `NSInvalidArgumentException`. RFCReaderKit makes them off the main
  /// actor, in builds that run side by side, and its tests in parallel; the app's PDF
  /// export does too. The `monospaced_font_kept` lint rule keeps every other call out.
  public static func monospacedFont(ofSize size: CGFloat, weight: Weight) -> PlatformFont {
    _ = keptMonospacedFont
    return monospacedSystemFont(ofSize: size, weight: weight)
  }

  /// A monospaced system font, never released. Made by whichever thread asks first,
  /// while any other waits: a `static let` is initialized under a lock.
  #if canImport(UIKit)
    private static let keptMonospacedFont = monospacedSystemFont(ofSize: 12, weight: .regular)
  #else
    // Unsafe only in name: `NSFont` is not `Sendable`, as `UIFont` is, but a font is
    // immutable, and this one is never read, only held.
    nonisolated(unsafe) private static let keptMonospacedFont = monospacedSystemFont(
      ofSize: 12, weight: .regular)
  #endif
}
