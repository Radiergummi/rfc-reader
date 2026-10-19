import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// What a click or a tap in a highlight offers (#522): its color, Copy as Quote and
/// Delete. Its actions are closures the coordinator gives it, so it reads nothing from
/// the environment, which a popover's hosted root is outside of.
struct HighlightPopover: View {
  /// The width it is measured at on iOS, where the popover is sized before it shows.
  static let width: CGFloat = 260

  let color: HighlightColor
  let colors: [HighlightColor]
  let choose: (HighlightColor) -> Void
  let copyAsQuote: () -> Void
  let delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ForEach(colors) { option in
          Button {
            choose(option)
          } label: {
            HighlightSwatch(color: option, isChosen: option == color)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(verbatim: option.title()))
          .accessibilityAddTraits(option == color ? .isSelected : [])
        }
      }
      Divider()
      Button("Copy as Quote", systemImage: "text.quote", action: copyAsQuote)
        .buttonStyle(.borderless)
      Button("Delete Highlight", systemImage: "trash", role: .destructive, action: delete)
        .buttonStyle(.borderless)
    }
    .padding(12)
  }
}

/// A highlight color as a swatch: a filled circle, or for the underline an underlined
/// letter; ringed when it is the highlight's.
struct HighlightSwatch: View {
  let color: HighlightColor
  var isChosen = false

  static let size: CGFloat = 22

  var body: some View {
    ZStack {
      if color.isUnderline {
        Text(verbatim: "U")
          .font(.system(size: 13, weight: .semibold))
          .underline(color: Color(RFCColors.highlight(color)))
      } else {
        Circle().fill(Color(Self.opaque(color)))
      }
    }
    .frame(width: Self.size, height: Self.size)
    .overlay {
      Circle().strokeBorder(
        isChosen ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isChosen ? 2 : 1)
    }
    .contentShape(Circle())
  }

  /// The fill's color at full strength, which a swatch shows better than the
  /// translucent fill.
  static func opaque(_ color: HighlightColor) -> PlatformColor {
    PlatformColor(color.fill.light.color)
  }

  #if canImport(UIKit)
    /// The swatch as an image, for a menu's palette.
    static func image(_ color: HighlightColor) -> UIImage? {
      if color.isUnderline { return UIImage(systemName: "underline") }
      return UIImage(systemName: "circle.fill")?.withTintColor(
        opaque(color), renderingMode: .alwaysOriginal)
    }
  #else
    /// The swatch as an image, for a menu item.
    static func image(_ color: HighlightColor) -> NSImage? {
      if color.isUnderline {
        return NSImage(systemSymbolName: "underline", accessibilityDescription: nil)
      }
      let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
      let configuration = NSImage.SymbolConfiguration(paletteColors: [opaque(color)])
      return symbol?.withSymbolConfiguration(configuration)
    }
  #endif
}
