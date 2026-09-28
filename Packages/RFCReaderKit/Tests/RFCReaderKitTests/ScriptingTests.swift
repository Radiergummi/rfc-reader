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
  @Test func `every title names its own collection`() {
    let filters: [LibraryFilter] = [
      .all, .recent, .bookmarks, .downloaded, .standards, .bestCurrentPractice,
      .stream(.ietf), .stream(.independent), .workingGroup("httpbis"),
      .series(DocumentID(series: .bcp, number: 14)),
    ]
    for filter in filters {
      #expect(self.filter(filter.title) == filter, "\(filter.title)")
    }
  }

  private let http3 = CollectionSnapshot.Entry(
    id: UUID(), name: "HTTP/3", color: .blue, members: [])
  private let secondHTTP3 = CollectionSnapshot.Entry(
    id: UUID(), name: "HTTP/3", color: .green, members: [])
  private let shadowing = CollectionSnapshot.Entry(
    id: UUID(), name: "Bookmarks", color: .red, members: [])

  /// Among collections of one name, the first in the sidebar.
  @Test func `a user collection is named as the sidebar names it`() {
    let filter = LibraryFilter(
      scriptName: "http/3", workingGroups: groups, collections: [http3, secondHTTP3])
    #expect(filter == .collection(http3.id))
  }

  /// No existing script changes meaning because a collection took a name.
  @Test func `built-in names win over a collection's`() {
    let filter = LibraryFilter(
      scriptName: "Bookmarks", workingGroups: groups, collections: [shadowing])
    #expect(filter == .bookmarks)
  }

  @Test func `case does not matter`() {
    #expect(filter("bookmarks") == .bookmarks)
    #expect(filter("ALL RFCS") == .all)
    #expect(filter("  Recently Read ") == .recent)
  }

  /// Spelled the way the index spells it, because that is what rows compare against.
  @Test func `a working group comes back as the index spells it`() {
    #expect(filter("HTTPBIS") == .workingGroup("httpbis"))
  }

  @Test func `a series is named by its document`() {
    #expect(filter("BCP 14") == .series(DocumentID(series: .bcp, number: 14)))
    #expect(filter("std 97") == .series(DocumentID(series: .std, number: 97)))
  }

  /// An RFC is a document, not a collection, and an unknown name is an error to
  /// the script rather than an empty list.
  @Test func `anything else is no collection`() {
    #expect(filter("RFC 9110") == nil)
    #expect(filter("9110") == nil)
    #expect(filter("tsvwg") == nil, "not a group this index knows")
    #expect(filter("") == nil)
  }
}

@Suite("Document references")
struct DocumentReferenceTests {
  @Test func `a number is an RFC`() {
    #expect(DocumentReference.link(from: "9110") == RFCLink(id: .rfc(9110)))
  }

  @Test func `a name is its document`() {
    #expect(DocumentReference.link(from: "RFC 9110") == RFCLink(id: .rfc(9110)))
    #expect(
      DocumentReference.link(from: "bcp 14") == RFCLink(id: DocumentID(series: .bcp, number: 14)))
  }

  @Test func `a link is followed`() {
    let link = DocumentReference.link(from: "rfc://9110#section-4.2")
    #expect(link == RFCLink(id: .rfc(9110), section: "4.2"))
  }

  /// The section asked for outright is the more specific request.
  @Test func `a given section wins over the links`() {
    #expect(
      DocumentReference.link(from: "9110", section: "3") == RFCLink(id: .rfc(9110), section: "3"))
    #expect(
      DocumentReference.link(from: "rfc://9110#section-4.2", section: "5")
        == RFCLink(id: .rfc(9110), section: "5"))
    #expect(DocumentReference.link(from: "9110", section: "") == RFCLink(id: .rfc(9110)))
  }

  @Test func `anything else is nothing`() {
    #expect(DocumentReference.link(from: "hypertext") == nil)
    #expect(DocumentReference.link(from: "") == nil)
  }
}
