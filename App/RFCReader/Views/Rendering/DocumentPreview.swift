import RFCKit
import RFCReaderKit
import SwiftUI

/// The document a reference names, as a force click (macOS) or a long press (iOS)
/// previews it: Safari's link preview, for RFCs (#29).
///
/// A reader of its own, not a picture of one — its own `RFCTextView`, its own text
/// storage built by `DocumentTextBuilder` at the preview's width — so it reads and
/// scrolls like the reader does, opened at the place the reference names. Links
/// inside it are not followed: a click anywhere in it is the commit, which `commit`
/// turns into opening that place in the reader underneath. On iOS a context menu's
/// preview takes no touches, and UIKit's tap on it is the commit instead. The
/// reader's own body stays one text storage; this lives beside it, in a popover on
/// macOS and a context menu on iOS.
struct DocumentPreview: View {
  let library: LibraryModel
  let id: DocumentID
  /// A section number or an anchor, or nil for the top.
  let place: String?
  /// Fixed while the preview is up: the document is built at its column.
  var size = LinkPreview.documentSize
  let commit: () -> Void

  /// The reader's own settings, so the preview is set as the reader is, and its
  /// build and its text view agree on the column, as `DocumentView` and the
  /// reader's do (#32).
  @ReaderSettingsValue private var settings
  /// The reader follows Dynamic Type (#331), so the preview of it does too.
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var loaded: Loaded?
  @State private var failure: String?
  @State private var scrollTarget: ReaderScrollTarget?
  @State private var lastVisibleAnchor = VisibleAnchorBox()
  @State private var heading = HeadingBox()

  /// Everything a preview shows, kept whole by `LibraryModel.previews` so the
  /// build is never paired with another parse of its document.
  struct Loaded {
    let document: RFCDocument
    let built: BuiltDocument
    /// What a citation of a bibliography entry in the preview previews (#198).
    let bibliography: [ReferenceGroup]
  }

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: size.width, height: size.height)
    .task { await load() }
  }

  /// What is being previewed, above the text: the reader's own header would name
  /// it too, but only while the preview sits at the top of the document.
  private var titleBar: some View {
    HStack(spacing: 8) {
      Text(id.displayName)
        .fontWeight(.semibold)
      if let title = library.metadata(id)?.title {
        Text(title)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var content: some View {
    if let loaded {
      RFCTextView(
        built: loaded.built,
        bibliography: loaded.bibliography,
        measure: settings.measure,
        documentID: id,
        commitsOnClick: commit,
        lastVisibleAnchor: lastVisibleAnchor,
        scrollTarget: scrollTarget,
        onScrollHandled: { scrollTarget = nil },
        onVisibleAnchorChange: { _ in },
        onLink: { _, _ in true },
        onToolbarTitle: { _, _ in },
        onToolbarTitleReleased: { _ in },
        heading: heading,
        headerIdentity: DocumentHeaderView.Identity(
          header: loaded.document.header, metadata: library.metadata(id)),
        header: { EmptyView() }
      )
    } else if let failure {
      ContentUnavailableView(
        "Couldn’t Load \(id.displayName)", systemImage: "exclamationmark.triangle",
        description: Text(failure))
    } else {
      ProgressView()
    }
  }

  /// What a preview of the same document in the same style kept (#374), or else
  /// fetched if it is not cached, the way the reader fetches it, and built at the
  /// preview's own column.
  private func load() async {
    let column = ReaderLayout.column(forWidth: size.width, measure: settings.measure)
    let style = settings.style(column: column, textSize: textSize)
    let key = BuildKey(document: id, style: style)
    do {
      let kept = library.keptPreview(for: key)
      let shown: Loaded
      if let kept {
        shown = kept
      } else {
        let document = try await library.document(for: id)
        shown = Loaded(
          document: document, built: await DocumentSession.built(document, style: style),
          bibliography: ReferenceGroup.groups(in: document))
      }
      loaded = shown
      // Resolved the way the reader resolves a jump, so the preview opens where a
      // click on the reference goes.
      if let place {
        scrollTarget = ReaderScrollTarget(anchor: shown.document.anchor(forPlace: place))
      }
      // After the text is shown: asking whether the document is still downloaded
      // waits for the store, which may be parsing another document.
      if kept == nil {
        await library.keep(shown, for: key)
      }
    } catch {
      failure = error.localizedDescription
    }
  }
}
