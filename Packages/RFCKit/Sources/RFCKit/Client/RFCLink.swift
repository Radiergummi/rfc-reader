import Foundation

/// Understands every way people link to RFCs, so the app can open them all:
/// its own `rfc://` scheme, rfc-editor.org, datatracker.ietf.org and tools.ietf.org.
public struct RFCLink: Hashable, Sendable {
  public var id: DocumentID
  /// Section or appendix number, e.g. `4.2` or `A.1`.
  public var section: String?

  public init(id: DocumentID, section: String? = nil) {
    self.id = id
    self.section = section
  }

  /// The app's own URL scheme: `rfc://9110`, `rfc://9110#section-4.2`, `rfc://bcp14`.
  ///
  /// A section is a fragment, because that is what it is — a place within the
  /// document, not a document of its own — and it is spelled the RFC Editor's way,
  /// so the same section names the same place whether the link points at our
  /// reader or at their HTML.
  public static let scheme = "rfc"

  public var appURL: URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = id.series == .rfc ? String(id.number) : id.fileStem
    // Unwrapped because nothing here can fail: the host is a document ID's own
    // letters and digits, and the one caller-supplied part, the section, goes in
    // as a fragment, which `URLComponents` percent-encodes (#150).
    return Self.url(components.url!, section: section)
  }

  /// `url` with `section`'s fragment, the one way every builder attaches a section.
  ///
  /// Through `URLComponents`, which percent-encodes the fragment. A section is
  /// caller-supplied text, and splicing it into a string gave a URL that
  /// `URL(string:)` refused wherever it contained a space or a reserved character
  /// (#150): `appURL` trapped, and the web builders silently dropped the section.
  static func url(_ url: URL, section: String?) -> URL {
    guard let section,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.fragment = fragment(for: section)
    return components.url ?? url
  }

  public var webURL: URL {
    CitationFormatter.url(for: id, section: section)
  }

  public init?(url: URL) {
    let scheme = url.scheme?.lowercased()
    let host = url.host()?.lowercased() ?? ""
    // Decoded, which `url.fragment` is not: the builders percent-encode a section,
    // and `section-4.2%20draft` has to come back as the section it was.
    let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
    let fragmentSection = Self.section(fromFragment: fragment)

    if scheme == Self.scheme {
      guard let id = DocumentID(parsing: host) else { return nil }
      self.init(id: id, section: fragmentSection)
      return
    }

    guard scheme == "https" || scheme == "http" else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }

    switch host {
    case "www.rfc-editor.org", "rfc-editor.org":
      // /rfc/rfc9110.html, /rfc/rfc9110, /info/rfc9110, /rfc/rfc9110.txt, /errata/rfc9110
      guard components.count >= 2, ["rfc", "info", "errata"].contains(components[0]) else {
        return nil
      }
      let stem = (components[1] as NSString).deletingPathExtension
      guard let id = DocumentID(parsing: stem) else { return nil }
      self.init(id: id, section: fragmentSection)
    case "datatracker.ietf.org", "tools.ietf.org":
      // /doc/html/rfc9110, /doc/rfc9110/, /html/rfc9110
      guard let stem = components.last(where: { DocumentID(parsing: $0) != nil }) else {
        return nil
      }
      guard let id = DocumentID(parsing: stem) else { return nil }
      self.init(id: id, section: fragmentSection)
    default:
      return nil
    }
  }

  /// The RFC Editor's and Datatracker's fragment convention, which the app's own
  /// scheme follows too: `4.2` → `section-4.2`, appendix `A.1` → `appendix-A.1`.
  /// `section(fromFragment:)` is the other half, and the two are kept together so
  /// neither can drift.
  static func fragment(for section: String) -> String {
    section.first?.isLetter == true ? "appendix-\(section)" : "section-\(section)"
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
