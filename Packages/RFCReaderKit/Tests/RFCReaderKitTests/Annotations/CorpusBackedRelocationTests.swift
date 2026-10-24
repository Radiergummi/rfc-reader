import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The legacy text renderings a corpus-backed suite reads, from the directory
/// `RFC_CORPUS_TEXT` names: `make test-corpus-app` fetches the Makefile's
/// `CORPUS_TEST_APP_TEXT_DOCUMENTS` there.
enum CorpusLegacyText {
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_TEXT"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static func document(_ stem: String) throws -> RFCDocument {
    let file = try #require(directory).appendingPathComponent("\(stem).txt")
    return LegacyTextParser.parse(try Data(contentsOf: file))
  }
}

/// A document moving from converted legacy text to authored XML is the largest move
/// relocation is written for (#522): every heading and paragraph anchor differs, and
/// the text is the same words. RFC 9110 exists in both.
@Suite(
  "Corpus-backed: relocation",
  .enabled(if: CorpusXML.isAvailable && CorpusLegacyText.directory != nil))
struct CorpusBackedRelocationTests {
  @Test func `a passage of the legacy parse is found in the authored XML`() throws {
    let legacy = ModelText(try CorpusLegacyText.document("rfc9110"))
    let authored = ModelText(try CorpusXML.document("rfc9110"))
    let relocator = Relocator(authored)
    var found = 0
    var ambiguous = 0
    var detached = 0
    var wrong: [String] = []
    // A passage of about a sentence from the middle of every 25th paragraph-sized
    // span: one place in each stretch of the document, chosen at run time.
    let paragraphs = legacy.spans.filter { !$0.isSection && $0.range.count > 120 }
    for span in stride(from: 0, to: paragraphs.count, by: 25).map({ paragraphs[$0] }) {
      let middle = span.range.lowerBound + span.range.count / 2
      let start = wordStart(in: legacy, from: middle - 40)
      let end = wordStart(in: legacy, from: middle + 40)
      guard start < end, let target = Target(covering: start..<end, in: legacy) else { continue }
      switch relocator.relocate(target) {
      case .exact(let moved), .moved(let moved):
        found += 1
        let covered = moved.range(in: authored).map { authored.text(in: $0) } ?? ""
        let normalized = { (text: String) in
          String(decoding: TextNormalization(Array(text.utf16)).trimmed, as: UTF16.self)
        }
        if normalized(covered) != normalized(legacy.text(in: start..<end)) {
          wrong.append(String(covered.prefix(20)))
        }
      case .ambiguous: ambiguous += 1
      case .detached: detached += 1
      }
    }
    let total = found + ambiguous + detached
    #expect(total > 20, "\(total) passages sampled")
    #expect(wrong.isEmpty, "found elsewhere than the same words: \(wrong.prefix(3))")
    #expect(
      Double(found) >= Double(total) * 0.9,
      "\(found) of \(total) found, \(ambiguous) ambiguous, \(detached) detached")
  }

  /// The start of the first word at or after `offset`.
  private func wordStart(in model: ModelText, from offset: Int) -> Int {
    var index = max(0, offset)
    while index < model.length, model.units[index] != 0x20 { index += 1 }
    return min(model.length, index + 1)
  }
}
