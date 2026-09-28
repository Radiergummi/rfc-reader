import RFCKit
import SwiftUI

struct StatusBadge: View {
  let status: PublicationStatus

  var body: some View {
    Text(status.shortName)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Self.color(for: status).opacity(0.15), in: Capsule())
      .foregroundStyle(Self.color(for: status))
      .accessibilityLabel(status.displayName)
  }

  /// The status's tint, shared with the Info pane's status box.
  static func color(for status: PublicationStatus) -> Color {
    switch status {
    case .internetStandard, .draftStandard: .green
    case .proposedStandard: .blue
    case .bestCurrentPractice: .purple
    case .informational: .gray
    case .experimental: .orange
    case .historic: .brown
    case .unknown: .secondary
    }
  }
}
