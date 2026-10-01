#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// ⌘=, the second way to View ▸ Bigger (#153). The menu shows ⌘+, but on a US
  /// keyboard "+" takes Shift, so ⌘= is the chord people press, as they do in
  /// Safari and Preview. A menu item holds one key equivalent, and SwiftUI leaves a
  /// hidden one out of the menu altogether, key equivalent and all -- measured -- so
  /// the reader window answers ⌘= itself, as it answers ⌘K.
  public enum BiggerShortcut {
    /// Whether a key press is ⌘=: Command and no other modifier that makes it a
    /// different shortcut. Caps Lock and the function key are ignored, as AppKit's
    /// own key equivalents ignore them. ⌘⇧= arrives as "+", which the menu item
    /// answers.
    public static func matches(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
      let significant = modifiers.intersection([.command, .shift, .option, .control])
      return significant == .command && characters == "="
    }
  }
#endif
