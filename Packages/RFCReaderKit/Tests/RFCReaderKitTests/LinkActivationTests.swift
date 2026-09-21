import Foundation
import Testing
@testable import RFCReaderKit

/// The browser's conventions, because that is what a reader's hands already know.
@Suite("Link activation")
struct LinkActivationTests {
    private typealias Keys = LinkActivation.ModifierKeys

    @Test func aPlainClickFollowsTheLinkHere() {
        #expect(LinkActivation.from(modifiers: []) == .here)
    }

    @Test func commandOpensABackgroundTabAndLeavesYouWhereYouAre() {
        #expect(LinkActivation.from(modifiers: .command) == .newTabInBackground)
    }

    /// The ordering that is easy to get wrong: Command-Shift must not fall through to
    /// the Shift case and open a window.
    @Test func commandShiftOpensAForegroundTabNotAWindow() {
        #expect(LinkActivation.from(modifiers: [.command, .shift]) == .newTabInForeground)
    }

    @Test func shiftAloneOpensAWindow() {
        #expect(LinkActivation.from(modifiers: .shift) == .newWindow)
    }

    @Test func modifiersWeDoNotCareAboutAreIgnored() {
        // Option and Control are not in the set at all, so an Option-click reads as a
        // plain one rather than as something unhandled.
        #expect(LinkActivation.from(modifiers: Keys(rawValue: 1 << 7)) == .here)
        #expect(LinkActivation.from(modifiers: [.command, Keys(rawValue: 1 << 7)]) == .newTabInBackground)
    }
}
