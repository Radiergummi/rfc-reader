import Testing

@testable import RFCReaderKit

/// The browser's conventions, because that is what a reader's hands already know.
@Suite("Link activation")
struct LinkActivationTests {
  @Test func `a plain click follows the link here`() {
    #expect(LinkActivation(command: false, shift: false) == .here)
  }

  @Test func `command opens a background tab and leaves you where you are`() {
    #expect(LinkActivation(command: true, shift: false) == .newTab(inBackground: true))
  }

  /// The pairing that is easy to get backwards: Shift means "and take me there", so
  /// Command-Shift must bring the tab forward rather than leave it behind.
  @Test func `command shift opens the tab in the foreground`() {
    #expect(LinkActivation(command: true, shift: true) == .newTab(inBackground: false))
  }

  @Test func `shift alone opens the tab in the foreground`() {
    #expect(LinkActivation(command: false, shift: true) == .newTab(inBackground: false))
  }
}
