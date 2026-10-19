import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A redline: the newer revision, with what changed since the older marked in the one
/// text storage (#729). Over model values written by hand in a draft's shape.
@Suite("Builder redline")
struct BuilderRedlineTests {
  private func document(_ sections: [Section]) -> RFCDocument {
    RFCDocument(header: DocumentHeader(title: "An Example"), sections: sections, source: .xml)
  }

  private func section(_ anchor: String, _ blocks: [Block]) -> Section {
    Section(anchor: anchor, number: "1", title: "Introduction", blocks: blocks)
  }

  private func paragraph(_ text: String, anchor: String? = nil) -> Block {
    .paragraph(Paragraph(text: text, anchor: anchor))
  }

  private func redline(from old: [Section], to new: [Section]) -> BuiltDocument {
    let newer = document(new)
    return DocumentTextBuilder.build(
      newer, redline: RevisionDiff(from: document(old), to: newer), style: ReadingStyle())
  }

  private func attribute(
    _ key: NSAttributedString.Key, at needle: String, in built: BuiltDocument
  ) throws -> Any? {
    built.text.attribute(
      key, at: try Fixtures.offset(of: needle, in: built.text), effectiveRange: nil)
  }

  private let unchanged = "This document describes an example protocol for testing."

  @Test func `a word replaced is struck through, and its replacement underlined`() throws {
    let built = redline(
      from: [section("intro", [paragraph(unchanged), paragraph("A client MAY retry.")])],
      to: [section("intro", [paragraph(unchanged), paragraph("A client SHOULD retry.")])])
    #expect(try attribute(.strikethroughStyle, at: "MAY", in: built) != nil)
    #expect(try attribute(.rfcReaderOnly, at: "MAY", in: built) != nil)
    #expect(try attribute(.underlineStyle, at: "SHOULD", in: built) != nil)
    #expect(try attribute(.underlineStyle, at: "client", in: built) == nil)
    #expect(try attribute(.strikethroughStyle, at: "example", in: built) == nil)
    #expect(built.isRedline)
  }

  /// Copy gives the newer text: what was deleted is the reader's to show.
  @Test func `a copy of a redline is the newer text`() {
    let built = redline(
      from: [section("intro", [paragraph("A client MAY retry.")])],
      to: [section("intro", [paragraph("A client SHOULD retry.")])])
    let copied = SelectionText.plainText(of: built.text)
    #expect(copied.contains("A client SHOULD retry."))
    #expect(!copied.contains("MAY"))
  }

  /// A removed block may share an anchor with the newer document; only the newer
  /// one's is in the index.
  @Test func `a removed block is struck through, and its anchor is not indexed`() throws {
    let built = redline(
      from: [
        section(
          "intro",
          [
            paragraph(unchanged, anchor: "p1"),
            paragraph("A paragraph that the newer revision dropped.", anchor: "p2"),
          ])
      ],
      to: [section("intro", [paragraph(unchanged, anchor: "p1")])])
    #expect(try attribute(.strikethroughStyle, at: "dropped", in: built) != nil)
    #expect(built.anchors.offset(of: "p2") == nil)
    #expect(built.anchors.offset(of: "p1") != nil)
  }

  @Test func `a section added says so, and one removed is struck through`() throws {
    let intro = section("intro", [paragraph(unchanged)])
    let gone = Section(
      anchor: "history", number: "2", title: "History",
      blocks: [paragraph("Earlier versions of this protocol were never deployed widely.")])
    let added = Section(
      anchor: "security", number: "2", title: "Security Considerations",
      blocks: [paragraph("Implementations need to authenticate every peer they accept.")])
    let built = redline(from: [intro, gone], to: [intro, added])
    #expect(built.text.string.contains("Added in this revision"))
    #expect(built.text.string.contains("Removed in this revision"))
    #expect(try attribute(.strikethroughStyle, at: "never deployed", in: built) != nil)
    #expect(try attribute(.strikethroughStyle, at: "History", in: built) != nil)
    #expect(built.anchors.offset(of: "history") == nil)
    #expect(built.anchors.offset(of: "security") != nil)
  }

  /// The redline is the reader's one text storage, held to its rules.
  @Test func `nothing in a redline becomes an attachment`() {
    let figure = Block.preformatted(Preformatted(kind: .artwork, text: "+---+\n| A |\n+---+"))
    let built = redline(
      from: [section("intro", [paragraph(unchanged), figure])],
      to: [section("intro", [paragraph(unchanged), paragraph("A new paragraph.")])])
    var attachments = 0
    built.text.enumerateAttribute(
      .attachment, in: NSRange(location: 0, length: built.text.length)
    ) { value, _, _ in
      if value != nil { attachments += 1 }
    }
    #expect(attachments == 0)
  }

  /// A word struck through and its replacement are set apart, by a space a copy
  /// leaves out.
  @Test func `a deletion and its replacement do not run together`() {
    let built = redline(
      from: [section("intro", [paragraph("The server closes the connection.")])],
      to: [section("intro", [paragraph("The server closes it.")])])
    #expect(built.text.string.contains("the connection. it."))
    #expect(SelectionText.plainText(of: built.text).contains("The server closes it."))
  }

  /// A removed figure takes no ordinal from the newer document's, whose choices
  /// and openings are keyed by them.
  @Test func `a removed block leaves the newer blocks' ordinals as they were`() {
    let figure = { (text: String) in
      Block.preformatted(Preformatted(kind: .artwork, text: text))
    }
    let kept = figure("+---+\n| B |\n+---+")
    let plain = DocumentTextBuilder.build(
      document([section("intro", [paragraph(unchanged), kept])]), style: ReadingStyle())
    let built = redline(
      from: [section("intro", [figure("+---+\n| A |\n+---+"), paragraph(unchanged), kept])],
      to: [section("intro", [paragraph(unchanged), kept])])
    func ordinals(_ built: BuiltDocument) -> [Int] {
      var found: [Int] = []
      built.text.enumerateAttribute(
        .rfcVerbatim, in: NSRange(location: 0, length: built.text.length)
      ) { value, _, _ in
        if let box = value as? VerbatimBox, found.last != box.ordinal { found.append(box.ordinal) }
      }
      return found
    }
    #expect(ordinals(built).last == ordinals(plain).last)
  }
}
