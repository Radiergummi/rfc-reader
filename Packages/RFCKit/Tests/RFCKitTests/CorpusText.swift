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

  /// The document `stem` names, such as `rfc1178`, decoded as every reader of the
  /// format decodes it, through `LegacyTextParser.text(decoding:)`.
  static func text(_ stem: String) throws -> String {
    guard let directory else { throw CorpusTextError.notConfigured }
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

  /// The RFCXML of the document `stem` names, such as `rfc9110`.
  static func xml(_ stem: String) throws -> Data {
    guard let xmlDirectory else { throw CorpusTextError.xmlNotConfigured }
    let file = xmlDirectory.appendingPathComponent("\(stem).xml")
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw CorpusTextError.xmlNotFetched(stem)
    }
    return try Data(contentsOf: file)
  }
}

enum CorpusTextError: Error, Equatable {
  /// `RFC_CORPUS_TEXT` is not set; a suite that reads the corpus is enabled only where
  /// it is.
  case notConfigured
  /// The document is not in the directory: `make test-corpus` fetches only the
  /// documents listed in the Makefile's `CORPUS_TEST_DOCUMENTS`.
  case notFetched(String)
  /// `RFC_CORPUS_XML` is not set.
  case xmlNotConfigured
  /// The RFCXML document is not in the directory: `make test-corpus` fetches only the
  /// documents listed in the Makefile's `CORPUS_TEST_XML_DOCUMENTS`.
  case xmlNotFetched(String)
}

extension CorpusTextError: CustomStringConvertible {
  var description: String {
    switch self {
    case .notConfigured:
      "RFC_CORPUS_TEXT is not set"
    case .notFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_DOCUMENTS"
    case .xmlNotConfigured:
      "RFC_CORPUS_XML is not set"
    case .xmlNotFetched(let stem):
      "\(stem) is read by a corpus-backed test but not fetched: add it to CORPUS_TEST_XML_DOCUMENTS"
    }
  }
}
