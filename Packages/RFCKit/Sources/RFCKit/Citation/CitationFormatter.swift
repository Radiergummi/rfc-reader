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
  /// An xml2rfc `<reference>` element, as bib.ietf.org serves it: what an
  /// Internet-Draft's author pastes into their own references (#712).
  case xml2rfc

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .short: "Short"
    case .full: "Full citation"
    case .markdown: "Markdown link"
    case .bibtex: "BibTeX"
    case .url: "URL"
    case .xml2rfc: "xml2rfc reference"
    }
  }

  /// Whether the style says more than the designation and the link, and so is made
  /// from the index's entry: an unlisted document can be cited only in the others.
  public var needsIndexEntry: Bool {
    switch self {
    case .short, .markdown, .url: false
    case .full, .bibtex, .xml2rfc: true
    }
  }

  /// Whether a citation in this style names a section. A BibTeX entry and an
  /// xml2rfc reference describe the document as a whole: neither has a field that
  /// says "and I mean §4.2" (xml2rfc says it in the `xref` that cites the
  /// reference), so a section would silently become part of the title or be dropped
  /// by whoever renders it. Better to cite the document, which is what their keys
  /// are for.
  public var citesSections: Bool {
    switch self {
    case .short, .full, .markdown, .url: true
    case .bibtex, .xml2rfc: false
    }
  }
}

/// What a citation is made from: an RFC's entry in the index, or a BCP, STD or FYI
/// and its members' (#712). A series is cited as itself, never as its first RFC,
/// whose text the reader shows for it (#656).
public enum CitedDocument: Hashable, Sendable {
  case rfc(RFCMetadata)
  case series(DocumentID, members: [RFCMetadata])

  /// `id` as `index` describes it: nil for an RFC it doesn't list, and for a series
  /// none of whose members it lists.
  public init?(_ id: DocumentID, in index: RFCIndex) {
    guard id.series != .rfc else {
      guard let metadata = index[id] else { return nil }
      self = .rfc(metadata)
      return
    }
    let members = index.series(id)?.members.compactMap { index[$0] } ?? []
    guard !members.isEmpty else { return nil }
    self = .series(id, members: members)
  }

  /// The designation alone, with nothing the index says: enough for the styles that
  /// do not need its entry (`CitationStyle.needsIndexEntry`).
  public init(bare id: DocumentID) {
    self =
      id.series == .rfc
      ? .rfc(RFCMetadata(id: id, title: "", date: PublicationDate(year: 0)))
      : .series(id, members: [])
  }

  public var id: DocumentID {
    switch self {
    case .rfc(let metadata): metadata.id
    case .series(let id, _): id
    }
  }
}

public enum CitationFormatter {
  public static func cite(
    _ rfc: RFCMetadata, section: String? = nil, style: CitationStyle,
    site: LinkSite = .rfcEditor
  ) -> String {
    cite(.rfc(rfc), section: section, style: style, site: site)
  }

  /// `document` cited in `style`, at `section` where the style names one, linking to
  /// `site`.
  public static func cite(
    _ document: CitedDocument, section: String? = nil, style: CitationStyle,
    site: LinkSite = .rfcEditor
  ) -> String {
    let id = document.id
    switch style {
    case .short:
      return shortCitation(id, section: section)
    case .url:
      return link(to: id, section: section, site: site).absoluteString
    case .markdown:
      let label = shortCitation(id, section: section)
      return "[\(label)](\(link(to: id, section: section, site: site).absoluteString))"
    case .full:
      switch document {
      case .rfc(let rfc): return fullCitation(rfc, section: section, site: site)
      case .series(let id, let members):
        return seriesFullCitation(id, members: members, section: section, site: site)
      }
    case .bibtex:
      switch document {
      case .rfc(let rfc): return bibtex(rfc, site: site)
      case .series(let id, let members): return seriesBibtex(id, members: members, site: site)
      }
    case .xml2rfc:
      switch document {
      case .rfc(let rfc): return xml2rfcReference(rfc, site: site, indent: "")
      case .series(let id, let members):
        return xml2rfcReferenceGroup(id, members: members, site: site)
      }
    }
  }

  /// Where a citation links: the section on `site`, except a series' section on the
  /// web. A series has no page of its own sections, the RFC Editor's
  /// `rfc/bcp14#section-2` is no page at all, so the link is to the series and the
  /// label names the section. The app opens a series at a section.
  private static func link(to id: DocumentID, section: String?, site: LinkSite) -> URL {
    let linksSection = id.series == .rfc || site == .app
    return url(for: id, section: linksSection ? section : nil, site: site)
  }

  /// The document, or its section, on `site` (`LinkSite.url(for:)`).
  public static func url(
    for id: DocumentID, section: String? = nil, site: LinkSite = .rfcEditor
  ) -> URL {
    site.url(for: RFCLink(id: id, section: section))
  }

