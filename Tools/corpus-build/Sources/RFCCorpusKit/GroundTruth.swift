import Foundation
import RFCKit

/// The one ground truth the legacy parser has (#42): from RFC 8650 on, an RFC's
/// text is generated from its XML by xml2rfc, so the XML says what the text's
/// blocks are. `score` parses the text with `LegacyTextParser` and the XML with
/// `RFCXMLParser`, pulls the same kinds of block out of both documents, and counts
/// how many of the XML's the parser found.
///
/// Blocks are compared by content, not by position: the parser keeps no source
/// lines on its blocks, and xml2rfc renders artwork, source code and headings
/// close enough to literally that one normalized text recognizes both.
///
/// A regression floor, not a measure of the legacy corpus: xml2rfc's output is
/// uniform — indent 3, wrapped at 72, never justified, no tabs — and the documents
/// that break the parser have no analogue in it.
public enum GroundTruth {
  public enum Kind: String, CaseIterable, Sendable {
    case artwork
    case sourceCode
    case heading
    /// Artwork and source code alike, matched whatever they were called. Plain text
    /// cannot say what is code, so the parser calls every verbatim block artwork,
    /// and a grammar it kept whole is still a block it got right. The per-kind
    /// scores say what it called the block; this one says whether it found it.
    /// No extracted block has this kind: `score` derives it.
    case verbatim
  }

  /// A block as it is scored: its kind and its normalized content.
  public struct Block: Hashable, Sendable {
    public var kind: Kind
    public var content: String

    public init(kind: Kind, content: String) {
      self.kind = kind
      self.content = content
    }
  }

  /// How the blocks the parser found compare with the ones the XML has. Written
  /// with its precision and recall, so score.json can be read as it is.
  public struct Counts: Encodable, Equatable, Sendable {
    /// In both.
    public var truePositives: Int
    /// Found by the parser, and not in the XML: invented, or split or merged.
    public var falsePositives: Int
    /// In the XML, and not found by the parser.
    public var falseNegatives: Int

    public init(truePositives: Int, falsePositives: Int, falseNegatives: Int) {
      self.truePositives = truePositives
      self.falsePositives = falsePositives
      self.falseNegatives = falseNegatives
    }

    public static let zero = Counts(truePositives: 0, falsePositives: 0, falseNegatives: 0)

    /// Nil when the parser found none.
    public var precision: Double? {
      ratio(truePositives, truePositives + falsePositives)
    }

    /// Nil when the XML has none.
    public var recall: Double? {
      ratio(truePositives, truePositives + falseNegatives)
    }

    /// Every block that is wrong one way or the other.
    public var errors: Int { falsePositives + falseNegatives }

    private func ratio(_ part: Int, _ whole: Int) -> Double? {
      whole == 0 ? nil : Double(part) / Double(whole)
    }

    public static func += (lhs: inout Counts, rhs: Counts) {
      lhs = lhs + rhs
    }

    public static func + (lhs: Counts, rhs: Counts) -> Counts {
      Counts(
        truePositives: lhs.truePositives + rhs.truePositives,
        falsePositives: lhs.falsePositives + rhs.falsePositives,
        falseNegatives: lhs.falseNegatives + rhs.falseNegatives)
    }

    public func encode(to encoder: any Encoder) throws {
      try EncodedCounts(self).encode(to: encoder)
    }
  }

  // MARK: - Extraction

  /// Every heading of `document`, then every artwork and source code block, each
  /// in document order. Scoring does not depend on the order. Artwork with no text
  /// is left out: xml2rfc prints a placeholder for artwork it has only as SVG, so
  /// the text can never hold it.
  public static func blocks(of document: RFCDocument) -> [Block] {
    let headings = document.allSections.map { section in
      Block(
        kind: .heading, content: normalize(number: section.number, title: printed(section.title)))
    }
    let verbatim = document.blocks.compactMap { block -> Block? in
      guard case .preformatted(let content) = block, content.type != "svg" else { return nil }
      let text = normalize(verbatim: content.text)
      guard !text.isEmpty else { return nil }
      let kind: Kind =
        switch content.kind {
        case .artwork: .artwork
        case .sourceCode: .sourceCode
        }
      return Block(kind: kind, content: text)
    }
    return headings + verbatim
  }

  /// A title as xml2rfc prints it: its plain text, except that a superscript is
  /// written `^(8)`.
  private static func printed(_ title: [Inline]) -> String {
    title.map { inline in
      if case .superscript(let text) = inline { "^(\(text))" } else { [inline].plainText }
    }.joined()
  }

  // MARK: - Normalization

