import Foundation
import RFCKit

/// The help's sections, in its order (#780). Each is a place the help can be opened
/// at, as a search field's "Search Syntax…" opens it at the search.
public enum HelpSection: String, CaseIterable, Identifiable, Sendable {
  case search
  case shortcuts
  case gestures
  case readingModes
  case backlinks

  public var id: String { rawValue }

  public func title(locale: Locale = .interface) -> String {
    switch self {
    case .search: String(kit: "Searching", locale: locale)
    case .shortcuts: String(kit: "Keyboard Shortcuts", locale: locale)
    case .gestures: String(kit: "Clicks and Gestures", locale: locale)
    case .readingModes: String(kit: "Reading Modes", locale: locale)
    case .backlinks: String(kit: "Backlinks", locale: locale)
    }
  }
}

/// What the help says (#780): plain data, as the glossary and the primer are, so its
/// words are in RFCReaderKit's catalog and a test can read them. Native text in a
/// window or a sheet, never a web page or a help book (VISION, "never ship a web
/// view").
public enum HelpContent {
  /// One line of a section: a term, such as `wg:httpbis` or a gesture's name, and
  /// what it does.
  public struct Entry: Hashable, Sendable {
    public let term: String
    public let text: String
  }

  /// The help's own title: its window's, its sheet's and the menu item's.
  public static func title(locale: Locale = .interface) -> String {
    ReaderShortcut.help.title(locale: locale)
  }

  /// What a section says before its entries.
  public static func introduction(
    to section: HelpSection, on platform: ReaderShortcut.Platform = .current,
    locale: Locale = .interface
  ) -> String {
    switch section {
    case .search:
      String(
        kit: """
          The library's search field finds RFCs by number, title, keyword, author, working \
          group and abstract. Filters narrow what it finds: a filter's name, a colon and a \
          value, with a comma between values that any one of may match. Words and filters \
          can be mixed in any order.
          """, locale: locale)
    case .shortcuts:
      String(
        kit: "The menus list every command that has a shortcut, beside its name.", locale: locale)
    case .gestures:
      String(kit: "Links in an RFC do more than open what they name.", locale: locale)
    case .readingModes:
      switch platform {
      case .mac:
        String(
          kit: """
            A reading mode changes what the reader shows, never the document itself. \
            Choose one in View ▸ Reading Mode.
            """, locale: locale)
      case .iOS:
        String(
          kit: """
            A reading mode changes what the reader shows, never the document itself. \
            Choose one in the reader's More menu.
            """, locale: locale)
      }
    case .backlinks:
      String(
        kit: """
          A heading that other sections of the document refer to has a caption under it, \
          such as "Three Backlinks". Choose the caption to list the sections that refer to \
          the heading, and choose one of them to go there.
          """, locale: locale)
    }
  }

  /// A section's entries. The search's are its filters, from RFCKit's grammar; the
  /// shortcuts' are not entries but `ReaderShortcut.rows(in:on:locale:)`.
  public static func entries(
    in section: HelpSection, on platform: ReaderShortcut.Platform = .current,
    locale: Locale = .interface
  ) -> [Entry] {
    switch section {
    case .search:
      SearchQuery.filterNames.map { name in
        Entry(
          term: filterExample(name), text: filterExplanation(name, locale: locale) ?? "")
      }
    case .shortcuts, .backlinks: []
    case .gestures: gestures(on: platform, locale: locale)
    case .readingModes:
      ReadingMode.allCases.map { mode in
        Entry(term: mode.name(in: locale), text: explanation(of: mode, locale: locale))
      }
    }
  }

  /// A filter written with a value, as it would be typed. Syntax, so it is not
  /// translated.
  static func filterExample(_ name: String) -> String {
    switch name {
    case "wg": "wg:httpbis"
    case "status": "status:std"
    case "author": "author:fielding"
    case "stream": "stream:irtf"
    case "year": "year:2020-2022"
    case "after": "after:2023-06"
    case "before": "before:2024"
    case "published": "published:<90d"
    case "has": "has:xml"
    case "is": "is:bookmarked"
    case "in": "in:rfc9110"
    case "section": "section:security"
    case "sort": "sort:newest"
    default: "\(name):"
    }
  }

