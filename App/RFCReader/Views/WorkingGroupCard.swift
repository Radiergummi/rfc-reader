import RFCReaderKit
import SwiftUI

/// What a working group is, above its RFCs (#363): its name, kind, area and state,
/// its chairs, how much it has published and when, and its pages. The words are
/// `WorkingGroupSummary`'s; this is only their layout.
struct WorkingGroupCard: View {
  let summary: WorkingGroupSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(summary.title)
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        if let acronym = summary.acronym {
          Text(acronym)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      if !summary.facts.isEmpty {
        Text(summary.facts.joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !summary.chairs.isEmpty {
        Text("Chairs: \(summary.chairs.formatted(.list(type: .and)))")
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let publications = summary.publications {
        Text(publications)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      if !summary.links.isEmpty {
        WrappingRowLayout(spacing: 14) {
          ForEach(summary.links, id: \.self) { link in
            Link(destination: link.url) {
              Label(link.title, systemImage: link.symbol)
            }
            .font(.subheadline)
          }
        }
        .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    #if os(macOS)
      // A card of its own on the Mac's inset list; on iOS the grouped list's row is one.
      .padding(12)
      .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    #endif
  }
}
