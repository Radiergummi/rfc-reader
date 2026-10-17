import RFCKit
import RFCReaderKit
import SwiftUI
import Translation

/// Translating the document on demand (#749): asked for from the More menu, carried
/// out by the Translation framework on the device, and kept, so the same document is
/// not translated again. What a translated document is, and what is not translated,
/// are `DocumentTranslation`'s; where a translation stands is `TranslationRun`'s.
extension DocumentSession {
  /// The framework's configuration for the document, which `.translationTask` runs
  /// `translate(with:cache:)` under. Nil for a reader who reads only English, who
  /// is not offered a translation.
  static func translationConfiguration() -> TranslationSession.Configuration? {
    DocumentTranslation.target.map {
      TranslationSession.Configuration(source: Locale.Language(identifier: "en"), target: $0)
    }
  }

  /// Translates the document with `translator`, if the reader still shows the
  /// translation and none is made or under way: `.translationTask` runs this again
  /// whenever the view appears. What an earlier translation kept is not asked for
  /// again, and the rest is asked for in one batch. What comes back is kept even if
  /// the batch fails or is canceled, so the next attempt asks only for the rest; a
  /// batch that ended early is no translation, and leaves the phase idle.
  func translate(with translator: TranslationSession, cache: TranslationCache) async {
    guard showsTranslation, !translationPhase.isUnderWayOrMade,
      let document = state.document, let target = translator.targetLanguage
    else { return }
    let language = target.minimalIdentifier
    translationPhase = .translating(progress: 0)
    var translations = await Self.kept(by: cache, of: id, into: language)
    var run = TranslationRun(await Self.missing(in: document, known: translations))
    var failure: (any Error)?
    if !run.requests.isEmpty {
      let requests = run.requests.enumerated().map { index, source in
        TranslationSession.Request(sourceText: source, clientIdentifier: String(index))
      }
      do {
        for try await response in translator.translate(batch: requests) {
          let moved = run.receive(response.targetText, for: response.clientIdentifier)
          if moved { translationPhase = .translating(progress: run.progress) }
        }
      } catch {
        failure = error
      }
    }
    if !run.received.isEmpty {
      await Self.keep(run.received, in: cache, of: id, into: language)
    }
    if let failure {
      readerLog.failure(of: id, "translating failed", failure)
      translationPhase = .failed
      return
    }
    guard run.isComplete else {
      translationPhase = .idle
      return
    }
    translations.merge(run.received) { _, new in new }
    translationPhase = .translated(await Self.translated(document, translations))
  }

  @concurrent
  private static func kept(
    by cache: TranslationCache, of id: DocumentID, into language: String
  ) async -> [String: String] {
    cache.translations(of: id, into: language)
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
