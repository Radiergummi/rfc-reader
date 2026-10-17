import RFCKit
import RFCReaderKit
import SwiftUI

#if !os(macOS)
  /// What a list row offers beyond a tap (#348): a leading swipe to bookmark it, and
  /// a context menu previewing its abstract, as Notes previews a note.
  ///
  /// A series row is bookmarked and opened as itself, but not added to a collection
  /// or shared (#321): a collection holds RFCs.
  struct RowActions: ViewModifier {
    let row: LibraryRow
    let isBookmarked: Bool

    private var rfc: RFCMetadata? { row.rfc }
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.undoManager) private var undoManager
    /// The Add to Collection sheet a swipe opens, which cannot open a menu (#349).
    @State private var isChoosingCollection = false
    /// New Collection was chosen on that sheet: asked for once the sheet is gone.
    @State private var wantsNewCollection = false

    func body(content: Content) -> some View {
      content
        .swipeActions(edge: .leading) {
          Button(action: toggleBookmark) {
            Label(
              DocumentActions.bookmarkCommand(isBookmarked: isBookmarked),
              systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
          }
          .tint(.accentColor)
          if rfc != nil {
            Button {
              isChoosingCollection = true
            } label: {
              Label("Add to Collection", systemImage: "folder.badge.plus")
            }
            .tint(.indigo)
          }
        }
        .sheet(isPresented: $isChoosingCollection) {
          guard wantsNewCollection else { return }
          wantsNewCollection = false
          navigation.collectionEditor = .create(adding: row.id)
        } content: {
          AddToCollectionSheet(document: row.id) { wantsNewCollection = true }
        }
        .contextMenu {
          // `DocumentMenus.rowActions`, the table the Mac's menu renders too (#761).
          let sections = DocumentMenus.rowActions(
            isRFC: rfc != nil, opensTabs: false, opensWindows: library.opensNewWindows,
            inCollection: false)
          DividedSections(sections: sections, item: item)
        } preview: {
          preview
        }
    }

    @ViewBuilder
    private func item(_ action: DocumentMenus.RowAction) -> some View {
      switch action {
      case .openInNewWindow:
        Button {
          library.openWindow(for: row.id)
        } label: {
          Label("Open in New Window", systemImage: "macwindow.badge.plus")
        }
      case .bookmark:
        Button(action: toggleBookmark) {
          Label(
            DocumentActions.bookmarkCommand(isBookmarked: isBookmarked),
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
        }
      case .addToCollection:
        Menu("Add to Collection") {
          AddToCollectionItems(
            document: row.id, library: library, navigation: navigation,
            undoManager: undoManager)
        }
      case .readingPath:
        Button {
          navigation.readingPath = ReadingPathRequest(root: row.id)
        } label: {
          Label("Reading Path", systemImage: "list.number")
        }
      case .keepOffline:
        KeepOfflineButton(document: row.id, library: library)
      case .share:
        ShareLink(
          item: RFCEditorEndpoints.infoPage(row.id),
          subject: Text(verbatim: "\(row.id.displayName): \(row.title)"))
      // iOS opens no tabs, and its lists are not a collection's to remove from here.
      case .openInNewTab, .removeFromCollection:
        EmptyView()
      }
    }

    private var preview: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(row.id.displayName)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(row.title).font(.headline)
        if let memberList = row.memberList {
          Text(memberList).font(.callout).foregroundStyle(.secondary)
        }
        if let abstract = rfc?.abstract {
          Text(abstract)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(12)
        }
      }
      .typesettingLanguage(.init(identifier: "en"))
      .padding()
      .frame(width: 340, alignment: .leading)
    }

    private func toggleBookmark() {
      library.toggleBookmark(row.id)
    }
  }
#endif
