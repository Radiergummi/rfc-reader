import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a refresh tells the reader about its bookmarks (#191): each event once, and
/// only for an RFC that was bookmarked at both ends of the comparison.
@Suite("Bookmark events")
struct BookmarkEventsTests {
  private static let now = Date(timeIntervalSince1970: 1_790_000_000)
  private static let bookmarked: Set<DocumentID> = [.rfc(9990)]

  private static func index(
    obsoletedBy: [DocumentID] = [], updatedBy: [DocumentID] = [], errata: Bool = false
  ) -> RFCIndex {
    RFCIndex(rfcs: [
      RFCMetadata(
        id: .rfc(9990), title: "An Example Protocol", date: PublicationDate(year: 2020, month: 1),
        obsoletedBy: obsoletedBy, updatedBy: updatedBy,
        errataURL: errata ? URL(string: "https://www.rfc-editor.org/errata/rfc9990") : nil),
      RFCMetadata(
        id: .rfc(9991), title: "Another Example", date: PublicationDate(year: 2021, month: 1),
        obsoletedBy: obsoletedBy),
    ])
  }

  private static func revisions(_ drafts: [String: RevisionStage]) -> RFCRevisions {
    RFCRevisions(
      generatedAt: now,
      revisions: [
        9990: drafts.map { draft, stage in
          RFCRevisions.Revision(
            relation: .obsoletes, draft: draft, revision: "03", published: now, stream: "ietf",
            group: "example", intendedStatus: "Proposed Standard", stage: stage)
        }
      ])
  }

  private static func baseline(
    _ index: RFCIndex?, _ revisions: RFCRevisions? = nil, bookmarks: Set<DocumentID> = bookmarked,
    after previous: BookmarkBaseline? = nil
  ) -> BookmarkBaseline {
    BookmarkBaseline(
      bookmarks: bookmarks, index: index, revisions: revisions, carryingOver: previous)
  }

  private static func events(
    from old: BookmarkBaseline?, to new: BookmarkBaseline
  ) -> [BookmarkEvent] {
    BookmarkEvents.between(old, new)
  }

  // MARK: - Events

  @Test func `nothing changed is no event`() {
    let old = Self.baseline(Self.index(), Self.revisions(["draft-a": .inGroup]))
    let new = Self.baseline(Self.index(), Self.revisions(["draft-a": .inGroup]))
    #expect(Self.events(from: old, to: new).isEmpty)
  }

  @Test func `a first comparison reports no history`() {
    let new = Self.baseline(
      Self.index(obsoletedBy: [.rfc(9999)], errata: true), Self.revisions(["draft-a": .inGroup]))
    #expect(Self.events(from: nil, to: new).isEmpty)
  }

  @Test func `a new obsoleting RFC is an event`() {
    let old = Self.baseline(Self.index())
    let new = Self.baseline(Self.index(obsoletedBy: [.rfc(9999)]))
    #expect(Self.events(from: old, to: new) == [.obsoleted(.rfc(9990), newer: [.rfc(9999)])])
  }

  @Test func `a new updating RFC is an event, and one already known is not`() {
    let old = Self.baseline(Self.index(updatedBy: [.rfc(9997)]))
    let new = Self.baseline(Self.index(updatedBy: [.rfc(9997), .rfc(9998)]))
    #expect(Self.events(from: old, to: new) == [.updated(.rfc(9990), newer: [.rfc(9998)])])
  }

  @Test func `errata newly listed are an event`() {
    let old = Self.baseline(Self.index())
    let new = Self.baseline(Self.index(errata: true))
    #expect(Self.events(from: old, to: new) == [.errataListed(.rfc(9990))])
  }

  @Test func `a draft newly revising the RFC is an event`() {
    let old = Self.baseline(Self.index(), Self.revisions([:]))
    let new = Self.baseline(Self.index(), Self.revisions(["draft-a": .inGroup]))
    #expect(
      Self.events(from: old, to: new) == [
        .revisionStarted(
          .rfc(9990), draft: "draft-a", relation: .obsoletes, stage: .inGroup,
          stream: "ietf")
      ])
  }

  @Test func `a draft reaching the RFC Editor queue is an event`() {
    let old = Self.baseline(Self.index(), Self.revisions(["draft-a": .iesgReview]))
    let new = Self.baseline(Self.index(), Self.revisions(["draft-a": .rfcEditorQueue]))
    #expect(
      Self.events(from: old, to: new) == [
        .revisionQueued(.rfc(9990), draft: "draft-a", relation: .obsoletes)
      ])
  }

  @Test func `a draft moving between earlier stages is no event`() {
    let old = Self.baseline(Self.index(), Self.revisions(["draft-a": .inGroup]))
    let new = Self.baseline(Self.index(), Self.revisions(["draft-a": .iesgReview]))
    #expect(Self.events(from: old, to: new).isEmpty)
  }

  @Test func `a draft that drops out of the file and comes back is not reported again`() {
    let first = Self.baseline(Self.index(), Self.revisions(["draft-a": .inGroup]))
    let second = Self.baseline(Self.index(), Self.revisions([:]), after: first)
    let third = Self.baseline(Self.index(), Self.revisions(["draft-a": .inGroup]), after: second)
    #expect(Self.events(from: first, to: second).isEmpty)
    #expect(Self.events(from: second, to: third).isEmpty)
  }

  @Test func `an RFC that is not bookmarked is no event`() {
    let old = Self.baseline(Self.index())
    let new = Self.baseline(Self.index(obsoletedBy: [.rfc(9999)]))
    let events = Self.events(from: old, to: new)
    #expect(!events.contains { $0.document == .rfc(9991) })
  }

  @Test func `a newly bookmarked RFC reports nothing from before it was bookmarked`() {
    let old = Self.baseline(Self.index(), bookmarks: [])
    let new = Self.baseline(Self.index(obsoletedBy: [.rfc(9999)], errata: true))
    #expect(Self.events(from: old, to: new).isEmpty)
  }

  @Test func `no event is reported twice across two comparisons`() {
    let first = Self.baseline(Self.index(), Self.revisions([:]))
    let second = Self.baseline(
      Self.index(obsoletedBy: [.rfc(9999)], errata: true), Self.revisions(["draft-a": .inGroup]),
      after: first)
    let third = Self.baseline(
      Self.index(obsoletedBy: [.rfc(9999)], errata: true), Self.revisions(["draft-a": .inGroup]),
      after: second)
    #expect(Self.events(from: first, to: second).count == 3)
    #expect(Self.events(from: second, to: third).isEmpty)
  }

  // MARK: - Data not there

  @Test func `a comparison without an index keeps the last index it had`() {
    let first = Self.baseline(Self.index())
    let second = Self.baseline(nil, Self.revisions([:]), after: first)
    let third = Self.baseline(Self.index(obsoletedBy: [.rfc(9999)]), after: second)
    #expect(Self.events(from: first, to: second).isEmpty)
    #expect(Self.events(from: second, to: third) == [.obsoleted(.rfc(9990), newer: [.rfc(9999)])])
  }

  @Test func `a comparison without the revisions keeps the last revisions it had`() {
    let first = Self.baseline(Self.index(), Self.revisions(["draft-a": .iesgReview]))
    let second = Self.baseline(Self.index(), nil, after: first)
    let third = Self.baseline(
      Self.index(), Self.revisions(["draft-a": .rfcEditorQueue]), after: second)
    #expect(Self.events(from: first, to: second).isEmpty)
    #expect(
      Self.events(from: second, to: third) == [
        .revisionQueued(.rfc(9990), draft: "draft-a", relation: .obsoletes)
      ])
  }

  @Test func `what is carried over drops an RFC no longer bookmarked`() {
    let first = Self.baseline(Self.index())
    let second = Self.baseline(nil, bookmarks: [], after: first)
    #expect(second.index?.isEmpty == true)
  }

  @Test func `a baseline survives a round trip through JSON`() throws {
    let baseline = Self.baseline(
      Self.index(obsoletedBy: [.rfc(9999)], errata: true), Self.revisions(["draft-a": .inGroup]))
    let decoded = try BookmarkBaseline.decode(baseline.encoded())
    #expect(decoded == baseline)
  }

  // MARK: - Notices

  @Test func `one refresh's events about an RFC are one notice`() {
    let notices = BookmarkNotice.notices(
      for: [
        .obsoleted(.rfc(9990), newer: [.rfc(9999)]),
        .errataListed(.rfc(9990)),
        .revisionQueued(.rfc(9991), draft: "draft-b", relation: .updates),
      ], index: Self.index(), locale: .english)
    #expect(notices.map(\.document) == [.rfc(9990), .rfc(9991)])
    #expect(notices[0].title == "RFC 9990")
    #expect(notices[0].subtitle == "An Example Protocol")
    #expect(notices[0].body == "Obsoleted by RFC 9999.\nNow has errata.")
    #expect(notices[1].body == "Being updated by draft-b, in the RFC Editor queue.")
  }

  @Test func `a notice words a draft by its relation and stage`() {
    let notices = BookmarkNotice.notices(
      for: [
        .updated(.rfc(9990), newer: [.rfc(9997), .rfc(9998)]),
        .revisionStarted(
          .rfc(9990), draft: "draft-a", relation: .obsoletes, stage: .inGroup,
          stream: "ietf"),
      ], index: Self.index(), locale: .english)
    #expect(
      notices.first?.body
        == "Updated by RFC 9997 and RFC 9998.\nBeing replaced by draft-a, in the working group.")
  }

  /// The list is the locale's: in English, with a serial comma.
  @Test func `three newer RFCs are listed as the language lists them`() {
    let notice = BookmarkNotice.notices(
      for: [.obsoleted(.rfc(9990), newer: [.rfc(9996), .rfc(9997), .rfc(9998)])], index: nil,
      locale: .english
    ).first
    #expect(notice?.body == "Obsoleted by RFC 9996, RFC 9997, and RFC 9998.")
  }

  @Test func `a notice opens its RFC`() {
    let notice = BookmarkNotice.notices(
      for: [.errataListed(.rfc(9990))], index: nil, locale: .english
    ).first
    #expect(notice?.url == URL(string: "rfc://9990"))
    #expect(notice?.subtitle == nil)
  }
}
