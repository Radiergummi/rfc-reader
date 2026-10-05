import AppIntents
import RFCKit
import RFCReaderKit

/// A section of an RFC (#192), identified across documents as `rfc9110#section-4.2`
/// (`SectionIdentifier`): what Open Section opens and Find Requirements narrows to.
struct SectionEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Section", numericFormat: "\(placeholder: .int) sections")
  }

  static var defaultQuery: SectionEntityQuery { SectionEntityQuery() }

  let id: String
  let document: DocumentID
  let anchor: String
  /// Where the reader goes for it.
  let link: RFCLink

  /// `4.2`, `A.1`; nil for an unnumbered section such as the acknowledgements.
  @Property(title: "Number")
  var number: String?

  @Property(title: "Title")
  var title: String

  /// `RFC 9110`.
  @Property(title: "Document")
  var documentName: String

  init(_ section: RFCKit.Section, in document: DocumentID) {
    id = SectionIdentifier(document: document, anchor: section.anchor).description
    self.document = document
    anchor = section.anchor
    link = RFCLink(section, in: document)
    number = section.number
    title = section.displayTitle
    documentName = document.displayName
  }

  var displayRepresentation: DisplayRepresentation {
    // Data, not language: no key for the catalog.
    DisplayRepresentation(
      title: .verbatim(title), subtitle: .verbatim(documentName))
  }
}

/// A document's sections, which means loading the document as opening it would
/// (`IntentDocuments`). By identifier, sections of any document; by what was typed or
/// said, and as suggestions, sections of the RFC the intent asking was given.
struct SectionEntityQuery: EntityStringQuery {
  @IntentParameterDependency<OpenSectionIntent>(\.$document)
  var openSection

  @IntentParameterDependency<RequirementsIntent>(\.$document)
  var requirements

  /// The RFC the intent asking for sections was given, if it has been given one.
  private var document: DocumentID? {
    openSection?.document.documentID ?? requirements?.document.documentID
  }

  func entities(for identifiers: [SectionEntity.ID]) async throws -> [SectionEntity] {
    var found: [SectionEntity] = []
    for identifier in identifiers.compactMap(SectionIdentifier.init) {
      let document = try await IntentDocuments.load(identifier.document)
      guard let section = document.section(anchor: identifier.anchor) else { continue }
      found.append(SectionEntity(section, in: identifier.document))
    }
    return found
  }

  func entities(matching string: String) async throws -> [SectionEntity] {
    guard let id = document else { return [] }
    let loaded = try await IntentDocuments.load(id)
    return SectionLookup.sections(matching: string, in: loaded).map { SectionEntity($0, in: id) }
  }

  /// Every section, as the table of contents lists them.
  func suggestedEntities() async throws -> [SectionEntity] {
    try await entities(matching: "")
  }
}
