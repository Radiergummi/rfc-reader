import AppIntents
import CoreSpotlight
import RFCKit
import RFCReaderKit

/// An RFC as Shortcuts, Siri and Spotlight know it (#192): what an intent takes or
/// returns, and what a Spotlight result is, since `SpotlightIndexer` associates
/// each indexed item with one.
///
/// Nonisolated, because `SpotlightIndexer` makes one per RFC off the main actor. So
/// its fields are plain values rather than `@Property`, whose storage a nonisolated
/// type cannot hold: Shortcuts shows them, in the display representation, but does
/// not offer them as properties to read.
nonisolated struct RFCEntity: AppEntity, IndexedEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "RFC", numericFormat: "\(placeholder: .int) RFCs")
  }

  static var defaultQuery: RFCEntityQuery { RFCEntityQuery() }

  /// The file stem, `rfc9110`, as Spotlight indexes it.
  let id: String
  let documentID: DocumentID

  let number: Int
  let title: String
  let status: String
  /// `Obsoleted by RFC 9110`, for an RFC that is not current.
  let obsoletedBy: String?

  init(_ metadata: RFCMetadata) {
    id = metadata.id.fileStem
    documentID = metadata.id
    number = metadata.number
    title = metadata.title
    status = metadata.currentStatus.displayName
    obsoletedBy = metadata.obsoletionNote
  }

  var displayRepresentation: DisplayRepresentation {
    // Data, not language: no key for the catalog.
    DisplayRepresentation(
      title: .verbatim("\(documentID.displayName): \(title)"),
      subtitle: .verbatim(obsoletedBy ?? status))
  }
}

/// Finds RFCs in the index, so an intent answers offline: by identifier, by what was
/// typed or said (`DocumentLookup`), and the ones read recently as suggestions.
nonisolated struct RFCEntityQuery: EntityStringQuery {
  func entities(for identifiers: [RFCEntity.ID]) async throws -> [RFCEntity] {
    guard let search = await LibraryModel.shared.settledSearch() else { return [] }
    return DocumentLookup.rfcs(identifiedBy: identifiers, in: search.index).map(RFCEntity.init)
  }

  func entities(matching string: String) async throws -> [RFCEntity] {
    guard let search = await LibraryModel.shared.settledSearch() else { return [] }
    return DocumentLookup.rfcs(matching: string, in: search).map(RFCEntity.init)
  }

  /// As many of the RFCs read last as a list to choose from takes in.
  private static let suggestionCount = 20

  /// What was read last: also what a phrase can name (`RFCReaderShortcuts`).
  func suggestedEntities() async throws -> [RFCEntity] {
    guard let search = await LibraryModel.shared.settledSearch() else { return [] }
    let read = await LibraryModel.shared.recentlyRead()
    return Array(read.lazy.compactMap { search.index[$0] }.prefix(Self.suggestionCount))
      .map(RFCEntity.init)
  }
}
