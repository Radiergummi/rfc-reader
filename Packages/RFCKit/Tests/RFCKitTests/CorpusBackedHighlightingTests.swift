import Foundation
import Testing

@testable import RFCKit

/// Every block the highlighters claim, in documents chosen for what they hold: RFC
/// 9110's HTTP without bodies, RFC 9457's problem+json and problem+xml bodies, RFC
/// 8927's valid JSON, RFC 8727's 53 KB JSON block, RFC 9635's invalid and folded
/// JSON and odd HTTP, RFC 9022's fragmentary XML, RFC 8935's indented HTTP. Each
/// block is lexed as published and, where RFC 8792 folded it, unfolded, as the
/// reader shows it in a wide column.
@Suite("Corpus-backed: syntax highlighting", .enabled(if: CorpusText.isXMLAvailable))
struct CorpusBackedHighlightingTests {
  static let documents = [
    "rfc9110", "rfc9457", "rfc8927", "rfc8727", "rfc9635", "rfc9022", "rfc8935",
  ]

  struct Sample {
    let place: String
    let language: Lexers.Language
    let type: ArtworkType
    let text: String
  }

  static func samples(_ stem: String) throws -> [Sample] {
    let document = try RFCXMLParser.parse(try CorpusText.xml(stem))
    return document.blocks.flatMap { block -> [Sample] in
      guard case .preformatted(let content) = block,
        let type = ArtworkType.canonical(content.type),
        let language = Lexers.language(of: type)
      else { return [] }
      let place = "\(stem) \(content.anchor ?? "(no anchor)")"
      let texts = [content.text] + [FoldedLines.unfold(content.text)].compactMap { $0 }
      return texts.map { Sample(place: place, language: language, type: type, text: $0) }
    }
  }

  private static func nonWhitespace(_ text: String) -> Int {
    text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
  }

  private static func firstLine(of text: String) -> String {
    text.split(separator: "\n").first { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? ""
  }

  @Test(arguments: documents)
  func `every block is covered exactly once`(stem: String) throws {
    let samples = try Self.samples(stem)
    #expect(!samples.isEmpty, "\(stem) has no block to highlight")
    for sample in samples {
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type), "\(sample.place)")
      #expect(tokens.cover(sample.text), "\(sample.place)")
    }
  }

  @Test(arguments: documents)
  func `no block takes long`(stem: String) throws {
    for sample in try Self.samples(stem) {
      let elapsed = ContinuousClock().measure {
        _ = Lexers.highlight(sample.text, as: sample.type)
      }
      #expect(elapsed < .milliseconds(500), "\(sample.place) took \(elapsed)")
    }
  }

  @Test(arguments: documents)
  func `a block that parses as JSON leaves nothing plain but white space`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language == .json {
      let parsed = try? JSONSerialization.jsonObject(
        with: Data(sample.text.utf8), options: .fragmentsAllowed)
      guard parsed != nil else { continue }
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      let plain = tokens.text(of: .plain, in: sample.text)
      #expect(
        plain.allSatisfy { Self.nonWhitespace($0) == 0 }, "\(sample.place): \(plain.prefix(3))")
    }
  }

  /// Past an RFC 8792 fold, a backslash at the end of the line, a string goes on.
  @Test(arguments: documents)
  func `no JSON string or XML value runs past its line unless folded`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language != .httpMessage {
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      let strings =
        tokens.text(of: .string, in: sample.text) + tokens.text(of: .name, in: sample.text)
      #expect(
        strings.allSatisfy { !$0.replacingOccurrences(of: "\\\n", with: "").contains("\n") },
        "\(sample.place)")
    }
  }

  /// A JSON block that is valid or not is still mostly read: an elision, a
  /// fragment's stray character or a hand-broken string leaves a little plain, never
  /// most of it. A block typed `json` that is an HTTP message is another language,
  /// and the header RFC 8792 puts on a folded block is not JSON, so it is not counted.
  @Test(arguments: documents)
  func `a JSON block is mostly lexed`(stem: String) throws {
    for sample in try Self.samples(stem) where sample.language == .json {
      guard !HTTPLexer.isStartLine(Self.firstLine(of: sample.text)) else { continue }
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      let header = sample.text.split(separator: "\n")
        .filter { $0.contains("line wrapping per RFC 8792") }
        .map { Self.nonWhitespace(String($0)) }.reduce(0, +)
      let plain =
        tokens.text(of: .plain, in: sample.text).map(Self.nonWhitespace).reduce(0, +) - header
      let all = Self.nonWhitespace(sample.text) - header
      #expect(Double(plain) <= Double(all) * 0.1, "\(sample.place): \(plain) of \(all) plain")
    }
  }

  @Test(arguments: documents)
  func `an XML block with a tag has a name`(stem: String) throws {
    for sample in try Self.samples(stem)
    where sample.language == .xml && sample.text.contains("<") {
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      #expect(tokens.contains { $0.kind == .name }, "\(sample.place)")
    }
  }

  @Test(arguments: documents)
  func `an HTTP block that starts with a message or a field has a name or keyword`(
    stem: String
  ) throws {
    let field = try NSRegularExpression(pattern: HTTPLexer.fieldLine, options: .anchorsMatchLines)
    for sample in try Self.samples(stem) where sample.language == .httpMessage {
      let firstLine = Self.firstLine(of: sample.text)
      let isField =
        field.firstMatch(in: firstLine, range: NSRange(location: 0, length: firstLine.utf16.count))
        != nil
      guard HTTPLexer.isStartLine(firstLine) || isField else { continue }
      let tokens = try #require(Lexers.highlight(sample.text, as: sample.type))
      #expect(tokens.contains { $0.kind == .name || $0.kind == .keyword }, "\(sample.place)")
    }
  }
}
