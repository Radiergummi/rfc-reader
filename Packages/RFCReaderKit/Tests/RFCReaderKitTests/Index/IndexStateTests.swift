import Foundation
import Testing

@testable import RFCReaderKit

/// Where the index stands, and whether a background refresh checks it (#191, #314).
@Suite("Index state")
struct IndexStateTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func `an index checked within the day is not checked in the background`() {
    let state = IndexState.ready(updatedAt: now - IndexCheck.interval + 60)
    #expect(!state.isCheckDue(now: now))
  }

  @Test func `an index checked over a day ago is checked in the background`() {
    let state = IndexState.ready(updatedAt: now - IndexCheck.interval - 60)
    #expect(state.isCheckDue(now: now))
  }

  @Test func `an index that failed is checked in the background`() {
    let state = IndexState.failed(.offline, message: "offline")
    #expect(state.isCheckDue(now: now))
  }

  @Test func `an index not yet loaded is not checked in the background`() {
    #expect(!IndexState.idle.isCheckDue(now: now))
    #expect(!IndexState.loading.isCheckDue(now: now))
  }

  @Test func `only a loaded index is ready`() {
    #expect(IndexState.ready(updatedAt: now).isReady)
    #expect(!IndexState.loading.isReady)
    #expect(!IndexState.failed(.offline, message: "offline").isReady)
  }

  @Test func `only a failure has failed`() {
    #expect(IndexState.failed(.offline, message: "offline").isFailed)
    #expect(!IndexState.loading.isFailed)
    #expect(!IndexState.ready(updatedAt: now).isFailed)
  }
}
