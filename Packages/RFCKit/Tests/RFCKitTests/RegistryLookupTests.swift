import Testing

@testable import RFCKit

/// What was typed, matched against registry entries (#175): exact values and names,
/// in every registry that has them, or in the one a qualifier names.
@Suite("Registry lookup")
struct RegistryLookupTests {
  private static let entries = [
    RegistryEntry(
      registry: .httpStatusCodes, value: "425", name: "Too Early",
      references: [RFCLink(id: .rfc(8470), section: "5.2")]),
    RegistryEntry(
      registry: .httpStatusCodes, value: "70", name: "Seventy", references: []),
    RegistryEntry(
      registry: .httpFieldNames, value: "Retry-After", name: nil,
      references: [RFCLink(id: .rfc(9110), section: "10.2.3")]),
    RegistryEntry(
      registry: .tlsAlerts, value: "70", name: "protocol_version",
      references: [RFCLink(id: .rfc(8446), section: "6.2")]),
    RegistryEntry(
      registry: .quicTransportErrors, value: "0x03", name: "FLOW_CONTROL_ERROR",
      references: [RFCLink(id: .rfc(9000), section: "20")]),
    RegistryEntry(
      registry: .mediaTypes, value: "application/dns-message", name: nil,
      references: [RFCLink(id: .rfc(8484))]),
  ]

  private func lookup(_ query: String) -> [String] {
    RegistryLookup.matches(query, in: Self.entries).map { "\($0.registry.rawValue) \($0.value)" }
  }

  @Test func `a bare value matches every registry that has it`() {
    #expect(lookup("70") == ["httpStatusCodes 70", "tlsAlerts 70"])
    #expect(lookup("425") == ["httpStatusCodes 425"])
  }

  @Test func `a qualifier narrows to its registry`() {
    #expect(lookup("tls alert 70") == ["tlsAlerts 70"])
    #expect(lookup("alert 70") == ["tlsAlerts 70"])
    #expect(lookup("http 425") == ["httpStatusCodes 425"])
    #expect(lookup("status 70") == ["httpStatusCodes 70"])
    #expect(lookup("quic 0x3") == ["quicTransportErrors 0x03"])
  }

  /// `http` qualifies both HTTP registries: a status or a field.
  @Test func `http names a status or a field`() {
    #expect(lookup("http retry-after") == ["httpFieldNames Retry-After"])
    #expect(lookup("header Retry-After") == ["httpFieldNames Retry-After"])
  }

  @Test func `a name matches regardless of case`() {
    #expect(lookup("retry-after") == ["httpFieldNames Retry-After"])
    #expect(lookup("too early") == ["httpStatusCodes 425"])
    #expect(lookup("flow_control_error") == ["quicTransportErrors 0x03"])
    #expect(lookup("Application/DNS-Message") == ["mediaTypes application/dns-message"])
  }

  /// A code point is a number, however many digits it is written with.
  @Test func `a hexadecimal value matches however it is padded`() {
    #expect(lookup("0x3") == ["quicTransportErrors 0x03"])
    #expect(lookup("0x0003") == ["quicTransportErrors 0x03"])
  }

  @Test func `only exact matches count`() {
    #expect(lookup("42") == [])
    #expect(lookup("retry") == [])
    #expect(lookup("application/dns") == [])
  }

  @Test func `a qualifier alone, or nothing, matches nothing`() {
    #expect(lookup("tls alert") == [])
    #expect(lookup("  ") == [])
  }
}
