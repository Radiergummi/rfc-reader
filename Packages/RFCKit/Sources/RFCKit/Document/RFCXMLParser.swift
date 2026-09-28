import Foundation

/// Parses RFCXML v3 (RFC 7991) as published by the RFC Editor into an `RFCDocument`.
///
/// The RFC Editor's "prepped" XML carries `pn` (part number) attributes and
/// `derivedContent` on cross references, which this parser leans on for stable
/// anchors and display text instead of re-implementing the numbering rules.
public struct RFCXMLParser: Sendable {
  public enum ParseError: Error, Sendable, Equatable {
    case notAnRFC(rootElement: String)
    case malformed(XMLSyntaxError)
  }

  public init() {}

  public static func parse(_ data: Data) throws(ParseError) -> RFCDocument {
    try RFCXMLParser().parse(data)
  }

  public func parse(_ data: Data) throws(ParseError) -> RFCDocument {
    let root: XMLTree.Element
    do {
      root = try XMLTree.parse(data)
    } catch {
      throw .malformed(error)
    }
    guard root.name == "rfc" else { throw .notAnRFC(rootElement: root.name) }

    // References first, so cross references in the body resolve to RFC numbers.
    // Every list, not only the back's: a converted legacy document can hold one in
    // `<middle>` (RFC 2511's `9. References`, ahead of its appendices), or in a
    // chapter, and a citation into it is as much a link as one into the back.
    let back = root.first("back")
    let builder = Builder(referenceTargets: Builder.referenceTargets(in: root))

    let header = builder.parseHeader(root)
    var sections: [Section] = []
    if let middle = root.first("middle") {
      sections += builder.parseSections(in: middle, appendix: false, position: nil)
    }
    if let back {
      var count = 0
      for element in back.elements {
        switch element.name {
        case "references":
          count += 1
          sections.append(builder.parseReferencesSection(element))
        case "section":
          count += 1
          sections.append(builder.parseSection(element, appendix: true, position: "back-\(count)"))
        default:
          break
        }
      }
    }
    var document = RFCDocument(header: header, sections: sections, source: .xml)
    document.abbreviations = Abbreviations.defined(in: document)
    return document
  }

  /// Whether a `<link rel>` names `token`. RFCXML takes `rel` from HTML, where it is a
  /// set of space-separated keywords compared without regard to ASCII case, so
  /// `rel="Prev"` and `rel="prev alternate"` both name the preceding draft. The prep
  /// tool writes exactly `prev` today; this is what the attribute means, not a
  /// guess at what it might write.
  static func relation(_ rel: String?, includes token: String) -> Bool {
    guard let rel else { return false }
    return rel.split(whereSeparator: \.isWhitespace).contains {
      $0.lowercased() == token.lowercased()
    }
  }

  // MARK: - Builder

  private struct Builder {
    /// Reference anchor (e.g. `QUIC-TRANSPORT`) to the RFC it denotes.
    let referenceTargets: [String: DocumentID]

    /// Authored XML marks most of its citations with `<xref>`, but prose still
    /// says "RFC 3986" in the middle of a sentence, and nothing in the schema
    /// marks that up. The legacy parser has always linkified those; running the
    /// same linker here is what stops a reference reading as a link in one
    /// source format and as plain text in the other.
    ///
    /// No section numbers, deliberately: `<xref>` is how authored XML points at
    /// a section, so guessing at "Section 4" as well would be this parser
    /// inventing links the source declined to make.
    let linker: InlineLinker

    init(referenceTargets: [String: DocumentID]) {
      self.referenceTargets = referenceTargets
      self.linker = InlineLinker(
        sectionNumbers: [],
        referenceTargets: referenceTargets.mapValues { .document($0, section: nil) }
      )
    }

    /// Every reference anchor below `element`, which has to be read before the
    /// body so a cross reference in it resolves to a document.
    static func referenceTargets(in element: XMLTree.Element) -> [String: DocumentID] {
      var targets: [String: DocumentID] = [:]
      func walk(_ element: XMLTree.Element) {
        for child in element.elements {
          switch child.name {
          case "reference":
            if let anchor = child["anchor"], let id = parseEntryMetadata(child).documentID {
              targets[anchor] = id
            }
          case "referencegroup":
            if let anchor = child["anchor"], let id = DocumentID(label: anchor) {
              targets[anchor] = id
            }
            walk(child)
          case "middle", "back", "section", "references":
            walk(child)
          default:
            break
          }
        }
      }
      walk(element)
      return targets
    }

