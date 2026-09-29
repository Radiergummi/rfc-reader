import CoreSpotlight
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

  /// The index's placeholder for an individual or independent submission is not a
  /// group, and as a keyword it would match thousands of unrelated RFCs.
  @Test func `a document from no working group has no group keyword`() {
    var individual = Self.semantics
    individual.workingGroup = "NON WORKING GROUP"
    #expect(!SpotlightEntry(individual).keywords.contains("NON WORKING GROUP"))
  }

  // MARK: - When to index again

  private static let day: TimeInterval = 86_400
  private static let now = Date(timeIntervalSince1970: 1_700_006_400)
  private static let entries = [SpotlightEntry(semantics)]

  /// Nothing to do at a launch whose index is the one already indexed, whenever and
  /// however it arrived: fetched again, read from the cache, or bundled.
  @Test func `the same entries in the same week are not indexed again`() {
    let weekStart = Date(timeIntervalSince1970: 1_700_096_400)
    #expect(
      SpotlightEntry.clientState(for: Self.entries, now: weekStart)
        == SpotlightEntry.clientState(
          for: [SpotlightEntry(Self.semantics)], now: weekStart.addingTimeInterval(2 * Self.day)))
  }

  @Test func `a changed entry is indexed again`() {
    var obsoleted = Self.semantics
    obsoleted.obsoletedBy = [.rfc(9999)]
    #expect(
      SpotlightEntry.clientState(for: Self.entries, now: Self.now)
        != SpotlightEntry.clientState(for: [SpotlightEntry(obsoleted)], now: Self.now))
  }

  /// Where one field ends and the next begins is part of what is compared.
  @Test func `moving text between fields is a change`() {
    var first = SpotlightEntry(Self.semantics)
    var second = first
    first.keywords = ["ab", "c"]
    second.keywords = ["a", "bc"]
    #expect(
      SpotlightEntry.clientState(for: [first], now: Self.now)
        != SpotlightEntry.clientState(for: [second], now: Self.now))
  }

  /// Items expire, so an index that never changes, as on a Mac that stays offline,
  /// is still renewed before they do.
  @Test func `the same entries are indexed again a week on, before they expire`() {
    #expect(
      SpotlightEntry.clientState(for: Self.entries, now: Self.now)
        != SpotlightEntry.clientState(
          for: Self.entries, now: Self.now.addingTimeInterval(7 * Self.day)))
    #expect(SpotlightEntry.lifetime > 14 * Self.day)
  }

  /// An app left running is checked again when it is next activated in a new week,
  /// so its items are renewed before they expire; within the week an activation
  /// does nothing.
  @Test func `an activation in the same week does not check again`() {
    let weekStart = Date(timeIntervalSince1970: 1_700_096_400)
    #expect(
      !SpotlightEntry.isRecheckDue(
        lastCheckedAt: weekStart, now: weekStart.addingTimeInterval(6 * Self.day)))
  }

  @Test func `an activation in a later week checks again`() {
    let weekStart = Date(timeIntervalSince1970: 1_700_096_400)
    #expect(
      SpotlightEntry.isRecheckDue(
        lastCheckedAt: weekStart, now: weekStart.addingTimeInterval(7 * Self.day)))
    #expect(
      SpotlightEntry.isRecheckDue(
        lastCheckedAt: weekStart, now: weekStart.addingTimeInterval(40 * Self.day)))
  }

  /// A result arrives back as its identifier, and opens the RFC it names.
  @Test func `a chosen result names the document it came from`() {
    let activity = NSUserActivity(activityType: CSSearchableItemActionType)
    activity.userInfo = [
      CSSearchableItemActivityIdentifier: SpotlightEntry(Self.semantics).identifier
    ]
    #expect(SpotlightEntry.documentID(from: activity) == .rfc(9110))
  }

  @Test func `an activity that is not a chosen result names nothing`() {
    let other = NSUserActivity(activityType: "me.mazetti.rfc-reader.other")
    other.userInfo = [CSSearchableItemActivityIdentifier: "rfc9110"]
    #expect(SpotlightEntry.documentID(from: other) == nil)
    let foreign = NSUserActivity(activityType: CSSearchableItemActionType)
    foreign.userInfo = [CSSearchableItemActivityIdentifier: "not a document"]
    #expect(SpotlightEntry.documentID(from: foreign) == nil)
  }
}
