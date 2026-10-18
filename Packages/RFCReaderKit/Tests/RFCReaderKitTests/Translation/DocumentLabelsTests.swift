import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The words the builder writes into the body itself (#749): English, and in a
/// translated document the translation's, so the body is in one language.
@Suite("Document labels")
struct DocumentLabelsTests {
  private static let german = [
    "Abstract": "Zusammenfassung",
    "Note": "Hinweis",
    "Notes": "Hinweise",
    "Figure 1": "Abbildung 1",
    "Table 1": "Tabelle 1",
    "Appendix A": "Anhang A",
    "Annex A": "Annex A",
    "One Backlink": "Ein Rückverweis",
    "Two Backlinks": "Zwei Rückverweise",
    "Three Backlinks": "Drei Rückverweise",
    "4 Backlinks": "4 Rückverweise",
  ]

  @Test func `every phrase a translation is asked for is one of the English labels'`() {
    #expect(Set(DocumentLabels.sources) == Set(Self.german.keys))
  }

  @Test func `a label is the word its numbered phrase was translated with`() {
    let labels = DocumentLabels(translating: Self.german)
    #expect(labels.figure == "Abbildung")
    #expect(labels.table == "Tabelle")
    #expect(labels.appendix == "Anhang")
    #expect(labels.backlinksCaption(count: 1) == "Ein Rückverweis")
    #expect(labels.backlinksCaption(count: 12) == "12 Rückverweise")
  }

  /// A translation that lost the number or letter cannot say which word is the
  /// label's, and one that is missing says nothing: either keeps the English.
  @Test func `a phrase whose number is lost, or missing, keeps the English`() {
    let labels = DocumentLabels(translating: ["Figure 1": "Abbildung eins", "Table 1": "Tabelle 1"])
    #expect(labels.figure == "Figure")
    #expect(labels.table == "Tabelle")
    #expect(labels.abstract == "Abstract")
    #expect(DocumentLabels(translating: [:]) == .english)
  }

  @Test func `a label written without a space, or after its number, is found or kept`() {
    let labels = DocumentLabels(translating: ["Figure 1": "図1", "Table 1": "1. táblázat"])
    #expect(labels.figure == "図")
    #expect(labels.table == "Table")
  }

  @Test func `a translated build says the translated labels`() throws {
    let document = try Fixtures.rfc8999()
    let labels = DocumentLabels(translating: Self.german)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(), translation: labels)
    let text = built.text.string
    #expect(text.hasPrefix("Zusammenfassung\n"))
    #expect(!text.contains("Abstract\n"))
    #expect(text.contains("Rückverweis"))
    #expect(!text.contains("Backlink"))
  }

  @Test func `an appendix heading is numbered with the translated word`() throws {
    let document = try Fixtures.rfc8999()
    let appendices = document.allSections.filter { $0.isAppendix && $0.number != nil }
    try #require(!appendices.isEmpty)
    let labels = DocumentLabels(translating: Self.german)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle(), translation: labels)
    for section in appendices {
      let heading = try #require(built.anchors.heading(of: section.anchor))
      #expect(heading.hasPrefix("Anhang "), "\(heading)")
    }
    let headings = built.anchors.entries.compactMap(\.heading)
    #expect(!headings.contains { $0.hasPrefix("Appendix ") })
  }

  @Test func `an original build is not a translation, and a translated one is`() throws {
    let document = try Fixtures.rfc8999()
    #expect(!DocumentTextBuilder.build(document, style: ReadingStyle()).isTranslation)
    #expect(
      DocumentTextBuilder.build(document, style: ReadingStyle(), translation: .english)
        .isTranslation)
  }
}
