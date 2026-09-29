import Foundation
import Testing

@testable import RFCKit

/// IANA's registries, read into entries that name the RFC and section defining them
/// (#175). The files here are hand-written in the shape IANA publishes, not copied
/// from it.
@Suite("IANA registries")
struct IANARegistryTests {
  private func parse(_ xml: String, as registry: IANARegistry) throws -> [RegistryEntry] {
    try IANARegistry.parse(Data(xml.utf8), as: registry)
  }

  private static let statusCodes = """
    <?xml version='1.0' encoding='UTF-8'?>
    <registry xmlns="http://www.iana.org/assignments" id="http-status-codes">
      <title>Status Codes</title>
      <registry id="http-status-codes-1">
        <title>HTTP Status Codes</title>
        <xref type="rfc" data="rfc9110">RFC9110, Section 16.2.1</xref>
        <record>
          <value>100</value>
          <description>Continue</description>
          <xref type="rfc" data="rfc9110">RFC9110, Section 15.2.1</xref>
        </record>
        <record>
          <value>102</value>
          <description>Processing</description>
          <xref type="rfc" data="rfc2518"/>
        </record>
        <record>
          <value>104</value>
          <description>Something Provisional</description>
          <xref type="draft" data="draft-ietf-example-00"/>
        </record>
        <record>
          <value>105-199</value>
          <description>Unassigned</description>
        </record>
        <record>
          <value>425</value>
          <description>Too Early</description>
          <xref type="rfc" data="rfc8470">RFC8470, Sections 5.2 and 5.3</xref>
        </record>
      </registry>
    </registry>
    """

