import Testing

@testable import RFCKit

/// A status's names: the full one, and the short one a list row's badge shows.
@Suite("Publication status")
struct PublicationStatusTests {
  /// Words, not abbreviations: "STD" is the series' name rather than a status.
  /// BCP is the exception, being what the IETF itself calls them.
  @Test func `a short name is a word`() {
    #expect(PublicationStatus.internetStandard.shortName == "Standard")
    #expect(PublicationStatus.draftStandard.shortName == "Draft Standard")
    #expect(PublicationStatus.proposedStandard.shortName == "Proposed")
    #expect(PublicationStatus.informational.shortName == "Informational")
    #expect(PublicationStatus.bestCurrentPractice.shortName == "BCP")
  }

  @Test(arguments: PublicationStatus.allCases)
  func `a short name is no longer than the full one`(status: PublicationStatus) {
    #expect(status.shortName.count <= status.displayName.count)
  }
}
