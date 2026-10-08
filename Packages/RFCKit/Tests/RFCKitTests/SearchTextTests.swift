import Testing

@testable import RFCKit

@Suite("Search text")
struct SearchTextTests {
  private func text(_ string: String) -> SearchText { SearchText(alreadyFolded: string) }

  // MARK: - Containment

  @Test func `a term is found at the start middle and end`() {
    let haystack = text("hypertext transfer protocol")
    #expect(haystack.contains(text("hypertext")))
    #expect(haystack.contains(text("transfer")))
    #expect(haystack.contains(text("protocol")))
  }

  @Test func `a term that is not there is not found`() {
    #expect(!text("hypertext transfer protocol").contains(text("quic")))
  }

  @Test func `a term longer than the field is not found`() {
    #expect(!text("tls").contains(text("transport layer security")))
  }

  @Test func `every field contains the empty term`() {
    #expect(text("anything").contains(text("")))
    #expect(text("").contains(text("")))
  }

  @Test func `an empty field contains nothing else`() {
    #expect(!text("").contains(text("a")))
  }

  /// The case the first-byte skip gets wrong if the inner walk does not restart
  /// from the right place: every candidate starts correctly and fails late.
  @Test func `repeated first bytes do not confuse the scan`() {
    #expect(text("aaaaab").contains(text("aaab")))
    #expect(!text("aaaaa").contains(text("aaab")))
    #expect(text("abababc").contains(text("ababc")))
  }

  @Test func `a field contains itself`() {
    #expect(text("congestion control").contains(text("congestion control")))
  }

  // MARK: - Prefixes

  @Test func `numbers match on their prefix`() {
    #expect(text("9110").hasPrefix(text("91")))
    #expect(text("9110").hasPrefix(text("9110")))
    #expect(!text("9110").hasPrefix(text("110")))
    #expect(!text("911").hasPrefix(text("9110")))
  }

  @Test func `everything has the empty prefix`() {
    #expect(text("9110").hasPrefix(text("")))
  }

  // MARK: - Beyond ASCII

  /// UTF-8 is self-synchronizing and a needle never begins with a continuation
  /// byte, so scanning bytes cannot match halfway into a character.
  @Test func `a match never starts inside a character`() {
    #expect(text("münchen").contains(text("ünchen")))
    #expect(!text("münchen").contains(text("unchen")))
    #expect(text("größe").contains(text("öß")))
  }

  /// The one thing byte comparison gives up against `String.range(of:)`, pinned so
  /// it is a known trade rather than a surprise: the two spellings of `é` are
  /// canonically equivalent and don't match as bytes. The search folds both sides
  /// first (`folded`, #425), so it never meets them unfolded.
  @Test func `canonically equivalent spellings no longer match`() {
    let composed = text("\u{00E9}")
    let decomposed = text("e\u{0301}")
    #expect(!composed.contains(decomposed))
    #expect(!decomposed.contains(composed))
  }

  /// Folded, they are the same bytes, and so is a letter Foundation doesn't count as
  /// a base letter and a diacritic: a kana and its voicing mark typed apart.
  @Test func `folded, canonically equivalent spellings are the same`() {
    #expect(SearchText(folding: "\u{00E9}") == SearchText(folding: "e\u{0301}"))
    #expect(SearchText(folding: "\u{304C}") == SearchText(folding: "\u{304B}\u{3099}"))
  }
}
