import Foundation
import RFCKit
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

  /// The German is compiled into RFCReaderKit's bundle and found through it.
  @Test func `RFCReaderKit finds its German catalog`() {
    #expect(String(kit: "Remove from Collection", locale: .german) == "Aus Sammlung entfernen")
    let more = DocumentMenus.more(
      showsOriginal: false, errata: nil, precedingDraft: nil, locale: .german)
    #expect(
      more.map { $0.map(\.title) } == [
        ["Originaltext"], ["Auf rfc-editor.org öffnen", "Datatracker"],
      ])
  }

  @Test func `a German notice lists its RFCs in German`() {
    let notice = BookmarkNotice.notices(
      for: [.obsoleted(.rfc(9990), newer: [.rfc(9991), .rfc(9992)])], index: nil, locale: .german
    ).first
    #expect(notice?.body == "Ersetzt durch RFC 9991 und RFC 9992.")
  }

  /// A collection's name is the reader's own text: never looked up, even when it is
  /// a word the catalog translates.
  @Test func `a collection's name is never translated`() {
    let snapshot = CollectionSnapshot(collections: [
      .init(id: UUID(), name: "Errata", color: .blue, members: [])
    ])
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: snapshot, locale: .german)
    #expect(menu[0].map(\.title) == ["Errata"])
  }

  @Test func `one RFC is counted in the singular in German`() {
    #expect(String(kit: "\(1) RFCs", locale: .german) == "1 RFC")
    #expect(String(kit: "\(3) RFCs", locale: .german) == "3 RFCs")
  }

  /// The glossary keeps its shape in German: a summary of a sentence or two, ending
  /// with a full stop.
  @Test(arguments: Glossary.Term.allCases)
  func `a German glossary summary is a sentence or two`(term: Glossary.Term) {
    let summary = Glossary.entry(for: term, locale: .german).summary
    #expect((1...2).contains(summary.components(separatedBy: ". ").count), "\(summary)")
    #expect(summary.hasSuffix("."))
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
