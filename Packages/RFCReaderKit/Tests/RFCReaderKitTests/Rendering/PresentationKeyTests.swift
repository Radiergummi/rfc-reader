import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A choice of a block's presentation is keyed by its anchor, so it names the same block
/// in every build of a document; only a block without one falls back to its ordinal.
@Suite("Presentation choices")
struct PresentationKeyTests {
  private func boxes(in text: NSAttributedString) -> [VerbatimBox] {
    var result: [VerbatimBox] = []
    var seen = Set<ObjectIdentifier>()
    text.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      guard let box = value as? VerbatimBox, seen.insert(ObjectIdentifier(box)).inserted else {
        return
      }
      result.append(box)
    }
    return result
  }

  @Test func `an anchored block is keyed by its anchor`() throws {
    let built = DocumentTextBuilder.build(
      try Fixtures.document(named: "rfc9197.xml"), style: ReadingStyle())
    let box = try #require(boxes(in: built.text).first { $0.shown == .rendered })
    let anchor = try #require(box.content.anchor)
    #expect(box.presentationKey == .anchor(anchor))
  }

  @Test func `a block without an anchor is keyed by its ordinal`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle())
    let box = try #require(boxes(in: built.text).first)
    #expect(box.content.anchor == nil)
    #expect(box.presentationKey == .ordinal(0))
  }

  @Test func `an empty anchor is no anchor`() {
    #expect(PresentationKey(anchor: "", ordinal: 3) == .ordinal(3))
    #expect(PresentationKey(anchor: nil, ordinal: 3) == .ordinal(3))
    #expect(PresentationKey(anchor: "section-4.1-2", ordinal: 3) == .anchor("section-4.1-2"))
  }

  @Test func `two builds of a document give the same keys`() throws {
    let document = try Fixtures.document(named: "rfc9197.xml")
    let reader = DocumentTextBuilder.build(document, style: ReadingStyle())
    let printed = DocumentTextBuilder.build(
      document, style: ReadingStyle(emitsLinks: false, references: .plainText))
    let keys = boxes(in: reader.text).map(\.presentationKey)
    #expect(!keys.isEmpty)
    #expect(keys == boxes(in: printed.text).map(\.presentationKey))
  }

  @Test func `a block chosen by its anchor is shown as its source`() throws {
    let document = try Fixtures.document(named: "rfc9197.xml")
    let rendered = DocumentTextBuilder.build(document, style: ReadingStyle())
    let first = try #require(boxes(in: rendered.text).first { $0.shown == .rendered })
    let anchor = try #require(first.content.anchor)
    let source = DocumentTextBuilder.build(
      document, style: ReadingStyle(),
      choices: PresentationChoices(chosen: [.anchor(anchor): .text]))
    let block = try #require(boxes(in: source.text).first { $0.content.anchor == anchor })
    #expect(block.shown == .source)
  }

  /// The reader's preference for every document: a block with a rendering is shown
  /// as its text unless the reader chose otherwise for it.
  @Test func `a document that prefers text shows every rendered block as its text`() throws {
    let document = try Fixtures.document(named: "rfc9197.xml")
    let built = DocumentTextBuilder.build(
      document, style: ReadingStyle(), choices: PresentationChoices(preferred: .text))
    let shown = boxes(in: built.text).map(\.shown)
    #expect(shown.contains(.source))
    #expect(!shown.contains(.rendered))
  }

  @Test func `a block chosen as a figure is drawn where the document prefers text`() throws {
    let document = try Fixtures.document(named: "rfc9197.xml")
    let rendered = DocumentTextBuilder.build(document, style: ReadingStyle())
    let first = try #require(boxes(in: rendered.text).first { $0.shown == .rendered })
    let built = DocumentTextBuilder.build(
      document, style: ReadingStyle(),
      choices: PresentationChoices(preferred: .text, chosen: [first.presentationKey: .figure]))
    let shown = Dictionary(
      uniqueKeysWithValues: boxes(in: built.text).map { ($0.presentationKey, $0.shown) })
    #expect(shown[first.presentationKey] == .rendered)
    #expect(shown.values.filter { $0 == .rendered }.count == 1)
  }

  @Test func `the preference reads as a presentation`() {
    #expect(PresentationChoices(drawsDiagrams: true).preferred == .figure)
    #expect(PresentationChoices(drawsDiagrams: false).preferred == .text)
    #expect(PresentationChoices.defaults.preferred == .figure)
  }
}
