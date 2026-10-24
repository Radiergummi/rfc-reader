import Foundation
import RFCKit

/// A document's highlights and notes as one Markdown file (#524), to take them
/// elsewhere: a front matter block naming the RFC, then every annotation in document
/// order, under the heading of the section it is in, each highlight a quote cited from
/// its section on rfc-editor.org with its notes after it; last, under "Not placed",
/// what is in the document nowhere.
///
/// An ambiguous highlight, whose passage is in several places, is left out, but its
/// notes are not: they come last, with its quote. The file leaves the app, so a note's
/// `rfc://` links become rfc-editor.org ones. Like the reader body, it is English.
///
/// Pure: it places the annotations in the document's model text, which needs no build.
public enum AnnotationExport {
  public static func markdown(
    of document: RFCDocument, id: DocumentID, annotations: AnnotationSnapshot,
    exported: Date, timeZone: TimeZone = .current
  ) -> String {
    let highlights = annotations.highlights(of: id)
    let notes = annotations.notes(of: id)
    let model = ModelText(document)
    let highlightPlacement = HighlightPlacement(highlights, in: model)
    let notePlacement = NotePlacement(notes, highlights: highlightPlacement, in: model)

    var notesOnHighlight: [UUID: [AnnotationSnapshot.NoteEntry]] = [:]
    var ownNotes: [AnnotationSnapshot.NoteEntry] = []
    for note in notes {
      if case .onHighlight(let highlight)? = notePlacement.statuses[note.id] {
        notesOnHighlight[highlight, default: []].append(note)
      } else {
        ownNotes.append(note)
      }
    }

    let writer = Writer(document: document, id: id)
    var placed: [Placed] = []
    var unplaced: [String] = []
    for highlight in highlights {
      let itsNotes = notesOnHighlight[highlight.id] ?? []
      switch highlightPlacement.statuses[highlight.id] {
      case .placed(let range, _, let section)?:
        placed.append(
          Placed(
            start: range.lowerBound, isSectionNote: false, createdAt: highlight.createdAt,
            section: section,
            text: writer.highlight(passages(range, in: model), section: section, notes: itsNotes)))
      case .ambiguous?:
        if !itsNotes.isEmpty {
          unplaced.append(
            writer.highlight([Passage(highlight.quote.exact)], section: nil, notes: itsNotes))
        }
      case .detached?, nil:
        unplaced.append(
          writer.highlight([Passage(highlight.quote.exact)], section: nil, notes: itsNotes))
      }
    }
    for note in ownNotes {
      if case .placed(let range, let section)? = notePlacement.statuses[note.id] {
        // A section's note sits under its heading; a block's says which block, as a
        // highlight does.
        let isSection = if case .section? = note.current { true } else { false }
        placed.append(
          Placed(
            start: range.lowerBound, isSectionNote: isSection, createdAt: note.createdAt,
            section: section,
            text: isSection
              ? writer.body(of: note)
              : writer.highlight(passages(range, in: model), section: section, notes: [note])))
      } else {
        // Where it was found last, should it have been since it was made.
        let quote = if case .range(_, _, let quote)? = note.current { quote.exact } else { "" }
        unplaced.append(writer.highlight([Passage(quote)], section: nil, notes: [note]))
      }
    }

    var parts = [frontMatter(document: document, id: id, exported: exported, timeZone: timeZone)]
    // The section whose heading was written last: nil before any, and nil inside once
    // an annotation in no section was.
    var section: String??
    // The annotations of one place in the order they were made, a section's own note
    // ahead of whatever starts with it.
    for item in placed.sorted(by: {
      ($0.start, $0.isSectionNote ? 0 : 1, $0.createdAt) < (
        $1.start, $1.isSectionNote ? 0 : 1, $1.createdAt
      )
    }) {
      let heading = section != .some(item.section) ? writer.heading(of: item.section) : nil
      if let heading {
        parts.append(heading)
      } else if section != nil {
        // After an entry, under no new heading: a section that has none, too.
        parts.append(Self.entryBreak)
      }
      section = item.section
      parts.append(item.text)
    }
    if !unplaced.isEmpty {
      parts.append("## Not placed")
      parts.append(unplaced.joined(separator: "\n\n" + Self.entryBreak + "\n\n"))
    }
    // Not where there are only ambiguous highlights without notes, which are left out.
    if highlights.isEmpty && notes.isEmpty { parts.append("No highlights or notes.") }
    return parts.joined(separator: "\n\n") + "\n"
  }

