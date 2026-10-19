import Foundation
import SwiftUI

/// A keyboard shortcut of the reader's own: the key equivalent its command takes, and
/// the line the help lists it on (#780).
///
/// One list, so the help cannot show a shortcut that has since changed: a test cannot
/// read a key equivalent back out of SwiftUI's `Commands`, so rather than comparing
/// two lists, the commands take theirs from here. The system's own shortcuts, such as
/// Copy or Quit, are not the reader's and are not listed.
///
/// A second way to the same command, such as ⌘K for Go to RFC, is an entry of its own
/// with the same title, and the help lists the two on one line. On the Mac the reader
/// window answers those itself (`QuickOpenShortcut`, `BiggerShortcut`,
/// `HistoryArrowShortcut`), because a menu item holds one key equivalent.
public enum ReaderShortcut: CaseIterable, Sendable {
  case goToRFC
  /// ⌘K, the second way to Go to RFC.
  case quickOpen
  case back
  case forward
  /// ⌘← on the Mac, the second way to Back; the iPad's Back itself.
  case backArrow
  case forwardArrow
  case bookmark
  case newCollection
  case copyAsQuote
  /// Edit ▸ Highlight (#522), Books' chord.
  case highlight
  case copyCitation
  case export
  case pageSetup
  case print
  case bigger
  /// ⌘=, the second way to Bigger.
  case biggerAlternate
  case smaller
  case actualSize
  case toggleSidebar
  case contents
  case info
  case nextSection
  case previousSection
  case find
  case findNext
  case findPrevious
  case useSelectionForFind
  case jumpToSelection
  case searchLibrary
  case newWindow
  case newTab
  case help

  /// Where a shortcut is answered. The iPhone is `.iOS` too: a keyboard can be
  /// attached to one.
  public enum Platform: Sendable, CaseIterable {
    case mac
    case iOS

    public static var current: Platform {
      #if os(macOS)
        .mac
      #else
        .iOS
      #endif
    }
  }

  public enum Key: Hashable, Sendable {
    case character(Character)
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
  }

