import Foundation
import SwiftUI
import TipKit

/// The tips for what nobody finds (#782): reading modes, reference previews and Go
/// to RFC, each a popover on a toolbar item or a search field, never in the reader's
/// text storage. Their words and rules are here; where each is anchored, and the
/// events, are the app's.
public enum ReaderTips {
  /// A document shown in a reader: a row picked, a link or a citation followed.
  public static let documentOpened = Tips.Event(id: "documentOpened")
  /// A citation of another RFC followed from the reader, which is when Back first
  /// has somewhere to go.
  public static let citationFollowed = Tips.Event(id: "citationFollowed")
  /// A search typed into the library's search field (`startsSearch`).
  public static let searchTyped = Tips.Event(id: "searchTyped")

  /// The defaults key that has the tips reset at the next launch: Developer ▸ Reset
  /// Tips sets it in a Debug build, and `-ResetTipsAtLaunch YES` as a launch
  /// argument does the same. TipKit resets its store only before it is configured.
  public static let resetAtLaunchKey = "ResetTipsAtLaunch"

  /// Configures TipKit, once at launch and before any tip is shown, resetting the
  /// tips first when asked to. Both throw only when TipKit is configured already,
  /// which a second call would be, so there is nothing to recover from.
  @MainActor
  public static func configure(defaults: UserDefaults = .standard) {
    if defaults.bool(forKey: resetAtLaunchKey) {
      defaults.removeObject(forKey: resetAtLaunchKey)
      try? Tips.resetDatastore()
    }
    try? Tips.configure()
  }

  /// Whether an edit of the search field starts a search: the field had no words and
  /// now has some. Counting every keystroke would count letters, not searches.
  public static func startsSearch(from old: String, to new: String) -> Bool {
    old.allSatisfy(\.isWhitespace) && !new.allSatisfy(\.isWhitespace)
  }
}

/// A tip whose Learn More opens the help at a section.
public protocol HelpTip: Tip {
  var helpSection: HelpSection { get }
}

extension HelpTip {
  /// Learn More, the one action each tip has.
  public var actions: [Action] {
    [Action(id: "help", title: String(kit: "Learn More…", locale: .interface))]
  }
}

/// What a tip says.
public struct TipWords: Equatable, Sendable {
  public let title: String
  public let message: String
}

/// Reading Mode, on the reader's More menu, after the third document opened.
public struct ReadingModeTip: HelpTip {
  public init() {}

  public var helpSection: HelpSection { .readingModes }

  public static func words(
    on platform: ReaderShortcut.Platform = .current, locale: Locale = .interface
  ) -> TipWords {
    TipWords(
      title: String(kit: "Read an Outline, or One Section", locale: locale),
      message: String(
        kit: """
          Reading Mode, in this menu, folds the document to its headings, or shows one \
          section at a time.
          """, locale: locale))
  }

  public var title: Text { Text(verbatim: Self.words().title) }
  public var message: Text? { Text(verbatim: Self.words().message) }
  public var image: Image? { Image(systemName: "list.bullet.indent") }

  public var rules: [Rule] {
    #Rule(ReaderTips.documentOpened) { $0.donations.count >= 3 }
  }
}

/// Previews, on Back, after the first citation followed: the moment Back has
/// somewhere to go. On the Mac and the iPad; an iPhone has no Back of the app's
/// own to anchor it to.
public struct PreviewTip: HelpTip {
  public init() {}

  public var helpSection: HelpSection { .gestures }

  public static func words(
    on platform: ReaderShortcut.Platform = .current, locale: Locale = .interface
  ) -> TipWords {
    let title = String(kit: "Preview Before You Go", locale: locale)
    return switch platform {
    case .mac:
      TipWords(
        title: title,
        message: String(
          kit: """
            Force-click a reference to read the RFC it names without leaving this one, \
            or rest the pointer on it for its abstract.
            """, locale: locale))
    case .iOS:
      TipWords(
        title: title,
        message: String(
          kit: "Touch and hold a reference to read the RFC it names without leaving this one.",
          locale: locale))
    }
  }

  public var title: Text { Text(verbatim: Self.words().title) }
  public var message: Text? { Text(verbatim: Self.words().message) }
  public var image: Image? { Image(systemName: "eye") }

  public var rules: [Rule] {
    #Rule(ReaderTips.citationFollowed) { $0.donations.count >= 1 }
  }
}

/// Go to RFC, after the fifth search typed: on the Mac's search field, as ⌘K, and
/// on iOS's Go to RFC button.
public struct GoToRFCTip: HelpTip {
  public init() {}

  public var helpSection: HelpSection { .shortcuts }

  public static func words(
    on platform: ReaderShortcut.Platform = .current, locale: Locale = .interface
  ) -> TipWords {
    let title = String(kit: "Know Which RFC You Want?", locale: locale)
    switch platform {
    case .mac:
      let chord = ReaderShortcut.quickOpen.chord(on: .mac)?.symbols ?? ""
      return TipWords(
        title: title,
        message: String(
          kit: "Press \(chord) to go straight to it, by its number or words from its title.",
          locale: locale))
    case .iOS:
      return TipWords(
        title: title,
        message: String(
          kit: "Go to RFC opens it straight away, by its number or words from its title.",
          locale: locale))
    }
  }

  public var title: Text { Text(verbatim: Self.words().title) }
  public var message: Text? { Text(verbatim: Self.words().message) }
  public var image: Image? { Image(systemName: "number") }

  public var rules: [Rule] {
    #Rule(ReaderTips.searchTyped) { $0.donations.count >= 5 }
  }
}