  /// Verbatim text as it compares: blank lines and trailing spaces dropped, and the
  /// indentation all its lines share removed, so xml2rfc's three spaces and an
  /// author's own margin compare equal while a diagram keeps its shape. A page
  /// break inside a figure leaves blank lines, which is why those go too. So do the
  /// `<CODE BEGINS>` and `<CODE ENDS>` lines xml2rfc writes around marked source
  /// code, which the element does not hold. Tabs are expanded to eight columns
  /// first, as the parser and xml2rfc both do.
  public static func normalize(verbatim text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        String(String(line).expandingTabs().reversed().drop(while: \.isWhitespace).reversed())
      }
      .filter { !$0.isEmpty }
    if let first = lines.first, first.drop(while: \.isWhitespace).hasPrefix("<CODE BEGINS>") {
      lines.removeFirst()
    }
    if let last = lines.last, last.drop(while: \.isWhitespace) == "<CODE ENDS>" {
      lines.removeLast()
    }
    let margin = lines.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
    return lines.map { String($0.dropFirst(margin)) }.joined(separator: "\n")
  }

  /// A heading as it compares: its number without a trailing dot, which the
  /// legacy text writes and the XML does not, then its title, with every run of
  /// white space one space. A non-breaking hyphen is a hyphen and the invisible
  /// joiners go, as xml2rfc prints them.
  public static func normalize(number: String?, title: String) -> String {
    var parts: [String] = []
    if let number, !number.isEmpty {
      parts.append(number.hasSuffix(".") ? String(number.dropLast()) : number)
    }
    parts.append(
      title.replacingOccurrences(of: "\u{2011}", with: "-")
        .replacingOccurrences(of: "\u{2060}", with: "")
        .replacingOccurrences(of: "\u{200B}", with: ""))
    return parts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(
      separator: " ")
  }

  // MARK: - Scoring

  /// `found` against `expected`, per kind, as multisets: a block found twice and
  /// expected once is one true positive and one false positive. Every kind has an
  /// entry, zero or not, `verbatim` included.
  public static func score(found: [Block], expected: [Block]) -> [Kind: Counts] {
    var counts = match(found: found, expected: expected)
    let asVerbatim = { (blocks: [Block]) in
      blocks.filter { $0.kind != .heading }.map { Block(kind: .verbatim, content: $0.content) }
    }
    counts[.verbatim] = match(found: asVerbatim(found), expected: asVerbatim(expected))[.verbatim]
    return counts
  }

  private static func match(found: [Block], expected: [Block]) -> [Kind: Counts] {
    var counts = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, Counts.zero) })
    var remaining = Dictionary(expected.map { ($0, 1) }, uniquingKeysWith: +)
    for block in found {
      if let left = remaining[block], left > 0 {
        remaining[block] = left - 1
        counts[block.kind]!.truePositives += 1
      } else {
        counts[block.kind]!.falsePositives += 1
      }
    }
    for (block, left) in remaining {
      counts[block.kind]!.falseNegatives += left
    }
    return counts
  }
}

/// `GroundTruth.Counts` as score.json spells it: its counts, and the ratios it
/// computes from them.
private struct EncodedCounts: Encodable {
  var truePositives: Int
  var falsePositives: Int
  var falseNegatives: Int
  var precision: Double?
  var recall: Double?

  init(_ counts: GroundTruth.Counts) {
    truePositives = counts.truePositives
    falsePositives = counts.falsePositives
    falseNegatives = counts.falseNegatives
    precision = counts.precision
    recall = counts.recall
  }
}

/// `corpus/score.json`: the totals per kind, and every document worst first.
/// Kinds are keyed by name, and every one is present, so two runs' files diff
/// line for line.
public struct GroundTruthReport: Encodable, Sendable {
  public struct Document: Encodable, Sendable {
    /// The file stem, `rfc9110`.
    public var document: String
    /// Its headings' errors and its verbatim blocks', so a grammar kept whole as
    /// artwork counts as the block it is, not as a miss and an invention.
    public var errors: Int
    public var kinds: [String: GroundTruth.Counts]
  }

  public var kinds: [String: GroundTruth.Counts]
  public var documents: [Document]

  /// Ranked by errors, most first, and by number where they tie, so the order
  /// is the same from run to run.
  public init(documents scored: [(DocumentID, [GroundTruth.Kind: GroundTruth.Counts])]) {
    var totals = Dictionary(
      uniqueKeysWithValues: GroundTruth.Kind.allCases.map { ($0, GroundTruth.Counts.zero) })
    for (_, counts) in scored {
      for (kind, count) in counts {
        totals[kind, default: .zero] += count
      }
    }
    kinds = Dictionary(uniqueKeysWithValues: totals.map { ($0.key.rawValue, $0.value) })
    var ranked: [(number: Int, document: Document)] = []
    for (id, counts) in scored {
      let errors = [GroundTruth.Kind.heading, .verbatim].compactMap { counts[$0]?.errors }
        .reduce(0, +)
      var byName: [String: GroundTruth.Counts] = [:]
      for (kind, count) in counts { byName[kind.rawValue] = count }
      ranked.append((id.number, Document(document: id.fileStem, errors: errors, kinds: byName)))
    }
    ranked.sort { lhs, rhs in
      if lhs.document.errors != rhs.document.errors {
        return lhs.document.errors > rhs.document.errors
      }
      return lhs.number < rhs.number
    }
    documents = ranked.map(\.document)
  }
}
