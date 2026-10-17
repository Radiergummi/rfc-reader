import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a translation keeps (#749), so a document opened again is not translated
/// again, and a changed one only where it changed.
@Suite("Translation cache")
final class TranslationCacheTests {
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: "TranslationCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  private let cache: TranslationCache

  init() {
    cache = TranslationCache(directory: directory)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  @Test func `nothing is kept for a document never translated`() {
    #expect(cache.translations(of: .rfc(9110), into: "de").isEmpty)
  }

  @Test func `what is kept is found again, by document and language`() {
    cache.keep(["Abstract": "Zusammenfassung"], of: .rfc(9110), into: "de")
    #expect(cache.translations(of: .rfc(9110), into: "de") == ["Abstract": "Zusammenfassung"])
    #expect(cache.translations(of: .rfc(9110), into: "fr").isEmpty)
    #expect(cache.translations(of: .rfc(9111), into: "de").isEmpty)
  }

  /// A source already kept stays kept, so a revised document translates only what
  /// is new in it.
  @Test func `keeping more adds to what is kept`() {
    cache.keep(["Abstract": "Zusammenfassung"], of: .rfc(9110), into: "de")
    cache.keep(["Note": "Hinweis"], of: .rfc(9110), into: "de")
    #expect(
      cache.translations(of: .rfc(9110), into: "de")
        == ["Abstract": "Zusammenfassung", "Note": "Hinweis"])
  }
}
