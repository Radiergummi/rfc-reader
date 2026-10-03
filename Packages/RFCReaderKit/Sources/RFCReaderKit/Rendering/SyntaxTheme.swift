import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The color of each kind of token. A value, so that colors can be configured later
/// (pickers in Settings, a color-blind variant) by handing the builder another
/// theme. Its colors must be dynamic, resolved by appearance when drawn, so that
/// dark mode is a redraw and print's light appearance needs no rebuild; and each
/// must reach 4.5:1 against the verbatim card (`SyntaxThemeTests`).
public struct SyntaxTheme: Sendable {
  private let colors: [TokenKind: PlatformColor]

  public init(_ colors: [TokenKind: PlatformColor]) {
    self.colors = colors
  }

  /// The color of `kind`, or nil to keep the body color of the block's context,
  /// which a quote or an aside sets: always for plain text.
  public func color(for kind: TokenKind) -> PlatformColor? {
    kind == .plain ? nil : colors[kind]
  }

  /// Restrained, for a reader where code supports the prose: names, strings and
  /// literals in three quiet hues, punctuation and comments in gray. The system's
  /// secondary label color, about 4:1 on the card, is too faint for them.
  public static let standard: SyntaxTheme = {
    let muted = color(light: 0x6E6E73, dark: 0xA1A1A6)
    let literal = color(light: 0x8A3FB0, dark: 0xD9A6F5)
    return SyntaxTheme([
      .punctuation: muted,
      .comment: muted,
      .name: color(light: 0x3A3AB8, dark: 0xA9A9FF),
      .string: color(light: 0x1F7A3A, dark: 0x7BD88F),
      .keyword: literal,
      .number: literal,
      .attribute: literal,
    ])
  }()

  /// A color for each appearance, as sRGB hex, resolved when it is drawn.
  static func color(light: UInt32, dark: UInt32) -> PlatformColor {
    RFCColors.byAppearance(light: SRGBColor(hex: light), dark: SRGBColor(hex: dark))
  }
}
