import Foundation

/// Produces citations for an RFC in the formats people actually paste into things.
public enum CitationStyle: String, CaseIterable, Sendable, Identifiable {
    /// `RFC 9110, Section 4.2` — for chat, commit messages and code comments.
    case short
    /// The RFC Editor's recommended full citation.
    case full
    /// `[RFC 9110, Section 4.2](https://www.rfc-editor.org/rfc/rfc9110#section-4.2)`
    case markdown
    /// BibTeX entry in the shape the Datatracker emits.
    case bibtex
    /// Just the canonical URL.
    case url

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .short: "Short"
        case .full: "Full citation"
        case .markdown: "Markdown link"
        case .bibtex: "BibTeX"
        case .url: "URL"
        }
    }
}

public struct CitationFormatter: Sendable {
    public init() {}

    public func cite(_ rfc: RFCMetadata, section: String? = nil, style: CitationStyle) -> String {
        switch style {
        case .short:
            return sectionSuffix(section).map { "\(rfc.id.displayName), \($0)" } ?? rfc.id.displayName
        case .url:
            return Self.url(for: rfc.id, section: section).absoluteString
        case .markdown:
            let label = cite(rfc, section: section, style: .short)
            return "[\(label)](\(Self.url(for: rfc.id, section: section).absoluteString))"
        case .full:
            return fullCitation(rfc, section: section)
        case .bibtex:
            return bibtex(rfc)
        }
    }

    /// The RFC Editor's own HTML has `#section-N` anchors; deep links go there.
    public static func url(for id: DocumentID, section: String? = nil) -> URL {
        let base = RFCEditorEndpoints.base.appending(path: "rfc/\(id.fileStem)")
        guard let section else { return RFCEditorEndpoints.infoPage(id) }
        return URL(string: base.absoluteString + "#\(RFCLink.fragment(for: section))") ?? base
    }

    private func sectionSuffix(_ section: String?) -> String? {
        guard let section, !section.isEmpty else { return nil }
        return section.first?.isLetter == true ? "Appendix \(section)" : "Section \(section)"
    }

    private func fullCitation(_ rfc: RFCMetadata, section: String?) -> String {
        // Matches the format shown on every rfc-editor.org info page:
        // Fielding, R., Ed., Nottingham, M., Ed., and J. Reschke, Ed., "HTTP Semantics", STD 97, RFC 9110, DOI 10.17487/RFC9110, June 2022, <https://www.rfc-editor.org/info/rfc9110>.
        var parts: [String] = []
        parts.append(Self.authorList(rfc.authors))
        parts.append("\"\(rfc.title)\"")
        for series in rfc.isAlso where series.series != .rfc {
            parts.append(series.displayName)
        }
        parts.append(rfc.id.displayName)
        if let doi = rfc.doi { parts.append("DOI \(doi)") }
        parts.append(rfc.date.formatted)
        parts.append("<\(RFCEditorEndpoints.infoPage(rfc.id).absoluteString)>")
        var citation = parts.joined(separator: ", ") + "."
        if let suffix = sectionSuffix(section) {
            citation += " \(suffix)."
        }
        return citation
    }

    /// `S. Bradner` → `Bradner, S.`; last author gets `and` with initials first.
    static func authorList(_ authors: [Author]) -> String {
        func inverted(_ author: Author) -> String {
            let name = author.name
            guard let lastSpace = name.lastIndex(of: " ") else { return name + roleSuffix(author) }
            let surname = String(name[name.index(after: lastSpace)...])
            let initials = String(name[..<lastSpace])
            return "\(surname), \(initials)\(roleSuffix(author))"
        }
        func roleSuffix(_ author: Author) -> String {
            author.role?.lowercased().hasPrefix("ed") == true ? ", Ed." : ""
        }
        switch authors.count {
        case 0: return "IETF"
        case 1: return inverted(authors[0])
        case 2: return "\(inverted(authors[0])) and \(authors[1].name)\(roleSuffix(authors[1]))"
        default:
            let head = authors.dropLast().map(inverted).joined(separator: ", ")
            let last = authors[authors.count - 1]
            return "\(head), and \(last.name)\(roleSuffix(last))"
        }
    }

    private func bibtex(_ rfc: RFCMetadata) -> String {
        let key = rfc.id.fileStem
        let authors = rfc.authors.map(\.name).joined(separator: " and ")
        var fields: [(String, String)] = [
            ("series", "{Request for Comments}"),
            ("number", String(rfc.number)),
            ("howpublished", "{\(rfc.id.displayName)}"),
            ("publisher", "{RFC Editor}"),
        ]
        if let doi = rfc.doi { fields.append(("doi", "{\(doi)}")) }
        fields.append(("url", "{\(RFCEditorEndpoints.infoPage(rfc.id).absoluteString)}"))
        if !authors.isEmpty { fields.append(("author", "{\(authors)}")) }
        fields.append(("title", "{{\(rfc.title)}}"))
        if let pages = rfc.pageCount { fields.append(("pagetotal", String(pages))) }
        fields.append(("year", String(rfc.date.year)))
        if let monthName = rfc.date.monthName { fields.append(("month", String(monthName.prefix(3).lowercased()))) }
        if let abstract = rfc.abstract { fields.append(("abstract", "{\(abstract)}")) }
        let body = fields.map { "    \($0.0) = \($0.1)," }.joined(separator: "\n")
        return "@misc{\(key),\n\(body)\n}"
    }
}
