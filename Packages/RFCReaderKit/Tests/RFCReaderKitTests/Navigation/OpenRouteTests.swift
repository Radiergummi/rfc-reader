import RFCKit
import Testing

@testable import RFCReaderKit

/// Whether an open jumps within the document on screen or goes somewhere new.
@Suite("Open route")
struct OpenRouteTests {
  private let bcp14 = DocumentID(series: .bcp, number: 14)

  @Test func `a section of the selected document is a jump`() {
    let route = OpenRoute.route(
      RFCLink(id: .rfc(9110), section: "4.2"), selected: .rfc(9110), shown: .rfc(9110))
    #expect(route == .jump(to: "4.2"))
  }

  /// The reader resolves an anchor, or finds it names nothing (#276).
  @Test func `an anchor in the selected document is a jump`() {
    let route = OpenRoute.route(
      RFCLink(id: .rfc(9110), anchor: "page-12"), selected: .rfc(9110), shown: .rfc(9110))
    #expect(route == .jump(to: "page-12"))
  }

  /// A selected BCP shows its first member, which is the document on screen (#656).
  @Test func `a section of the RFC a selected series shows is a jump`() {
    let route = OpenRoute.route(
      RFCLink(id: .rfc(2119), section: "2"), selected: bcp14, shown: .rfc(2119))
    #expect(route == .jump(to: "2"))
  }

  @Test func `a section of the selected series is a jump`() {
    let route = OpenRoute.route(
      RFCLink(id: bcp14, section: "2"), selected: bcp14, shown: .rfc(2119))
    #expect(route == .jump(to: "2"))
  }

  /// No place to jump to: the document's own row, which reopens it if hidden.
  @Test func `the selected document without a place is a go`() {
    let route = OpenRoute.route(RFCLink(id: .rfc(9110)), selected: .rfc(9110), shown: .rfc(9110))
    #expect(route == .go(to: HistoryEntry(id: .rfc(9110))))
  }

  @Test func `another document goes to its place, arrived at as asked`() {
    let route = OpenRoute.route(
      RFCLink(id: .rfc(8446), section: "4.1"), arrival: .citation, selected: .rfc(9110),
      shown: .rfc(9110))
    #expect(route == .go(to: HistoryEntry(id: .rfc(8446), section: "4.1", arrival: .citation)))
  }

  /// A hidden document is not on screen, so a link into it opens it at the place.
  @Test func `a place with nothing selected is a go`() {
    let route = OpenRoute.route(
      RFCLink(id: .rfc(9110), anchor: "page-12"), selected: nil, shown: nil)
    #expect(route == .go(to: HistoryEntry(id: .rfc(9110), section: "page-12")))
  }
}
