import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Document actions")
struct DocumentActionsTests {
  private let id = DocumentID(series: .rfc, number: 9110)

  private func metadata(title: String) -> RFCMetadata {
    Fixtures.metadata(id.number, title: title, year: 2022, month: 6)
  }

  // MARK: - The bookmark's title

  @Test func `the index names the bookmark`() {
    let title = DocumentActions.bookmarkTitle(
      metadata: metadata(title: "HTTP Semantics"),
      documentTitle: "Something else entirely",
      id: id
    )
    #expect(title == "HTTP Semantics")
  }

  /// The divergence this whole type exists to settle: macOS had no document to
  /// fall back to and went straight to `RFC 9110`, so the same bookmark read
  /// differently depending on which toolbar made it.
  @Test func `the document names it when the index does not`() {
    let title = DocumentActions.bookmarkTitle(
      metadata: nil, documentTitle: "HTTP Semantics", id: id)
    #expect(title == "HTTP Semantics")
  }

  @Test func `the number names it when nothing else can`() {
    #expect(DocumentActions.bookmarkTitle(metadata: nil, documentTitle: nil, id: id) == "RFC 9110")
  }

  // MARK: - The reader's subtitle

  /// One rule for both platforms: macOS used the index alone, iOS fell back to
  /// the document, so an RFC missing from the index was named on one and not on
  /// the other.
  @Test func `the subtitle follows the bookmarks sources`() {
    #expect(
      DocumentActions.subtitle(metadata: metadata(title: "HTTP Semantics"), documentTitle: "Other")
        == "HTTP Semantics")
    #expect(
      DocumentActions.subtitle(metadata: nil, documentTitle: "HTTP Semantics") == "HTTP Semantics")
  }

  /// The designation is the title above it, so the subtitle has no last resort.
  @Test func `the subtitle is empty rather than the number again`() {
    #expect(DocumentActions.subtitle(metadata: nil, documentTitle: nil) == nil)
  }

  // MARK: - The citation

  @Test func `a citation carries the section being read`() {
    let cited = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: "4.2", style: .full)
    #expect(cited.contains("4.2"))
  }

  /// BibTeX has no field that says "and I mean §4.2", so a section passed through
  /// would land in the title or be dropped by whoever renders the entry.
  @Test func `bibtex cites the whole document even while a section is being read`() {
    let withSection = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: "4.2", style: .bibtex)
    let without = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: nil, style: .bibtex)
    #expect(withSection == without)
  }

  @Test func `every other style keeps the section`() {
    for style in CitationStyle.allCases where style != .bibtex {
      let withSection = DocumentActions.citation(
        metadata(title: "HTTP Semantics"), section: "4.2", style: style)
      let without = DocumentActions.citation(
        metadata(title: "HTTP Semantics"), section: nil, style: style)
      #expect(withSection != without, "\(style) dropped the section")
    }
  }

  // MARK: - The section link

  @Test func `the section link points at the place being read`() {
    let link = DocumentActions.sectionLink(id: id, section: "4.2")
    #expect(link == RFCLink(id: id, section: "4.2").webURL.absoluteString)
    #expect(link.contains("section-4.2"))
  }

  /// Read inside an appendix numbered like a section, the place being read is the
  /// appendix's, not section 1's: the reader passes the section's `place` (#429).
  @Test func `a numbered appendix is cited and linked as an appendix`() {
    let appendix = Section(
      anchor: "appendix-1", number: "1", title: "State Tables", isAppendix: true)
    let citation = DocumentActions.citation(
      metadata(title: "HTTP Semantics"), section: appendix.place, style: .short)
    #expect(citation == "RFC 9110, Appendix 1")
    let link = DocumentActions.sectionLink(id: id, section: appendix.place)
    #expect(link == "https://www.rfc-editor.org/rfc/rfc9110#appendix-1")
  }

  @Test func `the link points at the document when no section is known`() {
    let link = DocumentActions.sectionLink(id: id, section: nil)
    #expect(!link.contains("section"))
  }

  /// The Bookmark button keeps its label, and says whether the document is
  /// bookmarked in words VoiceOver reads, which the glyph alone never did (#278).
  @Test func `the bookmark state is said in words`() {
    #expect(DocumentActions.bookmarkState(isBookmarked: true, locale: .english) == "Bookmarked")
    #expect(
      DocumentActions.bookmarkState(isBookmarked: false, locale: .english) == "Not bookmarked")
  }

  /// The ⌘D command says what it will do, on the Mac's Edit menu and the iPad's
  /// alike, where the button beside it says what is (#278).
  @Test func `the bookmark command is titled by what it will do`() {
    #expect(DocumentActions.bookmarkCommand(isBookmarked: false, locale: .english) == "Bookmark")
    #expect(
      DocumentActions.bookmarkCommand(isBookmarked: true, locale: .english) == "Remove Bookmark")
  }

  @Test func `the Keep Offline command is titled by what it will do`() {
    #expect(DocumentActions.keepOfflineCommand(isKept: false, locale: .english) == "Keep Offline")
    #expect(
      DocumentActions.keepOfflineCommand(isKept: true, locale: .english) == "Stop Keeping Offline")
  }
}
