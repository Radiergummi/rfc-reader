import Foundation

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

  /// The document `stem` names, such as `rfc1178`, decoded as corpus-build decodes it:
  /// UTF-8, or Windows-1252 for the older documents that are not.
  static func text(_ stem: String) throws -> String {
    guard let directory else { throw CorpusTextError.notConfigured }
    let bytes = try Data(contentsOf: directory.appendingPathComponent("\(stem).txt"))
    return String(data: bytes, encoding: .utf8)
      ?? String(data: bytes, encoding: .windowsCP1252)
      ?? String(decoding: bytes, as: UTF8.self)
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
    guard let xmlDirectory else { throw CorpusTextError.notConfigured }
    return try Data(contentsOf: xmlDirectory.appendingPathComponent("\(stem).xml"))
  }
}

enum CorpusTextError: Error {
  /// `RFC_CORPUS_TEXT`, or `RFC_CORPUS_XML`, is not set; a suite that reads the corpus
  /// is enabled only where it is.
  case notConfigured
}
