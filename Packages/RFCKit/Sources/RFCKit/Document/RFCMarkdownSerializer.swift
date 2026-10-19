import Foundation

/// Writes an `RFCDocument`, or one of its sections, as CommonMark with GitHub's
/// tables (#642, #377): the Markdown export, and the text the MCP server returns.
///
/// Nothing is lost: every inline's text is written, in order, and every anchor once,
/// as an HTML comment ahead of what carries it (`<!-- anchor: section-4.2-3 -->`), so
/// a reader of the text can name a paragraph without counting. Renderers ignore
/// the comments. The same input is written the same way every time.
/// `docs/superpowers/specs/2026-10-02-mcp-server-design.md`, "Slice 1", has the
/// rules block kind by block kind.
public struct RFCMarkdownSerializer: Sendable {
  public var inDocumentLinks: InDocumentLinks

  public init(inDocumentLinks: InDocumentLinks = .fragments) {
    self.inDocumentLinks = inDocumentLinks
  }

  /// The whole document: its title and byline, its abstract, then its sections, one
  /// heading level below the title.
  public func serialize(_ document: RFCDocument) -> String {
    let writer = Writer(links: ExportLinks(document: document, inDocument: inDocumentLinks))
    var parts: [[String]] = [
      ["# " + Writer.headingText(Writer.escaped(document.header.title))]
    ]
    let byline = ExportLinks.byline(of: document.header)
    if !byline.isEmpty { parts.append([Writer.escapingLineStart(Writer.escaped(byline))]) }
    if !document.header.abstract.isEmpty {
      // The anchor the full-text index gives the abstract, unless a section has it,
      // as in the page (`RFCHTMLSerializer`).
      let isTaken = document.allSections.contains { $0.anchor == FullTextIndex.abstractAnchor }
      parts.append(
        (isTaken ? [] : writer.anchor(FullTextIndex.abstractAnchor)) + ["## Abstract"])
      parts.append(writer.blocks(document.header.abstract))
    }
    for section in document.sections {
      parts.append(writer.section(section, level: 2, includingSubsections: true))
    }
    return Writer.joined(parts)
  }

  /// `section` of `document`, its heading at the first level and its subsections'
  /// below it, or without its subsections.
  public func serialize(
    _ section: Section, in document: RFCDocument, includingSubsections: Bool = true
  ) -> String {
    let writer = Writer(links: ExportLinks(document: document, inDocument: inDocumentLinks))
    return Writer.joined([
      writer.section(section, level: 1, includingSubsections: includingSubsections)
    ])
  }
}

