import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// A new window on iPad is asked for with a user activity that carries the link it
/// opens (#158).
@Suite("Scene request")
struct SceneRequestTests {
  @Test func `a link survives the activity's user info`() {
    let link = RFCLink(id: .rfc(9110), section: "section-8.3")
    #expect(SceneRequest.link(from: SceneRequest.userInfo(for: link)) == link)
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