  /// `RFC 9110, Section 4.2`, `RFC 9110, Appendix A.1`, or the document alone.
  public static func shortCitation(_ id: DocumentID, section: String? = nil) -> String {
    sectionSuffix(section).map { "\(id.displayName), \($0)" } ?? id.displayName
  }

  private static func sectionSuffix(_ section: String?) -> String? {
    guard let section, !section.isEmpty else { return nil }
    return PlaceName.spelledOut(section)
  }

  private static func fullCitation(_ rfc: RFCMetadata, section: String?, site: LinkSite)
    -> String
  {
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
    parts.append("<\(url(for: rfc.id, site: site).absoluteString)>")
    var citation = parts.joined(separator: ", ") + "."
    if let suffix = sectionSuffix(section) {
      citation += " \(suffix)."
    }
    return citation
  }

  /// The RFC Editor's form for a series, as an RFC's references list one:
  ///
  ///     Best Current Practice 14, <https://www.rfc-editor.org/info/bcp14>.
  ///     At the time of writing, this BCP comprises the following:
  ///     Bradner, S., "Key words …", BCP 14, RFC 2119, …
  private static func seriesFullCitation(
    _ id: DocumentID, members: [RFCMetadata], section: String?, site: LinkSite
  ) -> String {
    var first =
      "\(id.series.displayName) \(id.number), <\(url(for: id, site: site).absoluteString)>."
    if let suffix = sectionSuffix(section) {
      first += " \(suffix)."
    }
    let comprises = "At the time of writing, this \(id.series.rawValue) comprises the following:"
    let lines = members.map { fullCitation($0, section: nil, site: site) }
    return ([first, comprises] + lines).joined(separator: "\n")
  }

