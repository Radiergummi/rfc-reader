import Testing
@testable import RFCKit

@Suite("Search text")
struct SearchTextTests {
    private func text(_ string: String) -> SearchText { SearchText(string) }

    // MARK: - Containment

    @Test func aTermIsFoundAtTheStartMiddleAndEnd() {
        let haystack = text("hypertext transfer protocol")
        #expect(haystack.contains(text("hypertext")))
        #expect(haystack.contains(text("transfer")))
        #expect(haystack.contains(text("protocol")))
    }

    @Test func aTermThatIsNotThereIsNotFound() {
        #expect(!text("hypertext transfer protocol").contains(text("quic")))
    }

    @Test func aTermLongerThanTheFieldIsNotFound() {
        #expect(!text("tls").contains(text("transport layer security")))
    }

    @Test func everyFieldContainsTheEmptyTerm() {
        #expect(text("anything").contains(text("")))
        #expect(text("").contains(text("")))
    }

    @Test func anEmptyFieldContainsNothingElse() {
        #expect(!text("").contains(text("a")))
    }

    /// The case the first-byte skip gets wrong if the inner walk does not restart
    /// from the right place: every candidate starts correctly and fails late.
    @Test func repeatedFirstBytesDoNotConfuseTheScan() {
        #expect(text("aaaaab").contains(text("aaab")))
        #expect(!text("aaaaa").contains(text("aaab")))
        #expect(text("abababc").contains(text("ababc")))
    }

    @Test func aFieldContainsItself() {
        #expect(text("congestion control").contains(text("congestion control")))
    }

    // MARK: - Prefixes

    @Test func numbersMatchOnTheirPrefix() {
        #expect(text("9110").hasPrefix(text("91")))
        #expect(text("9110").hasPrefix(text("9110")))
        #expect(!text("9110").hasPrefix(text("110")))
        #expect(!text("911").hasPrefix(text("9110")))
    }

    @Test func everythingHasTheEmptyPrefix() {
        #expect(text("9110").hasPrefix(text("")))
    }

    // MARK: - Beyond ASCII

    /// UTF-8 is self-synchronizing and a needle never begins with a continuation
    /// byte, so scanning bytes cannot match halfway into a character.
    @Test func aMatchNeverStartsInsideACharacter() {
        #expect(text("münchen").contains(text("ünchen")))
        #expect(!text("münchen").contains(text("unchen")))
        #expect(text("größe").contains(text("öß")))
    }

    /// The one thing byte comparison gives up against `String.range(of:)`, pinned so
    /// it is a known trade rather than a surprise: the two spellings of `é` are
    /// canonically equivalent and no longer match each other.
    @Test func canonicallyEquivalentSpellingsNoLongerMatch() {
        let composed = text("\u{00E9}")
        let decomposed = text("e\u{0301}")
        #expect(!composed.contains(decomposed))
        #expect(!decomposed.contains(composed))
    }
}
