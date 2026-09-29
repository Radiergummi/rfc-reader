#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import Testing

  @testable import RFCReaderKit

  /// ⌘K opens the palette as ⌘L does, since that is where most apps with one put it.
  @Suite("Quick open shortcut")
  struct QuickOpenShortcutTests {
    @Test func `command K opens the palette`() {
      #expect(QuickOpenShortcut.matches(characters: "k", modifiers: .command))
    }

    /// Caps Lock and the function key are not a different shortcut: a key pressed
    /// with Caps Lock on is still ⌘K.
    @Test func `caps lock and the function key do not change the shortcut`() {
      #expect(QuickOpenShortcut.matches(characters: "k", modifiers: [.command, .capsLock]))
      #expect(QuickOpenShortcut.matches(characters: "k", modifiers: [.command, .function]))
    }

    /// ⇧⌘K, ⌥⌘K and ⌃⌘K are other shortcuts, and K alone is typing.
    @Test func `another modifier or none is not the shortcut`() {
      #expect(!QuickOpenShortcut.matches(characters: "k", modifiers: [.command, .shift]))
      #expect(!QuickOpenShortcut.matches(characters: "k", modifiers: [.command, .option]))
      #expect(!QuickOpenShortcut.matches(characters: "k", modifiers: [.command, .control]))
      #expect(!QuickOpenShortcut.matches(characters: "k", modifiers: []))
      #expect(!QuickOpenShortcut.matches(characters: "j", modifiers: .command))
      #expect(!QuickOpenShortcut.matches(characters: nil, modifiers: .command))
    }
  }
#endif
