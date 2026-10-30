import CoreGraphics
import Foundation

/// What a key pressed in the reader's text does (#711).
public enum ReaderKeyCommand: Equatable, Sendable {
  case scroll(Scroll)
  /// The document's top and end.
  case top
  case end
  /// Next Section and Previous Section.
  case section(Folding.FocusStep)
  case find
  case findNext
  case findPrevious
  /// The focus moves to the next or previous link.
  case link(Folding.FocusStep)
  /// The focused link is followed, as a click on it is.
  case followLink
  /// The focused link's preview opens, as a force click or a long press opens it.
  case previewLink
  /// The focus leaves the link it is on.
  case leaveLink

  /// How far a key scrolls.
  public enum Scroll: Sendable {
    case pageDown
    case pageUp
    case halfPageDown
    case halfPageUp
    case lineDown
    case lineUp

    /// The distance down, negative up, for a `viewport` this high showing lines
    /// `line` high. A page keeps one line of the one before it in view, as Safari's
    /// does, unless the viewport holds no more than two lines.
    public func distance(viewport: CGFloat, line: CGFloat) -> CGFloat {
      let page = viewport > 2 * line ? viewport - line : viewport
      return switch self {
      case .pageDown: page
      case .pageUp: -page
      case .halfPageDown: viewport / 2
      case .halfPageUp: -viewport / 2
      case .lineDown: line
      case .lineUp: -line
      }
    }
  }
}

/// The reader's keys (#711): turns the keys pressed in the reader's text into
/// commands, holding the first key of a vim pair, `gg`, `]]`, `[[`, `]r` or `[r`, until
/// the second comes.
///
/// Only keys pressed without ⌘, ⌃ or a chord's ⌥ come here: those are the menus' and
/// the text view's own, as ⌘↑ and ⌘↓ go to the document's top and end. Nor do any while a
/// text field has the focus, which the text view is not then.
public struct ReaderKeys: Sendable {
  /// A key press, as far as the reader tells keys apart. A letter is the character
  /// it types, Shift included: `G` is Shift-G.
  public enum Key: Equatable, Sendable {
    case character(Character)
    case space
    case shiftSpace
    case tab
    case shiftTab
    case returnKey
    case escape
  }

  /// Which of the reader's keys are on: Settings ▸ Reading's Keyboard section.
  public struct Options: Equatable, Sendable {
    public var vimKeys: Bool
    public var tabsThroughLinks: Bool

    public init(vimKeys: Bool, tabsThroughLinks: Bool) {
      self.vimKeys = vimKeys
      self.tabsThroughLinks = tabsThroughLinks
    }
  }

  public enum Outcome: Equatable, Sendable {
    case command(ReaderKeyCommand)
    /// The first key of a pair, held for the second.
    case pending
    /// Not the reader's: the text view does what it does with it.
    case unhandled
  }

  /// How long the first key of a pair waits for the second, in seconds: vim's own
  /// `timeoutlen`.
  public static let pairTimeout: TimeInterval = 1

  /// The first key of a pair, and when it was pressed.
  private var pending: (key: Character, time: TimeInterval)?

  public init() {}

  /// What `key`, pressed at `time` in seconds, does with `options` on, and with a
  /// link focused or not.
  public mutating func press(
    _ key: Key, at time: TimeInterval, options: Options, focusesLink: Bool
  ) -> Outcome {
    let first = pending
    pending = nil
    if let first, options.vimKeys, time - first.time <= Self.pairTimeout,
      case .character(let second) = key, let command = Self.pair(first.key, second)
    {
      return .command(command)
    }
    switch key {
    case .space: return .command(focusesLink ? .previewLink : .scroll(.pageDown))
    case .shiftSpace: return .command(.scroll(.pageUp))
    case .tab: return options.tabsThroughLinks ? .command(.link(.next)) : .unhandled
    case .shiftTab: return options.tabsThroughLinks ? .command(.link(.previous)) : .unhandled
    case .returnKey: return focusesLink ? .command(.followLink) : .unhandled
    case .escape: return focusesLink ? .command(.leaveLink) : .unhandled
    case .character(let character):
      guard options.vimKeys else { return .unhandled }
      if Self.pairs.contains(character) {
        pending = (character, time)
        return .pending
      }
      return Self.single(character).map(Outcome.command) ?? .unhandled
    }
  }

