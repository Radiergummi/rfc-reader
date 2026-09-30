import Foundation

/// Writes an `RFCDocument` back out as RFCXML v3.
///
/// This exists for the corpus pipeline: legacy plain-text RFCs are parsed once, offline,
/// and published as XML so the app has a single runtime path. The output uses the same
/// conventions as the RFC Editor's prepped XML (`pn` part numbers, `anchor`s, `derivedContent`
/// omitted), so `RFCXMLParser` reads it back into an equivalent model. Cross references to
/// documents that have no entry in the References section become `<eref>`s pointing at
/// rfc-editor.org, which the parser resolves back into document references.
public struct RFCXMLSerializer: Sendable {
  public struct Options: Sendable {
    /// Written as a comment right after the XML declaration; say where the XML came from.
    public var generatorComment: String?
    /// Emitted as `<link rel="alternate">`, normally the original `.txt` URL.
    public var sourceURL: URL?

    public init(generatorComment: String? = nil, sourceURL: URL? = nil) {
      self.generatorComment = generatorComment
      self.sourceURL = sourceURL
    }
  }

  public var options: Options

  public init(options: Options = Options()) {
    self.options = options
  }

  /// The XML, and what could not be written into it.
  public struct Serialization: Sendable {
    public var xml: String
    /// One line for each part of the document the XML has no place for and so leaves out.
    public var warnings: [String]
  }

  /// The XML alone, for a caller that has no use for the warnings.
  public func serialize(_ document: RFCDocument) -> String {
    serialization(of: document).xml
  }

  public func serialization(of document: RFCDocument) -> Serialization {
    var writer = Writer()
    let referenceAnchors = Self.referenceAnchors(in: document)
    var context = Context(referenceAnchors: referenceAnchors, sections: document.sections)

    writer.raw("<?xml version='1.0' encoding='utf-8'?>")
    if let comment = options.generatorComment {
      writer.raw("<!-- \(comment.replacingOccurrences(of: "--", with: "- -")) -->")
    }

    var rfcAttributes: [(String, String)] = [("version", "3")]
    if let id = document.header.id, id.series == .rfc {
      rfcAttributes.append(("number", String(id.number)))
    }
    if let category = document.header.category {
      rfcAttributes.append(("category", category.rawValue))
    }
    if let draft = document.header.draftName { rfcAttributes.append(("docName", draft)) }
    if !document.header.obsoletes.isEmpty {
      rfcAttributes.append(
        ("obsoletes", document.header.obsoletes.map { String($0.number) }.joined(separator: ", ")))
    }
    if !document.header.updates.isEmpty {
      rfcAttributes.append(
        ("updates", document.header.updates.map { String($0.number) }.joined(separator: ", ")))
    }
    rfcAttributes.append(("xml:lang", "en"))

    writer.open("rfc", rfcAttributes)
    if let draft = document.header.precedingDraft {
      writer.empty("link", [("href", draft.absoluteString), ("rel", "prev")])
    }
    if let source = options.sourceURL {
      writer.empty("link", [("href", source.absoluteString), ("rel", "alternate")])
    }
    // `<abstract>` holds paragraphs and lists only. One holding anything else
    // (RFC 391's has artwork) is written as the body's first section instead, so
    // nothing in it is dropped.
    let abstractFits = document.header.abstract.allSatisfy(Self.fitsInAbstract)
    writeFront(document.header, writer: &writer, context: &context, abstract: abstractFits)

    let backStart = Self.backStart(document.sections)
    writer.open("middle")
    if !abstractFits {
      let abstract = Section(
        anchor: "abstract", title: "Abstract", blocks: document.header.abstract)
      writeSection(abstract, writer: &writer, context: &context)
    }
    for section in document.sections[..<backStart] {
      writeOrLift(section, writer: &writer, context: &context)
    }
    writer.close("middle")

    // The back is every bibliography, in document order, then its sections, which
    // the schema requires in that order: those lifted from the middle, its own, then
    // those lifted from its sections (#315). Its sections are written apart and
    // first, so what they lift can still go ahead of them.
    let back = document.sections[backStart...]
    var sections = Writer(depth: writer.depth + 1)
    for section in back {
      writeOrLift(section, writer: &sections, context: &context)
    }
    if !context.lifted.isEmpty || !back.isEmpty {
      writer.open("back")
      for section in context.lifted {
        writeReferences(section, writer: &writer, context: &context)
      }
      writer.append(sections)
      writer.close("back")
    }
    writer.close("rfc")
    return Serialization(xml: writer.output, warnings: context.warnings)
  }

