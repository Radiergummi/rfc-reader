import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Artwork renderers")
struct ArtworkRenderersTests {
  private let context = RenderContext(style: ReadingStyle(), column: 600)

  @Test func `no type and no suffix is claimed by two entries`() {
    let names = ArtworkRenderers.entries.flatMap(\.types)
    #expect(names.count == Set(names).count)
    let suffixes = ArtworkRenderers.entries.flatMap(\.suffixes)
    #expect(suffixes.count == Set(suffixes).count)
  }

  @Test func `a JSON block is rendered as styled text`() throws {
    let block = Preformatted(kind: .sourceCode, text: #"{"a": 1}"#, type: "json")
    let classification = ArtworkClassification(type: ArtworkType.canonical("json"))
    #expect(ArtworkRenderers.presentations(for: classification.type).map(\.id) == ["syntax"])
    let rendition = try #require(ArtworkRenderers.render(block, classification, context: context))
    guard case .styled(let tokens) = rendition else {
      Issue.record("expected styled text, got \(rendition)")
      return
    }
    #expect(tokens.contains { $0.kind == .name })
  }

  @Test func `a type is claimed by its structured suffix`() {
    let type = ArtworkType.canonical("application/problem+json")
    #expect(ArtworkRenderers.presentations(for: type).map(\.id) == ["syntax"])
  }

  @Test func `a block over the size limit is declined`() {
    let text = String(repeating: " ", count: Lexers.sizeLimit + 1)
    let block = Preformatted(kind: .sourceCode, text: text, type: "json")
    let classification = ArtworkClassification(type: ArtworkType.canonical("json"))
    #expect(ArtworkRenderers.render(block, classification, context: context) == nil)
  }

  @Test func `a packet classification is rendered by the packet grid`() {
    let block = Preformatted(kind: .artwork, text: PacketSamples.variable)
    let packet = ArtworkClassification(type: ArtworkType(name: "packet"))
    #expect(ArtworkRenderers.presentations(for: packet.type).map(\.id) == ["packet-grid"])
    #expect(ArtworkRenderers.render(block, packet, context: context) != nil)
  }

  @Test func `an unclassified block has no presentation`() {
    let block = Preformatted(kind: .artwork, text: PacketSamples.variable)
    #expect(ArtworkRenderers.render(block, .unclassified, context: context) == nil)
  }
}