    // MARK: Header

    func parseHeader(_ rfc: XMLTree.Element) -> DocumentHeader {
      let front = rfc.first("front")
      let titleElement = front?.first("title")
      var header = DocumentHeader(title: titleElement?.normalizedText ?? "")
      header.abbreviatedTitle = titleElement?["abbrev"]

      if let number = rfc["number"].flatMap(Int.init) {
        header.id = .rfc(number)
      } else if let series = front?.all("seriesInfo").first(where: { $0["name"] == "RFC" }),
        let number = series["value"].flatMap(Int.init)
      {
        header.id = .rfc(number)
      }

      header.authors = (front?.all("author") ?? []).compactMap(Self.parseAuthor)
      if let date = front?.first("date") {
        header.date = Self.parseDate(date)
      }
      header.area = front?.first("area")?.normalizedText
      header.workingGroup = front?.first("workgroup")?.normalizedText
      header.keywords = (front?.all("keyword") ?? []).map(\.normalizedText).filter { !$0.isEmpty }
      if let abstract = front?.first("abstract") {
        header.abstract = parseBlocks(in: abstract)
      }
      header.obsoletes = parseDocumentList(rfc["obsoletes"])
      header.updates = parseDocumentList(rfc["updates"])
      header.category = rfc["category"].flatMap(categoryName)
      header.draftName = rfc["docName"]
      header.precedingDraft =
        rfc.all("link").first { RFCXMLParser.relation($0["rel"], includes: "prev") }?["href"]
        .flatMap(URL.init(string:))
      return header
    }

    private func categoryName(_ category: String) -> String {
      switch category {
      case "std": "Standards Track"
      case "bcp": "Best Current Practice"
      case "info": "Informational"
      case "exp": "Experimental"
      case "historic": "Historic"
      default: category
      }
    }

    private func parseDocumentList(_ value: String?) -> [DocumentID] {
      guard let value else { return [] }
      return value.split(whereSeparator: { $0 == "," || $0 == " " })
        .compactMap { Int($0) }
        .map { DocumentID.rfc($0) }
    }

    private static func parseAuthor(_ element: XMLTree.Element) -> Author? {
      var name = element["fullname"]
      if name == nil || name?.isEmpty == true {
        let parts = [element["initials"], element["surname"]].compactMap { $0 }.filter {
          !$0.isEmpty
        }
        name = parts.isEmpty ? nil : parts.joined(separator: " ")
      }
      if name == nil || name?.isEmpty == true {
        name = element.first("organization")?.normalizedText
      }
      guard let name, !name.isEmpty else { return nil }
      let role = element["role"] == "editor" ? "Editor" : nil
      return Author(name: name, role: role, contact: parseContact(element))
    }

    /// `<organization>` and `<address>`, when the author has either. Every element
    /// is optional in the schema, and empty ones are common in the published
    /// series (`<organization/>`), so an empty one counts as absent.
    private static func parseContact(_ element: XMLTree.Element) -> AuthorContact? {
      let address = element.first("address")
      let contact = AuthorContact(
        organization: nonEmpty(element.first("organization")),
        postal: address?.first("postal").flatMap(parsePostal),
        phone: nonEmpty(address?.first("phone")),
        facsimile: nonEmpty(address?.first("facsimile")),
        emails: (address?.all("email") ?? []).compactMap(nonEmpty),
        uri: nonEmpty(address?.first("uri"))
      )
      return contact.isEmpty ? nil : contact
    }

    /// Structured fields where the author gave them, or the author's own lines.
    /// A field given twice is given once and left empty once in the published
    /// series (RFC 9269's `<city/><city>Munich</city>`), so the first with text
    /// is the one kept.
    private static func parsePostal(_ element: XMLTree.Element) -> PostalAddress? {
      func values(_ name: String) -> [String] { element.all(name).compactMap(nonEmpty) }
      let postal = PostalAddress(
        street: values("street"),
        extendedAddress: values("extaddr"),
        postOfficeBox: values("pobox").first,
        cityArea: values("cityarea").first,
        city: values("city").first,
        region: values("region").first,
        code: values("code").first,
        sortingCode: values("sortingcode").first,
        country: values("country").first,
        postalLines: values("postalLine")
      )
      return postal.lines.isEmpty ? nil : postal
    }

