import Foundation

/// Understands every way people link to RFCs, so the app can open them all:
/// its own `rfc://` scheme, rfc-editor.org, datatracker.ietf.org and tools.ietf.org.
/// `Codable` so it can be a `WindowGroup` value: opening a reference in its own tab
/// hands the link to a new scene, and SwiftUI persists that value across launches.
public struct RFCLink: Hashable, Sendable, Codable {
    public var id: DocumentID
    /// Section or appendix number, e.g. `4.2` or `A.1`.
    public var section: String?

    public init(id: DocumentID, section: String? = nil) {
        self.id = id
        self.section = section
    }

    /// The app's own URL scheme: `rfc://9110`, `rfc://9110/section/4.2`, `rfc://9110#section-4.2`, `rfc://bcp14`.
    public static let scheme = "rfc"

    public var appURL: URL {
        var string = "\(Self.scheme)://\(id.series == .rfc ? String(id.number) : id.fileStem)"
        if let section { string += "/section/\(section)" }
        return URL(string: string)!
    }

    public var webURL: URL {
        CitationFormatter.url(for: id, section: section)
    }

    public init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host()?.lowercased() ?? ""
        let fragmentSection = Self.section(fromFragment: url.fragment)

        if scheme == Self.scheme {
            guard let id = DocumentID(parsing: host) else { return nil }
            let components = url.pathComponents.filter { $0 != "/" }
            var section: String?
            if components.count >= 2, components[0] == "section" {
                section = components[1]
            }
            self.init(id: id, section: section ?? fragmentSection)
            return
        }

        guard scheme == "https" || scheme == "http" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "www.rfc-editor.org", "rfc-editor.org":
            // /rfc/rfc9110.html, /rfc/rfc9110, /info/rfc9110, /rfc/rfc9110.txt, /errata/rfc9110
            guard components.count >= 2, ["rfc", "info", "errata"].contains(components[0]) else { return nil }
            let stem = (components[1] as NSString).deletingPathExtension
            guard let id = DocumentID(parsing: stem) else { return nil }
            self.init(id: id, section: fragmentSection)
        case "datatracker.ietf.org", "tools.ietf.org":
            // /doc/html/rfc9110, /doc/rfc9110/, /html/rfc9110
            guard let stem = components.last(where: { DocumentID(parsing: $0) != nil }) else { return nil }
            guard let id = DocumentID(parsing: stem) else { return nil }
            self.init(id: id, section: fragmentSection)
        default:
            return nil
        }
    }

    /// `section-4.2` → `4.2`, `appendix-A.1` → `A.1`, `page-12` → nil.
    private static func section(fromFragment fragment: String?) -> String? {
        guard let fragment else { return nil }
        for prefix in ["section-", "appendix-"] where fragment.hasPrefix(prefix) {
            let value = String(fragment.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
