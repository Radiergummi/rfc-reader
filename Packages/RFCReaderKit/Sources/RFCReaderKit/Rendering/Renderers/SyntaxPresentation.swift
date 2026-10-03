import Foundation
import RFCKit

/// Source code highlighted, for every type a lexer in RFCKit reads (`Lexers`).
enum SyntaxPresentation {
  static let entry = RendererEntry(
    types: Lexers.claimedNames, suffixes: Lexers.claimedSuffixes,
    presentations: [
      Presentation(id: "syntax") { block, classification, _ in
        guard let type = classification.type,
          let tokens = Lexers.highlight(block.text, as: type)
        else { return nil }
        return .styled(tokens)
      }
    ])
}
