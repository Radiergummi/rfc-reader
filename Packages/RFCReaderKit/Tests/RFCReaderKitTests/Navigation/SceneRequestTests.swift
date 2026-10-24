import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A new window on iPad is asked for with a user activity that carries the link it
/// opens (#158).
@Suite("Scene request")
struct SceneRequestTests {
  /// A place is a section or an anchor (#276), and both survive.
  @Test(
    arguments: [
      RFCLink(id: .rfc(9110), section: "8.3"), RFCLink(id: .rfc(9110), section: "A.1"),
      RFCLink(id: .rfc(9110), anchor: "sample-varint"),
    ])
  func `a link survives the activity's user info`(link: RFCLink) {
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link)) == .rfc(link))
  }

  /// A section's anchor goes as its fragment and comes back as its number, which
  /// names the same place.
  @Test func `a section's anchor comes back as its number`() {
    let link = RFCLink(id: .rfc(9110), section: "section-8.3")
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link))?.place == "8.3")
  }

  @Test func `a series link survives the activity's user info`() {
    let link = RFCLink(id: DocumentID(series: .bcp, number: 14))
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link)) == .rfc(link))
  }

  /// A draft opens in a window of its own as an RFC does (#728).
  @Test func `a draft's link survives the activity's user info`() throws {
    let link = ReadableLink.draft(
      DraftLink(id: try #require(DraftID(parsing: "draft-ietf-quic-http-34")), section: "4.2"))
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link)) == link)
  }

  @Test func `an activity without a link opens nothing`() {
    #expect(SceneRequest.link(from: nil) == nil)
    #expect(SceneRequest.link(from: [:]) == nil)
    #expect(SceneRequest.link(from: [SceneRequest.linkKey: 42]) == nil)
    #expect(SceneRequest.link(from: [SceneRequest.linkKey: "https://example.com"]) == nil)
  }

  @Test func `the activity type is the app's own`() {
    #expect(SceneRequest.activityType == "me.mazetti.rfc-reader.open")
  }
}
