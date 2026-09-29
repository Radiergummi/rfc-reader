import Testing

@testable import RFCKit

/// The small vocabularies the parsers and the serializer share, each read and written
/// in one place, so the two directions cannot drift apart.
@Suite("Vocabulary")
struct VocabularyTests {
  @Test(arguments: [
    ("section-4.2", PartNumber.section("4.2")),
    ("section-1", PartNumber.section("1")),
    ("section-appendix.a", PartNumber.appendix("A")),
    ("section-appendix.b.1", PartNumber.appendix("B.1")),
    ("figure-3", PartNumber.figure(3)),
    ("table-12", PartNumber.table(12)),
  ])
  func `a part number reads back as it is written`(_ attribute: String, _ partNumber: PartNumber) {
    #expect(PartNumber(attribute) == partNumber)
    #expect(partNumber.attribute == attribute)
  }

  /// Prep numbers the boilerplate and the contents too, and those are not sections the
  /// document numbers.
  @Test(arguments: [
    "section-boilerplate.1", "section-toc.1", "section-", "figure-x", "table-", "4.2",
  ])
  func `what is not a numbered part is not a part number`(_ attribute: String) {
    #expect(PartNumber(attribute) == nil)
  }

  @Test(arguments: [("4.2", "section-4.2"), ("A.1", "appendix-A.1"), ("B", "appendix-B")])
  func `a section anchor reads back as it is written`(_ number: String, _ anchor: String) {
    #expect(SectionAnchor.anchor(forSectionNumber: number) == anchor)
    #expect(SectionAnchor.sectionNumber(fromAnchor: anchor) == number)
  }

  @Test(arguments: ["page-12", "section-", "appendix-", "name-introduction"])
  func `an anchor that names no section number has none`(_ anchor: String) {
    #expect(SectionAnchor.sectionNumber(fromAnchor: anchor) == nil)
  }

  @Test func `a series entry names the document it is made from`() throws {
    #expect(SeriesInfo(DocumentID.rfc(9110)) == SeriesInfo(name: "RFC", value: "9110"))
    let bestCurrentPractice = try #require(DocumentID(label: "BCP14"))
    #expect(SeriesInfo(bestCurrentPractice) == SeriesInfo(name: "BCP", value: "14"))
  }

  /// The legacy parser's month patterns and `PublicationDate`'s month names agree:
  /// every month a title page can spell is one `PublicationDate` numbers.
  @Test func `every month the legacy patterns match is a month by number`() {
    for month in 1...12 {
      let name = PublicationDate(year: 2000, month: month).monthName ?? ""
      let match = "\(name) 1999".firstMatch(of: LegacyTextParser.monthYearPattern)
      #expect(match.map { PublicationDate.month(from: String($0.1)) } == month, "\(name)")
      #expect(LegacyTextParser.isDateLine(["\(name) 9, 1999"]), "\(name)")
    }
  }
}
