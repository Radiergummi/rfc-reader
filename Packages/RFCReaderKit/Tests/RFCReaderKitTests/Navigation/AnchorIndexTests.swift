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

  /// #143: the section index is made with the index, so asking for it is free and
  /// gives the same index each time; an index of sections only is its own.
  @Test func `the section index holds the sections, and is its own`() {
    let index = AnchorIndex([
      .init(anchor: "section-1", offset: 0, heading: "1. Introduction"),
      .init(anchor: "figure-1", offset: 120),
      .init(anchor: "section-2", offset: 400, heading: "2. Terms"),
    ])
    #expect(index.sections.entries.map(\.anchor) == ["section-1", "section-2"])
    #expect(index.sections.heading(of: "section-2") == "2. Terms")
    #expect(index.sections.offset(of: "figure-1") == nil)
    #expect(index.sections.sections == index.sections)
    #expect(index.sections != index)
    #expect(AnchorIndex([]).sections == AnchorIndex([]))
  }

  /// The one binary search both lookups share: the first element past the
  /// partition point, the end when there is none.
  @Test func `the partitioning index is the first element that belongs after the point`() {
    let offsets = [0, 120, 120, 400]
    #expect(offsets.partitioningIndex { $0 > -1 } == 0)
    #expect(offsets.partitioningIndex { $0 > 0 } == 1)
    #expect(offsets.partitioningIndex { $0 > 120 } == 3)
    #expect(offsets.partitioningIndex { $0 > 400 } == 4)
    #expect([Int]().partitioningIndex { $0 > 0 } == 0)
    #expect(offsets[1...].partitioningIndex { $0 > 120 } == 3)
  }
}
