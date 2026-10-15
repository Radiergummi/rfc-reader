import Testing

@testable import RFCReaderKit

/// What a tap on the reader's text does on iPhone: it toggles the bars, unless it is
/// for something else (#598).
@Suite("Reader chrome taps")
struct ReaderChromeTapTests {
  /// A text with a link at 10 and a heading that toggles at 20.
  private static func action(for tap: ReaderChrome.Tap, discloses: Bool = true)
    -> ReaderChrome.TapAction
  {
    ReaderChrome.action(
      for: tap, discloses: discloses, isLink: { $0 == 10 }, toggles: { $0 == 20 })
  }

  private static func tap(
    clears: Bool = false, onHeader: Bool = false, besideDisclosure: Int? = nil,
    character: Int? = nil
  ) -> ReaderChrome.Tap {
    ReaderChrome.Tap(
      clearsSelectionOrStopsFling: clears, isOnHeader: onHeader,
      besideDisclosure: besideDisclosure, character: character)
  }

  @Test func `a tap on plain text toggles the bars`() {
    #expect(Self.action(for: Self.tap(character: 5)) == .toggleBars)
  }

  @Test func `a tap beside the text toggles the bars`() {
    #expect(Self.action(for: Self.tap()) == .toggleBars)
  }

  @Test func `a tap on the header is the header's`() {
    #expect(Self.action(for: Self.tap(onHeader: true, character: 5)) == .nothing)
  }

  @Test func `a tap on a link follows it`() {
    #expect(Self.action(for: Self.tap(character: 10)) == .nothing)
  }

  @Test func `a tap that clears a selection or stops a fling does only that`() {
    #expect(Self.action(for: Self.tap(clears: true, character: 5)) == .nothing)
    #expect(Self.action(for: Self.tap(clears: true, character: 20)) == .nothing)
  }

  @Test func `a tap on a heading that discloses toggles its section`() {
    #expect(Self.action(for: Self.tap(character: 20)) == .toggleSection(at: 20))
  }

  @Test func `a tap beside a disclosure toggles its section`() {
    #expect(
      Self.action(for: Self.tap(besideDisclosure: 20, character: 5)) == .toggleSection(at: 20))
  }

  @Test func `beside a disclosure with nothing to toggle, the character decides`() {
    #expect(Self.action(for: Self.tap(besideDisclosure: 30, character: 10)) == .nothing)
  }

  @Test func `out of a mode that discloses, a heading is text`() {
    #expect(
      Self.action(for: Self.tap(besideDisclosure: 20, character: 20), discloses: false)
        == .toggleBars)
  }
}