  public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
  }

  /// A key and the modifiers held with it.
  public struct Chord: Hashable, Sendable {
    public let key: Key
    public let modifiers: Modifiers

    init(_ key: Key, _ modifiers: Modifiers = .command) {
      self.key = key
      self.modifiers = modifiers
    }

    init(_ character: Character, _ modifiers: Modifiers = .command) {
      self.init(.character(character), modifiers)
    }

    /// As a menu writes it: the modifiers in the order ⌃⌥⇧⌘, then the key, a letter
    /// in capitals.
    public var symbols: String {
      var written = ""
      if modifiers.contains(.control) { written += "⌃" }
      if modifiers.contains(.option) { written += "⌥" }
      if modifiers.contains(.shift) { written += "⇧" }
      if modifiers.contains(.command) { written += "⌘" }
      switch key {
      case .character(let character): written += character.uppercased()
      case .upArrow: written += "↑"
      case .downArrow: written += "↓"
      case .leftArrow: written += "←"
      case .rightArrow: written += "→"
      }
      return written
    }
  }

  /// What the help groups the shortcuts under, in the help's order.
  public enum Group: CaseIterable, Sendable {
    case documents
    case view
    case find
    case windows

    public func title(locale: Locale = .interface) -> String {
      switch self {
      case .documents: String(kit: "Documents", locale: locale)
      case .view: String(kit: "View", locale: locale)
      case .find: String(kit: "Find", locale: locale)
      case .windows: String(kit: "Windows and Help", locale: locale)
      }
    }
  }

  /// The chord on `platform`, or nil where the shortcut is not answered there.
  public func chord(on platform: Platform = .current) -> Chord? {
    let mac = platform == .mac
    return switch self {
    case .goToRFC: Chord("l")
    case .quickOpen: Chord("k")
    // On the Mac ⌘[ and ⌘], as Safari's and Finder's menus have them (#761); the
    // iPad keeps the arrows, which nothing else there answers.
    case .back: Chord(mac ? .character("[") : .leftArrow)
    case .forward: Chord(mac ? .character("]") : .rightArrow)
    case .backArrow: mac ? Chord(.leftArrow) : nil
    case .forwardArrow: mac ? Chord(.rightArrow) : nil
    case .bookmark: Chord("d")
    case .newCollection: mac ? Chord("n", [.command, .shift]) : nil
    case .copyAsQuote: mac ? Chord("c", [.command, .option, .shift]) : nil
    case .highlight: mac ? Chord("h", [.command, .control]) : nil
    case .copyCitation: mac ? Chord("c", [.command, .shift]) : nil
    case .export: mac ? Chord("e", [.command, .shift]) : nil
    case .pageSetup: mac ? Chord("p", [.command, .shift]) : nil
    case .print: mac ? Chord("p") : nil
    case .bigger: Chord("+")
    case .biggerAlternate: Chord("=")
    case .smaller: Chord("-")
    case .actualSize: Chord("0")
    case .toggleSidebar: mac ? Chord("s", [.command, .control]) : nil
    // ⌥⌘I, the inspector's chord in Pages, Keynote and Finder; ⌘I, Get Info.
    case .contents: Chord("i", [.command, .option])
    case .info: Chord("i")
    // ⌥⌘↓ and ⌥⌘↑: the text view's arrows take ⌘ to the document's ends and ⌥ to its
    // paragraphs' ends, and leave the two together alone.
    case .nextSection: Chord(.downArrow, [.command, .option])
    case .previousSection: Chord(.upArrow, [.command, .option])
    case .find: Chord("f")
    case .findNext: Chord("g")
    case .findPrevious: Chord("g", [.command, .shift])
    case .useSelectionForFind: mac ? Chord("e") : nil
    case .jumpToSelection: mac ? Chord("j") : nil
    // ⌥⌘F, the chord Mail and Notes give their search field.
    case .searchLibrary: mac ? Chord("f", [.command, .option]) : nil
    case .newWindow: mac ? Chord("n") : nil
    case .newTab: mac ? Chord("t") : nil
    case .help: Chord("?")
    }
  }

  /// What the help calls it: its command's name, or for one whose name changes with
  /// what it will do, such as Show Sidebar, both.
  public func title(locale: Locale = .interface) -> String {
    switch self {
    case .goToRFC, .quickOpen: String(kit: "Go to RFC", locale: locale)
    case .back, .backArrow: String(kit: "Back", locale: locale)
    case .forward, .forwardArrow: String(kit: "Forward", locale: locale)
    case .bookmark: String(kit: "Add or Remove Bookmark", locale: locale)
    case .newCollection: String(kit: "New Collection", locale: locale)
    case .copyAsQuote: String(kit: "Copy as Quote", locale: locale)
    case .highlight: String(kit: "Highlight", locale: locale)
    case .copyCitation: String(kit: "Copy Citation", locale: locale)
    case .export: String(kit: "Export", locale: locale)
    case .pageSetup: String(kit: "Page Setup", locale: locale)
    case .print: String(kit: "Print", locale: locale)
    case .bigger, .biggerAlternate: String(kit: "Bigger Text", locale: locale)
    case .smaller: String(kit: "Smaller Text", locale: locale)
    case .actualSize: String(kit: "Actual Size", locale: locale)
    case .toggleSidebar: String(kit: "Show or Hide Sidebar", locale: locale)
    case .contents: String(kit: "Show or Hide Contents", locale: locale)
    case .info: String(kit: "Show or Hide Info", locale: locale)
    case .nextSection: String(kit: "Next Section, in Focus", locale: locale)
    case .previousSection: String(kit: "Previous Section, in Focus", locale: locale)
    case .find: String(kit: "Find in Document", locale: locale)
    case .findNext: String(kit: "Find Next", locale: locale)
    case .findPrevious: String(kit: "Find Previous", locale: locale)
    case .useSelectionForFind: String(kit: "Use Selection for Find", locale: locale)
    case .jumpToSelection: String(kit: "Jump to Selection", locale: locale)
    case .searchLibrary: String(kit: "Search Library", locale: locale)
    case .newWindow: String(kit: "New Window", locale: locale)
    case .newTab: String(kit: "New Tab", locale: locale)
    case .help: String(kit: "RFC Reader Help", locale: locale)
    }
  }

  public var group: Group {
    switch self {
    case .goToRFC, .quickOpen, .back, .forward, .backArrow, .forwardArrow, .bookmark,
      .newCollection, .copyAsQuote, .highlight, .copyCitation, .export, .pageSetup, .print:
      .documents
    case .bigger, .biggerAlternate, .smaller, .actualSize, .toggleSidebar, .contents, .info,
      .nextSection, .previousSection:
      .view
    case .find, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection, .searchLibrary:
      .find
    case .newWindow, .newTab, .help: .windows
    }
  }

  /// One line of the help: a command's title and every chord that reaches it.
  public struct Row: Hashable, Sendable {
    public let title: String
    public let chords: [Chord]
  }

  /// The help's lines for `group` on `platform`, in the list's order: the shortcuts
  /// answered there, those with the same title on one line.
  public static func rows(
    in group: Group, on platform: Platform = .current, locale: Locale = .interface
  ) -> [Row] {
    var rows: [Row] = []
    for shortcut in allCases where shortcut.group == group {
      guard let chord = shortcut.chord(on: platform) else { continue }
      let title = shortcut.title(locale: locale)
      if let index = rows.firstIndex(where: { $0.title == title }) {
        rows[index] = Row(title: title, chords: rows[index].chords + [chord])
      } else {
        rows.append(Row(title: title, chords: [chord]))
      }
    }
    return rows
  }

  /// The key equivalent its command takes on this platform, or nil where it has
  /// none.
  public var keyboardShortcut: KeyboardShortcut? {
    guard let chord = chord() else { return nil }
    let key: KeyEquivalent =
      switch chord.key {
      case .character(let character): KeyEquivalent(character)
      case .upArrow: .upArrow
      case .downArrow: .downArrow
      case .leftArrow: .leftArrow
      case .rightArrow: .rightArrow
      }
    var modifiers: EventModifiers = []
    if chord.modifiers.contains(.control) { modifiers.insert(.control) }
    if chord.modifiers.contains(.option) { modifiers.insert(.option) }
    if chord.modifiers.contains(.shift) { modifiers.insert(.shift) }
    if chord.modifiers.contains(.command) { modifiers.insert(.command) }
    return KeyboardShortcut(key, modifiers: modifiers)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  extension ReaderShortcut.Chord {
    /// Whether a key press is this chord, for the shortcuts the Mac's reader window
    /// answers itself: exactly its modifiers among ⌃⌥⇧⌘, and its key. Caps Lock and
    /// the function key are ignored, as AppKit's own key equivalents ignore them.
    public func matches(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
      var expected: NSEvent.ModifierFlags = []
      if self.modifiers.contains(.control) { expected.insert(.control) }
      if self.modifiers.contains(.option) { expected.insert(.option) }
      if self.modifiers.contains(.shift) { expected.insert(.shift) }
      if self.modifiers.contains(.command) { expected.insert(.command) }
      guard modifiers.intersection([.command, .shift, .option, .control]) == expected,
        let characters
      else { return false }
      let functionKey: Int
      switch key {
      case .character(let character):
        return characters.lowercased() == String(character).lowercased()
      case .upArrow: functionKey = NSUpArrowFunctionKey
      case .downArrow: functionKey = NSDownArrowFunctionKey
      case .leftArrow: functionKey = NSLeftArrowFunctionKey
      case .rightArrow: functionKey = NSRightArrowFunctionKey
      }
      return characters.unicodeScalars.first.map { Int($0.value) } == functionKey
    }
  }
#endif
