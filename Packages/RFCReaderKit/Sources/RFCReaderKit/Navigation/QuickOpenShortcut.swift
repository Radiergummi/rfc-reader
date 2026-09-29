#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// ⌘K, the second way to the Go to RFC palette. ⌘L is the menu's, where Safari
  /// puts its own field; ⌘K is where most apps with a palette put theirs. A menu item
  /// holds one key equivalent, so the menu shows ⌘L and the reader window answers
  /// ⌘K itself.
  public enum QuickOpenShortcut {
    /// Whether a key press is ⌘K: Command and no other modifier that makes it a
    /// different shortcut. Caps Lock and the function key are ignored, as AppKit's
    /// own key equivalents ignore them.
    public static func matches(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
      let significant = modifiers.intersection([.command, .shift, .option, .control])
      return significant == .command && characters?.lowercased() == "k"
    }
  }
#endif