  /// Where `<back>` starts. The schema orders it as its `<references>`, then its
  /// sections, and requires `<middle>` to hold at least one section (#65). So the back
  /// is the run of references sections that ends at the last one, and whatever
  /// follows; everything before that run is the middle, an appendix among it too,
  /// whose `pn` still names it one. With no references, the back is the appendices
  /// the document ends with, and when that would leave the middle empty, as in the
  /// legacy documents whose first chapter, `I.`, reads as an appendix, there is no
  /// back.
  static func backStart(_ sections: [Section]) -> Int {
    if let last = sections.lastIndex(where: isReferences) {
      var first = last
      while first > 0, isReferences(sections[first - 1]) { first -= 1 }
      return first
    }
    var first = sections.count
    while first > 0, sections[first - 1].isAppendix { first -= 1 }
    return first == 0 ? sections.count : first
  }

  /// `<abstract>` holds `t`, `dl`, `ol` and `ul`, and nothing else.
  private static func fitsInAbstract(_ block: Block) -> Bool {
    switch block {
    case .paragraph, .list, .definitionList: true
    default: false
    }
  }

  // MARK: - Front

  private func writeFront(
    _ header: DocumentHeader, writer: inout Writer, context: inout Context, abstract: Bool
  ) {
    writer.open("front")
    var titleAttributes: [(String, String)] = []
    if let abbrev = header.abbreviatedTitle { titleAttributes.append(("abbrev", abbrev)) }
    writer.element("title", titleAttributes, text: header.title)
    if let id = header.id, id.series == .rfc {
      writer.empty("seriesInfo", [("name", "RFC"), ("value", String(id.number))])
    }
    for author in header.authors {
      var attributes: [(String, String)] = [("fullname", author.name)]
      if let role = author.role { attributes.append(("role", role.rawValue)) }
      if let contact = author.contact {
        writer.open("author", attributes)
        writeContact(contact, writer: &writer)
        writer.close("author")
      } else {
        writer.empty("author", attributes)
      }
    }
    // RFCXML requires `author+`, and `<author/>` satisfies the schema; the parser reads
    // it back as no author at all. Unlike a reference's, a document's own front always
    // names someone in the published series, and xml2rfc's prep step refuses an empty
    // one here -- the schema is the bar this output is held to, not prep.
    if header.authors.isEmpty { writer.empty("author") }
    if let date = header.date {
      var attributes: [(String, String)] = []
      if let month = date.monthName { attributes.append(("month", month)) }
      if let day = date.day { attributes.append(("day", String(day))) }
      attributes.append(("year", String(date.year)))
      writer.empty("date", attributes)
    }
    if let area = header.area { writer.element("area", text: area) }
    if let group = header.workingGroup { writer.element("workgroup", text: group) }
    for keyword in header.keywords { writer.element("keyword", text: keyword) }
    if abstract, !header.abstract.isEmpty {
      writer.open("abstract")
      for block in header.abstract { writeBlock(block, writer: &writer, context: &context) }
      writer.close("abstract")
    }
    writer.close("front")
  }

  /// In the schema's order: `organization`, then `address` holding `postal`,
  /// `phone`, `facsimile`, each `email` and `uri`.
  private func writeContact(_ contact: AuthorContact, writer: inout Writer) {
    if let organization = contact.organization {
      writer.element("organization", text: organization)
    }
    let hasAddress =
      contact.postal != nil || contact.phone != nil || contact.facsimile != nil
      || !contact.emails.isEmpty || contact.uri != nil
    guard hasAddress else { return }
    writer.open("address")
    if let postal = contact.postal {
      writer.open("postal")
      // The schema's choice: the author's lines, or the fields, never both.
      if postal.postalLines.isEmpty {
        for street in postal.street { writer.element("street", text: street) }
        for line in postal.extendedAddress { writer.element("extaddr", text: line) }
        let fields = [
          ("pobox", postal.postOfficeBox), ("cityarea", postal.cityArea), ("city", postal.city),
          ("region", postal.region), ("code", postal.code), ("sortingcode", postal.sortingCode),
          ("country", postal.country),
        ]
        for case (let name, let value?) in fields { writer.element(name, text: value) }
      } else {
        for line in postal.postalLines { writer.element("postalLine", text: line) }
      }
      writer.close("postal")
    }
    if let phone = contact.phone { writer.element("phone", text: phone) }
    if let facsimile = contact.facsimile { writer.element("facsimile", text: facsimile) }
    for email in contact.emails { writer.element("email", text: email) }
    if let uri = contact.uri { writer.element("uri", text: uri) }
    writer.close("address")
  }

