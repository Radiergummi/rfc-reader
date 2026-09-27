import Testing

@testable import RFCReaderKit

@Suite("Anchor index")
struct AnchorIndexTests {
  private let index = AnchorIndex([
    .init(anchor: "section-1", offset: 0),
    .init(anchor: "figure-1", offset: 120),
    .init(anchor: "section-2", offset: 400),
  ])

  @Test func `finds an offset by anchor`() {
    #expect(index.offset(of: "figure-1") == 120)
    #expect(index.offset(of: "nope") == nil)
  }

  @Test func `finds the nearest preceding anchor`() {
    #expect(index.anchor(at: 0) == "section-1")
    #expect(index.anchor(at: 119) == "section-1")
    #expect(index.anchor(at: 120) == "figure-1")
    #expect(index.anchor(at: 399) == "figure-1")
    #expect(index.anchor(at: 10_000) == "section-2")
  }

  /// The same lookup, as a position in `entries`, for a caller that needs the
  /// entry before as well.
  @Test func `finds the nearest preceding entrys index`() {
    #expect(index.index(at: 0) == 0)
    #expect(index.index(at: 399) == 1)
    #expect(index.index(at: 400) == 2)
    #expect(AnchorIndex([.init(anchor: "abstract", offset: 50)]).index(at: 49) == nil)
  }

  @Test func `returns nil before the first anchor`() {
    let offsetIndex = AnchorIndex([.init(anchor: "abstract", offset: 50)])
    #expect(offsetIndex.anchor(at: 49) == nil)
    #expect(offsetIndex.anchor(at: 50) == "abstract")
  }

  @Test func `sorts entries by offset`() {
    let unsorted = AnchorIndex([
      .init(anchor: "b", offset: 10),
      .init(anchor: "a", offset: 5),
    ])
    #expect(unsorted.entries.map(\.anchor) == ["a", "b"])
  }
}
