import RFCReaderKit
import SwiftUI

extension View {
  /// This view's text in a page theme's colors (#704): its body text as the
  /// primary style, its secondary text as the secondary, and its links as the
  /// tint. Unchanged under the automatic palette, which keeps the system's.
  func readerPalette(_ palette: ReaderPalette) -> some View {
    modifier(ReaderPaletteStyle(palette: palette))
  }
}

private struct ReaderPaletteStyle: ViewModifier {
  let palette: ReaderPalette

  func body(content: Content) -> some View {
    if palette.drawsSystemColors {
      content
    } else {
      content
        .foregroundStyle(Color(palette.text), Color(palette.secondaryText))
        .tint(Color(palette.link))
    }
  }
}
