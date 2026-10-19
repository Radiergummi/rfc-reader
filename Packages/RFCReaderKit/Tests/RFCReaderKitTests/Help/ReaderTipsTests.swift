import Foundation
import Testing
import TipKit

@testable import RFCReaderKit

/// The tips for what nobody finds (#782): when each shows, what it says, and where
/// its Learn More opens the help. How TipKit presents them is TipKit's.
@Suite("Reader tips")
struct ReaderTipsTests {
  /// TipKit's own rules, evaluated by TipKit over a store of the test's own: each
  /// tip waits for the agreed number of its event, and shows on the one after.
  @Test(arguments: [
    (TipCase.readingMode, 3),
    (TipCase.preview, 1),
    (TipCase.goToRFC, 5),
  ])
  func `each tip shows after the agreed number of its event`(tip: TipCase, count: Int) async {
    TipStore.configureOnce()
    for _ in 1..<count {
      await tip.event.donate()
    }
    #expect(await tip.staysHidden())
    await tip.event.donate()
    #expect(await tip.becomesDisplayable())
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
  @Test func `going to an RFC is taught by its chord on the Mac and its button on iOS`() {
    let chord = ReaderShortcut.quickOpen.chord(on: .mac)?.symbols
    #expect(chord == "⌘K")
    #expect(GoToRFCTip.words(on: .mac, locale: .english).message.contains("⌘K"))
    #expect(GoToRFCTip.words(on: .iOS, locale: .english).message.contains("Go to RFC"))
  }

  @Test func `every tip has words in English and in German`() {
    for platform in ReaderShortcut.Platform.allCases {
      let english = [
        ReadingModeTip.words(locale: .english),
        PreviewTip.words(on: platform, locale: .english),
        GoToRFCTip.words(on: platform, locale: .english),
      ]
      let german = [
        ReadingModeTip.words(locale: Locale(identifier: "de_DE")),
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

  /// A search counts once it is done with, not as it starts: on the first keystroke,
  /// the tip would open over the field being typed in.
  @Test func `a search is counted when it is committed`() {
    #expect(
      SearchStep.counts([
        .edit("", "h"), .edit("h", "http"), .commit("http"),
        // Committed again, or refined and committed, it is the same search.
        .commit("http"), .edit("http", "https"), .commit("https"),
        // Cleared after it counted, it does not count again.
        .edit("https", ""),
        // The next one counts on its own commit.
        .edit("", "tls"), .commit("tls"),
      ]) == [false, false, true, false, false, false, false, false, true])
  }

  @Test func `a search never committed is counted when it is cleared`() {
    #expect(SearchStep.counts([.edit("", "quic"), .edit("quic", "")]) == [false, true])
    // Nothing to count: an empty field cleared, or spaces alone.
    #expect(
      SearchStep.counts([.edit("", ""), .edit("", " "), .edit(" ", ""), .commit(" ")]) == [
        false, false, false, false,
      ])
  }
}

/// An edit of the search field or a commit of it, as `ReaderTips.Searches` is told.
enum SearchStep {
  case edit(String, String)
  case commit(String)

  /// Whether each step counted a search, from a field with none made yet.
  static func counts(_ steps: [SearchStep]) -> [Bool] {
    var searches = ReaderTips.Searches()
    return steps.map { step in
      switch step {
      case .edit(let old, let new): searches.changed(from: old, to: new)
      case .commit(let query): searches.committed(query)
      }
    }
  }
}

/// A tip and the event that brings it on.
enum TipCase: Sendable, CustomTestStringConvertible {
  case readingMode
  case preview
  case goToRFC

  var tip: any Tip {
    switch self {
    case .readingMode: ReadingModeTip()
    case .preview: PreviewTip()
    case .goToRFC: GoToRFCTip()
    }
  }

  var event: Tips.Event<Tips.EmptyDonation> {
    switch self {
    case .readingMode: ReaderTips.documentOpened
    case .preview: ReaderTips.citationFollowed
    case .goToRFC: ReaderTips.searchTyped
    }
  }

  var testDescription: String { "\(self)" }

  /// TipKit settles a donation's effect a moment after it returns: polled for, up to
  /// two seconds.
  func becomesDisplayable() async -> Bool {
    for _ in 0..<40 {
      if tip.shouldDisplay { return true }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return false
  }

  /// Not displayable for as long as a donation could take to settle, half a second:
  /// checked at once, a rule that showed a donation too early would still pass.
  func staysHidden() async -> Bool {
    for _ in 0..<10 {
      if tip.shouldDisplay { return false }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return true
  }
}

/// TipKit configured once for the test process, over a store of its own in a
/// temporary directory, so no run sees another's donations. Each tip's event is its
/// own, so the cases do not count each other's.
enum TipStore {
  private static let configured: Void = {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ReaderTipsTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? Tips.configure([.datastoreLocation(.url(directory)), .displayFrequency(.immediate)])
  }()

  static func configureOnce() { configured }
}
