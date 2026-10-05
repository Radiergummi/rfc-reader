import RFCKit
import RFCReaderKit
import SwiftUI

/// The single most important piece of context: is this still the current document?
struct StatusBanner: View {
  /// Read from the environment of the hosting controller in the text view's top
  /// inset, which `ReaderEnvironment` makes sure it was given.
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(ReaderState.self) private var reader
  #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif
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
            symbol: "exclamationmark.triangle.fill", tint: Self.color(of: .obsoleted),
            comparesWith: offersComparison
              ? metadata.obsoletedBy.filter { $0 != metadata.id } : [])
        }
        if !metadata.updatedBy.isEmpty {
          row(
            "Updated by", metadata.updatedBy, term: .updates,
            symbol: "arrow.triangle.2.circlepath", tint: Self.color(of: .updated))
        }
        if metadata.hasErrata, let url = metadata.errataURL {
          Link(destination: url) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              symbol("pencil.and.list.clipboard")
              Text("This RFC has errata")
            }
          }
          .font(.subheadline)
          .foregroundStyle(Self.link)
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
    let title = Text(line.title).foregroundStyle(Self.link)
    let detail = Text(line.detail).foregroundStyle(.secondary)
    return DraftLink(line: line) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        symbol("doc.badge.clock").foregroundStyle(.secondary)
        // A key, not verbatim: only a LocalizedStringKey interpolates a styled Text;
        // a String would hold each one's debug description.
        Text(
          "\(relation) \(title) \(detail)", comment: "A draft's relation, its name and its stage")
      }
    }
    .font(.subheadline)
  }

  /// The title and the documents wrap beside the symbol, so a document updated by
  /// many others flows onto as many lines as it takes, indented under the title
  /// (#439). The title opens its glossary entry (#362).
  private func row(
    _ title: LocalizedStringKey, _ ids: [DocumentID], term: Glossary.ProcessTerm, symbol: String,
    tint: Color, comparesWith successors: [DocumentID] = []
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
            .foregroundStyle(Self.link)
            .lineLimit(1)
        }
        compare(with: successors)
      }
    }
    .font(.subheadline)
  }

  /// Whether this reader can open a successor beside it (#187): a reader read alone,
  /// where there is room for two.
  private var offersComparison: Bool {
    guard reader.coupling == nil else { return false }
    #if os(macOS)
      return true
    #else
      return SideBySide.isOffered(in: horizontalSizeClass)
    #endif
  }

  /// Reads the successor beside this document, the two scrolling together (#187).
  @ViewBuilder
  private func compare(with successors: [DocumentID]) -> some View {
    if successors.count == 1, let successor = successors.first {
      Button("Compare Side by Side") {
        reader.compare(metadata, with: successor, library: library)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Self.link)
    } else if !successors.isEmpty {
      Menu("Compare Side by Side") {
        ForEach(successors, id: \.self) { successor in
          Button(successor.displayName) {
            reader.compare(metadata, with: successor, library: library)
          }
        }
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .foregroundStyle(Self.link)
      .fixedSize()
    }
  }

  /// The banner's links, in the reader's link color rather than the accent, which on
  /// a Mac with a yellow or green accent was far below the minimum contrast (#317).
  private static let link = Color(RFCColors.readerLink)

  /// A row's symbol, in a color that clears 3:1 on the banner (#317).
  private static func color(of symbol: AccentContrast.BannerSymbol) -> Color {
    Color(appearanceDependent: symbol.colors.light, dark: symbol.colors.dark)
  }

  /// Hidden from accessibility: the row's text carries the meaning, as a `Label`'s
  /// title does.
  private func symbol(_ name: String) -> some View {
    Image(systemName: name)
      .frame(width: symbolWidth)
      .accessibilityHidden(true)
  }
}
