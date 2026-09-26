import Testing

@testable import RFCReaderKit

@Suite("Anchor index")
struct AnchorIndexTests {
  private let index = AnchorIndex([
    .init(anchor: "section-1", offset: 0),
    .init(anchor: "figure-1", offset: 120),
    .init(anchor: "section-2", offset: 400),
  ])

  @Test func findsAnOffsetByAnchor() {
    #expect(index.offset(of: "figure-1") == 120)
    #expect(index.offset(of: "nope") == nil)
  }

  @Test func findsTheNearestPrecedingAnchor() {
    #expect(index.anchor(at: 0) == "section-1")
    #expect(index.anchor(at: 119) == "section-1")
    #expect(index.anchor(at: 120) == "figure-1")
    #expect(index.anchor(at: 399) == "figure-1")
    #expect(index.anchor(at: 10_000) == "section-2")
  }

  @Test func returnsNilBeforeTheFirstAnchor() {
    let offsetIndex = AnchorIndex([.init(anchor: "abstract", offset: 50)])
    #expect(offsetIndex.anchor(at: 49) == nil)
    #expect(offsetIndex.anchor(at: 50) == "abstract")
  }

  @Test func sortsEntriesByOffset() {
    let unsorted = AnchorIndex([
      .init(anchor: "b", offset: 10),
      .init(anchor: "a", offset: 5),
    ])
    #expect(unsorted.entries.map(\.anchor) == ["a", "b"])
  }
}
