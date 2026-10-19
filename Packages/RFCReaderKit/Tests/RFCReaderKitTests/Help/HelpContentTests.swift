import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the help says (#780): the search syntax, the shortcuts, the gestures, the
/// reading modes and the backlinks.
@Suite("Help content")
struct HelpContentTests {
  @Test func `the sections are in the help's order`() {
    #expect(
      HelpSection.allCases.map { $0.title(locale: .english) } == [
        "Searching", "Keyboard Shortcuts", "Clicks and Gestures", "Reading Modes", "Backlinks",
      ])
    #expect(HelpContent.title(locale: .english) == "RFC Reader Help")
  }

  /// The search's entries come from RFCKit's grammar, so a new filter is listed
  /// without a hand edit, and this fails until the help has words for it.
  @Test func `every filter is listed, with an example and what it does`() {
    let entries = HelpContent.entries(in: .search, on: .mac, locale: .english)
    #expect(entries.count == SearchQuery.filterNames.count)
    for (name, entry) in zip(SearchQuery.filterNames, entries) {
      #expect(entry.term.hasPrefix("\(name):"))
      #expect(entry.term.count > name.count + 1, "\(name) has no example value")
      #expect(!entry.text.isEmpty, "\(name) has no explanation")
    }
  }

  /// An example is a query the search reads as the filter it shows, not as text.
  @Test func `every filter's example is a filter the search reads`() {
    for entry in HelpContent.entries(in: .search, on: .mac, locale: .english) {
      let parsed = IndexSearch.parseQuery(entry.term)
      #expect(parsed.text.isEmpty, "\(entry.term)")
      #expect(parsed.unknown.isEmpty, "\(entry.term)")
    }
  }

  @Test func `every reading mode is explained`() {
    let entries = HelpContent.entries(in: .readingModes, on: .mac, locale: .english)
    #expect(entries.map(\.term) == ReadingMode.allCases.map { $0.name(in: .english) })
    #expect(entries.allSatisfy { $0.text.hasSuffix(".") })
  }

  /// The Mac's pointer gestures, and the touch screen's one.
  @Test func `the gestures are the platform's`() {
    #expect(
      HelpContent.entries(in: .gestures, on: .mac, locale: .english).map(\.term) == [
        "Hover", "Force Click", "Command-Click", "Option-Click",
      ])
    #expect(
      HelpContent.entries(in: .gestures, on: .iOS, locale: .english).map(\.term) == [
        "Touch and Hold"
      ])
  }

  /// Every section says something before its entries, on both platforms.
  @Test(arguments: ReaderShortcut.Platform.allCases)
  func `every section is introduced`(platform: ReaderShortcut.Platform) {
    for section in HelpSection.allCases {
      #expect(HelpContent.introduction(to: section, on: platform, locale: .english).hasSuffix("."))
    }
  }

  /// The words come from RFCReaderKit's catalog, so a German interface reads German:
  /// every one of them, as a key that drifted from its entry would fall back to English.
  @Test(arguments: ReaderShortcut.Platform.allCases)
  func `the help is translated`(platform: ReaderShortcut.Platform) {
    func words(_ locale: Locale) -> [String] {
      HelpSection.allCases.flatMap { section in
        [
          section.title(locale: locale),
          HelpContent.introduction(to: section, on: platform, locale: locale),
        ]
          // A filter's example is syntax, which is not translated; its explanation is.
          + HelpContent.entries(in: section, on: platform, locale: locale).flatMap {
            section == .search ? [$0.text] : [$0.term, $0.text]
          }
      }
        + ReaderShortcut.Group.allCases.flatMap { group in
          [group.title(locale: locale)]
            + ReaderShortcut.rows(in: group, on: platform, locale: locale).map(\.title)
        }
    }
    // A word that is the same in both languages.
    let alike: Set<String> = ["Normal"]
    for (english, german) in zip(words(.english), words(.german))
    where !alike.contains(english) {
      #expect(english != german, "\(english)")
    }
  }
}
