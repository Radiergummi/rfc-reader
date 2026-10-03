#if !os(macOS)
  import RFCKit
  import RFCReaderKit
  import SwiftUI

  /// The reader's chrome on iOS (#601): its title in the bar, the toolbar, the bars
  /// put away while reading on, the return offer, the panel as a column or a sheet,
  /// and Save to Files. On the Mac all of it is the window's (`ReaderWindowController`).
  struct IOSDocumentChrome: ViewModifier {
    let id: DocumentID
    let metadata: RFCMetadata?
    /// What the return offer names its place in.
    let document: RFCDocument?
    let library: LibraryModel
    let navigation: NavigationModel
    let reader: ReaderState
    @Binding var showsInspector: Bool
    @Binding var barsHidden: Bool
    let output: DocumentOutput
    /// Whether the window's reader state is this reader's; see `DocumentTitle`.
    let isShown: Bool

    @Environment(\.sceneChrome) private var chrome
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// Whether the panel is a sheet over the reader rather than a column beside it.
    private var isCompact: Bool { chrome.isCollapsed }

    func body(content: Content) -> some View {
      content
        .navigationBarTitleDisplayMode(.inline)
        // The designation over what it is called, in the bar once the header has
        // scrolled away. The navigation title stays, for the back button and the
        // app switcher.
        .toolbar {
          ToolbarItem(placement: .principal) {
            DocumentTitle(
              title: id.displayName,
              subtitle: DocumentActions.subtitle(
                metadata: metadata, documentTitle: isShown ? reader.documentTitle : nil) ?? "",
              reader: reader, isShown: isShown)
          }
        }
        .toolbar {
          DocumentToolbar(
            id: id, metadata: metadata, library: library, navigation: navigation,
            reader: reader, isBookmarked: library.bookmarkedDocuments.contains(id),
            showsInspector: $showsInspector,
            exportDocument: { output.exportDocument(id, as: $0, library: library) },
            printDocument: {
              output.printDocument(
                id, original: reader.showOriginal,
                title: reader.documentTitle ?? metadata?.title, library: library)
            },
            showsBottomBar: !barsHidden)
        }
        // The top bar, which leaves the status bar; the bottom one goes by losing
        // its items (`DocumentToolbar.showsBottomBar`). The reader runs under both,
        // so neither moves it.
        .toolbarVisibility(barsHidden ? .hidden : .automatic, for: .navigationBar)
        // The original text has no reader to bring them back with a tap, and the
        // reader made afresh on the way back starts with them showing.
        .onChange(of: reader.showOriginal) { barsHidden = false }
        // An overlay rather than an inset: it floats over the text and takes no
        // layout, so it cannot disturb the column, which is derived from this
        // view's frame.
        .overlay(alignment: .bottom) {
          returnButton.animation(.snappy, value: visibleReturn)
        }
        // Long enough to decide, without sitting over the text for good. Not under
        // VoiceOver, where a control that leaves on a timer may be gone before it
        // is reached: there it stays until the next navigation replaces it.
        .task(id: visibleReturn) {
          guard visibleReturn != nil, !voiceOverEnabled else { return }
          try? await Task.sleep(for: .seconds(8))
          guard !Task.isCancelled else { return }
          navigation.settleReturnOffer()
        }
        // iOS keeps the inspector as a column beside the reader where there is
        // room for one. In compact width it is a sheet, and a `.sheet` of our own
        // rather than the one `.inspector` turns itself into: that one, swiped
        // away, set the binding back to false but dropped the next request to
        // show it, so the panel's buttons opened it only on every other tap.
        //
        // The panel is the stack's, and only the reader on top presents it (#263):
        // the readers below would present it too, out of sight.
        .inspector(isPresented: isCompact || !isShown ? .constant(false) : $showsInspector) {
          PanelHost(isPresented: $showsInspector, closesAfterChoice: false)
            .inspectorColumnWidth(min: 260, ideal: 320)
        }
        .sheet(isPresented: isCompact && isShown ? $showsInspector : .constant(false)) {
          PanelHost(isPresented: $showsInspector, closesAfterChoice: true)
            .presentationDetents([.medium, .large])
        }
        .fileExporter(
          isPresented: Binding(
            get: { output.exported != nil },
            set: { if !$0 { output.finishExport() } }),
          document: output.exported,
          contentType: (output.exported?.format ?? .pdf).contentType,
          defaultFilename: ExportFormat.fileStem(for: id)
        ) { _ in
          output.finishExport()
        }
    }

    /// Where a tap on the return offer goes, while it is on show.
    ///
    /// In a single column only: beside other columns, the back/forward pair is in
    /// the bar.
    private var visibleReturn: HistoryEntry? {
      chrome.isCollapsed ? navigation.returnOffer : nil
    }

    /// "Back to § 4.2" after following a link within the document (#254). In a
    /// single column there is no back/forward pair, and the system back button
    /// leaves the document.
    @ViewBuilder
    private var returnButton: some View {
      if let offer = visibleReturn {
        Button {
          navigation.goBack()
        } label: {
          Label(
            ReturnOffer.title(for: offer, in: document),
            systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.glass)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }
#endif
