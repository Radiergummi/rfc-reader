import Testing

@testable import RFCReaderKit

@Suite("Reader arrival")
struct ReaderArrivalTests {
  /// Stands in for the navigation's scroll request, which is the app's.
  private typealias Arrival = ReaderArrival<String>

  /// The first time the text appears, nothing has been read in this view yet.
  @Test func `a request wins over the stored position on opening`() {
    let arrival = Arrival.onAppear(
      pendingAnchor: nil, placeLeft: nil, request: "section-5", storedAnchor: "section-2")
    #expect(arrival == .request("section-5"))
  }

  @Test func `the stored position is restored when there is no request`() {
    let arrival = Arrival.onAppear(
      pendingAnchor: nil, placeLeft: nil, request: nil, storedAnchor: "section-2")
    #expect(arrival == .place("section-2"))
  }

  @Test func `a document never read opens where it is`() {
    let arrival = Arrival.onAppear(
      pendingAnchor: nil, placeLeft: nil, request: nil, storedAnchor: nil)
    #expect(arrival == .stay)
  }

  /// Turning Original Text off makes the text view again (#449): the request that
  /// opened the document and the position stored when it was last left both name
  /// where the reader was then, not where they are.
  @Test func `the text made again returns to where the reader was`() {
    let arrival = Arrival.onAppear(
      pendingAnchor: nil, placeLeft: .section("section-12"), request: "section-5",
      storedAnchor: "section-2")
    #expect(arrival == .place("section-12"))
  }

  /// Ahead of section one — the header, the abstract, a contents list — the
  /// reader's section is reported as section one, and scrolling there would hide
  /// what they were reading. A text view made again starts at the top.
  @Test func `the text made again stays at the top the reader left it at`() {
    let arrival = Arrival.onAppear(
      pendingAnchor: nil, placeLeft: .top, request: "section-5", storedAnchor: "section-2")
    #expect(arrival == .stay)
  }

  /// A jump asked for while the text view was gone — from the contents panel, over
  /// the original text — is where the reader asked to be since.
  @Test func `a scroll asked for while the text was gone wins over the place left`() {
    let arrival = Arrival.onAppear(
      pendingAnchor: "section-7", placeLeft: .section("section-12"), request: "section-7",
      storedAnchor: "section-2")
    #expect(arrival == .place("section-7"))
  }

  /// The store is a fetch; nothing reads it when something else decides.
  @Test func `the stored position is not read when the reader has a place`() {
    var reads = 0
    _ = Arrival.onAppear(
      pendingAnchor: nil, placeLeft: .section("section-12"), request: nil,
      storedAnchor: {
        reads += 1
        return "section-2"
      }())
    #expect(reads == 0)
  }
}
