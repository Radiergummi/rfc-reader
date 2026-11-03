import Testing

@testable import RFCReaderKit

/// When the Mac app opens a reader window of its own after launching (#762, #939).
@Suite("Launch window")
struct LaunchWindowTests {
  @Test func `a default launch opens one at once`() {
    var window = LaunchWindow(launchIsDefault: true, readerCameBack: false)
    #expect(window.opensAtLaunch)
    let opens = window.becameActive(hasReaderWindow: true)
    #expect(!opens)
  }

  @Test func `a reader window that came back is enough`() {
    for launchIsDefault in [true, false] {
      var window = LaunchWindow(launchIsDefault: launchIsDefault, readerCameBack: true)
      #expect(!window.opensAtLaunch)
      let opens = window.becameActive(hasReaderWindow: true)
      #expect(!opens)
    }
  }

  /// AppKit calls a launch that restores the last session's state not the default
  /// one, even when that state holds no reader window. The Dock activates the app; a
  /// script, a Service or a background intent doesn't, and gets no window.
  @Test func `a Dock launch that restored no reader window opens one on activation`() {
    var window = LaunchWindow(launchIsDefault: false, readerCameBack: false)
    #expect(!window.opensAtLaunch)
    let opens = window.becameActive(hasReaderWindow: false)
    #expect(opens)
  }

  /// Switching to an app a script launched opens the window then, once.
  @Test func `only the first activation opens one`() {
    var window = LaunchWindow(launchIsDefault: false, readerCameBack: false)
    let first = window.becameActive(hasReaderWindow: false)
    #expect(first)
    let second = window.becameActive(hasReaderWindow: false)
    #expect(!second)
  }

  /// A link that launched the app made a window for itself first.
  @Test func `a window made since launch is enough`() {
    var window = LaunchWindow(launchIsDefault: false, readerCameBack: false)
    let first = window.becameActive(hasReaderWindow: true)
    #expect(!first)
    let second = window.becameActive(hasReaderWindow: false)
    #expect(!second)
  }
}
