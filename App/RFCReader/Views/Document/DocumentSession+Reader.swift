import RFCKit
import RFCReaderKit
import SwiftUI
import os

/// What a session puts into the window's reader state, and the build, which the view
/// used to do itself (#599): the view lays the reader out and wires it, and asks the
/// session for the rest.
///
/// Every closure here captures what it writes to — the reader state, the library,
/// the navigation — and never the view or the session, for the reason `startLoad`
/// gives. And none writes once its document is no longer the one selected: a
/// replaced reader lives on through its fade (`ReaderHost`), and must not write its
/// document's details over the next one's.
extension DocumentSession {
  /// Fetches the document, with the reader's panel made ready for it first.
  ///
  /// Once per view, plus Try Again after a failure: the view is made per document
  /// (`.id(selection)`), and appearing again keeps what it loaded.
  func open(
    into reader: ReaderState, library: LibraryModel, navigation: NavigationModel,
    positions: ReadingPositionKeeper, showsOriginal: Bool
  ) {
    // The scene's `ReaderState` must not carry the previous document's place into
    // this one; `install()` reports the real anchor a moment later.
    reader.clear()
    reader.showOriginal = showsOriginal
    reader.isLoading = true
    // Its header is on its way until the reader reports, so the title stays out of
    // the toolbar rather than showing and then dropping (#281).
    reader.documentStartsLoading()
    markPublishedOriginal(into: reader, library: library, navigation: navigation)
    // Before the fetch, not after: the index knows the document before its body
    // arrives, so the tab is ready the moment the panel is.
    deriveInfo(into: reader, library: library, navigation: navigation)
    // A scan has no text to fetch (#207): its page is the index's. Nor has a pointer
    // the pack lists (#316), whose XML it left out.
    let pointerInPack = library.pointersInPack.contains(id)
    guard
      PublishedOriginalPage.loadsText(
        id, formats: library.metadata(id)?.formats, pointerInPack: pointerInPack)
    else {
      skipLoad()
      reader.isLoading = false
      // Recorded as a loaded text would be: Recently Read lists a scan, and a
      // pointer with a pack or without. Here, so once per opening, like a load's.
      positions.markOpened()
      Task(name: "Mark opened") { [library, id] in await library.markOpened(id) }
      return
    }
    startLoad(from: library) { [reader, library, navigation, positions, id] loaded in
      guard navigation.selection == id else { return }
      reader.groups = ReferenceGroup.groups(in: loaded)
      reader.info = Self.info(for: id, authors: loaded.header.authors, in: library)
      // Here rather than on appearing: once per opening, since each is a view of
      // its own (`.id(selection)`) and a collapsed split view's spurious
      // disappear and appear is not another one (#260). And only once the
      // document is here, so one that failed to open is not listed as read.
      positions.markOpened()
      reader.documentTitle = loaded.header.title
      reader.precedingDraft = loaded.header.precedingDraft
      reader.hasDocument = true
      reader.publishedOriginal = Self.publishedOriginal(id, text: loaded, in: library)
      // Last and apart, so the first build does not wait for it.
      Task(name: "Extract requirements") { [reader, navigation, id] in
        let requirements = await Self.requirements(in: loaded)
        guard navigation.selection == id else { return }
        reader.requirements = requirements
      }
      Task(name: "Find a grammar to export") { [reader, navigation, id] in
        let formats = await Self.exportFormats(for: loaded)
        guard navigation.selection == id else { return }
        reader.exportFormats = formats
      }
    } failed: { [reader, navigation, id] in
      // No header is coming, so the toolbar names the RFC that failed; unless it is
      // a scan (`publishedOriginal`), whose page shows the header.
      guard navigation.selection == id else { return }
      reader.documentFailedToLoad()
      // A jump waiting for the text is not coming.
      if let request = navigation.scrollRequest { navigation.settle(request) }
    }
  }

  /// Why this RFC is read as its original, if it is (#207): as the load starts, and
  /// again when the index loads, which may be after the fetch ended.
  func markPublishedOriginal(
    into reader: ReaderState, library: LibraryModel, navigation: NavigationModel
  ) {
    guard navigation.selection == id else { return }
    reader.publishedOriginal = Self.publishedOriginal(id, text: state.document, in: library)
  }

  /// What the Info pane shows. Again whenever the index loads or refreshes: a document
  /// opened before the index finished loading has none to show until it does. And
  /// again once the document is here, whose own authors carry the contact details
  /// their chips open.
  func deriveInfo(into reader: ReaderState, library: LibraryModel, navigation: NavigationModel) {
    guard navigation.selection == id else { return }
    reader.info = Self.info(for: id, authors: state.document?.header.authors, in: library)
  }

  private static func publishedOriginal(
    _ id: DocumentID, text document: RFCDocument?, in library: LibraryModel
  ) -> PublishedOriginalPage.Status? {
    library.metadata(id).flatMap {
      PublishedOriginalPage.Status(
        id, formats: $0.formats, text: document,
        pointerInPack: library.pointersInPack.contains(id))
    }
  }

  private static func info(
    for id: DocumentID, authors: [Author]?, in library: LibraryModel
  ) -> DocumentInfo? {
    library.metadata(id).map {
      DocumentInfo(
        $0, authors: authors, in: library.index,
        revisions: library.revisionsSummary(for: $0.id))
    }
  }

  /// The formats the document can be saved as, off the main actor: finding a grammar
  /// parses every block that may be one.
  @concurrent
  private static func exportFormats(for document: RFCDocument) async -> [ExportFormat] {
    ExportFormat.available(for: document)
  }

  /// The Requirements tab's rows (#180), off the main actor: every sentence of the
  /// document is split and read for key words.
  @concurrent
  private static func requirements(in document: RFCDocument) async -> [Requirement] {
    Requirements.extract(from: document)
  }

  /// Off the main actor, and structured: unlike a detached task, it inherits the
  /// caller's priority and its cancellation (#129). The builder never checks for
  /// cancellation, so a build that has started runs to the end; `requestBuild` is
  /// what discards a canceled one. `DocumentPreview` builds through it too.
  @concurrent
  static func built(
    _ document: RFCDocument, style: ReadingStyle, choices: PresentationChoices = .defaults
  ) async -> BuiltDocument {
    let name = document.header.id?.displayName ?? "untitled"
    return signposter.withIntervalSignpost(
      "Build document", id: signposter.makeSignpostID(), "\(name, privacy: .public)"
    ) {
      DocumentTextBuilder.build(document, style: style, choices: choices)
    }
  }
}