  // MARK: - Sections

  /// A section at any depth, in `<middle>` or among the back's sections, written in
  /// place, or, when it is a references section, set aside for the back's references
  /// (`Context.lifted`), keeping its anchor, number and name (#315): the schema has
  /// room for `<references>` nowhere else. One ahead of the back (RFC 2511's `9.
  /// References`, before its appendices and theirs) written as a section would wrap
  /// its list in a second, unnumbered `<references>`, and read back as a section
  /// holding a subsection it never had.
  private func writeOrLift(_ section: Section, writer: inout Writer, context: inout Context) {
    if Self.isReferences(section) {
      context.lifted.append(section)
    } else {
      writeSection(section, writer: &writer, context: &context)
    }
  }

  private func writeSection(_ section: Section, writer: inout Writer, context: inout Context) {
    let partNumber = context.partNumber(of: section)
    let title = partNumber == nil ? section.displayTitleInlines : section.title
    var attributes = Self.anchorAttribute(section.anchor, partNumber: partNumber)
    if let partNumber {
      attributes.append(("numbered", "true"))
      attributes.append(("pn", partNumber))
    } else {
      attributes.append(("numbered", "false"))
    }
    writer.open("section", attributes)
    writer.line("<name>\(inlineXML(title, context: &context))</name>")
    for block in section.blocks { writeBlock(block, writer: &writer, context: &context) }
    // A bibliography under a section, a subsection of References or one under an
    // appendix, goes to the back, and the section keeps the rest (#315).
    for subsection in section.subsections {
      writeOrLift(subsection, writer: &writer, context: &context)
    }
    writer.close("section")
  }

  private func writeReferences(_ section: Section, writer: inout Writer, context: inout Context) {
    let partNumber = context.partNumber(of: section)
    let title = partNumber == nil ? section.displayTitleInlines : section.title
    var attributes = Self.anchorAttribute(section.anchor, partNumber: partNumber)
    if let partNumber { attributes.append(("pn", partNumber)) }
    writer.open("references", attributes)
    writer.line("<name>\(inlineXML(title, context: &context))</name>")
    var entries: [Reference] = []
    for block in section.blocks {
      guard case .references(let list) = block else {
        context.warnings.append(
          "dropped non-reference block in references section \(section.anchor)")
        continue
      }
      entries += list.entries
    }
    // A list holding entries beside lists of its own may not hold them directly:
    // they go in a list of their own, named after it (#315).
    let wrapsEntries = !entries.isEmpty && !section.subsections.isEmpty
    if wrapsEntries {
      // Named after the list, which is unique, rather than counted, so it stays
      // what it was from one build to the next.
      writer.open("references", [("anchor", "\(section.anchor)-entries")])
      writer.line("<name>\(inlineXML(title, context: &context))</name>")
    }
    for reference in entries {
      writeReference(reference, writer: &writer, context: &context)
    }
    if wrapsEntries { writer.close("references") }
    for subsection in section.subsections {
      writeReferences(subsection, writer: &writer, context: &context)
    }
    writer.close("references")
  }

  private func writeReference(
    _ reference: Reference, writer: inout Writer, context: inout Context
  ) {
    var attributes: [(String, String)] = [("anchor", reference.anchor)]
    if let url = reference.url { attributes.append(("target", url.absoluteString)) }
    if reference.displayAnchor != reference.anchor {
      attributes.append(("derivedAnchor", reference.displayAnchor))
    }
    writer.open("reference", attributes)
    writer.open("front")
    writer.element(
      "title",
      text: reference.title.isEmpty ? (reference.rawText ?? reference.anchor) : reference.title)
    for author in reference.authors {
      var authorAttributes: [(String, String)] = [("fullname", author.name)]
      if let role = author.role { authorAttributes.append(("role", role.rawValue)) }
      writer.empty("author", authorAttributes)
    }
    // The published series' own spelling of an entry naming no one (RFC 9293's `offload`).
    if reference.authors.isEmpty { writer.empty("author") }
    if let date = reference.date {
      var dateAttributes: [(String, String)] = []
      if let month = date.monthName { dateAttributes.append(("month", month)) }
      dateAttributes.append(("year", String(date.year)))
      writer.empty("date", dateAttributes)
    }
    writer.close("front")
    for info in reference.seriesInfo {
      writer.empty("seriesInfo", [("name", info.name), ("value", info.value)])
    }
    if let raw = reference.rawText, !reference.title.isEmpty {
      writer.element("refcontent", text: raw)
    }
    if !reference.annotation.isEmpty {
      writer.line(
        "<annotation>\(inlineXML(reference.annotation, context: &context))</annotation>")
    }
    writer.close("reference")
  }

