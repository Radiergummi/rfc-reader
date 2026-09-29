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

  public enum ParseError: Error, Sendable, Equatable {
    case malformed(XMLSyntaxError)
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

  /// Every assigned value in `registry`, read from its file. Unassigned ranges are
  /// left out; a value defined outside the RFCs is kept, with no reference.
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
      // Media types: a record names the subtype, under its top-level type.
      return root.all("registry").flatMap { type in
        let typeName = type.first("title")?.normalizedText ?? type["id"] ?? ""
        return type.all("record").compactMap { record in
          record.first("name").map { name in
            RegistryEntry(
              registry: registry, value: "\(typeName)/\(name.normalizedText)", name: nil,
              references: references(in: record))
          }
        }
      }
    }
    guard let found = subregistry(registryID, in: root) else { return [] }
    return found.all("record").compactMap { record in
      guard let value = record.first("value")?.normalizedText, isAssigned(value, in: record)
      else { return nil }
      // QUIC's records carry a code name beside a description, and the name is what
      // people write; the others' description is their name.
      let name = (record.first("name") ?? record.first("description"))?.normalizedText
      return RegistryEntry(
        registry: registry, value: value, name: name, references: references(in: record))
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

  /// Not a range of codes (`105-199`, `0x40-0x7f`) and not marked unassigned. A
  /// range is numbers on both sides of the hyphen, so a field name such as `A-IM`
  /// is a value.
  private static func isAssigned(_ value: String, in record: XMLTree.Element) -> Bool {
    if record.first("description")?.normalizedText == "Unassigned" { return false }
    let isDecimalRange = value.wholeMatch(of: /[0-9]+ *- *[0-9]+/) != nil
    let isHexadecimalRange = value.wholeMatch(of: /0x[0-9A-Fa-f]+ *- *0x[0-9A-Fa-f]+/) != nil
    return !isDecimalRange && !isHexadecimalRange
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
}
