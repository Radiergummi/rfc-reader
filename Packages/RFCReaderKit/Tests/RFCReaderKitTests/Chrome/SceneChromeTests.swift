import SwiftUI
import Testing

@testable import RFCReaderKit

/// What a scene's size classes say about its chrome, worked out once (#257).
@Suite("Scene chrome")
struct SceneChromeTests {
  @Test(arguments: [
    (UserInterfaceSizeClass?.some(.compact), true),
    (.some(.regular), false),
    (nil, false),
  ])
  func `a compact width is collapsed`(horizontal: UserInterfaceSizeClass?, collapsed: Bool) {
    #expect(SceneChrome(horizontal: horizontal, vertical: .regular).isCollapsed == collapsed)
  }

  /// A phone held sideways: the bars are short, whatever the width.
  @Test(arguments: [
    (UserInterfaceSizeClass?.some(.compact), true),
    (.some(.regular), false),
    (nil, false),
  ])
  func `a compact height has short bars`(vertical: UserInterfaceSizeClass?, short: Bool) {
    #expect(SceneChrome(horizontal: .compact, vertical: vertical).hasShortBars == short)
    #expect(SceneChrome(horizontal: .regular, vertical: vertical).hasShortBars == short)
  }

  /// Before a scene has traits, SwiftUI passes no size class, and the scene reads as
  /// side by side with tall bars: what a view that compared with `.compact` got.
  @Test func `the default is side by side with tall bars`() {
    #expect(SceneChrome() == SceneChrome(horizontal: nil, vertical: nil))
    #expect(!SceneChrome().isCollapsed)
    #expect(!SceneChrome().hasShortBars)
  }
}
