import Foundation
import Testing

@testable import RFCReaderKit

/// The reader's keys (#711): what a key press in the reader's text does, a small
/// state machine so that `gg`, `]]` and a `g` left too long are pinned here.
@Suite("Reader keys")
struct ReaderKeysTests {
  private static let standard = ReaderKeys.Options(vimKeys: false, tabsThroughLinks: true)
  private static let vim = ReaderKeys.Options(vimKeys: true, tabsThroughLinks: true)

  /// The outcomes of `keys` pressed one after another, a tenth of a second apart.
  private static func outcomes(
    _ keys: [ReaderKeys.Key], options: ReaderKeys.Options = vim, focusesLink: Bool = false
  ) -> [ReaderKeys.Outcome] {
    var machine = ReaderKeys()
    return keys.enumerated().map { step, key in
      machine.press(key, at: Double(step) / 10, options: options, focusesLink: focusesLink)
    }
  }

  @Test func `space pages down and shift-space up, whatever the options`() {
    for options in [Self.standard, Self.vim] {
      #expect(Self.outcomes([.space], options: options) == [.command(.scroll(.pageDown))])
      #expect(Self.outcomes([.shiftSpace], options: options) == [.command(.scroll(.pageUp))])
    }
  }

  @Test func `tab moves through links unless that is turned off`() {
    #expect(Self.outcomes([.tab], options: Self.standard) == [.command(.link(.next))])
    #expect(Self.outcomes([.shiftTab], options: Self.standard) == [.command(.link(.previous))])
    let off = ReaderKeys.Options(vimKeys: false, tabsThroughLinks: false)
    #expect(Self.outcomes([.tab, .shiftTab], options: off) == [.unhandled, .unhandled])
  }

