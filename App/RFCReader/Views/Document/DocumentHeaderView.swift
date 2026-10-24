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
    /// What the header says of a draft (#728), nil for an RFC.
    let draft: DraftStatus?
    /// The draft an RFC was, which it can be compared with (#729).
    let precedingDraft: DraftID?
    /// What the text below is compared with, and whether its redline is built yet.
    let comparison: Comparison?
    /// What the header says of a translation (#749), nil for the English.
    let translation: TranslationMark?
    /// The errata naming no section the document has (#387), which the chip by the
    /// date lists.
    let documentErrata: [ErrataSummary.Item]

    /// Merged by `HeaderSummary`, which a printed page's title block reads too.
    init(
      header: DocumentHeader, metadata: RFCMetadata?, revisions: RevisionsSummary? = nil,
      draft: DraftStatus? = nil, comparison: Comparison? = nil,
      translation: TranslationMark? = nil,
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
      self.draft = draft
      precedingDraft = draft == nil ? header.precedingDraft.flatMap(DraftLink.init(url:))?.id : nil
      self.comparison = comparison
      self.translation = translation
      self.documentErrata = documentErrata
    }
  }

  /// What the reader compares the document with (#729).
  struct Comparison: Equatable {
    let older: ReadableDocument
    /// Whether the redline is on screen, rather than still being worked out.
    let isShown: Bool
    /// Whether the older document failed to load, and nothing is coming.
    let failed: Bool
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
      if let draft = identity.draft {
        DraftBanner(status: draft)
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
        #if os(macOS)
          if !identity.documentErrata.isEmpty {
            DocumentErrataChip(items: identity.documentErrata)
          }
        #endif
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      #if !os(macOS)
        // A line of its own: beside the rest it wraps on an iPhone in portrait.
        if !identity.documentErrata.isEmpty {
          DocumentErrataChip(items: identity.documentErrata)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      #endif
      if !identity.authors.isEmpty {
        AuthorChips(authors: identity.authors)
          .font(.subheadline)
      }
      if let comparison = identity.comparison {
        ComparisonNotice(comparison: comparison)
          .padding(.top, 4)
      } else if let precedingDraft = identity.precedingDraft {
        PrecedingDraftComparison(draft: precedingDraft)
      }
      if let translation = identity.translation {
        TranslationNotice(mark: translation)
          .padding(.top, 4)
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

/// That the text below is an Internet-Draft, not an RFC (#728): which revision it
/// is, with a menu of the others, and where the draft has gone since, a newer
/// revision or the RFC it became, which a button opens.
private struct DraftBanner: View {
  /// Hosted outside the SwiftUI hierarchy, by a host that `ReaderEnvironment`
  /// guarantees gave it the environment.
  @Environment(LibraryModel.self) private var library
  @Environment(NavigationModel.self) private var navigation
  @Environment(ReaderState.self) private var reader
  let status: DraftStatus

  var body: some View {
    WrappingRowLayout(spacing: 8) {
      Label {
        Text(verbatim: status.mark)
      } icon: {
        Image(systemName: "doc.badge.clock")
      }
      .fontWeight(.medium)
      Menu {
        ForEach(status.choices) { choice in
          Button {
            open(choice.draft)
          } label: {
            if let date = choice.date {
              Text(verbatim: "\(choice.label) · \(date)")
            } else {
              Text(verbatim: choice.label)
            }
          }
          .disabled(choice.isShown)
        }
      } label: {
        Text(verbatim: status.revisionLabel)
      }
      .menuStyle(.button)
      .buttonStyle(.borderless)
      .fixedSize()
      .accessibilityLabel(Text("Revision"))
      .accessibilityValue(Text(verbatim: status.revisionLabel))
      if !status.olderChoices.isEmpty {
        Menu {
          ForEach(status.olderChoices) { choice in
            Button {
              reader.comparedWith = .draft(choice.draft)
            } label: {
              Text(verbatim: choice.label)
            }
          }
        } label: {
          Text("Show Changes")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
      }
      if let notice = status.notice {
        if let rfc = status.publishedAs {
          Button {
            library.open(rfc, activation: .current, in: navigation, arrival: .citation)
          } label: {
            Text(verbatim: notice)
          }
          .buttonStyle(.borderless)
        } else if let newer = status.newer {
          Button {
            open(newer)
          } label: {
            Text(verbatim: notice)
          }
          .buttonStyle(.borderless)
        } else {
          Text(verbatim: notice)
        }
      }
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }

  /// Another revision of the draft, in this tab, as a link followed in the reader.
  private func open(_ draft: DraftID) {
    library.open(
      .draft(DraftLink(id: draft)), activation: .current, in: navigation, arrival: .citation)
  }
}

/// That the text below marks what changed since an older document (#729), with the
/// way back to the text alone beside it.
private struct ComparisonNotice: View {
  /// Hosted outside the SwiftUI hierarchy, by a host that `ReaderEnvironment`
  /// guarantees gave it the environment.
  @Environment(ReaderState.self) private var reader
  let comparison: DocumentHeaderView.Comparison

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "arrow.left.arrow.right")
      if comparison.failed {
        Text("Couldn't load \(comparison.older.displayName) to compare")
      } else {
        Text("Changes since \(comparison.older.displayName)")
      }
      if !comparison.isShown, !comparison.failed {
        ProgressView()
          .controlSize(.small)
      }
      Button("Hide Changes") { reader.comparedWith = nil }
        .buttonStyle(.borderless)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }
}

/// An RFC's offer to mark what changed since the draft it was (#729).
private struct PrecedingDraftComparison: View {
  @Environment(ReaderState.self) private var reader
  let draft: DraftID

  var body: some View {
    Button {
      reader.comparedWith = .draft(draft)
    } label: {
      Label("Show Changes Since \(draft.displayName)", systemImage: "arrow.left.arrow.right")
    }
    .buttonStyle(.borderless)
    .font(.subheadline)
  }
}

/// That the text below is a machine's translation, not the RFC (#749), for as long
/// as it is shown, with the way back to the English beside it.
private struct TranslationNotice: View {
  /// Hosted outside the SwiftUI hierarchy, by a host that `ReaderEnvironment`
  /// guarantees gave it the environment.
  @Environment(ReaderState.self) private var reader
  let mark: TranslationMark

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "translate")
      switch mark {
      case .translating(let progress):
        Text("Translating…")
        ProgressView(value: progress)
          .frame(maxWidth: 120)
      case .translated:
        Text("Machine-translated from English")
      case .failed:
        Text("Couldn't translate this document")
      }
      Button("Show Original") { reader.showTranslation = false }
        .buttonStyle(.borderless)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }
}

/// The whole document's errata (#387), those naming no section it has: a chip by the
/// date on macOS, and on a line of its own under it on iOS, worded as a heading's is,
/// which lists them in a popover on macOS, and in a sheet the scene presents on iOS,
/// where the header cannot present (`GlossaryPresentation`).
private struct DocumentErrataChip: View {
  let items: [ErrataSummary.Item]
  @Environment(NavigationModel.self) private var navigation
  @State private var isShown = false

  var body: some View {
    Button {
      #if os(iOS)
        navigation.errataShown = ErrataRequest(items: items)
      #else
        isShown = true
      #endif
    } label: {
      Label {
        Text(verbatim: ErrataMarks.label(for: items))
      } icon: {
        Image(systemName: "exclamationmark.bubble")
      }
    }
    .buttonStyle(.borderless)
    .help("The errata not marked on any section")
    .popover(isPresented: $isShown) {
      ErrataList(items: items)
    }
  }
}
