import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

/// The per-tab back/forward stack. Pure value semantics, so two tabs holding one of
/// these cannot see each other's history -- which is the whole point: the reader used
/// to keep its selection on a process-wide singleton, and navigating in one tab moved
/// every other tab with it.
@Suite("Navigation history")
struct NavigationHistoryTests {
    private func place(_ number: Int, _ section: String? = nil) -> Place {
        Place(id: .rfc(number), section: section)
    }

    @Test func aFreshHistoryGoesNowhere() {
        let history = NavigationHistory()
        #expect(history.current == nil)
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func theFirstVisitIsNotSomethingToGoBackFrom() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        #expect(history.current == place(9110))
        #expect(!history.canGoBack, "there is nowhere behind the first document")
        #expect(!history.canGoForward)
    }

    @Test func backReturnsToThePreviousDocument() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(8999))
        #expect(history.canGoBack)

        #expect(history.goBack() == place(9110))
        #expect(history.current == place(9110))
        #expect(history.canGoForward)
        #expect(!history.canGoBack)
    }

    @Test func forwardRetracesTheStepBack() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(8999))
        _ = history.goBack()

        #expect(history.goForward() == place(8999))
        #expect(history.current == place(8999))
        #expect(history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func goingNowhereWhenThereIsNowhereToGo() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        #expect(history.goBack() == nil)
        #expect(history.goForward() == nil)
        #expect(history.current == place(9110), "a refused move must not disturb where we are")
    }

    /// A browser drops the forward stack the moment you strike out in a new direction.
    @Test func navigatingAfterGoingBackDropsTheForwardStack() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(8999))
        _ = history.goBack()
        #expect(history.canGoForward)

        history.go(to: place(2119))
        #expect(!history.canGoForward, "9110 -> 8999, back, then off to 2119: 8999 is no longer ahead")
        #expect(history.goBack() == place(9110))
    }

    /// Section jumps are navigations too, so Back undoes one.
    @Test func aSectionJumpWithinOneDocumentIsItsOwnEntry() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(9110, "4.2"))
        #expect(history.current == place(9110, "4.2"))
        #expect(history.canGoBack)
        #expect(history.goBack() == place(9110))
    }

    /// Leaving a document records where the reader actually was, so coming back does
    /// not dump them at the top of a 200-page RFC.
    @Test func backRestoresWhereTheReaderWasReading() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(8999), leaving: "section-7.3")
        #expect(history.goBack() == place(9110, "section-7.3"))
    }

    /// The position we left is only remembered for the entry we left; arriving
    /// somewhere new must not inherit it.
    @Test func thePositionLeftBehindDoesNotFollowYouForward() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(8999), leaving: "section-7.3")
        #expect(history.current == place(8999), "8999 is opened at its top, not at 9110's position")
    }

    /// Going back, then forward again, should return to the spot you were reading when
    /// you first left -- not to the top.
    @Test func forwardAlsoRestoresItsRecordedPosition() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(8999))
        _ = history.goBack(leaving: "section-2.1")
        #expect(history.goForward() == place(8999, "section-2.1"), "forward returns to where 8999 was left")
        #expect(history.goBack() == place(9110), "9110 was left at its top, and stays there")
    }

    /// Re-opening the document already on screen is not a navigation. Clicking the
    /// same link twice must not stack two identical entries to walk back through.
    @Test func openingWhatIsAlreadyOpenIsNotAnEntry() {
        var history = NavigationHistory()
        history.go(to: place(9110))
        history.go(to: place(9110))
        #expect(!history.canGoBack)
    }

    @Test func theStackSurvivesALongWalk() {
        var history = NavigationHistory()
        for number in 1...10 { history.go(to: place(number)) }
        for number in stride(from: 9, through: 1, by: -1) {
            #expect(history.goBack() == place(number))
        }
        #expect(!history.canGoBack)
        for number in 2...10 {
            #expect(history.goForward() == place(number))
        }
        #expect(!history.canGoForward)
    }
}
