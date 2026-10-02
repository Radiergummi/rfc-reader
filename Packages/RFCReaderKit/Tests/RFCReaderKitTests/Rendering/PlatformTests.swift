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

  /// A stroke crosses from one line's fragment into the next, and two translucent
  /// partial coverages of one pixel composite lighter than one: #31's seam. Opaque,
  /// a stroke's pieces can overlap without showing it.
  @Test(arguments: [false, true])
  func `a stroke is an opaque mid gray in either appearance`(dark: Bool) throws {
    let stroke = try resolved(RFCColors.stroke, dark: dark)
    #expect(stroke.alpha == 1, "stroke alpha \(stroke.alpha)")
    #expect(stroke.white > 0.3 && stroke.white < 0.7, "stroke white \(stroke.white)")
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
    #expect(
      bold.fontDescriptor.symbolicTraits.contains(RFCTraits.bold), "\(Fixtures.describe(bold))")
  }

  /// #326: a font resolved again from its own descriptor came back at the system's
  /// default 12 pt, once in a while, under a full parallel test run. Strong text adds
  /// no trait to a bold system font, and must not go through that resolution at all.
  @Test func `adding a trait the font has is the same font`() {
    let bold = PlatformFont.systemFont(ofSize: 17, weight: .bold)
    #expect(bold.adding(traits: []) === bold)
    #expect(bold.adding(traits: RFCTraits.bold) === bold)
  }

  /// A superscript in strong italic text: the face, its weight and its slant at
  /// three quarters of the size, made as a copy of the font, not a descriptor match.
  @Test func `a resized font keeps its face and traits`() {
    let font = PlatformFont.systemFont(ofSize: 17, weight: .bold).adding(traits: RFCTraits.italic)
    let small = font.resized(to: 12.75)
    #expect(small.pointSize == 12.75, "\(Fixtures.describe(small))")
    #expect(small.fontName == font.fontName, "\(Fixtures.describe(small))")
    #expect(
      small.fontDescriptor.symbolicTraits.isSuperset(of: [RFCTraits.bold, RFCTraits.italic]),
      "\(Fixtures.describe(small))")
  }

  @Test func `traits are distinct and non empty`() {
    #expect(!RFCTraits.italic.isEmpty)
    #expect(!RFCTraits.bold.isEmpty)
    #expect(RFCTraits.italic != RFCTraits.bold)
  }
}
