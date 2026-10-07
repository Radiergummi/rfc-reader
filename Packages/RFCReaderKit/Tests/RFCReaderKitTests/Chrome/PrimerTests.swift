import Foundation
import RFCKit
import RFCReaderKit
import Testing

/// "How an RFC Is Made" (#365): the stages from a first draft to a published RFC,
/// in the app's own words.
@Suite("Primer")
struct PrimerTests {
  private let primer = Glossary.primer(locale: .english)

  @Test func `the stages run from a draft to publication`() {
    #expect(primer.title == "How an RFC Is Made")
    #expect(
      primer.stages.map(\.title) == [
        "An Internet-Draft", "Adoption by a Working Group", "Working Group Last Call",
        "IETF Last Call and IESG Review", "The RFC Editor", "Publication",
      ])
    #expect(primer.otherStreams.title == "Other Streams")
  }

  /// Two to four sentences each, written out, as a glossary entry is.
  @Test func `every stage is two to four sentences`() {
    for stage in primer.stages + [primer.otherStreams] {
      #expect(!stage.title.isEmpty)
      #expect((2...4).contains(stage.text.components(separatedBy: ". ").count), "\(stage.title)")
      #expect(stage.text.hasSuffix("."), "\(stage.title)")
    }
    #expect(primer.introduction.hasSuffix("."))
  }

  /// Each stage names the glossary entries it is about, which open from it, once each.
  @Test func `every stage names glossary terms, once each`() {
    for stage in primer.stages + [primer.otherStreams] {
      #expect(!stage.related.isEmpty, "\(stage.title)")
      #expect(Set(stage.related).count == stage.related.count, "\(stage.title)")
    }
  }

  /// The streams other than the IETF's are where the primer leaves the IETF's path.
  @Test func `the other streams are the IAB, the IRTF and the Independent stream`() {
    #expect(primer.otherStreams.related == [.stream(.iab), .stream(.irtf), .stream(.independent)])
  }

  /// Every stage has an identity of its own, so a list of them can be iterated.
  @Test func `every stage has an identity of its own`() {
    let stages = primer.stages + [primer.otherStreams]
    #expect(Set(stages.map(\.id)).count == stages.count)
  }

  /// The words come from RFCReaderKit's catalog, so a German interface reads German.
  @Test func `the primer is translated`() {
    let german = Glossary.primer(locale: Locale(identifier: "de"))
    #expect(german.title != primer.title)
    #expect(german.stages.count == primer.stages.count)
  }
}
