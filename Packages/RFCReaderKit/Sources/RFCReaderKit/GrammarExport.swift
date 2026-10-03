import Foundation
import RFCKit

/// A document's grammar collected into one self-contained ABNF file (#185), as RFC
/// 9110's appendix does by hand and most documents do not: every grammar block in
/// document order, each headed by its section, and a closing comment naming what
/// the rules use and do not define.
///
/// RFC 5234's core rules are named and pointed to, not copied in: their definitions
/// are that RFC's text.
public enum GrammarExport {
  /// The file's text, or nil for a document with no grammar.
  public static func text(for document: RFCDocument, hints: ArtworkHints = .bundled) -> String? {
    var blocks: [(heading: String?, text: String)] = []
    for section in document.allSections {
      for block in section.blocks.flattened {
        guard case .preformatted(let content) = block,
          let type = ArtworkClassifier.classify(content, in: document.header.id, hints: hints).type,
          ABNFPresentation.types.contains(type.name),
          ABNF.parse(content.text) != nil
        else { continue }
        blocks.append((heading(of: section), unindented(content.text)))
      }
    }
    guard !blocks.isEmpty else { return nil }

    let grammar = DocumentGrammar(blocks: blocks.map(\.text))
    let rules = blocks.flatMap { ABNF.parse($0.text) ?? [] }
    var core: [String] = []
    var undefined: [String] = []
    for use in rules.flatMap(\.uses) {
      let name = use.name
      guard grammar.target(of: name) != .anchor(ABNFPresentation.anchor(for: name)) else {
        continue
      }
      if ABNFPresentation.coreRules.contains(name.lowercased()) {
        if !core.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
          core.append(name)
        }
      } else if !undefined.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
        undefined.append(name)
      }
    }

    let id = document.header.id.map(\.displayName) ?? document.header.title
    var lines = [
      "; The collected ABNF grammar of \(id), \(document.header.title), in document order."
    ]
    for block in blocks {
      lines.append("")
      if let heading = block.heading { lines.append("; \(heading)") }
      lines.append(block.text.trimmingCharacters(in: .newlines))
    }
    if !core.isEmpty || !undefined.isEmpty { lines.append("") }
    if !core.isEmpty {
      lines.append(
        "; Core rules used, defined in RFC 5234, Appendix B.1: \(core.joined(separator: ", "))")
    }
    if !undefined.isEmpty {
      lines.append(
        "; Used, and defined in none of the blocks above: \(undefined.joined(separator: ", "))")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// `Section 3.1. Title`, or the title alone for a section with no number.
  private static func heading(of section: Section) -> String? {
    let title = section.titleText
    guard let number = section.number, !number.isEmpty else { return title.isEmpty ? nil : title }
    return "Section \(number). \(title)"
  }

  /// The block without the indentation all its lines share: a rule starts at column 0
  /// in an ABNF file, wherever the document set the block.
  private static func unindented(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    let indent =
      lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { $0.prefix { $0 == " " }.count }.min() ?? 0
    return lines.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " }.count))) }
      .joined(separator: "\n")
  }
}