extension RFCMarkdownSerializer {
  /// The walk over the model. Each block becomes lines; blocks are separated by a
  /// blank line, and a container indents what it holds.
  fileprivate struct Writer {
    let links: ExportLinks
    /// Whether what is written goes in a GitHub table's cell, where a `|` ends the
    /// cell even inside a code span unless it is escaped.
    var isInTable = false

    init(links: ExportLinks) {
      self.links = links
    }

    static func joined(_ parts: [[String]]) -> String {
      parts.filter { !$0.isEmpty }.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
        + "\n"
    }

    // MARK: Sections

    func section(_ section: Section, level: Int, includingSubsections: Bool) -> [String] {
      let marks = String(repeating: "#", count: min(level, 6))
      let title = Self.headingText(inlines(section.displayTitleInlines, breaks: " "))
      var parts: [[String]] = [
        anchor(section.anchor) + [title.isEmpty ? marks : marks + " " + title]
      ]
      parts.append(blocks(section.blocks))
      if includingSubsections {
        for subsection in section.subsections {
          parts.append(self.section(subsection, level: level + 1, includingSubsections: true))
        }
      }
      return Self.lines(parts)
    }

    /// A heading's text, with a trailing `#` escaped so it is not read as a closing
    /// sequence.
    static func headingText(_ text: String) -> String {
      guard text.hasSuffix("#") else { return text }
      return text.dropLast() + "\\#"
    }

    // MARK: Blocks

    /// Blocks, separated by blank lines. A list after a block that ends with a list
    /// is kept apart from it by an empty comment, which CommonMark would otherwise
    /// read as one list.
    func blocks(_ blocks: [Block]) -> [String] {
      var parts: [[String]] = []
      for part in blocks.map(block) where !part.isEmpty {
        if let previous = parts.last, Self.endsWithList(previous), Self.isList(part) {
          parts.append(["<!-- -->"])
        }
        parts.append(part)
      }
      return Self.lines(parts)
    }

    /// Whether `lines` open with a list item, past their anchors.
    static func isList(_ lines: [String]) -> Bool {
      guard let first = lines.first(where: { !isAnchor($0) }) else { return false }
      if first.hasPrefix("- ") || first == "-" { return true }
      let digits = first.prefix { $0.isASCII && $0.isNumber }
      let rest = first.dropFirst(digits.count)
      return !digits.isEmpty && (rest.hasPrefix(". ") || rest.hasPrefix(") "))
    }

    /// Whether `lines` end with a list: whether the last of them not indented under
    /// something else, past the anchors, is a list item.
    static func endsWithList(_ lines: [String]) -> Bool {
      guard let last = lines.last(where: { !$0.isEmpty && !$0.hasPrefix(" ") && !isAnchor($0) })
      else { return false }
      return isList([last])
    }

    static func isAnchor(_ line: String) -> Bool {
      line.hasPrefix("<!-- anchor:")
    }

    /// Parts separated by blank lines, the empty ones left out.
    static func lines(_ parts: [[String]]) -> [String] {
      Array(parts.filter { !$0.isEmpty }.joined(separator: [""]))
    }

    func block(_ block: Block) -> [String] {
      switch block {
      case .paragraph(let paragraph):
        return anchor(paragraph.anchor) + paragraphLines(paragraph.inlines)
      case .list(let list):
        return self.list(list)
      case .definitionList(let list):
        return definitionList(list)
      case .preformatted(let content):
        return anchor(content.anchor) + fenced(content)
      case .figure(let figure):
        let caption = BlockCaption.text("Figure", number: figure.number, title: figure.title)
        return anchor(figure.anchor)
          + Self.lines([
            blocks(figure.blocks), caption.map { ["*" + Self.escaped($0) + "*"] } ?? [],
          ])
      case .table(let table):
        return self.table(table)
      case .blockQuote(let inner), .aside(let inner):
        return blocks(inner).map { $0.isEmpty ? ">" : "> " + $0 }
      case .references(let list):
        return references(list)
      case .index(let index):
        return self.index(index)
      }
    }

    func anchor(_ anchor: String?) -> [String] {
      guard let anchor else { return [] }
      return ["<!-- anchor: \(anchor) -->"]
    }

    /// A paragraph reflowed: one line, but for where the source breaks it.
    func paragraphLines(_ inlines: [Inline]) -> [String] {
      let text = self.inlines(Self.trimmingBreaks(inlines), breaks: "\\\n")
      guard !text.isEmpty else { return [] }
      return text.split(separator: "\n", omittingEmptySubsequences: false).map {
        Self.escapingLineStart(String($0))
      }
    }

    /// `inlines` without the breaks they open or close with, which break nothing,
    /// nor do those with only spaces between them and either end.
    static func trimmingBreaks(_ inlines: [Inline]) -> [Inline] {
      func isBlank(_ inline: Inline) -> Bool {
        switch inline {
        case .lineBreak: true
        case .text(let text): text.allSatisfy(\.isWhitespace)
        default: false
        }
      }
      return Array(inlines.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }

    /// `lines` as the content of a list item marked `marker`: the first line after
    /// the marker, the rest indented under it.
    static func item(_ marker: String, _ lines: [String]) -> [String] {
      guard let first = lines.first else { return [marker] }
      let indent = String(repeating: " ", count: marker.count + 1)
      return [marker + " " + first] + lines.dropFirst().map { $0.isEmpty ? "" : indent + $0 }
    }

    func list(_ list: ListBlock) -> [String] {
      let items: [[String]]
      switch list.style {
      case .bullet:
        items = list.items.map { Self.item("-", anchor($0.anchor) + blocks($0.blocks)) }
      case .bare:
        items = list.items.map { anchor($0.anchor) + blocks($0.blocks) }
        return Self.lines(items)
      case .numbered(let numbering):
        let isCommonMark =
          numbering.counter == .decimal && numbering.prefix.isEmpty
          && [".", ")"].contains(numbering.suffix) && numbering.start >= 0
        items = list.items.enumerated().map { index, item in
          let marker = numbering.marker(at: index)
          let content = anchor(item.anchor) + blocks(item.blocks)
          if isCommonMark { return Self.item(marker, content) }
          // The marker opens the item's first paragraph; ahead of anything else, a
          // fence or a table, it would stop it being one, so it stands alone. A
          // paragraph with nothing to write is not the first.
          guard case .paragraph = item.blocks.first(where: { !block($0).isEmpty }) else {
            return Self.item("-", [Self.escaped(marker), ""] + content)
          }
          return Self.item("-", Self.prefixing(Self.escaped(marker), to: content))
        }
      }
      // A list is loose, items set apart, when any item holds more than one line
      // past its anchors, which keep their own lines in a tight list. Text never
      // holds an anchor's comment: its `<` is escaped.
      let isLoose = items.contains { $0.filter { !$0.contains("<!-- anchor:") }.count > 1 }
      return isLoose ? Self.lines(items) : items.flatMap { $0 }
    }

    /// `content` with `marker` ahead of its first line that is not an anchor.
    static func prefixing(_ marker: String, to content: [String]) -> [String] {
      guard let index = content.firstIndex(where: { !isAnchor($0) }) else {
        return content + [marker]
      }
      var content = content
      content[index] = content[index].isEmpty ? marker : marker + " " + content[index]
      return content
    }

    func definitionList(_ list: DefinitionList) -> [String] {
      let items = list.items.map { item -> [String] in
        let term = inlines(item.term, breaks: " ")
        let definition = anchor(item.definitionAnchor) + blocks(item.definition)
        return Self.item(
          "-",
          Self.lines([
            anchor(item.anchor) + (term.isEmpty ? [] : ["**" + term + "**"]), definition,
          ]))
      }
      return Self.lines(items)
    }

    func fenced(_ content: Preformatted) -> [String] {
      var text = content.text
      while text.hasSuffix("\n") { text.removeLast() }
      let fence = String(repeating: "`", count: max(3, Self.longestRun(of: "`", in: text) + 1))
      let info = ArtworkType.canonical(content.type)?.name ?? ""
      let body = text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false)
      return [fence + info] + body.map(String.init) + [fence]
    }

    static func longestRun(of character: Character, in text: String) -> Int {
      var longest = 0
      var current = 0
      for each in text {
        current = each == character ? current + 1 : 0
        longest = max(longest, current)
      }
      return longest
    }

    // MARK: Tables

    func table(_ table: Table) -> [String] {
      let rows = table.header + table.rows
      let caption = BlockCaption.text("Table", number: table.number, title: table.title)
      let fitsOneLine = rows.allSatisfy { row in
        row.cells.allSatisfy { cell in !cell.flattened.contains(.lineBreak) }
      }
      let body =
        fitsOneLine && table.header.count <= 1 ? gitHubTable(table) : stackedTable(table)
      return anchor(table.anchor)
        + Self.lines([body, caption.map { ["*" + Self.escaped($0) + "*"] } ?? []])
    }

    private func gitHubTable(_ table: Table) -> [String] {
      let columns = max(1, (table.header + table.rows).map(\.cells.count).max() ?? 1)
      var cellWriter = self
      cellWriter.isInTable = true
      func row(_ cells: [[Inline]]) -> String {
        let padded = cells + Array(repeating: [], count: columns - cells.count)
        return "| " + padded.map { cellWriter.inlines($0, breaks: " ") }.joined(separator: " | ")
          + " |"
      }
      let rowAnchors = (table.header + table.rows).flatMap { anchor($0.anchor) }
      let header = row(table.header.first?.cells ?? [])
      let rule = "|" + String(repeating: " --- |", count: columns)
      return rowAnchors + [header, rule] + table.rows.map { row($0.cells) }
    }

    /// Each row a list item of `header: cell` pairs, the way the reader stacks a
    /// table too wide or too tall for its columns.
    private func stackedTable(_ table: Table) -> [String] {
      let names = table.header.last?.cells.map { inlines($0, breaks: " ") } ?? []
      let rows = (table.header.count > 1 ? Array(table.header.dropLast()) : []) + table.rows
      return rows.flatMap { row -> [String] in
        let pairs = row.cells.enumerated().compactMap { column, cell -> String? in
          let value = inlines(Self.trimmingBreaks(cell), breaks: "\\\n")
          let name = column < names.count ? names[column] : ""
          guard !name.isEmpty else { return value.isEmpty ? nil : value }
          return "**\(name)**: \(value)"
        }
        let lines = pairs.joined(separator: "\\\n").split(separator: "\n").map {
          Self.escapingLineStart(String($0))
        }
        return Self.item("-", anchor(row.anchor) + lines)
      }
    }

    // MARK: References and the index

    func references(_ list: ReferenceList) -> [String] {
      let kind = ExportLinks.kindName(list.kind)
      return list.entries.flatMap { entry -> [String] in
        var parts = ["**" + Self.escaped("[\(entry.displayAnchor)]") + "**"]
        let title = entry.title.isEmpty ? (entry.rawText ?? "") : entry.title
        if let url = ExportLinks.url(of: entry), !title.isEmpty {
          parts.append(
            "[\(Self.escaped(Self.reflowed(title)))](\(Self.destination(url.absoluteString))).")
        } else if !title.isEmpty {
          parts.append(Self.escaped(Self.reflowed(title)) + ".")
        }
        let authors = entry.authors.map(\.displayName).joined(separator: ", ")
        if !authors.isEmpty { parts.append(Self.escaped(authors) + ".") }
        let provenance = entry.provenance(separator: ", ")
        if !provenance.isEmpty { parts.append(Self.escaped(provenance) + ".") }
        let annotation = inlines(entry.annotation, breaks: " ")
        if !annotation.isEmpty { parts.append(annotation) }
        if let kind { parts.append(kind + ".") }
        return Self.item("-", anchor(entry.anchor) + [parts.joined(separator: " ")])
      }
    }

    func index(_ index: IndexBlock) -> [String] {
      Self.lines(
        [anchor(IndexBlock.anchor)]
          + index.groups.map { group in
            Self.lines([
              anchor(group.anchor) + ["**" + Self.escaped(group.label) + "**"],
              definitionList(IndexBlock.definitionList(group.entries)),
            ])
          })
    }

    // MARK: Inlines

    /// `inlines` as one run of Markdown, a line break written as `breaks`, without
    /// the spaces it opens or closes with: a run is a paragraph, a cell or a term.
    func inlines(_ inlines: [Inline], breaks: String) -> String {
      run(inlines, breaks: breaks).trimmingCharacters(in: .whitespaces)
    }

    private func run(_ inlines: [Inline], breaks: String) -> String {
      var result = ""
      for inline in inlines {
        switch inline {
        case .text(let text):
          result += Self.escaped(Self.reflowed(text))
        case .emphasis(let inner):
          result += Self.wrapped(run(inner, breaks: breaks), in: "*", tag: "em")
        case .strong(let inner):
          result += Self.wrapped(run(inner, breaks: breaks), in: "**", tag: "strong")
        case .code(let code):
          let span = Self.codeSpan(code)
          result += isInTable ? span.replacingOccurrences(of: "|", with: "\\|") : span
        case .superscript(let text):
          result += "<sup>" + Self.escaped(text) + "</sup>"
        case .subscript(let text):
          result += "<sub>" + Self.escaped(text) + "</sub>"
        case .link(let url, let inner):
          let text = self.inlines(inner, breaks: " ")
          let label = text.isEmpty ? Self.escaped(url.absoluteString) : text
          result += "[\(label)](\(Self.destination(url.absoluteString)))"
        case .crossReference(let reference):
          let label = Self.escaped(Self.reflowed(reference.display.text))
          result += "[\(label)](\(Self.destination(links.href(for: reference))))"
        case .lineBreak:
          result += breaks
        }
      }
      return result
    }

    /// Runs of whitespace as one space: the source's line breaks are its layout.
    static func reflowed(_ text: String) -> String {
      var result = ""
      var inSpace = false
      for character in text {
        if character == " " || character == "\t" || character == "\n" || character == "\r" {
          if !inSpace { result.append(" ") }
          inSpace = true
        } else {
          result.append(character)
          inSpace = false
        }
      }
      return result
    }

    /// `text` between `delimiter`s, with the spaces it opens or closes with kept
    /// outside them, where CommonMark asks for them. Text that opens or closes with
    /// punctuation is put in `tag` instead: beside a letter outside it, CommonMark
    /// would not read the delimiters as emphasis, and would show them.
    static func wrapped(_ text: String, in delimiter: String, tag: String) -> String {
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      guard let first = trimmed.first, let last = trimmed.last else { return text }
      let leading = text.prefix { $0 == " " }
      let trailing = String(text.reversed().prefix { $0 == " " })
      if isPunctuation(first) || isPunctuation(last) {
        return leading + "<\(tag)>" + trimmed + "</\(tag)>" + trailing
      }
      return leading + delimiter + trimmed + delimiter + trailing
    }

    static func isPunctuation(_ character: Character) -> Bool {
      character.isPunctuation || character.isSymbol
    }

    static func codeSpan(_ code: String) -> String {
      let text = code.replacingOccurrences(of: "\n", with: " ")
      guard !text.isEmpty else { return "" }
      let fence = String(repeating: "`", count: longestRun(of: "`", in: text) + 1)
      let isAllSpaces = text.allSatisfy { $0 == " " }
      let needsPadding =
        text.hasPrefix("`") || text.hasSuffix("`")
        || (text.hasPrefix(" ") && text.hasSuffix(" ") && !isAllSpaces)
      let pad = needsPadding ? " " : ""
      return fence + pad + text + pad + fence
    }

    /// A link's destination, in angle brackets where it holds what would end it.
    static func destination(_ url: String) -> String {
      url.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(url)>" : url
    }

    // MARK: Escaping

    /// What Markdown would read as markup anywhere in a line.
    private static let markup: Set<Character> = [
      "\\", "`", "*", "_", "[", "]", "<", ">", "&", "|", "~",
    ]

    static func escaped(_ text: String) -> String {
      var result = ""
      for character in text {
        if markup.contains(character) { result.append("\\") }
        result.append(character)
      }
      return result
    }

    /// `line` without the indentation that would make it code, and with what would
    /// open a heading, a list or a setext underline escaped.
    static func escapingLineStart(_ line: String) -> String {
      let trimmed = line.drop { $0 == " " || $0 == "\t" }
      guard let first = trimmed.first else { return "" }
      if "#-+=".contains(first) { return "\\" + trimmed }
      let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
      if !digits.isEmpty, digits.count <= 9,
        let next = trimmed.dropFirst(digits.count).first, next == "." || next == ")"
      {
        return digits + "\\" + trimmed.dropFirst(digits.count)
      }
      return String(trimmed)
    }
  }
}
