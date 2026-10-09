import Foundation
import RFCKit

/// An ABNF grammar with its rule names as links (#185): each rule's definition is an
/// anchor, and each use of a name the document defines links to it, in whichever of
/// the document's grammar blocks it is. RFC 5234's core rules link to its Appendix
/// B.1. A name defined nowhere in the document, as one imported from another, stays
/// plain.
enum ABNFPresentation {
  /// `abnf822` is a grammar in the bar dialect, alternating with `|` (#696): its rules
  /// link, and it is no RFC 5234 grammar, so no `.abnf` file takes it.
  static let types: Set<String> = ["abnf", "abnf9110", barDialectType]

  /// The type the legacy parser sets on a grammar in the bar dialect.
  static let barDialectType = "abnf822"

  /// The dialect a block of `type` is written in: the bar dialect's own type says so,
  /// and every other grammar is RFC 5234's.
  static func dialect(ofType type: String?) -> ABNF.Dialect {
    ArtworkType.canonical(type)?.name == barDialectType ? .rfc822 : .rfc5234
  }

  static let entry = RendererEntry(
    types: types,
    presentations: [
      Presentation(id: "abnf-links") { block, _, context in
        render(block.text, dialect: dialect(ofType: block.type), grammar: context.grammar)
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

  static func render(
    _ text: String, dialect: ABNF.Dialect = .rfc5234, grammar: DocumentGrammar
  ) -> Rendition? {
    guard let rules = ABNF.parse(text, dialect: dialect) else { return nil }
    var definitions: [LinkedText.Definition] = []
    var links: [LinkedText.Link] = []
    for rule in rules {
      let anchor = anchor(for: rule.name)
      if rule.isIncremental {
        // `=/` adds to a rule defined before it: a use of the name, which stays plain
        // where the rule is another document's, as `method =/` of RFC 9110's would.
        if let target = grammar.target(of: rule.name) {
          links.append(LinkedText.Link(range: rule.nameRange, target: target))
        }
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
  /// Where a rule's name is first defined, and the rule's lines.
  private struct Definition: Sendable, Equatable {
    var block: String
    var offset: Int
    var lines: String
  }

  /// For each anchor, its first definition.
  private var definitions: [String: Definition] = [:]

  public init() {}

  /// The document's grammar blocks, each with the section it is in (nil for the
  /// abstract), in document order: a block the document or a hint types `abnf`,
  /// `abnf9110` or the bar dialect's `abnf822`. One the reader shows other than as written, folded by RFC 8792 or
  /// set with tabs, is left out: its rules could not be anchored in its own text, and
  /// a link to an anchor that is never set would go nowhere.
  static func blocks(of document: RFCDocument, hints: ArtworkHints)
    -> [(section: Section?, content: Preformatted)]
  {
    let sections: [(Section?, [Block])] =
      [(nil, document.header.abstract)] + document.allSections.map { ($0, $0.blocks) }
    return sections.flatMap { section, blocks in
      blocks.flattened.compactMap { block -> (Section?, Preformatted)? in
        guard case .preformatted(let content) = block,
          let type = ArtworkClassifier.statedType(
            of: content, in: document.header.id, hints: hints),
          ABNFPresentation.types.contains(type.name),
          !content.text.contains("\t"), FoldedLines.strategy(of: content.text) == nil
        else { return nil }
        return (section, content)
      }
    }
  }

  /// The grammar of `document`'s grammar blocks, as the reader shows them: source
  /// code without the indent all its lines share, so a definition's offset is into
  /// the text a block is set as.
  init(of document: RFCDocument, hints: ArtworkHints) {
    self.init(
      blocks: Self.blocks(of: document, hints: hints).map { _, content in
        (
          text: content.kind == .sourceCode
            ? DocumentTextBuilder.removingSharedIndent(content.text) : content.text,
          dialect: ABNFPresentation.dialect(ofType: content.type)
        )
      })
  }

  /// The grammar of `blocks`, the texts of a document's grammar blocks in order, in
  /// RFC 5234's dialect.
  public init(blocks: [String]) {
    self.init(blocks: blocks.map { (text: $0, dialect: ABNF.Dialect.rfc5234) })
  }

  /// The grammar of `blocks`, each in the dialect it is written in.
  init(blocks: [(text: String, dialect: ABNF.Dialect)]) {
    for (block, dialect) in blocks {
      guard let rules = ABNF.parse(block, dialect: dialect) else { continue }
      let starts = rules.map(\.nameRange.location)
      for (index, rule) in rules.enumerated() where !rule.isIncremental {
        let anchor = ABNFPresentation.anchor(for: rule.name)
        guard definitions[anchor] == nil else { continue }
        let end = index + 1 < starts.count ? starts[index + 1] : (block as NSString).length
        definitions[anchor] = Definition(
          block: block, offset: rule.nameRange.location,
          lines: Self.lines(of: block, from: rule.nameRange.location, to: end))
      }
    }
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
