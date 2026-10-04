import AppIntents
import RFCKit

/// A protocol identifier in an IANA registry (#175, #192), such as HTTP status 425
/// or TLS alert 70, with the RFC section that defines it.
struct RegistryEntryEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Identifier", numericFormat: "\(placeholder: .int) identifiers")
  }

  static var defaultQuery: RegistryEntryQuery { RegistryEntryQuery() }

  /// `RegistryEntry.identifier`, `tlsAlerts:70`.
  let id: String
  /// The section that defines it: the current RFC's, where a later one replaced the
  /// first (`RegistryEntry.reference(isObsolete:)`).
  let reference: RFCLink?

  /// `TLS alert`.
  @Property(title: "Registry")
  var registry: String

  /// `70`.
  @Property(title: "Value")
  var value: String

  /// `protocol_version`; nil where the value is its own name, as a field's is.
  @Property(title: "Name")
  var name: String?

  /// `RFC 8446, Section 6.2`.
  @Property(title: "Defined In")
  var definedIn: String?

  init(_ entry: RegistryEntry, isObsolete: (DocumentID) -> Bool) {
    let reference = entry.reference(isObsolete: isObsolete)
    id = entry.identifier
    self.reference = reference
    registry = entry.registry.displayName
    value = entry.value
    name = entry.name
    definedIn = reference.map { CitationFormatter.shortCitation($0.id, section: $0.section) }
  }

  /// `TLS alert 70`.
  var heading: String { "\(registry) \(value)" }

  var displayRepresentation: DisplayRepresentation {
    let subtitle = [name, definedIn].compactMap { $0 }.joined(separator: " · ")
    return DisplayRepresentation(title: "\(heading)", subtitle: "\(subtitle)")
  }
}

/// Finds identifiers as the Go to RFC palette does (`RegistryLookup`): `425`,
/// `tls alert 70`, `Retry-After`.
struct RegistryEntryQuery: EntityStringQuery {
  func entities(for identifiers: [RegistryEntryEntity.ID]) async throws -> [RegistryEntryEntity] {
    let entries = await LibraryModel.shared.loadedRegistryEntries()
    return await entities(RegistryLookup.entries(identifiedBy: identifiers, in: entries))
  }

  func entities(matching string: String) async throws -> [RegistryEntryEntity] {
    let entries = await LibraryModel.shared.loadedRegistryEntries()
    return await entities(RegistryLookup.matches(string, in: entries))
  }

  /// With what the index says is obsoleted, so each opens the current RFC.
  private func entities(_ entries: [RegistryEntry]) async -> [RegistryEntryEntity] {
    let index = await LibraryModel.shared.settledSearch()?.index
    return entries.map { entry in
      RegistryEntryEntity(entry) { index?[$0]?.isObsolete ?? false }
    }
  }
}