    private static func nonEmpty(_ element: XMLTree.Element?) -> String? {
      guard let text = element?.normalizedText, !text.isEmpty else { return nil }
      return text
    }

    private static func parseDate(_ element: XMLTree.Element) -> PublicationDate? {
      guard let year = element["year"].flatMap(Int.init) else { return nil }
      let month = element["month"].flatMap(PublicationDate.month(from:))
      let day = element["day"].flatMap(Int.init)
      return PublicationDate(year: year, month: month, day: day)
    }

    // MARK: Sections

    /// Sections of `parent`, whose own position is `position` (nil for `<middle>`).
    func parseSections(in parent: XMLTree.Element, appendix: Bool, position: String?) -> [Section] {
      var count = 0
      return parent.elements.compactMap { child in
        switch child.name {
        case "section":
          count += 1
          let childPosition = position.map { "\($0).\(count)" } ?? "\(count)"
          return parseSection(child, appendix: appendix, position: childPosition)
        // Not valid RFCXML, but our serializer emits it for a references subsection
        // whose siblings are ordinary sections; keep it as a subsection.
        case "references":
          count += 1
          return parseReferencesSection(child)
        default:
          return nil
        }
      }
    }

    /// `position` is where the section sits among its siblings -- `2.1`, `back-1` --
    /// and names a section that has neither `anchor` nor `pn`, as in unprepped XML.
    /// An anchor keys deep links and reading positions, so it has to come out the same
    /// on every parse.
    func parseSection(_ element: XMLTree.Element, appendix: Bool, position: String) -> Section {
      let partNumber = element["pn"]
      let numbering = sectionNumber(fromPartNumber: partNumber)
      let isNumbered = element["numbered"] != "false"
      let anchor = element["anchor"] ?? partNumber ?? "unanchored-section-\(position)"
      let title = parseHeadingTitle(element, fallback: "")
      let blocks = parseBlocks(in: element)
      let subsections = parseSections(
        in: element, appendix: appendix || numbering.isAppendix, position: position)
      return Section(
        anchor: anchor,
        number: isNumbered ? numbering.number : nil,
        title: title,
        blocks: blocks,
        subsections: subsections,
        // Unnumbered back matter (Acknowledgements, Authors' Addresses) is not an appendix.
        isAppendix: isNumbered && (appendix || numbering.isAppendix)
      )
    }

    /// A heading's `<name>`, as inlines. Headings cite documents like any other
    /// prose -- "Changes from RFC 3066" -- and the schema lets `<name>` hold an
    /// `<xref>`, so reading it as flat text threw those links away.
    private func parseHeadingTitle(_ element: XMLTree.Element, fallback: String) -> [Inline] {
      guard let name = element.first("name") else { return [.text(fallback)] }
      let inlines = normalize(parseInlines(name.children))
      return inlines.isEmpty ? [.text(fallback)] : inlines
    }

    /// `section-4.2` → `4.2`; `section-appendix.a.1` → `A.1`.
    private func sectionNumber(fromPartNumber partNumber: String?) -> (
      number: String?, isAppendix: Bool
    ) {
      guard var value = partNumber, value.hasPrefix("section-") else { return (nil, false) }
      value.removeFirst("section-".count)
      if value.hasPrefix("appendix.") {
        value.removeFirst("appendix.".count)
        var parts = value.split(separator: ".").map(String.init)
        if let first = parts.first { parts[0] = first.uppercased() }
        return (parts.joined(separator: "."), true)
      }
      if value.first?.isNumber == true { return (value, false) }
      return (nil, false)
    }

