import RFCKit

/// What a code block's language label says (#820). A `<sourcecode type>` is a
/// keyword or a media type, and some of them read badly in the label's capitals,
/// `APPLICATION/JSONPATH` or `CBOR-DIAG`: those are shown by their language's name.
/// The names are the reader's, English like the rest of the body.
enum CodeLanguage {
  /// The types of the RFCXML corpus whose capitals do not read as a name, keyed by
  /// their `ArtworkType` name. A type whose capitals read well, `ABNF` or `YANG`,
  /// needs none, and neither does an author's typo.
  private static let names: [String: String] = [
    "abnf2616": "ABNF",
    "abnf9110": "ABNF",
    "application/jsonpath": "JSON Path",
    "application/pgp-encrypted": "OpenPGP Message",
    "application/pgp-keys": "OpenPGP Key",
    "application/pgp-signature": "OpenPGP Signature",
    "application/sslkeylogfile": "SSL Key Log",
    "asn1": "ASN.1",
    "cbor-diag": "CBOR Diagnostic Notation",
    "cbor-pretty": "Annotated CBOR",
    "core-link-format": "CoRE Link Format",
    "dns-rr": "DNS Records",
    "example-crypto-material": "Example Key Material",
    "http-message": "HTTP Message",
    "http-message-new": "HTTP Message",
    "message/http": "HTTP Message",
    "message/rfc822": "Internet Message",
    "nfsv4compound": "NFSv4 COMPOUND",
    "pkcs8": "PKCS #8",
    "pkcs12": "PKCS #12",
    "sdf+json": "SDF",
    "senml-json": "SenML JSON",
    "tcp-ao-test-vectors": "TCP-AO Test Vectors",
    "test-vector": "Test Vector",
    "test-vectors": "Test Vectors",
    "text/c": "C",
    "text/css": "CSS",
    "text/plain": "Text",
    "text/rfc822-headers": "Message Headers",
    "tls-presentation": "TLS Presentation Language",
    "x509": "X.509",
    "yang-instance-data+json": "YANG Instance Data",
    "yang-sid+json": "YANG SID",
    "yangtree": "YANG Tree",
  ]

  /// The name of the language `type` declares, read as the renderers read it, or
  /// `type` as given where it has none.
  static func name(of type: String) -> String {
    ArtworkType.canonical(type).flatMap { names[$0.name] } ?? type
  }
}
