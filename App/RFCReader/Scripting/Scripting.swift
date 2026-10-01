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

  extension AppDelegate {
    /// The application's elements that live here rather than on `NSApplication`.
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
      key == "rfcs" || key == "orderedWindows"
    }

    /// The application's `windows`, less any reader window that has closed but is
    /// still alive (#432). Closing empties such a window, so a script would see an
    /// invisible window that answers nothing. Open means still registered here, not
    /// still having a controller: a print or export under way keeps the controller
    /// of a window that has closed.
    @objc var orderedWindows: [NSWindow] {
      NSApp.orderedWindows.filter { window in
        !(window is ReaderWindow) || controllers.contains { $0.window === window }
      }
    }

    /// Every RFC, for `every rfc`. `count of rfcs` and `rfc 5` go through the two
    /// indexed accessors below instead, which build one object or none rather than
    /// all 9,842.
    @objc var rfcs: [ScriptableRFC] {
      LibraryModel.shared.index?.rfcs.map { ScriptableRFC($0.id) } ?? []
    }

    @objc func countOfRfcs() -> Int {
      LibraryModel.shared.index?.rfcs.count ?? 0
    }

    @objc(objectInRfcsAtIndex:)
    func objectInRfcs(at index: Int) -> ScriptableRFC? {
      LibraryModel.shared.index.map { ScriptableRFC($0.rfcs[index].id) }
    }

    /// `rfc id 9110`, looked up by number rather than found by walking `rfcs`.
    @objc(valueInRfcsWithUniqueID:)
    func valueInRfcs(withUniqueID uniqueID: Any) -> ScriptableRFC? {
      guard let number = (uniqueID as? NSNumber)?.intValue,
        LibraryModel.shared.index?[number] != nil
      else { return nil }
      return ScriptableRFC(.rfc(number))
    }
  }

  /// A reader window's properties. Every window and tab is a `ReaderWindow`; a script
  /// asking one of these of any other window — the settings — gets an error.
  extension ReaderWindow {
    private var controller: ReaderWindowController? {
      ReaderWindowController.controller(for: self)
    }

    @objc var scriptCurrentRFC: ScriptableRFC? {
      controller?.navigation.selection.map(ScriptableRFC.init)
    }

    @objc var scriptCurrentSection: String? {
      controller?.reader.currentSection
    }

    @objc var scriptCollection: String {
      get { controller.map { LibraryModel.shared.title(for: $0.navigation.filter) } ?? "" }
      set {
        let library = LibraryModel.shared
        let groups = Set(library.index?.rfcs.compactMap(\.workingGroup) ?? [])
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
      return navigation.rowsNow().map { ScriptableRFC($0.id) }
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

    /// An enumeration's value crosses as its four-character code.
    @objc var scriptInspectorPane: FourCharCode {
      get {
        guard let reader = controller?.reader else { return ScriptCode.contents }
        if reader.pane == .info { return ScriptCode.info }
        switch reader.tab {
        case .contents: return ScriptCode.contents
        case .references: return ScriptCode.references
        case .requirements: return ScriptCode.requirements
        }
      }
      set {
        guard let reader = controller?.reader else { return }
        switch newValue {
        case ScriptCode.info:
          reader.pane = .info
        case ScriptCode.references:
          reader.pane = .navigation
          reader.tab = .references
        case ScriptCode.requirements:
          reader.pane = .navigation
          reader.tab = .requirements
        default:
          reader.pane = .navigation
          reader.tab = .contents
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
        switch code {
        case ScriptCode.newTab: .newTab
        case ScriptCode.newWindow: .newWindow
        default: .frontTab
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
      window.navigation.jump(toSection: section) {
        command.resumeExecution(withResult: nil)
      }
    }
  }

  /// The dictionary's enumerators, as the four-character codes Apple events carry.
  enum ScriptCode {
    static let contents = code("RIpC")
    static let references = code("RIpR")
    static let requirements = code("RIpQ")
    static let info = code("RIpI")
    static let newTab = code("RPnT")
    static let newWindow = code("RPnW")

    private static func code(_ string: String) -> FourCharCode {
      string.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
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
