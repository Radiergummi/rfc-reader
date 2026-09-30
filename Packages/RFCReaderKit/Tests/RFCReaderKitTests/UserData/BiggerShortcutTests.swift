#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import Testing

  @testable import RFCReaderKit

  /// ⌘= enlarges the text as View ▸ Bigger's ⌘+ does (#153): on a US keyboard "+"
  /// takes Shift, and ⌘= is the chord people press.
  @Suite("Bigger shortcut")
  struct BiggerShortcutTests {
    @Test func `command equals is bigger`() {
      #expect(BiggerShortcut.matches(characters: "=", modifiers: .command))
    }

    /// Caps Lock and the function key are not a different shortcut.
    @Test func `caps lock and the function key do not change the shortcut`() {
      #expect(BiggerShortcut.matches(characters: "=", modifiers: [.command, .capsLock]))
      #expect(BiggerShortcut.matches(characters: "=", modifiers: [.command, .function]))
    }

    /// ⌘+ is the menu item's own, and another modifier or none is not the shortcut.
    @Test func `anything else is not the shortcut`() {
      #expect(!BiggerShortcut.matches(characters: "+", modifiers: .command))
      #expect(!BiggerShortcut.matches(characters: "=", modifiers: [.command, .option]))
      #expect(!BiggerShortcut.matches(characters: "=", modifiers: [.command, .control]))
      #expect(!BiggerShortcut.matches(characters: "=", modifiers: []))
      #expect(!BiggerShortcut.matches(characters: nil, modifiers: .command))
    }
  }
#endif