  // MARK: - Blocks

  private func writeBlock(_ block: Block, writer: inout Writer, context: inout Context) {
    switch block {
    case .paragraph(let paragraph):
      var attributes: [(String, String)] = []
      if let anchor = paragraph.anchor { attributes.append(("pn", anchor)) }
      if paragraph.indent > 0 { attributes.append(("indent", String(paragraph.indent))) }
      writer.line(
        "<t\(Writer.attributeString(attributes))>\(inlineXML(paragraph.inlines, context: &context))</t>"
      )
    case .list(let list):
      var attributes: [(String, String)] = []
      let name: String
      switch list.style {
      case .bullet:
        name = "ul"
      case .bare:
        name = "ul"
        attributes.append(("empty", "true"))
      case .numbered(let numbering):
        name = "ol"
        attributes.append(("type", numbering.type))
        attributes.append(("start", String(numbering.start)))
      }
      if list.isCompact { attributes.append(("spacing", "compact")) }
      writer.open(name, attributes)
      for item in list.items {
        var itemAttributes: [(String, String)] = []
        if let anchor = item.anchor { itemAttributes.append(("pn", anchor)) }
        writer.open("li", itemAttributes)
        for inner in item.blocks { writeBlock(inner, writer: &writer, context: &context) }
        writer.close("li")
      }
      writer.close(name)
    case .definitionList(let items):
      writer.open("dl")
      for item in items {
        var termAttributes: [(String, String)] = []
        if let anchor = item.anchor { termAttributes.append(("pn", anchor)) }
        writer.line(
          "<dt\(Writer.attributeString(termAttributes))>\(inlineXML(item.term, context: &context))</dt>"
        )
        var definitionAttributes: [(String, String)] = []
        if let anchor = item.definitionAnchor { definitionAttributes.append(("pn", anchor)) }
        writer.open("dd", definitionAttributes)
        for inner in item.definition { writeBlock(inner, writer: &writer, context: &context) }
        writer.close("dd")
      }
      writer.close("dl")
    case .preformatted(let preformatted):
      let name = preformatted.kind == .artwork ? "artwork" : "sourcecode"
      var attributes: [(String, String)] = []
      if let type = preformatted.type { attributes.append(("type", type)) }
      if let fileName = preformatted.name { attributes.append(("name", fileName)) }
      if let anchor = preformatted.anchor { attributes.append(("pn", anchor)) }
      writer.line("<\(name)\(Writer.attributeString(attributes))>")
      writer.raw(Writer.escape(preformatted.text))
      writer.raw("</\(name)>")
    case .figure(let figure):
      var attributes: [(String, String)] = []
      if let anchor = figure.anchor { attributes.append(("anchor", anchor)) }
      if let number = figure.number {
        attributes.append(("pn", PartNumber.figure(number).attribute))
      }
      writer.open("figure", attributes)
      if let title = figure.title { writer.element("name", text: title) }
      for inner in figure.blocks { writeBlock(inner, writer: &writer, context: &context) }
      writer.close("figure")
    case .table(let table):
      var attributes: [(String, String)] = []
      if let anchor = table.anchor { attributes.append(("anchor", anchor)) }
      if let number = table.number { attributes.append(("pn", PartNumber.table(number).attribute)) }
      writer.open("table", attributes)
      if let title = table.title { writer.element("name", text: title) }
      if !table.header.isEmpty {
        writer.open("thead")
        for row in table.header {
          writer.open("tr", row.anchor.map { [("anchor", $0)] } ?? [])
          for cell in row.cells { writer.line("<th>\(inlineXML(cell, context: &context))</th>") }
          writer.close("tr")
        }
        writer.close("thead")
      }
      writer.open("tbody")
      for row in table.rows {
        writer.open("tr", row.anchor.map { [("anchor", $0)] } ?? [])
        for cell in row.cells { writer.line("<td>\(inlineXML(cell, context: &context))</td>") }
        writer.close("tr")
      }
      writer.close("tbody")
      writer.close("table")
    case .blockQuote(let blocks):
      writer.open("blockquote")
      for inner in blocks { writeBlock(inner, writer: &writer, context: &context) }
      writer.close("blockquote")
    case .aside(let blocks):
      writer.open("aside")
      for inner in blocks { writeBlock(inner, writer: &writer, context: &context) }
      writer.close("aside")
    case .references(let list):
      // A reference list outside a references section: wrap it so it stays valid.
      writer.open("references", [("anchor", "refs-\(context.nextAutoAnchor())")])
      writer.element("name", text: list.title)
      for reference in list.entries {
        writeReference(reference, writer: &writer, context: &context)
      }
      writer.close("references")
    }
  }