  /// What a filter does, or nil for one the help has no words for yet, which a test
  /// rules out.
  static func filterExplanation(_ name: String, locale: Locale) -> String? {
    switch name {
    case "wg":
      String(
        kit: "RFCs from a working group, such as wg:quic,tls for either. Also group:.",
        locale: locale)
    case "status":
      String(
        kit: """
          RFCs with a status: std, internet-standard, bcp, info, exp or historic; current \
          leaves out the obsoleted ones.
          """, locale: locale)
    case "author":
      String(kit: "RFCs with an author of that name. Also by:.", locale: locale)
    case "stream":
      String(
        kit: "RFCs from a stream: ietf, irtf, iab, independent, editorial or legacy.",
        locale: locale)
    case "year":
      String(kit: "RFCs published in a year, or in a range of years.", locale: locale)
    case "after":
      String(kit: "RFCs published after a year or a month.", locale: locale)
    case "before":
      String(kit: "RFCs published before a year or a month.", locale: locale)
    case "published":
      String(kit: "RFCs published within that many days.", locale: locale)
    case "has":
      String(kit: "RFCs published in RFCXML, the format of most RFCs since 2019.", locale: locale)
    case "is":
      String(kit: "Your own RFCs: bookmarked, read or offline.", locale: locale)
    case "in":
      String(
        kit: """
          Within one RFC, such as in:rfc9110 or in:bcp14, or a collection, such as \
          in:"My Collection".
          """, locale: locale)
    case "section":
      String(
        kit: """
          Sections whose heading matches, in the RFCs the app holds, or in every RFC once \
          Index All RFCs has run.
          """, locale: locale)
    case "sort":
      String(kit: "The order of the results: newest, oldest or last-read.", locale: locale)
    default: nil
    }
  }

  private static func gestures(on platform: ReaderShortcut.Platform, locale: Locale) -> [Entry] {
    switch platform {
    case .mac:
      [
        Entry(
          term: String(kit: "Hover", locale: locale),
          text: String(
            kit: """
              Rest the pointer on a reference to an RFC to see its title, status and \
              abstract.
              """, locale: locale)),
        Entry(
          term: String(kit: "Force Click", locale: locale),
          text: String(
            kit: """
              Force-click a reference to read the RFC it names at the place it names, \
              without leaving the page. Click the preview to go there.
              """, locale: locale)),
        Entry(
          term: String(kit: "Command-Click", locale: locale),
          text: String(
            kit: """
              Open a link in a new tab behind this one; with Shift as well, in front of it.
              """, locale: locale)),
        Entry(
          term: String(kit: "Option-Click", locale: locale),
          text: String(
            kit: """
              Option-click a section's number to copy a link to the section, and a format \
              in Info to download it rather than open it in the browser.
              """, locale: locale)),
      ]
    case .iOS:
      [
        Entry(
          term: String(kit: "Touch and Hold", locale: locale),
          text: String(
            kit: """
              Touch and hold a reference to read the RFC it names at the place it names, \
              without leaving the page. Tap the preview to go there.
              """, locale: locale))
      ]
    }
  }

  private static func explanation(of mode: ReadingMode, locale: Locale) -> String {
    switch mode {
    case .normal:
      String(kit: "The whole document.", locale: locale)
    case .outline:
      String(
        kit: """
          Only the headings. A heading's chevron opens its section in place, and closes it \
          again.
          """, locale: locale)
    case .focus:
      String(
        kit: """
          One section and its subsections. Next Section and Previous Section move to the \
          sections beside it.
          """, locale: locale)
    case .implementer:
      String(
        kit: """
          The whole document, each requirement with a MUST, SHOULD or MAY marked by a band, \
          and its asides folded under their captions.
          """, locale: locale)
    }
  }
}
