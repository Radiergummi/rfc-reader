import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Streaming parser for `https://www.rfc-editor.org/rfc-index.xml` (about 14 MB, ~10k entries).
///
/// The index is parsed with a SAX-style state machine rather than a tree because it is
/// large and flat; an `XMLElement` tree of it would waste memory on the many tiny nodes.
public final class RFCIndexParser: NSObject, XMLParserDelegate {
    public enum ParseError: Error, Sendable {
        case malformed(line: Int, message: String)
    }

    public static func parse(_ data: Data) throws -> RFCIndex {
        let parser = RFCIndexParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldProcessNamespaces = false
        _ = xml.parse()
        // swift-corelibs-foundation reports a spurious error after the closing root tag on
        // large documents; once the root element has closed, the document is complete.
        if !parser.rootClosed {
            if let error = parser.error { throw error }
            if let error = xml.parserError {
                throw ParseError.malformed(line: xml.lineNumber, message: error.localizedDescription)
            }
            throw ParseError.malformed(line: xml.lineNumber, message: "document ended before </rfc-index>")
        }
        return RFCIndex(rfcs: parser.rfcs, series: parser.series, notIssued: parser.notIssued)
    }

    public static func parse(contentsOf url: URL) throws -> RFCIndex {
        try parse(Data(contentsOf: url))
    }

    // MARK: - State

    private var rfcs: [RFCMetadata] = []
    private var series: [SeriesEntry] = []
    private var notIssued: [Int] = []
    private var error: ParseError?
    private var rootClosed = false

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

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
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

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        text.append(string)
    }

    public func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            path.removeLast()
            text = ""
            if path.isEmpty { rootClosed = true }
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
        case "publication-status": entry.publicationStatus = PublicationStatus(rawValue: value) ?? .unknown
        case "stream": entry.stream = Stream(rawValue: value) ?? .legacy
        case "area": entry.area = value.isEmpty ? nil : value
        case "wg_acronym": entry.workingGroup = value.isEmpty ? nil : value
        case "errata-url": entry.errataURL = URL(string: value)
        case "doi": entry.doi = value.isEmpty ? nil : value
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        error = .malformed(line: parser.lineNumber, message: parseError.localizedDescription)
    }
}
