import Foundation
import Testing

@testable import RFCReaderKit

/// What the library list shows while there is no index to list (#770).
@Suite("Index placeholder")
struct IndexPlaceholderTests {
  @Test func `a download with no index shows its progress`() {
    #expect(
      IndexPlaceholder(state: .loading, hasIndex: false, bytesReceived: 4_000_000)
        == .downloading(bytesReceived: 4_000_000))
  }

  /// Reading the index kept, or the one bundled, is not a download: the list's status
  /// line says it is loading.
  @Test func `loading without a download shows nothing`() {
    #expect(IndexPlaceholder(state: .loading, hasIndex: false, bytesReceived: nil) == nil)
    #expect(IndexPlaceholder(state: .idle, hasIndex: false, bytesReceived: nil) == nil)
  }

  @Test func `a failure with no index says why`() {
    #expect(
      IndexPlaceholder(
        state: .failed(.offline, message: "The Internet connection appears to be offline."),
        hasIndex: false, bytesReceived: nil)
        == .failed(.offline, message: "The Internet connection appears to be offline."))
  }

  /// Retry downloads under the failure it is retrying.
  @Test func `a retry's download replaces the failure`() {
    #expect(
      IndexPlaceholder(
        state: .failed(.offline, message: "Offline"), hasIndex: false, bytesReceived: 0)
        == .downloading(bytesReceived: 0))
  }

  /// A refresh, or its failure, under an index already listed is the status line's.
  @Test func `with an index there is nothing to show`() {
    #expect(IndexPlaceholder(state: .loading, hasIndex: true, bytesReceived: 10) == nil)
    #expect(
      IndexPlaceholder(state: .failed(.server, message: "503"), hasIndex: true, bytesReceived: nil)
        == nil)
    #expect(
      IndexPlaceholder(state: .ready(updatedAt: .now), hasIndex: false, bytesReceived: nil) == nil)
  }

  /// The main actor hears of the download every 100 KB, not every packet.
  @Test func `only each further 100 KB is a step`() {
    var steps = IndexPlaceholder.ProgressSteps()
    let received: [Int64] = [99_999, 100_000, 150_000, 230_000, 329_999, 330_000]
    let shown = received.filter { steps.isStep($0) }
    #expect(shown == [100_000, 230_000, 330_000])
  }
}
