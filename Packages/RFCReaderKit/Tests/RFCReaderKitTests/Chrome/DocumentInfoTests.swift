import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The Info inspector (#25): everything the index knows about a document that is
/// not its prose — a header, a strip of key facts, and sections — with nothing
/// shown for what it does not know.
@Suite("Document info")
struct DocumentInfoTests {
  private let rich = RFCMetadata(
    id: .rfc(9110),
    title: "HTTP Semantics",
    authors: [Author(name: "R. Fielding", role: .editor), Author(name: "M. Nottingham")],
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

  private let bare = RFCMetadata(
    id: .rfc(1149), title: "IP over Avian Carriers", date: PublicationDate(year: 1990, month: 4))

  private var index: RFCIndex {
    RFCIndex(
      rfcs: [rich, bare],
      series: [
        SeriesEntry(id: DocumentID(series: .std, number: 97), members: [.rfc(9110), .rfc(9111)])
      ])
  }

  private func info(_ metadata: RFCMetadata) -> DocumentInfo {
    DocumentInfo(metadata, in: index)
  }

  private func section(_ title: String, of metadata: RFCMetadata) -> DocumentInfo.Section? {
    info(metadata).sections.first { $0.title == title }
  }

  private func value(_ label: String, in section: DocumentInfo.Section?) -> DocumentInfo.Value? {
    section?.rows.first { $0.label == label }?.value
  }

  @Test func `the header names the document and its standing`() {
    let info = info(rich)
    #expect(info.number == "RFC 9110")
    #expect(info.title == "HTTP Semantics")
    #expect(info.status == .internetStandard)
    #expect(!info.isObsolete)
  }

  /// The header says what the status means, not only its name: "Internet Standard"
  /// is jargon to most readers, and "STD" more so.
  @Test(arguments: PublicationStatus.allCases.filter { $0 != .unknown })
  func `every status is explained in a sentence`(status: PublicationStatus) {
    var metadata = bare
    metadata.currentStatus = status
    let summary = info(metadata).statusSummary
    #expect(summary?.isEmpty == false)
    #expect(summary?.hasSuffix(".") == true)
  }

  @Test func `an unknown status is not explained`() {
    #expect(info(bare).statusSummary == nil)
  }

  /// Said beside the status, from the same model, so the header has two boxes of one
  /// kind rather than one from the model and one from the view.
  @Test func `an obsolete document says so in a sentence, and a current one does not`() {
    var obsolete = bare
    obsolete.obsoletedBy = [.rfc(9999)]
    #expect(info(obsolete).obsoleteSummary?.isEmpty == false)
    #expect(info(rich).obsoleteSummary == nil)
  }

  /// Links and files are a card of rows; the rest a list of captioned values. Said by
  /// the section, not guessed by the view from its rows.
  @Test func `a section says how it is set`() {
    #expect(info(rich).sections.map(\.style) == [.list, .list, .card, .card, .list])
  }

  /// The strip under the header: what someone deciding whether this is the right
  /// document looks for first, each a short value over its caption.
  @Test func `the key facts are when, how long, from whom and which group`() {
    #expect(
      info(rich).facts == [
        DocumentInfo.Fact(value: "2022", label: "Published"),
        DocumentInfo.Fact(value: "194", label: "Pages"),
        DocumentInfo.Fact(value: "IETF", label: "Stream"),
        DocumentInfo.Fact(value: "httpbis", label: "Group"),
      ])
  }

  /// A fact is a word or two in a quarter of a narrow panel.
  @Test func `the independent stream is short enough for the strip`() {
    var metadata = bare
    metadata.stream = .independent
    #expect(info(metadata).facts.contains(DocumentInfo.Fact(value: "Independent", label: "Stream")))
  }

  @Test func `the sections come in a fixed order`() {
    #expect(
      info(rich).sections.map(\.title)
        == ["Authors", "Relationships", "Links", "Formats", "Details"])
  }

  /// One row of people, drawn as the header's chips (#19).
  @Test func `the authors are one row of people`() {
    #expect(
      section("Authors", of: rich)?.rows == [
        DocumentInfo.Row(label: "", value: .authors(rich.authors))
      ])
  }

  /// The document's own authors carry the contact details a chip opens, which the
  /// index never has; the index's names stand in until the document is here, as
  /// they do in the header.
  @Test func `the document's own authors stand in for the index's`() {
    let own = [Author(name: "Roy T. Fielding", role: .editor)]
    let info = DocumentInfo(rich, authors: own, in: index)
    #expect(info.sections.first?.rows.first?.value == .authors(own))
    let unknown = DocumentInfo(rich, authors: [], in: index)
    #expect(unknown.sections.first?.rows.first?.value == .authors(rich.authors))
  }

  /// The status it was published with only where it differs from the current one:
  /// RFC 9110 went out a Proposed Standard and is an Internet Standard now.
  @Test func `the details hold what the header and the strip leave out`() {
    let details = section("Details", of: rich)
    #expect(
      value("Published as", in: details) == .text(PublicationStatus.proposedStandard.displayName))
    #expect(value("Published", in: details) == .text("June 2022"))
    #expect(value("Area", in: details) == .text("Applications and Real-Time"))
    #expect(value("Keywords", in: details) == .keywords(["HTTP", "semantics"]))
    #expect(value("Formats", in: details) == nil)

    var unchanged = rich
    unchanged.publicationStatus = unchanged.currentStatus
    #expect(value("Published as", in: section("Details", of: unchanged)) == nil)
  }

  /// The index fills the field for a document from no group with a sentence rather
  /// than leaving it empty, and that is not a group's name.
  @Test func `a document from no working group has no working group fact`() {
    var metadata = rich
    metadata.workingGroup = "NON WORKING GROUP"
    #expect(!info(metadata).facts.contains { $0.label == "Group" })
  }

  /// A series member links to the others, not to itself.
  @Test func `relationships are documents, and a series lists its other members`() {
    let relationships = section("Relationships", of: rich)
    #expect(value("Obsoletes", in: relationships) == .documents([.rfc(2818), .rfc(7230)]))
    #expect(value("Updated by", in: relationships) == .documents([.rfc(9204)]))
    #expect(value("Part of STD 97", in: relationships) == .documents([.rfc(9111)]))
    #expect(value("Obsoleted by", in: relationships) == nil)
  }

  /// Each a row with an icon, as a Settings or App Store link is.
  @Test func `pages elsewhere are links with an icon, the DOI one to copy`() {
    let links = section("Links", of: rich)
    #expect(links?.rows.map(\.label) == ["Errata", "RFC Editor", "Datatracker", "DOI"])
    #expect(links?.rows.allSatisfy { $0.symbol != nil } == true)
    #expect(value("DOI", in: links) == .copyable("10.17487/RFC9110"))
    #expect(
      value("Errata", in: links) == .link(URL(string: "https://www.rfc-editor.org/errata/rfc9110")!)
    )
    #expect(value("RFC Editor", in: links) == .link(RFCEditorEndpoints.infoPage(.rfc(9110))))
    #expect(value("Datatracker", in: links) == .link(RFCEditorEndpoints.datatracker(.rfc(9110))))
  }

  /// Set as the links are, each opening the file where the RFC Editor hosts it, or
  /// saving it with Option held.
  @Test func `each format is a file to open or save`() {
    let formats = section("Formats", of: rich)
    #expect(formats?.rows.map(\.label) == ["Plain Text", "HTML", "XML", "PDF"])
    #expect(formats?.rows.allSatisfy { $0.symbol != nil } == true)
    #expect(value("PDF", in: formats) == .file(.rfc(9110), .pdf))
  }

  /// A legacy document knows little, and its panel is short rather than full of
  /// dashes: an empty field has no fact or row, and a section with no rows is not
  /// shown.
  @Test func `what is not known is not shown`() {
    let info = info(bare)
    #expect(info.facts.map(\.label) == ["Published", "Stream"])
    #expect(info.sections.map(\.title) == ["Links", "Details"])
    let rows = info.sections.flatMap(\.rows).map(\.label)
    for absent in ["Keywords", "Area", "DOI", "Errata", "Published as"] {
      #expect(!rows.contains(absent), "\(absent) shown for a document that has none")
    }
  }

  @Test func `without an index a series has no members to list`() {
    let relationships = DocumentInfo(rich, in: nil).sections.first { $0.title == "Relationships" }
    #expect(relationships?.rows.contains { $0.label.hasPrefix("Part of") } == false)
  }
}

/// The IETF's areas, which the index records by their short codes (#25).
@Suite("Area names")
struct AreaNameTests {
  @Test(arguments: [
    ("art", "Applications and Real-Time"), ("wit", "Web and Internet Transport"),
    ("rtg", "Routing"), ("sec", "Security"), ("int", "Internet"),
    ("ops", "Operations and Management"), ("tsv", "Transport"), ("gen", "General"),
  ])
  func `a known area is written out`(code: String, name: String) {
    #expect(DocumentInfo.areaName(code) == name)
  }

  /// Codes are not always lower case in the index.
  @Test func `an area is found whatever its case`() {
    #expect(DocumentInfo.areaName("SEC") == "Security")
  }

  /// A retired or unknown area keeps its code, in capitals, as the IETF writes it.
  @Test func `an unknown area keeps its code`() {
    #expect(DocumentInfo.areaName("xyz") == "XYZ")
  }
}
