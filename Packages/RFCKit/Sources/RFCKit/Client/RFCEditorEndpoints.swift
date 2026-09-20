import Foundation

/// URL construction for the RFC Editor and IETF Datatracker. All of these were
/// verified live in September 2026; none require authentication.
public enum RFCEditorEndpoints {
    public static let base = URL(string: "https://www.rfc-editor.org")!
    public static let datatrackerBase = URL(string: "https://datatracker.ietf.org")!

    /// The full index, about 14 MB of XML covering every RFC, BCP, STD and FYI.
    public static var index: URL { base.appending(path: "rfc-index.xml") }

    /// RSS feed of recently published RFCs; cheap to poll for "what's new".
    public static var recentFeed: URL { base.appending(path: "rfcrss.xml") }

    /// Every erratum ever filed, as one JSON array (about 12 MB).
    public static var errata: URL { base.appending(path: "errata.json") }

    /// The document body in the given format, e.g. `/rfc/rfc9110.xml`.
    public static func document(_ id: DocumentID, format: FileFormat) -> URL {
        base.appending(path: "rfc/\(id.fileStem).\(format.pathExtension)")
    }

    /// Lightweight per-RFC metadata (status, obsoletes, updates, errata URL).
    public static func metadata(_ id: DocumentID) -> URL {
        base.appending(path: "rfc/\(id.fileStem).json")
    }

    /// The human-facing landing page, the canonical thing to share.
    public static func infoPage(_ id: DocumentID) -> URL {
        base.appending(path: "info/\(id.fileStem)")
    }

    public static func errataPage(_ id: DocumentID) -> URL {
        base.appending(path: "errata/\(id.fileStem)")
    }

    /// Datatracker's HTMLized rendering, which has anchors for every section and reference.
    public static func datatracker(_ id: DocumentID, section: String? = nil) -> URL {
        var url = datatrackerBase.appending(path: "doc/html/\(id.fileStem)")
        if let section {
            url = URL(string: url.absoluteString + "#section-\(section)") ?? url
        }
        return url
    }

    /// Datatracker's document record, including working group and history.
    public static func datatrackerDocument(_ id: DocumentID) -> URL {
        datatrackerBase.appending(path: "api/v1/doc/document/")
            .appending(queryItems: [
                URLQueryItem(name: "name", value: id.fileStem),
                URLQueryItem(name: "format", value: "json"),
            ])
    }
}