  /// Between two entries under one heading, and two notes of one highlight, so that
  /// a note's list does not run on into the next one's, nor a quote-less note read as
  /// the entry before's. Parts are joined by a blank line, so it is never taken for a
  /// heading's underline.
  static let entryBreak = "---"

  /// What a quote says, and whether it is a figure's or code's, whose lines are kept as
  /// they are; nil where only the stored quote is known, which says so by an indented
  /// line.
  struct Passage {
    let text: String
    let isVerbatim: Bool?

    init(_ text: String, isVerbatim: Bool? = nil) {
      self.text = text
      self.isVerbatim = isVerbatim
    }
  }

  /// The passages at `range`, split as Copy as Quote splits a selection: prose apart
  /// from a figure's or code's lines, which start from the start of their first line,
  /// whose indentation a highlight snapped to words leaves out.
  private static func passages(_ range: Range<Int>, in model: ModelText) -> [Passage] {
    var passages: [Passage] = []
    var start = range.lowerBound
    func prose(until end: Int) {
      guard start < end else { return }
      let text = model.text(in: start..<end)
      if text.contains(where: { !$0.isWhitespace }) {
        passages.append(Passage(text, isVerbatim: false))
      }
    }
    for block in model.verbatim where block.overlaps(range) {
      prose(until: block.lowerBound)
      let end = min(block.upperBound, range.upperBound)
      passages.append(
        Passage(
          model.text(in: lineStart(max(block.lowerBound, start), in: model)..<end), isVerbatim: true
        ))
      start = end
    }
    prose(until: range.upperBound)
    return passages
  }

  /// `offset`, or where its line starts when only spaces and tabs come before it there.
  private static func lineStart(_ offset: Int, in model: ModelText) -> Int {
    let space: UInt16 = 0x20
    let tab: UInt16 = 0x09
    let newline: UInt16 = 0x0A
    var start = offset
    while start > 0, model.units[start - 1] == space || model.units[start - 1] == tab {
      start -= 1
    }
    return start > 0 && model.units[start - 1] != newline ? offset : start
  }

  /// One annotation placed in the document, as it is written.
  private struct Placed {
    /// Where it starts in the model text.
    let start: Int
    /// Whether it is a note on its section, which comes ahead of what starts with it.
    let isSectionNote: Bool
    let createdAt: Date
    /// The section, or the abstract, it starts in.
    let section: String?
    let text: String
  }

