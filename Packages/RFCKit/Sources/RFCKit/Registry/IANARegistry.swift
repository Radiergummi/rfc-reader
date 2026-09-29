import Foundation

/// An IANA registry the app looks values up in (#175): the protocol identifiers
/// engineers know by value rather than by document, such as HTTP 425 or TLS alert 70.
///
/// IANA publishes each registry as XML, and each record names the RFC that defines
/// it, usually with the section. Registries change more often than RFCs, so they are
/// fetched on the device rather than shipped with the corpus.
public enum IANARegistry: String, CaseIterable, Sendable, Hashable {
  case httpStatusCodes
  case httpFieldNames
  case tlsAlerts
  case quicTransportErrors
  case mediaTypes

  public enum ParseError: Error, LocalizedError, Sendable, Equatable {
    case malformed(XMLSyntaxError)
    /// Well-formed XML without the registry, or with no record in it: an XHTML
    /// error page, or a registry IANA has renamed. Kept as a registry, it would
    /// answer every lookup with nothing until it was next fetched.
    case missing(String)

    /// The syntax error's own words, or which registry has no records (#320).
    public var errorDescription: String? {
      switch self {
      case .malformed(let error): error.errorDescription
      case .missing(let registry): "IANA's \(registry) holds no registry records."
      }
    }
  }

  /// The file IANA publishes the registry in. One file can hold several registries:
  /// TLS alerts are one of `tls-parameters`' many.
  public var file: String {
    switch self {
    case .httpStatusCodes: "http-status-codes"
    case .httpFieldNames: "http-fields"
    case .tlsAlerts: "tls-parameters"
    case .quicTransportErrors: "quic"
    case .mediaTypes: "media-types"
    }
  }

  public var url: URL {
    URL(string: "https://www.iana.org/assignments/\(file)/\(file).xml")!
  }

  /// What a match is called where it is listed: "HTTP status 425".
  public var displayName: String {
    switch self {
    case .httpStatusCodes: "HTTP status"
    case .httpFieldNames: "HTTP field"
    case .tlsAlerts: "TLS alert"
    case .quicTransportErrors: "QUIC error"
    case .mediaTypes: "Media type"
    }
  }

  /// The `id` of the registry within its file, or nil for media types, where every
  /// registry in the file is a top-level type.
  private var registryID: String? {
    switch self {
    case .httpStatusCodes: "http-status-codes-1"
    case .httpFieldNames: "field-names"
    case .tlsAlerts: "tls-parameters-6"
    case .quicTransportErrors: "quic-transport-error-codes"
    case .mediaTypes: nil
    }
  }

  /// Every assigned value in `registry`, read from its file. What is unassigned or
  /// reserved is left out; an assigned range, such as QUIC's `CRYPTO_ERROR`, is one
  /// entry; a value defined outside the RFCs is kept, with no reference.
  public static func parse(_ data: Data, as registry: IANARegistry) throws(ParseError)
    -> [RegistryEntry]
  {
    let root: XMLTree.Element
    do {
      root = try XMLTree.parse(data)
    } catch {
      throw .malformed(error)
    }
    guard let registryID = registry.registryID else {
      let types = root.all("registry").flatMap { type in
        mediaTypes(in: type, registry: registry)
      }
      guard !types.isEmpty else { throw .missing(registry.file) }
      return types
    }
    guard let found = subregistry(registryID, in: root) else { throw .missing(registryID) }
    let entries = found.all("record").compactMap { record -> RegistryEntry? in
      guard let value = record.first("value")?.normalizedText, isAssigned(record) else {
        return nil
      }
      // QUIC's records carry a code name beside a description, and the name is what
      // people write; the others' description is their name.
      let name = (record.first("name") ?? record.first("description"))?.normalizedText
      return RegistryEntry(
        registry: registry, value: value, name: name, references: references(in: record))
    }
    guard !entries.isEmpty else { throw .missing(registryID) }
    return entries
  }

  /// A top-level type's records, each named in full. IANA writes a type's standing
  /// after its name ("font-woff - DEPRECATED in favor of font/woff"), and a name has
  /// no spaces, so the name is what comes before the first.
  private static func mediaTypes(in type: XMLTree.Element, registry: IANARegistry)
    -> [RegistryEntry]
  {
    let typeName = type.first("title")?.normalizedText ?? type["id"] ?? ""
    return type.all("record").compactMap { record in
      guard let subtype = record.first("name")?.normalizedText.split(separator: " ").first
      else { return nil }
      return RegistryEntry(
        registry: registry, value: "\(typeName)/\(subtype)", name: nil,
        references: references(in: record))
    }
  }

  /// The registry `id` names, however deep in the file it is.
  private static func subregistry(_ id: String, in element: XMLTree.Element) -> XMLTree.Element? {
    for child in element.all("registry") {
      if child["id"] == id { return child }
      if let found = subregistry(id, in: child) { return found }
    }
    return nil
  }

  /// Neither unassigned nor reserved: those are what a registry says of the codes
  /// no one may use, not codes someone looks up.
  private static func isAssigned(_ record: XMLTree.Element) -> Bool {
    let description = record.first("description")?.normalizedText ?? ""
    return description != "Unassigned" && !description.hasPrefix("Reserved")
  }

  /// The RFCs a record cites, each at the section it names: an attribute where the
  /// file has one, otherwise the first number after "Section" or "Appendix" in the
  /// reference's text ("RFC8470, Sections 5.2 and 5.3" opens at 5.2).
  private static func references(in record: XMLTree.Element) -> [RFCLink] {
    record.all("xref").compactMap { xref in
      guard xref["type"] == "rfc", let data = xref["data"],
        let id = DocumentID(fileStem: data.lowercased())
      else { return nil }
      let section =
        xref["section"]
        ?? xref.normalizedText.firstMatch(of: /(?:Sections?|Appendix) +([A-Z0-9][A-Za-z0-9.]*)/)
        .map { String($0.1).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
      return RFCLink(id: id, section: section)
    }
  }
}

/// One assigned value in a registry: what it is, what it is called, and the RFC
/// sections defining it.
public struct RegistryEntry: Sendable, Hashable {
  public var registry: IANARegistry
  /// What identifies the entry: `425`, `0x03`, `Retry-After`,
  /// `application/dns-message`.
  public var value: String
  /// What the registry calls it, where that is not the value itself: `Too Early`,
  /// `FLOW_CONTROL_ERROR`.
  public var name: String?
  public var references: [RFCLink]

  public init(registry: IANARegistry, value: String, name: String?, references: [RFCLink]) {
    self.registry = registry
    self.value = value
    self.name = name
    self.references = references
  }

  /// The reference to open: the last one not obsoleted, or the last one if every one
  /// is. IANA lists a record's references oldest first, so the first is often the
  /// RFC that a later one replaced: `HTTP2-Settings` cites RFC 7540, then RFC 9113.
  public func reference(isObsolete: (DocumentID) -> Bool) -> RFCLink? {
    references.last { !isObsolete($0.id) } ?? references.last
  }
}
