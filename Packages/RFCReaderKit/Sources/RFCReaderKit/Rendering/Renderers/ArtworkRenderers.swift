import Foundation
import RFCKit

/// One way to show a block. Returns nil to decline, and the next presentation is
/// tried, down to the block's source.
public struct Presentation: Sendable {
  public let id: String
  public let render: @Sendable (Preformatted, ArtworkClassification, RenderContext) -> Rendition?

  public init(
    id: String,
    render: @escaping @Sendable (Preformatted, ArtworkClassification, RenderContext) -> Rendition?
  ) {
    self.id = id
    self.render = render
  }
}

/// The types a renderer claims, and its presentations in order of preference.
public struct RendererEntry: Sendable {
  public let types: Set<String>
  public let presentations: [Presentation]

  public init(types: Set<String>, presentations: [Presentation]) {
    self.types = types
    self.presentations = presentations
  }
}

/// Every renderer, by the canonical types it claims. Adding a format is adding its
/// entry here: Swift has no static self-registration, and one literal is also one
/// place a test can check that no type is claimed twice.
enum ArtworkRenderers {
  static let entries: [RendererEntry] = [
    PacketPresentation.entry,
    ABNFPresentation.entry,
  ]

  static func presentations(for type: ArtworkType?) -> [Presentation] {
    guard let type else { return [] }
    return entries.first { $0.types.contains(type.name) }?.presentations ?? []
  }

  /// The first presentation that accepts the block, or nil: set it as verbatim.
  static func render(
    _ block: Preformatted, _ classification: ArtworkClassification, context: RenderContext
  ) -> Rendition? {
    for presentation in presentations(for: classification.type) {
      if let rendition = presentation.render(block, classification, context) {
        return rendition
      }
    }
    return nil
  }
}
