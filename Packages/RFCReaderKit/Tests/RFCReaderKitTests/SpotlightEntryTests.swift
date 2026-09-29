import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What system search knows about an RFC (#178): one item per RFC, found by its
/// number, title, abstract, working group and authors.
@Suite("Spotlight entry")
struct SpotlightEntryTests {
  private static let semantics = RFCMetadata(
    id: .rfc(9110), title: "HTTP Semantics",
    authors: [Author(name: "R. Fielding"), Author(name: "M. Nottingham")],
    date: PublicationDate(year: 2022), keywords: ["HTTP", "semantics"],
    abstract: "The Hypertext Transfer Protocol is a stateless protocol.", workingGroup: "httpbis")

  @Test func `an RFC is titled with its designation and its title`() {
    let entry = SpotlightEntry(Self.semantics)
    #expect(entry.title == "RFC 9110: HTTP Semantics")
    #expect(entry.description == "The Hypertext Transfer Protocol is a stateless protocol.")
  }

  /// People type a number every way it is written.
  @Test func `the number is a keyword in every spelling, beside the group and authors`() {
    let keywords = SpotlightEntry(Self.semantics).keywords
    #expect(keywords.starts(with: ["9110", "RFC 9110", "RFC9110"]))
    for expected in ["httpbis", "R. Fielding", "M. Nottingham", "HTTP", "semantics"] {
      #expect(keywords.contains(expected))
    }
  }

  /// Obsoleted RFCs are still looked up by number, so they are indexed, and say so.
  @Test func `an obsoleted RFC says what replaced it`() {
    var old = Self.semantics
    old.id = .rfc(7231)
    old.obsoletedBy = [.rfc(9110)]
    #expect(
      SpotlightEntry(old).description
        == "Obsoleted by RFC 9110. The Hypertext Transfer Protocol is a stateless protocol.")
  }

  @Test func `an RFC without an abstract has an empty description`() {
    var bare = Self.semantics
    bare.abstract = nil
    #expect(SpotlightEntry(bare).description == "")
  }

  /// A result arrives back as its identifier, and opens the RFC it names.
  @Test func `the identifier names the document it came from`() {
    let entry = SpotlightEntry(Self.semantics)
    #expect(entry.identifier == "rfc9110")
    #expect(SpotlightEntry.documentID(fromIdentifier: entry.identifier) == .rfc(9110))
    #expect(SpotlightEntry.documentID(fromIdentifier: "not a document") == nil)
  }
}
