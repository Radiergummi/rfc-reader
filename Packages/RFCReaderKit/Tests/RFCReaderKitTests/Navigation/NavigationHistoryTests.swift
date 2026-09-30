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
  private func place(_ number: Int, _ section: String? = nil) -> HistoryEntry {
    HistoryEntry(id: .rfc(number), section: section)
  }

  // MARK: - Returning from a jump within a document (#254)

  @Test func `a jump within the document offers the way back`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-15.5"), leaving: "section-4.2")
    #expect(history.returnOffer == place(9110, "section-4.2"))
  }

  /// The system back button already leaves the document; the offer is for
  /// returning within it.
  @Test func `a jump to another document offers nothing`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    #expect(history.returnOffer == nil)
  }

  @Test func `the first place offers nothing`() {
    var history = NavigationHistory()
    history.go(to: place(9110, "section-4.2"))
    #expect(history.returnOffer == nil)
  }

  /// Stepping through the history is not a jump to undo, even when the step lands
  /// next to another place in the same document.
  @Test func `stepping back or forward offers nothing`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-4"))
    history.go(to: place(9110, "section-15"))
    _ = history.goBack()
    #expect(history.returnOffer == nil)
    _ = history.goForward()
    #expect(history.returnOffer == nil)
  }

  /// Settled is a fact about the history, not about the place offered: the same
  /// jump taken again, after going back, offers again.
  @Test func `a settled offer stays settled until the next jump`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-15"), leaving: "section-4")
    history.settleReturnOffer()
    #expect(history.returnOffer == nil)
    #expect(history.current == place(9110, "section-15"), "settling does not move")

    _ = history.goBack()
    history.go(to: place(9110, "section-15"), leaving: "section-4")
    #expect(history.returnOffer == place(9110, "section-4"))
  }

  @Test func `a new jump after stepping back offers again`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-4"))
    _ = history.goBack()
    history.go(to: place(9110, "section-9"), leaving: "section-2")
    #expect(history.returnOffer == place(9110, "section-2"))
  }

  // MARK: - Leaving the document without leaving the history (#261)

  /// Going back to the list on an iPhone, or deselecting the row on a Mac, puts
  /// nothing on screen. The history is not where that decision is undone: Back
  /// and Forward still work from the list.
  @Test func `hiding puts nothing on screen and keeps the history`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    history.hide()
    #expect(history.shown == nil)
    #expect(history.current == place(8999))
    #expect(history.canGoBack)
  }

  /// The row just left is the likeliest one to be tapped again, and `go` treats
  /// the place already current as no navigation at all.
  @Test func `going to the hidden place shows it without a new entry`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    history.hide()
    history.go(to: place(8999))
    #expect(history.shown == place(8999))
    #expect(history.goBack() == place(9110))
    #expect(!history.canGoBack)
  }

  /// The row carries no section, and the place left behind usually does: after a
  /// jump, a deep link, or Back and Forward.
  @Test func `reopening the hidden document shows it where it was`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-15.5"), leaving: "section-4.2")
    history.hide()
    history.go(to: place(9110))
    #expect(history.shown == place(9110, "section-15.5"))
    #expect(history.goBack() == place(9110, "section-4.2"))
    #expect(!history.canGoBack)
  }

  /// Reopening is not a jump to undo, even though Back stays in the document.
  @Test func `reopening the hidden document offers nothing`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-15.5"), leaving: "section-4.2")
    history.hide()
    history.go(to: place(9110))
    #expect(history.returnOffer == nil)
  }

  @Test func `going somewhere else records the hidden place`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.hide()
    history.go(to: place(8999))
    #expect(history.shown == place(8999))
    #expect(history.goBack() == place(9110))
  }

  @Test func `stepping back or forward shows where it lands`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    history.hide()
    _ = history.goBack()
    #expect(history.shown == place(9110))
    history.hide()
    _ = history.goForward()
    #expect(history.shown == place(8999))
  }

  /// The offer is drawn over the document it returns within.
  @Test func `nothing on screen offers nothing`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-15.5"), leaving: "section-4.2")
    history.hide()
    #expect(history.returnOffer == nil)
  }

  @Test func `a fresh history shows nothing`() {
    #expect(NavigationHistory().shown == nil)
  }

  @Test func `a fresh history goes nowhere`() {
    let history = NavigationHistory()
    #expect(history.current == nil)
    #expect(!history.canGoBack)
    #expect(!history.canGoForward)
  }

  @Test func `the first visit is not something to go back from`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    #expect(history.current == place(9110))
    #expect(!history.canGoBack, "there is nowhere behind the first document")
    #expect(!history.canGoForward)
  }

  @Test func `back returns to the previous document`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    #expect(history.canGoBack)

    #expect(history.goBack() == place(9110))
    #expect(history.current == place(9110))
    #expect(history.canGoForward)
    #expect(!history.canGoBack)
  }

  @Test func `forward retraces the step back`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    _ = history.goBack()

    #expect(history.goForward() == place(8999))
    #expect(history.current == place(8999))
    #expect(history.canGoBack)
    #expect(!history.canGoForward)
  }

  @Test func `going nowhere when there is nowhere to go`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    #expect(history.goBack() == nil)
    #expect(history.goForward() == nil)
    #expect(history.current == place(9110), "a refused move must not disturb where we are")
  }

  /// A browser drops the forward stack the moment you strike out in a new direction.
  @Test func `navigating after going back drops the forward stack`() {
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
  @Test func `a section jump within one document is its own entry`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "4.2"))
    #expect(history.current == place(9110, "4.2"))
    #expect(history.canGoBack)
    #expect(history.goBack() == place(9110))
  }

  /// Leaving a document records where the reader actually was, so coming back does
  /// not dump them at the top of a 200-page RFC.
  @Test func `back restores where the reader was reading`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999), leaving: "section-7.3")
    #expect(history.goBack() == place(9110, "section-7.3"))
  }

  /// The position we left is only remembered for the entry we left; arriving
  /// somewhere new must not inherit it.
  @Test func `the position left behind does not follow you forward`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999), leaving: "section-7.3")
    #expect(history.current == place(8999), "8999 is opened at its top, not at 9110's position")
  }

  /// Going back, then forward again, should return to the spot you were reading when
  /// you first left -- not to the top.
  @Test func `forward also restores its recorded position`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(8999))
    _ = history.goBack(leaving: "section-2.1")
    #expect(
      history.goForward() == place(8999, "section-2.1"), "forward returns to where 8999 was left")
    #expect(history.goBack() == place(9110), "9110 was left at its top, and stays there")
  }

  /// Re-opening the document already on screen is not a navigation. Clicking the
  /// same link twice must not stack two identical entries to walk back through.
  @Test func `opening what is already open is not an entry`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110))
    #expect(!history.canGoBack)
  }

  /// Going to the section the reader is in scrolls back to it, without a second
  /// entry (#287).
  @Test func `going to the section the reader is in arrives there again`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-4.2"))
    #expect(
      history.go(to: place(9110, "section-4.2"), leaving: "section-4.2")
        == place(9110, "section-4.2"))
    #expect(history.go(to: place(9110, "section-4.2")) == place(9110, "section-4.2"))
    #expect(history.goBack() == place(9110))
    #expect(!history.canGoBack)
  }

  // MARK: - Where the reader is, in either spelling (#482)

  private let document = RFCDocument(
    header: DocumentHeader(title: "T"),
    sections: [
      Section(anchor: "section-1", number: "1", title: "Introduction"),
      Section(
        anchor: "section-4", number: "4", title: "Semantics",
        subsections: [Section(anchor: "section-4.2", number: "4.2", title: "Methods")]),
      Section(anchor: "section-9", number: "9", title: "Security"),
    ],
    source: .xml)

  /// The build's anchors: every section's, the abstract ahead of them, and a
  /// figure in §4.2.
  private var places: DocumentPlaces {
    DocumentPlaces(
      document: document,
      anchors: AnchorIndex([
        .init(anchor: "abstract", offset: 0),
        .init(anchor: "section-1", offset: 50, heading: "1. Introduction", place: "1"),
        .init(anchor: "section-4", offset: 100, heading: "4. Semantics", place: "4"),
        .init(anchor: "section-4.2", offset: 200, heading: "4.2. Methods", place: "4.2"),
        .init(anchor: "figure-1", offset: 300),
        .init(anchor: "section-9", offset: 400, heading: "9. Security", place: "9"),
      ]))
  }

  /// Read on from the section the tab was sent to, then sent there again: where
  /// the reader had got to is a place to come back to, so it gets an entry.
  @Test func `going to the current section after reading on is a navigation`() {
    var history = NavigationHistory()
    history.go(to: place(9110, "section-1"))
    history.go(to: place(9110, "section-4.2"), leaving: "section-1")
    #expect(
      history.go(to: place(9110, "section-4.2"), leaving: "section-9")
        == place(9110, "section-4.2"))
    #expect(history.returnOffer == place(9110, "section-9"))
    #expect(history.goBack() == place(9110, "section-9"))
    #expect(history.goBack() == place(9110, "section-1"))
    #expect(!history.canGoBack)
  }

  @Test func `a place is recorded as its anchor`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    #expect(
      history.go(to: place(9110, "4.2"), in: places)
        == place(9110, "section-4.2"))
    #expect(history.current == place(9110, "section-4.2"))
  }

  /// A link spells the place as a number, the contents and the reader's position
  /// as an anchor; the same place clicked twice is still one entry.
  @Test func `the same place in either spelling is one entry`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "4.2"), in: places)
    history.go(
      to: place(9110, "section-4.2"), leaving: "section-4.2", in: places)
    history.go(
      to: place(9110, "4.2"), leaving: "section-4.2", in: places)
    #expect(history.goBack() == place(9110))
    #expect(!history.canGoBack)
  }

  /// A deep link records the number before the document is loaded to resolve it.
  @Test func `a number the tab was sent to is the anchor the reader reports`() {
    var history = NavigationHistory()
    history.go(to: place(9110, "4.2"))
    #expect(
      history.go(to: place(9110, "section-4.2"), in: places)
        == place(9110, "section-4.2"))
    #expect(
      history.go(
        to: place(9110, "section-4.2"), leaving: "section-4.2",
        in: places)
        == place(9110, "section-4.2"))
    #expect(!history.canGoBack)
    #expect(history.current == place(9110, "section-4.2"))
  }

  /// The reader reports where it is by section, so while it reports the section a
  /// figure is in, it is still at the figure.
  @Test func `a place in the section the reader reports is where the reader is`() {
    var history = NavigationHistory()
    history.go(to: place(9110, "section-1"))
    history.go(to: place(9110, "figure-1"), leaving: "section-1", in: places)
    #expect(
      history.go(to: place(9110, "figure-1"), leaving: "section-4.2", in: places)
        == place(9110, "figure-1"))
    #expect(history.goBack() == place(9110, "section-1"))
    #expect(!history.canGoBack)
  }

  /// Ahead of the first section the reader reports that section, so a place
  /// there is where the reader is while it does.
  @Test func `a place ahead of the first section is where the reader is`() {
    var history = NavigationHistory()
    history.go(to: place(9110, "section-9"))
    history.go(to: place(9110, "abstract"), leaving: "section-9", in: places)
    #expect(
      history.go(to: place(9110, "abstract"), leaving: "section-1", in: places)
        == place(9110, "abstract"))
    #expect(history.goBack() == place(9110, "section-9"))
    #expect(!history.canGoBack)
  }

  /// Where the reader was is recorded in the same spelling as where it went.
  @Test func `the place left behind is recorded as its anchor`() {
    var history = NavigationHistory()
    history.go(to: place(9110, "1"))
    history.go(to: place(9110, "9"), in: places)
    #expect(history.goBack() == place(9110, "section-1"))
  }

  /// A row names no section, so it asks for nothing to scroll to in the document
  /// already open.
  @Test func `going to the document already open without a section goes nowhere`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    #expect(history.go(to: place(9110)) == nil)
  }

  /// A link to the hidden place shows it and scrolls to its section; its row, which
  /// names none, shows it where it was.
  @Test func `going to the hidden place scrolls only when it names a section`() {
    var history = NavigationHistory()
    history.go(to: place(9110))
    history.go(to: place(9110, "section-15.5"))
    history.hide()
    #expect(history.go(to: place(9110, "section-15.5")) == place(9110, "section-15.5"))
    history.hide()
    #expect(history.go(to: place(9110)) == nil)
    #expect(history.shown == place(9110, "section-15.5"))
  }

  @Test func `going somewhere new arrives there`() {
    var history = NavigationHistory()
    #expect(history.go(to: place(9110)) == place(9110))
    #expect(history.go(to: place(9110, "section-4.2")) == place(9110, "section-4.2"))
  }

  @Test func `the stack survives a long walk`() {
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
