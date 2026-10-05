import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The color of each kind of token. A value, so that colors can be configured
/// (pickers in Settings, a color-blind variant, #707) by handing the builder another
/// theme through `ReadingStyle`. Its colors must be dynamic, resolved by appearance
/// when drawn, so that dark mode is a redraw and print's light appearance needs no
/// rebuild; and each must reach 4.5:1 against the verbatim card (`SyntaxThemeTests`).
///
/// Equal by `id` alone. A theme is part of `ReadingStyle`, which keys the preview
/// cache, and its colors are dynamic `PlatformColor`s, which compare by identity:
/// two themes are the same theme when they say they are, and a theme changed in
/// place has to get a new identifier, as a user's edited copy does (#709).
public struct SyntaxTheme: Sendable, Hashable, Identifiable {
  /// What user defaults hold for it (`ReaderPreferences.syntaxThemeKey`): renaming
  /// one resets everyone who chose it to the standard theme.
  public let id: String
  private let colors: [TokenKind: PlatformColor]

  public init(id: String, _ colors: [TokenKind: PlatformColor]) {
    self.id = id
    self.colors = colors
  }

  public static func == (lhs: SyntaxTheme, rhs: SyntaxTheme) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }

  /// Every theme the reader offers, the standard one first.
  public static let all: [SyntaxTheme] = [.standard]

  /// The theme called `id`, or the standard one where there is none by that name:
  /// one stored by a later version, or removed since.
  public static func named(_ id: String?) -> SyntaxTheme {
    all.first { $0.id == id } ?? .standard
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
    return SyntaxTheme(
      id: "standard",
      [
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