  // MARK: - Inlines

  private func inlineXML(_ inlines: [Inline], context: inout Context) -> String {
    var result = ""
    for inline in inlines {
      switch inline {
      case .text(let text):
        result += Writer.escape(text)
      case .emphasis(let inner):
        result += "<em>\(inlineXML(inner, context: &context))</em>"
      case .strong(let inner):
        result += "<strong>\(inlineXML(inner, context: &context))</strong>"
      case .code(let text):
        result += "<tt>\(Writer.escape(text))</tt>"
      case .superscript(let text):
        result += "<sup>\(Writer.escape(text))</sup>"
      case .subscript(let text):
        result += "<sub>\(Writer.escape(text))</sub>"
      case .link(let url, let inner):
        result +=
          "<eref target=\"\(Writer.escapeAttribute(url.absoluteString))\">\(inlineXML(inner, context: &context))</eref>"
      case .crossReference(let xref):
        result += crossReferenceXML(xref, context: &context)
      case .lineBreak:
        result += "<br/>"
      }
    }
    return result
  }

  private func crossReferenceXML(_ xref: CrossReference, context: inout Context) -> String {
    let content = xref.text.map(Writer.escape) ?? ""
    switch xref.target {
    case .anchor(let anchor):
      let target = Writer.escapeAttribute(anchor)
      return content.isEmpty
        ? "<xref target=\"\(target)\"/>" : "<xref target=\"\(target)\">\(content)</xref>"
    case .entrySection(let entry, let tag, let section, let url):
      var attributes = " target=\"\(Writer.escapeAttribute(entry))\""
      attributes += " section=\"\(Writer.escapeAttribute(section))\""
      attributes += " sectionFormat=\"\(xref.sectionFormat.rawValue)\""
      attributes += " derivedContent=\"\(Writer.escapeAttribute(tag))\""
      if let url {
        attributes += " derivedLink=\"\(Writer.escapeAttribute(url.absoluteString))\""
      }
      // Words that are there but empty are `none`'s nothing, not ours to compose.
      if xref.text?.isEmpty == true {
        attributes += " format=\"none\""
      }
      return content.isEmpty ? "<xref\(attributes)/>" : "<xref\(attributes)>\(content)</xref>"
    case .document(let id, let section, _):
      if let anchor = context.referenceAnchors[id] {
        var attributes = " target=\"\(Writer.escapeAttribute(anchor))\""
        // The source's own wording, not a fixed "of": it decides how the label
        // reads on the way back in, and `bare` in particular means something
        // different enough that the reader declines to chip it.
        if let section {
          attributes += " section=\"\(Writer.escapeAttribute(section))\""
          attributes += " sectionFormat=\"\(xref.sectionFormat.rawValue)\""
        }
        return content.isEmpty ? "<xref\(attributes)/>" : "<xref\(attributes)>\(content)</xref>"
      }
      // No bibliography entry: an external link the parser maps back to a document reference.
      let url = RFCLink(id: id, section: section).webURL
      let label = content.isEmpty ? Writer.escape(id.displayName) : content
      return "<eref target=\"\(Writer.escapeAttribute(url.absoluteString))\">\(label)</eref>"
    }
  }

  // MARK: - Helpers

