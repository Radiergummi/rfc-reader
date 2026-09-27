import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The inspector's Info tab (#25): everything the index knows about a document that
/// is not its prose, in sections, with nothing shown for what it does not know.
@Suite("Document info")
struct DocumentInfoTests {
  private let rich = RFCMetadata(
    id: .rfc(9110),
    title: "HTTP Semantics",
    authors: [Author(name: "R. Fielding", role: "editor"), Author(name: "M. Nottingham")],
    date: PublicationDate(year: 2022, month: 6),
    formats: [.text, .html, .xml, .pdf],
    pageCount: 194,
    keywords: ["HTTP", "semantics"],
    isAlso: [DocumentID(series: .std, number: 97)],
    obsoletes: [.rfc(2818), .rfc(7230)],
    updatedBy: [.rfc(9204)],
    currentStatus: .internetStandard,
    publicationStatus: .proposedStandard,
    stream: .ietf,
    area: "art",
    workingGroup: "httpbis",
    errataURL: URL(string: "https://www.rfc-editor.org/errata/rfc9110"),
    doi: "10.17487/RFC9110"
  )

  private let bare = RFCMetadata(id: .rfc(1149), title: "IP over Avian Carriers", date: PublicationDate(year: 1990, month: 4))

  private var index: RFCIndex {
    RFCIndex(
      rfcs: [rich, bare],
      series: [SeriesEntry(id: DocumentID(series: .std, number: 97), members: [.rfc(9110), .rfc(9111)])])
  }

  private func section(_ title: String, of metadata: RFCMetadata) -> DocumentInfo.Section? {
    DocumentInfo.sections(for: metadata, in: index).first { $0.title == title }
  }

  private func value(_ label: String, in section: DocumentInfo.Section?) -> DocumentInfo.Value? {
    section?.rows.first { $0.label == label }?.value
  }

  @Test func `the sections come in a fixed order`() {
    #expect(
      DocumentInfo.sections(for: rich, in: index).map(\.title)
        == ["Document", "Authors", "Status", "Relationships", "Links"])
  }

  @Test func `the document section says what and when`() {
    let document = section("Document", of: rich)
    #expect(value("Number", in: document) == .text("RFC 9110"))
    #expect(value("Published", in: document) == .text("June 2022"))
    #expect(value("Pages", in: document) == .text("194"))
    #expect(value("Keywords", in: document) == .text("HTTP, semantics"))
    #expect(value("Formats", in: document) == .text("TXT, HTML, XML, PDF"))
  }

  @Test func `authors are listed with their role`() {
    #expect(
      section("Authors", of: rich)?.rows
        == [
          DocumentInfo.Row(label: "Editor", value: .text("R. Fielding")),
          DocumentInfo.Row(label: "", value: .text("M. Nottingham")),
        ])
  }

  /// The status it was published with only where it differs from the current one:
  /// RFC 9110 went out a Proposed Standard and is an Internet Standard now.
  @Test func `the original status is shown only where it differs`() {
    let status = section("Status", of: rich)
    #expect(value("Status", in: status) == .text(PublicationStatus.internetStandard.displayName))
    #expect(value("Published as", in: status) == .text(PublicationStatus.proposedStandard.displayName))
    #expect(value("Stream", in: status) == .text("IETF"))
    #expect(value("Working group", in: status) == .text("httpbis"))
    #expect(value("Area", in: status) == .text("art"))

    var unchanged = rich
    unchanged.publicationStatus = unchanged.currentStatus
    let rows = DocumentInfo.sections(for: unchanged, in: index).first { $0.title == "Status" }?.rows
    #expect(rows?.contains { $0.label == "Published as" } == false)
  }

  /// A series member links to the others, not to itself.
  @Test func `relationships are links, and a series lists its other members`() {
    let relationships = section("Relationships", of: rich)
    #expect(value("Obsoletes", in: relationships) == .documents([.rfc(2818), .rfc(7230)]))
    #expect(value("Updated by", in: relationships) == .documents([.rfc(9204)]))
    #expect(value("Part of STD 97", in: relationships) == .documents([.rfc(9111)]))
    #expect(value("Obsoleted by", in: relationships) == nil)
  }

  @Test func `identifiers and pages elsewhere are links`() {
    let links = section("Links", of: rich)
    #expect(value("DOI", in: links) == .copyable("10.17487/RFC9110"))
    #expect(value("Errata", in: links) == .link(URL(string: "https://www.rfc-editor.org/errata/rfc9110")!))
    #expect(value("RFC Editor", in: links) == .link(RFCEditorEndpoints.infoPage(.rfc(9110))))
    #expect(value("Datatracker", in: links) == .link(RFCEditorEndpoints.datatracker(.rfc(9110))))
  }

  /// A legacy document knows little, and its tab is short rather than full of
  /// dashes: an empty field has no row, and a section with no rows is not shown.
  @Test func `what is not known is not shown`() {
    let sections = DocumentInfo.sections(for: bare, in: index)
    #expect(sections.map(\.title) == ["Document", "Status", "Links"])
    let rows = sections.flatMap(\.rows).map(\.label)
    for absent in ["Pages", "Keywords", "Formats", "Working group", "Area", "DOI", "Errata", "Published as"] {
      #expect(!rows.contains(absent), "\(absent) shown for a document that has none")
    }
  }

  @Test func `without an index a series has no members to list`() {
    let relationships = DocumentInfo.sections(for: rich, in: nil).first { $0.title == "Relationships" }
    #expect(relationships?.rows.contains { $0.label.hasPrefix("Part of") } == false)
  }
}
