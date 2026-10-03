import Foundation
import Testing

@testable import RFCKit

/// The XML `corpus-build` publishes for a legacy RFC is a fixed point: parsing it and
/// serializing the result again, with the same options, gives the same bytes. Whatever
/// the serializer writes, the parser reads back as the same document, so a patched
/// document that is re-serialized changes only where the patch changed it (#197,
/// #683).
@Suite("RFCXML serializer: round trip")
struct SerializerRoundTripTests {
  /// The options a corpus run serializes with: a generator comment and the source.
  private static func serializer(for fixture: String) -> RFCXMLSerializer {
    let stem = String(fixture.dropLast(4))
    return RFCXMLSerializer(
      options: .init(
        generatorComment: "Generated from \(stem).txt.",
        sourceURL: DocumentID(parsing: stem).map { RFCEditorEndpoints.document($0, format: .text) }
      ))
  }

  /// The first line the two differ in, with its number, for a failure to point at.
  private static func firstDifference(_ first: String, _ second: String) -> String {
    let firstLines = first.split(separator: "\n", omittingEmptySubsequences: false)
    let secondLines = second.split(separator: "\n", omittingEmptySubsequences: false)
    for (number, (line, other)) in zip(firstLines, secondLines).enumerated() where line != other {
      return "line \(number + 1):\n  written: \(line)\n  again:   \(other)"
    }
    return "line \(min(firstLines.count, secondLines.count) + 1): one ends early"
  }

  @Test func `every legacy fixture serializes to a fixed point`() throws {
    var changed: [String] = []
    for fixture in try Fixtures.legacyTexts() {
      let serializer = Self.serializer(for: fixture)
      let written = serializer.serialize(try Fixtures.document(fixture))
      let again = serializer.serialize(try RFCXMLParser.parse(Data(written.utf8)))
      if again != written {
        changed.append("\(fixture), \(Self.firstDifference(written, again))")
      }
    }
    #expect(changed.isEmpty, "\(changed.joined(separator: "\n"))")
  }
}
