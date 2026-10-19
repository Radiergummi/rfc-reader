#if os(macOS)
  import AppKit
  import RFCKit
  import RFCReaderKit

  // The objects and commands `RFCReader.sdef` names, by the Cocoa class and key each
  // entry there gives. None of them decides anything: they translate between Apple
  // events and the models the menus and toolbar already drive, and what needs
  // deciding — which collection a name means, which document a reference names —
  // is in `RFCReaderKit`, where it is tested.
  //
  // They reach `LibraryModel.shared` because AppKit's scripting bridge makes them,
  // and has no way to hand them the library.

  /// An RFC as a script sees it, named by its number: `rfc id 9110`.
  @objc(ScriptableRFC)
  final class ScriptableRFC: NSObject {
    let id: DocumentID

    init(_ id: DocumentID) {
      self.id = id
    }

    private var metadata: RFCMetadata? {
      LibraryModel.shared.metadata(id)
    }

    @objc var number: Int { id.number }
    @objc var name: String { id.displayName }
    @objc var title: String? { metadata?.title }
    @objc var status: String? { metadata?.currentStatus.displayName }
    @objc var year: Int { metadata?.date.year ?? 0 }
    @objc var workingGroup: String? { metadata?.workingGroup }
    @objc var isObsolete: Bool { metadata?.isObsolete ?? false }

    @objc var isBookmarked: Bool {
      get { LibraryModel.shared.bookmarkedDocuments.contains(id) }
      set {
        // Applied, as the window applies it, but not kept: a script is told, rather
        // than seeing a success that is gone at the next launch (#318). Told when
        // the value is already the one asked for as well: in memory, a bookmark that
        // is already there was made this session, and is no more kept than a new one.
        if AppData.isStoredInMemory {
          ScriptError.report(AppData.storeWarning.message)
        }
        guard newValue != isBookmarked else { return }
        LibraryModel.shared.toggleBookmark(id)
      }
    }

    /// The Keep Offline mark (#358). Setting it saves the mark before it returns, and
    /// a download it starts goes on after; the store being in memory is reported as
    /// a bookmark's is.
    @objc var isKeptOffline: Bool {
      get { LibraryModel.shared.offlineMarks.contains(id) }
      set {
        if AppData.isStoredInMemory {
          ScriptError.report(AppData.storeWarning.message)
        }
        guard newValue != isKeptOffline else { return }
        LibraryModel.shared.setKeptOfflineInBackground(id, newValue)
      }
    }

    /// Where the object lives, which is how a script gets a reference it can use
    /// again: the application's `rfcs`, by number.
    nonisolated override var objectSpecifier: NSScriptObjectSpecifier? {
      guard let application = NSScriptClassDescription(for: NSApplication.self) else { return nil }
      return NSUniqueIDSpecifier(
        containerClassDescription: application,
        containerSpecifier: nil,
        key: "rfcs",
        uniqueID: NSNumber(value: id.number)
      )
    }
  }

  /// A collection the reader made, as a script sees it (#355), named by its
  /// identifier. `make new collection` builds one with `init()`, sets the properties
  /// it was given, and only then inserts it, which is when it is made in the store:
  /// until then it holds what it was given.
  @objc(ScriptableCollection)
  final class ScriptableCollection: NSObject {
    /// Nil until `make` has inserted it.
    fileprivate(set) var identifier: UUID?
    fileprivate var givenName: String?
    fileprivate var givenQuery: String?

    override init() {}

    init(_ identifier: UUID) {
      self.identifier = identifier
    }

    private var entry: CollectionSnapshot.Entry? {
      identifier.flatMap { LibraryModel.shared.collections[$0] }
    }

    @objc var uniqueID: String { identifier?.uuidString ?? "" }

    @objc var name: String {
      get { entry?.name ?? givenName ?? "" }
      set {
        guard let entry else {
          givenName = newValue
          return
        }
        guard CollectionStore.isValidName(newValue) else {
          ScriptError.report("A collection's name can't be empty.")
          return
        }
        let saved = LibraryModel.shared.editCollections {
          try CollectionStore.update(entry.id, name: newValue, color: entry.color, in: $0)
        }
        if !saved { ScriptError.report("The collection's name could not be saved.") }
      }
    }

    @objc var query: String? {
      get { identifier == nil ? givenQuery : entry?.query }
      set {
        guard let entry else {
          givenQuery = newValue
          return
        }
        // A collection's kind is fixed when it is made: its RFCs are chosen, or a
        // query's.
        guard entry.isDynamic else {
          ScriptError.report("“\(entry.name)” holds RFCs chosen one by one, not a query.")
          return
        }
        if let refusal = Self.refusal(of: newValue) {
          ScriptError.report(refusal)
          return
        }
        let saved = LibraryModel.shared.editCollections {
          try CollectionStore.update(
            entry.id, name: entry.name, color: entry.color, query: newValue, in: $0)
        }
        if !saved { ScriptError.report("The collection's query could not be saved.") }
      }
    }

    /// Why the store would refuse `query` for a collection made from one, in a
    /// script's words; nil when it takes it.
    static func refusal(of query: String?) -> String? {
      guard let query, !query.isUnsearchedQuery else {
        return "A collection's query can't be empty."
      }
      guard CollectionStore.isValidQuery(query) else {
        return "A collection's query can't name a section: its list shows RFCs, not sections."
      }
      return nil
    }

    /// The application's `scriptCollections`, by identifier.
    nonisolated override var objectSpecifier: NSScriptObjectSpecifier? {
      guard let application = NSScriptClassDescription(for: NSApplication.self) else { return nil }
      let uniqueID = MainActor.assumeIsolated { self.uniqueID }
      return NSUniqueIDSpecifier(
        containerClassDescription: application,
        containerSpecifier: nil,
        key: "scriptCollections",
        uniqueID: uniqueID
      )
    }
  }

  extension AppDelegate {
    /// The application's elements that live here rather than on `NSApplication`.
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
      key == "rfcs" || key == "orderedWindows" || key == "scriptCollections"
    }

    /// Every collection, in the sidebar's order.
    @objc var scriptCollections: [ScriptableCollection] {
      LibraryModel.shared.collections.collections.map { ScriptableCollection($0.id) }
    }

    @objc(valueInScriptCollectionsWithUniqueID:)
    func valueInScriptCollections(withUniqueID uniqueID: Any) -> ScriptableCollection? {
      guard let string = uniqueID as? String, let identifier = UUID(uuidString: string),
        LibraryModel.shared.collections[identifier] != nil
      else { return nil }
      return ScriptableCollection(identifier)
    }

    /// `make new collection`: made in the store from what it was given, at the end
    /// of the sidebar, as New Collection makes one. With a query it is made from
    /// that query; named, if it was given no name, by its query.
    @objc(insertInScriptCollections:)
    func insertInScriptCollections(_ collection: ScriptableCollection) {
      if AppData.isStoredInMemory {
        ScriptError.report(AppData.storeWarning.message)
      }
      let query = collection.givenQuery
      let name = collection.givenName ?? query ?? ""
      guard CollectionStore.isValidName(name) else {
        ScriptError.report("A collection needs a name, or a query to be named by.")
        return
      }
      if query != nil, let refusal = ScriptableCollection.refusal(of: query) {
        ScriptError.report(refusal)
        return
      }
      let saved = LibraryModel.shared.editCollections {
        collection.identifier = try CollectionStore.create(
          named: name, color: .default, query: query, in: $0
        ).identifier
      }
      if !saved { ScriptError.report("The collection could not be made.") }
    }

    @objc(insertObject:inScriptCollectionsAtIndex:)
    func insert(_ collection: ScriptableCollection, inScriptCollectionsAt index: Int) {
      insertInScriptCollections(collection)
    }

    /// The application's `windows`, less any reader window that has closed but is
    /// still alive (#432). Closing empties such a window, so a script would see an
    /// invisible window that answers nothing. Open means still registered here, not
    /// still alive: a print or export under way keeps a window that has closed.
    @objc var orderedWindows: [NSWindow] {
      NSApp.orderedWindows.filter { window in
        !(window is ReaderWindow) || controllers.contains { $0.window === window }
      }
    }

    /// Every RFC, for `every rfc`. `count of rfcs` and `rfc 5` go through the two
    /// indexed accessors below instead, which build one object or none rather than
    /// all 9,842.
    @objc var rfcs: [ScriptableRFC] {
      Self.settledIndex?.rfcs.map { ScriptableRFC($0.id) } ?? []
    }

    @objc func countOfRfcs() -> Int {
      Self.settledIndex?.rfcs.count ?? 0
    }

    @objc(objectInRfcsAtIndex:)
    func objectInRfcs(at index: Int) -> ScriptableRFC? {
      Self.settledIndex.map { ScriptableRFC($0.rfcs[index].id) }
    }

    /// The index once it has loaded or failed to, for a script (#762). A script that
    /// launched the app asks before the index has loaded, and found no RFCs at all;
    /// the intents wait for it with `settledSearch()`. An object accessor cannot
    /// suspend its Apple event, so it turns the run loop until the index settles,
    /// which lets the main actor's load run, until `indexDeadline`.
    ///
    /// Turning the run loop inside an accessor lets other main-actor work run in the
    /// middle of it, a link routed or a window made, so nothing here holds on to model
    /// state across the wait: each accessor reads the index once it is back.
    static var settledIndex: RFCIndex? {
      let library = LibraryModel.shared
      let deadline = indexDeadline
      while !library.hasIndexSettled, Date.now < deadline {
        RunLoop.current.run(mode: .default, before: min(deadline, .now.addingTimeInterval(0.05)))
      }
      return library.index
    }

    /// Until when scripts wait for the index before they find none: 30 s from the
    /// first that asked, longer than a launch takes to read the cached index, short of
    /// an Apple event's default timeout of two minutes. One deadline for the process,
    /// so a script's every command does not wait 30 s again for an index that is not
    /// coming. Lazy, as a static `let` is.
    private static let indexDeadline = Date.now.addingTimeInterval(30)

    /// `rfc id 9110`, looked up by number rather than found by walking `rfcs`.
    @objc(valueInRfcsWithUniqueID:)
    func valueInRfcs(withUniqueID uniqueID: Any) -> ScriptableRFC? {
      guard let number = (uniqueID as? NSNumber)?.intValue,
        Self.settledIndex?[number] != nil
      else { return nil }
      return ScriptableRFC(.rfc(number))
    }
  }

  /// A reader window's properties. Every window and tab is a `ReaderWindow`; a script
  /// asking one of these of any other window — the settings, or the primer — gets an
  /// error.
  extension ReaderWindow {
    private var controller: ReaderWindowController? {
      ReaderWindowController.controller(for: self)
    }

    /// The RFC on screen: a BCP, STD or FYI's first member, as its reader shows it
    /// (#656). A script's RFC is named by its number, so a series is never one.
    @objc var scriptCurrentRFC: ScriptableRFC? {
      guard let shown = controller?.navigation.shown, shown.series == .rfc else { return nil }
      return ScriptableRFC(shown)
    }

    @objc var scriptCurrentSection: String? {
      controller?.reader.currentSection
    }

    @objc var scriptCollection: String {
      get {
        // In English, whatever the interface's language: the names a script sets a
        // filter by are (LibraryFilter(scriptName:)).
        controller.map {
          $0.navigation.filter.title(in: LibraryModel.shared.collections, locale: .english)
        } ?? ""
      }
      set {
        let library = LibraryModel.shared
        // Once the index has settled, or a working group's name is not yet one.
        let groups = Set(AppDelegate.settledIndex?.rfcs.compactMap(\.workingGroup) ?? [])
        guard
          let filter = LibraryFilter(
            scriptName: newValue, workingGroups: groups,
            collections: library.collections.collections)
        else {
          ScriptError.report("There is no collection named “\(newValue)”.")
          return
        }
        controller?.navigation.sidebarSelection = filter
      }
    }

    @objc var scriptSearchText: String {
      get { controller?.navigation.searchText ?? "" }
      // A script reads the list straight after setting the text.
      set { controller?.navigation.setSearchTextSynchronously(newValue) }
    }

    @objc var scriptListedRFCs: [ScriptableRFC] {
      guard let navigation = controller?.navigation else { return [] }
      // Not the rows on show: the script may have changed the collection a moment
      // ago, and they follow a turn later.
      // RFCs only: an `rfc` element is specified by its number, so a series row
      // listed as one would be taken for the RFC of its number (#152, #321).
      return navigation.rowsNow().compactMap(\.rfc).map { ScriptableRFC($0.id) }
    }

    @objc var scriptInspectorVisible: Bool {
      get { controller?.isPanelOpen ?? false }
      set {
        if controller?.setPanelOpen(newValue) == false {
          ScriptError.report("The inspector can only be shown over an RFC.")
        }
      }
    }

    /// A command told to this window rather than to the application — `tell front
    /// window to go back`. The command already knows its window from its receiver,
    /// so this only runs it.
    @objc(handleReaderCommand:)
    func handleReaderCommand(_ command: NSScriptCommand) -> Any? {
      command.performDefaultImplementation()
    }

    /// An enumeration's value crosses as its four-character code (`ScriptPane`).
    @objc var scriptInspectorPane: FourCharCode {
      get {
        guard let reader = controller?.reader else { return ScriptPane.contents.code }
        if reader.pane == .info { return ScriptPane.information.code }
        // A switch rather than names matched, so a tab added or renamed is a
        // compile error here, not a pane a script quietly cannot reach.
        let pane: ScriptPane =
          switch reader.tab {
          case .contents: .contents
          case .references: .references
          case .requirements: .requirements
          case .annotations: .annotations
          }
        return pane.code
      }
      set {
        guard let reader = controller?.reader else { return }
        let pane = ScriptPane(code: newValue) ?? .contents
        reader.pane = pane.pane
        switch pane {
        case .contents: reader.tab = .contents
        case .references: reader.tab = .references
        case .requirements: reader.tab = .requirements
        case .annotations: reader.tab = .annotations
        case .information: break
        }
      }
    }
  }

  /// Every command in the dictionary: run on the main actor, against the window it
  /// names or the front one.
  ///
  /// The classes are `nonisolated` and their members `@MainActor`, not the other way
  /// round: under the target's main-actor default, the initializers inherited from
  /// `NSScriptCommand` would become main-actor isolated, which the compiler rejects
  /// as overrides of nonisolated ones.
  nonisolated class RFCScriptCommand: NSScriptCommand {
    /// Cocoa Scripting's entry point, which Swift sees as nonisolated. It is only
    /// ever called on the main thread, and `assumeIsolated` traps rather than races
    /// if that changes; the command itself only crosses to where it already is.
    override func performDefaultImplementation() -> Any? {
      nonisolated(unsafe) let command = self
      MainActor.assumeIsolated { command.perform() }
      return nil
    }

    @MainActor func perform() {
      preconditionFailure("\(type(of: self)) must override perform()")
    }

    @MainActor var targetWindow: ReaderWindowController? {
      let named = (evaluatedReceivers as? NSWindow) ?? (evaluatedArguments?["window"] as? NSWindow)
      return named.flatMap(ReaderWindowController.controller(for:))
        ?? AppDelegate.shared?.activeController
    }
  }

  /// `open rfc 9110 at section "4.2" placement new tab`.
  @objc(RFCOpenCommand)
  nonisolated final class RFCOpenCommand: RFCScriptCommand {
    @MainActor override func perform() {
      let reference =
        (directParameter as? String) ?? (directParameter as? NSNumber)?.stringValue ?? ""
      let section = evaluatedArguments?["section"] as? String
      guard let link = DocumentReference.link(from: reference, section: section) else {
        ScriptError.report("“\(reference)” names no RFC.", in: self)
        return
      }
      let code = (evaluatedArguments?["placement"] as? NSNumber)?.uint32Value
      let placement: LibraryModel.Placement =
        switch code.flatMap(ScriptPlacement.init(code:)) {
        case .newTab: .newTab
        case .newWindow: .newWindow
        case .frontTab, nil: .frontTab
        }
      LibraryModel.shared.open(link, placement: placement)
    }
  }

  @objc(RFCGoBackCommand)
  nonisolated final class RFCGoBackCommand: RFCScriptCommand {
    @MainActor override func perform() {
      targetWindow?.navigation.goBack()
    }
  }

  @objc(RFCGoForwardCommand)
  nonisolated final class RFCGoForwardCommand: RFCScriptCommand {
    @MainActor override func perform() {
      targetWindow?.navigation.goForward()
    }
  }

  /// `jump to section "4.2"`: resolved against the document the window shows, the
  /// way a section link in the prose is, by number or by anchor.
  ///
  /// The reader resolves it, in a later update, so the command waits for it: a
  /// script's next command, such as `go back`, finds the jump in the history (#482).
  @objc(RFCJumpToSectionCommand)
  nonisolated final class RFCJumpToSectionCommand: RFCScriptCommand {
    @MainActor override func perform() {
      guard let section = directParameter as? String, !section.isEmpty else {
        ScriptError.report("Which section?", in: self)
        return
      }
      guard let window = targetWindow, window.navigation.selection != nil else {
        ScriptError.report("There is no RFC to jump in.", in: self)
        return
      }
      suspendExecution()
      nonisolated(unsafe) let command = self
      // A place the document does not hold is an error to the script, in words,
      // as the scripting decision asks, not a jump that went nowhere (#762).
      window.navigation.jump(toSection: section) { outcome in
        switch outcome {
        case .landed:
          break
        case .noSuchPlace:
          ScriptError.report("The RFC has no section “\(section)”.", in: command)
        case .notShown:
          ScriptError.report("The RFC could not be shown to jump in.", in: command)
        case .interrupted:
          ScriptError.report(
            "The jump to section “\(section)” was interrupted before it was made.", in: command)
        }
        command.resumeExecution(withResult: nil)
      }
    }
  }

  /// `export rfc id 9110 as PDF to file "…"` (#383): the file File > Export… writes,
  /// made by the same `DocumentExport`, without opening a window. The command waits
  /// for it, so a script's next line finds the file written.
  @objc(RFCExportCommand)
  nonisolated final class RFCExportCommand: RFCScriptCommand {
    @MainActor override func perform() {
      let specifier = directParameter as? NSScriptObjectSpecifier
      guard let rfc = specifier?.objectsByEvaluatingSpecifier as? ScriptableRFC else {
        ScriptError.report("Which RFC? Name one as rfc id 9110.", in: self)
        return
      }
      let code = (evaluatedArguments?["format"] as? NSNumber)?.uint32Value
      guard let format = code.flatMap(ExportFormat.init(scriptCode:)) else {
        ScriptError.report(
          "Which format? Export as PDF, EPUB, HTML, Markdown, plain text, XML or ABNF.", in: self)
        return
      }
      guard let file = evaluatedArguments?["file"] as? URL, file.isFileURL else {
        ScriptError.report("Where to? Export to a file.", in: self)
        return
      }
      let id = rfc.id
      suspendExecution()
      nonisolated(unsafe) let command = self
      Task {
        do {
          let data = try await DocumentExport.data(
            for: id, as: format, paperSize: NSPrintInfo.shared.paperSize,
            library: LibraryModel.shared)
          try data.write(to: file, options: .atomic)
        } catch let error as CocoaError where format == .abnf && error.code == .fileWriteUnknown {
          // What `DocumentExport` throws for a grammar the RFC does not have, which
          // the menus never offer.
          ScriptError.report("\(id.displayName) has no grammar to export as ABNF.", in: command)
        } catch {
          ScriptError.report(
            "\(id.displayName) could not be exported as \(format.scriptName): \(error.localizedDescription)",
            in: command)
        }
        command.resumeExecution(withResult: nil)
      }
    }
  }

  /// A failure the script sees as an error, with our words rather than a generic one.
  enum ScriptError {
    /// `command` defaults to the one being executed, which is the only way a
    /// property's setter can reach it.
    static func report(
      _ message: String,
      in command: NSScriptCommand? = NSScriptCommand.current()
    ) {
      command?.scriptErrorNumber = Int(errAEEventFailed)
      command?.scriptErrorString = message
    }
  }
#endif
