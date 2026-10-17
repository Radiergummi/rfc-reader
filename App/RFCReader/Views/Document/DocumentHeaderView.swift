import RFCKit
import RFCReaderKit
import SwiftUI

/// Everything above the first line of prose: title, badges, authors, and the status
/// banner. Hosted in the text view's top content inset, so it scrolls with the body
/// without being part of it — the banner carries buttons, and nobody selects through
/// it. The abstract is no longer here; it is the first prose in the storage, which is
/// what puts the banner between the title and the abstract as `VISION.md` asks.
struct DocumentHeaderView: View {
  /// Hosted outside the SwiftUI hierarchy, by a host that `ReaderEnvironment`
  /// guarantees gave it the environment.
  @Environment(NavigationModel.self) private var navigation

  /// Exactly what the body below reads, and nothing else.
  ///
  /// The header is hosted in a `UIHostingController`/`NSHostingController` that
  /// sits outside SwiftUI's diffing, so assigning `rootView` re-renders the whole
  /// subtree — on every update pass, which includes every section crossing while
  /// scrolling. Comparing this decides whether that assignment is needed at all.
  /// It is also the view's input, so a field it does not carry is a field the
  /// header cannot display, and the two cannot fall out of step.
  struct Identity: Equatable {
    let title: String
    let date: String?
    let workingGroup: String?
    /// Whole, not pre-joined names: a chip needs the author's contact (#19).
    let authors: [Author]
    /// Everything else the header shows comes straight off the metadata, which
    /// is `Hashable` — so it is compared whole rather than field by field.
    let metadata: RFCMetadata?
    /// The banner's drafts, as lines rather than the summary, which carries the time
    /// it was made and so would never compare equal.
    let revisionLines: [RevisionsSummary.Line]
    let moreRevisions: String?
    /// The errata naming no section the document has (#387), which the chip by the
    /// date lists.
    let documentErrata: [ErrataSummary.Item]

    /// Merged by `HeaderSummary`, which a printed page's title block reads too.
    init(
      header: DocumentHeader, metadata: RFCMetadata?, revisions: RevisionsSummary? = nil,
      documentErrata: [ErrataSummary.Item] = []
    ) {
      let summary = HeaderSummary(header: header, metadata: metadata)
      title = summary.title
      date = summary.date
      workingGroup = summary.workingGroup
      authors = summary.authors
      self.metadata = metadata
      revisionLines = revisions?.bannerLines ?? []
      moreRevisions = revisions?.moreText
      self.documentErrata = documentErrata
    }
  }

  /// The view renders from the identity rather than beside it, so the two cannot
  /// describe different headers.
  let identity: Identity

  /// Told where the heading ends, for the toolbar's copy of the title to take over
  /// from as it scrolls away; see `ToolbarTitleReveal`.
  let reader: ReaderController

  nonisolated static let coordinateSpace = "documentHeader"

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(identity.title)
        .font(.largeTitle.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
          $0.frame(in: .named(Self.coordinateSpace)).maxY
        } action: { bottom in
          reader.headingBottom = bottom
        }
      HStack(spacing: 8) {
        if let metadata = identity.metadata {
          GlossaryButton(term: .status(metadata.currentStatus), presentation: .scene(navigation)) {
            StatusBadge(status: metadata.currentStatus)
          }
          GlossaryButton(term: .stream(metadata.stream), presentation: .scene(navigation)) {
            Text(metadata.stream.displayName)
          }
        }
        if let date = identity.date {
          Text(date)
        }
        if let group = identity.workingGroup {
          Text(group)
        }
        if !identity.documentErrata.isEmpty {
          DocumentErrataChip(items: identity.documentErrata)
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      if !identity.authors.isEmpty {
        AuthorChips(authors: identity.authors)
          .font(.subheadline)
      }
      if let metadata = identity.metadata {
        StatusBanner(
          metadata: metadata, revisionLines: identity.revisionLines,
          moreRevisions: identity.moreRevisions
        )
        .padding(.top, 4)
      }
    }
    // The header is hosted, not placed by SwiftUI, and a hosting view lays its
    // root out at that root's own width rather than at the frame the coordinator
    // gave it — so a `VStack` that hugs its content ends up somewhere other than
    // the column's leading edge, and by a distance that changes with the title's
    // length. Filling the column is the same instruction the body text gets.
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The whole document's errata (#387), those naming no section it has: a chip by the
/// date, worded as a heading's is, which lists them in a popover.
private struct DocumentErrataChip: View {
  let items: [ErrataSummary.Item]
  @State private var isShown = false

  var body: some View {
    Button {
      isShown = true
    } label: {
      Label {
        Text(verbatim: ErrataMarks.label(for: items))
      } icon: {
        Image(systemName: "exclamationmark.bubble")
      }
    }
    .buttonStyle(.borderless)
    .help("The errata that name no section")
    .popover(isPresented: $isShown) {
      ErrataList(items: items)
        .frame(width: ErrataList.width)
        .frame(maxHeight: ErrataList.maximumHeight)
    }
  }
}
