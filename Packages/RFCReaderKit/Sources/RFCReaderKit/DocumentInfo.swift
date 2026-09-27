import Foundation
import RFCKit

/// The inspector's Info tab (#25): everything the index knows about a document that
/// is not its prose, as titled sections of labelled rows.
///
/// A field the index does not have gets no row, and a section left with no rows is
/// not shown, so a legacy document's tab is short rather than a column of dashes.
/// Derived once per document rather than in a view body, which the reader
/// re-evaluates on every section crossing.
public enum DocumentInfo {
  public struct Section: Equatable, Sendable {
    public let title: String
    public let rows: [Row]
  }

  public struct Row: Equatable, Sendable {
    /// Empty for a row that needs none, such as an author with no role.
    public let label: String
    public let value: Value
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

  public static func sections(for metadata: RFCMetadata, in index: RFCIndex?) -> [Section] {
    [
      section("Document", document(metadata)),
      section("Authors", metadata.authors.map { Row(label: role($0), value: .text($0.name)) }),
      section("Status", status(metadata)),
      section("Relationships", relationships(metadata, index: index)),
      section("Links", links(metadata)),
    ].compactMap { $0 }
  }

  /// "Editor" is the one role the index and both parsers record, and it is read the
  /// way `CitationFormatter` reads it, so "Ed." counts too.
  private static func role(_ author: Author) -> String {
    author.role?.lowercased().hasPrefix("ed") == true ? "Editor" : ""
  }

  private static func section(_ title: String, _ rows: [Row]) -> Section? {
    rows.isEmpty ? nil : Section(title: title, rows: rows)
  }

  private static func document(_ metadata: RFCMetadata) -> [Row] {
    var rows = [
      Row(label: "Number", value: .text(metadata.id.displayName)),
      Row(label: "Published", value: .text(metadata.date.formatted)),
    ]
    if let pages = metadata.pageCount {
      rows.append(Row(label: "Pages", value: .text(String(pages))))
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

  /// The status it was published with only where it differs from today's: that is
  /// the interesting case, a Proposed Standard since advanced, or a document since
  /// made historic.
  private static func status(_ metadata: RFCMetadata) -> [Row] {
    var rows: [Row] = []
    if metadata.currentStatus != .unknown {
      rows.append(Row(label: "Status", value: .text(metadata.currentStatus.displayName)))
    }
    let original = metadata.publicationStatus
    if original != .unknown, original != metadata.currentStatus {
      rows.append(Row(label: "Published as", value: .text(original.displayName)))
    }
    rows.append(Row(label: "Stream", value: .text(metadata.stream.displayName)))
    if let group = metadata.workingGroup {
      rows.append(Row(label: "Working group", value: .text(group)))
    }
    if let area = metadata.area { rows.append(Row(label: "Area", value: .text(area))) }
    return rows
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
        index?.series.first { $0.id == series }?.members.filter { $0 != metadata.id } ?? []
      if !others.isEmpty {
        rows.append(Row(label: "Part of \(series.displayName)", value: .documents(others)))
      }
    }
    return rows
  }

  /// The same pages the More menu opens, so the two read them from one place.
  private static func links(_ metadata: RFCMetadata) -> [Row] {
    var rows: [Row] = []
    if let doi = metadata.doi { rows.append(Row(label: "DOI", value: .copyable(doi))) }
    if let errata = metadata.errataURL { rows.append(Row(label: "Errata", value: .link(errata))) }
    rows.append(Row(label: "RFC Editor", value: .link(RFCEditorEndpoints.infoPage(metadata.id))))
    rows.append(
      Row(label: "Datatracker", value: .link(RFCEditorEndpoints.datatracker(metadata.id))))
    return rows
  }
}
