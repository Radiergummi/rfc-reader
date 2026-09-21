import Foundation
import Testing
@testable import RFCReaderKit

@Suite("Platform types")
@MainActor
struct PlatformTests {
    @Test func dynamicColoursAreNotResolved() {
        // The point of RFCColors is that the values stored in the attributed string
        // resolve at draw time, so dark mode costs a redraw and never a rebuild.
        #expect(RFCColors.label !== RFCColors.secondaryLabel)
    }

    @Test func monospacedFontIsMonospaced() {
        let font = PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let builder = DocumentTextBuilder(style: ReadingStyle())
        let narrow = builder.lineWidth("i", font: font)
        let wide = builder.lineWidth("W", font: font)
        #expect(abs(narrow - wide) < 0.01)
    }

    @Test func traitsAreDistinctAndNonEmpty() {
        #expect(!RFCTraits.italic.isEmpty)
        #expect(!RFCTraits.bold.isEmpty)
        #expect(RFCTraits.italic != RFCTraits.bold)
    }
}
