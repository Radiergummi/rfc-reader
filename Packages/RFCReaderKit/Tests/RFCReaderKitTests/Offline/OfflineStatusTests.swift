import Foundation
import RFCKit
import RFCReaderKit
import Testing

/// What a row in Available Offline says while its body is not on the device yet
/// (#358).
@Suite("Offline status")
struct OfflineStatusTests {
  @Test func `a kept body says nothing, whatever else is recorded of it`() {
    let id = DocumentID.rfc(1)
    let status = OfflineStatus(
      kept: [id], downloading: [id], failed: [id], waiting: [id], deferral: .offline)
    #expect(status.state(of: id) == nil)
  }

  @Test func `a running download wins over a failure and a wait it has ended`() {
    let id = DocumentID.rfc(1)
    let status = OfflineStatus(
      downloading: [id], failed: [id], waiting: [id], deferral: .waitingForWiFi)
    #expect(status.state(of: id) == .downloading)
  }

  @Test func `a failure wins over a wait`() {
    let id = DocumentID.rfc(1)
    let status = OfflineStatus(failed: [id], waiting: [id], deferral: .lowDataMode)
    #expect(status.state(of: id) == .failed)
  }

  @Test func `a waiting document says what it waits for`() {
    let status = OfflineStatus(waiting: [.rfc(1)], deferral: .lowPowerMode)
    #expect(status.state(of: .rfc(1)) == .waiting(.lowPowerMode))
    #expect(status.state(of: .rfc(2)) == nil)
  }

  @Test func `each state's words and button`() {
    let english = Locale.english
    #expect(OfflineRowState.downloading.description(locale: english) == "Downloading…")
    #expect(OfflineRowState.downloading.action(locale: english) == nil)
    #expect(OfflineRowState.failed.description(locale: english) == "Couldn't download")
    #expect(OfflineRowState.failed.action(locale: english) == "Retry")
    #expect(
      OfflineRowState.waiting(.waitingForWiFi).description(locale: english)
        == "Waiting for Wi-Fi")
    #expect(OfflineRowState.waiting(.offline).action(locale: english) == "Download Now")
  }
}
