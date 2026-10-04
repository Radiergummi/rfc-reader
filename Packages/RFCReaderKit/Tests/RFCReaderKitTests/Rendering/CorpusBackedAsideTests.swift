import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Asides whose text opens with "Note:" and states a requirement in the same
/// sentence (#700): RFC 9110 and RFC 9022 have them, and none of the committed
/// fixtures does. The caption takes the label's place in the build, and the band
/// still finds the sentence.
@Suite("Corpus-backed: aside captions", .enabled(if: CorpusXML.isAvailable))
struct CorpusBackedAsideTests {
  @Test(arguments: ["rfc9110", "rfc9022"])
  func `a requirement an aside's label opened is still banded`(stem: String) throws {
    let document = try CorpusXML.document(stem)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let requirements = Requirements.extract(from: document)
    let labeled = requirements.filter {
      $0.sentence.hasPrefix("Note:") || $0.sentence.hasPrefix("NOTE:")
    }
    try #require(!labeled.isEmpty)
    let bands = RequirementBands(requirements, in: built)
    #expect(bands.ranges.count == requirements.count)
  }
}
