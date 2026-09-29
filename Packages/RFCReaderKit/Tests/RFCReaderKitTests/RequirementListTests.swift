import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The Requirements tab (#180): a document's requirements under their sections,
/// narrowed by key word and by what they are about, and exported as a checklist.
@Suite("Requirement list")
struct RequirementListTests {
  private static func requirement(
    _ sentence: String, _ keywords: [BCP14Keyword], section: String, number: String? = nil,
    title: String = "Title", anchor: String? = nil, isHeuristic: Bool = false
  ) -> Requirement {
    Requirement(
      keywords: keywords, sentence: sentence, anchor: anchor ?? section, sectionAnchor: section,
      sectionNumber: number, sectionTitle: title, isHeuristic: isHeuristic)
  }

  private static let all = [
    requirement(
      "The client MUST send a Host field.", [.must], section: "section-7.2", number: "7.2",
      title: "Host", anchor: "section-7.2-3"),
    requirement(
      "A server MAY reject it.", [.may], section: "section-7.2", number: "7.2", title: "Host"),
    requirement(
      #"A proxy MUST NOT forward "Connection", and SHOULD log it."#, [.mustNot, .should],
      section: "section-7.6.1", number: "7.6.1", title: "Connection"),
    requirement(
      "Senders SHOULD be quick.", [.should], section: "acknowledgments", title: "Acknowledgments"),
  ]

  @Test func `requirements are grouped under their sections, in order`() {
    let sections = RequirementList.sections(of: Self.all)
    #expect(sections.map(\.anchor) == ["section-7.2", "section-7.6.1", "acknowledgments"])
    #expect(sections.map(\.heading) == ["7.2. Host", "7.6.1. Connection", "Acknowledgments"])
    #expect(sections[0].requirements.count == 2)
  }

  @Test func `the key words offered are those the document uses, in BCP 14's order`() {
    #expect(RequirementList.keywords(in: Self.all) == [.must, .mustNot, .should, .may])
  }

  @Test func `a key word filter keeps the requirements that use it`() {
    let filter = RequirementList.Filter(keyword: .should)
    #expect(
      filter.apply(to: Self.all).map(\.sectionAnchor) == ["section-7.6.1", "acknowledgments"])
  }

  /// "server" finds "the server MUST …": the words a requirement is about.
  @Test func `a text filter matches the sentence, ignoring case`() {
    #expect(RequirementList.Filter(text: "PROXY").apply(to: Self.all).count == 1)
    #expect(RequirementList.Filter(text: "  ").apply(to: Self.all).count == 4)
    #expect(RequirementList.Filter(keyword: .must, text: "server").apply(to: Self.all).isEmpty)
  }

  // MARK: - Checklist

  @Test func `the checklist in Markdown is a task list citing each section`() {
    let markdown = RequirementList.markdownChecklist(
      Array(Self.all.prefix(3)), document: .rfc(9110))
    #expect(
      markdown == """
        # RFC 9110 conformance checklist

        - [ ] **MUST** The client MUST send a Host field. ([RFC 9110, Section 7.2](rfc://9110#section-7.2))
        - [ ] **MAY** A server MAY reject it. ([RFC 9110, Section 7.2](rfc://9110#section-7.2))
        - [ ] **MUST NOT, SHOULD** A proxy MUST NOT forward "Connection", and SHOULD log it. ([RFC 9110, Section 7.6.1](rfc://9110#section-7.6.1))

        """)
  }

  /// A section without a number is cited by the document alone.
  @Test func `an unnumbered section is cited by the document`() {
    let markdown = RequirementList.markdownChecklist([Self.all[3]], document: .rfc(9110))
    #expect(markdown.contains("([RFC 9110](rfc://9110))"))
  }

  @Test func `an appendix is cited as an appendix`() {
    let inAppendix = Self.requirement(
      "It MUST be listed.", [.must], section: "appendix-A.1", number: "A.1", title: "Examples")
    let markdown = RequirementList.markdownChecklist([inAppendix], document: .rfc(9110))
    #expect(markdown.contains("[RFC 9110, Appendix A.1]"))
  }

  /// A field holding a comma or a quote is quoted, its quotes doubled.
  @Test func `the checklist in CSV quotes every field`() {
    let csv = RequirementList.csvChecklist(
      [Self.all[0], Self.all[2]], document: .rfc(9110))
    #expect(
      csv == """
        "Key words","Requirement","Citation","Link","Heuristic"\r
        "MUST","The client MUST send a Host field.","RFC 9110, Section 7.2","rfc://9110#section-7.2","No"\r
        "MUST NOT, SHOULD","A proxy MUST NOT forward ""Connection"", and SHOULD log it.","RFC 9110, Section 7.6.1","rfc://9110#section-7.6.1","No"\r

        """)
  }

  // MARK: - Recovered from legacy text

  private static let recovered = requirement(
    "A host MUST answer.", [.must], section: "section-3", number: "3", isHeuristic: true)

  /// Requirements read from legacy text say so: their sentences were recovered.
  @Test func `only requirements recovered from legacy text carry a note`() {
    #expect(RequirementList.note(for: Self.all) == nil)
    #expect(RequirementList.note(for: [Self.recovered]) == RequirementList.heuristicNote)
  }

  @Test func `the Markdown checklist of recovered requirements carries the note`() {
    let markdown = RequirementList.markdownChecklist([Self.recovered], document: .rfc(1122))
    #expect(
      markdown == """
        # RFC 1122 conformance checklist

        > \(RequirementList.heuristicNote)

        - [ ] **MUST** A host MUST answer. ([RFC 1122, Section 3](rfc://1122#section-3))

        """)
  }

  @Test func `the CSV checklist marks a recovered requirement`() {
    let csv = RequirementList.csvChecklist([Self.recovered], document: .rfc(1122))
    #expect(csv.hasSuffix(#","Yes"\#r\#n"#))
  }
}
