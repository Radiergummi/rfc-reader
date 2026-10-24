import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What the header says of a draft on screen (#728).
@Suite("Draft status")
struct DraftStatusTests {
  private static let name = "draft-ietf-example-protocol"

  private static func revision(_ number: String) -> DraftID {
    DraftID(name: name, revision: number)!
  }

  private static func info(newest: String, publishedAs: DocumentID? = nil) -> DraftInfo {
    DraftInfo(
      name: name, title: "An Example Protocol", newestRevision: newest, state: "Active",
      revisions: (0...(Int(newest) ?? 0)).map {
        DraftInfo.Revision(
          revision: String(format: "%02d", $0),
          published: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 8_000_000))
      },
      publishedAs: publishedAs)
  }

  @Test func `a draft says it is not an RFC, and which revision it is`() {
    let status = DraftStatus(
      shown: Self.revision("03"), info: Self.info(newest: "03"), locale: .english)
    #expect(status.mark == "Internet-Draft, not an RFC")
    #expect(status.revisionLabel == "Revision 3")
    #expect(status.notice == nil)
    #expect(status.newer == nil)
  }

  @Test func `an older revision names the newest`() {
    let status = DraftStatus(
      shown: Self.revision("01"), info: Self.info(newest: "03"), locale: .english)
    #expect(status.notice == "Revision 3 is the newest")
    #expect(status.newer == Self.revision("03"))
  }

  @Test func `a published draft names its RFC, whichever revision is shown`() {
    let status = DraftStatus(
      shown: Self.revision("03"), info: Self.info(newest: "03", publishedAs: .rfc(9999)),
      locale: .english)
    #expect(status.notice == "Published as RFC 9999")
    #expect(status.publishedAs == .rfc(9999))
  }

  @Test func `the revisions to switch to are the newest first, the one shown marked`() {
    let status = DraftStatus(
      shown: Self.revision("01"), info: Self.info(newest: "02"), locale: .english)
    #expect(status.choices.map(\.draft) == ["02", "01", "00"].map(Self.revision))
    #expect(status.choices.map(\.label) == ["Revision 2", "Revision 1", "Revision 0"])
    #expect(status.choices.map(\.isShown) == [false, true, false])
    #expect(status.choices.allSatisfy { $0.date != nil })
  }

  /// Before Datatracker answers, or offline with nothing kept, only what is on
  /// screen is known.
  @Test func `without Datatracker's word the revision on screen is all there is`() {
    let status = DraftStatus(shown: Self.revision("05"), info: nil, locale: .english)
    #expect(status.notice == nil)
    #expect(status.choices.map(\.draft) == [Self.revision("05")])
  }

  /// Datatracker's description of another draft says nothing of this one.
  @Test func `another draft's description is not this one's`() {
    let other = DraftInfo(
      name: "draft-other-thing", title: "", newestRevision: "09", state: nil, revisions: [],
      publishedAs: .rfc(1))
    let status = DraftStatus(shown: Self.revision("05"), info: other, locale: .english)
    #expect(status.notice == nil)
    #expect(status.publishedAs == nil)
  }

  /// What a revision can be compared with (#729): the ones before it.
  @Test func `the revisions to compare with are the older ones, the nearest first`() {
    let status = DraftStatus(
      shown: Self.revision("02"), info: Self.info(newest: "03"), locale: .english)
    #expect(status.olderChoices.map(\.draft) == ["01", "00"].map(Self.revision))
  }
}
