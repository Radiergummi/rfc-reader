import RFCKit
import RFCReaderKit
import SwiftUI

struct StatusBadge: View {
  let status: PublicationStatus

  var body: some View {
    Text(status.shortName)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Self.fill(for: status), in: Capsule())
      .foregroundStyle(Self.color(for: status))
      .accessibilityLabel(status.displayName)
  }

  /// The status's text color, shared with the Info pane's status box: one that
  /// clears the minimum contrast on ``fill(for:)`` in either appearance (#317).
  static func color(for status: PublicationStatus) -> Color {
    Color(
      appearanceDependent: StatusPalette.colors(for: status, in: .light).text,
      dark: StatusPalette.colors(for: status, in: .dark).text)
  }

  /// The status's fill: opaque in light appearance, translucent in dark, so the pill
  /// takes the color of what is behind it.
  static func fill(for status: PublicationStatus) -> Color {
    Color(
      fill: StatusPalette.colors(for: status, in: .light),
      dark: StatusPalette.colors(for: status, in: .dark))
  }

  /// The Info pane's Obsolete box's text color, measured as a status's is.
  static let obsoleteColor = Color(
    appearanceDependent: StatusPalette.obsolete(in: .light).text,
    dark: StatusPalette.obsolete(in: .dark).text)

  /// The Obsolete box's fill, drawn as a status's is.
  static let obsoleteFill = Color(
    fill: StatusPalette.obsolete(in: .light), dark: StatusPalette.obsolete(in: .dark))
}

extension Color {
  /// Colors whose contrast RFCReaderKit has measured, drawn as exactly those sRGB
  /// values at those opacities: `light` in light appearance and `dark` in dark.
  init(
    appearanceDependent light: SRGBColor, dark: SRGBColor, lightOpacity: Double = 1,
    darkOpacity: Double = 1
  ) {
    #if os(macOS)
      self.init(
        nsColor: NSColor(name: nil) { appearance in
          let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          let color = isDark ? dark : light
          return NSColor(
            srgbRed: color.red, green: color.green, blue: color.blue,
            alpha: isDark ? darkOpacity : lightOpacity)
        })
    #else
      self.init(
        uiColor: UIColor { traits in
          let isDark = traits.userInterfaceStyle == .dark
          let color = isDark ? dark : light
          return UIColor(
            red: color.red, green: color.green, blue: color.blue,
            alpha: isDark ? darkOpacity : lightOpacity)
        })
    #endif
  }

  /// A palette's fill, at the opacity it is measured at in each appearance.
  init(fill light: StatusPalette.Colors, dark: StatusPalette.Colors) {
    self.init(
      appearanceDependent: light.fill, dark: dark.fill, lightOpacity: light.fillOpacity,
      darkOpacity: dark.fillOpacity)
  }
}
