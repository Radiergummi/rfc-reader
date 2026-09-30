import Foundation

/// Understands every way people link to RFCs, so the app can open them all:
/// its own `rfc://` scheme, rfc-editor.org, datatracker.ietf.org and tools.ietf.org.
public struct RFCLink: Hashable, Sendable {
  public var id: DocumentID
  /// Section or appendix number, e.g. `4.2` or `A.1`. An appendix numbered like a
  /// section, as legacy RFCs number `Appendix 1`, is its anchor, `appendix-1`: the
  /// number alone names section 1. A place is a number or an anchor, and
  /// `RFCDocument.anchor(forPlace:)` resolves either.
  public var section: String?
  /// A fragment that names no section, kept as it came: an anchor the document may
  /// define, such as an author's `sample-varint`, or one it doesn't, such as the RFC
  /// Editor's `page-12` (#276). Only the reader reads it, to go there or to open at
  /// the top; a citation names a section, and never this.
  public var anchor: String?

  public init(id: DocumentID, section: String? = nil, anchor: String? = nil) {
    self.id = id
    self.section = section
    self.anchor = anchor
  }

  /// Where in the document the reader goes: the section, or else the anchor.
  public var place: String? { section ?? anchor }

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
    components.fragment = section.map(SectionAnchor.anchor(forSectionNumber:)) ?? anchor
    // Unwrapped because nothing here can fail: the host is a document ID's own
    // letters and digits, and the one caller-supplied part, the section, goes in
    // as a fragment, which `URLComponents` percent-encodes (#150).
    return components.url!
  }

  /// `url` with `section`'s fragment, the one way every web builder attaches a section.
  ///
  /// Through `URLComponents`, which percent-encodes the fragment. A section is
  /// caller-supplied text, and splicing it into a string gave a URL that
  /// `URL(string:)` refused wherever it contained a space or a reserved character
  /// (#150): `appURL` trapped, and the web builders silently dropped the section.
  static func url(_ url: URL, section: String?) -> URL {
    guard let section,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.fragment = SectionAnchor.anchor(forSectionNumber: section)
    return components.url ?? url
  }

  public var webURL: URL {
    guard section == nil, let anchor else {
      return CitationFormatter.url(for: id, section: section)
    }
    // The document's page, which defines the anchor, rather than its info page.
    let page = RFCEditorEndpoints.base.appending(path: "rfc/\(id.fileStem)")
    guard var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else {
      return page
    }
    components.fragment = anchor
    return components.url ?? page
  }

  public init?(url: URL) {
    let scheme = url.scheme?.lowercased()
    let host = url.host()?.lowercased() ?? ""
    // Decoded, which `url.fragment` is not: the builders percent-encode a section,
    // and `section-4.2%20draft` has to come back as the section it was.
    let fragment = url.fragment(percentEncoded: false) ?? ""
    let fragmentSection = SectionAnchor.sectionNumber(fromAnchor: fragment)
    // Any other fragment is an anchor, unless it starts with a digit: an XML ID
    // cannot, and a bare `#4.2` is no section either (#276).
    let fragmentAnchor =
      fragmentSection == nil && fragment.first.map { !$0.isNumber } == true ? fragment : nil

    if scheme == Self.scheme {
      guard let id = DocumentID(parsing: host) else { return nil }
      self.init(id: id, section: fragmentSection, anchor: fragmentAnchor)
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
      self.init(id: id, section: fragmentSection, anchor: fragmentAnchor)
    case "datatracker.ietf.org", "tools.ietf.org":
      // /doc/html/rfc9110, /doc/rfc9110/, /html/rfc9110
      guard let stem = components.last(where: { DocumentID(parsing: $0) != nil }) else {
        return nil
      }
      guard let id = DocumentID(parsing: stem) else { return nil }
      self.init(id: id, section: fragmentSection, anchor: fragmentAnchor)
    default:
      return nil
    }
  }
}
