import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Finding a target again when the text moves (#522), over documents written for each
/// case: relocation takes a model text, never parses one.
@Suite("Annotations: relocation")
struct RelocationTests {
  private func model(_ paragraphs: [Paragraph], subsections: [Section] = []) -> ModelText {
    ModelText(
      RFCDocument(
        header: DocumentHeader(title: "T"),
        sections: [
          Section(
            anchor: "section-1", number: "1", title: "One",
            blocks: paragraphs.map(Block.paragraph), subsections: subsections)
        ], source: .xml))
  }

  private func target(_ needle: String, in model: ModelText) throws -> Target {
    let text = model.text(in: 0..<model.length) as NSString
    let found = text.range(of: needle)
    try #require(found.location != NSNotFound)
    return try #require(
      Target(covering: found.location..<NSMaxRange(found), in: model))
  }

  private func covered(_ relocation: Relocation, in model: ModelText) -> String? {
    relocation.target?.range(in: model).map { model.text(in: $0) }
  }

  @Test func `the same text is exact`() throws {
    let model = model([Paragraph(text: "The client MUST send a request.")])
    let target = try target("MUST send", in: model)
    #expect(Relocator(model).relocate(target) == .exact(target))
  }

  @Test func `a block gaining an anchor re-expresses an exact target under it`() throws {
    let before = model([Paragraph(text: "The client MUST send a request.")])
    let target = try target("MUST send", in: before)
    guard case .range(let start, _, _) = target else { return }
    #expect(start.anchor == "section-1")
    let after = model([Paragraph(text: "The client MUST send a request.", anchor: "section-1-1")])
    let relocation = Relocator(after).relocate(target)
    guard case .exact(.range(let moved, _, _)) = relocation else {
      Issue.record("not exact: \(relocation)")
      return
    }
    #expect(moved == Position(anchor: "section-1-1", offset: 11))
  }

  @Test func `text moved within its section is found there`() throws {
    let before = model([Paragraph(text: "The client MUST send a request to the server.")])
    let target = try target("MUST send a request", in: before)
    let after = model([
      Paragraph(text: "A new opening paragraph."),
      Paragraph(text: "The client MUST send a request to the server."),
    ])
    let relocation = Relocator(after).relocate(target)
    guard case .moved = relocation else {
      Issue.record("not moved: \(relocation)")
      return
    }
    #expect(covered(relocation, in: after) == "MUST send a request")
  }

  @Test func `white space and reference spellings compare as one`() throws {
    let before = model([Paragraph(text: "as defined in [RFC2119] and  used here")])
    let target = try target("defined in [RFC2119] and  used", in: before)
    let after = model([
      Paragraph(text: "Opening."), Paragraph(text: "as defined in RFC\u{00A0}2119 and used here"),
    ])
    let relocation = Relocator(after).relocate(target)
    #expect(covered(relocation, in: after) == "defined in RFC\u{00A0}2119 and used")
  }

  @Test func `a repeated passage is ambiguous`() throws {
    let before = model([Paragraph(text: "The sender MUST NOT retry. Then it stops.")])
    let target = try target("MUST NOT retry", in: before)
    let after = model([
      Paragraph(text: "Opening."),
      Paragraph(text: "The sender MUST NOT retry. Then it stops."),
      Paragraph(text: "The sender MUST NOT retry. Then it stops."),
    ])
    #expect(Relocator(after).relocate(target) == .ambiguous)
  }

  @Test func `text that is gone is detached`() throws {
    let before = model([Paragraph(text: "The client MUST send a request.")])
    let target = try target("MUST send", in: before)
    let after = model([Paragraph(text: "Something else entirely.")])
    #expect(Relocator(after).relocate(target) == .detached)
  }

  @Test func `a short quote needs both its prefix and its suffix`() throws {
    let before = model([Paragraph(text: "alpha beta gamma delta")])
    let target = try target("beta", in: before)
    // The prefix still matches, the suffix does not.
    let after = model([Paragraph(text: "Opening."), Paragraph(text: "alpha beta epsilon")])
    #expect(Relocator(after).relocate(target) == .detached)
  }

  @Test func `a cut quote is found by its start and its digest`() throws {
    let long = (1...40).map { "word\($0)" }.joined(separator: " ")
    let before = model([Paragraph(text: "Start. " + long + " End.")])
    let target = try target(long, in: before)
    guard case .range(_, _, let quote) = target else { return }
    #expect(quote.isCut)
    #expect(quote.exact.count == Quote.exactLimit)
    let after = model([Paragraph(text: "Opening."), Paragraph(text: "Start. " + long + " End.")])
    #expect(covered(Relocator(after).relocate(target), in: after) == long)
    // The same start, a different whole.
    let shorter = long.replacingOccurrences(of: "word40", with: "word99")
    let altered = model([Paragraph(text: "Opening."), Paragraph(text: "Start. " + shorter + " End.")])
    #expect(Relocator(altered).relocate(target) == .detached)
  }

  @Test func `a section target relocates by its anchor alone`() {
    let model = model([Paragraph(text: "Text.")])
    #expect(Relocator(model).relocate(.section("section-1")) == .exact(.section("section-1")))
    #expect(Relocator(model).relocate(.section("section-9")) == .detached)
  }

  @Test func `a soft hyphen and a hyphenated line end are not there`() {
    let normalized = TextNormalization(Array("con\u{00AD}nec-\n   tion  here".utf16))
    #expect(String(decoding: normalized.units, as: UTF16.self) == "connection here")
  }
}
