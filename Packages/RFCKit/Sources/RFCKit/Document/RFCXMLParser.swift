import Foundation

/// Parses RFCXML v3 (RFC 7991) as published by the RFC Editor into an `RFCDocument`.
///
/// The RFC Editor's "prepped" XML carries `pn` (part number) attributes and
/// `derivedContent` on cross references, which this parser leans on for stable
/// anchors and display text instead of re-implementing the numbering rules.
public struct RFCXMLParser: Sendable {
  public enum ParseError: Error, Sendable {
    case notAnRFC(rootElement: String)
    case malformed(String)
  }

  public init() {}

  public static func parse(_ data: Data) throws -> RFCDocument {
    try RFCXMLParser().parse(data)
  }

  public func parse(_ data: Data) throws -> RFCDocument {
    let root: XMLElement
    do {
      root = try XMLTreeBuilder.parse(data)
    } catch let error as XMLTreeError {
      switch error {
      case .malformed(let line, let column, let message):
        throw ParseError.malformed("line \(line), column \(column): \(message)")
      case .empty:
        throw ParseError.malformed("empty document")
      }
    }
    guard root.name == "rfc" else { throw ParseError.notAnRFC(rootElement: root.name) }

    // References first, so cross references in the body resolve to RFC numbers.
    let back = root.first("back")
    let builder = Builder(referenceTargets: back.map(Builder.referenceTargets(in:)) ?? [:])

    let header = builder.parseHeader(root)
    var sections: [Section] = []
    if let middle = root.first("middle") {
      sections += builder.parseSections(in: middle, appendix: false)
    }
    if let back {
      for element in back.elements {
        switch element.name {
        case "references":
          sections.append(builder.parseReferencesSection(element))
        case "section":
          sections.append(builder.parseSection(element, appendix: true))
        default:
          break
        }
      }
    }
    return RFCDocument(header: header, sections: sections, source: .xml)
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
    static func referenceTargets(in element: XMLElement) -> [String: DocumentID] {
      var targets: [String: DocumentID] = [:]
      func walk(_ element: XMLElement) {
        for child in element.elements {
          switch child.name {
          case "reference":
            if let anchor = child["anchor"], let id = parseReference(child).documentID {
              targets[anchor] = id
            }
          case "referencegroup":
            if let anchor = child["anchor"], let id = DocumentID(label: anchor) {
              targets[anchor] = id
            }
            walk(child)
          case "references":
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

    func parseHeader(_ rfc: XMLElement) -> DocumentHeader {
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

    private static func parseAuthor(_ element: XMLElement) -> Author? {
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
      return Author(name: name, role: role)
    }

    private static func parseDate(_ element: XMLElement) -> PublicationDate? {
      guard let year = element["year"].flatMap(Int.init) else { return nil }
      let month = element["month"].flatMap(PublicationDate.month(from:))
      let day = element["day"].flatMap(Int.init)
      return PublicationDate(year: year, month: month, day: day)
    }

    // MARK: Sections

    func parseSections(in parent: XMLElement, appendix: Bool) -> [Section] {
      parent.elements.compactMap { child in
        switch child.name {
        case "section": parseSection(child, appendix: appendix)
        // Not valid RFCXML, but our serializer emits it for a references subsection
        // whose siblings are ordinary sections; keep it as a subsection.
        case "references": parseReferencesSection(child)
        default: nil
        }
      }
    }

    func parseSection(_ element: XMLElement, appendix: Bool) -> Section {
      let partNumber = element["pn"]
      let numbering = sectionNumber(fromPartNumber: partNumber)
      let isNumbered = element["numbered"] != "false"
      let anchor = element["anchor"] ?? partNumber ?? UUID().uuidString
      let title = parseHeadingTitle(element, fallback: "")
      let blocks = parseBlocks(in: element)
      let subsections = parseSections(in: element, appendix: appendix || numbering.isAppendix)
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
    private func parseHeadingTitle(_ element: XMLElement, fallback: String) -> [Inline] {
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

    func parseReferencesSection(_ element: XMLElement) -> Section {
      let partNumber = element["pn"]
      let numbering = sectionNumber(fromPartNumber: partNumber)
      let title = parseHeadingTitle(element, fallback: "References")
      var entries: [Reference] = []
      var subsections: [Section] = []
      for child in element.elements {
        switch child.name {
        case "reference":
          entries.append(Self.parseReference(child))
        case "referencegroup":
          entries.append(Self.parseReferenceGroup(child))
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

    static func parseReference(_ element: XMLElement) -> Reference {
      let front = element.first("front")
      let authors = (front?.all("author") ?? []).compactMap(Self.parseAuthor).map { author in
        author.role == nil ? author.name : "\(author.name), Ed."
      }
      let seriesInfo: [(name: String, value: String)] =
        (element.all("seriesInfo") + (front?.all("seriesInfo") ?? [])).compactMap {
          info -> (name: String, value: String)? in
          guard let name = info["name"], let value = info["value"] else { return nil }
          return (name: name, value: value)
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
    private static func derivedAnchor(of element: XMLElement) -> String? {
      element["derivedAnchor"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parseReferenceGroup(_ element: XMLElement) -> Reference {
      let anchor = element["anchor"] ?? ""
      let members = element.all("reference").map(parseReference)
      let memberNames = members.compactMap { $0.documentID?.displayName }
      var seriesInfo: [(name: String, value: String)] = []
      if let id = DocumentID(label: anchor) {
        seriesInfo.append((name: id.series.rawValue, value: String(id.number)))
      }
      return Reference(
        anchor: anchor,
        displayAnchor: Self.derivedAnchor(of: element),
        title: members.count == 1
          ? members[0].title : "\(anchor) consists of \(memberNames.joined(separator: ", "))",
        authors: members.count == 1 ? members[0].authors : [],
        date: members.count == 1 ? members[0].date : nil,
        seriesInfo: seriesInfo,
        url: element["target"].flatMap(URL.init(string:))
      )
    }

    // MARK: Blocks

    private static let inlineElements: Set<String> = [
      "xref", "eref", "em", "strong", "tt", "sup", "sub", "bcp14", "br", "u",
      "spanx", "cref", "iref", "contact", "relref",
    ]

    /// Converts the children of a container element into blocks. Runs of loose text
    /// and inline elements (as found inside `<li>` or `<dd>`) become implicit paragraphs.
    func parseBlocks(in element: XMLElement) -> [Block] {
      var blocks: [Block] = []
      var pendingInline: [XMLNode] = []

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
          if Self.inlineElements.contains(child.name) {
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

    private func parseBlock(_ element: XMLElement) -> Block? {
      switch element.name {
      case "t":
        let inlines = normalize(parseInlines(element.children))
        guard !inlines.isEmpty else { return nil }
        return .paragraph(Paragraph(inlines, anchor: element["anchor"] ?? element["pn"]))
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
      case "name", "section", "references", "toc", "boilerplate":
        return nil
      case "texttable", "list", "vspace", "preamble", "postamble", "ttcol", "c":
        // RFCXML v2 leftovers; the prepped RFC Editor output does not contain them.
        return nil
      default:
        // Unknown container: keep its content rather than dropping text.
        let blocks = parseBlocks(in: element)
        return blocks.count == 1 ? blocks[0] : (blocks.isEmpty ? nil : .aside(blocks))
      }
    }

    private func parseListItems(_ element: XMLElement) -> [ListItem] {
      element.all("li").map { item in
        ListItem(blocks: parseBlocks(in: item), anchor: item["anchor"] ?? item["pn"])
      }
    }

    private func parseDefinitionItems(_ element: XMLElement) -> [DefinitionItem] {
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
              anchor: pendingAnchor
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

    private func parseArtwork(_ element: XMLElement, kind: Preformatted.Kind) -> Preformatted {
      var text = element.text
      // The RFC Editor wraps artwork in newlines for readability of the XML itself.
      while text.hasPrefix("\n") { text.removeFirst() }
      while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
      let type = element["type"].flatMap { $0.isEmpty ? nil : $0 }
      let name = element["name"].flatMap { $0.isEmpty ? nil : $0 }
      return Preformatted(
        kind: kind, text: text, type: type, name: name, anchor: element["anchor"] ?? element["pn"])
    }

    private func parseTable(_ element: XMLElement) -> Table {
      func rows(in container: XMLElement?) -> [[[Inline]]] {
        (container?.all("tr") ?? []).map { row in
          row.elements.filter { $0.name == "th" || $0.name == "td" }
            .map { normalize(parseInlines($0.children)) }
        }
      }
      let number = element["pn"].flatMap { partNumber -> Int? in
        guard partNumber.hasPrefix("table-") else { return nil }
        return Int(partNumber.dropFirst("table-".count))
      }
      return Table(
        title: element.first("name")?.normalizedText,
        number: number,
        header: rows(in: element.first("thead")),
        rows: rows(in: element.first("tbody")) + rows(in: element.first("tfoot")),
        anchor: element["anchor"]
      )
    }

    // MARK: Inlines

    /// `linkBare` is false for the words inside an `<eref>`: they are already a
    /// link, and a cross reference nested in one is a link with two destinations.
    func parseInlines(_ nodes: [XMLNode], linkBare: Bool = true) -> [Inline] {
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

    private func parseInline(_ element: XMLElement, linkBare: Bool) -> [Inline] {
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

    private func parseCrossReference(_ element: XMLElement) -> CrossReference {
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
