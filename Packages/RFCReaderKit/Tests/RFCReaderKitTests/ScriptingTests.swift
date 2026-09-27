import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Scripting: collection names")
struct LibraryFilterScriptNameTests {
  private let groups: Set<String> = ["httpbis", "quic"]

  private func filter(_ name: String) -> LibraryFilter? {
    LibraryFilter(scriptName: name, workingGroups: groups)
  }

  /// What a script reads back is what it can set: every title round-trips.
  @Test func everyTitleNamesItsOwnCollection() {
    let filters: [LibraryFilter] = [
      .all, .recent, .bookmarks, .downloaded, .standards, .bestCurrentPractice,
      .stream(.ietf), .stream(.independent), .workingGroup("httpbis"),
      .series(DocumentID(series: .bcp, number: 14)),
    ]
    for filter in filters {
      #expect(self.filter(filter.title) == filter, "\(filter.title)")
    }
  }

  @Test func caseDoesNotMatter() {
    #expect(filter("bookmarks") == .bookmarks)
    #expect(filter("ALL RFCS") == .all)
    #expect(filter("  Recently Read ") == .recent)
  }

  /// Spelled the way the index spells it, because that is what rows compare against.
  @Test func aWorkingGroupComesBackAsTheIndexSpellsIt() {
    #expect(filter("HTTPBIS") == .workingGroup("httpbis"))
  }

  @Test func aSeriesIsNamedByItsDocument() {
    #expect(filter("BCP 14") == .series(DocumentID(series: .bcp, number: 14)))
    #expect(filter("std 97") == .series(DocumentID(series: .std, number: 97)))
  }

  /// An RFC is a document, not a collection, and an unknown name is an error to
  /// the script rather than an empty list.
  @Test func anythingElseIsNoCollection() {
    #expect(filter("RFC 9110") == nil)
    #expect(filter("9110") == nil)
    #expect(filter("tsvwg") == nil, "not a group this index knows")
    #expect(filter("") == nil)
  }
}

@Suite("Document references")
struct DocumentReferenceTests {
  @Test func aNumberIsAnRFC() {
    #expect(DocumentReference.link(from: "9110") == RFCLink(id: .rfc(9110)))
  }

  @Test func aNameIsItsDocument() {
    #expect(DocumentReference.link(from: "RFC 9110") == RFCLink(id: .rfc(9110)))
    #expect(
      DocumentReference.link(from: "bcp 14") == RFCLink(id: DocumentID(series: .bcp, number: 14)))
  }

  @Test func aLinkIsFollowed() {
    let link = DocumentReference.link(from: "rfc://9110#section-4.2")
    #expect(link == RFCLink(id: .rfc(9110), section: "4.2"))
  }

  /// The section asked for outright is the more specific request.
  @Test func aGivenSectionWinsOverTheLinks() {
    #expect(
      DocumentReference.link(from: "9110", section: "3") == RFCLink(id: .rfc(9110), section: "3"))
    #expect(
      DocumentReference.link(from: "rfc://9110#section-4.2", section: "5")
        == RFCLink(id: .rfc(9110), section: "5"))
    #expect(DocumentReference.link(from: "9110", section: "") == RFCLink(id: .rfc(9110)))
  }

  @Test func anythingElseIsNothing() {
    #expect(DocumentReference.link(from: "hypertext") == nil)
    #expect(DocumentReference.link(from: "") == nil)
  }
}
