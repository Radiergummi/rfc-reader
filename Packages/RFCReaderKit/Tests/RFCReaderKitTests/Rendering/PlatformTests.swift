import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Platform types")
@MainActor
struct PlatformTests {
  @Test func `dynamic colors are not resolved`() {
    // The point of RFCColors is that the values stored in the attributed string
    // resolve at draw time, so dark mode costs a redraw and never a rebuild.
    #expect(RFCColors.label !== RFCColors.secondaryLabel)
  }

  /// A card is a faint tint of the page, as Apple's documentation sets a code
  /// listing: DocC darkens a white page to 247 and lifts a black one to 22. The
  /// system fills forced to 0.3 opacity read far darker in light and far lighter in
  /// dark. An aside is set a little stronger than a figure.
  @Test(arguments: [false, true])
  func `cards are a faint tint of the page`(dark: Bool) throws {
    let card = try resolved(RFCColors.cardFill, dark: dark)
    let aside = try resolved(RFCColors.asideFill, dark: dark)
    // Towards black on a light page, towards white on a dark one.
    #expect(card.white == (dark ? 1 : 0))
    #expect(card.alpha > 0.02 && card.alpha < 0.1, "card alpha \(card.alpha)")
    #expect(aside.alpha > card.alpha && aside.alpha < 0.15, "aside alpha \(aside.alpha)")
  }

  private func resolved(_ color: PlatformColor, dark: Bool) throws -> (
    white: CGFloat, alpha: CGFloat
  ) {
    var white: CGFloat = -1
    var alpha: CGFloat = -1
    #if canImport(UIKit)
      let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
      _ = color.resolvedColor(with: traits).getWhite(&white, alpha: &alpha)
    #else
      let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
      appearance.performAsCurrentDrawingAppearance {
        color.usingColorSpace(.genericGray)?.getWhite(&white, alpha: &alpha)
      }
    #endif
    return (white, alpha)
  }

  @Test func `the symbol shim renders at the size asked`() throws {
    let small = try #require(PlatformImage.symbol(named: "doc.text", pointSize: 10))
    let large = try #require(PlatformImage.symbol(named: "doc.text", pointSize: 30))
    #expect(large.size.height > small.size.height)
  }

  @Test func `adding a trait keeps the size and adds the trait`() {
    let base = PlatformFont.systemFont(ofSize: 17)
    let bold = base.adding(traits: RFCTraits.bold)
    #expect(bold.pointSize == base.pointSize)
    #expect(bold.fontDescriptor.symbolicTraits.contains(RFCTraits.bold))
  }

  @Test func `traits are distinct and non empty`() {
    #expect(!RFCTraits.italic.isEmpty)
    #expect(!RFCTraits.bold.isEmpty)
    #expect(RFCTraits.italic != RFCTraits.bold)
  }
}
