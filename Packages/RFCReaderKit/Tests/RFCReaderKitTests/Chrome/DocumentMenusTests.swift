import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a document's Cite, More and Add to Collection menus hold.
@Suite("Document menus")
struct DocumentMenusTests {
  private func titles(_ sections: DocumentMenus.Sections) -> [[String]] {
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
