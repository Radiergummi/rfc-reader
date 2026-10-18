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
    let cite = DocumentMenus.cite(locale: .english)
    #expect(cite.count == 2)
    #expect(cite[0].map(\.action) == CitationStyle.allCases.map { .copyCitation($0) })
    #expect(titles(cite)[1] == ["Copy Link to Current Section"])
  }

  @Test func `more has the original text apart from the pages elsewhere`() {
    let more = DocumentMenus.more(
      showsOriginal: false, showsTranslation: false, errata: nil, precedingDraft: nil,
      offersTranslation: true,
      locale: .english)
    #expect(
      titles(more) == [["Original Text", "Translate"], ["Open on rfc-editor.org", "Datatracker"]])
  }

  @Test func `errata and the preceding draft appear only where the document has them`() {
    let more = DocumentMenus.more(
      showsOriginal: false, showsTranslation: false, errata: errata, precedingDraft: draft,
      offersTranslation: true,
      locale: .english)
    #expect(
      titles(more)[1] == ["Open on rfc-editor.org", "Errata", "Datatracker", "Preceding Draft"])
    #expect(more[1][1].action == .openErrata(errata))
    #expect(more[1][3].action == .openPrecedingDraft(draft))
  }

  @Test func `original text is a toggle showing whether it is on`() {
    #expect(
      DocumentMenus.more(
        showsOriginal: true, showsTranslation: false, errata: nil, precedingDraft: nil,
        offersTranslation: true,
        locale: .english)[
          0][0].isOn == true)
    #expect(
      DocumentMenus.more(
        showsOriginal: false, showsTranslation: false, errata: nil, precedingDraft: nil,
        offersTranslation: true,
        locale: .english)[
          0][0].isOn == false
    )
  }

  /// The translation is the reader's text in another language (#749), not a page
  /// elsewhere, so it sits beside the original text.
  @Test func `translate is a toggle beside the original text`() {
    let shown = DocumentMenus.more(
      showsOriginal: false, showsTranslation: true, errata: nil, precedingDraft: nil,
      offersTranslation: true,
      locale: .english)
    #expect(shown[0][1].action == .toggleTranslation)
    #expect(shown[0][1].isOn == true)
    let hidden = DocumentMenus.more(
      showsOriginal: false, showsTranslation: false, errata: nil, precedingDraft: nil,
      offersTranslation: true,
      locale: .english)
    #expect(hidden[0][1].isOn == false)
    #expect(
      DocumentMenus.Action.toggleTranslation.effect(for: .rfc(9110), citing: nil, section: nil)
        == .toggleTranslation)
  }

  @Test func `a reader of English alone is not offered a translation`() {
    let more = DocumentMenus.more(
      showsOriginal: false, showsTranslation: false, errata: nil, precedingDraft: nil,
      offersTranslation: false,
      locale: .english)
    #expect(titles(more)[0] == ["Original Text"])
  }

  @Test func `with no collections, add to collection offers only a new one`() {
    let menu = DocumentMenus.addToCollection(
      .rfc(9110), in: CollectionSnapshot(collections: []), locale: .english)
    #expect(titles(menu) == [["New Collection…"]])
  }

  /// A window with no document still opens the bookmark item's menu, which AppKit
  /// never validates: it offers a new collection rather than nothing.
  @Test func `with no document, add to collection offers only a new one`() {
    let snapshot = CollectionSnapshot(collections: [
      .init(id: UUID(), name: "HTTP", color: .blue, members: [.rfc(9110)])
    ])
    let menu = DocumentMenus.addToCollection(nil, in: snapshot, locale: .english)
    #expect(titles(menu) == [["New Collection…"]])
  }

  @Test func `every collection is listed, checked where the document is in it`() {
    let http = UUID()
    let dns = UUID()
    let snapshot = CollectionSnapshot(collections: [
      .init(id: http, name: "HTTP", color: .blue, members: [.rfc(9110)]),
      .init(id: dns, name: "DNS", color: .green, members: [.rfc(1035)]),
    ])
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: snapshot, locale: .english)
    #expect(titles(menu) == [["HTTP", "DNS"], ["New Collection…"]])
    #expect(menu[0].map(\.isOn) == [true, false])
    #expect(menu[0].map(\.action) == [.toggleCollection(http), .toggleCollection(dns)])
  }

  /// Each collection is shown as the sidebar shows it, as a folder in its color, so
  /// the menu and the sidebar name the same collection the same way.
  /// A collection's name is the user's own text, never a key, even when it is a
  /// word the catalog has.
  @Test func `a collection's item is titled with its name as typed`() {
    let snapshot = CollectionSnapshot(collections: [
      .init(id: UUID(), name: "Errata", color: .blue, members: [])
    ])
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: snapshot, locale: .english)
    #expect(titles(menu)[0] == ["Errata"])
  }

  @Test func `cite names each style`() {
    #expect(
      titles(DocumentMenus.cite(locale: .english))[0]
        == ["Short", "Full Citation", "Markdown Link", "BibTeX", "URL", "xml2rfc Reference"])
  }

  @Test func `a collection's item is its folder in its color`() {
    let snapshot = CollectionSnapshot(collections: [
      .init(id: UUID(), name: "HTTP", color: .blue, members: []),
      .init(id: UUID(), name: "DNS", color: .green, members: []),
    ])
    let menu = DocumentMenus.addToCollection(.rfc(9110), in: snapshot, locale: .english)
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
    action.effect(for: .rfc(9110), citing: .rfc(metadata), section: "4.2")
  }

  @Test(arguments: CitationStyle.allCases)
  func `a citation copies the citation of the section being read`(style: CitationStyle) {
    #expect(
      effect(.copyCitation(style))
        == .copy(DocumentActions.citation(.rfc(metadata), section: "4.2", style: style), .citation))
  }

  /// Copy Citation is in the style Settings chose, linking the site it chose (#712).
  @Test func `copy citation is in the chosen style, on the chosen site`() {
    var settings = ReaderSettings()
    settings.citationStyle = .url
    settings.linkSite = .datatracker
    #expect(
      DocumentMenus.Action.copyPreferredCitation.effect(
        for: .rfc(9110), citing: .rfc(metadata), section: "4.2", settings: settings)
        == .copy("https://datatracker.ietf.org/doc/html/rfc9110#section-4.2", .citation))
    #expect(
      DocumentMenus.Action.copyPreferredCitation.effect(
        for: .rfc(9110), citing: .rfc(metadata), section: "4.2")
        == effect(.copyCitation(.markdown)))
  }

  /// A BCP is cited as the BCP, though the reader shows its first RFC's text: the
  /// section link is to the text shown (#656, #712).
  @Test func `a series is cited as itself and linked as the RFC shown`() {
    let bcp14 = DocumentID(series: .bcp, number: 14)
    let keywords = Fixtures.metadata(2119, title: "Key words", year: 1997)
    let cited = CitedDocument.series(bcp14, members: [keywords])
    #expect(
      DocumentMenus.Action.copyCitation(.short).effect(
        for: .rfc(2119), citing: cited, section: "2") == .copy("BCP 14, Section 2", .citation))
    #expect(
      DocumentMenus.Action.copySectionLink.effect(for: .rfc(2119), citing: cited, section: "2")
        == .copy("https://www.rfc-editor.org/rfc/rfc2119#section-2", .link))
  }

  @Test func `a citation without the document's metadata does nothing`() {
    #expect(
      DocumentMenus.Action.copyCitation(.short)
        .effect(for: .rfc(9110), citing: nil, section: nil) == nil)
  }

  @Test func `the section link copies the link to where the reader is`() {
    #expect(
      effect(.copySectionLink)
        == .copy(DocumentActions.sectionLink(id: .rfc(9110), section: "4.2"), .link))
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
    #expect(action.effect(for: .rfc(9110), citing: nil, section: nil) != nil)
  }

  @Test func `original text toggles`() {
    #expect(effect(.toggleOriginalText) == .toggleOriginalText)
  }
}

