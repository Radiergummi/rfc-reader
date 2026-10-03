import RFCReaderKit
import SwiftUI

/// What a heading's backlink caption opens (#183): the sections that refer to the one
/// under it, each a button that goes there. Opened by a click or a tap on the caption,
/// not by a hover, because its rows are to be pressed: a hover card closes as the
/// pointer leaves the caption for it (`ReferencePreview`).
struct BacklinksList: View {
  let entries: [BacklinkEntry]
  let onSelect: (String) -> Void

  /// The list's fixed width: the reference card's.
  static let width = ReferencePreview.width
  /// The tallest the rows are before they scroll: a section every other one refers
  /// to, such as a terminology section, would otherwise run the popover off the
  /// screen, its last rows out of reach.
  static let maximumRowsHeight: CGFloat = 320

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Referred to from").font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 8)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
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
      }
      // As tall as the rows up to the cap, not as tall as it is offered: the
      // popover is sized to what the list asks for.
      .frame(maxHeight: Self.maximumRowsHeight)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
    .frame(width: Self.width, alignment: .leading)
  }
}
