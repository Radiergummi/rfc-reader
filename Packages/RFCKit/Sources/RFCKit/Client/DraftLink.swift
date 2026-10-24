import Foundation

/// Understands the ways people link to an Internet-Draft (#728): the app's own
/// `rfc://draft-…`, Datatracker's pages and its HTML rendering, and the IETF
/// archive's files, with the section or anchor the link was opened at.
public struct DraftLink: Hashable, Sendable {
  public var id: DraftID
  /// Section or appendix number, as `RFCLink.section` is.
  public var section: String?
  /// A fragment that names no section, kept as it came, as `RFCLink.anchor` is.
  public var anchor: String?

  public init(id: DraftID, section: String? = nil, anchor: String? = nil) {
    self.id = id
    self.section = section
    self.anchor = anchor
  }

  /// Where in the draft the reader goes: the section, or else the anchor.
  public var place: String? { section ?? anchor }

  /// `rfc://draft-ietf-httpbis-semantics-19#section-4.2`.
  public var appURL: URL {
    id.appURL(fragment: section.map(SectionAnchor.anchor(forSectionNumber:)) ?? anchor)
  }

  /// The link `url` makes, when it is the draft's own: its text at the IETF, its
  /// page or its HTML at Datatracker, or the app's own. Nil for a page about the
  /// draft, its history, ballot or writeup, which someone following the link wants
  /// to read on the web.
  public init?(url: URL) {
    let scheme = url.scheme?.lowercased()
    let host = url.host()?.lowercased() ?? ""
    let (section, anchor) = RFCLink.place(inFragmentOf: url)

    if scheme == RFCLink.scheme {
      guard let id = DraftID(parsing: host) else { return nil }
      self.init(id: id, section: section, anchor: anchor)
      return
    }

    guard scheme == "https" || scheme == "http" else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }
    let id: DraftID?
    switch host {
    case "datatracker.ietf.org":
      // /doc/draft-name/, /doc/draft-name/19/, /doc/html/draft-name-19,
      // /doc/draft-name-19/. Anything after the name but a revision is a page
      // about it.
      guard components.first == "doc" else { return nil }
      var rest = components.dropFirst()
      if rest.first == "html" { rest = rest.dropFirst() }
      id = Self.draft(named: rest)
    case "tools.ietf.org":
      // /html/draft-name-19, the old tools site, which Datatracker now serves.
      guard components.first == "html" else { return nil }
      id = Self.draft(named: components.dropFirst())
    case "www.ietf.org", "ietf.org":
      // /archive/id/draft-name-19.txt, and /id/draft-name-19.txt before it.
      let directory = components.dropLast()
      guard directory == ["archive", "id"] || directory == ["id"], let file = components.last
      else { return nil }
      let stem = String(file.prefix { $0 != "." })
      guard Self.documentExtensions.contains(String(file.dropFirst(stem.count))) else {
        return nil
      }
      id = DraftID(parsing: stem)
    default:
      return nil
    }
    guard let id else { return nil }
    self.init(id: id, section: section, anchor: anchor)
  }

  /// The formats a draft's own file comes in at the archive.
  private static let documentExtensions: Set = ["", ".txt", ".xml", ".html", ".pdf"]

  /// The draft path components name: a name, with or without its revision, and
  /// then at most the revision as a component of its own.
  private static func draft(named components: ArraySlice<String>) -> DraftID? {
    guard let first = components.first, let id = DraftID(parsing: first) else { return nil }
    let rest = components.dropFirst()
    switch rest.count {
    case 0:
      return id
    case 1 where id.revision == nil:
      return id.at(revision: rest.first)
    default:
      return nil
    }
  }
}

/// A link to anything the reader can open: an RFC, BCP, STD or FYI, or an
/// Internet-Draft.
public enum ReadableLink: Hashable, Sendable {
  case rfc(RFCLink)
  case draft(DraftLink)

  /// The link `url` makes, an RFC's tried first: see `RFCLink(url:)` and
  /// `DraftLink(url:)`.
  public init?(url: URL) {
    if let link = RFCLink(url: url) {
      self = .rfc(link)
    } else if let link = DraftLink(url: url) {
      self = .draft(link)
    } else {
      return nil
    }
  }

  /// What the link opens.
  public var document: ReadableDocument {
    switch self {
    case .rfc(let link): .rfc(link.id)
    case .draft(let link): .draft(link.id)
    }
  }

  /// Where in the document the reader goes.
  public var place: String? {
    switch self {
    case .rfc(let link): link.place
    case .draft(let link): link.place
    }
  }

  /// The app's own URL for the link.
  public var appURL: URL {
    switch self {
    case .rfc(let link): link.appURL
    case .draft(let link): link.appURL
    }
  }
}
