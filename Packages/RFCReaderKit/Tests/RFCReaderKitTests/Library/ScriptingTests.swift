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
      let title = filter.title(in: .empty, locale: .english)
      #expect(self.filter(title) == filter, "\(title)")
    }
  }

  /// A collection's title too: its name, which a script can set it by.
  @Test func `a collection's title names it`() {
    let title = LibraryFilter.collection(http3.id).title(
      in: CollectionSnapshot(collections: [http3]), locale: .english)
    #expect(title == "HTTP/3")
    #expect(
      LibraryFilter(scriptName: title, workingGroups: groups, collections: [http3])
        == .collection(http3.id))
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

/// What `collection "…"` names, for `delete` and every other command on the
/// application's collections (#987): only collections the reader made are elements,
/// so a built-in list's name is told apart, to be refused in words.
@Suite("Scripting: a collection element's name")
struct ScriptCollectionNameTests {
  private let groups: Set<String> = ["httpbis"]
  private let http3 = CollectionSnapshot.Entry(
    id: UUID(), name: "HTTP/3", color: .blue, members: [])
  private let secondHTTP3 = CollectionSnapshot.Entry(
    id: UUID(), name: "HTTP/3", color: .green, members: [])
  private let shadowing = CollectionSnapshot.Entry(
    id: UUID(), name: "Bookmarks", color: .red, members: [], query: "wg:quic")

  private func target(_ name: String) -> ScriptCollectionName? {
    ScriptCollectionName(
      name, collections: CollectionSnapshot(collections: [http3, secondHTTP3, shadowing]),
      workingGroups: groups)
  }

  @Test func `a collection is the first of its name in the sidebar, in any case`() {
    #expect(target("http/3") == .collection(http3.id))
  }

  /// Only the reader's collections are elements, so here a collection of a built-in
  /// list's name is the one named, where a window's collection would be the list.
  @Test func `a collection named like a built-in list is the collection`() {
    #expect(target("bookmarks") == .collection(shadowing.id))
  }

  @Test func `a built-in list, a stream, a series or a working group is built in`() {
    #expect(target("Recently Read") == .builtIn(.recent))
    #expect(target("IETF") == .builtIn(.stream(.ietf)))
    #expect(target("BCP 14") == .builtIn(.series(DocumentID(series: .bcp, number: 14))))
    #expect(target("HTTPBIS") == .builtIn(.workingGroup("httpbis")))
  }

  /// The app has to wait for its index to know the working groups.
  @Test func `a collection's name does not ask for the working groups`() {
    var asked = false
    let named = ScriptCollectionName(
      "HTTP/3", collections: CollectionSnapshot(collections: [http3]),
      workingGroups: {
        asked = true
        return groups
      }())
    #expect(named == .collection(http3.id))
    #expect(!asked)
  }

  @Test func `anything else names nothing`() {
    #expect(target("QUIC") == nil)
    #expect(target("") == nil)
  }
}
