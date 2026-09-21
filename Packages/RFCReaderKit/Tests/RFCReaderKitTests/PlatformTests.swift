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

    @Test func theSymbolShimRendersAtTheSizeAsked() throws {
        let small = try #require(PlatformImage.symbol(named: "doc.text", pointSize: 10))
        let large = try #require(PlatformImage.symbol(named: "doc.text", pointSize: 30))
        #expect(large.size.height > small.size.height)
    }

    @Test func addingATraitKeepsTheSizeAndAddsTheTrait() {
        let base = PlatformFont.systemFont(ofSize: 17)
        let bold = base.adding(traits: RFCTraits.bold)
        #expect(bold.pointSize == base.pointSize)
        #expect(bold.fontDescriptor.symbolicTraits.contains(RFCTraits.bold))
    }

    @Test func traitsAreDistinctAndNonEmpty() {
        #expect(!RFCTraits.italic.isEmpty)
        #expect(!RFCTraits.bold.isEmpty)
        #expect(RFCTraits.italic != RFCTraits.bold)
    }
}
