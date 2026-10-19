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
      let notes = notesOnHighlight[highlight.id] ?? []
      switch highlightPlacement.statuses[highlight.id] {
      case .placed(let range, _, let section)?:
        placed.append(
          Placed(
            start: range.lowerBound, isSectionNote: false, createdAt: highlight.createdAt,
            section: section,
            text: writer.highlight(quote: model.text(in: range), section: section, notes: notes)))
      case .ambiguous?:
        if !notes.isEmpty {
          unplaced.append(
            writer.highlight(quote: highlight.quote.exact, section: nil, notes: notes))
        }
      case .detached?, nil:
        unplaced.append(writer.highlight(quote: highlight.quote.exact, section: nil, notes: notes))
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
              : writer.highlight(quote: model.text(in: range), section: section, notes: [note])))
      } else {
        let quote = if case .range(_, _, let quote)? = note.target { quote.exact } else { "" }
        unplaced.append(writer.highlight(quote: quote, section: nil, notes: [note]))
      }
    }

    var parts = [frontMatter(document: document, id: id, exported: exported, timeZone: timeZone)]
    var section: String??
    // The annotations of one place in the order they were made, a section's own note
    // ahead of whatever starts with it.
    for item in placed.sorted(by: {
      ($0.start, $0.isSectionNote ? 0 : 1, $0.createdAt) < (
        $1.start, $1.isSectionNote ? 0 : 1, $1.createdAt
      )
    }) {
      if section != .some(item.section) {
        section = item.section
        if let heading = writer.heading(of: item.section) { parts.append(heading) }
      }
      parts.append(item.text)
    }
    if !unplaced.isEmpty {
      parts.append("## Not placed")
      parts.append(contentsOf: unplaced)
    }
    if parts.count == 1 { parts.append("No highlights or notes.") }
    return parts.joined(separator: "\n\n") + "\n"
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

    /// A quote, cited from `section` when it has a place, then `notes`' bodies.
    func highlight(quote: String, section: String?, notes: [AnnotationSnapshot.NoteEntry])
      -> String
    {
      var parts: [String] = []
      if !quote.isEmpty { parts.append(Self.blockQuote(quote)) }
      if let section { parts.append("— " + citation(of: section)) }
      parts.append(contentsOf: notes.map(body(of:)))
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
    /// `<` as an entity, or a Markdown renderer takes `<field-name>` for a tag. A quote
    /// with an indented line is of a figure, code or a grammar, whose columns and
    /// lines are its meaning: fenced, with its lines as they are, so Markdown neither
    /// reflows them nor reads them as its own.
    static func blockQuote(_ text: String) -> String {
      let lines = text.components(separatedBy: "\n").map(trimmingTrailingSpaces)
      let isVerbatim = lines.contains { $0.first == " " || $0.first == "\t" }
      guard isVerbatim else {
        return lines.filter { !$0.isEmpty }
          .map { "> " + escaped($0) }
          .joined(separator: "\n>\n")
      }
      // Longer than any run of backticks in it, or a line of it would close the fence.
      var longest = 0
      for line in lines {
        var run = 0
        for character in line {
          run = character == "`" ? run + 1 : 0
          longest = max(longest, run)
        }
      }
      let fence = String(repeating: "`", count: max(3, longest + 1))
      return ([fence] + lines + [fence]).map { $0.isEmpty ? ">" : "> " + $0 }
        .joined(separator: "\n")
    }

    private static func trimmingTrailingSpaces(_ line: String) -> String {
      var line = line
      while line.last == " " || line.last == "\t" { line.removeLast() }
      return line
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
