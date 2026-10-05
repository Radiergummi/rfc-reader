import Foundation
import Testing

@testable import RFCReaderKit

/// `#expect` cannot hold a mutating call, so each key is typed first and what
/// type-select answered is expected after.
@Suite("Index overlay: type-select")
struct IndexTypeSelectTests {
  static let keys = ["accept", "cache", "content-type", "content length", "etag", "if-match"]

  /// Types each of `characters` a tenth of a second apart from `start`, answering what
  /// type-select said to each.
  static func type(_ characters: String, into select: inout IndexTypeSelect, from start: Double = 0)
    -> [Bool]
  {
    characters.enumerated().map { step in
      select.type(String(step.element), at: start + Double(step.offset) * 0.1)
    }
  }

  @Test func `typed letters build a buffer that selects the first entry they start`() {
    var select = IndexTypeSelect()
    #expect(Self.type("c", into: &select) == [true])
    #expect(select.match(in: Self.keys) == 1)
    #expect(Self.type("o", into: &select, from: 0.3) == [true])
    #expect(select.match(in: Self.keys) == 2)
  }

  @Test func `case and diacritics are folded`() {
    var select = IndexTypeSelect()
    #expect(Self.type("É", into: &select) == [true])
    #expect(select.match(in: Self.keys) == 4)
  }

  @Test func `a pause starts a new buffer`() {
    var select = IndexTypeSelect()
    #expect(Self.type("c", into: &select) == [true])
    #expect(Self.type("e", into: &select, from: IndexTypeSelect.timeout + 0.1) == [true])
    #expect(select.buffer == "e")
  }

  @Test func `a space joins a buffer that holds something, and otherwise is not type-select's`() {
    var select = IndexTypeSelect()
    #expect(Self.type(" ", into: &select) == [false])
    #expect(select.buffer.isEmpty)
    #expect(Self.type("content l", into: &select).allSatisfy { $0 })
    #expect(select.match(in: Self.keys) == 3)
  }

  @Test func `punctuation joins a buffer that holds something, and never starts one`() {
    var select = IndexTypeSelect()
    #expect(Self.type("-", into: &select) == [false])
    #expect(Self.type("if-m", into: &select, from: 0.1) == [true, true, true, true])
    #expect(select.match(in: Self.keys) == 5)
  }

  @Test func `with no entry starting so, the next entry in order is selected`() {
    var select = IndexTypeSelect()
    #expect(Self.type("d", into: &select) == [true])
    #expect(select.match(in: Self.keys) == 4)
  }

  @Test func `past every entry, the last is selected`() {
    var select = IndexTypeSelect()
    #expect(Self.type("z", into: &select) == [true])
    #expect(select.match(in: Self.keys) == 5)
  }

  @Test func `nothing typed or nothing to select selects nothing`() {
    var select = IndexTypeSelect()
    #expect(select.match(in: Self.keys) == nil)
    #expect(Self.type("a", into: &select) == [true])
    #expect(select.match(in: []) == nil)
  }

  @Test func `a control character is not type-select's`() {
    var select = IndexTypeSelect()
    #expect(Self.type("\u{F700}", into: &select) == [false])
    #expect(Self.type("\t", into: &select) == [false])
  }
}
