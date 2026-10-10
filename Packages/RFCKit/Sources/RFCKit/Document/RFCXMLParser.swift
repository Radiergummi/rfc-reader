import Foundation

/// Parses RFCXML v3 (RFC 7991) as published by the RFC Editor into an `RFCDocument`.
///
/// The RFC Editor's "prepped" XML carries `pn` (part number) attributes and
/// `derivedContent` on cross references, which this parser leans on for stable
/// anchors and display text instead of re-implementing the numbering rules.
public enum RFCXMLParser {
  public enum ParseError: Error, LocalizedError, Sendable, Equatable {
    case notAnRFC(rootElement: String)
    case malformed(XMLSyntaxError)

    /// The syntax error's own words, which the app shows (#320).
    public var errorDescription: String? {
      switch self {
      case .notAnRFC(let root): "Not an RFC: the document's root element is <\(root)>."
      case .malformed(let error): error.errorDescription
      }
    }
  }

  public static func parse(_ data: Data) throws(ParseError) -> RFCDocument {
    let root: XMLTree.Element
    do {
      root = try XMLTree.parse(data)
    } catch {
      throw .malformed(error)
    }
    guard root.name == "rfc" else { throw .notAnRFC(rootElement: root.name) }

    // References first, so cross references in the body resolve to RFC numbers.
    // Every list, not only the back's: XML from elsewhere, and legacy conversions
    // made before #315 lifted every bibliography into `<back>`, can hold one in
    // `<middle>` or in a chapter, and a citation into it is as much a link as one
    // into the back.
    let back = root.first("back")
    let builder = Builder(referencesIn: root)

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
          sections.append(builder.parseReferencesSection(element, position: "back-\(count)"))
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
    document.definedTerms = DefinedTerms.defined(
      in: document, indexed: builder.primaryIndexTerms(in: root))
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

  /// A citable reference anchor's document, and the anchor of the bibliography
  /// entry a citation of it resolves to.
  private struct CitedEntry {
    let id: DocumentID
    /// The anchor itself, except for a `<referencegroup>`'s member, whose entry in
    /// the list is the group's (#184).
    let entry: String
  }

  // MARK: - Builder

  /// The terms primary index entries define; see `Builder.primaryIndexTerms(in:)`.
  static func primaryIndexTerms(in root: XMLTree.Element) -> [IndexedTerm] {
    Builder(referencesIn: root).primaryIndexTerms(in: root)
  }

  /// Every `<xref>` below `root`, in document order, resolved the way the parser
  /// resolves it. Resolving one is a pure function of the element and the reference
  /// lists, so the rules are tested over hand-written trees where no committed
  /// fixture has the shape.
  static func crossReferences(in root: XMLTree.Element) -> [CrossReference] {
    let builder = Builder(referencesIn: root)
    var result: [CrossReference] = []
    func walk(_ element: XMLTree.Element) {
      for child in element.elements {
        if child.name == "xref" {
          result.append(builder.parseCrossReference(child))
        } else {
          walk(child)
        }
      }
    }
    walk(root)
    return result
  }

  private struct Builder {
    /// Reference anchor (e.g. `QUIC-TRANSPORT`) to the RFC it denotes and the entry
    /// a citation of it resolves to.
    let referenceTargets: [String: CitedEntry]

    /// The anchor of every entry in a references section, in a series or not, to the
    /// anchor of the bibliography entry it is listed under: itself, or its
    /// `<referencegroup>`'s. A citation of any of them is bracketed, "[66]", the way
    /// the RFC Editor renders it.
    let referenceEntries: [String: String]

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

    /// Whether a section named in the prose before a citation is the citation's
    /// (`foldingSection`): in a document the RFC Editor prepped, which carries its
    /// `prepTime`. Not in one corpus-build converted from plain text, whose citations
    /// the legacy parser has already read, so the XML reads back as the model it was
    /// written from.
    let foldsSectionsInProse: Bool

    /// The RFC being parsed, whose page at the RFC Editor shows what an artwork
    /// published only as SVG draws.
    let documentID: DocumentID?

    /// The RFC the document is, from its `number` or its front's `<seriesInfo>`; nil for
    /// a draft.
    static func documentID(of rfc: XMLTree.Element) -> DocumentID? {
      if let number = rfc["number"].flatMap(Int.init) { return .rfc(number) }
      let series = rfc.first("front")?.all("seriesInfo").first { $0["name"] == "RFC" }
      return series?["value"].flatMap(Int.init).map(DocumentID.rfc)
    }

    init(referencesIn root: XMLTree.Element) {
      self.documentID = Self.documentID(of: root)
      let (referenceTargets, referenceEntries) = Self.references(in: root)
      self.referenceTargets = referenceTargets
      self.referenceEntries = referenceEntries
      self.foldsSectionsInProse = root["prepTime"] != nil
      self.linker = InlineLinker(
        sectionNumbers: [],
        referenceTargets: referenceTargets.mapValues {
          .document($0.id, section: nil, entry: $0.entry)
        }
      )
    }

    /// Every reference anchor below `element` with the entry it is listed under, and
    /// the ones among them that denote a document, which have to be read before the
    /// body so a cross reference in it resolves to a document.
    static func references(
      in element: XMLTree.Element
    ) -> (targets: [String: CitedEntry], entries: [String: String]) {
      var targets: [String: CitedEntry] = [:]
      var entries: [String: String] = [:]
      func walk(_ element: XMLTree.Element, group: String?) {
        for child in element.elements {
          switch child.name {
          case "reference":
            guard let anchor = child["anchor"] else { break }
            entries[anchor] = group ?? anchor
            if let id = parseEntryMetadata(child).documentID {
              targets[anchor] = CitedEntry(id: id, entry: group ?? anchor)
            }
          case "referencegroup":
            let anchor = child["anchor"]
            if let anchor {
              entries[anchor] = anchor
              if let id = DocumentID(label: anchor) {
                targets[anchor] = CitedEntry(id: id, entry: anchor)
              }
            }
            walk(child, group: anchor)
          case "middle", "back", "section", "references":
            walk(child, group: group)
          default:
            break
          }
        }
      }
      walk(element, group: nil)
      return (targets, entries)
    }

    // MARK: Header

    func parseHeader(_ rfc: XMLTree.Element) -> DocumentHeader {
      let front = rfc.first("front")
      let titleElement = front?.first("title")
      var header = DocumentHeader(title: titleElement?.normalizedText ?? "")
      header.abbreviatedTitle = titleElement?["abbrev"]

      header.id = Self.documentID(of: rfc)

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
      header.category = rfc["category"].flatMap(DocumentHeader.Category.init(parsing:))
      header.draftName = rfc["docName"]
      header.precedingDraft =
        rfc.all("link").first { RFCXMLParser.relation($0["rel"], includes: "prev") }?["href"]
        .flatMap(URL.init(string:))
      return header
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
      let role = element["role"].flatMap(Author.Role.init(parsing:))
      let surname = element["surname"].map { $0.trimmingCharacters(in: .whitespaces) }
      return Author(
        name: name, role: role, contact: parseContact(element),
        statedSurname: surname?.isEmpty == false ? surname : nil)
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
      func childPosition(_ count: Int) -> String {
        position.map { "\($0).\(count)" } ?? "\(count)"
      }
      var count = 0
      return parent.elements.compactMap { child in
        switch child.name {
        case "section":
          count += 1
          return parseSection(child, appendix: appendix, position: childPosition(count))
        // Not valid RFCXML, but legacy conversions made before #315 have it, a
        // references subsection whose siblings are ordinary sections; keep it as a
        // subsection.
        case "references":
          count += 1
          return parseReferencesSection(child, position: childPosition(count))
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
      // Prep's index is one block; a section of any other shape reads as its blocks.
      let blocks = parseIndex(element).map { [Block.index($0)] } ?? parseBlocks(in: element)
      // A `pn` says which it is. Where there is none, as in unprepped XML, a section is
      // an appendix by where it sits: in `<back>`, or in an appendix. Prepped RFCXML
      // gives every section in `<back>` an appendix's `pn`, but a legacy conversion
      // writes a numbered section that follows the references there too, because the
      // schema puts every `<references>` ahead of the back's sections (#315). Its `pn`
      // is a section's, and it is announced as one: `11.`, not `Appendix 11.` (#683).
      let isAppendixByPlace = numbering.number == nil ? appendix : numbering.isAppendix
      let subsections = parseSections(in: element, appendix: isAppendixByPlace, position: position)
      return Section(
        anchor: anchor,
        number: isNumbered ? numbering.number : nil,
        title: title,
        blocks: blocks,
        subsections: subsections,
        // Unnumbered back matter (Acknowledgements, Authors' Addresses) is not an appendix.
        isAppendix: isNumbered && isAppendixByPlace
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
      switch partNumber.flatMap(PartNumber.init) {
      case .section(let number): (number, false)
      case .appendix(let number): (number, true)
      case .figure, .table, nil: (nil, false)
      }
    }

    // MARK: Index

    /// The index prep generates from a document's `<iref>`s, where `section` is one:
    /// a `<t>` anchored `rfc.index.index`, which prep writes and nothing else does,
    /// then a `<ul>` of letter groups. Nil for any other section, and for an index of
    /// any other shape, which reads as the generic blocks it is made of rather than as
    /// half an index.
    func parseIndex(_ section: XMLTree.Element) -> IndexBlock? {
      let body = section.elements.filter { $0.name != "name" }
      guard body.count == 2, body[0].name == "t", body[0]["anchor"] == IndexBlock.anchor,
        body[1].name == "ul"
      else { return nil }
      var groups: [IndexBlock.Group] = []
      for item in body[1].elements {
        guard let group = parseIndexGroup(item) else { return nil }
        groups.append(group)
      }
      return IndexBlock(groups: groups)
    }

    /// A letter group: an anchored empty `<t>`, whose anchor names the letter by its
    /// code point, and a list holding one `<dl>`.
    private func parseIndexGroup(_ item: XMLTree.Element) -> IndexBlock.Group? {
      let parts = item.elements
      guard item.name == "li", parts.count == 2, parts[0].name == "t", parts[1].name == "ul",
        let anchor = parts[0]["anchor"], IndexBlock.label(ofGroupAnchor: anchor) != nil
      else { return nil }
      let items = parts[1].elements
      guard items.count == 1, let onlyItem = items.first, onlyItem.name == "li" else { return nil }
      let lists = onlyItem.elements
      guard lists.count == 1, let list = lists.first, list.name == "dl",
        let read = parseIndexEntries(list), read.parentLocators.isEmpty
      else { return nil }
      return IndexBlock.Group(anchor: anchor, entries: read.entries)
    }

    /// The entries of an index `<dl>`, a `<dt>` and a `<dd>` each, and the locators of
    /// those without a term. Prep writes an item's own locators so when it has
    /// subitems too (RFC 9051, 9499), and they are the enclosing entry's. An entry
    /// without a term that holds a list holds the subentries of the entry before it
    /// (RFC 9110's `Grammar`).
    private func parseIndexEntries(_ list: XMLTree.Element) -> (
      entries: [IndexBlock.Entry], parentLocators: [IndexBlock.Locator]
    )? {
      let parts = list.elements
      guard parts.count.isMultiple(of: 2) else { return nil }
      var entries: [IndexBlock.Entry] = []
      var parentLocators: [IndexBlock.Locator] = []
      for start in stride(from: 0, to: parts.count, by: 2) {
        let term = parts[start]
        let description = parts[start + 1]
        // A `<dd>` holds its locators' paragraphs and at most one list of subentries;
        // a second would be half an index.
        let contents = description.elements
        let nestedLists = contents.filter { $0.name == "dl" }
        guard term.name == "dt", description.name == "dd", nestedLists.count <= 1,
          let locators = parseIndexLocators(contents.filter { $0.name != "dl" })
        else { return nil }
        // A term names something: an RFC number in it is part of the name, not a
        // citation (RFC 9051 indexes fetch items named after a format).
        let words = normalize(parseInlines(term.children, linkBare: false))
        if words.isEmpty {
          parentLocators += locators
        } else {
          entries.append(IndexBlock.Entry(term: words, locators: locators))
        }
        if let nested = nestedLists.first {
          guard !entries.isEmpty, let read = parseIndexEntries(nested) else { return nil }
          entries[entries.count - 1].locators += read.parentLocators
          entries[entries.count - 1].subentries += read.entries
        }
      }
      return (entries, parentLocators)
    }

    /// The locators in the paragraphs of an index `<dd>`: each `<xref>` in a `<t>`,
    /// primary where prep set it in `<strong>`, with nothing but separators between
    /// them, which prep writes as a semicolon. Nil for anything else, such as words.
    private func parseIndexLocators(_ paragraphs: [XMLTree.Element]) -> [IndexBlock.Locator]? {
      var locators: [IndexBlock.Locator] = []
      for part in paragraphs {
        guard part.name == "t", Self.holdsOnlySeparators(part) else { return nil }
        for element in part.elements {
          switch element.name {
          case "xref":
            locators.append(
              IndexBlock.Locator(reference: parseCrossReference(element), isPrimary: false))
          case "strong":
            let emphases = element.elements.filter { $0.name == "em" }
            let references = element.elements.flatMap { $0.name == "em" ? $0.elements : [$0] }
            guard !references.isEmpty, references.allSatisfy({ $0.name == "xref" }),
              ([element] + emphases).allSatisfy(Self.holdsOnlySeparators)
            else {
              return nil
            }
            locators += references.map {
              IndexBlock.Locator(reference: parseCrossReference($0), isPrimary: true)
            }
          default:
            return nil
          }
        }
      }
      return locators
    }

    /// Whether the text directly in `paragraph`, or in the emphasis around a primary
    /// locator, is only what separates locators: a semicolon or a comma, and white
    /// space.
    private static func holdsOnlySeparators(_ paragraph: XMLTree.Element) -> Bool {
      paragraph.children.allSatisfy { node in
        guard case .text(let text) = node else { return true }
        return text.allSatisfy { $0.isWhitespace || $0 == ";" || $0 == "," }
      }
    }

    /// `position` names an anchorless list, as it does a section in `parseSection`.
    func parseReferencesSection(_ element: XMLTree.Element, position: String) -> Section {
      let partNumber = element["pn"]
      let numbering = sectionNumber(fromPartNumber: partNumber)
      let title = parseHeadingTitle(element, fallback: "References")
      var entries: [Reference] = []
      var subsections: [Section] = []
      var count = 0
      for child in element.elements {
        switch child.name {
        case "reference":
          entries.append(parseReference(child))
        case "referencegroup":
          entries.append(parseReferenceGroup(child))
        case "references":
          count += 1
          subsections.append(parseReferencesSection(child, position: "\(position).\(count)"))
        default:
          break
        }
      }
      let blocks: [Block] =
        entries.isEmpty
        ? [] : [.references(ReferenceList(title: title.plainText, entries: entries))]
      return Section(
        anchor: element["anchor"] ?? partNumber ?? "unanchored-references-\(position)",
        number: numbering.number,
        title: title,
        blocks: blocks,
        subsections: subsections,
        // An appendix that is a bibliography, `Appendix C -- References`, says so in its
        // `pn` like any other appendix.
        isAppendix: numbering.isAppendix
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
    /// `references(in:)` needs it before there is a builder to link prose
    /// with; the annotation, which is prose, is read by the instance method.
    static func parseEntryMetadata(_ element: XMLTree.Element) -> Reference {
      let front = element.first("front")
      // No contact: an entry's `<author>` may carry an address, and the bibliography
      // has no use for one.
      let authors = (front?.all("author") ?? []).compactMap(Self.parseAuthor).map { author in
        Author(name: author.name, role: author.role, statedSurname: author.statedSurname)
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
        seriesInfo.append(SeriesInfo(id))
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
        annotation: groupAnnotation(of: members),
        members: members.compactMap(\.documentID)
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

    /// The terms primary index entries define (#176): `<iref primary="true">` without a
    /// subitem, each with the anchors it may be defined at, innermost first: the
    /// element it sits in, then each element around it. `DefinedTerms` takes the first
    /// of them the built model holds, and what holds it as the definition (#455), so
    /// which anchors the model keeps is said once, by the model. With a subitem an
    /// entry files a name under a group (`Grammar` / `ALPHA`, `Fields` /
    /// `Content-Type`), an index heading rather than a term. One in an inline element
    /// is the block's around it, and one in a `<dt>` is defined by the `<dd>` after
    /// it, whose anchors follow the term's.
    func primaryIndexTerms(in root: XMLTree.Element) -> [IndexedTerm] {
      var terms: [IndexedTerm] = []
      func record(
        entriesIn element: XMLTree.Element, anchors: [String], definition: () -> [Block]
      ) {
        let items = Self.indexEntries(in: element).compactMap { entry -> String? in
          guard entry["primary"] == "true", entry["subitem"] == nil else { return nil }
          return entry["item"]
        }
        guard !items.isEmpty else { return }
        // Built once, however many entries the block holds.
        let definition = definition()
        terms += items.map { IndexedTerm(term: $0, anchors: anchors, definition: definition) }
      }
      func visit(_ element: XMLTree.Element, around: [String]) {
        let anchors = Self.anchors(of: element) + around
        record(entriesIn: element, anchors: anchors) {
          ["li", "dd", "td", "th"].contains(element.name)
            ? parseBlocks(in: element) : parseBlock(element).map { [$0] } ?? []
        }
        let children = element.elements.filter { !Self.inlineElements.contains($0.name) }
        for (position, child) in children.enumerated() {
          guard child.name == "dt" else {
            visit(child, around: anchors)
            continue
          }
          let next = children.dropFirst(position + 1).first
          let description = next?.name == "dd" ? next : nil
          record(
            entriesIn: child,
            anchors: Self.anchors(of: child) + (description.map(Self.anchors(of:)) ?? []) + anchors
          ) { description.map(parseBlocks(in:)) ?? [] }
        }
      }
      visit(root, around: [])
      return terms
    }

    /// The index entries an element holds itself, directly or in its inline elements,
    /// not in the blocks nested in it.
    private static func indexEntries(in element: XMLTree.Element) -> [XMLTree.Element] {
      element.elements.flatMap { child -> [XMLTree.Element] in
        if child.name == "iref" { return [child] }
        return inlineElements.contains(child.name) ? indexEntries(in: child) : []
      }
    }

    /// The anchors an element may be known by: the author's, then the part number.
    private static func anchors(of element: XMLTree.Element) -> [String] {
      [element["anchor"], element["pn"]].compactMap { $0 }
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
            style: .numbered(ListNumbering(type: element["type"], start: start)),
            items: parseListItems(element),
            isCompact: element["spacing"] == "compact"
          ))
      case "dl":
        return .definitionList(
          DefinitionList(
            parseDefinitionItems(element),
            isCompact: element["spacing"] == "compact",
            hangsTerms: element["newline"] == "false"
          ))
      case "artwork":
        return .preformatted(parseArtwork(element, kind: .artwork))
      case "sourcecode":
        return .preformatted(parseArtwork(element, kind: .sourceCode))
      case "artset":
        // Prefer the ASCII alternative; SVG needs a dedicated renderer, and an artset
        // without one shows the gap, as an SVG artwork alone does.
        let alternatives = element.all("artwork")
        let chosen = alternatives.first { $0["type"] == "ascii-art" } ?? alternatives.first
        return chosen.map { .preformatted(parseArtwork($0, kind: .artwork)) }
      case "figure":
        let number: Int? =
          if case .figure(let number)? = element["pn"].flatMap(PartNumber.init) { number } else {
            nil
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
      // An SVG drawing's text nodes, run together, are neither the drawing nor text
      // to read; the block says where the drawing is, as xml2rfc's text rendering
      // does, and keeps its type for a renderer to come (#768). Source code typed
      // `svg` is markup to read, and stays.
      let isDrawing = kind == .artwork && element["type"]?.lowercased() == "svg"
      var text = isDrawing ? svgOnlyNote : element.text
      // The RFC Editor wraps artwork in newlines for readability of the XML itself.
      while text.hasPrefix("\n") { text.removeFirst() }
      while text.hasSuffix("\n") || text.hasSuffix(" ") { text.removeLast() }
      let type = element["type"].flatMap { $0.isEmpty ? nil : $0 }
      let name = element["name"].flatMap { $0.isEmpty ? nil : $0 }
      return Preformatted(
        kind: kind, text: text, type: type, name: name, anchor: element["anchor"] ?? element["pn"])
    }

    /// What xml2rfc's text rendering sets in place of a drawing it has only as SVG.
    private var svgOnlyNote: String {
      guard let documentID else { return "(Artwork only available as SVG)" }
      let page = RFCEditorEndpoints.base.appending(path: "rfc/\(documentID.fileStem).html")
      return "(Artwork only available as SVG: see \(page.absoluteString))"
    }

    private func parseTable(_ element: XMLTree.Element) -> Table {
      func rows(_ elements: [XMLTree.Element]) -> [Table.Row] {
        elements.map { row in
          Table.Row(
            cells: row.elements.filter { $0.name == "th" || $0.name == "td" }
              .map { normalize(parseInlines($0.children)) },
            anchor: row["anchor"])
        }
      }
      // RFC 7991 allows more than one `<tbody>`: RFC 9911's tables of YANG types
      // put each group of related types in its own, and reading only the first
      // dropped all but the counters.
      let headerRows = element.first("thead")?.all("tr") ?? []
      let bodyRows = element.elements
        .filter { $0.name == "tbody" || $0.name == "tfoot" }
        .flatMap { $0.all("tr") }
      let number: Int? =
        if case .table(let number)? = element["pn"].flatMap(PartNumber.init) { number } else { nil }
      return Table(
        title: element.first("name")?.normalizedText,
        number: number,
        header: rows(headerRows),
        rows: rows(bodyRows),
        anchor: element["anchor"]
      )
    }

    // MARK: Inlines

    /// `linkBare` is false for the words inside an `<eref>`: they are already a
    /// link, and a cross reference nested in one is a link with two destinations.
    func parseInlines(_ nodes: [XMLTree.Node], linkBare: Bool = true) -> [Inline] {
      var result: [Inline] = []
      // The citation a section named in the text before it was folded into, which
      // stands in for the next node.
      var folded: CrossReference?
      for (offset, node) in nodes.enumerated() {
        if let reference = folded {
          result.append(.crossReference(reference))
          folded = nil
          continue
        }
        switch node {
        case .text(var text):
          // Words set as the author typed them are not ours to rewrite.
          if linkBare, offset + 1 < nodes.count, case .element(let next) = nodes[offset + 1],
            let fold = foldingSection(before: next, from: text)
          {
            text = fold.text
            folded = fold.reference
          }
          result += linkBare ? linker.link(text) : [.text(text)]
        case .element(let element):
          result += parseInline(element, linkBare: linkBare)
        }
      }
      return result
    }

    /// A section named in the prose right before a citation, `Section 6.1 of` or
    /// `Appendix B in`, ending `text`. A whole word: `Subsection 2 of` is not one.
    private static let sectionBeforeCitation = Pattern(
      #/\b(?:[Ss]ection\s+(?<section>\d+(?:\.\d+)*)|[Aa]ppendix\s+(?<appendix>[A-Z](?:\.\d+)*))\s+(?:of|in)\s+$/#
    )

    /// The citation `xref` with the section the prose before it names, and the prose
    /// left before it, where `text` ends naming one and `xref` has none of its own:
    /// `Section 6.1 of <xref target="RFC3550"/>` is cited as if the author had written
    /// `<xref target="RFC3550" section="6.1"/>` (#445). The words fold into the
    /// citation when it words the section itself; one in the author's own words keeps
    /// them, and the prose before them, and only its target learns the section. A
    /// citation the section changes nothing for, a place in this document, is nil.
    private func foldingSection(before xref: XMLTree.Element, from text: String)
      -> (text: String, reference: CrossReference)?
    {
      guard foldsSectionsInProse, xref.name == "xref" || xref.name == "relref",
        xref["section"] == nil
      else { return nil }
      // Most text before a citation does not end in `of` or `in`, and is spared the scan.
      let ending = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard ending.hasSuffix("of") || ending.hasSuffix("in"),
        let match = text.firstMatch(of: Self.sectionBeforeCitation),
        let section = match.section ?? match.appendix
      else { return nil }
      var sectioned = xref
      sectioned.attributes["section"] = String(section)
      sectioned.attributes["sectionFormat"] = "of"
      let plain = parseCrossReference(xref)
      let reference = parseCrossReference(sectioned)
      guard reference.target != plain.target else { return nil }
      guard reference.label != plain.label else { return (text, reference) }
      return (String(text[..<match.range.lowerBound]), reference)
    }

    private func parseInline(_ element: XMLTree.Element, linkBare: Bool) -> [Inline] {
      switch element.name {
      case "xref", "relref":
        return [.crossReference(parseCrossReference(element))]
      case "eref":
        let inner = parseInlines(element.children, linkBare: false)
        guard let target = element["target"], let url = URL(string: target) else { return inner }
        // Links into the RFC series are document references, whichever site they point
        // at, where a citation can say all of the link (#683).
        if let link = RFCLink(citing: url) {
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

    func parseCrossReference(_ element: XMLTree.Element) -> CrossReference {
      let targetAnchor = element["target"] ?? ""
      let section = element["section"]
      let innerText = element.normalizedText
      let derived = element["derivedContent"].flatMap { $0.isEmpty ? nil : $0 }
      let format = element["format"] ?? "default"

      let sectionFormat =
        CrossReference.SectionFormat(rawValue: element["sectionFormat"] ?? "") ?? .of

      if let cited = referenceTargets[targetAnchor] {
        let id = cited.id
        let target = CrossReference.Target.document(id, section: section, entry: cited.entry)
        // Words the source put inside the link stand in for the label -- unless
        // they are the series spelling its own name, which is the label we
        // would have composed anyway.
        if !innerText.isEmpty, !CrossReference.isCanonicalTag(innerText, for: id) {
          return CrossReference(target: target, text: innerText, sectionFormat: sectionFormat)
        }
        // `none` asks for the element's own text and nothing else, which may be none
        // at all; `title` for the entry's title, which is not a tag to bracket.
        if format == "none" {
          return CrossReference(target: target, text: innerText, sectionFormat: sectionFormat)
        }
        if format == "title", let derived {
          return CrossReference(target: target, text: derived, sectionFormat: sectionFormat)
        }
        // Words that are the document's own name ask for its label, whatever the
        // entry's tag: composed from the tag, `RFC 1006` against an entry `RC87` read
        // `[RC87]` (#683).
        if !innerText.isEmpty {
          return CrossReference(target: target, sectionFormat: sectionFormat)
        }
        // "RFC9110" is the canonical number; anything else is a tag the author
        // chose ("QUIC-TRANSPORT") and is the name the document uses
        // throughout, so it survives verbatim, brackets and all, with a section
        // worded around it as `sectionFormat` asks: "Appendix A.3 of [HTTP/3]" (#552).
        let raw = derived ?? targetAnchor
        if !CrossReference.isCanonicalTag(raw, for: id) {
          let text =
            section.map { section in
              CrossReference.sectionLabel(
                section, of: CrossReference.nonBreakingLabel(raw), format: sectionFormat)
            } ?? "[\(raw)]"
          return CrossReference(target: target, text: text, sectionFormat: sectionFormat)
        }
        // `counter` asks for something the target cannot supply -- a number -- so
        // the tooling's own rendering is the label.
        if format == "counter", let derived {
          return CrossReference(target: target, text: derived, sectionFormat: sectionFormat)
        }
        return CrossReference(target: target, sectionFormat: sectionFormat)
      }

      // A member of a `<referencegroup>` has no entry of its own in the bibliography;
      // the group's is the one to link to.
      let entry = referenceEntries[targetAnchor]
      // A section of an entry outside the series is worded as a section of an RFC
      // is, around the entry's tag, and opens the section's own page (#473).
      if let entry, let section {
        let target = CrossReference.Target.entrySection(
          entry: entry, tag: derived ?? targetAnchor, section: section,
          // A link without a scheme leads nowhere; the entry is then the target.
          url: element["derivedLink"].flatMap(absoluteURL))
        if !innerText.isEmpty || format == "none" {
          return CrossReference(target: target, text: innerText, sectionFormat: sectionFormat)
        }
        if format == "default" {
          return CrossReference(target: target, sectionFormat: sectionFormat)
        }
        return CrossReference(target: target, text: derived, sectionFormat: sectionFormat)
      }
      let target = CrossReference.Target.anchor(entry ?? targetAnchor)
      // Empty or not, the element's own text is all `none` shows (xml2rfc renders an
      // empty one as nothing), never the anchor.
      if format == "none" {
        return CrossReference(target: target, text: innerText)
      }
      if innerText.isEmpty, format == "default", entry != nil {
        return CrossReference(target: target, text: "[\(derived ?? targetAnchor)]")
      }
      let text = innerText.isEmpty ? derived : innerText
      return CrossReference(target: target, text: text)
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
      [.text(author.isEditor ? "\(author.name) (editor)" : author.name)]
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
          .text("URI: "), link(absoluteURL(uri), uri),
        ])
      }
    }
    return Array(lines.joined(separator: [Inline.lineBreak]))
  }

  /// `string` as a URL, unless it has no scheme: a relative link leads nowhere in
  /// the reader.
  static func absoluteURL(_ string: String) -> URL? {
    URL(string: string).flatMap { $0.scheme == nil ? nil : $0 }
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
