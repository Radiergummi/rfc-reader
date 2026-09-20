import RFCKit
import SwiftUI

struct StatusBadge: View {
    let status: PublicationStatus

    var body: some View {
        Text(shortName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(status.displayName)
    }

    private var shortName: String {
        switch status {
        case .internetStandard: "STD"
        case .draftStandard: "Draft STD"
        case .proposedStandard: "Proposed"
        case .bestCurrentPractice: "BCP"
        case .informational: "Info"
        case .experimental: "Experimental"
        case .historic: "Historic"
        case .unknown: "Unknown"
        }
    }

    private var color: Color {
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
