import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a document's Cite, More and Add to Collection menus hold.
@Suite("Document menus")
struct DocumentMenusTests {
  private func titles<Action>(_ sections: DocumentMenus.Sections<Action>) -> [[String]] {
    sections.map { $0.map(\.title) }
  }

  private let errata = URL(string: "https://www.rfc-editor.org/errata/rfc9110")!
  private let draft = URL(string: "https://datatracker.ietf.org/doc/draft-ietf-httpbis-semantics")!

  @Test func `cite offers every style, then the section link on its own`() {
    let cite = DocumentMenus.cite()
    #expect(cite.count == 2)
    #expect(cite[0].map(\.action) == CitationStyle.allCases.map { .copyCitation($0) })
    #expect(titles(cite)[1] == ["Copy Link to Current Section"])
  }

  @Test func `more has the original text apart from the pages elsewhere`() {
    let more = DocumentMenus.more(showsOriginal: false, errata: nil, precedingDraft: nil)
    #expect(titles(more) == [["Original Text"], ["Open on rfc-editor.org", "Datatracker"]])
  }

  @Test func `errata and the preceding draft appear only where the document has them`() {
    let more = DocumentMenus.more(showsOriginal: false, errata: errata, precedingDraft: draft)
    #expect(
      titles(more)[1] == ["Open on rfc-editor.org", "Errata", "Datatracker", "Preceding Draft"])
    #expect(more[1][1].action == .openErrata(errata))
    #expect(more[1][3].action == .openPrecedingDraft(draft))
  }

  @Test func `original text is a toggle showing whether it is on`() {
    #expect(
      DocumentMenus.more(showsOriginal: true, errata: nil, precedingDraft: nil)[0][0].isOn == true)
    #expect(
      DocumentMenus.more(showsOriginal: false, errata: nil, precedingDraft: nil)[0][0].isOn == false
    )
  }

  @Test func `with no collections, add to collection offers only a new one`() {
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: CollectionSnapshot(collections: []))
    #expect(titles(menu) == [["New Collection…"]])
  }

  /// A window with no document still opens the bookmark item's menu, which AppKit
  /// never validates: it offers a new collection rather than nothing.
  @Test func `with no document, add to collection offers only a new one`() {
    let snapshot = CollectionSnapshot(collections: [
      .init(id: UUID(), name: "HTTP", color: .blue, members: [.rfc(9110)])
    ])
    let menu = DocumentMenus.addToCollection(nil, in: snapshot)
    #expect(titles(menu) == [["New Collection…"]])
  }

  @Test func `every collection is listed, checked where the document is in it`() {
    let http = UUID()
    let dns = UUID()
    let snapshot = CollectionSnapshot(collections: [
      .init(id: http, name: "HTTP", color: .blue, members: [.rfc(9110)]),
      .init(id: dns, name: "DNS", color: .green, members: [.rfc(1035)]),
    ])
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: snapshot)
    #expect(titles(menu) == [["HTTP", "DNS"], ["New Collection…"]])
    #expect(menu[0].map(\.isOn) == [true, false])
    #expect(menu[0].map(\.action) == [.toggleCollection(http), .toggleCollection(dns)])
  }

  /// Each collection is shown as the sidebar shows it, as a folder in its color, so
  /// the menu and the sidebar name the same collection the same way.
  @Test func `a collection's item is its folder in its color`() {
    let snapshot = CollectionSnapshot(collections: [
      .init(id: UUID(), name: "HTTP", color: .blue, members: []),
      .init(id: UUID(), name: "DNS", color: .green, members: []),
    ])
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: snapshot)
    #expect(menu[0].map(\.icon) == [.init("folder", color: .blue), .init("folder", color: .green)])
    #expect(menu[1].map(\.icon) == [nil])
  }
}

/// What each of Cite's and More's actions does, which both platforms carry out the
/// same way (#600).
@Suite("Document menu effects")
struct DocumentMenuEffectsTests {
  private let metadata = Fixtures.metadata(9110, title: "HTTP Semantics", year: 2022)
  private let errata = URL(string: "https://www.rfc-editor.org/errata/rfc9110")!
  private let precedingDraft = URL(
    string: "https://datatracker.ietf.org/doc/draft-ietf-httpbis-semantics-19")!

  private func effect(_ action: DocumentMenus.Action) -> DocumentMenus.Effect? {
    action.effect(for: .rfc(9110), metadata: metadata, section: "4.2")
  }

  @Test(arguments: CitationStyle.allCases)
  func `a citation copies the citation of the section being read`(style: CitationStyle) {
    #expect(
      effect(.copyCitation(style))
        == .copy(DocumentActions.citation(metadata, section: "4.2", style: style)))
  }

  @Test func `a citation without the document's metadata does nothing`() {
    #expect(
      DocumentMenus.Action.copyCitation(.short)
        .effect(for: .rfc(9110), metadata: nil, section: nil) == nil)
  }

  @Test func `the section link copies the link to where the reader is`() {
    #expect(
      effect(.copySectionLink)
        == .copy(DocumentActions.sectionLink(id: .rfc(9110), section: "4.2")))
  }

  @Test func `the pages elsewhere open`() {
    #expect(effect(.openInfoPage) == .open(RFCEditorEndpoints.infoPage(.rfc(9110))))
    #expect(effect(.openDatatracker) == .open(RFCEditorEndpoints.datatracker(.rfc(9110))))
    #expect(effect(.openErrata(errata)) == .open(errata))
    #expect(effect(.openPrecedingDraft(precedingDraft)) == .open(precedingDraft))
  }

  @Test(arguments: [
    DocumentMenus.Action.copySectionLink, .toggleOriginalText, .openInfoPage, .openDatatracker,
  ])
  func `only a citation needs the document's metadata`(action: DocumentMenus.Action) {
    #expect(action.effect(for: .rfc(9110), metadata: nil, section: nil) != nil)
  }

  @Test func `original text toggles`() {
    #expect(effect(.toggleOriginalText) == .toggleOriginalText)
  }
}
