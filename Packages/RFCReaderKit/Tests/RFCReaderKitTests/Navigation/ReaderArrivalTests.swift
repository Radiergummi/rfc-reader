import Testing

@testable import RFCReaderKit

@Suite("Reader arrival")
struct ReaderArrivalTests {
  /// The first time the text appears, nothing has been read in this view yet.
  @Test func `a request wins over the stored position on opening`() {
    let arrival = ReaderArrival.onAppear(
      visibleAnchor: nil, hasPendingScroll: false, hasRequest: true, storedAnchor: "section-2")
    #expect(arrival == .request)
  }

  @Test func `the stored position is restored when there is no request`() {
    let arrival = ReaderArrival.onAppear(
      visibleAnchor: nil, hasPendingScroll: false, hasRequest: false, storedAnchor: "section-2")
    #expect(arrival == .place("section-2"))
  }

  @Test func `a document never read opens where it is`() {
    let arrival = ReaderArrival.onAppear(
      visibleAnchor: nil, hasPendingScroll: false, hasRequest: false, storedAnchor: nil)
    #expect(arrival == .stay)
  }

  /// Turning Original Text off makes the text view again (#449): the request that
  /// opened the document and the position stored when it was last left both name
  /// where the reader was then, not where they are.
  @Test func `the text made again returns to where the reader was`() {
    let arrival = ReaderArrival.onAppear(
      visibleAnchor: "section-12", hasPendingScroll: false, hasRequest: true,
      storedAnchor: "section-2")
    #expect(arrival == .place("section-12"))
  }

  /// A jump asked for while the text view was gone — from the contents panel, over
  /// the original text — is carried out by the text view as it is made.
  @Test func `a scroll asked for while the text was gone is left to land`() {
    let arrival = ReaderArrival.onAppear(
      visibleAnchor: "section-12", hasPendingScroll: true, hasRequest: true,
      storedAnchor: "section-2")
    #expect(arrival == .stay)
  }

  /// The store is a fetch; nothing reads it when something else decides.
  @Test func `the stored position is not read when the reader has a place`() {
    var reads = 0
    _ = ReaderArrival.onAppear(
      visibleAnchor: "section-12", hasPendingScroll: false, hasRequest: false,
      storedAnchor: {
        reads += 1
        return "section-2"
      }())
    #expect(reads == 0)
  }
}
