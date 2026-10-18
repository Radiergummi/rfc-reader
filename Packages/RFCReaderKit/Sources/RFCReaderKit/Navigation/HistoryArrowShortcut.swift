#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// ⌘← and ⌘→, the second way to Back and Forward (#761). The menu's items are ⌘[
  /// and ⌘], as Safari's and Finder's are: AppKit offers a key to the main menu
  /// before the field editor, so menu items on the arrows took the start and end of
  /// a line away from every text field. The reader window answers the arrows itself
  /// instead, and only where the first responder is not text being edited, as it
  /// answers ⌘K: the reader's own text, which is not edited, goes back from the arrows
  /// as it did, after a click in it as before one.
  public enum HistoryArrowShortcut {
    public enum Step: Sendable, Equatable {
      case back
      case forward
    }

    /// The step a key press is: ⌘← or ⌘→, with Command and no other modifier that
    /// makes it a different shortcut, outside text being edited. Nil for anything
    /// else. `inText` is whether the first responder is text being edited, a field's
    /// editor, whose caret the arrows move.
    public static func step(
      characters: String?, modifiers: NSEvent.ModifierFlags, inText: Bool
    ) -> Step? {
      guard !inText else { return nil }
      if ReaderShortcut.backArrow.chord(on: .mac)?.matches(
        characters: characters, modifiers: modifiers) == true
      {
        return .back
      }
      if ReaderShortcut.forwardArrow.chord(on: .mac)?.matches(
        characters: characters, modifiers: modifiers) == true
      {
        return .forward
      }
      return nil
    }
  }
#endif
