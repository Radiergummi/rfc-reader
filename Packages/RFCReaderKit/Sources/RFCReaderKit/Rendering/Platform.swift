#if canImport(UIKit)
  import UIKit

  public typealias PlatformFont = UIFont
  public typealias PlatformColor = UIColor
  public typealias PlatformFontDescriptor = UIFontDescriptor
  public typealias PlatformImage = UIImage
#else
  import AppKit

  public typealias PlatformFont = NSFont
  public typealias PlatformColor = NSColor
  public typealias PlatformFontDescriptor = NSFontDescriptor
  public typealias PlatformImage = NSImage

  extension NSImage {
    /// Mirrors `UIImage(systemName:)` so the builder can ask for an SF Symbol
    /// without branching on platform.
    convenience init?(systemName: String) {
      self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }
  }
#endif

/// Dynamic colors, stored in the attributed string unresolved so that a change of
/// appearance or accent costs a redraw rather than a rebuild of the whole document.
public enum RFCColors {
  public static var label: PlatformColor {
    #if canImport(UIKit)
      .label
    #else
      .labelColor
    #endif
  }

  public static var secondaryLabel: PlatformColor {
    #if canImport(UIKit)
      .secondaryLabel
    #else
      .secondaryLabelColor
    #endif
  }

  public static var accent: PlatformColor {
    #if canImport(UIKit)
      .tintColor
    #else
      .controlAccentColor
    #endif
  }

  /// A link, where no text view colours it: an exported PDF's (#376).
  public static var link: PlatformColor {
    #if canImport(UIKit)
      .link
    #else
      .linkColor
    #endif
  }

  /// The card behind artwork and tables: a faint tint of the page, the way Apple's
  /// documentation sets a code listing. DocC darkens a white page to 247 and lifts a
  /// black one to 22, about 3% towards black and 9% towards white. A system fill
  /// forced to a fixed opacity read far darker than that in light and far lighter
  /// in dark.
  public static var cardFill: PlatformColor { pageTint(light: 0.03, dark: 0.085) }

  /// An aside's card, a step stronger than a figure's.
  public static var asideFill: PlatformColor { pageTint(light: 0.045, dark: 0.12) }

  /// Black at `light` on a light page, white at `dark` on a dark one. Translucent,
  /// so it tints whatever the page is rather than assuming its color.
  private static func pageTint(light: CGFloat, dark: CGFloat) -> PlatformColor {
    #if canImport(UIKit)
      UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(white: 1, alpha: dark) : UIColor(white: 0, alpha: light)
      }
    #else
      NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
      }
    #endif
  }

  /// The rule beside a quote or aside: a line, not a fill. macOS's
  /// `quaternarySystemFill` is about a quarter as opaque as the `quaternaryLabelColor`
  /// the rule used to draw in, which left a rule this thin close to invisible;
  /// `separatorColor` is the line color, at about the old opacity. iOS's
  /// `quaternarySystemFill` is darker, and the rule keeps it.
  public static var rule: PlatformColor {
    #if canImport(UIKit)
      .quaternarySystemFill
    #else
      .separatorColor
    #endif
  }

  /// The lines a decorated block draws over its text: the label color, a step
  /// back, so a grid reads as structure and its field names as the content.
  public static var stroke: PlatformColor { secondaryLabel }
}

/// Symbolic traits, which AppKit and UIKit spell differently.
public enum RFCTraits {
  public static var italic: PlatformFontDescriptor.SymbolicTraits {
    #if canImport(UIKit)
      .traitItalic
    #else
      .italic
    #endif
  }

  public static var bold: PlatformFontDescriptor.SymbolicTraits {
    #if canImport(UIKit)
      .traitBold
    #else
      .bold
    #endif
  }

  /// For the tests, which check that code runs are set monospaced.
  static var monospace: PlatformFontDescriptor.SymbolicTraits {
    #if canImport(UIKit)
      .traitMonoSpace
    #else
      .monoSpace
    #endif
  }
}

extension PlatformImage {
  /// An SF Symbol rendered at `pointSize`. AppKit and UIKit spell the
  /// configuration step differently (`withSymbolConfiguration` against
  /// `withConfiguration`); that difference belongs here rather than in the builder.
  static func symbol(named name: String, pointSize: CGFloat) -> PlatformImage? {
    let configuration = SymbolConfiguration(pointSize: pointSize, weight: .regular)
    #if canImport(UIKit)
      return PlatformImage(systemName: name)?.withConfiguration(configuration)
    #else
      return PlatformImage(systemName: name)?.withSymbolConfiguration(configuration)
    #endif
  }
}

extension PlatformFont {
  /// This font with `traits` added, or this font unchanged when the descriptor
  /// cannot supply them. UIKit's `withSymbolicTraits` returns an optional
  /// descriptor and AppKit's does not, and only AppKit's font initializer is
  /// failable; both spellings collapse to the same fallback here.
  func adding(traits: PlatformFontDescriptor.SymbolicTraits) -> PlatformFont {
    let descriptor = fontDescriptor
    let combined = descriptor.symbolicTraits.union(traits)
    #if canImport(UIKit)
      guard let traited = descriptor.withSymbolicTraits(combined) else { return self }
      return PlatformFont(descriptor: traited, size: pointSize)
    #else
      return PlatformFont(descriptor: descriptor.withSymbolicTraits(combined), size: pointSize)
        ?? self
    #endif
  }

  /// The font's weight as its descriptor states it. This is what lets a run inside
  /// a semibold heading keep its weight. A face that states no weight at all is
  /// bold if it carries the bold trait and regular otherwise. The trait alone is
  /// not the weight: a semibold face carries it too, and reading that as bold set
  /// inline code in a heading heavier than the heading around it (#153).
  var weight: PlatformFont.Weight {
    let traits = fontDescriptor.object(forKey: .traits) as? [PlatformFontDescriptor.TraitKey: Any]
    if let stated = traits?[.weight] as? CGFloat, stated != 0 {
      return PlatformFont.Weight(rawValue: stated)
    }
    return fontDescriptor.symbolicTraits.contains(RFCTraits.bold) ? .bold : .regular
  }

  /// This font's face and traits at another size.
  func resized(to size: CGFloat) -> PlatformFont {
    #if canImport(UIKit)
      PlatformFont(descriptor: fontDescriptor, size: size)
    #else
      PlatformFont(descriptor: fontDescriptor, size: size) ?? self
    #endif
  }
}
