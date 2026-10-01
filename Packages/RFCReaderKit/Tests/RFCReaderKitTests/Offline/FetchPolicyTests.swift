import Foundation
import Testing

@testable import RFCReaderKit

/// Whether a fetch goes ahead on the path the device has, by why it was asked for
/// (#358): one somebody waits for always does, a discretionary one only on a path that
/// costs nothing and outside Low Power Mode.
@Suite("Fetch policy")
struct FetchPolicyTests {
  private static let wifi = FetchPolicy.Path(status: .satisfied)
  private static let cellular = FetchPolicy.Path(status: .satisfied, isExpensive: true)
  private static let lowData = FetchPolicy.Path(status: .satisfied, isConstrained: true)
  private static let offline = FetchPolicy.Path(status: .unsatisfied)
  private static let cellularDenied = FetchPolicy.Path(status: .cellularDenied)

  private static let paths = [wifi, cellular, lowData, offline, cellularDenied]

  /// Opening a document, Retry, a Keep Offline tap on this device and Download Now:
  /// somebody is waiting, so they fetch on any path, in Low Power Mode too. One that
  /// cannot succeed fails in front of them, as an open does today.
  @Test(arguments: FetchPolicy.Cause.allCases.filter(\.isAwaited))
  func `a fetch somebody waits for goes ahead on any path`(cause: FetchPolicy.Cause) {
    for path in Self.paths {
      for lowPower in [false, true] {
        #expect(FetchPolicy.decide(cause: cause, path: path, lowPower: lowPower) == .fetch)
      }
    }
  }

  @Test func `the causes nobody waits for are a synced mark and the bookmark setting`() {
    #expect(
      Set(FetchPolicy.Cause.allCases.filter { !$0.isAwaited }) == [.syncedMark, .bookmarkSetting])
  }

  @Test(arguments: FetchPolicy.Cause.allCases.filter { !$0.isAwaited })
  func `a discretionary fetch goes ahead only on a free path outside Low Power Mode`(
    cause: FetchPolicy.Cause
  ) {
    func decide(_ path: FetchPolicy.Path, lowPower: Bool = false) -> FetchPolicy.Decision {
      FetchPolicy.decide(cause: cause, path: path, lowPower: lowPower)
    }
    #expect(decide(Self.wifi) == .fetch)
    #expect(decide(Self.cellular) == .deferred(.waitingForWiFi))
    #expect(decide(Self.lowData) == .deferred(.lowDataMode))
    #expect(decide(Self.offline) == .deferred(.offline))
    #expect(decide(Self.cellularDenied) == .deferred(.cellularDenied))
    #expect(decide(Self.wifi, lowPower: true) == .deferred(.lowPowerMode))
  }

  /// One reason, the first that holds: whether there is a network at all, then what
  /// the path costs, then the device's power. Low Data Mode is a setting the reader
  /// chose, so it is named before the expense it usually comes with.
  @Test func `a deferral names the first reason that holds`() {
    func decide(_ path: FetchPolicy.Path, lowPower: Bool) -> FetchPolicy.Decision {
      FetchPolicy.decide(cause: .syncedMark, path: path, lowPower: lowPower)
    }
    let expensiveAndConstrained = FetchPolicy.Path(
      status: .satisfied, isExpensive: true, isConstrained: true)
    #expect(decide(expensiveAndConstrained, lowPower: true) == .deferred(.lowDataMode))
    #expect(decide(Self.cellular, lowPower: true) == .deferred(.waitingForWiFi))
    let offlineButExpensive = FetchPolicy.Path(status: .unsatisfied, isExpensive: true)
    #expect(decide(offlineButExpensive, lowPower: true) == .deferred(.offline))
  }
}
