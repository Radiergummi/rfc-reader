import Foundation
import RFCKit

/// Legacy RFCs read from a fetched corpus rather than committed: RFCKit's `CorpusText`,
/// for the corpus-backed suites here. `make test-corpus` fetches the documents in the
/// Makefile's `CORPUS_TEST_DOCUMENTS` and points `RFC_CORPUS_TEXT` at them; without it,
/// as in `make check` and on CI, those suites are skipped.
enum CorpusText {
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_TEXT"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static var isAvailable: Bool { directory != nil }

  /// The document `stem` names, such as `rfc570`, decoded as a convert run decodes it.
  static func text(_ stem: String) throws -> String {
    guard let directory else { throw CorpusTextError.notConfigured }
    let file = directory.appendingPathComponent("\(stem).txt")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusTextError.notFetched(stem)
    }
    return LegacyTextParser.text(decoding: try Data(contentsOf: file))
  }
}

enum CorpusTextError: Error, CustomStringConvertible {
  case notConfigured
  case notFetched(String)

  var description: String {
    switch self {
    case .notConfigured:
      "RFC_CORPUS_TEXT is not set"
    case .notFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_DOCUMENTS"
    }
  }
}
