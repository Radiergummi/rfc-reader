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
/// turns into opening that place in the reader underneath. The reader's own body
/// stays one text storage; this lives in a popover beside it.
struct DocumentPreview: View {
  let library: LibraryModel
  let id: DocumentID
  /// A section number or an anchor, or nil for the top.
  let place: String?
  let commit: () -> Void

  static let size = CGSize(width: 560, height: 620)

  @AppStorage("readingFontSize") private var fontSize = 17.0
  @State private var loaded: Loaded?
  @State private var failure: String?
  @State private var scrollTarget: ReaderScrollTarget?
  @State private var lastVisibleAnchor = VisibleAnchorBox()
  @State private var heading = HeadingBox()

  private struct Loaded {
    let document: RFCDocument
    let built: BuiltDocument
  }

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: Self.size.width, height: Self.size.height)
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
      let column = ReaderLayout.column(forWidth: Self.size.width)
      let built = await Self.build(
        document, style: ReadingStyle(bodySize: fontSize, measure: column))
      loaded = Loaded(document: document, built: built)
      // Resolved the way the reader resolves a jump: a section number, or else an
      // anchor as it stands.
      if let place {
        let anchor =
          (document.section(number: place) ?? document.section(anchor: place))?.anchor ?? place
        scrollTarget = ReaderScrollTarget(anchor: anchor, animated: false)
      }
    } catch {
      failure = error.localizedDescription
    }
  }

  @concurrent
  private static func build(_ document: RFCDocument, style: ReadingStyle) async -> BuiltDocument {
    DocumentTextBuilder.build(document, style: style)
  }
}
