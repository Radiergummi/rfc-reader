import RFCKit
import Testing

@testable import RFCReaderKit

/// The contents panel lists the sections a build holds, so every row it shows is a
/// place the reader can scroll to (#599).
@Suite("Reachable sections")
struct ReachableSectionsTests {
  @Test func `every section listed is one the build can scroll to`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let listed = built.reachableSections(of: document)
    #expect(!listed.isEmpty)
    #expect(listed.allSatisfy { built.anchors.sections.offset(of: $0.anchor) != nil })
  }

  @Test func `they are the document's own sections, in its order`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let order = Dictionary(
      document.allSections.enumerated().map { ($1.anchor, $0) },
      uniquingKeysWith: { first, _ in first })
    let positions = built.reachableSections(of: document).map { order[$0.anchor] }
    #expect(positions.allSatisfy { $0 != nil })
    #expect(positions.compactMap(\.self) == positions.compactMap(\.self).sorted())
  }
}
