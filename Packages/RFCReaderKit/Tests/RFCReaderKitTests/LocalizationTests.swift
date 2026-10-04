import Foundation
import Testing

@testable import RFCReaderKit

extension Locale {
  /// What tests resolve German in, whatever the machine running them prefers;
  /// `.english` is RFCReaderKit's own.
  static let german = Locale(identifier: "de")
}

@Suite("Localization")
struct LocalizationTests {
  @Test func `a key resolves to its English text in English`() {
    #expect(String(kit: "Remove from Collection", locale: .english) == "Remove from Collection")
  }

  /// The language is the catalog's, the region the reader's.
  @Test func `the interface keeps the reader's region`() {
    #expect(Locale.interface.region == Locale.current.region)
  }

  @Test func `the interface language is the one the catalog resolves to, not the region's`() {
    let resolved = Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
    #expect(Locale.interface.language.languageCode == resolved.language.languageCode)
  }
}
