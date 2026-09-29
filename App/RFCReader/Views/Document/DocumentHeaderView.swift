import RFCKit
import RFCReaderKit
import SwiftUI

/// Everything above the first line of prose: title, badges, authors, and the status
/// banner. Hosted in the text view's top content inset, so it scrolls with the body
/// without being part of it — the banner carries buttons, and nobody selects through
/// it. The abstract is no longer here; it is the first prose in the storage, which is
/// what puts the banner between the title and the abstract as `VISION.md` asks.
struct DocumentHeaderView: View {
  /// Passed down for the same reason `StatusBanner` takes them: this whole subtree
  /// is hosted outside the SwiftUI hierarchy.
  let library: LibraryModel
  let navigation: NavigationModel

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

    /// Merged by `HeaderSummary`, which a printed page's title block reads too.
    init(header: DocumentHeader, metadata: RFCMetadata?, revisions: RevisionsSummary? = nil) {
      let summary = HeaderSummary(header: header, metadata: metadata)
      title = summary.title
      date = summary.date
      workingGroup = summary.workingGroup
      authors = summary.authors
      self.metadata = metadata
      revisionLines = revisions?.bannerLines ?? []
      moreRevisions = revisions?.moreText
    }
  }

  /// The view renders from the identity rather than beside it, so the two cannot
  /// describe different headers.
  let identity: Identity

  /// Where the heading ends, for the toolbar's copy of the title to take over from
  /// as it scrolls away; see `ToolbarTitleReveal`.
  let heading: HeadingBox

  nonisolated static let coordinateSpace = "documentHeader"

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(identity.title)
        .font(.largeTitle.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
          $0.frame(in: .named(Self.coordinateSpace)).maxY
        } action: { bottom in
          heading.bottom = bottom
        }
      HStack(spacing: 8) {
        if let metadata = identity.metadata {
          StatusBadge(status: metadata.currentStatus)
          Text(metadata.stream.displayName)
        }
        if let date = identity.date {
          Text(date)
        }
        if let group = identity.workingGroup {
          Text(group)
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
          library: library, navigation: navigation, metadata: metadata,
          revisionLines: identity.revisionLines, moreRevisions: identity.moreRevisions
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
