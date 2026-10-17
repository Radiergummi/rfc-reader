import Foundation
import RFCKit

/// A translated document (#749): the original's model with its prose replaced, and
/// nothing else. Its sections, blocks and anchors are the original's, so it is built
/// by the same builder and the contents, deep links, reading positions and Find all
/// keep working on it.
///
/// What is translated is what a reader reads as prose: paragraphs, list items,
/// definitions and their terms, table cells, quotations, asides, section titles, and
/// figure and table titles. What is set as typed is not: artwork, source code and
/// grammars, the bibliography, the index, and the header, whose title and authors
/// are names.
///
/// Each run of prose is translated whole, as plain text, so its grammar is the
/// translation's own. What was a link in it, a cross reference, inline code or a web
/// link, is linked again where its words turn up in the translation: as they were,
/// as "RFC 9110" and "[HTTP]" usually do, or, for a reference written in words like
/// "Section 4", as that label's own translation. One whose words turn up neither way
/// is plain text in the translation, rather than a link on the wrong words. Emphasis
/// is lost.
public enum DocumentTranslation {
  /// Every string a translation of `document` is asked for, once each, in document
  /// order: each run of prose, each caption, and the label of each reference written
  /// in words.
  public static func sources(in document: RFCDocument) -> [String] {
    var seen: Set<String> = []
    var sources: [String] = []
    _ = Rewriter { source in
      if seen.insert(source).inserted { sources.append(source) }
      return source
    }
    .document(document)
    return sources
  }

  /// `document` with every source `translations` has a translation of replaced by
  /// it. A source it lacks stays as it was.
  public static func translated(
    _ document: RFCDocument, _ translations: [String: String]
  ) -> RFCDocument {
    Rewriter { translations[$0] ?? $0 }.document(document)
  }

  /// What a translation of `document` still has to ask for, with `known` already
  /// translated: its sources and the builder's labels, once each, in that order.
  public static func missing(in document: RFCDocument, known: [String: String]) -> [String] {
    var seen: Set<String> = []
    return (sources(in: document) + DocumentLabels.sources).filter {
      known[$0] == nil && seen.insert($0).inserted
    }
  }

  /// The same, over blocks.
  static func translated(blocks: [Block], _ translations: [String: String]) -> [Block] {
    Rewriter { translations[$0] ?? $0 }.blocks(blocks)
  }
}

/// A document as a translation gave it (#749): its model, and the labels the
/// builder writes into it.
public struct TranslatedDocument: Sendable, Equatable {
  public let document: RFCDocument
  public let labels: DocumentLabels

  /// `original` translated by `translations`, which carry the labels' translations
  /// beside the prose's.
  public init(_ original: RFCDocument, _ translations: [String: String]) {
    document = DocumentTranslation.translated(original, translations)
    labels = DocumentLabels(translating: translations)
  }
}

/// One walk over the model that replaces each string of prose by what `translate`
/// makes of it. `DocumentTranslation.sources` walks it with a `translate` that only
/// records, so what is asked for and what is replaced cannot disagree.
private struct Rewriter {
  let translate: (String) -> String

  func document(_ document: RFCDocument) -> RFCDocument {
    var document = document
    document.header.abstract = blocks(document.header.abstract)
    document.sections = document.sections.map(section)
    return document
  }

  /// A heading's qualifier, "(Normative)", is translated with its title, as the
  /// reader shows them together, and so is no longer a qualifier of its own.
  func section(_ section: Section) -> Section {
    var section = section
    let words = section.headingWords
    let title = inlines(words)
    if title != words {
      section.title = title
      section.qualifier = nil
    }
    section.blocks = blocks(section.blocks)
    section.subsections = section.subsections.map(self.section)
    return section
  }

  func blocks(_ blocks: [Block]) -> [Block] {
    blocks.map(block)
  }

  func block(_ block: Block) -> Block {
    switch block {
    case .paragraph(var paragraph):
      paragraph.inlines = inlines(paragraph.inlines)
      return .paragraph(paragraph)
    case .list(var list):
      list.items = list.items.map { item in
        var item = item
        item.blocks = blocks(item.blocks)
        return item
      }
      return .list(list)
    case .definitionList(var list):
      list.items = list.items.map { item in
        var item = item
        item.term = inlines(item.term)
        item.definition = blocks(item.definition)
        return item
      }
      return .definitionList(list)
    case .figure(var figure):
      figure.title = figure.title.map(text)
      figure.blocks = blocks(figure.blocks)
      return .figure(figure)
    case .table(var table):
      table.title = table.title.map(text)
      table.header = table.header.map(row)
      table.rows = table.rows.map(row)
      return .table(table)
    case .blockQuote(let inner):
      return .blockQuote(blocks(inner))
    case .aside(let inner):
      return .aside(aside(inner))
    case .preformatted, .references, .index:
      return block
    }
  }

  func row(_ row: Table.Row) -> Table.Row {
    var row = row
    row.cells = row.cells.map(inlines)
    return row
  }

