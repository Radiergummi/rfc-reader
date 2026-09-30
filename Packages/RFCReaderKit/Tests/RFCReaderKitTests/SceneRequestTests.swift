import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A new window on iPad is asked for with a user activity that carries the link it
/// opens (#158).
@Suite("Scene request")
struct SceneRequestTests {
  /// A place is a section number or an anchor (#276), and both survive.
  @Test(arguments: ["8.3", "A.1", "sample-varint"])
  func `a link survives the activity's user info`(place: String) {
    let link = RFCLink(id: .rfc(9110), section: place)
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link)) == link)
  }

  /// A section's anchor goes as its fragment and comes back as its number, which
  /// names the same place.
  @Test func `a section's anchor comes back as its number`() {
    let link = RFCLink(id: .rfc(9110), section: "section-8.3")
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link))?.section == "8.3")
  }

  @Test func `a series link survives the activity's user info`() {
    let link = RFCLink(id: DocumentID(series: .bcp, number: 14))
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
