import Foundation
import Testing

@testable import RFCReaderKit

/// The tips for what nobody finds (#782): when each shows, what it says, and where
/// its Learn More opens the help. How TipKit presents them is TipKit's.
@Suite("Reader tips")
struct ReaderTipsTests {
  @Test func `each tip shows after the agreed number of its event`() {
    #expect(ReadingModeTip.documentsOpened == 3)
    #expect(PreviewTip.citationsFollowed == 1)
    #expect(GoToRFCTip.searchesTyped == 5)
  }

  @Test func `each tip's Learn More opens the help at its section`() {
    #expect(ReadingModeTip().helpSection == .readingModes)
    #expect(PreviewTip().helpSection == .gestures)
    #expect(GoToRFCTip().helpSection == .shortcuts)
  }

  @Test func `the tips are told apart`() {
    let ids = [ReadingModeTip().id, PreviewTip().id, GoToRFCTip().id]
    #expect(Set(ids).count == ids.count)
  }

  @Test func `a preview is taught as the platform makes one`() {
    let mac = PreviewTip.words(on: .mac, locale: .english)
    let iOS = PreviewTip.words(on: .iOS, locale: .english)
    #expect(mac.message.contains("Force-click"))
    #expect(iOS.message.contains("Touch and hold"))
    #expect(mac.title == iOS.title)
  }

  /// The Mac's tip names the chord the command answers, so the two cannot drift.
  @Test func `Go to RFC is taught by its chord on the Mac and its button on iOS`() {
    let chord = ReaderShortcut.quickOpen.chord(on: .mac)?.symbols
    #expect(chord == "⌘K")
    #expect(GoToRFCTip.words(on: .mac, locale: .english).message.contains("⌘K"))
    #expect(GoToRFCTip.words(on: .iOS, locale: .english).message.contains("Go to RFC"))
  }

  @Test func `every tip has words in English and in German`() {
    for platform in ReaderShortcut.Platform.allCases {
      let english = [
        ReadingModeTip.words(on: platform, locale: .english),
        PreviewTip.words(on: platform, locale: .english),
        GoToRFCTip.words(on: platform, locale: .english),
      ]
      let german = [
        ReadingModeTip.words(on: platform, locale: Locale(identifier: "de_DE")),
        PreviewTip.words(on: platform, locale: Locale(identifier: "de_DE")),
        GoToRFCTip.words(on: platform, locale: Locale(identifier: "de_DE")),
      ]
      for (english, german) in zip(english, german) {
        #expect(!english.title.isEmpty && !english.message.isEmpty)
        #expect(english.title != german.title, "\(english.title) is not translated")
        #expect(english.message != german.message, "\(english.message) is not translated")
      }
    }
  }

  /// A search typed by hand counts once, when the field gains text, not on every
  /// keystroke: five searches, not five letters.
  @Test func `a search is counted when an empty field gains text`() {
    #expect(ReaderTips.startsSearch(from: "", to: "h"))
    #expect(!ReaderTips.startsSearch(from: "h", to: "ht"))
    #expect(!ReaderTips.startsSearch(from: "http", to: ""))
    #expect(!ReaderTips.startsSearch(from: "", to: ""))
    // Spaces alone are no search.
    #expect(!ReaderTips.startsSearch(from: "", to: " "))
    #expect(ReaderTips.startsSearch(from: " ", to: " q"))
  }
}
