import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// RFC 9197, a committed fixture, carries packet diagrams the recognizer claims.
@Suite("Builder: rendered artwork")
struct BuilderRendererTests {
  private let style = ReadingStyle()

  private func document() throws -> RFCDocument {
    try Fixtures.document(named: "rfc9197.xml")
  }

  /// Every verbatim block's box and its whole extent, in order.
  private func blocks(in text: NSAttributedString) -> [(box: VerbatimBox, range: NSRange)] {
    var result: [(box: VerbatimBox, range: NSRange)] = []
    var seen = Set<ObjectIdentifier>()
    text.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let box = value as? VerbatimBox, seen.insert(ObjectIdentifier(box)).inserted,
        let extent = text.extent(ofBox: .rfcVerbatim, at: range.location)
      else { return }
      result.append((box, extent))
    }
    return result
  }

  private func hiddenCharacters(in range: NSRange, of text: NSAttributedString) -> String {
    var hidden = ""
    text.enumerateAttribute(.foregroundColor, in: range) { value, piece, _ in
      guard let color = value as? PlatformColor, color == DocumentTextBuilder.hiddenColor else {
        return
      }
      hidden += (text.string as NSString).substring(with: piece)
    }
    return hidden
  }

  @Test func `a packet diagram is rendered with strokes over its hidden borders`() throws {
    let built = DocumentTextBuilder.build(try document(), style: style)
    let rendered = blocks(in: built.text).filter { $0.box.shown == .rendered }
    #expect(!rendered.isEmpty, "RFC 9197 has packet diagrams")
    for (box, range) in rendered {
      #expect(box.classification.type?.name == "packet")
      let strokes = built.text.attribute(.rfcStrokes, at: range.location, effectiveRange: nil)
      #expect((strokes as? StrokeBox)?.strokes.isEmpty == false)
      let hidden = hiddenCharacters(in: range, of: built.text)
      #expect(!hidden.isEmpty)
      #expect(hidden.allSatisfy { "+-=|~:/\\.".contains($0) }, "hid \(hidden)")
    }
  }

  @Test func `blocks are numbered in the order they are set`() throws {
    let built = DocumentTextBuilder.build(try document(), style: style)
    let ordinals = blocks(in: built.text).map(\.box.ordinal)
    #expect(ordinals == Array(0..<ordinals.count))
  }

  @Test func `showing a block's source keeps its text and drops its decoration`() throws {
    let document = try document()
    let rendered = DocumentTextBuilder.build(document, style: style)
    let first = try #require(blocks(in: rendered.text).first { $0.box.shown == .rendered })
    let source = DocumentTextBuilder.build(
      document, style: style,
      choices: PresentationChoices(shownAsSource: [first.box.presentationKey]))
    #expect(source.text.string == rendered.text.string)
    let block = try #require(blocks(in: source.text).first { $0.box.ordinal == first.box.ordinal })
    #expect(block.box.shown == .source)
    #expect(
      source.text.attribute(.rfcStrokes, at: block.range.location, effectiveRange: nil) == nil)
    #expect(hiddenCharacters(in: block.range, of: source.text).isEmpty)
  }

  @Test func `a hint of none sets a packet diagram as plain verbatim`() throws {
    let document = try document()
    let id = try #require(document.header.id)
    let rendered = DocumentTextBuilder.build(document, style: style)
    let first = try #require(blocks(in: rendered.text).first { $0.box.shown == .rendered })
    let anchor = try #require(first.box.content.anchor)
    let hinted = DocumentTextBuilder.build(
      document, style: style, hints: ArtworkHints([.init(document: id, anchor: anchor): .none]))
    let block = try #require(blocks(in: hinted.text).first { $0.box.ordinal == first.box.ordinal })
    #expect(block.box.shown == .plain)
    #expect(hiddenCharacters(in: block.range, of: hinted.text).isEmpty)
  }

  @Test func `a packet hint on art the recognizer declines falls back to plain verbatim`() throws {
    let document = try document()
    let id = try #require(document.header.id)
    let plain = try #require(
      blocks(in: DocumentTextBuilder.build(document, style: style).text).first {
        $0.box.shown == .plain && $0.box.content.kind == .artwork && $0.box.content.anchor != nil
      })
    let anchor = try #require(plain.box.content.anchor)
    let hinted = DocumentTextBuilder.build(
      document, style: style,
      hints: ArtworkHints([.init(document: id, anchor: anchor): .type("packet")]))
    let block = try #require(blocks(in: hinted.text).first { $0.box.ordinal == plain.box.ordinal })
    #expect(block.box.shown == .plain)
    #expect(
      hinted.text.attribute(.rfcStrokes, at: block.range.location, effectiveRange: nil) == nil)
  }
}
