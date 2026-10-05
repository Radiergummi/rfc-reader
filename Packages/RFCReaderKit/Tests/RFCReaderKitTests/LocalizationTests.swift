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

  /// French first and German second: the catalog has German, so German it is, in
  /// the reader's region.
  @Test func `a language the catalog lacks gives way to the catalog's, in the reader's region`() {
    let interface = Locale.interface(localization: "de", current: Locale(identifier: "fr_FR"))
    #expect(interface.language.languageCode?.identifier == "de")
    #expect(interface.region?.identifier == "FR")
  }

  /// The reader's own settings stay when the language gives way: a 12-hour clock
  /// and a week that starts on Monday.
  @Test func `a language the catalog lacks keeps the reader's settings`() {
    let interface = Locale.interface(
      localization: "de", current: Locale(identifier: "fr_FR@hours=h12;fw=mon"))
    #expect(interface.hourCycle == .oneToTwelve)
    #expect(interface.firstDayOfWeek == .monday)
  }

  /// British English is the catalog's English, and keeps its own lists.
  @Test func `a variant of the catalog's language is kept as it is`() {
    let interface = Locale.interface(localization: "en", current: Locale(identifier: "en_GB"))
    #expect(interface == Locale(identifier: "en_GB"))
    #expect(
      ["RFC 1", "RFC 2", "RFC 3"].formatted(.list(type: .and).locale(interface))
        == "RFC 1, RFC 2 and RFC 3")
  }
}
