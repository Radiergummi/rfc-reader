import Foundation
import Testing

@testable import RFCKit

/// `[Inline].locatedPlainText`: the plain text, and the range each cross reference
/// occupies in it. The query set cuts its citing sentences out at these ranges, so
/// they must land exactly where `plainText` puts each label.
@Suite("Model: located plain text")
struct LocatedPlainTextTests {
  private static let section = CrossReference(
    target: .document(DocumentID(series: .rfc, number: 9110), section: "4.2"))
  private static let anchor = CrossReference(target: .anchor("intro"), text: "the introduction")

  private static let inlines: [Inline] = [
    .text("As "),
    .emphasis([.text("defined in "), .crossReference(section)]),
    .text(", and see"),
    .lineBreak,
    .link(URL(string: "https://example.org")!, [.crossReference(anchor)]),
    .code("."),
  ]

  @Test func `the text is plainText`() {
    #expect(Self.inlines.locatedPlainText.text == Self.inlines.plainText)
  }

  @Test func `each cross reference is found at its label, in order, however deeply nested`() {
    let located = Self.inlines.locatedPlainText
    #expect(located.crossReferences.map(\.reference) == [Self.section, Self.anchor])
    #expect(
      located.crossReferences.map { String(located.text[$0.range]) } == [
        Self.section.displayLabel, "the introduction",
      ])
  }

  @Test func `text without cross references locates none`() {
    let located = [Inline.text("Plain words."), .strong([.text("Bold ones.")])].locatedPlainText
    #expect(located.text == "Plain words.Bold ones.")
    #expect(located.crossReferences.isEmpty)
  }
}