  /// The keys that start a pair.
  private static let pairs: Set<Character> = ["g", "]", "["]

  private static func pair(_ first: Character, _ second: Character) -> ReaderKeyCommand? {
    switch (first, second) {
    case ("g", "g"): .top
    case ("]", "]"): .section(.next)
    case ("[", "["): .section(.previous)
    case ("]", "r"): .link(.next)
    case ("[", "r"): .link(.previous)
    default: nil
    }
  }

  private static func single(_ character: Character) -> ReaderKeyCommand? {
    switch character {
    case "j": .scroll(.lineDown)
    case "k": .scroll(.lineUp)
    case "d": .scroll(.halfPageDown)
    case "u": .scroll(.halfPageUp)
    case "G": .end
    case "/": .find
    case "n": .findNext
    case "N": .findPrevious
    default: nil
    }
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  extension ReaderKeys.Key {
    /// The reader's key a key press on the Mac is, from its `characters`, what they
    /// would be without the modifiers, and its modifier flags; nil for one with ⌘ or
    /// ⌃ held, which is the menus' or the text view's, and for one that types no
    /// single character. With ⌥ held, only the character ⌥ typed, as a German Mac
    /// types `[` and `]` with ⌥5 and ⌥6; a chord's ⌥ that changes nothing is nil.
    public init?(
      characters: String?, charactersIgnoringModifiers: String?,
      modifiers: NSEvent.ModifierFlags
    ) {
      guard modifiers.isDisjoint(with: [.command, .control]),
        let characters, characters.count == 1, let character = characters.first
      else { return nil }
      if modifiers.contains(.option) {
        guard characters != charactersIgnoringModifiers else { return nil }
        self = .character(character)
        return
      }
      let shift = modifiers.contains(.shift)
      switch character {
      case " ": self = shift ? .shiftSpace : .space
      case "\t": self = .tab
      // AppKit's Shift-Tab, NSBackTabCharacter.
      case "\u{19}": self = .shiftTab
      // Return, and Enter, NSEnterCharacter.
      case "\r", "\u{3}": self = .returnKey
      case "\u{1B}": self = .escape
      default: self = .character(character)
      }
    }
  }
#elseif canImport(UIKit)
  import UIKit

  extension ReaderKeys.Key {
    /// The reader's key a hardware keyboard's key is, from its usage, the characters
    /// it types, what they would be without the modifiers, and its modifier flags; nil
    /// for one with ⌘ or ⌃ held, which is the menus' or the text view's, and for one
    /// that types no single character. With ⌥ held, only the character ⌥ typed, as a
    /// German keyboard types `[` and `]` with ⌥5 and ⌥6; a chord's ⌥ that changes
    /// nothing is nil.
    public init?(
      keyCode: UIKeyboardHIDUsage, characters: String, charactersIgnoringModifiers: String,
      modifiers: UIKeyModifierFlags
    ) {
      guard modifiers.isDisjoint(with: [.command, .control]) else { return nil }
      if modifiers.contains(.alternate) {
        guard characters != charactersIgnoringModifiers, characters.count == 1,
          let character = characters.first
        else { return nil }
        self = .character(character)
        return
      }
      let shift = modifiers.contains(.shift)
      switch keyCode {
      case .keyboardSpacebar: self = shift ? .shiftSpace : .space
      case .keyboardTab: self = shift ? .shiftTab : .tab
      case .keyboardReturnOrEnter, .keypadEnter: self = .returnKey
      case .keyboardEscape: self = .escape
      default:
        guard characters.count == 1, let character = characters.first else { return nil }
        self = .character(character)
      }
    }
  }
#endif
