import Foundation

@testable import RFCKit

/// RFCs read from a fetched corpus rather than from the fixtures: legacy texts, and
/// the RFCs authored in RFCXML.
///
/// A fixture is RFC text committed to the repository, and the repository takes no
/// more of it. A finding that needs a whole document, because it is about what the
/// parser makes of one, reads the document from the directory `RFC_CORPUS_TEXT`
/// names instead: `make test-corpus` fetches the documents those suites need into
/// `corpus/text.noindex` and points it there. Without it, as in `make check` and on
/// CI, the suites that need it are skipped.
///
/// It also passes the Makefile's lists of those documents, `CORPUS_TEST_DOCUMENTS` as
/// `RFC_CORPUS_TEXT_DOCUMENTS` and `CORPUS_TEST_XML_DOCUMENTS` as
/// `RFC_CORPUS_XML_DOCUMENTS`, and a document not on its list is refused, even where a
/// local corpus holds it: CI fetches only the listed ones. Where a list is not set, as
/// in a `swift test` run with the directory set by hand, nothing is refused.
enum CorpusText {
  /// The directory of `rfcNNNN.txt` files, where one is set.
  static var directory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_TEXT"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static var isAvailable: Bool {
    directory != nil
  }

  /// The stems `RFC_CORPUS_TEXT_DOCUMENTS` lists, where it is set.
  static var listedDocuments: Set<String>? {
    listed(in: "RFC_CORPUS_TEXT_DOCUMENTS")
  }

  /// The document `stem` names, such as `rfc1178`, decoded as every reader of the
  /// format decodes it, through `LegacyTextParser.text(decoding:)`. `listed` is the
  /// list it is checked against, the environment's unless a test passes its own.
  static func text(_ stem: String, listed: Set<String>? = listedDocuments) throws -> String {
    guard let directory else { throw CorpusTextError.notConfigured }
    if let listed, !listed.contains(stem) {
      throw CorpusTextError.notListed(stem)
    }
    let file = directory.appendingPathComponent("\(stem).txt")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusTextError.notFetched(stem)
    }
    let bytes = try Data(contentsOf: file)
    return LegacyTextParser.text(decoding: bytes)
  }

  /// The directory of `rfcNNNN.xml` files, the RFCs authored in RFCXML, where one is set.
  static var xmlDirectory: URL? {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_XML"], !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static var isXMLAvailable: Bool {
    xmlDirectory != nil
  }

  /// The stems `RFC_CORPUS_XML_DOCUMENTS` lists, where it is set.
  static var listedXMLDocuments: Set<String>? {
    listed(in: "RFC_CORPUS_XML_DOCUMENTS")
  }

  /// The RFCXML of the document `stem` names, such as `rfc9110`. `listed` is the list
  /// it is checked against, the environment's unless a test passes its own.
  static func xml(_ stem: String, listed: Set<String>? = listedXMLDocuments) throws -> Data {
    guard let xmlDirectory else { throw CorpusTextError.xmlNotConfigured }
    if let listed, !listed.contains(stem) {
      throw CorpusTextError.xmlNotListed(stem)
    }
    let file = xmlDirectory.appendingPathComponent("\(stem).xml")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusTextError.xmlNotFetched(stem)
    }
    return try Data(contentsOf: file)
  }

  /// The stems the environment variable `name` lists, separated by whitespace, or nil
  /// where it is not set.
  private static func listed(in name: String) -> Set<String>? {
    guard let list = ProcessInfo.processInfo.environment[name] else { return nil }
    return Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
  }
}

enum CorpusTextError: Error, Equatable {
  /// `RFC_CORPUS_TEXT` is not set; a suite that reads the corpus is enabled only where
  /// it is.
  case notConfigured
  /// `RFC_CORPUS_INDEX` is not set.
  case indexNotConfigured
  /// The document is not in the directory: `make test-corpus` fetches only the
  /// documents listed in the Makefile's `CORPUS_TEST_DOCUMENTS`.
  case notFetched(String)
  /// The document is not in `RFC_CORPUS_TEXT_DOCUMENTS`, the Makefile's
  /// `CORPUS_TEST_DOCUMENTS`.
  case notListed(String)
  /// `RFC_CORPUS_XML` is not set.
  case xmlNotConfigured
  /// The RFCXML document is not in the directory: `make test-corpus` fetches only the
  /// documents listed in the Makefile's `CORPUS_TEST_XML_DOCUMENTS`.
  case xmlNotFetched(String)
  /// The RFCXML document is not in `RFC_CORPUS_XML_DOCUMENTS`, the Makefile's
  /// `CORPUS_TEST_XML_DOCUMENTS`.
  case xmlNotListed(String)
}

extension CorpusTextError: CustomStringConvertible {
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
    case .xmlNotConfigured:
      "RFC_CORPUS_XML is not set"
    case .xmlNotFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_XML_DOCUMENTS"
    case .xmlNotListed(let stem):
      "\(stem) is read by a corpus-backed test but not listed: add it to CORPUS_TEST_XML_DOCUMENTS"
    }
  }
}

/// The RFC index, from `RFC_CORPUS_INDEX`, for a suite that checks something against
/// every RFC's metadata. `make test-corpus` fetches it.
enum CorpusIndex {
  static var isAvailable: Bool { parsed != nil }

  static func index() throws -> RFCIndex {
    guard let parsed else { throw CorpusTextError.indexNotConfigured }
    return try parsed.get()
  }

  /// Parsed once: it is several megabytes. The parse's error is kept, so an index that
  /// is set but unreadable says why rather than that it is not set.
  private static let parsed: Result<RFCIndex, any Error>? = {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS_INDEX"], !path.isEmpty
    else { return nil }
    return Result { try RFCIndexParser.parse(contentsOf: URL(fileURLWithPath: path)) }
  }()
}
