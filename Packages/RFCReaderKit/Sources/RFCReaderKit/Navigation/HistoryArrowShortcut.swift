#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// ⌘← and ⌘→, the second way to Back and Forward (#761). The menu's items are ⌘[
  /// and ⌘], as Safari's and Finder's are: AppKit offers a key to the main menu
  /// before the field editor, so menu items on the arrows took the start and end of
  /// a line away from every text field. The reader window answers the arrows itself
  /// instead, and only where the first responder is not text, as it answers ⌘K.
  public enum HistoryArrowShortcut {
    public enum Step: Sendable, Equatable {
      case back
      case forward
    }

    /// The step a key press is: ⌘← or ⌘→, with Command and no other modifier that
    /// makes it a different shortcut, outside text. Nil for anything else.
    /// `inText` is whether the first responder is text, a field or the reader's own
    /// text view, whose caret the arrows move.
    public static func step(
      characters: String?, modifiers: NSEvent.ModifierFlags, inText: Bool
    ) -> Step? {
      guard !inText else { return nil }
      let significant = modifiers.intersection([.command, .shift, .option, .control])
      guard significant == .command, let scalar = characters?.unicodeScalars.first else {
        return nil
      }
      return switch Int(scalar.value) {
      case NSLeftArrowFunctionKey: .back
      case NSRightArrowFunctionKey: .forward
      default: nil
      }
    }
  }
#endif
