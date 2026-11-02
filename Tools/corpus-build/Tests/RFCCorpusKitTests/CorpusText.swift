import Foundation
import RFCKit

/// Legacy RFCs read from a fetched corpus rather than committed: RFCKit's `CorpusText`,
/// for the corpus-backed suites here. `make test-corpus` fetches the documents in the
/// Makefile's `CORPUS_TEST_DOCUMENTS` and points `RFC_CORPUS_TEXT` at them; without it,
/// as in `make check` and on CI, those suites are skipped. It passes that list as
/// `RFC_CORPUS_TEXT_DOCUMENTS`, and a document not on it is refused, even where a local
/// corpus holds it; where it is not set, nothing is refused.
enum CorpusText {
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_TEXT"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static var isAvailable: Bool { directory != nil }

  /// The stems `RFC_CORPUS_TEXT_DOCUMENTS` lists, separated by spaces, where it is set.
  static var listedDocuments: Set<String>? {
    guard let list = ProcessInfo.processInfo.environment["RFC_CORPUS_TEXT_DOCUMENTS"]
    else { return nil }
    return Set(list.split(separator: " ").map(String.init))
  }

  /// The RFC index, from `RFC_CORPUS_INDEX`, for a suite that converts as a corpus run
  /// does, with each document's metadata. `make test-corpus` fetches it.
  static var hasIndex: Bool { parsedIndex != nil }

  static func index() throws -> RFCIndex {
    guard let parsedIndex else { throw CorpusTextError.indexNotConfigured }
    return try parsedIndex.get()
  }

  /// Parsed once: it is several megabytes. The parse's error is kept, so an index that
  /// is set but unreadable says why rather than that it is not set.
  private static let parsedIndex = parseIndex(
    atPath: ProcessInfo.processInfo.environment["RFC_CORPUS_INDEX"])

  /// Nil when `path` is not set.
  static func parseIndex(atPath path: String?) -> Result<RFCIndex, any Error>? {
    guard let path, !path.isEmpty else { return nil }
    return Result { try RFCIndexParser.parse(contentsOf: URL(fileURLWithPath: path)) }
  }

  /// The document `stem` names, such as `rfc570`, decoded as a convert run decodes it.
  static func text(_ stem: String) throws -> String {
    guard let directory else { throw CorpusTextError.notConfigured }
    if let listedDocuments, !listedDocuments.contains(stem) {
      throw CorpusTextError.notListed(stem)
    }
    let file = directory.appendingPathComponent("\(stem).txt")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusTextError.notFetched(stem)
    }
    return LegacyTextParser.text(decoding: try Data(contentsOf: file))
  }
}

enum CorpusTextError: Error, CustomStringConvertible {
  case notConfigured
  case indexNotConfigured
  case notFetched(String)
  case notListed(String)

  var description: String {
    switch self {
    case .notConfigured:
      "RFC_CORPUS_TEXT is not set"
    case .indexNotConfigured:
      "RFC_CORPUS_INDEX is not set"
    case .notFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_DOCUMENTS"
    case .notListed(let stem):
      "\(stem) is read by a corpus-backed test but not listed: add it to CORPUS_TEST_DOCUMENTS"
    }
  }
}