    func parseReferencesSection(_ element: XMLTree.Element) -> Section {
      let partNumber = element["pn"]
      let numbering = sectionNumber(fromPartNumber: partNumber)
      let title = parseHeadingTitle(element, fallback: "References")
      var entries: [Reference] = []
      var subsections: [Section] = []
      for child in element.elements {
        switch child.name {
        case "reference":
          entries.append(parseReference(child))
        case "referencegroup":
          entries.append(parseReferenceGroup(child))
        case "references":
          subsections.append(parseReferencesSection(child))
        default:
          break
        }
      }
      let blocks: [Block] =
        entries.isEmpty
        ? [] : [.references(ReferenceList(title: title.plainText, entries: entries))]
      return Section(
        anchor: element["anchor"] ?? partNumber ?? "references",
        number: numbering.number,
        title: title,
        blocks: blocks,
        subsections: subsections
      )
    }

    func parseReference(_ element: XMLTree.Element) -> Reference {
      var reference = Self.parseEntryMetadata(element)
      if let annotation = element.first("annotation") {
        reference.annotation = normalize(parseInlines(annotation.children))
      }
      return reference
    }

    /// Everything about an entry that is not prose. Static because
    /// `referenceTargets(in:)` needs it before there is a builder to link prose
    /// with; the annotation, which is prose, is read by the instance method.
    static func parseEntryMetadata(_ element: XMLTree.Element) -> Reference {
      let front = element.first("front")
      let authors = (front?.all("author") ?? []).compactMap(Self.parseAuthor).map { author in
        author.role == nil ? author.name : "\(author.name), Ed."
      }
      let seriesInfo: [SeriesInfo] =
        (element.all("seriesInfo") + (front?.all("seriesInfo") ?? [])).compactMap {
          info -> SeriesInfo? in
          guard let name = info["name"], let value = info["value"] else { return nil }
          return SeriesInfo(name: name, value: value)
        }
      let refContent = element.first("refcontent")?.normalizedText
      return Reference(
        anchor: element["anchor"] ?? "",
        displayAnchor: Self.derivedAnchor(of: element),
        title: front?.first("title")?.normalizedText ?? "",
        authors: authors,
        date: front?.first("date").flatMap(Self.parseDate),
        seriesInfo: seriesInfo,
        url: element["target"].flatMap(URL.init(string:)),
        rawText: refContent
      )
    }

