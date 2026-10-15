import RFCKit
import RFCReaderKit
import SwiftUI

/// A section the full-text search found (#37), in the list's "In the Text" rows: its
/// RFC, the section, and the words around the match, the matched ones bold.
struct SectionHitRow: View {
  let hit: SectionHit
  /// The RFC's title, from the index.
  let title: String?

  /// "5.3 Connection ID", or the heading alone for a section with no number.
  private var section: String {
    hit.number.map { "\($0) \(hit.heading)" } ?? hit.heading
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        // A narrow no-break space, as `RFCRow` writes the number.
        Text(verbatim: hit.document.displayName.replacing(" ", with: "\u{202F}"))
        if let title {
          Text(verbatim: title)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      Text(verbatim: section)
        .lineLimit(1)
      Text(SectionResults.attributed(hit.snippet))
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(3)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
