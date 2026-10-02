import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Artwork renderers")
struct ArtworkRenderersTests {
  private let context = RenderContext(style: ReadingStyle(), column: 600)

  @Test func `no type is claimed by two entries`() {
    let claims = ArtworkRenderers.entries.flatMap(\.types)
    #expect(claims.count == Set(claims).count)
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
