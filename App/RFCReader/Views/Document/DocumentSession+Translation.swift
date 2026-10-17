import RFCKit
import RFCReaderKit
import SwiftUI
import Translation

/// Translating the document on demand (#749): asked for from the More menu, carried
/// out by the Translation framework on the device, and kept, so the same document is
/// not translated again. What a translated document is, and what is not translated,
/// are `DocumentTranslation`'s.
extension DocumentSession {
  /// Where a translation of the document stands.
  enum TranslationPhase: Equatable {
    case idle
    /// The share of what had to be asked for that has come back.
    case translating(progress: Double)
    case translated(TranslatedDocument)
    case failed
  }

  /// The language to translate into: the first of the reader's languages that is
  /// not English, which the document already is. Nil for a reader who reads only
  /// English, which leaves the choice to the framework.
  static var translationTarget: Locale.Language? {
    Locale.preferredLanguages.lazy
      .map { Locale.Language(identifier: $0) }
      .first { $0.languageCode != .english }
  }

  /// The framework's configuration for the document, which `.translationTask` runs
  /// `translate(with:)` under.
  static func translationConfiguration() -> TranslationSession.Configuration {
    TranslationSession.Configuration(
      source: Locale.Language(identifier: "en"), target: translationTarget)
  }

  /// Translates the document with `translator`: what an earlier translation kept is
  /// not asked for again, the rest is asked for in one batch, and the whole is kept
  /// once it is back. Once per document unless it failed: a translation already
  /// made, or under way, is left as it is.
  func translate(with translator: TranslationSession, cache: TranslationCache) async {
    guard let document = state.document else { return }
    switch translationPhase {
    case .translating, .translated: return
    case .idle, .failed: break
    }
    translationPhase = .translating(progress: 0)
    let language = translator.targetLanguage?.minimalIdentifier
    var translations = await Self.kept(by: cache, of: id, into: language)
    let missing = await Self.missing(in: document, known: translations)
    var fresh: [String: String] = [:]
    var responseLanguage: String?
    do {
      // Identified by index, so a response is matched to its source whatever the
      // framework makes of the text's white space.
      let requests = missing.enumerated().map { index, source in
        TranslationSession.Request(sourceText: source, clientIdentifier: String(index))
      }
      for try await response in translator.translate(batch: requests) {
        guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
        fresh[missing[index]] = response.targetText
        responseLanguage = responseLanguage ?? response.targetLanguage.minimalIdentifier
        // A step at a time, so the header is not hosted again for every paragraph.
        if fresh.count.isMultiple(of: 50) {
          translationPhase = .translating(progress: Double(fresh.count) / Double(missing.count))
        }
      }
    } catch {
      readerLog.failure(of: id, "translating failed", error)
      translationPhase = .failed
      return
    }
    translations.merge(fresh) { _, new in new }
    if let language = language ?? responseLanguage, !fresh.isEmpty {
      await Self.keep(fresh, in: cache, of: id, into: language)
    }
    translationPhase = .translated(await Self.translated(document, translations))
  }

  @concurrent
  private static func kept(
    by cache: TranslationCache, of id: DocumentID, into language: String?
  ) async -> [String: String] {
    language.map { cache.translations(of: id, into: $0) } ?? [:]
  }

  @concurrent
  private static func keep(
    _ translations: [String: String], in cache: TranslationCache, of id: DocumentID,
    into language: String
  ) async {
    cache.keep(translations, of: id, into: language)
  }

  @concurrent
  private static func missing(in document: RFCDocument, known: [String: String]) async -> [String] {
    DocumentTranslation.missing(in: document, known: known)
  }

  @concurrent
  private static func translated(
    _ document: RFCDocument, _ translations: [String: String]
  ) async -> TranslatedDocument {
    TranslatedDocument(document, translations)
  }
}