  @Test func `a record names its value, its name and the section defining it`() throws {
    let entries = try parse(Self.statusCodes, as: .httpStatusCodes)
    #expect(
      entries.first
        == RegistryEntry(
          registry: .httpStatusCodes, value: "100", name: "Continue",
          references: [RFCLink(id: .rfc(9110), section: "15.2.1")]))
  }

  @Test func `a reference without a section names the document alone`() throws {
    let entries = try parse(Self.statusCodes, as: .httpStatusCodes)
    #expect(entries.first { $0.value == "102" }?.references == [RFCLink(id: .rfc(2518))])
  }

  /// A record defined outside the RFCs is still a registered value: it is found,
  /// and opens nothing.
  @Test func `a record that cites no RFC is kept with no reference`() throws {
    let entries = try parse(Self.statusCodes, as: .httpStatusCodes)
    #expect(entries.first { $0.value == "104" }?.references == [])
  }

  @Test func `an unassigned range is not an entry`() throws {
    let entries = try parse(Self.statusCodes, as: .httpStatusCodes)
    #expect(entries.map(\.value) == ["100", "102", "104", "425"])
  }

  /// "Sections 5.2 and 5.3" opens at the first.
  @Test func `a reference to several sections opens at the first`() throws {
    let entries = try parse(Self.statusCodes, as: .httpStatusCodes)
    #expect(
      entries.first { $0.value == "425" }?.references == [RFCLink(id: .rfc(8470), section: "5.2")])
  }

  @Test func `a section can be an attribute, and a value its own name`() throws {
    let xml = """
      <registry xmlns="http://www.iana.org/assignments" id="http-fields">
        <registry id="field-names">
          <record>
            <value>Retry-After</value>
            <status>permanent</status>
            <xref type="rfc" data="rfc9110" section="10.2.3">RFC 9110, Section 10.2.3: HTTP Semantics</xref>
          </record>
          <record>
            <value>A-IM</value>
            <xref type="rfc" data="rfc3229">RFC 3229: Delta encoding in HTTP</xref>
          </record>
        </registry>
      </registry>
      """
    let entries = try parse(xml, as: .httpFieldNames)
    #expect(
      entries == [
        RegistryEntry(
          registry: .httpFieldNames, value: "Retry-After", name: nil,
          references: [RFCLink(id: .rfc(9110), section: "10.2.3")]),
        RegistryEntry(
          registry: .httpFieldNames, value: "A-IM", name: nil,
          references: [RFCLink(id: .rfc(3229))]),
      ])
  }

  /// A file holds many registries; only the one asked for is read.
  @Test func `only the sub-registry asked for is read`() throws {
    let xml = """
      <registry xmlns="http://www.iana.org/assignments" id="tls-parameters">
        <registry id="tls-parameters-5">
          <title>TLS ContentType</title>
          <record><value>21</value><description>alert</description></record>
        </registry>
        <registry id="tls-parameters-6">
          <title>TLS Alerts</title>
          <record>
            <value>70</value>
            <description>protocol_version</description>
            <xref type="rfc" data="rfc8446">RFC8446, Section 6.2</xref>
            <xref type="rfc-errata" data="1234"/>
          </record>
        </registry>
      </registry>
      """
    #expect(
      try parse(xml, as: .tlsAlerts) == [
        RegistryEntry(
          registry: .tlsAlerts, value: "70", name: "protocol_version",
          references: [RFCLink(id: .rfc(8446), section: "6.2")])
      ])
  }

  /// QUIC's records carry a name beside the description; the name is what people
  /// write.
  @Test func `a QUIC error is named by its code name`() throws {
    let xml = """
      <registry xmlns="http://www.iana.org/assignments" id="quic">
        <registry id="quic-transport-error-codes">
          <record>
            <value>0x03</value>
            <name>FLOW_CONTROL_ERROR</name>
            <description>Flow control error</description>
            <xref type="rfc" data="rfc9000" section="20"/>
          </record>
        </registry>
      </registry>
      """
    #expect(
      try parse(xml, as: .quicTransportErrors) == [
        RegistryEntry(
          registry: .quicTransportErrors, value: "0x03", name: "FLOW_CONTROL_ERROR",
          references: [RFCLink(id: .rfc(9000), section: "20")])
      ])
  }

  /// Every top-level type is a sub-registry of its own, and a record names only the
  /// subtype.
  @Test func `a media type is named in full, from every top-level type`() throws {
    let xml = """
      <registry xmlns="http://www.iana.org/assignments" id="media-types">
        <registry id="application">
          <title>application</title>
          <record>
            <name>dns-message</name>
            <xref type="rfc" data="rfc8484"/>
            <file type="template">application/dns-message</file>
          </record>
        </registry>
        <registry id="text">
          <title>text</title>
          <record>
            <name>markdown</name>
            <xref type="rfc" data="rfc7763"/>
          </record>
        </registry>
      </registry>
      """
    #expect(
      try parse(xml, as: .mediaTypes).map(\.value) == ["application/dns-message", "text/markdown"])
  }

  @Test func `malformed XML is an error, not an empty registry`() {
    #expect(throws: IANARegistry.ParseError.self) {
      try parse("<registry><record>", as: .httpStatusCodes)
    }
  }

  /// Answers the registry's own URL with `body`, and anything else with a 404.
  private struct RegistryTransport: HTTPTransport {
    let registry: IANARegistry
    let body: String
    let status: Int

    func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
      let found = url == registry.url
      let response = HTTPURLResponse(
        url: url, statusCode: found ? status : 404, httpVersion: nil, headerFields: nil)!
      return (found ? Data(body.utf8) : Data(), response)
    }
  }

  @Test func `the client fetches a registry from IANA and reads it`() async throws {
    let client = RFCEditorClient(
      transport: RegistryTransport(registry: .httpStatusCodes, body: Self.statusCodes, status: 200))
    let fetched = try await client.fetchRegistry(.httpStatusCodes)
    #expect(fetched.entries.map(\.value) == ["100", "102", "104", "425"])
    #expect(fetched.data == Data(Self.statusCodes.utf8))
  }

  /// An error page is not a registry, and must not be kept as one.
  @Test func `a failed fetch is an error`() async {
    let client = RFCEditorClient(
      transport: RegistryTransport(registry: .tlsAlerts, body: "<html>", status: 503))
    await #expect(throws: RFCEditorClient.ClientError.self) {
      try await client.fetchRegistry(.tlsAlerts)
    }
  }

  @Test func `each registry names the file IANA publishes it in`() {
    #expect(
      IANARegistry.httpStatusCodes.url.absoluteString
        == "https://www.iana.org/assignments/http-status-codes/http-status-codes.xml")
    #expect(IANARegistry.tlsAlerts.url.lastPathComponent == "tls-parameters.xml")
  }
}
