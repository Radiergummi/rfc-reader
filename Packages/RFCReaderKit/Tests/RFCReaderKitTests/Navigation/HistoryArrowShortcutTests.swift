#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import Testing

  @testable import RFCReaderKit

  /// ⌘← and ⌘→ go back and forward only where they would not move a caret (#761):
  /// the menu's Back and Forward are ⌘[ and ⌘], and a text field keeps its arrows.
  @Suite("History arrow shortcut")
  struct HistoryArrowShortcutTests {
    private let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    private let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    /// What AppKit sets on an arrow key's event besides Command.
    private let arrow: NSEvent.ModifierFlags = [.command, .numericPad, .function]

    @Test func `command arrows go back and forward outside a text field`() {
      #expect(
        HistoryArrowShortcut.step(characters: left, modifiers: arrow, inText: false) == .back)
      #expect(
        HistoryArrowShortcut.step(characters: right, modifiers: arrow, inText: false) == .forward)
    }

    /// Search Library and Go to RFC keep ⌘← and ⌘→ for the start and end of a line.
    @Test func `a text field keeps its command arrows`() {
      #expect(HistoryArrowShortcut.step(characters: left, modifiers: arrow, inText: true) == nil)
      #expect(HistoryArrowShortcut.step(characters: right, modifiers: arrow, inText: true) == nil)
    }

    /// ⇧⌘← selects to the start of a line, ⌥⌘← is another shortcut, and a bare
    /// arrow moves the caret: none is a step through history.
    @Test func `other modifiers and other keys are not a step`() {
      #expect(
        HistoryArrowShortcut.step(
          characters: left, modifiers: arrow.union(.shift), inText: false) == nil)
      #expect(
        HistoryArrowShortcut.step(
          characters: left, modifiers: arrow.union(.option), inText: false) == nil)
      #expect(
        HistoryArrowShortcut.step(
          characters: left, modifiers: [.numericPad, .function], inText: false)
          == nil)
      #expect(HistoryArrowShortcut.step(characters: "[", modifiers: .command, inText: false) == nil)
    }
  }
#endif