  /// An aside's "Note:" is the builder's to take for its caption, which the
  /// translated labels name, so it stays as it is ahead of the translated rest.
  func aside(_ inner: [Block]) -> [Block] {
    let labeled = DocumentTextBuilder.labeledAside(inner)
    guard labeled.blocks != inner else { return blocks(inner) }
    let label = labeled.caption + ":"
    var translated = blocks(labeled.blocks)
    if labeled.blocks.count < inner.count {
      return [.paragraph(Paragraph(text: label, anchor: labeled.anchor))] + translated
    }
    guard case .paragraph(var first) = translated.first else { return translated }
    if case .text(let words)? = first.inlines.first {
      first.inlines[0] = .text(label + " " + words)
    } else {
      first.inlines.insert(.text(label + " "), at: 0)
    }
    translated[0] = .paragraph(first)
    return translated
  }

  /// A caption, which the model keeps as a plain string.
  func text(_ text: String) -> String {
    Self.isProse(text) ? translate(text) : text
  }

  /// A run of prose, translated whole and linked again (`Relinking`).
  func inlines(_ inlines: [Inline]) -> [Inline] {
    let source = inlines.plainText
    guard Self.isProse(source) else { return inlines }
    // Before the run itself, so the labels are asked for even where the run is not
    // translated.
    let keepers = keepers(in: inlines)
    let translated = translate(source)
    guard translated != source else { return inlines }
    return Relinking.inlines(translated, keeping: keepers)
  }

  /// What may be linked again in a translation of `inlines`, in order.
  func keepers(in inlines: [Inline]) -> [Relinking.Keeper] {
    inlines.flatMap { inline -> [Relinking.Keeper] in
      switch inline {
      case .crossReference(let reference):
        let display = reference.display
        guard !display.text.isEmpty else { return [] }
        var keeper = Relinking.Keeper(inline: inline, words: display.text)
        if !display.isChip, Self.isProse(display.text) {
          let translated = translate(display.text)
          if translated != display.text {
            var relabeled = reference
            relabeled.text = translated
            keeper.translation = (translated, .crossReference(relabeled))
          }
        }
        return [keeper]
      case .code(let code):
        return code.isEmpty ? [] : [Relinking.Keeper(inline: inline, words: code)]
      case .link(let url, let inner):
        let words = inner.plainText
        return words.isEmpty
          ? [] : [Relinking.Keeper(inline: .link(url, [.text(words)]), words: words)]
      case .emphasis(let inner), .strong(let inner):
        return keepers(in: inner)
      case .text, .superscript, .subscript, .lineBreak:
        return []
      }
    }
  }

  /// Whether `text` has words to translate: a run of digits and punctuation, a
  /// table cell's "0x01", does not.
  static func isProse(_ text: String) -> Bool {
    text.contains { $0.isLetter }
  }
}

/// Puts what was linked in a run of prose back into its translation.
enum Relinking {
  /// Something linked in the original run, and the words it is found by.
  struct Keeper {
    var inline: Inline
    var words: String
    /// For a reference written in words: what those words were translated as on
    /// their own, and the reference relabeled with them.
    var translation: (words: String, inline: Inline)?
  }

  /// `translated` as inlines: each keeper where its words are found, in order and
  /// after the one found before it, and plain text around them. A keeper not found
  /// is left out, and its words, if the translation kept any, stay plain text.
  static func inlines(_ translated: String, keeping keepers: [Keeper]) -> [Inline] {
    var result: [Inline] = []
    var cursor = translated.startIndex
    for keeper in keepers {
      let found =
        range(of: keeper.words, in: translated, from: cursor).map { ($0, keeper.inline) }
        ?? keeper.translation.flatMap { translation in
          range(of: translation.words, in: translated, from: cursor).map {
            ($0, translation.inline)
          }
        }
      guard let (range, inline) = found else { continue }
      result += text(translated[cursor..<range.lowerBound])
      result.append(inline)
      cursor = range.upperBound
    }
    result += text(translated[cursor...])
    return result
  }

  /// `words` in `text` at or after `start`, as a whole: not the "RFC 1" of "RFC 12".
  /// A no-break space in `words`, which a citation's label has between its name and
  /// number, matches an ordinary one, which a translation may have made of it.
  static func range(
    of words: String, in text: String, from start: String.Index
  ) -> Range<String.Index>? {
    let spaced = words.replacing("\u{00A0}", with: " ")
    for spelling in spaced == words ? [words] : [words, spaced] {
      var from = start
      while let found = text.range(of: spelling, range: from..<text.endIndex) {
        let before =
          found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : nil
        let after = found.upperBound < text.endIndex ? text[found.upperBound] : nil
        let startsWord = spelling.first.map(isWordCharacter) ?? false
        let endsWord = spelling.last.map(isWordCharacter) ?? false
        if !(startsWord && before.map(isWordCharacter) == true)
          && !(endsWord && after.map(isWordCharacter) == true)
        {
          return found
        }
        from = text.index(after: found.lowerBound)
      }
    }
    return nil
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }

  /// Plain text, with each line break the translation kept a line break again.
  private static func text(_ text: Substring) -> [Inline] {
    guard !text.isEmpty else { return [] }
    var result: [Inline] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      if index > 0 { result.append(.lineBreak) }
      if !line.isEmpty { result.append(.text(String(line))) }
    }
    return result
  }
}
