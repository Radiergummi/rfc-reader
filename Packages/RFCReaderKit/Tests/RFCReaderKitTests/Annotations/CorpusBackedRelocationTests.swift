import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The legacy text renderings a corpus-backed suite reads, from the directory
/// `RFC_CORPUS_TEXT` names: `make test-corpus-app` fetches the Makefile's
/// `CORPUS_TEST_APP_TEXT_DOCUMENTS` there, and passes that list as
/// `RFC_CORPUS_APP_TEXT_DOCUMENTS`. A document not on it is refused, even where a local
/// corpus holds it; where it is not set, nothing is refused.
enum CorpusLegacyText {
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_TEXT"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  /// The stems `RFC_CORPUS_APP_TEXT_DOCUMENTS` lists, where it is set. Not RFCKit's
  /// `RFC_CORPUS_TEXT_DOCUMENTS`, so an environment copied from `make test-corpus`
  /// cannot check this package against the wrong list.
  static var listedDocuments: Set<String>? {
    CorpusList.stems(in: "RFC_CORPUS_APP_TEXT_DOCUMENTS")
  }

  /// `listed` is the list `stem` is checked against, the environment's unless a test
  /// passes its own.
  static func document(_ stem: String, listed: Set<String>? = listedDocuments) throws
    -> RFCDocument
  {
    if let listed, !listed.contains(stem) {
      throw CorpusLegacyTextError.notListed(stem)
    }
    let file = try #require(directory).appendingPathComponent("\(stem).txt")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusLegacyTextError.notFetched(stem)
    }
    return LegacyTextParser.parse(try Data(contentsOf: file))
  }
}

enum CorpusLegacyTextError: Error, Equatable, CustomStringConvertible {
  /// The document is not in the directory: `make test-corpus-app` fetches only the
  /// documents listed in the Makefile's `CORPUS_TEST_APP_TEXT_DOCUMENTS`.
  case notFetched(String)
  /// The document is not in `RFC_CORPUS_APP_TEXT_DOCUMENTS`, the Makefile's
  /// `CORPUS_TEST_APP_TEXT_DOCUMENTS`.
  case notListed(String)

  var description: String {
    switch self {
    case .notFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_APP_TEXT_DOCUMENTS"
    case .notListed(let stem):
      "\(stem) is read by a corpus-backed test but not listed: add it to CORPUS_TEST_APP_TEXT_DOCUMENTS"
    }
  }
}

/// A document moving from converted legacy text to authored XML is the largest move
/// relocation is written for (#522): every heading and paragraph anchor differs, and
/// the text is the same words. RFC 9110 exists in both.
@Suite(
  "Corpus-backed: relocation",
  .enabled(if: CorpusXML.isAvailable && CorpusLegacyText.directory != nil))
struct CorpusBackedRelocationTests {
  /// A document fetched locally, by `make corpus`, but not on the Makefile's list is
  /// refused (#986).
  @Test(.enabled(if: CorpusLegacyText.listedDocuments != nil))
  func `a legacy document not on the list is refused as not listed`() {
    #expect(throws: CorpusLegacyTextError.notListed("rfc0")) {
      try CorpusLegacyText.document("rfc0")
    }
  }

  @Test func `a listed legacy document that is not fetched is refused as not fetched`() {
    #expect(throws: CorpusLegacyTextError.notFetched("rfc0")) {
      try CorpusLegacyText.document("rfc0", listed: ["rfc0"])
    }
  }

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