  @Test func `a focused link is followed with return, previewed with space and left with escape`() {
    #expect(
      Self.outcomes([.returnKey, .space, .escape], focusesLink: true) == [
        .command(.followLink), .command(.previewLink), .command(.leaveLink),
      ])
    #expect(Self.outcomes([.returnKey, .escape]) == [.unhandled, .unhandled])
    // Shift-space still pages up: only space is the link's.
    #expect(Self.outcomes([.shiftSpace], focusesLink: true) == [.command(.scroll(.pageUp))])
  }

  @Test func `without vim keys a letter is the text view's`() {
    let letters = "jkdugG/nN][".map(ReaderKeys.Key.character)
    #expect(
      Self.outcomes(letters, options: Self.standard)
        == Array(repeating: .unhandled, count: letters.count))
  }

  @Test(arguments: [
    (ReaderKeys.Key.character("j"), ReaderKeyCommand.scroll(.lineDown)),
    (.character("k"), .scroll(.lineUp)),
    (.character("d"), .scroll(.halfPageDown)),
    (.character("u"), .scroll(.halfPageUp)),
    (.character("G"), .end),
    (.character("/"), .find),
    (.character("n"), .findNext),
    (.character("N"), .findPrevious),
  ])
  func `a vim key is its command at once`(_ key: ReaderKeys.Key, _ command: ReaderKeyCommand) {
    #expect(Self.outcomes([key]) == [.command(command)])
  }

  @Test(arguments: [
    ("g", "g", ReaderKeyCommand.top),
    ("]", "]", .section(.next)),
    ("[", "[", .section(.previous)),
    ("]", "r", .link(.next)),
    ("[", "r", .link(.previous)),
  ])
  func `a vim pair is its command on its second key`(
    _ first: Character, _ second: Character, _ command: ReaderKeyCommand
  ) {
    #expect(
      Self.outcomes([.character(first), .character(second)]) == [.pending, .command(command)])
  }

  @Test func `a first key left too long starts again`() {
    var machine = ReaderKeys()
    #expect(
      machine.press(.character("g"), at: 0, options: Self.vim, focusesLink: false) == .pending)
    #expect(
      machine.press(
        .character("g"), at: ReaderKeys.pairTimeout + 0.1, options: Self.vim, focusesLink: false)
        == .pending)
    #expect(
      machine.press(
        .character("g"), at: ReaderKeys.pairTimeout + 0.2, options: Self.vim, focusesLink: false)
        == .command(.top))
  }

  /// A key that makes no pair with the first is taken as itself.
  @Test func `a key that makes no pair is its own`() {
    #expect(
      Self.outcomes([.character("g"), .character("j")]) == [.pending, .command(.scroll(.lineDown))])
    #expect(Self.outcomes([.character("]"), .character("[")]) == [.pending, .pending])
    #expect(Self.outcomes([.character("]"), .character("x")]) == [.pending, .unhandled])
    #expect(Self.outcomes([.character("g"), .space]) == [.pending, .command(.scroll(.pageDown))])
  }

  @Test func `a page keeps a line of the one before, a half page is half the viewport`() {
    #expect(ReaderKeyCommand.Scroll.pageDown.distance(viewport: 600, line: 20) == 580)
    #expect(ReaderKeyCommand.Scroll.pageUp.distance(viewport: 600, line: 20) == -580)
    #expect(ReaderKeyCommand.Scroll.halfPageDown.distance(viewport: 600, line: 20) == 300)
    #expect(ReaderKeyCommand.Scroll.halfPageUp.distance(viewport: 600, line: 20) == -300)
    #expect(ReaderKeyCommand.Scroll.lineDown.distance(viewport: 600, line: 20) == 20)
    #expect(ReaderKeyCommand.Scroll.lineUp.distance(viewport: 600, line: 20) == -20)
  }

  /// A viewport of no more than two lines pages a whole viewport, or a page would
  /// move a line or nothing at all.
  @Test func `a viewport of two lines or less pages whole`() {
    #expect(ReaderKeyCommand.Scroll.pageDown.distance(viewport: 40, line: 20) == 40)
    #expect(ReaderKeyCommand.Scroll.pageUp.distance(viewport: 30, line: 20) == -30)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// What AppKit hands the reader's text view, read as the reader's keys.
  @Suite("Reader keys on the Mac")
  struct MacReaderKeysTests {
    @Test func `a key press is read as the reader's key`() {
      #expect(ReaderKeys.Key(characters: " ", modifiers: []) == .space)
      #expect(ReaderKeys.Key(characters: " ", modifiers: .shift) == .shiftSpace)
      #expect(ReaderKeys.Key(characters: "\t", modifiers: []) == .tab)
      #expect(ReaderKeys.Key(characters: "\u{19}", modifiers: .shift) == .shiftTab)
      #expect(ReaderKeys.Key(characters: "\r", modifiers: []) == .returnKey)
      #expect(ReaderKeys.Key(characters: "\u{1B}", modifiers: []) == .escape)
      #expect(ReaderKeys.Key(characters: "G", modifiers: .shift) == .character("G"))
      // Caps Lock and the function key, which an arrow carries, change nothing.
      #expect(ReaderKeys.Key(characters: "j", modifiers: .capsLock) == .character("j"))
    }

    @Test func `a chord with command, control or option is not the reader's`() {
      for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
        #expect(ReaderKeys.Key(characters: "j", modifiers: modifier) == nil)
      }
      #expect(ReaderKeys.Key(characters: nil, modifiers: []) == nil)
      #expect(ReaderKeys.Key(characters: "", modifiers: []) == nil)
    }
  }
#elseif canImport(UIKit)
  import UIKit

  /// What UIKit hands the reader's text view, read as the reader's keys.
  @Suite("Reader keys on iOS")
  struct IOSReaderKeysTests {
    @Test func `a key press is read as the reader's key`() {
      #expect(ReaderKeys.Key(keyCode: .keyboardSpacebar, characters: " ", modifiers: []) == .space)
      #expect(
        ReaderKeys.Key(keyCode: .keyboardSpacebar, characters: " ", modifiers: .shift)
          == .shiftSpace)
      #expect(
        ReaderKeys.Key(keyCode: .keyboardTab, characters: "\t", modifiers: .shift) == .shiftTab)
      #expect(
        ReaderKeys.Key(keyCode: .keyboardReturnOrEnter, characters: "\r", modifiers: [])
          == .returnKey)
      #expect(ReaderKeys.Key(keyCode: .keyboardEscape, characters: "", modifiers: []) == .escape)
      #expect(
        ReaderKeys.Key(keyCode: .keyboardG, characters: "G", modifiers: .shift) == .character("G"))
    }

    @Test func `a chord with command, control or option is not the reader's`() {
      for modifier: UIKeyModifierFlags in [.command, .control, .alternate] {
        #expect(ReaderKeys.Key(keyCode: .keyboardJ, characters: "j", modifiers: modifier) == nil)
      }
    }
  }
#endif
