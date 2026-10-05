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
    Self.url(url, fragment: section.map(SectionAnchor.anchor(forSectionNumber:)))
  }

  /// `url` with `fragment` as its fragment, percent-encoded as `url(_:section:)`
  /// says.
  static func url(_ url: URL, fragment: String?) -> URL {
    guard let fragment,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.fragment = fragment
    return components.url ?? url
  }

  public var webURL: URL {
    guard section == nil, let anchor else {
      return CitationFormatter.url(for: id, section: section)
    }
    // The document's page, which defines the anchor, rather than its info page.
    return Self.url(
      RFCEditorEndpoints.base.appending(path: "rfc/\(id.fileStem)"), fragment: anchor)
  }

  /// The link `url` makes, where a citation can say all of it: an RFC itself, or one
  /// of its sections. Nil for a page about it, its errata or its history, and for an
  /// anchor that names no section, which a citation has no place for and would open
  /// at the document's top instead (#683).
  public init?(citing url: URL) {
    guard let link = RFCLink(url: url), link.id.series == .rfc, link.anchor == nil,
      !url.pathComponents.contains(where: { ["errata", "inline-errata"].contains($0) }),
      DocumentID(parsing: url.deletingPathExtension().lastPathComponent) == link.id
    else { return nil }
    self = link
  }

  /// The link `url` makes where it is the document's own page, which the Safari
  /// extension may send to the app on its own (#194): its text at the RFC Editor in
  /// any format, or its page at Datatracker, with the section or anchor it was
  /// opened at. Nil for a page about the document, its info page, errata or history,
  /// which someone following the link wants to read on the web.
  public init?(documentPage url: URL) {
    let name = url.lastPathComponent
    guard url.scheme?.lowercased() != Self.scheme, let link = RFCLink(url: url),
      !url.pathComponents.contains(where: { ["info", "errata", "inline-errata"].contains($0) }),
      DocumentID(parsing: Self.stem(of: name)) == link.id,
      Self.documentExtensions.contains(String(name.dropFirst(Self.stem(of: name).count)))
    else { return nil }
    self = link
  }

  /// The formats a document's own page comes in; any other, such as the RFC Editor's
  /// `.json` of its metadata, is a page about it.
  private static let documentExtensions: Set = ["", ".html", ".txt", ".xml", ".pdf", ".txt.pdf"]

  /// A file name without any of its extensions: `rfc4321` of `rfc4321.txt.pdf`.
  private static func stem(of name: String) -> String {
    String(name.prefix { $0 != "." })
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
      fragmentSection == nil && fragment.first?.isNumber == false ? fragment : nil

    if scheme == Self.scheme {
      guard let id = DocumentID(parsing: host) else { return nil }
      self.init(id: id, section: fragmentSection, anchor: fragmentAnchor)
      return
    }

    guard scheme == "https" || scheme == "http" else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }

    switch host {
    case "www.rfc-editor.org", "rfc-editor.org":
      // /rfc/rfc9110.html, /rfc/rfc9110, /info/rfc9110, /rfc/rfc9110.txt, /errata/rfc9110,
      // and the PDF, /rfc/rfc9110.pdf or a legacy RFC's /rfc/pdfrfc/rfc2616.txt.pdf
      guard components.count >= 2, ["rfc", "info", "errata"].contains(components[0]),
        let id = DocumentID(parsing: Self.stem(of: components[components.count - 1]))
      else { return nil }
      self.init(id: id, section: fragmentSection, anchor: fragmentAnchor)
    case "datatracker.ietf.org", "tools.ietf.org":
      // /doc/html/rfc9110, /doc/rfc9110/, /html/rfc9110. Spelled with its series: a
      // bare number here is a draft's revision, a meeting or an IPR disclosure.
      guard
        let id = components.lazy.reversed()
          .filter({ $0.first?.isLetter == true })
          .compactMap(DocumentID.init(parsing:)).first
      else { return nil }
      self.init(id: id, section: fragmentSection, anchor: fragmentAnchor)
    default:
      return nil
    }
  }
}
