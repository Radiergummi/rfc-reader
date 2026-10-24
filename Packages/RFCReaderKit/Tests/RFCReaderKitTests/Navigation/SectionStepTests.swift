import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Next Section and Previous Section outside Focus (#711): which heading the reader
/// goes to from the line it is on, a pure function of the build and the folding.
@Suite("Section steps")
struct SectionStepTests {
  private static func rfc8999() throws -> BuiltDocument {
    DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle())
  }

  /// A line inside the entry at `position`, past its heading: in its text.
  private static func line(inside position: Int, of index: FoldingIndex) -> Int {
    let entry = index.entries[position]
    let end =
      position + 1 < index.entries.count ? index.entries[position + 1].paragraph : index.length
    return (entry.offset + end) / 2
  }

  /// From inside a section Previous goes back to its own heading, the nearest above
  /// the line, as `[[` does in vim.
  @Test func `next goes past the line's section and previous to the heading above it`() throws {
    let index = try Self.rfc8999().foldingIndex
    let entries = index.entries
    for position in entries.indices.dropFirst().dropLast() {
      let line = Self.line(inside: position, of: index)
      #expect(
        Folding().section(.next, fromLine: line, in: index) == entries[position + 1].anchor,
        "from \(entries[position].anchor)")
      #expect(
        Folding().section(.previous, fromLine: line, in: index) == entries[position].anchor,
        "from \(entries[position].anchor)")
    }
  }

  /// On a heading, as a jump leaves the reader's line, Next goes on from it rather
  /// than to it again: the line is at the start of its paragraph.
  @Test func `from a heading's own line next goes on to the one after it`() throws {
    let index = try Self.rfc8999().foldingIndex
    let entries = index.entries
    #expect(
      Folding().section(.next, fromLine: entries[1].paragraph, in: index) == entries[2].anchor)
    #expect(
      Folding().section(.previous, fromLine: entries[1].paragraph, in: index)
        == entries[0].anchor)
  }

  /// Above the text, at the header, the reader's line is nil.
  @Test func `above the first heading next goes to it, and previous nowhere`() throws {
    let index = try Self.rfc8999().foldingIndex
    let first = try #require(index.entries.first)
    #expect(Folding().section(.next, fromLine: nil, in: index) == first.anchor)
    #expect(Folding().section(.previous, fromLine: nil, in: index) == nil)
    #expect(Folding(mode: .outline).section(.next, fromLine: nil, in: index) == first.anchor)
  }

  @Test func `at the end next goes nowhere`() throws {
    let index = try Self.rfc8999().foldingIndex
    let entries = index.entries
    #expect(Folding().section(.next, fromLine: index.length, in: index) == nil)
    #expect(Folding().section(.previous, fromLine: index.length, in: index) == entries.last?.anchor)
  }

  /// RFC 8999's Appendix A goes by an anchor of its own, `bad-assumptions`.
  @Test func `from inside an appendix the steps leave it`() throws {
    let built = try Self.rfc8999()
    let index = built.foldingIndex
    let appendix = try #require(index.entries.firstIndex { $0.anchor == "bad-assumptions" })
    let line = Self.line(inside: appendix, of: index)
    #expect(Folding().section(.previous, fromLine: line, in: index) == "bad-assumptions")
    #expect(
      Folding().section(.next, fromLine: line, in: index)
        == index.entries.dropFirst(appendix + 1).first?.anchor)
  }

  /// Closed, the outline shows the top-level headings only, and the steps go from
  /// one to the next, past the subsections it folds.
  @Test func `in the outline the steps go to the rows it shows`() throws {
    let index = try Self.rfc8999().foldingIndex
    let outline = Folding(mode: .outline)
    let rows = index.entries.filter { $0.depth == 1 }
    let parent = try #require(
      rows.indices.dropLast().first { position in
        index.entries.contains {
          $0.depth > 1 && $0.offset > rows[position].offset && $0.offset < rows[position + 1].offset
        }
      })
    #expect(
      outline.section(.next, fromLine: rows[parent].paragraph, in: index)
        == rows[parent + 1].anchor)
    #expect(
      outline.section(.previous, fromLine: rows[parent + 1].paragraph, in: index)
        == rows[parent].anchor)
    // Open, its subsections are rows of their own.
    let open = Folding(mode: .outline, expanded: [rows[parent].anchor])
    let child = try #require(index.entries.first { $0.offset > rows[parent].offset })
    #expect(open.section(.next, fromLine: rows[parent].paragraph, in: index) == child.anchor)
  }

  @Test func `focus steps its focus instead`() throws {
    let index = try Self.rfc8999().foldingIndex
    #expect(Folding(focusingOn: nil).section(.next, fromLine: 0, in: index) == nil)
  }

  @Test func `implementer steps as normal reading does`() throws {
    let index = try Self.rfc8999().foldingIndex
    let line = Self.line(inside: 1, of: index)
    #expect(
      Folding(mode: .implementer).section(.next, fromLine: line, in: index)
        == Folding().section(.next, fromLine: line, in: index))
  }
}
