#if os(macOS)
  import AppKit
#endif

#if os(macOS)
  /// One find-bar action, sent to the first responder that can perform it.
  ///
  /// `performTextFinderAction(_:)` decides *which* action it is by reading `tag` off
  /// its sender, which is why the sender is this tiny object rather than nil: the
  /// selector alone carries no way to say "show the bar" versus "find next".
  final class FindCommand: NSObject {
    static let showFindInterface = FindCommand(.showFindInterface)
    static let nextMatch = FindCommand(.nextMatch)
    static let previousMatch = FindCommand(.previousMatch)
    /// Use Selection for Find (#761), which `NSTextView` already performs.
    static let setSearchString = FindCommand(.setSearchString)

    @objc let tag: Int

    private init(_ action: NSTextFinder.Action) {
      self.tag = action.rawValue
    }

    func send() {
      ActiveReaderWindow.shared.controller?.focusSearchableText()
      NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: self)
    }

    /// Jump to Selection (#761): not a find-bar action but the responder's own, as
    /// AppKit's standard Edit ▸ Find menu sends it.
    static func jumpToSelection() {
      ActiveReaderWindow.shared.controller?.focusSearchableText()
      NSApp.sendAction(#selector(NSResponder.centerSelectionInVisibleArea(_:)), to: nil, from: nil)
    }
  }
#endif
