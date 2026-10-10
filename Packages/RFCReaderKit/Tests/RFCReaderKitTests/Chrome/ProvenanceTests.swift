import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// How a document got where it is (#364): stream, working group and status as one
/// path, each step opening what it names.
@Suite("Provenance")
struct ProvenanceTests {
  private let advanced = RFCMetadata(
    id: .rfc(9110), title: "HTTP Semantics", date: PublicationDate(year: 2022, month: 6),
    currentStatus: .internetStandard, publicationStatus: .proposedStandard, stream: .ietf,
    workingGroup: "httpbis")

  private func provenance(
    _ metadata: RFCMetadata, locale: Locale = .english
  ) -> Provenance {
    Provenance(metadata, locale: locale)
  }

  @Test func `the steps are stream, working group and status`() {
    let steps = provenance(advanced).steps
    #expect(steps.map(\.kind) == [.stream, .workingGroup, .status])
    #expect(steps.map(\.text) == ["IETF", "httpbis", "Proposed Standard → Internet Standard"])
  }

  /// The stream and the status open their glossary entries (#362), the group its card
  /// (#363).
  @Test func `each step opens what it names`() {
    #expect(
      provenance(advanced).steps.map(\.target) == [
        .glossary(.stream(.ietf)), .workingGroup("httpbis"),
        .glossary(.status(.internetStandard)),
      ])
  }

  /// The index fills the field for a document from no group with a sentence, which is
  /// no group's name: such a document goes from its stream to its status.
  @Test func `a document from no working group goes from stream to status`() {
    var metadata = advanced
    metadata.workingGroup = "NON WORKING GROUP"
    metadata.stream = .independent
    #expect(provenance(metadata).steps.map(\.kind) == [.stream, .status])
    metadata.workingGroup = nil
    #expect(provenance(metadata).steps.map(\.kind) == [.stream, .status])
  }

  @Test func `an unchanged status is named once`() {
    var metadata = advanced
    metadata.publicationStatus = .internetStandard
    #expect(provenance(metadata).steps.last?.text == "Internet Standard")
    metadata.publicationStatus = .unknown
    #expect(provenance(metadata).steps.last?.text == "Internet Standard")
  }

  @Test func `a status the index does not know ends the chain before it`() {
    var metadata = advanced
    metadata.currentStatus = .unknown
    #expect(provenance(metadata).steps.map(\.kind) == [.stream, .workingGroup])
  }

  /// VoiceOver names each step, since the chain's arrows are not read.
  @Test func `each step is said with its name`() {
    #expect(
      provenance(advanced).steps.map(\.accessibilityLabel) == [
        "Stream: IETF", "Working group: httpbis",
        "Status: Proposed Standard, now Internet Standard",
      ])
  }

  @Test func `the chain says when it was published`() {
    #expect(provenance(advanced).published == "Published June 2022")
  }

  /// The chain's words are the interface's; the stream's and the status's names are
  /// the IETF's designations, and stay English.
  @Test func `the words are in the interface's language`() {
    let chain = provenance(advanced, locale: .german)
    #expect(chain.title == "Herkunft")
    #expect(chain.published == "Veröffentlicht Juni 2022")
    #expect(
      chain.steps.map(\.accessibilityLabel) == [
        "Stream: IETF", "Working Group: httpbis",
        "Status: Proposed Standard, jetzt Internet Standard",
      ])
  }
}
