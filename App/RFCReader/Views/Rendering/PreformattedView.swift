import RFCKit
import SwiftUI

/// Artwork, packet diagrams and source code: monospaced, never wrapped, horizontally scrollable.
struct PreformattedView: View {
    let content: Preformatted
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if content.kind == .sourceCode, let type = content.type {
                Text(type.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                Text(content.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button {
                    Clipboard.copy(content.text)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy")
            }
        }
        .id(content.anchor ?? "")
    }
}
