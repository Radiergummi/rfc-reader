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

  @AppStorage("readingFontSize") private var fontSize = 17.0
  @AppStorage("underlineLinks") private var underlineLinks = false
  /// The reader follows Dynamic Type (#331), so the preview of it does too.
  @Environment(\.dynamicTypeSize) private var textSize
  /// The reader's own preference, so the preview's build and its text view agree
  /// on the column, as `DocumentView` and the reader's do (#32).
  @AppStorage("readerMeasure") private var measure = MeasurePreference.recommended
  @State private var loaded: Loaded?
  @State private var failure: String?
  @State private var scrollTarget: ReaderScrollTarget?
  @State private var lastVisibleAnchor = VisibleAnchorBox()
  @State private var heading = HeadingBox()

  private struct Loaded {
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
        measure: measure,
        documentID: id,
        commitsOnClick: commit,
        lastVisibleAnchor: lastVisibleAnchor,
        scrollTarget: scrollTarget,
        onScrollHandled: { scrollTarget = nil },
        onVisibleAnchorChange: { _ in },
        onLink: { _, _ in true },
        onToolbarTitle: { _ in },
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

  /// Fetched if it is not cached, the way the reader fetches it, and built at the
  /// preview's own column.
  private func load() async {
    do {
      let document = try await library.document(for: id)
      let column = ReaderLayout.column(forWidth: size.width, measure: measure)
      let built = await DocumentView.build(
        document,
        style: ReadingStyle(
          bodySize: fontSize, measure: column, underlinesLinks: underlineLinks,
          textSize: textSize))
      loaded = Loaded(
        document: document, built: built, bibliography: ReferenceGroup.groups(in: document))
      // Resolved the way the reader resolves a jump, so the preview opens where a
      // click on the reference goes.
      if let place {
        scrollTarget = ReaderScrollTarget(
          anchor: document.anchor(forPlace: place), animated: false)
      }
    } catch {
      failure = error.localizedDescription
    }
  }
}
