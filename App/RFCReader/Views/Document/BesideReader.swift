import RFCKit
import RFCReaderKit
import SwiftUI

/// The reader opened beside the window's own, scrolling with it (#187).
///
/// It is read under `reading`'s own navigation and reader state, which whoever hosts
/// it applies: the macOS window hands its split item's hosted root the four models,
/// and iPad's detail column applies them around this view. The window's own reader
/// state is `main`, which the comparison belongs to and which closes it.
struct BesideReader: View {
  let reading: SideBySide
  let main: ReaderState
  let mainNavigation: NavigationModel
  @Environment(LibraryModel.self) private var library

  var body: some View {
    DocumentView(id: reading.pair.other, isBeside: true)
      .id(reading.pair.other)
      .overlay(alignment: .bottom) {
        BesideBar(reading: reading, close: main.endComparison)
          .padding(.bottom, 16)
      }
      // A link followed to another document leaves the comparison: the document
      // opens in the window's reader, as from a reader read alone.
      .onChange(of: reading.navigation.selection) { _, selection in
        guard let selection, selection != reading.pair.other else { return }
        main.endComparison()
        mainNavigation.open(
          selection, section: reading.navigation.scrollRequest?.section, in: library.index)
      }
      #if os(iOS)
        // Its header's glossary terms, which the window's `readerScene` presents only
        // for the window's own navigation; see `GlossaryPresentation`.
        .sheet(item: Bindable(reading.navigation).glossaryTerm) { term in
          GlossarySheet(term: term)
        }
      #endif
  }
}

/// What the two readers are doing, and the way out.
private struct BesideBar: View {
  let reading: SideBySide
  let close: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(reading.pair.status(reading.alignment, holdingStill: reading.holdsStill))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Button("Close", systemImage: "xmark", action: close)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Read \(reading.pair.reading.displayName) alone")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .glassEffect(.regular, in: .capsule)
  }
}

#if !os(macOS)
  extension SideBySide {
    /// Whether a document can be read beside another here: on iPad beside other
    /// columns, where each reader still has a column's width. Not on iPhone, nor
    /// in an iPad's compact width.
    static func isOffered(in sizeClass: UserInterfaceSizeClass?) -> Bool {
      UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
    }
  }
#endif

/// Compare with each document a reading can be compared with, or Stop Comparing
/// while one is (#187): in View on the Mac, in More on iPad.
struct CompareItems: View {
  let id: DocumentID
  let library: LibraryModel
  let reader: ReaderState

  var body: some View {
    if let beside = reader.sideBySide {
      Button("Stop Comparing with \(beside.pair.other.displayName)") {
        reader.endComparison()
      }
    } else if let metadata = library.metadata(id) {
      let offered = SideBySidePair.offered(for: metadata)
      if !offered.isEmpty {
        Menu("Compare Side by Side", systemImage: "rectangle.split.2x1") {
          ForEach(offered, id: \.self) { other in
            Button(other.displayName) {
              reader.compare(metadata, with: other, library: library)
            }
          }
        }
      }
    }
  }
}