    /// The tag the prep tool resolved for this entry -- a `<displayreference>`
    /// nickname, or a number under `symRefs="false"` -- which is what every
    /// `<xref>` citing it carries as `derivedContent`.
    private static func derivedAnchor(of element: XMLTree.Element) -> String? {
      element["derivedAnchor"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private func parseReferenceGroup(_ element: XMLTree.Element) -> Reference {
      let anchor = element["anchor"] ?? ""
      let members = element.all("reference").map(parseReference)
      let memberNames = members.compactMap { $0.documentID?.displayName }
      var seriesInfo: [SeriesInfo] = []
      if let id = DocumentID(label: anchor) {
        seriesInfo.append(SeriesInfo(name: id.series.rawValue, value: String(id.number)))
      }
      return Reference(
        anchor: anchor,
        displayAnchor: Self.derivedAnchor(of: element),
        title: members.count == 1
          ? members[0].title : "\(anchor) consists of \(memberNames.joined(separator: ", "))",
        authors: members.count == 1 ? members[0].authors : [],
        date: members.count == 1 ? members[0].date : nil,
        seriesInfo: seriesInfo,
        url: element["target"].flatMap(URL.init(string:)),
        annotation: groupAnnotation(of: members)
      )
    }

    /// The schema gives `<referencegroup>` no annotation of its own; its members each
    /// may have one. A group of one is its member, annotation and all. A group of
    /// several is one entry in the panel, so every member's annotation is kept on it,
    /// each on its own line after the name of the member it belongs to -- a commit
    /// snapshot is no use unless it says which standard it pins.
    private func groupAnnotation(of members: [Reference]) -> [Inline] {
      if members.count == 1 { return members[0].annotation }
      let named = members.filter { !$0.annotation.isEmpty }.enumerated().flatMap {
        index, member -> [Inline] in
        let name = member.documentID?.displayName ?? member.displayAnchor
        return (index == 0 ? [] : [.lineBreak]) + [.text("\(name): ")] + member.annotation
      }
      return normalize(named)
    }

    // MARK: Blocks

    private static let inlineElements: Set<String> = [
      "xref", "eref", "em", "strong", "tt", "sup", "sub", "bcp14", "br", "u",
      "spanx", "cref", "iref", "contact", "relref",
    ]

    /// `<contact>` is inline in prose ("thanks to <contact fullname=…/>") and a
    /// block of its own directly in a section, where a Contributors section lists
    /// people with their addresses. The schema allows it as a block nowhere else.
    private static func isBlockContact(
      _ child: XMLTree.Element, in parent: XMLTree.Element
    ) -> Bool {
      child.name == "contact" && parent.name == "section"
    }

    /// Converts the children of a container element into blocks. Runs of loose text
    /// and inline elements (as found inside `<li>` or `<dd>`) become implicit paragraphs.
    func parseBlocks(in element: XMLTree.Element) -> [Block] {
      var blocks: [Block] = []
      var pendingInline: [XMLTree.Node] = []

      func flushInline() {
        guard !pendingInline.isEmpty else { return }
        let inlines = normalize(parseInlines(pendingInline))
        if !inlines.isEmpty {
          blocks.append(.paragraph(Paragraph(inlines)))
        }
        pendingInline = []
      }

      for node in element.children {
        switch node {
        case .text:
          pendingInline.append(node)
        case .element(let child):
          if Self.inlineElements.contains(child.name), !Self.isBlockContact(child, in: element) {
            pendingInline.append(node)
            continue
          }
          flushInline()
          if let block = parseBlock(child) {
            blocks.append(block)
          }
        }
      }
      flushInline()
      return blocks
    }

    private func parseBlock(_ element: XMLTree.Element) -> Block? {
      switch element.name {
      case "t":
        let inlines = normalize(parseInlines(element.children))
        guard !inlines.isEmpty else { return nil }
        return .paragraph(
          Paragraph(
            inlines,
            anchor: element["anchor"] ?? element["pn"],
            indent: element["indent"].flatMap(Int.init).map { max($0, 0) } ?? 0
          ))
      case "ul":
        let style: ListBlock.Style = element["empty"] == "true" ? .bare : .bullet
        return .list(
          ListBlock(
            style: style, items: parseListItems(element), isCompact: element["spacing"] == "compact"
          ))
      case "ol":
        let start = element["start"].flatMap(Int.init) ?? 1
        return .list(
          ListBlock(
            style: .numbered(format: element["type"], start: start),
            items: parseListItems(element),
            isCompact: element["spacing"] == "compact"
          ))
      case "dl":
        return .definitionList(parseDefinitionItems(element))
      case "artwork":
        return .preformatted(parseArtwork(element, kind: .artwork))
      case "sourcecode":
        return .preformatted(parseArtwork(element, kind: .sourceCode))
      case "artset":
        // Prefer the ASCII alternative; SVG needs a dedicated renderer.
        let alternatives = element.all("artwork")
        let chosen = alternatives.first { $0["type"] == "ascii-art" } ?? alternatives.first
        return chosen.map { .preformatted(parseArtwork($0, kind: .artwork)) }
      case "figure":
        let number = element["pn"].flatMap { partNumber -> Int? in
          guard partNumber.hasPrefix("figure-") else { return nil }
          return Int(partNumber.dropFirst("figure-".count))
        }
        var inner = element
        inner.children.removeAll {
          if case .element(let child) = $0 {
            return child.name == "name" || child.name == "preamble" || child.name == "postamble"
          }
          return false
        }
        var blocks: [Block] = []
        if let preamble = element.first("preamble") {
          blocks.append(.paragraph(Paragraph(normalize(parseInlines(preamble.children)))))
        }
        blocks += parseBlocks(in: inner)
        if let postamble = element.first("postamble") {
          blocks.append(.paragraph(Paragraph(normalize(parseInlines(postamble.children)))))
        }
        return .figure(
          Figure(
            title: element.first("name")?.normalizedText,
            number: number,
            blocks: blocks,
            anchor: element["anchor"]
          ))
      case "table":
        return .table(parseTable(element))
      case "blockquote":
        return .blockQuote(parseBlocks(in: element))
      case "aside":
        return .aside(parseBlocks(in: element))
      case "author", "contact":
        // Prep's "Authors' Addresses" section is made of `<author>`s, and a
        // Contributors section of `<contact>`s, which the schema gives the same
        // content. Read as the person's details, one paragraph each, rather than as
        // unknown containers, which nested an aside per level of
        // `<author><address><postal>` (#113).
        return Self.parseAuthor(element).map {
          .paragraph(Paragraph(RFCXMLParser.addressInlines($0)))
        }
      case "name", "section", "references", "toc", "boilerplate":
        return nil
      case "texttable", "list", "vspace", "preamble", "postamble", "ttcol", "c":
        // RFCXML v2 leftovers; the prepped RFC Editor output does not contain them.
        return nil
      default:
        // Unknown container: keep its content rather than dropping text, and set
        // more than one block apart as an aside. That aside is the parser's, so an
        // aside inside it is spliced in, because an aside may not hold another
        // (#113); content that is a single block, an authored aside too, is kept
        // as it is.
        let blocks = parseBlocks(in: element)
        guard blocks.count > 1 else { return blocks.first }
        return .aside(
          blocks.flatMap { block -> [Block] in
            if case .aside(let inner) = block { return inner }
            return [block]
          })
      }
    }

    private func parseListItems(_ element: XMLTree.Element) -> [ListItem] {
      element.all("li").map { item in
        ListItem(blocks: parseBlocks(in: item), anchor: item["anchor"] ?? item["pn"])
      }
    }

    private func parseDefinitionItems(_ element: XMLTree.Element) -> [DefinitionItem] {
      var items: [DefinitionItem] = []
      var pendingTerm: [Inline]?
      var pendingAnchor: String?
      for child in element.elements {
        switch child.name {
        case "dt":
          pendingTerm = normalize(parseInlines(child.children))
          pendingAnchor = child["anchor"] ?? child["pn"]
        case "dd":
          items.append(
            DefinitionItem(
              term: pendingTerm ?? [],
              definition: parseBlocks(in: child),
              anchor: pendingAnchor,
              definitionAnchor: child["anchor"] ?? child["pn"]
            ))
          pendingTerm = nil
          pendingAnchor = nil
        default:
          break
        }
      }
      if let pendingTerm {
        items.append(DefinitionItem(term: pendingTerm, definition: [], anchor: pendingAnchor))
      }
      return items
    }

    private func parseArtwork(_ element: XMLTree.Element, kind: Preformatted.Kind) -> Preformatted {
      var text = element.text
      // The RFC Editor wraps artwork in newlines for readability of the XML itself.
      while text.hasPrefix("\n") { text.removeFirst() }
      while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
      let type = element["type"].flatMap { $0.isEmpty ? nil : $0 }
      let name = element["name"].flatMap { $0.isEmpty ? nil : $0 }
      return Preformatted(
        kind: kind, text: text, type: type, name: name, anchor: element["anchor"] ?? element["pn"])
    }

    private func parseTable(_ element: XMLTree.Element) -> Table {
      func cells(of rows: [XMLTree.Element]) -> [[[Inline]]] {
        rows.map { row in
          row.elements.filter { $0.name == "th" || $0.name == "td" }
            .map { normalize(parseInlines($0.children)) }
        }
      }
      // Empty unless some row has one, as `Table.rowAnchors` documents.
      func anchors(of rows: [XMLTree.Element]) -> [String?] {
        rows.contains { $0["anchor"] != nil } ? rows.map { $0["anchor"] } : []
      }
      // RFC 7991 allows more than one `<tbody>`: RFC 9911's tables of YANG types
      // put each group of related types in its own, and reading only the first
      // dropped all but the counters. The cells and the anchors are read from the
      // same list of rows, so they cannot fall out of step.
      let headerRows = element.first("thead")?.all("tr") ?? []
      let bodyRows = element.elements
        .filter { $0.name == "tbody" || $0.name == "tfoot" }
        .flatMap { $0.all("tr") }
      let number = element["pn"].flatMap { partNumber -> Int? in
        guard partNumber.hasPrefix("table-") else { return nil }
        return Int(partNumber.dropFirst("table-".count))
      }
      return Table(
        title: element.first("name")?.normalizedText,
        number: number,
        header: cells(of: headerRows),
        rows: cells(of: bodyRows),
        anchor: element["anchor"],
        rowAnchors: anchors(of: bodyRows),
        headerRowAnchors: anchors(of: headerRows)
      )
    }

    // MARK: Inlines

    /// `linkBare` is false for the words inside an `<eref>`: they are already a
    /// link, and a cross reference nested in one is a link with two destinations.
    func parseInlines(_ nodes: [XMLTree.Node], linkBare: Bool = true) -> [Inline] {
      var result: [Inline] = []
      for node in nodes {
        switch node {
        case .text(let text):
          result += linkBare ? linker.link(text) : [.text(text)]
        case .element(let element):
          result += parseInline(element, linkBare: linkBare)
        }
      }
      return result
    }

    private func parseInline(_ element: XMLTree.Element, linkBare: Bool) -> [Inline] {
      switch element.name {
      case "xref", "relref":
        return [.crossReference(parseCrossReference(element))]
      case "eref":
        let inner = parseInlines(element.children, linkBare: false)
        guard let target = element["target"], let url = URL(string: target) else { return inner }
        // Links into the RFC series are document references, whichever site they point at.
        if let link = RFCLink(url: url), link.id.series == .rfc {
          let text = inner.isEmpty ? nil : inner.plainText.collapsingWhitespace()
          // This is the shape `RFCXMLSerializer` writes a document mention in
          // when the document has no bibliography entry, which is most of the
          // legacy corpus -- and the mention it wrote is the series' own
          // spelling, so it is a label to compose rather than words to keep.
          let authored = text.flatMap { CrossReference.isCanonicalTag($0, for: link.id) ? nil : $0 }
          return [
            .crossReference(
              CrossReference(target: .document(link.id, section: link.section), text: authored))
          ]
        }
        return [.link(url, inner.isEmpty ? [.text(target)] : inner)]
      case "em":
        return [.emphasis(parseInlines(element.children, linkBare: linkBare))]
      case "strong", "bcp14":
        return [.strong(parseInlines(element.children, linkBare: linkBare))]
      case "tt":
        return [.code(element.text)]
      case "sup":
        return [.superscript(element.text)]
      case "sub":
        return [.subscript(element.text)]
      case "br":
        return [.lineBreak]
      case "u":
        let format = element["format"]
        return UnicodeNotation.expand(element.text, format: format, ascii: element["ascii"])
      case "spanx":
        switch element["style"] {
        case "verb": return [.code(element.text)]
        case "strong": return [.strong(parseInlines(element.children, linkBare: linkBare))]
        default: return [.emphasis(parseInlines(element.children, linkBare: linkBare))]
        }
      case "contact":
        return [.text(element["fullname"] ?? element.text)]
      case "cref", "iref":
        return []
      // Both are block elements that v3 also allows inline. Whatever they hold
      // is set as the author typed it, so nothing in them is linkified.
      case "sourcecode", "artwork":
        return parseInlines(element.children, linkBare: false)
      default:
        return parseInlines(element.children, linkBare: linkBare)
      }
    }

    private func parseCrossReference(_ element: XMLTree.Element) -> CrossReference {
      let targetAnchor = element["target"] ?? ""
      let section = element["section"]
      let innerText = element.normalizedText
      let derived = element["derivedContent"].flatMap { $0.isEmpty ? nil : $0 }
      let format = element["format"] ?? "default"

      let sectionFormat =
        CrossReference.SectionFormat(rawValue: element["sectionFormat"] ?? "") ?? .of

      if let id = referenceTargets[targetAnchor] {
        let target = CrossReference.Target.document(id, section: section)
        // Words the source put inside the link stand in for the label -- unless
        // they are the series spelling its own name, which is the label we
        // would have composed anyway.
        if !innerText.isEmpty, !CrossReference.isCanonicalTag(innerText, for: id) {
          return CrossReference(target: target, text: innerText, sectionFormat: sectionFormat)
        }
        // "RFC9110" is the canonical number; anything else is a tag the author
        // chose ("QUIC-TRANSPORT") and is the name the document uses
        // throughout, so it survives verbatim, brackets and all.
        let raw = derived ?? targetAnchor
        if !CrossReference.isCanonicalTag(raw, for: id) {
          return CrossReference(target: target, text: "[\(raw)]", sectionFormat: sectionFormat)
        }
        // `counter` and `title` ask for something the target cannot supply --
        // a number, a heading -- so the tooling's own rendering is the label.
        if format == "counter" || format == "title", let derived {
          return CrossReference(target: target, text: derived, sectionFormat: sectionFormat)
        }
        return CrossReference(target: target, sectionFormat: sectionFormat)
      }

      let text = innerText.isEmpty ? derived : innerText
      return CrossReference(target: .anchor(targetAnchor), text: text)
    }

    /// Collapses whitespace the way HTML rendering would: runs become one space,
    /// and the paragraph is trimmed at both ends. Code and verbatim spans are untouched.
    func normalize(_ inlines: [Inline]) -> [Inline] {
      var result: [Inline] = []
      for inline in inlines {
        switch inline {
        case .text(let text):
          let hadLeading = text.first?.isWhitespace == true
          let hadTrailing = text.last?.isWhitespace == true
          var collapsed = text.collapsingWhitespace()
          if collapsed.isEmpty {
            collapsed = (hadLeading || hadTrailing) ? " " : ""
          } else {
            if hadLeading { collapsed = " " + collapsed }
            if hadTrailing { collapsed += " " }
          }
          if collapsed.isEmpty { continue }
          if collapsed == " ", case .text(let previous)? = result.last, previous.hasSuffix(" ") {
            continue
          }
          if case .text(let previous)? = result.last {
            // An element that yields nothing (an empty `<u>`, a `<cref>`) leaves
            // the spaces on either side of it meeting here.
            if previous.hasSuffix(" "), collapsed.hasPrefix(" ") {
              collapsed.removeFirst()
            }
            result[result.count - 1] = .text(previous + collapsed)
          } else {
            result.append(.text(collapsed))
          }
        case .emphasis(let inner):
          result.append(.emphasis(normalize(inner)))
        case .strong(let inner):
          result.append(.strong(normalize(inner)))
        case .link(let url, let inner):
          result.append(.link(url, normalize(inner)))
        default:
          result.append(inline)
        }
      }
      // Trim the paragraph ends.
      if case .text(let first)? = result.first {
        let trimmed = String(first.drop(while: \.isWhitespace))
        if trimmed.isEmpty { result.removeFirst() } else { result[0] = .text(trimmed) }
      }
      if case .text(let last)? = result.last {
        var trimmed = last
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        if trimmed.isEmpty {
          result.removeLast()
        } else {
          result[result.count - 1] = .text(trimmed)
        }
      }
      return result
    }
  }
}

extension RFCXMLParser {
  /// An author as the RFC Editor's rendering of an Authors' Addresses entry
  /// sets it, one detail per line, with the email and web addresses as links.
  static func addressInlines(_ author: Author) -> [Inline] {
    var lines: [[Inline]] = [
      [.text(author.role == "Editor" ? "\(author.name) (editor)" : author.name)]
    ]
    if let contact = author.contact {
      // An organization's own entry names it already: `parseAuthor` falls back to
      // the organization for a name when there is no person's.
      if let organization = contact.organization, organization != author.name {
        lines.append([.text(organization)])
      }
      for line in contact.postal?.lines ?? [] { lines.append([.text(line)]) }
      if let phone = contact.phone { lines.append([.text("Phone: \(phone)")]) }
      if let facsimile = contact.facsimile { lines.append([.text("Fax: \(facsimile)")]) }
      for email in contact.emails {
        lines.append([.text("Email: "), link(mailto(email), email)])
      }
      // A URI without a scheme (RFC 9517's `ddialliance.org`) would be a relative
      // link, to nowhere; it and one `URL` cannot read are shown as written.
      if let uri = contact.uri {
        lines.append([
          .text("URI: "), link(URL(string: uri).flatMap { $0.scheme == nil ? nil : $0 }, uri),
        ])
      }
    }
    return Array(lines.joined(separator: [Inline.lineBreak]))
  }

  private static func link(_ url: URL?, _ text: String) -> Inline {
    url.map { .link($0, [.text(text)]) } ?? .text(text)
  }

  /// A `mailto:` URL for an address as written. The address is the URL's path,
  /// so the characters a path may not hold are escaped: an address with a `?`,
  /// `#` or `%` in it would otherwise begin a query or a fragment, or be read as
  /// an escape, and link somewhere else.
  static func mailto(_ address: String) -> URL? {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = address
    return components.url
  }
}
