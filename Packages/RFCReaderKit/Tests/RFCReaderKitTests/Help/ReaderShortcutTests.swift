import Foundation
import RFCReaderKit
import SwiftUI
import Testing

/// The reader's own shortcuts, one list the commands take their key equivalents from
/// and the help renders (#780).
@Suite("Reader shortcuts")
struct ReaderShortcutTests {
  /// Two commands on one chord would leave one of them unreachable, and the help
  /// would list a shortcut that does something else.
  @Test(arguments: ReaderShortcut.Platform.allCases)
  func `no two shortcuts share a chord`(platform: ReaderShortcut.Platform) {
    let chords = ReaderShortcut.allCases.compactMap { $0.chord(on: platform) }
    #expect(Set(chords).count == chords.count)
  }

  @Test(arguments: ReaderShortcut.Platform.allCases)
  func `every shortcut has a title on both platforms, English and German`(
    platform: ReaderShortcut.Platform
  ) {
    for shortcut in ReaderShortcut.allCases where shortcut.chord(on: platform) != nil {
      #expect(!shortcut.title(locale: .english).isEmpty)
      #expect(!shortcut.title(locale: .german).isEmpty)
    }
  }

  /// Every shortcut is listed in the help, under one group or another, and every
  /// group lists something on the Mac.
  @Test func `the help lists every shortcut a platform answers`() {
    for platform in ReaderShortcut.Platform.allCases {
      let listed = ReaderShortcut.Group.allCases.flatMap {
        ReaderShortcut.rows(in: $0, on: platform, locale: .english)
      }
      let chords = ReaderShortcut.allCases.compactMap { $0.chord(on: platform) }
      #expect(Set(listed.flatMap(\.chords)) == Set(chords))
    }
    for group in ReaderShortcut.Group.allCases {
      #expect(!ReaderShortcut.rows(in: group, on: .mac, locale: .english).isEmpty)
    }
  }

  /// A second way to a command is on the same line as the first.
  @Test func `a second chord shares its command's line`() {
    let documents = ReaderShortcut.rows(in: .documents, on: .mac, locale: .english)
    let goTo = documents.first { $0.title == "Go to RFC" }
    #expect(goTo?.chords.map(\.symbols) == ["⌘L", "⌘K"])
    let back = documents.first { $0.title == "Back" }
    #expect(back?.chords.map(\.symbols) == ["⌘[", "⌘←"])
    let view = ReaderShortcut.rows(in: .view, on: .mac, locale: .english)
    #expect(view.first { $0.title == "Bigger Text" }?.chords.map(\.symbols) == ["⌘+", "⌘="])
  }

  /// The iPad's Back is the arrow, and the Mac's menu-only commands are not listed
  /// there.
  @Test func `the iPad lists what it answers`() {
    let documents = ReaderShortcut.rows(in: .documents, on: .iOS, locale: .english)
    #expect(documents.first { $0.title == "Back" }?.chords.map(\.symbols) == ["⌘←"])
    #expect(!documents.contains { $0.title == "Print" })
    #expect(
      ReaderShortcut.rows(in: .windows, on: .iOS, locale: .english).map(\.title) == [
        "RFC Reader Help"
      ])
  }

  /// Next and Previous Section work in every reading mode now (#711), and Go to
  /// Section takes ⌥⌘G on both platforms, as the maintainer chose.
  @Test func `the section commands are listed under View`() {
    for platform in ReaderShortcut.Platform.allCases {
      let view = ReaderShortcut.rows(in: .view, on: platform, locale: .english)
      #expect(view.first { $0.title == "Next Section" }?.chords.map(\.symbols) == ["⌥⌘↓"])
      #expect(view.first { $0.title == "Previous Section" }?.chords.map(\.symbols) == ["⌥⌘↑"])
      #expect(view.first { $0.title == "Go to Section" }?.chords.map(\.symbols) == ["⌥⌘G"])
    }
  }

  /// Written as a menu writes it: ⌃⌥⇧⌘, then the key.
  @Test func `a chord is written in the menu's order`() {
    #expect(ReaderShortcut.copyAsQuote.chord(on: .mac)?.symbols == "⌥⇧⌘C")
    #expect(ReaderShortcut.toggleSidebar.chord(on: .mac)?.symbols == "⌃⌘S")
    #expect(ReaderShortcut.nextSection.chord(on: .mac)?.symbols == "⌥⌘↓")
  }

  /// The commands take these, so the menu shows what the help says. Shortcuts
  /// answered on both platforms, as this runs on either.
  @Test func `the key equivalent is the chord`() {
    #expect(
      ReaderShortcut.findPrevious.keyboardShortcut
        == KeyboardShortcut("g", modifiers: [.command, .shift]))
    #expect(
      ReaderShortcut.previousSection.keyboardShortcut
        == KeyboardShortcut(.upArrow, modifiers: [.command, .option]))
  }
}
