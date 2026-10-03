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

  /// The status's fill: opaque, so the badge reads the same on a selected row.
  static func fill(for status: PublicationStatus) -> Color {
    Color(
      appearanceDependent: StatusPalette.colors(for: status, in: .light).fill,
      dark: StatusPalette.colors(for: status, in: .dark).fill)
  }

  /// The Info pane's Obsolete box's text color, measured as a status's is.
  static let obsoleteColor = Color(
    appearanceDependent: StatusPalette.obsolete(in: .light).text,
    dark: StatusPalette.obsolete(in: .dark).text)

  /// The Obsolete box's fill: opaque, as a status's is.
  static let obsoleteFill = Color(
    appearanceDependent: StatusPalette.obsolete(in: .light).fill,
    dark: StatusPalette.obsolete(in: .dark).fill)
}

extension Color {
  /// Colors whose contrast RFCReaderKit has measured, drawn as exactly those sRGB
  /// values: `light` in light appearance and `dark` in dark.
  init(appearanceDependent light: SRGBColor, dark: SRGBColor) {
    #if os(macOS)
      self.init(nsColor: RFCColors.byAppearance(light: light, dark: dark))
    #else
      self.init(uiColor: RFCColors.byAppearance(light: light, dark: dark))
    #endif
  }
}
