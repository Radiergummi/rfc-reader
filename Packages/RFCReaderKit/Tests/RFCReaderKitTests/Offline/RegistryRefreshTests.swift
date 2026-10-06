import RFCKit
import Testing

@testable import RFCReaderKit

/// Which registries a launch or an opened palette fetches, and on which networks
/// (#175, #314).
@Suite("Registry refresh")
struct RegistryRefreshTests {
  private func plan(stale: [IANARegistry], cached: Set<IANARegistry>) -> [String] {
    RegistryRefresh.fetches(stale: stale, cached: cached).map {
      "\($0.registry.rawValue) \($0.onExpensiveNetworks ? "any" : "cheap")"
    }
  }

  /// With nothing kept, the palette has nothing to find until it is fetched.
  @Test func `a registry never fetched takes any network`() {
    #expect(plan(stale: [.tlsAlerts], cached: []) == ["tlsAlerts any"])
  }

  /// A kept registry still answers lookups: its refresh can wait for a cheap
  /// network, like the daily index check.
  @Test func `a kept registry waits for a cheap network`() {
    #expect(plan(stale: [.tlsAlerts], cached: [.tlsAlerts]) == ["tlsAlerts cheap"])
  }

  /// A refresh waiting for a cheap network would hold back a first fetch behind it.
  @Test func `first fetches come before refreshes`() {
    #expect(
      plan(stale: [.httpStatusCodes, .tlsAlerts, .mediaTypes], cached: [.httpStatusCodes])
        == ["tlsAlerts any", "mediaTypes any", "httpStatusCodes cheap"])
  }

  @Test func `nothing stale fetches nothing`() {
    #expect(plan(stale: [], cached: [.tlsAlerts]).isEmpty)
  }
}
