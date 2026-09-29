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
/// close enough to literally that one normalised text recognises both.
///
/// A regression floor, not a measure of the legacy corpus: xml2rfc's output is
/// uniform — indent 3, wrapped at 72, never justified, no tabs — and the documents
/// that break the parser have no analogue in it.
public enum GroundTruth {
  public enum Kind: String, Codable, CaseIterable, Sendable, Comparable {
    case artwork
    case sourceCode
    case heading

    public static func < (lhs: Kind, rhs: Kind) -> Bool {
      allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
  }

  /// A block as it is scored: its kind and its normalised content.
  public struct Block: Hashable, Sendable {
    public var kind: Kind
    public var content: String

    public init(kind: Kind, content: String) {
      self.kind = kind
      self.content = content
    }
  }

  /// How the blocks the parser found compare with the ones the XML has.
  public struct Counts: Codable, Equatable, Sendable {
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

    /// Every block that is wrong one way or the other: how to rank documents.
    public var errors: Int { falsePositives + falseNegatives }

    private func ratio(_ part: Int, _ whole: Int) -> Double? {
      whole == 0 ? nil : Double(part) / Double(whole)
    }

    public static func + (lhs: Counts, rhs: Counts) -> Counts {
      Counts(
        truePositives: lhs.truePositives + rhs.truePositives,
        falsePositives: lhs.falsePositives + rhs.falsePositives,
        falseNegatives: lhs.falseNegatives + rhs.falseNegatives)
    }
  }

  // MARK: - Extraction

  /// Every heading, artwork and source code block of `document`, in document
  /// order: each section's heading, then its blocks, nested ones included, then its
  /// subsections. The abstract has no heading of its own.
  public static func blocks(of document: RFCDocument) -> [Block] {
    var blocks = verbatim(in: document.header.abstract)
    for section in document.allSections {
      blocks.append(
        Block(kind: .heading, content: normalize(number: section.number, title: section.titleText)))
      blocks += verbatim(in: section.blocks)
    }
    return blocks
  }

  private static func verbatim(in blocks: [RFCKit.Block]) -> [Block] {
    blocks.flattened.compactMap { block in
      guard case .preformatted(let content) = block else { return nil }
      let kind: Kind =
        switch content.kind {
        case .artwork: .artwork
        case .sourceCode: .sourceCode
        }
      return Block(kind: kind, content: normalize(verbatim: content.text))
    }
  }

  // MARK: - Normalisation

  /// Verbatim text as it compares: blank lines and trailing spaces dropped, and the
  /// indentation all its lines share removed, so xml2rfc's three spaces and an
  /// author's own margin compare equal while a diagram keeps its shape. A page
  /// break inside a figure leaves blank lines, which is why those go too.
  public static func normalize(verbatim text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in String(line.reversed().drop(while: \.isWhitespace).reversed()) }
      .filter { !$0.isEmpty }
    let margin = lines.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
    return lines.map { String($0.dropFirst(margin)) }.joined(separator: "\n")
  }

  /// A heading as it compares: its number without a trailing dot, which the
  /// legacy text writes and the XML does not, then its title, with every run of
  /// white space one space.
  public static func normalize(number: String?, title: String) -> String {
    var parts: [String] = []
    if let number, !number.isEmpty {
      parts.append(number.hasSuffix(".") ? String(number.dropLast()) : number)
    }
    parts.append(title)
    return parts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(
      separator: " ")
  }

  // MARK: - Scoring

  /// `found` against `expected`, per kind, as multisets: a block found twice and
  /// expected once is one true positive and one false positive. Every kind has an
  /// entry, zero or not.
  public static func score(found: [Block], expected: [Block]) -> [Kind: Counts] {
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
