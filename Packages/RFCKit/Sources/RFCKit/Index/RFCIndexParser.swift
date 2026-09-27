import Foundation

/// Streaming parser for `https://www.rfc-editor.org/rfc-index.xml` (about 14 MB, ~10k entries).
///
/// The index is parsed with a SAX-style state machine rather than a tree because it is
/// large and flat; an `XMLTree` of it would waste memory on the many tiny nodes. It runs
/// on `XMLDriver`, the tree's own driver, so the two share the rule about errors
/// reported after the root closes (#133).
public enum RFCIndexParser {
  public enum ParseError: Error, Sendable, Equatable {
    case malformed(XMLSyntaxError)
  }

  public static func parse(_ data: Data) throws(ParseError) -> RFCIndex {
    let reader = Reader()
    do {
      try XMLDriver.run(data, into: reader)
    } catch {
      throw .malformed(error)
    }
    return RFCIndex(rfcs: reader.rfcs, series: reader.series, notIssued: reader.notIssued)
  }

  /// Untyped, since reading the file can fail as well as parsing it.
  public static func parse(contentsOf url: URL) throws -> RFCIndex {
    try parse(Data(contentsOf: url))
  }
}

/// The index's state machine, fed by `XMLDriver`.
private final class Reader: XMLEvents {
  private(set) var rfcs: [RFCMetadata] = []
  private(set) var series: [SeriesEntry] = []
  private(set) var notIssued: [Int] = []

  private var path: [String] = []
  private var text = ""

  private var entry = EntryBuilder()
  private var entryKind: EntryKind?

  private enum EntryKind { case rfc, series, notIssued }

  private struct EntryBuilder {
    var docID: DocumentID?
    var title = ""
    var authors: [Author] = []
    var currentAuthorName = ""
    var currentAuthorRole: String?
    var month: Int?
    var day: Int?
    var year: Int?
    var formats: [FileFormat] = []
    var pageCount: Int?
    var keywords: [String] = []
    var abstractParagraphs: [String] = []
    var draft: String?
    var isAlso: [DocumentID] = []
    var obsoletes: [DocumentID] = []
    var obsoletedBy: [DocumentID] = []
    var updates: [DocumentID] = []
    var updatedBy: [DocumentID] = []
    var currentStatus: PublicationStatus = .unknown
    var publicationStatus: PublicationStatus = .unknown
    var stream: Stream = .legacy
    var area: String?
    var workingGroup: String?
    var errataURL: URL?
    var doi: String?

    func build() -> RFCMetadata? {
      guard let docID, let year else { return nil }
      return RFCMetadata(
        id: docID,
        title: title,
        authors: authors,
        date: PublicationDate(year: year, month: month, day: day),
        formats: formats,
        pageCount: pageCount,
        keywords: keywords,
        abstract: abstractParagraphs.isEmpty ? nil : abstractParagraphs.joined(separator: "\n\n"),
        draft: draft,
        isAlso: isAlso,
        obsoletes: obsoletes,
        obsoletedBy: obsoletedBy,
        updates: updates,
        updatedBy: updatedBy,
        currentStatus: currentStatus,
        publicationStatus: publicationStatus,
        stream: stream,
        area: area,
        workingGroup: workingGroup,
        errataURL: errataURL,
        doi: doi
      )
    }
  }

  // MARK: - XMLEvents

  func start(_ elementName: String, attributes: [String: String]) {
    path.append(elementName)
    text = ""
    switch elementName {
    case "rfc-entry":
      entry = EntryBuilder()
      entryKind = .rfc
    case "bcp-entry", "std-entry", "fyi-entry":
      entry = EntryBuilder()
      entryKind = .series
    case "rfc-not-issued-entry":
      entry = EntryBuilder()
      entryKind = .notIssued
    case "author":
      entry.currentAuthorName = ""
      entry.currentAuthorRole = nil
    default:
      break
    }
  }

  func text(_ string: String) {
    text.append(string)
  }

  func end(_ elementName: String) {
    defer {
      path.removeLast()
      text = ""
    }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parent = path.count >= 2 ? path[path.count - 2] : ""

    switch elementName {
    case "rfc-entry":
      if let rfc = entry.build() { rfcs.append(rfc) }
      entryKind = nil
    case "bcp-entry", "std-entry", "fyi-entry":
      if let id = entry.docID { series.append(SeriesEntry(id: id, members: entry.isAlso)) }
      entryKind = nil
    case "rfc-not-issued-entry":
      if let id = entry.docID { notIssued.append(id.number) }
      entryKind = nil

    case "doc-id":
      guard let id = DocumentID(parsing: value) else { return }
      switch parent {
      case "is-also": entry.isAlso.append(id)
      case "obsoletes": entry.obsoletes.append(id)
      case "obsoleted-by": entry.obsoletedBy.append(id)
      case "updates": entry.updates.append(id)
      case "updated-by": entry.updatedBy.append(id)
      default: entry.docID = id
      }
    case "title":
      if parent == "author" {
        entry.currentAuthorRole = value
      } else {
        entry.title = value.collapsingWhitespace()
      }
    case "name" where parent == "author":
      entry.currentAuthorName = value
    case "author":
      if !entry.currentAuthorName.isEmpty {
        entry.authors.append(Author(name: entry.currentAuthorName, role: entry.currentAuthorRole))
      }
    case "month": entry.month = PublicationDate.month(from: value)
    case "day": entry.day = Int(value)
    case "year": entry.year = Int(value)
    case "file-format":
      if let format = FileFormat(rawValue: value) { entry.formats.append(format) }
    case "page-count": entry.pageCount = Int(value)
    case "kw":
      if !value.isEmpty { entry.keywords.append(value) }
    case "p" where parent == "abstract":
      entry.abstractParagraphs.append(value.collapsingWhitespace())
    case "draft": entry.draft = value.isEmpty ? nil : value
    case "current-status": entry.currentStatus = PublicationStatus(rawValue: value) ?? .unknown
    case "publication-status":
      entry.publicationStatus = PublicationStatus(rawValue: value) ?? .unknown
    case "stream": entry.stream = Stream(rawValue: value) ?? .legacy
    case "area": entry.area = value.isEmpty ? nil : value
    case "wg_acronym": entry.workingGroup = value.isEmpty ? nil : value
    case "errata-url": entry.errataURL = URL(string: value)
    case "doi": entry.doi = value.isEmpty ? nil : value
    default:
      break
    }
  }

}
