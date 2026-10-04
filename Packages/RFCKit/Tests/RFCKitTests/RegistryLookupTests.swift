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

  /// A code has no sign, in either base: `0x+3` is not `0x03`.
  @Test func `a signed number matches nothing`() {
    #expect(lookup("0x+3") == [])
    #expect(lookup("0x-3") == [])
    #expect(lookup("+425") == [])
  }

  /// QUIC's codes are written in hexadecimal: `quic 10` is not `0x0a`.
  @Test func `a decimal number does not match a hexadecimal code`() {
    #expect(lookup("quic 3") == [])
    #expect(lookup("3") == [])
  }

  @Test func `a code inside an assigned range matches the range`() {
    let crypto = RegistryEntry(
      registry: .quicTransportErrors, value: "0x0100-0x01ff", name: "CRYPTO_ERROR",
      references: [RFCLink(id: .rfc(9000), section: "20")])
    #expect(RegistryLookup.matches("quic 0x0128", in: [crypto]) == [crypto])
    #expect(RegistryLookup.matches("crypto_error", in: [crypto]) == [crypto])
    #expect(RegistryLookup.matches("0x0200", in: [crypto]) == [])
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

  // MARK: - Identifiers

  /// What an App Intent's registry entry is identified by (#192): the registry and
  /// the value, which together name one entry.
  @Test func `an entry is identified by its registry and value`() throws {
    let tls = try #require(Self.entries.first { $0.registry == .tlsAlerts })
    #expect(tls.identifier == "tlsAlerts:70")
    let found = RegistryLookup.entries(
      identifiedBy: ["tlsAlerts:70", "httpStatusCodes:999", "mediaTypes:application/dns-message"],
      in: Self.entries)
    #expect(found.map(\.identifier) == ["tlsAlerts:70", "mediaTypes:application/dns-message"])
  }

  @Test func `an identifier of no registry names nothing`() {
    #expect(RegistryLookup.entries(identifiedBy: ["dns:70", "70", ""], in: Self.entries).isEmpty)
  }
}
