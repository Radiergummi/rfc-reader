import RFCKit
import RFCReaderKit
import SwiftUI

#if !os(macOS)
  /// What a list row offers beyond a tap (#348): a leading swipe to bookmark it, and
  /// a context menu previewing its abstract, as Notes previews a note.
  struct RowActions: ViewModifier {
    let rfc: RFCMetadata
    let isBookmarked: Bool
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
              isBookmarked ? "Remove Bookmark" : "Bookmark",
              systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
          }
          .tint(.accentColor)
          Button {
            isChoosingCollection = true
          } label: {
            Label("Add to Collection", systemImage: "folder.badge.plus")
          }
          .tint(.indigo)
        }
        .sheet(isPresented: $isChoosingCollection) {
          guard wantsNewCollection else { return }
          wantsNewCollection = false
          navigation.collectionEditor = .create(adding: rfc.id)
        } content: {
          AddToCollectionSheet(document: rfc.id) { wantsNewCollection = true }
        }
        .contextMenu {
          Button(action: toggleBookmark) {
            Label(
              isBookmarked ? "Remove Bookmark" : "Bookmark",
              systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
          }
          Menu("Add to Collection") {
            AddToCollectionItems(
              document: rfc.id, library: library, navigation: navigation,
              undoManager: undoManager)
          }
          ShareLink(
            item: RFCEditorEndpoints.infoPage(rfc.id),
            subject: Text("\(rfc.id.displayName): \(rfc.title)"))
          if library.opensNewWindows {
            Button {
              library.openWindow(for: rfc.id)
            } label: {
              Label("Open in New Window", systemImage: "macwindow.badge.plus")
            }
          }
        } preview: {
          preview
        }
    }

    private var preview: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(rfc.id.displayName)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(rfc.title).font(.headline)
        if let abstract = rfc.abstract {
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
      library.toggleBookmark(rfc.id)
    }
  }
#endif
