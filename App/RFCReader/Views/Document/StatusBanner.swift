import RFCKit
import RFCReaderKit
import SwiftUI

/// The single most important piece of context: is this still the current document?
struct StatusBanner: View {
  /// Handed over rather than read from the environment.
  ///
  /// This view is hosted in an `NSHostingController`/`UIHostingController` in the
  /// text view's top inset — outside the SwiftUI tree that `ContentView` injects
  /// into — so an `@Environment` lookup here is a runtime trap waiting to fire
  /// rather than a compile-time requirement. The two models arrive as properties so
  /// the compiler is the thing that notices when a call site forgets one.
  let library: LibraryModel
  let navigation: NavigationModel
  let metadata: RFCMetadata
  /// From the header's identity, so a new `revisions.json` re-measures the header.
  let revisionLines: [RevisionsSummary.Line]
  let moreRevisions: String?

  /// Every row's symbol gets this width, so each row's text, and the document
  /// rows' wrapped lines under it, start at the same x. The widest symbol is about
  /// 1.3 times the font's size; this fits the subheadline on both platforms.
  @ScaledMetric(relativeTo: .subheadline) private var symbolWidth = 20.0

  var body: some View {
    if metadata.isObsolete || !metadata.updatedBy.isEmpty || metadata.hasErrata
      || !revisionLines.isEmpty
    {
      VStack(alignment: .leading, spacing: 6) {
        if metadata.isObsolete {
          row(
            "Obsoleted by", metadata.obsoletedBy, term: .obsoletes,
            symbol: "exclamationmark.triangle.fill", tint: .red)
        }
        if !metadata.updatedBy.isEmpty {
          row(
            "Updated by", metadata.updatedBy, term: .updates,
            symbol: "arrow.triangle.2.circlepath", tint: .orange)
        }
        if metadata.hasErrata, let url = metadata.errataURL {
          Link(destination: url) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              symbol("pencil.and.list.clipboard")
              Text("This RFC has errata")
            }
          }
          .font(.subheadline)
        }
        if !revisionLines.isEmpty {
          ForEach(revisionLines) { line in
            revisionRow(line)
          }
          if let more = moreRevisions {
            Text(more)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(12)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  /// News, not a warning: a secondary symbol, unlike the red and orange rows above.
  /// The whole row is the link to the draft's datatracker page. One `Text`, so a
  /// narrow banner wraps it as a sentence rather than squeezing three columns.
  private func revisionRow(_ line: RevisionsSummary.Line) -> some View {
    let relation = Text(line.relation).fontWeight(.medium).foregroundStyle(.primary)
    let title = Text(line.title).foregroundStyle(.tint)
    let detail = Text(line.detail).foregroundStyle(.secondary)
    return DraftLink(line: line) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        symbol("doc.badge.clock").foregroundStyle(.secondary)
        Text("\(relation) \(title) \(detail)")
      }
    }
    .font(.subheadline)
  }

  /// The title and the documents wrap beside the symbol, so a document updated by
  /// many others flows onto as many lines as it takes, indented under the title
  /// (#439). The title opens its glossary entry (#362).
  private func row(
    _ title: String, _ ids: [DocumentID], term: Glossary.ProcessTerm, symbol: String, tint: Color
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      self.symbol(symbol).foregroundStyle(tint)
      WrappingRowLayout(spacing: 6) {
        GlossaryButton(term: .process(term), presentation: .scene(navigation)) {
          Text(title).fontWeight(.medium)
        }
        ForEach(ids, id: \.self) { id in
          Button(id.displayName) { library.open(id, activation: .current, in: navigation) }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .lineLimit(1)
        }
      }
    }
    .font(.subheadline)
  }

  /// Hidden from accessibility: the row's text carries the meaning, as a `Label`'s
  /// title does.
  private func symbol(_ name: String) -> some View {
    Image(systemName: name)
      .frame(width: symbolWidth)
      .accessibilityHidden(true)
  }
}
