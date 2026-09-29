import RFCReaderKit
import SwiftUI

/// What a heading's backlink chip opens (#183): the sections that refer to the one
/// under it, each a button that goes there. Opened by a click or a tap on the chip,
/// not by a hover, because its rows are to be pressed: a hover card closes as the
/// pointer leaves the chip for it (`ReferencePreview`).
struct BacklinksList: View {
  let entries: [BacklinkEntry]
  let onSelect: (String) -> Void

  /// The list's fixed width: the reference card's.
  static let width = ReferencePreview.width

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Referred to from").font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 8)
      ForEach(entries, id: \.anchor) { entry in
        Button {
          onSelect(entry.anchor)
        } label: {
          HStack(alignment: .firstTextBaseline) {
            Text(entry.heading).lineLimit(2).multilineTextAlignment(.leading)
            Spacer()
            if entry.count > 1 {
              Text("\(entry.count)×").font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("\(entry.count) times")
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
    .frame(width: Self.width, alignment: .leading)
  }
}
