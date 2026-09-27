import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Bibliography: annotations")
struct ReferenceAnnotationTests {
  /// RFC 9842's `[FETCH]` entry, as the parser reads its `<annotation>`: the commit
  /// the RFC was written against, which is the whole reason to show it.
  private static let snapshot = URL(
    string:
      "https://fetch.spec.whatwg.org/commit-snapshots/5a9680638ebfc2b3b7f4efb2bef0b579a2663951/"
  )!

  private static let fetch = Reference(
    anchor: "FETCH",
    title: "Fetch Standard",
    rawText: "WHATWG Living Standard",
    annotation: [.text("Commit snapshot: "), .link(snapshot, [.text(snapshot.absoluteString)])]
  )

  @Test func anAnnotationReadsAsItsText() throws {
    let text = try #require(Self.fetch.annotationText)
    #expect(String(text.characters) == "Commit snapshot: \(Self.snapshot.absoluteString)")
  }

  /// A snapshot nobody can open is only half kept.
  @Test func anAnnotationKeepsItsLinks() throws {
    let text = try #require(Self.fetch.annotationText)
    let links = text.runs.compactMap { run -> (String, URL)? in
      guard let link = run.link else { return nil }
      return (String(text[run.range].characters), link)
    }
    #expect(links.count == 1)
    #expect(links.first?.0 == Self.snapshot.absoluteString)
    #expect(links.first?.1 == Self.snapshot)
  }

  @Test func anEntryWithoutAnAnnotationHasNoText() {
    #expect(Reference(anchor: "RFC2119", title: "Key words").annotationText == nil)
  }
}
