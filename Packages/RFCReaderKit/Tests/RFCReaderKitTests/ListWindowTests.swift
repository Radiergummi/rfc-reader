import Testing

@testable import RFCReaderKit

@Suite("List window")
struct ListWindowTests {
  private let page = ListWindow.page
  private let lead = ListWindow.lead

  // MARK: - Where a list starts

  @Test func aListStartsAtOnePage() {
    #expect(ListWindow.initialLimit() == page)
  }

  @Test func aSelectionInsideTheFirstPageWidensNothing() {
    #expect(ListWindow.initialLimit(covering: 0) == page)
    #expect(ListWindow.initialLimit(covering: page - 1) == page)
  }

  /// The case this exists for: `open` resets the filter to `.all` so the document
  /// cannot be hidden, and a window stopping at the first page would hide it again.
  @Test func aSelectionBelowTheFirstPageWidensTheWindowPastIt() {
    let limit = ListWindow.initialLimit(covering: 7_700)
    #expect(limit > 7_700)
  }

  @Test func theWidenedWindowEndsOnAPageBoundary() {
    #expect(ListWindow.initialLimit(covering: page) == page * 2)
    #expect(ListWindow.initialLimit(covering: page * 2 - 1) == page * 2)
    #expect(ListWindow.initialLimit(covering: page * 2) == page * 3)
  }

  // MARK: - Growing it

  @Test func theTriggerSitsALeadAboveTheEndOfTheWindow() {
    #expect(ListWindow.triggerRow(limit: page, total: 9_842) == page - lead)
  }

  /// Otherwise the last row of a short list reports itself into an extension that
  /// can never render anything, once per scroll past it.
  @Test func aWindowAlreadyCoveringEverythingHasNoTrigger() {
    #expect(ListWindow.triggerRow(limit: page, total: 40) == nil)
    #expect(ListWindow.triggerRow(limit: page, total: page) == nil)
  }

  /// The trigger has to be a row the view is actually rendering, or nothing ever
  /// reports it and the list stops growing halfway down.
  @Test func theTriggerIsAlwaysInsideTheWindowAndTheList() {
    for total in [page + 1, page + lead, 1_000, 9_842] {
      var limit = ListWindow.initialLimit()
      while let trigger = ListWindow.triggerRow(limit: limit, total: total) {
        #expect(trigger >= 0)
        #expect(trigger < limit)
        #expect(trigger < total)
        limit = ListWindow.extendedLimit(from: limit, total: total)
      }
    }
  }

  @Test func eachExtensionAddsAPage() {
    #expect(ListWindow.extendedLimit(from: page, total: 9_842) == page * 2)
  }

  @Test func theLastExtensionStopsAtTheEndRatherThanPastIt() {
    let total = page + 10
    #expect(ListWindow.extendedLimit(from: page, total: total) == total)
  }

  /// Walking the whole library reaches the end and then stops asking.
  @Test func repeatedExtensionsWalkToTheEndAndStop() {
    let total = 9_842
    var limit = ListWindow.initialLimit()
    var extensions = 0
    while ListWindow.triggerRow(limit: limit, total: total) != nil {
      let next = ListWindow.extendedLimit(from: limit, total: total)
      #expect(next > limit)
      limit = next
      extensions += 1
      #expect(extensions < 1_000, "the window stopped growing before it reached the end")
    }
    #expect(limit == total)
  }
}
