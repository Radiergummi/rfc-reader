import Testing

@testable import RFCReaderKit

/// Whether the Mac app opens a reader window of its own at launch (#762, #939).
@Suite("Launch window")
struct LaunchWindowTests {
  @Test func `a launch from the Finder or the Dock opens one`() {
    #expect(LaunchWindow.opens(readerCameBack: false, launchIsDefault: true, launchedHidden: false))
  }

  @Test func `a reader window that came back is enough`() {
    #expect(
      !LaunchWindow.opens(readerCameBack: true, launchIsDefault: false, launchedHidden: false))
  }

  /// A script launches the app hidden, to ask it something, and a window made then is
  /// left behind.
  @Test func `a script's launch opens none`() {
    #expect(
      !LaunchWindow.opens(readerCameBack: false, launchIsDefault: false, launchedHidden: true))
  }

  /// AppKit calls a launch that restores the last session's state not the default one,
  /// even when that state holds no reader window: the settings alone, or nothing.
  @Test func `a launch that restored no reader window opens one`() {
    #expect(
      LaunchWindow.opens(readerCameBack: false, launchIsDefault: false, launchedHidden: false))
  }
}
