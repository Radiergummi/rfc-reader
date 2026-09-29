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

  /// What the status means, in a sentence, for the header; nil when the index
  /// does not know it.
  public var statusSummary: String? { Self.summary(of: status) }

  /// The header's second box, for a document a later one replaces.
  public var obsoleteSummary: String? {
    isObsolete ? "A later RFC replaces it; Relationships names which." : nil
  }

  public struct Section: Equatable, Sendable {
    public let title: String
    public let style: Style
    public let rows: [Row]
  }

  /// How a section is set: links and files as a card of rows with an icon, as
  /// Settings and the App Store set theirs; everything else as captioned values.
  public enum Style: Equatable, Sendable {
    case list
    case card
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
    /// Internet-Drafts, each opening its datatracker page in the browser.
    case drafts([RevisionsSummary.Line])
    /// A page elsewhere.
    case link(URL)
    /// A format of the document, where the RFC Editor hosts it
    /// (`RFCEditorEndpoints.document`): opened in the browser, or saved to Downloads
    /// with Option.
    case file(DocumentID, FileFormat)
    /// Keywords, set as tags, each searching the library for itself.
    case keywords([String])
    /// People, drawn as the header's chips (#19).
    case authors([Author])
  }

  /// - Parameter authors: the document's own, once it is here: they carry the
  ///   contact details a chip opens, which the index never has. The index's names
  ///   stand in until then, as they do in the header.
  /// - Parameter revisions: the drafts revising this document, from `revisions.json`;
  ///   nil or empty adds no rows.
  public init(
    _ metadata: RFCMetadata, authors: [Author]? = nil, in index: RFCIndex?,
    revisions: RevisionsSummary? = nil
  ) {
    number = metadata.id.displayName
    title = metadata.title
    status = metadata.currentStatus
    isObsolete = metadata.isObsolete
    facts = Self.facts(metadata)
    sections = [
      Self.section("Authors", .list, Self.authors(authors, else: metadata.authors)),
      Self.section(
        "Relationships", .list, Self.relationships(metadata, index: index, revisions: revisions)),
      Self.section("Links", .card, Self.links(metadata)),
      Self.section("Formats", .card, Self.formats(metadata)),
      Self.section("Details", .list, Self.details(metadata)),
    ].compactMap { $0 }
  }

  private static func section(_ title: String, _ style: Style, _ rows: [Row]) -> Section? {
    rows.isEmpty ? nil : Section(title: title, style: style, rows: rows)
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
      // "Working Group" is wider than a quarter of the panel.
      facts.append(Fact(value: group, label: "Group"))
    }
    return facts
  }

  private static func authors(_ own: [Author]?, else indexed: [Author]) -> [Row] {
    let authors = own.flatMap { $0.isEmpty ? nil : $0 } ?? indexed
    return authors.isEmpty ? [] : [Row(label: "", value: .authors(authors))]
  }

  /// Each relationship is a list, not a sentence: "obsoletes RFC 2616, 7230, 7231,
  /// 7232, 7233, 7234, 7235" needs the room. A series lists its other members, as
  /// the index records them, and not this document again.
  private static func relationships(
    _ metadata: RFCMetadata, index: RFCIndex?, revisions: RevisionsSummary?
  ) -> [Row] {
    var rows: [Row] = []
    for (label, documents) in [
      ("Obsoletes", metadata.obsoletes),
      ("Obsoleted by", metadata.obsoletedBy),
      ("Updates", metadata.updates),
      ("Updated by", metadata.updatedBy),
    ] where !documents.isEmpty {
      rows.append(Row(label: label, value: .documents(documents)))
    }
    for relation in [RevisionRelation.obsoletes, .updates] {
      let lines = revisions?.inspectorLines(relation) ?? []
      if !lines.isEmpty {
        rows.append(Row(label: RevisionsSummary.relationLabel(relation), value: .drafts(lines)))
      }
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

  /// Each format the RFC Editor publishes, set as the links are: the file where it
  /// is hosted, which the reader already keeps its own copy of the text of.
  private static func formats(_ metadata: RFCMetadata) -> [Row] {
    metadata.formats.map { format in
      let (label, symbol) =
        switch format {
        case .text: ("Plain Text", "doc.plaintext")
        case .html: ("HTML", "doc.richtext")
        case .xml: ("XML", "chevron.left.forwardslash.chevron.right")
        case .pdf: ("PDF", "doc.text")
        case .postScript: ("PostScript", "doc.text")
        }
      return Row(label: label, value: .file(metadata.id, format), symbol: symbol)
    }
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
      rows.append(Row(label: "Area", value: .text(areaName(area))))
    }
    if !metadata.keywords.isEmpty {
      rows.append(Row(label: "Keywords", value: .keywords(metadata.keywords)))
    }
    return rows
  }

  /// The status in a sentence: the name alone is jargon to most readers.
  private static func summary(of status: PublicationStatus) -> String? {
    switch status {
    case .internetStandard:
      "The IETF's highest maturity level: a stable standard, widely implemented and deployed."
    case .draftStandard:
      "A standard at a maturity level the IETF has since retired, between Proposed and Internet Standard."
    case .proposedStandard:
      "A standard the IETF has approved. Most of the Internet's standards remain at this level."
    case .bestCurrentPractice:
      "Guidance the IETF recommends, for operating the Internet or for its own processes."
    case .informational:
      "Published for information. Not a standard, and not a recommendation."
    case .experimental:
      "Published for experimentation and evaluation. Not a standard."
    case .historic:
      "Superseded or no longer in use, kept for the record."
    case .unknown:
      nil
    }
  }

  /// An area's name for the short code the index records it by, or the code in
  /// capitals, as the IETF writes it, for one this list does not know.
  public static func areaName(_ code: String) -> String {
    switch code.lowercased() {
    case "app": "Applications"
    case "art": "Applications and Real-Time"
    case "gen": "General"
    case "int": "Internet"
    case "ops": "Operations and Management"
    case "rai": "Real-Time Applications and Infrastructure"
    case "rtg": "Routing"
    case "sec": "Security"
    case "sub": "Sub-IP"
    case "tsv": "Transport"
    case "usv": "User Services"
    case "wit": "Web and Internet Transport"
    default: code.uppercased()
    }
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
