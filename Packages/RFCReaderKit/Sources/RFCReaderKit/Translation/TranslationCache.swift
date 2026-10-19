import Foundation
import RFCKit

/// The translations a document has had (#749), kept by document and language in
/// Caches, so opening it again does not translate it again. Kept by source string:
/// a revised document finds what it shares with the one translated before, and is
/// asked to translate only the rest. Caches, because it can be made again.
public struct TranslationCache: Sendable {
  private let directory: URL

  /// Caches/RFCReader/Translations.
  public init() {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    self.init(
      directory: caches.appending(path: "RFCReader/Translations", directoryHint: .isDirectory))
  }

  public init(directory: URL) {
    self.directory = directory
  }

  /// What `document` has been translated as into `language`, by source; empty when
  /// nothing is kept, or what is kept cannot be read.
  public func translations(of document: DocumentID, into language: String) -> [String: String] {
    translations(of: .rfc(document), into: language)
  }

  /// The same for an RFC or a draft's revision (#728).
  public func translations(of document: ReadableDocument, into language: String)
    -> [String: String]
  {
    guard let data = try? Data(contentsOf: url(of: document, into: language)),
      let translations = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return translations
  }

  /// Adds `translations` to what is kept for `document` in `language`. A failure
  /// to write costs only a translation done again, so it is not reported.
  public func keep(
    _ translations: [String: String], of document: DocumentID, into language: String
  ) {
    keep(translations, of: .rfc(document), into: language)
  }

  public func keep(
    _ translations: [String: String], of document: ReadableDocument, into language: String
  ) {
    let kept = self.translations(of: document, into: language).merging(translations) { $1 }
    guard let data = try? JSONEncoder().encode(kept) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: url(of: document, into: language), options: .atomic)
  }

  private func url(of document: ReadableDocument, into language: String) -> URL {
    directory.appending(path: "\(document.description).\(language).json")
  }
}
