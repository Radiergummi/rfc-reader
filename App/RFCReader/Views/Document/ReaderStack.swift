#if !os(macOS)
  import RFCReaderKit
  import SwiftUI

  /// The detail column on iOS (#263): a stack of readers, the root and one pushed
  /// over it for each citation of another RFC followed in a reader. The cited RFC
  /// slides in over the one it was cited from, and the system back button, or a
  /// swipe from the edge, returns to that one where it was left. On an iPhone and on
  /// an iPad beside other columns alike.
  ///
  /// The path is the tab's history, projected (`ReaderPath`), and the stack's own
  /// back is handed to it (`NavigationModel.popReaders(to:)`): the history stays the
  /// one record, which Back and Forward, "Back to §…" and the tab's snapshot all
  /// read. Anything from outside a reader — a row in the list, Go to RFC, a link
  /// from another app — starts the stack again.
  ///
  /// The readers below the top stay, each with its build, so going back costs
  /// nothing; past `ReaderPath.retainedReaders` of them, the deepest are let go and
  /// made again if the stack is popped back to them.
  ///
  /// The Mac has one reader, `ReaderHost`, in a window of its own making.
  struct ReaderStack: View {
    @Environment(NavigationModel.self) private var navigation
    /// The panel, the stack's rather than each reader's, so that an open panel stays
    /// open from one reader to the next.
    @State private var showsInspector = false

    var body: some View {
      let path = navigation.readerPath
      if let root = path.root {
        NavigationStack(path: pushed(in: path)) {
          readerView(root, in: path)
            .navigationDestination(for: ReaderPath.Reader.self) { readerView($0, in: path) }
        }
        // A new root is a new task, not a step back: it replaces the stack without
        // the pop that taking the path away would show.
        .transaction(value: root) { $0.disablesAnimations = true }
      } else {
        EmptyDetailView()
      }
    }

    /// The stack's path, which it shortens by itself only: its back button, or a
    /// swipe from the edge.
    private func pushed(in path: ReaderPath) -> Binding<[ReaderPath.Reader]> {
      Binding {
        path.pushed
      } set: { readers in
        navigation.popReaders(toPushed: readers)
      }
    }

    @ViewBuilder
    private func readerView(_ reader: ReaderPath.Reader, in path: ReaderPath) -> some View {
      if path.retains(reader) {
        DocumentView(id: reader.id, depth: reader.depth, showsInspector: $showsInspector)
          .id(reader)
      } else {
        // Out of sight under the readers kept, and made again if the stack is
        // popped back to it. Its title is what the back button above it says.
        Color.clear
          .navigationTitle(reader.id.displayName)
      }
    }
  }
#endif