  private struct Context {
    var referenceAnchors: [DocumentID: String]
    var warnings: [String] = []
    /// Every references section, the back's own among them, in document order, which
    /// the back writes ahead of its sections (#315).
    var lifted: [Section] = []
    private var autoAnchor = 0
    /// Each numbered section's `pn`, by its anchor, claimed in document order: the
    /// first of two sections numbered alike takes it, however the two are written.
    /// A bibliography lifted into the back is written after sections that follow it
    /// (#315), and claiming in writing order gave its number to the later one, whose
    /// `pn` then declared the ID the lifted list's anchor declared too.
    private var partNumbers: [String: String] = [:]

    init(referenceAnchors: [DocumentID: String], sections: [Section]) {
      self.referenceAnchors = referenceAnchors
      var claimed: Set<String> = []
      func claim(_ sections: [Section]) {
        for section in sections {
          if let number = section.number, partNumbers[section.anchor] == nil {
            let partNumber = PartNumber(sectionNumber: number, isAppendix: section.isAppendix)
              .attribute
            if claimed.insert(partNumber).inserted { partNumbers[section.anchor] = partNumber }
          }
          claim(section.subsections)
        }
      }
      claim(sections)
    }

    /// The section's `pn`, or nil when it has no number or an earlier section claimed
    /// that one. Two sections numbered alike (RFC 1 has two appendices A) would share
    /// a `pn`, which is an ID. The second is written unnumbered, its number in its
    /// name, so it reads the same and names nothing twice (#65). Given once: a second
    /// section of the same anchor gets none.
    mutating func partNumber(of section: Section) -> String? {
      guard section.number != nil else { return nil }
      return partNumbers.removeValue(forKey: section.anchor)
    }

    mutating func nextAutoAnchor() -> Int {
      autoAnchor += 1
      return autoAnchor
    }
  }

  private static func referenceAnchors(in document: RFCDocument) -> [DocumentID: String] {
    var anchors: [DocumentID: String] = [:]
    for case .references(let list) in document.blocks {
      for reference in list.entries {
        if let id = reference.documentID, anchors[id] == nil { anchors[id] = reference.anchor }
      }
    }
    return anchors
  }

  static func isReferences(_ section: Section) -> Bool {
    if section.blocks.contains(where: {
      if case .references = $0 { return true } else { return false }
    }) {
      return true
    }
    return !section.subsections.isEmpty && section.blocks.isEmpty
      && section.subsections.allSatisfy(isReferences)
  }

  /// `anchor` and `pn` are both `xsd:ID`, so an anchor that is the part number would
  /// declare that ID twice. The part number is written either way, as the published
  /// series always does, and the parser reads the anchor back from it.
  private static func anchorAttribute(_ anchor: String, partNumber: String?) -> [(String, String)] {
    anchor == partNumber ? [] : [("anchor", anchor)]
  }

  private struct Writer {
    private(set) var output = ""
    private(set) var depth: Int

    /// Starting `depth` levels in, for what is written apart and appended there.
    init(depth: Int = 0) {
      self.depth = depth
    }

    mutating func append(_ other: Writer) {
      output += other.output
    }

    mutating func raw(_ string: String) {
      output += string
      output += "\n"
    }

    mutating func line(_ string: String) {
      output += String(repeating: "  ", count: depth)
      output += string
      output += "\n"
    }

    mutating func open(_ name: String, _ attributes: [(String, String)] = []) {
      line("<\(name)\(Self.attributeString(attributes))>")
      depth += 1
    }

    mutating func close(_ name: String) {
      depth -= 1
      line("</\(name)>")
    }

    mutating func empty(_ name: String, _ attributes: [(String, String)] = []) {
      line("<\(name)\(Self.attributeString(attributes))/>")
    }

    mutating func element(_ name: String, _ attributes: [(String, String)] = [], text: String) {
      line("<\(name)\(Self.attributeString(attributes))>\(Self.escape(text))</\(name)>")
    }

    static func attributeString(_ attributes: [(String, String)]) -> String {
      attributes.map { " \($0.0)=\"\(escapeAttribute($0.1))\"" }.joined()
    }

    static func escape(_ text: String) -> String {
      var result = ""
      result.reserveCapacity(text.count)
      for character in text {
        switch character {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        default:
          // XML 1.0 forbids C0 control characters other than tab, newline and return.
          if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
            scalar.value < 0x20, scalar != "\t", scalar != "\n", scalar != "\r"
          {
            continue
          }
          result.append(character)
        }
      }
      return result
    }

    static func escapeAttribute(_ text: String) -> String {
      escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
  }
}
