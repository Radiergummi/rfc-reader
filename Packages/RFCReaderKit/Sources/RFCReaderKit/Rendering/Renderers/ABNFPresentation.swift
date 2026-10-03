import Foundation
import RFCKit

/// An ABNF grammar with its rule names as links (#185): each rule's definition is an
/// anchor, and each use of a name the document defines links to it, in whichever of
/// the document's grammar blocks it is. RFC 5234's core rules link to its Appendix
/// B.1. A name defined nowhere in the document, as one imported from another, stays
/// plain.
enum ABNFPresentation {
  static let types: Set<String> = ["abnf", "abnf9110"]

  static let entry = RendererEntry(
    types: types,
    presentations: [
      Presentation(id: "abnf-links") { block, _, context in
        render(block.text, grammar: context.grammar)
      }
    ])

  /// The anchor a rule's definition gets: stable, deep-linkable, and named for the
  /// rule as RFC 5234 compares names, without case.
  static func anchor(for name: String) -> String {
    "abnf-" + name.lowercased()
  }

  /// RFC 5234 Appendix B.1, which defines these for every grammar that uses them.
  static let coreRules: Set<String> = [
    "alpha", "bit", "char", "cr", "crlf", "ctl", "digit", "dquote", "hexdig", "htab", "lf",
    "lwsp", "octet", "sp", "vchar", "wsp",
  ]

  static func render(_ text: String, grammar: DocumentGrammar) -> Rendition? {
    guard let rules = ABNF.parse(text) else { return nil }
    var definitions: [LinkedText.Definition] = []
    var links: [LinkedText.Link] = []
    for rule in rules {
      let anchor = anchor(for: rule.name)
      if rule.isIncremental {
        // `=/` adds to a rule defined before it: a use of the name.
        links.append(LinkedText.Link(range: rule.nameRange, target: .anchor(anchor)))
      } else if grammar.definesHere(anchor, in: text, at: rule.nameRange.location) {
        definitions.append(LinkedText.Definition(range: rule.nameRange, anchor: anchor))
      }
      for use in rule.uses {
        guard let target = grammar.target(of: use.name) else { continue }
        links.append(LinkedText.Link(range: use.range, target: target))
      }
    }
    return .linked(LinkedText(definitions: definitions, links: links))
  }
}

/// The rules a document's grammar blocks define, collected over all of them before
/// any is set, so that a use in one block links to a definition in another (#185).
/// The first definition of a name is its anchor; a later one, in error, is not.
public struct DocumentGrammar: Sendable, Equatable {
  /// For each anchor, the block and offset where its name is first defined, and the
  /// rule's lines.
  private var definitions: [String: (block: String, offset: Int, lines: String)] = [:]

  public init() {}

  /// The grammar of `blocks`, the texts of a document's grammar blocks in order.
  public init(blocks: [String]) {
    for block in blocks {
      guard let rules = ABNF.parse(block) else { continue }
      let starts = rules.map(\.nameRange.location)
      for (index, rule) in rules.enumerated() where !rule.isIncremental {
        let anchor = ABNFPresentation.anchor(for: rule.name)
        guard definitions[anchor] == nil else { continue }
        let end = index + 1 < starts.count ? starts[index + 1] : (block as NSString).length
        definitions[anchor] = (
          block, rule.nameRange.location,
          Self.lines(of: block, from: rule.nameRange.location, to: end)
        )
      }
    }
  }

  public static func == (lhs: DocumentGrammar, rhs: DocumentGrammar) -> Bool {
    lhs.definitions.mapValues(\.lines) == rhs.definitions.mapValues(\.lines)
  }

  /// Whether the anchor's definition is the one at `offset` in `block`.
  func definesHere(_ anchor: String, in block: String, at offset: Int) -> Bool {
    guard let definition = definitions[anchor] else { return false }
    return definition.offset == offset && definition.block == block
  }

  /// Where a use of `name` links: the document's own definition, or RFC 5234's for a
  /// core rule; nil for a name defined nowhere.
  func target(of name: String) -> CrossReference.Target? {
    let anchor = ABNFPresentation.anchor(for: name)
    if definitions[anchor] != nil { return .anchor(anchor) }
    if ABNFPresentation.coreRules.contains(name.lowercased()) {
      return .document(.rfc(5234), section: "B.1")
    }
    return nil
  }

  /// The rule's lines, as its block sets them: what a rule link previews.
  public func definition(of anchor: String) -> String? {
    definitions[anchor]?.lines
  }

  /// From the start of the line the rule starts on to the line before the next rule,
  /// without the blank lines and comments that head the next one.
  private static func lines(of block: String, from start: Int, to end: Int) -> String {
    let text = block as NSString
    let first = text.lineRange(for: NSRange(location: start, length: 0)).location
    // The next rule's line starts where this one's lines end; the last rule runs to
    // the end of the block.
    let last =
      end < text.length ? text.lineRange(for: NSRange(location: end, length: 0)).location : end
    var lines = text.substring(with: NSRange(location: first, length: max(0, last - first)))
      .components(separatedBy: "\n")
    while let line = lines.last,
      line.trimmingCharacters(in: .whitespaces).isEmpty
        || line.trimmingCharacters(in: .whitespaces).hasPrefix(";")
    {
      lines.removeLast()
    }
    return lines.joined(separator: "\n")
  }
}
