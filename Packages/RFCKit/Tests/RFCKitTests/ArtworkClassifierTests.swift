import Foundation
import Testing

@testable import RFCKit

/// Which renderer a verbatim block goes to is decided here and nowhere else. The
/// diagrams are hand-written in the shape of an RFC's, not quoted from one.
@Suite("Artwork classification")
struct ArtworkClassifierTests {
  private static let packet = [
    "    0                   1",
    "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
    "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
    "   |     Type      |    Length     |",
    "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
  ].joined(separator: "\n")

  private let document = DocumentID.rfc(9999)

  private func classify(
    _ block: Preformatted, hints: ArtworkHints = .empty, in document: DocumentID? = .rfc(9999)
  ) -> String? {
    ArtworkClassifier.classify(block, in: document, hints: hints).type?.name
  }

  @Test func `a declared type is lowercased and loses its parameters`() {
    #expect(
      ArtworkType.canonical(#"Message/HTTP; msgtype="request""#)
        == ArtworkType(name: "message/http", parameters: ["msgtype": "request"]))
  }

  @Test(arguments: [nil, "", "ascii-art", "ASCII-Art", "drawing", "ascii", "text", "plain", "none"])
  func `a generic type is no type`(declared: String?) {
    #expect(ArtworkType.canonical(declared) == nil)
  }

  @Test func `a known alias is spelled the canonical way`() {
    #expect(ArtworkType.canonical("CBORdiag")?.name == "cbor-diag")
  }

  @Test(arguments: [
    ("application/problem+json", "json"), ("sdf+json", "json"), ("application/atom+xml", "xml"),
  ])
  func `a structured suffix is read from the type`(declared: String, suffix: String) {
    #expect(ArtworkType.canonical(declared)?.suffix == suffix)
  }

  @Test(arguments: ["json", "cbor-diag", "message/http", "a+"])
  func `a type without a suffix has none`(declared: String) {
    #expect(ArtworkType.canonical(declared)?.suffix == nil)
  }

  @Test func `untyped packet art is classified as a packet`() {
    #expect(classify(Preformatted(kind: .artwork, text: Self.packet)) == "packet")
    #expect(
      classify(Preformatted(kind: .artwork, text: Self.packet, type: "ascii-art")) == "packet")
  }

  @Test func `a declared type wins over the recognizer`() {
    #expect(
      classify(Preformatted(kind: .artwork, text: Self.packet, type: "call-flow")) == "call-flow")
  }

  @Test func `source code is never recognized as a packet`() {
    #expect(classify(Preformatted(kind: .sourceCode, text: Self.packet)) == nil)
  }

  @Test func `a hint names the type of untyped art`() {
    let block = Preformatted(
      kind: .artwork, text: "a -> b", type: "ascii-art", anchor: "section-2-3")
    let hints = ArtworkHints([
      .init(document: document, anchor: "section-2-3"): .type("state-machine")
    ])
    #expect(classify(block, hints: hints) == "state-machine")
  }

  @Test func `a hint does not override a declared type`() {
    let block = Preformatted(kind: .sourceCode, text: "x = y", type: "abnf", anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: document, anchor: "section-2-3"): .type("json")])
    #expect(classify(block, hints: hints) == "abnf")
  }

  @Test func `a hint of none leaves a packet diagram unclassified`() {
    let block = Preformatted(kind: .artwork, text: Self.packet, anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: document, anchor: "section-2-3"): .none])
    #expect(classify(block, hints: hints) == nil)
  }

  @Test func `a hint for another document does not apply`() {
    let block = Preformatted(kind: .artwork, text: Self.packet, anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: .rfc(1), anchor: "section-2-3"): .none])
    #expect(classify(block, hints: hints) == "packet")
  }

  @Test func `a block without an anchor takes no hint`() {
    let hints = ArtworkHints([.init(document: document, anchor: ""): .none])
    #expect(classify(Preformatted(kind: .artwork, text: Self.packet), hints: hints) == "packet")
  }
}
