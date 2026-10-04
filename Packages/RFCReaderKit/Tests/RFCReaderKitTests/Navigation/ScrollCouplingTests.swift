import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@MainActor
@Suite("Scroll coupling")
struct ScrollCouplingTests {
  private static let old = DocumentID.rfc(7231)
  private static let new = DocumentID.rfc(9110)

  /// A reader whose sections are one per hundred characters, `section-1` at 0, and
  /// which records what it was told to follow. Following reports the place it was
  /// sent to, as a text view's scroll does.
  private final class FakeReader: CoupledReader {
    let document: DocumentID
    var alignedSide: AlignedScrolling.Side?
    var followed: [AlignedScrolling.Follow] = []
    weak var coupling: ScrollCoupling?

    init(_ document: DocumentID, sections: Int) {
      self.document = document
      alignedSide = AlignedScrolling.Side(
        document: document,
        sections: AnchorIndex(
          (1...sections).map {
            AnchorIndex.Entry(anchor: "section-\($0)", offset: ($0 - 1) * 100, heading: "\($0).")
          }),
        length: sections * 100)
    }

    func follow(_ follow: AlignedScrolling.Follow) {
      followed.append(follow)
      if case .offset(let offset) = follow { coupling?.moved(document, to: offset) }
    }
  }

  private let coupling = ScrollCoupling(leader: old, follower: new)
  private let oldReader = FakeReader(old, sections: 3)
  private let newReader = FakeReader(new, sections: 3)

  /// Sections 1 and 2 swapped places; 3 has no counterpart.
  private static let rows = [
    AlignedSection(old: old, oldSection: "section-1", new: new, newSection: "section-2", score: 1),
    AlignedSection(old: old, oldSection: "section-2", new: new, newSection: "section-1", score: 1),
  ]

  init() {
    oldReader.coupling = coupling
    newReader.coupling = coupling
    coupling.attach(oldReader, showing: Self.old)
    coupling.attach(newReader, showing: Self.new)
  }

  @Test func `the follower follows the leader once the two are aligned`() {
    coupling.moved(Self.old, to: 50)
    #expect(newReader.followed.isEmpty)
    coupling.scrolling = AlignedScrolling(rows: Self.rows, between: Self.old, and: Self.new)
    #expect(newReader.followed == [.offset(150)])
    coupling.moved(Self.old, to: 120)
    #expect(newReader.followed.last == .offset(20))
  }

  @Test func `what the follower reports moves nothing back`() {
    coupling.scrolling = AlignedScrolling(rows: Self.rows, between: Self.old, and: Self.new)
    coupling.moved(Self.old, to: 50)
    coupling.moved(Self.new, to: 70)
    #expect(oldReader.followed.isEmpty)
  }

  @Test func `the reader used last leads`() {
    coupling.scrolling = AlignedScrolling(rows: Self.rows, between: Self.old, and: Self.new)
    coupling.lead(Self.new)
    coupling.moved(Self.new, to: 30)
    #expect(oldReader.followed == [.offset(130)])
    coupling.moved(Self.old, to: 0)
    #expect(newReader.followed.isEmpty)
  }

  @Test func `a follower attached later is put where the leader is`() {
    let coupling = ScrollCoupling(leader: Self.old, follower: Self.new)
    coupling.scrolling = AlignedScrolling(rows: Self.rows, between: Self.old, and: Self.new)
    coupling.attach(oldReader, showing: Self.old)
    coupling.moved(Self.old, to: 150)
    let reader = FakeReader(Self.new, sections: 3)
    coupling.attach(reader, showing: Self.new)
    #expect(reader.followed == [.offset(50)])
  }

  @Test func `an unaligned section holds the follower and is told once`() {
    var told: [String?] = []
    coupling.onUnaligned = { _, section in told.append(section) }
    coupling.scrolling = AlignedScrolling(rows: Self.rows, between: Self.old, and: Self.new)
    coupling.moved(Self.old, to: 210)
    coupling.moved(Self.old, to: 250)
    #expect(newReader.followed == [])
    coupling.moved(Self.old, to: 10)
    #expect(told == ["section-3", nil])
  }

  @Test func `a reader that went is not the one a newer reader replaced`() {
    let replacement = FakeReader(Self.new, sections: 3)
    coupling.attach(replacement, showing: Self.new)
    coupling.detach(newReader, showing: Self.new)
    coupling.scrolling = AlignedScrolling(rows: Self.rows, between: Self.old, and: Self.new)
    coupling.moved(Self.old, to: 0)
    #expect(replacement.followed == [.offset(100)])
  }
}
