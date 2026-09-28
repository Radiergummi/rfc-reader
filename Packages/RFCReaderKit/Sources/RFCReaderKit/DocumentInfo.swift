import Foundation
import RFCKit

/// The Info inspector (#25): everything the index knows about a document that is
/// not its prose.
///
/// Laid out the way Books and the App Store present an item: a header naming it
/// and its standing, a strip of the few facts someone looks for first, and then
/// sections. A field the index does not have gets no fact or row, and a section
/// left with no rows is not shown, so a legacy document's panel is short rather
/// than a column of dashes. Derived once per document rather than in a view body,
/// which the reader re-evaluates on every section crossing.
public struct DocumentInfo: Equatable, Sendable {
  /// "RFC 9110".
  public let number: String
  public let title: String
  /// Today's status, for the header's badge.
  public let status: PublicationStatus
  public let isObsolete: Bool
  /// When, how long, from whom and which group: each a word or two over a caption.
  public let facts: [Fact]
  public let sections: [Section]

  public struct Fact: Equatable, Sendable {
    public let value: String
    public let label: String
  }

  public struct Section: Equatable, Sendable {
    public let title: String
    public let rows: [Row]
  }

  public struct Row: Equatable, Sendable {
    /// Empty for a row that needs none, such as an author.
    public let label: String
    public let value: Value
    /// An SF Symbol, for a link row.
    public let symbol: String?

    public init(label: String, value: Value, symbol: String? = nil) {
      self.label = label
      self.value = value
      self.symbol = symbol
    }
  }

  public enum Value: Equatable, Sendable {
    case text(String)
    /// An identifier worth copying, such as the DOI.
    case copyable(String)
    /// Other documents, opened in the reader the way a reference is.
    case documents([DocumentID])
    /// A page elsewhere.
    case link(URL)
  }

  public init(_ metadata: RFCMetadata, in index: RFCIndex?) {
    number = metadata.id.displayName
    title = metadata.title
    status = metadata.currentStatus
    isObsolete = metadata.isObsolete
    facts = Self.facts(metadata)
    sections = [
      Self.section("Authors", metadata.authors.map(Self.author)),
      Self.section("Relationships", Self.relationships(metadata, index: index)),
      Self.section("Links", Self.links(metadata)),
      Self.section("Details", Self.details(metadata)),
    ].compactMap { $0 }
  }

  private static func section(_ title: String, _ rows: [Row]) -> Section? {
    rows.isEmpty ? nil : Section(title: title, rows: rows)
  }

  private static func facts(_ metadata: RFCMetadata) -> [Fact] {
    var facts = [Fact(value: String(metadata.date.year), label: "Published")]
    if let pages = metadata.pageCount {
      facts.append(Fact(value: String(pages), label: "Pages"))
    }
    // "Independent Submission" does not fit a quarter of the panel.
    let stream = metadata.stream == .independent ? "Independent" : metadata.stream.displayName
    facts.append(Fact(value: stream, label: "Stream"))
    if let group = metadata.namedWorkingGroup {
      facts.append(Fact(value: group, label: "Working Group"))
    }
    return facts
  }

  /// "Editor" is the one role the index and both parsers record.
  private static func author(_ author: Author) -> Row {
    Row(label: "", value: .text(author.isEditor ? "\(author.name), Ed." : author.name))
  }

  /// Each relationship is a list, not a sentence: "obsoletes RFC 2616, 7230, 7231,
  /// 7232, 7233, 7234, 7235" needs the room. A series lists its other members, as
  /// the index records them, and not this document again.
  private static func relationships(_ metadata: RFCMetadata, index: RFCIndex?) -> [Row] {
    var rows: [Row] = []
    for (label, documents) in [
      ("Obsoletes", metadata.obsoletes),
      ("Obsoleted by", metadata.obsoletedBy),
      ("Updates", metadata.updates),
      ("Updated by", metadata.updatedBy),
    ] where !documents.isEmpty {
      rows.append(Row(label: label, value: .documents(documents)))
    }
    for series in metadata.isAlso {
      let others =
        index?.series(series)?.members.filter { $0 != metadata.id } ?? []
      if !others.isEmpty {
        rows.append(Row(label: "Part of \(series.displayName)", value: .documents(others)))
      }
    }
    return rows
  }

  /// The pages the More menu opens, from the same `RFCEditorEndpoints`, and the DOI.
  private static func links(_ metadata: RFCMetadata) -> [Row] {
    var rows: [Row] = []
    if let errata = metadata.errataURL {
      rows.append(Row(label: "Errata", value: .link(errata), symbol: "exclamationmark.bubble"))
    }
    rows.append(
      Row(
        label: "RFC Editor", value: .link(RFCEditorEndpoints.infoPage(metadata.id)),
        symbol: "globe"))
    rows.append(
      Row(
        label: "Datatracker", value: .link(RFCEditorEndpoints.datatracker(metadata.id)),
        symbol: "chart.bar.doc.horizontal"))
    if let doi = metadata.doi {
      rows.append(Row(label: "DOI", value: .copyable(doi), symbol: "link"))
    }
    return rows
  }

  /// What the header and the strip leave out. The status it was published with
  /// only where it differs from today's: that is the interesting case, a Proposed
  /// Standard since advanced, or a document since made historic.
  private static func details(_ metadata: RFCMetadata) -> [Row] {
    var rows = [Row(label: "Published", value: .text(metadata.date.formatted))]
    let original = metadata.publicationStatus
    if original != .unknown, original != metadata.currentStatus {
      rows.append(Row(label: "Published as", value: .text(original.displayName)))
    }
    if let area = metadata.area {
      rows.append(Row(label: "Area", value: .text(area)))
    }
    if !metadata.keywords.isEmpty {
      rows.append(Row(label: "Keywords", value: .text(metadata.keywords.joined(separator: ", "))))
    }
    if !metadata.formats.isEmpty {
      rows.append(
        Row(
          label: "Formats", value: .text(metadata.formats.map(\.rawValue).joined(separator: ", "))))
    }
    return rows
  }
}

/// The inspector's two panes, which share one slot beside the reader: the
/// document's navigation (contents and references) and what is known about it.
///
/// Each has its own toolbar button, and they behave as Pages' Format and Document
/// buttons do: a button opens a closed inspector on its pane, swaps an open one to
/// it, and closes the inspector when its pane is already showing.
public enum InspectorPane: Sendable {
  case navigation
  case info

  /// What pressing `pressed`'s button does to an inspector that is `isOpen`,
  /// `showing` a pane. Closing keeps the pane, so the next open shows it again.
  public static func pressing(
    _ pressed: InspectorPane, isOpen: Bool, showing: InspectorPane
  ) -> (isOpen: Bool, pane: InspectorPane) {
    if isOpen, showing == pressed { return (false, showing) }
    return (true, pressed)
  }
}
