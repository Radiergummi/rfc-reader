import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Syntax theme")
@MainActor
struct SyntaxThemeTests {
  @Test func `plain text keeps the body color`() {
    #expect(SyntaxTheme.standard.color(for: .plain) == nil)
  }

  @Test func `every other kind has a color`() {
    for kind in TokenKind.allCases where kind != .plain {
      #expect(SyntaxTheme.standard.color(for: kind) != nil, "\(kind)")
    }
  }

  /// Dark mode is a redraw, never a rebuild, so a theme's colors must resolve by
  /// appearance.
  @Test func `every color is dynamic`() throws {
    for kind in TokenKind.allCases where kind != .plain {
      let color = try #require(SyntaxTheme.standard.color(for: kind))
      #expect(try resolved(color, dark: false) != resolved(color, dark: true), "\(kind)")
    }
  }

  /// The pages a card is drawn on: white in light; black (iOS) and macOS's dark text
  /// background in dark.
  @Test(arguments: [(false, 1.0), (true, 0.0), (true, 0.118)])
  func `every color reaches 4.5 to 1 against the card`(dark: Bool, page: Double) throws {
    let card = try resolved(RFCColors.cardFill, dark: dark)
    #expect(card.alpha > 0 && card.red >= 0, "the card resolves in sRGB")
    let level = page * (1 - card.alpha) + card.red * card.alpha
    let background = SRGBColor(red: level, green: level, blue: level)
    for kind in TokenKind.allCases where kind != .plain {
      let color = try resolved(try #require(SyntaxTheme.standard.color(for: kind)), dark: dark)
      let ratio = SRGBColor(red: color.red, green: color.green, blue: color.blue)
        .contrast(with: background)
      #expect(ratio >= 4.5, "\(kind) is \(ratio):1 on \(level) in \(dark ? "dark" : "light")")
    }
  }

  private struct Resolved: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
  }

  private func resolved(_ color: PlatformColor, dark: Bool) throws -> Resolved {
    var red: CGFloat = -1
    var green: CGFloat = -1
    var blue: CGFloat = -1
    var alpha: CGFloat = -1
    #if canImport(UIKit)
      let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
      _ = color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    #else
      let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
      appearance.performAsCurrentDrawingAppearance {
        color.usingColorSpace(.sRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      }
    #endif
    return Resolved(red: red, green: green, blue: blue, alpha: alpha)
  }
}
