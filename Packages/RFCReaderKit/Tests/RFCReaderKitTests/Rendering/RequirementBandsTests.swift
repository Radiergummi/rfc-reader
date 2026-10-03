import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Where Implementer's requirement bands go (#700): each BCP 14 sentence the
/// requirements index found, as a range of the built text, so the band is drawn
/// behind exactly that sentence and nothing is rebuilt for it.
@Suite("Requirement bands")
struct RequirementBandsTests {
  /// The words of `text`, letters and digits only: what a band's text and its
  /// sentence must agree on, whatever the build made of their spacing and brackets.
  private static func words(_ text: String) -> [String] {
    text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
  }

  private static func built(_ document: RFCDocument) -> BuiltDocument {
    DocumentTextBuilder.build(document, style: ReadingStyle())
  }

  @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
  func `every requirement is banded, and its band says its sentence`(name: String) throws {
    let document = try Fixtures.document(named: name)
    let requirements = Requirements.extract(from: document)
    try #require(!requirements.isEmpty)
    let built = Self.built(document)
    let bands = RequirementBands(requirements, in: built)
    let text = built.text.string as NSString
    #expect(bands.ranges.count == requirements.count)
    for (band, requirement) in zip(bands.ranges, requirements) {
      #expect(Self.words(text.substring(with: band)) == Self.words(requirement.sentence))
    }
  }

  /// From the sentence's first character to its stop, so the band neither starts on
  /// a space nor stops short of the full stop.
  @Test func `a band runs from the sentence's first character to its stop`() throws {
    let document = try Fixtures.rfc8999()
    let requirements = Requirements.extract(from: document)
    let built = Self.built(document)
    let text = built.text.string as NSString
    for (band, requirement) in zip(RequirementBands(requirements, in: built).ranges, requirements) {
      let banded = text.substring(with: band)
      #expect(banded.first == requirement.sentence.first, "\(banded)")
      #expect(banded.last == requirement.sentence.last, "\(banded)")
    }
  }

  @Test func `the bands are in order and never overlap`() throws {
    let document = try Fixtures.rfc8999()
    let bands = RequirementBands(Requirements.extract(from: document), in: Self.built(document))
    for (earlier, later) in zip(bands.ranges, bands.ranges.dropFirst()) {
      #expect(NSMaxRange(earlier) <= later.location)
    }
  }

  /// A requirement whose sentence the build does not have, as one of another
  /// document's would be, is left unbanded rather than banding whatever is near.
  @Test func `a sentence the build does not have gets no band`() throws {
    let document = try Fixtures.rfc8999()
    let built = Self.built(document)
    let requirement = try #require(Requirements.extract(from: document).first)
    var stranger = requirement
    stranger.sentence = "Nothing in this document MUST be read as this sentence."
    #expect(RequirementBands([stranger], in: built).ranges.isEmpty)
    #expect(RequirementBands([stranger, requirement], in: built).ranges.count == 1)
  }

  /// The bands a fragment draws: every one that meets its range, whole, since
  /// where a band starts and ends decides which of its corners round.
  @Test func `the bands meeting a range are found whole`() throws {
    let document = try Fixtures.rfc8999()
    let bands = RequirementBands(Requirements.extract(from: document), in: Self.built(document))
    let band = try #require(bands.ranges.dropFirst().first)
    let inside = NSRange(location: band.location + 1, length: 1)
    #expect(bands.ranges(meeting: inside) == [band])
    let across = NSRange(location: band.location - 1, length: band.length + 2)
    #expect(bands.ranges(meeting: across).contains(band))
    #expect(RequirementBands().ranges(meeting: inside).isEmpty)
  }
}
