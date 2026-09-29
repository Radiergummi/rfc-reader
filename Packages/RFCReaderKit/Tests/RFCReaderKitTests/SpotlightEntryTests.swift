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

  // MARK: - When to index again

  private static let day: TimeInterval = 86_400
  private static let indexDate = Date(timeIntervalSince1970: 1_700_000_000)

  /// Nothing to do at a launch whose index is the one already indexed.
  @Test func `the same index in the same week is not indexed again`() {
    let weekStart = Date(timeIntervalSince1970: 1_700_096_400)
    #expect(
      SpotlightEntry.clientState(indexUpdatedAt: Self.indexDate, now: weekStart)
        == SpotlightEntry.clientState(
          indexUpdatedAt: Self.indexDate, now: weekStart.addingTimeInterval(2 * Self.day)))
  }

  @Test func `a new index is indexed again`() {
    let now = Date(timeIntervalSince1970: 1_700_006_400)
    #expect(
      SpotlightEntry.clientState(indexUpdatedAt: Self.indexDate, now: now)
        != SpotlightEntry.clientState(
          indexUpdatedAt: Self.indexDate.addingTimeInterval(Self.day), now: now))
  }

  /// Items expire, so an index that never changes, as on a Mac that stays offline,
  /// is still renewed before they do.
  @Test func `the same index is indexed again a week on, before its items expire`() {
    let now = Date(timeIntervalSince1970: 1_700_006_400)
    #expect(
      SpotlightEntry.clientState(indexUpdatedAt: Self.indexDate, now: now)
        != SpotlightEntry.clientState(
          indexUpdatedAt: Self.indexDate, now: now.addingTimeInterval(7 * Self.day)))
    #expect(SpotlightEntry.lifetime > 14 * Self.day)
  }

  /// A result arrives back as its identifier, and opens the RFC it names.
  @Test func `the identifier names the document it came from`() {
    let entry = SpotlightEntry(Self.semantics)
    #expect(entry.identifier == "rfc9110")
    #expect(SpotlightEntry.documentID(fromIdentifier: entry.identifier) == .rfc(9110))
    #expect(SpotlightEntry.documentID(fromIdentifier: "not a document") == nil)
  }
}