/// A library row's and a reference's menus (#761): one table each for the Mac and iOS.
@Suite("Row and reference menus")
struct RowAndReferenceMenusTests {

  /// The Mac opens a row in a tab or a window, then everything the library does
  /// with it, then Share.
  @Test func `a Mac row opens first, then the library's actions, then share`() {
    #expect(
      DocumentMenus.rowActions(
        isRFC: true, opensTabs: true, opensWindows: true, inCollection: false,
        hasCitationIndex: true)
        == [
          [.openInNewTab, .openInNewWindow],
          [.bookmark, .addToCollection, .readingPath, .keepOffline],
          [.share],
        ])
  }

  /// An iPhone opens no window, an iPad one, and neither a tab.
  @Test func `a device offers only the windows and tabs it can open`() {
    let iPhone = DocumentMenus.rowActions(
      isRFC: true, opensTabs: false, opensWindows: false, inCollection: false,
      hasCitationIndex: true)
    #expect(iPhone.first == [.bookmark, .addToCollection, .readingPath, .keepOffline])
    let iPad = DocumentMenus.rowActions(
      isRFC: true, opensTabs: false, opensWindows: true, inCollection: false,
      hasCitationIndex: true)
    #expect(iPad.first == [.openInNewWindow])
  }

  /// A series is bookmarked and opened as itself, but a collection holds RFCs, and
  /// a series is not shared (#321).
  @Test func `a series is bookmarked and opened, not collected or shared`() {
    #expect(
      DocumentMenus.rowActions(
        isRFC: false, opensTabs: true, opensWindows: true, inCollection: false,
        hasCitationIndex: true)
        == [[.openInNewTab, .openInNewWindow], [.bookmark]])
  }

  /// A reference opens where the device can, then copies its link or cites it.
  @Test func `a reference opens first, then copies its link or cites it`() {
    #expect(
      DocumentMenus.referenceActions(opensTabs: true, opensWindows: true)
        == [[.openInNewTab, .openInNewWindow], [.copyLink, .cite]])
    #expect(
      DocumentMenus.referenceActions(opensTabs: false, opensWindows: false) == [[.copyLink, .cite]])
    // Nothing to cite from without the index's entry.
    #expect(
      DocumentMenus.referenceActions(opensTabs: false, opensWindows: false, describes: false)
        == [[.copyLink]])
  }

  /// Without a citation index a reading path could only say there is none (#769).
  @Test func `a row offers no reading path without a citation index`() {
    #expect(
      DocumentMenus.rowActions(
        isRFC: true, opensTabs: false, opensWindows: false, inCollection: false,
        hasCitationIndex: false
      ).first == [.bookmark, .addToCollection, .keepOffline])
  }

  @Test func `a collection's row can be removed from it, last`() {
    let actions = DocumentMenus.rowActions(
      isRFC: true, opensTabs: true, opensWindows: true, inCollection: true,
      hasCitationIndex: true)
    #expect(actions.last == [.removeFromCollection])
  }
}