  /// The number, the title and the day exported, as YAML.
  private static func frontMatter(
    document: RFCDocument, id: DocumentID, exported: Date, timeZone: TimeZone
  ) -> String {
    let day = exported.formatted(
      Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    return [
      "---",
      "\(id.series.rawValue.lowercased()): \(id.number)",
      "title: \(quoted(document.header.title))",
      "exported: \(day)",
      "---",
    ].joined(separator: "\n")
  }

  /// `text` as a double-quoted YAML string.
  static func quoted(_ text: String) -> String {
    let escaped =
      text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
    return "\"\(escaped)\""
  }

  /// What one export writes its parts with.
  private struct Writer {
    let document: RFCDocument
    let id: DocumentID

    /// The heading of the section, or the abstract, whose anchor is `anchor`; nil for
    /// none.
    func heading(of anchor: String?) -> String? {
      guard let anchor else { return nil }
      if anchor == ModelText.abstractAnchor { return "## Abstract" }
      return document.section(anchor: anchor).map { "## " + Self.escaped($0.displayTitle) }
    }

    /// A quote of `passages`, cited from `section` when it has a place, then `notes`'
    /// bodies.
    func highlight(
      _ passages: [Passage], section: String?, notes: [AnnotationSnapshot.NoteEntry]
    ) -> String {
      var parts: [String] = []
      let quoted = passages.filter { !$0.text.isEmpty }.map(Self.blockQuote)
      if !quoted.isEmpty { parts.append(quoted.joined(separator: "\n>\n")) }
      if let section { parts.append("— " + citation(of: section)) }
      if !notes.isEmpty {
        parts.append(
          notes.map(body(of:)).joined(separator: "\n\n" + AnnotationExport.entryBreak + "\n\n"))
      }
      return parts.joined(separator: "\n\n")
    }

    /// `[RFC 9110, Section 4.2](…)`, or the document alone for the abstract or a
    /// section with no number, as Copy as Quote cites them.
    private func citation(of section: String) -> String {
      let place = document.section(anchor: section)?.place
      // The citation reads only the number.
      let metadata = RFCMetadata(id: id, title: "", date: PublicationDate(year: 0))
      return CitationFormatter.cite(metadata, section: place, style: .markdown)
    }

    /// The quote, as Copy as Quote writes one. Prose is a paragraph a line, with a
    /// `<` as an entity, or a Markdown renderer takes `<field-name>` for a tag. A
    /// figure's, code's or a grammar's, whose columns and lines are its meaning, is
    /// fenced, with its lines as they are, so Markdown neither reflows them nor reads
    /// them as its own; a stored quote alone is taken for one by an indented line.
    static func blockQuote(_ quote: Passage) -> String {
      let lines = quote.text.components(separatedBy: "\n").map { $0.trimmingTrailingSpaces() }
      let isVerbatim =
        quote.isVerbatim ?? lines.contains { $0.first == " " || $0.first == "\t" }
      guard isVerbatim else {
        return lines.filter { !$0.isEmpty }
          .map { "> " + escaped($0) }
          .joined(separator: "\n>\n")
      }
      // Longer than any run of backticks in it, or a line of it would close the fence.
      let fence = String(
        repeating: "`", count: max(3, QuoteCitation.longestBacktickRun(in: lines) + 1))
      return ([fence] + lines + [fence]).map { $0.isEmpty ? ">" : "> " + $0 }
        .joined(separator: "\n")
    }

    /// Prose with its `<` an entity.
    private static func escaped(_ text: String) -> String {
      text.replacingOccurrences(of: "<", with: "&lt;")
    }

    /// A note's Markdown, with its `rfc://` links made rfc-editor.org ones.
    func body(of note: AnnotationSnapshot.NoteEntry) -> String {
      let body = NoteBody(markdown: note.body)
      return NoteBody(body.blocks.map(Self.webLinks)).markdown
    }

    private static func webLinks(_ block: NoteBody.Block) -> NoteBody.Block {
      switch block {
      case .paragraph(let spans): .paragraph(spans.map(webLink))
      case .list(let list): .list(webLinks(list))
      }
    }

    private static func webLinks(_ list: NoteBody.List) -> NoteBody.List {
      NoteBody.List(
        isOrdered: list.isOrdered,
        items: list.items.map {
          NoteBody.Item($0.spans.map(webLink), lists: $0.lists.map(webLinks))
        })
    }

    /// An `rfc://` link as the RFC Editor's, or as plain text when it names nothing
    /// there, since outside the app it would lead nowhere.
    private static func webLink(_ span: NoteBody.Span) -> NoteBody.Span {
      guard let url = span.link, url.scheme == RFCLink.scheme else { return span }
      return NoteBody.Span(span.text, style: span.style, link: RFCLink(url: url)?.webURL)
    }
  }
}
