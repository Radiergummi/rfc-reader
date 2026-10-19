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

    let writer = Writer(document: document, id: id, model: model)
    var placed: [(start: Int, isSection: Bool, section: String?, text: String)] = []
    var unplaced: [String] = []
    for highlight in highlights {
      let notes = notesOnHighlight[highlight.id] ?? []
      switch highlightPlacement.statuses[highlight.id] {
      case .placed(let range, _, let section)?:
        placed.append(
          (
            range.lowerBound, false, section,
            writer.highlight(quote: model.text(in: range), section: section, notes: notes)
          ))
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
        let isSection = if case .section? = note.current { true } else { false }
        placed.append((range.lowerBound, isSection, section, writer.body(of: note)))
      } else {
        let quote = if case .range(_, _, let quote)? = note.target { quote.exact } else { "" }
        unplaced.append(writer.highlight(quote: quote, section: nil, notes: [note]))
      }
    }

    var parts = [frontMatter(document: document, id: id, exported: exported, timeZone: timeZone)]
    var section: String??
    // Stable, so the annotations of one place keep the order they were made in; a
    // section's own note ahead of whatever starts with it.
    for item in placed.enumerated().sorted(by: {
      ($0.element.start, $0.element.isSection ? 0 : 1, $0.offset)
        < ($1.element.start, $1.element.isSection ? 0 : 1, $1.offset)
    }).map(\.element) {
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
    let model: ModelText

    /// The heading of the section, or the abstract, whose anchor is `anchor`; nil for
    /// none.
    func heading(of anchor: String?) -> String? {
      guard let anchor else { return nil }
      if anchor == ModelText.abstractAnchor { return "## Abstract" }
      return document.section(anchor: anchor).map { "## \($0.displayTitle)" }
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

    /// Each line its own paragraph of the quote. A `<` is an entity, as Copy as Quote
    /// writes it, or a Markdown renderer takes `<field-name>` for a tag.
    private static func blockQuote(_ text: String) -> String {
      text.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map { "> " + $0.replacingOccurrences(of: "<", with: "&lt;") }
        .joined(separator: "\n>\n")
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

    private static func webLink(_ span: NoteBody.Span) -> NoteBody.Span {
      guard let url = span.link, url.scheme == RFCLink.scheme, let link = RFCLink(url: url)
      else { return span }
      return NoteBody.Span(span.text, style: span.style, link: link.webURL)
    }
  }
}
