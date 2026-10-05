import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// An index set as one: a letter per group, a line per term with its locators as
/// `§` links, the primary first and semibold, subentries one step in; and the map
/// the overlays read.
@Suite("Builder: index")
struct BuilderIndexTests {
  private let style = ReadingStyle()

  static func locator(_ number: Int, primary: Bool) -> IndexBlock.Locator {
    IndexBlock.Locator(
      reference: CrossReference(target: .anchor("section-\(number)"), text: "Section \(number)"),
      isPrimary: primary)
  }

  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      anchor: "rfc.index.u67",
      entries: [
        IndexBlock.Entry(
          term: [.text("cache")],
          locators: [locator(2, primary: false), locator(1, primary: true)]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(term: [.text("ALPHA")], locators: [locator(1, primary: false)])
          ]),
      ]),
    IndexBlock.Group(
      anchor: "rfc.index.u87",
      entries: [IndexBlock.Entry(term: [.text("widget")], locators: [locator(1, primary: false)])]),
  ])

  private func built() -> BuiltDocument {
    DocumentTextBuilder.build(Fixtures.document(.index(Self.index)), style: style)
  }

  private func line(containing needle: String, in built: BuiltDocument) throws -> String {
    let text = built.text.string
    let lines = text.components(separatedBy: "\n")
    return try #require(lines.first { $0.contains(needle) })
  }

  @Test func `each group's letter is a line of its own, with no row of letter links`() throws {
    let built = built()
    #expect(try line(containing: "C", in: built) == "C")
    #expect(try line(containing: "W", in: built) == "W")
    #expect(!built.text.string.contains("C W"))
  }

  @Test func `an entry reads as its term, then its locators, the primary first`() throws {
    #expect(try line(containing: "cache", in: built()) == "cache\u{2003}§1, §2")
  }

  @Test func `a heading entry reads as its term alone, and its subentries follow it`() throws {
    let built = built()
    #expect(try line(containing: "Grammar", in: built) == "Grammar")
    #expect(try line(containing: "ALPHA", in: built) == "ALPHA\u{2003}§1")
  }

  @Test func `a locator links to its place in the document`() throws {
    let built = built()
    let offset = try Fixtures.offset(of: "§2", in: built.text)
    let url = try #require(built.text.attribute(.link, at: offset, effectiveRange: nil) as? URL)
    #expect(DocumentTextBuilder.anchor(from: url) == "section-2")
  }

  @Test func `the primary locator is semibold and the others are not`() throws {
    let built = built()
    func weight(of needle: String) throws -> CGFloat {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      let font = try #require(
        built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
      return font.weight.rawValue
    }
    #expect(abs(try weight(of: "§1, ") - PlatformFont.Weight.semibold.rawValue) < 0.05)
    #expect(abs(try weight(of: "§2") - PlatformFont.Weight.regular.rawValue) < 0.05)
  }

  @Test func `an entry hangs its wrapped lines one step in, and a subentry sits one step deeper`()
    throws
  {
    let built = built()
    func paragraph(at needle: String) throws -> NSParagraphStyle {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      return try #require(
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    }
    let entry = try paragraph(at: "cache")
    #expect(entry.firstLineHeadIndent == 0)
    #expect(entry.headIndent == style.indentStep)
    let subentry = try paragraph(at: "ALPHA")
    #expect(subentry.firstLineHeadIndent == style.indentStep)
    #expect(subentry.headIndent == style.indentStep * 2)
  }

  @Test func `a group's letter carries its anchor, as a heading does`() throws {
    let built = built()
    let offset = try #require(built.anchors.offset(of: "rfc.index.u67"))
    #expect(
      built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String
        == "rfc.index.u67")
    #expect(built.anchors.offset(of: IndexBlock.anchor) == offset)
  }

  @Test func `the map records each group's letter and each top-level entry's term`() throws {
    let built = built()
    let map = built.indexMap
    let text = built.text.string as NSString
    #expect(map.groups.map(\.label) == ["C", "W"])
    #expect(map.groups.map(\.anchor) == ["rfc.index.u67", "rfc.index.u87"])
    #expect(map.groups.map { text.substring(with: $0.labelRange) } == ["C", "W"])
    #expect(map.entries.map(\.key) == ["cache", "grammar", "widget"])
    #expect(
      map.entries.map { text.substring(with: $0.termRange) } == ["cache", "Grammar", "widget"])
    #expect(map.range.location == map.groups[0].labelRange.location)
    #expect(NSMaxRange(map.range) == text.length)
  }

  @Test func `a document without an index has an empty map`() {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.paragraph(Paragraph([.text("prose")]))), style: style)
    #expect(built.indexMap.isEmpty)
  }

  @Test func `a key folds case and diacritics`() {
    #expect(IndexMap.key("Échec") == "echec")
  }
}
