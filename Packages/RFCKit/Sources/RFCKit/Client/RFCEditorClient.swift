import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction over `URLSession` so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
    func data(for url: URL) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/xml, text/plain, application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RFCEditorClient.ClientError.invalidResponse(url)
        }
        return (data, http)
    }
}

/// Fetches and parses documents from the RFC Editor.
///
/// Callers decide about caching; this type only knows how to get bytes and turn them
/// into models. Keeping it an actor makes it trivially safe to share across the app.
public actor RFCEditorClient {
    public enum ClientError: Error, Sendable {
        case invalidResponse(URL)
        case httpStatus(Int, URL)
        case notFound(DocumentID)
        case decoding(String)
    }

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    public func fetchIndex() async throws -> RFCIndex {
        let data = try await fetch(RFCEditorEndpoints.index)
        do {
            return try RFCIndexParser.parse(data)
        } catch {
            throw ClientError.decoding("rfc-index.xml: \(error)")
        }
    }

    /// Raw bytes of a document in the given format, for caching.
    public func fetchDocumentData(_ id: DocumentID, format: FileFormat) async throws -> Data {
        try await fetch(RFCEditorEndpoints.document(id, format: format), notFoundAs: id)
    }

    /// Parses a document, preferring the semantic XML source when available and
    /// falling back to the plain-text rendering otherwise.
    public func fetchDocument(_ id: DocumentID, availableFormats: [FileFormat]? = nil) async throws -> RFCDocument {
        let tryXML = availableFormats?.contains(.xml) ?? true
        if tryXML {
            if let data = try? await fetchDocumentData(id, format: .xml),
               let document = try? RFCXMLParser.parse(data) {
                return document
            }
        }
        let data = try await fetchDocumentData(id, format: .text)
        return LegacyTextParser.parse(data)
    }

    public func fetchMetadata(_ id: DocumentID) async throws -> RFCEditorMetadataRecord {
        let data = try await fetch(RFCEditorEndpoints.metadata(id), notFoundAs: id)
        do {
            return try JSONDecoder().decode(RFCEditorMetadataRecord.self, from: data)
        } catch {
            throw ClientError.decoding("\(id.fileStem).json: \(error)")
        }
    }

    public func fetchRecent() async throws -> [RecentRFC] {
        let data = try await fetch(RFCEditorEndpoints.recentFeed)
        return try RecentFeedParser.parse(data)
    }

    // MARK: - Private

    private func fetch(_ url: URL, notFoundAs id: DocumentID? = nil) async throws -> Data {
        let (data, response) = try await transport.data(for: url)
        switch response.statusCode {
        case 200..<300:
            return data
        case 404:
            if let id { throw ClientError.notFound(id) }
            throw ClientError.httpStatus(404, url)
        default:
            throw ClientError.httpStatus(response.statusCode, url)
        }
    }
}

/// The RFC Editor's per-document JSON (`/rfc/rfc9110.json`).
public struct RFCEditorMetadataRecord: Codable, Sendable {
    public var docID: String
    public var title: String
    public var authors: [String]
    public var format: [String]
    public var pageCount: String?
    public var pubStatus: String
    public var status: String
    public var source: String?
    public var abstract: String?
    public var pubDate: String
    public var keywords: [String]
    public var obsoletes: [String]
    public var obsoletedBy: [String]
    public var updates: [String]
    public var updatedBy: [String]
    public var seeAlso: [String]
    public var doi: String?
    public var errataURL: String?
    public var draft: String?

    enum CodingKeys: String, CodingKey {
        case docID = "doc_id"
        case title, authors, format
        case pageCount = "page_count"
        case pubStatus = "pub_status"
        case status, source, abstract
        case pubDate = "pub_date"
        case keywords, obsoletes
        case obsoletedBy = "obsoleted_by"
        case updates
        case updatedBy = "updated_by"
        case seeAlso = "see_also"
        case doi
        case errataURL = "errata_url"
        case draft
    }

    public var id: DocumentID? { DocumentID(parsing: docID) }
    public var currentStatus: PublicationStatus { PublicationStatus(rawValue: status) ?? .unknown }
}

/// One entry of the "Recent RFCs" RSS feed.
public struct RecentRFC: Sendable, Hashable, Identifiable {
    public var id: DocumentID
    public var title: String
    public var summary: String
    public var link: URL?
    public var publishedAt: Date?

    public init(id: DocumentID, title: String, summary: String, link: URL? = nil, publishedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.link = link
        self.publishedAt = publishedAt
    }
}

public enum RecentFeedParser {
    public enum ParseError: Error, Sendable {
        case malformed(String)
    }

    nonisolated(unsafe) private static let titlePattern = #/^RFC\s*(?<number>\d+):\s*(?<title>.+)$/#

    public static func parse(_ data: Data) throws -> [RecentRFC] {
        let root: XMLElement
        do {
            root = try XMLTreeBuilder.parse(data)
        } catch {
            throw ParseError.malformed("\(error)")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        var items: [RecentRFC] = []
        for item in root.first("channel")?.all("item") ?? [] {
            let rawTitle = item.first("title")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let match = rawTitle.firstMatch(of: titlePattern), let number = Int(match.number) else { continue }
            items.append(RecentRFC(
                id: .rfc(number),
                title: String(match.title).trimmingCharacters(in: .whitespaces),
                summary: item.first("description")?.text.collapsingWhitespace() ?? "",
                link: item.first("link")?.text.trimmingCharacters(in: .whitespacesAndNewlines).flatMap(URL.init(string:)),
                publishedAt: item.first("pubDate")?.text.trimmingCharacters(in: .whitespacesAndNewlines).flatMap(formatter.date(from:))
            ))
        }
        return items
    }
}

private extension String {
    func flatMap<T>(_ transform: (String) -> T?) -> T? { transform(self) }
}