  /// `S. Bradner` → `Bradner, S.`, `F. Le Faucheur` → `Le Faucheur, F.`; last author
  /// gets `and` with initials first. A name that is all surname, an organization's,
  /// is not inverted.
  static func authorList(_ authors: [Author]) -> String {
    func inverted(_ author: Author) -> String {
      let initials = author.givenNames
      guard !initials.isEmpty else { return author.name + roleSuffix(author) }
      return "\(author.surname), \(initials)\(roleSuffix(author))"
    }
    func roleSuffix(_ author: Author) -> String {
      author.isEditor ? ", Ed." : ""
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

  private static func bibtex(_ rfc: RFCMetadata, site: LinkSite) -> String {
    let key = rfc.id.fileStem
    let authors = rfc.authors.map(\.name).joined(separator: " and ")
    var fields: [(String, String)] = [
      ("series", "{Request for Comments}"),
      ("number", String(rfc.number)),
      ("howpublished", "{\(rfc.id.displayName)}"),
      ("publisher", "{RFC Editor}"),
    ]
    if let doi = rfc.doi { fields.append(("doi", "{\(doi)}")) }
    fields.append(("url", "{\(url(for: rfc.id, site: site).absoluteString)}"))
    if !authors.isEmpty { fields.append(("author", "{\(Self.bibtexEscaped(authors))}")) }
    fields.append(("title", "{{\(Self.bibtexEscaped(rfc.title))}}"))
    if let pages = rfc.pageCount { fields.append(("pagetotal", String(pages))) }
    fields.append(("year", String(rfc.date.year)))
    if let monthName = rfc.date.monthName {
      fields.append(("month", String(monthName.prefix(3).lowercased())))
    }
    if let abstract = rfc.abstract {
      fields.append(("abstract", "{\(Self.bibtexEscaped(abstract))}"))
    }
    return bibtexEntry(key: key, fields: fields)
  }

  /// A series as one entry, which names its members: a reference manager keeps one
  /// key for `BCP 14` as an RFC's references list one entry for it.
  private static func seriesBibtex(_ id: DocumentID, members: [RFCMetadata], site: LinkSite)
    -> String
  {
    var fields: [(String, String)] = [
      ("series", "{\(id.series.displayName)}"),
      ("number", String(id.number)),
      ("howpublished", "{\(id.displayName)}"),
      ("publisher", "{RFC Editor}"),
      ("url", "{\(url(for: id, site: site).absoluteString)}"),
      ("title", "{{\(id.series.displayName) \(id.number)}}"),
    ]
    if !members.isEmpty {
      let names = members.map(\.id.displayName).joined(separator: ", ")
      fields.append(("note", "{Comprises \(names)}"))
    }
    return bibtexEntry(key: id.fileStem, fields: fields)
  }

  private static func bibtexEntry(key: String, fields: [(String, String)]) -> String {
    let body = fields.map { "    \($0.0) = \($0.1)," }.joined(separator: "\n")
    return "@misc{\(key),\n\(body)\n}"
  }

  /// An RFC as bib.ietf.org writes its `<reference>`: the title, each author by
  /// initials and surname (an organization's as an `organization`), the month and
  /// year, then its series, the RFC itself and its DOI. No abstract, which xml2rfc
  /// does not render in a references section.
  private static func xml2rfcReference(_ rfc: RFCMetadata, site: LinkSite, indent: String)
    -> String
  {
    var lines = [
      "<reference anchor=\"\(xmlAnchor(rfc.id))\" target=\"\(xmlEscaped(url(for: rfc.id, site: site).absoluteString))\">",
      "  <front>",
      "    <title>\(xmlEscaped(rfc.title))</title>",
    ]
    for author in rfc.authors {
      let initials = author.givenNames
      guard !initials.isEmpty else {
        lines += [
          "    <author>",
          "      <organization>\(xmlEscaped(author.name))</organization>",
          "    </author>",
        ]
        continue
      }
      var attributes = [("fullname", author.name), ("initials", initials)]
      if author.isEditor { attributes.append(("role", "editor")) }
      attributes.append(("surname", author.surname))
      lines.append("    <author\(xmlAttributes(attributes))/>")
    }
    var date: [(String, String)] = []
    if let month = rfc.date.monthName { date.append(("month", month)) }
    date.append(("year", String(rfc.date.year)))
    lines += ["    <date\(xmlAttributes(date))/>", "  </front>"]
    var series = rfc.isAlso.filter { $0.series != .rfc }.map {
      ($0.series.rawValue, String($0.number))
    }
    series.append(("RFC", String(rfc.number)))
    if let doi = rfc.doi { series.append(("DOI", doi)) }
    for (name, value) in series {
      lines.append("  <seriesInfo\(xmlAttributes([("name", name), ("value", value)]))/>")
    }
    lines.append("</reference>")
    return lines.map { indent + $0 }.joined(separator: "\n")
  }

  /// A series as bib.ietf.org writes it: a `<referencegroup>` of its members'
  /// references, which xml2rfc renders as the RFC Editor's form for a series.
  private static func xml2rfcReferenceGroup(
    _ id: DocumentID, members: [RFCMetadata], site: LinkSite
  ) -> String {
    let open =
      "<referencegroup anchor=\"\(xmlAnchor(id))\" target=\"\(xmlEscaped(url(for: id, site: site).absoluteString))\">"
    let references = members.map { xml2rfcReference($0, site: site, indent: "  ") }
    return ([open] + references + ["</referencegroup>"]).joined(separator: "\n")
  }

  /// `RFC9110`, `BCP14`: the anchor every I-D cites the document by.
  private static func xmlAnchor(_ id: DocumentID) -> String {
    "\(id.series.rawValue)\(id.number)"
  }

  private static func xmlAttributes(_ attributes: [(String, String)]) -> String {
    attributes.map { " \($0.0)=\"\(xmlEscaped($0.1))\"" }.joined()
  }

  /// Text for an element or an attribute: a title holding `&` or `<`, or an author's
  /// name a quotation mark, would otherwise end it early.
  static func xmlEscaped(_ text: String) -> String {
    var escaped = ""
    for character in text {
      switch character {
      case "&": escaped += "&amp;"
      case "<": escaped += "&lt;"
      case ">": escaped += "&gt;"
      case "\"": escaped += "&quot;"
      default: escaped.append(character)
      }
    }
    return escaped
  }

  /// Text for a brace-delimited BibTeX field. An unbalanced brace ends the field
  /// early, `%` starts a comment and `&` is LaTeX's alignment character, so a title
  /// holding any of them made the whole entry invalid (#150). Braces are spelled
  /// out rather than escaped, because BibTeX counts a brace whether or not a
  /// backslash precedes it, so `\{` only works for braces that already pair up. A
  /// backslash of the text's own is spelled out too, so it can't start a command.
  /// BibTeX accepts `_ $ # ^ ~`, but LaTeX reads them as markup when it typesets
  /// the field (#242). `\^` and `\~` are accent commands, so those two are
  /// spelled out as well. It goes by scalar, since a combining mark after one of
  /// these makes a `Character` that no case matches.
  static func bibtexEscaped(_ text: String) -> String {
    var escaped = ""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\\": escaped.append("\\textbackslash{}")
      case "{": escaped.append("\\textbraceleft{}")
      case "}": escaped.append("\\textbraceright{}")
      case "%", "&", "_", "$", "#": escaped.append("\\\(scalar)")
      case "^": escaped.append("\\textasciicircum{}")
      case "~": escaped.append("\\textasciitilde{}")
      default: escaped.unicodeScalars.append(scalar)
      }
    }
    return escaped
  }
}
