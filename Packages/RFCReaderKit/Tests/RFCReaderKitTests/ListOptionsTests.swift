import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The iOS list's view options (#348).
@Suite("List options")
struct ListOptionsTests {
  private let rows = [9110, 7231, 2616].map { number in
    RFCMetadata(
      id: .rfc(number), title: "Title", date: PublicationDate(year: 2020),
      obsoletedBy: number == 9110 ? [] : [.rfc(9110)])
  }

  @Test func `the defaults change nothing`() {
    let listed = ListOptions().apply(to: rows, filter: .all, query: "")

    #expect(listed.map(\.number) == [9110, 7231, 2616])
  }

  @Test func `oldest first reverses a list in order of publication`() {
    let options = ListOptions(order: .oldestFirst)

    #expect(options.apply(to: rows, filter: .all, query: "").map(\.number) == [2616, 7231, 9110])
  }

  /// Recently Read is in reading order and a search in order of relevance:
  /// reversing either would not put the oldest first.
  @Test func `the order leaves other orders alone`() {
    let options = ListOptions(order: .oldestFirst)

    #expect(
      options.apply(to: rows, filter: .recent, query: "").map(\.number) == [9110, 7231, 2616])
    #expect(
      options.apply(to: rows, filter: .all, query: "http").map(\.number) == [9110, 7231, 2616])
  }

  @Test func `hiding the obsolete keeps what is current`() {
    let options = ListOptions(showsObsolete: false)

    #expect(options.apply(to: rows, filter: .all, query: "").map(\.number) == [9110])
    #expect(options.apply(to: rows, filter: .bookmarks, query: "http").map(\.number) == [9110])
  }

  @Test func `the order applies only where it can`() {
    #expect(ListOptions.canReorder(.all, query: ""))
    #expect(!ListOptions.canReorder(.recent, query: ""))
    #expect(!ListOptions.canReorder(.all, query: "http"))
  }
}
