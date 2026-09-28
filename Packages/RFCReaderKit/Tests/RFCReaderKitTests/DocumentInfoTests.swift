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

  /// The strip under the header: what someone deciding whether this is the right
  /// document looks for first, each a short value over its caption.
  @Test func `the key facts are when, how long, from whom and which group`() {
    #expect(
      info(rich).facts == [
        DocumentInfo.Fact(value: "2022", label: "Published"),
        DocumentInfo.Fact(value: "194", label: "Pages"),
        DocumentInfo.Fact(value: "IETF", label: "Stream"),
        DocumentInfo.Fact(value: "httpbis", label: "Working Group"),
      ])
  }

  /// A fact is a word or two in a quarter of a narrow panel.
  @Test func `the independent stream is short enough for the strip`() {
    var metadata = bare
    metadata.stream = .independent
    #expect(info(metadata).facts.contains(DocumentInfo.Fact(value: "Independent", label: "Stream")))
  }

  @Test func `the sections come in a fixed order`() {
    #expect(info(rich).sections.map(\.title) == ["Authors", "Relationships", "Links", "Details"])
  }

  @Test func `authors are listed by name, an editor marked as one`() {
    #expect(
      section("Authors", of: rich)?.rows
        == [
          DocumentInfo.Row(label: "", value: .text("R. Fielding, Ed.")),
          DocumentInfo.Row(label: "", value: .text("M. Nottingham")),
        ])
  }

  /// The legacy parser records an editor as "Editor" and the index as whatever it
  /// says; both mean the same, and an unknown role is not promoted to one.
  @Test func `an editor is recognised however the role is spelled`() {
    var metadata = bare
    metadata.authors = [
      Author(name: "A. Author", role: "Ed."),
      Author(name: "B. Author", role: "Editor"),
      Author(name: "C. Author", role: "contributor"),
    ]
    #expect(
      section("Authors", of: metadata)?.rows.map(\.value)
        == [.text("A. Author, Ed."), .text("B. Author, Ed."), .text("C. Author")])
  }

  /// The status it was published with only where it differs from the current one:
  /// RFC 9110 went out a Proposed Standard and is an Internet Standard now.
  @Test func `the details hold what the header and the strip leave out`() {
    let details = section("Details", of: rich)
    #expect(
      value("Published as", in: details) == .text(PublicationStatus.proposedStandard.displayName))
    #expect(value("Published", in: details) == .text("June 2022"))
    #expect(value("Area", in: details) == .text("art"))
    #expect(value("Keywords", in: details) == .text("HTTP, semantics"))
    #expect(value("Formats", in: details) == .text("TXT, HTML, XML, PDF"))

    var unchanged = rich
    unchanged.publicationStatus = unchanged.currentStatus
    #expect(value("Published as", in: section("Details", of: unchanged)) == nil)
  }

  /// The index fills the field for a document from no group with a sentence rather
  /// than leaving it empty, and that is not a group's name.
  @Test func `a document from no working group has no working group fact`() {
    var metadata = rich
    metadata.workingGroup = "NON WORKING GROUP"
    #expect(!info(metadata).facts.contains { $0.label == "Working Group" })
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

  /// A legacy document knows little, and its panel is short rather than full of
  /// dashes: an empty field has no fact or row, and a section with no rows is not
  /// shown.
  @Test func `what is not known is not shown`() {
    let info = info(bare)
    #expect(info.facts.map(\.label) == ["Published", "Stream"])
    #expect(info.sections.map(\.title) == ["Links", "Details"])
    let rows = info.sections.flatMap(\.rows).map(\.label)
    for absent in ["Keywords", "Formats", "Area", "DOI", "Errata", "Published as"] {
      #expect(!rows.contains(absent), "\(absent) shown for a document that has none")
    }
  }

  @Test func `without an index a series has no members to list`() {
    let relationships = DocumentInfo(rich, in: nil).sections.first { $0.title == "Relationships" }
    #expect(relationships?.rows.contains { $0.label.hasPrefix("Part of") } == false)
  }
}

/// The inspector's two panes share one slot, as Pages' Format and Document do: each
/// has its own toolbar button, and the buttons swap the slot's content (#25).
@Suite("Inspector pane")
struct InspectorPaneTests {
  @Test func `a button opens a closed inspector on its own pane`() {
    let result = InspectorPane.pressing(.info, isOpen: false, showing: .navigation)
    #expect(result.isOpen)
    #expect(result.pane == .info)
  }

  @Test func `the other button swaps the pane and leaves it open`() {
    let result = InspectorPane.pressing(.info, isOpen: true, showing: .navigation)
    #expect(result.isOpen)
    #expect(result.pane == .info)
  }

  /// And keeps the pane, so the next open shows what was last there.
  @Test func `a button closes the inspector showing its own pane`() {
    let result = InspectorPane.pressing(.navigation, isOpen: true, showing: .navigation)
    #expect(!result.isOpen)
    #expect(result.pane == .navigation)
  }
}
